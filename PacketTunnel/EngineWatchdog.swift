import Foundation
import OpenAdBlockCore
import os

private let logger = Logger(subsystem: "io.github.tothanggtvt.openadblock.mac", category: "watchdog")

/// Keeps the Mac's network alive when the core stops moving packets.
///
/// Every app packet goes through the core, so a core that stopped (its tunnel thread ends as
/// soon as any of its tasks fails) or stopped taking packets turns the tunnel into a black hole:
/// the system keeps routing into it and nothing comes back until the extension restarts. The
/// watchdog restarts the core in place; when that keeps failing it gives the tunnel up, and when
/// the core blocks the watchdog itself it ends the process, so macOS tears the tunnel down and
/// the Mac goes back to its normal, unfiltered network.
final class EngineWatchdog: @unchecked Sendable {
    /// How often the core is checked.
    private static let interval: DispatchTimeInterval = .seconds(5)
    /// Checks in a row in which the core refused every packet before it counts as stuck. Its
    /// queue fills up in a burst too, but drains again within a check.
    private static let stuckChecks = 2
    /// Refused packets a check needs before it can count as stuck (not a stray drop when idle).
    private static let stuckDrops = 32
    /// Restarts that fail in a row before the tunnel is given up.
    private static let maxFailedRestarts = 3
    /// A check (or restart) still running after this long means the core blocks its callers.
    private static let hangLimit: TimeInterval = 45

    private let engine: NativeEngine
    private let restartEngine: () -> Bool
    private let giveUp: () -> Void
    private let queue = DispatchQueue(label: "openadblock.watchdog")
    private let onQueue = DispatchSpecificKey<Void>()
    private let hangQueue = DispatchQueue(label: "openadblock.watchdog.hang")

    private let lock = NSLock()
    private var accepted = 0
    private var refused = 0
    private var busySince: Date?

    // Only touched on `queue`.
    private var timer: DispatchSourceTimer?
    private var hangTimer: DispatchSourceTimer?
    private var stuck = 0
    private var failedRestarts = 0

    /// `restart` stops and starts the core and says whether it runs again; `giveUp` stops the
    /// tunnel. Both run on the watchdog's queue.
    init(engine: NativeEngine, restart: @escaping () -> Bool, giveUp: @escaping () -> Void) {
        self.engine = engine
        restartEngine = restart
        self.giveUp = giveUp
        queue.setSpecific(key: onQueue, value: ())
    }

    /// Packets handed to the core since the last call: `accepted` it queued, `refused` it did not
    /// (not running, or its queue is full).
    func record(accepted: Int, refused: Int) {
        lock.withLock {
            self.accepted += accepted
            self.refused += refused
        }
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            _ = lock.withLock { (accepted, refused) = (0, 0) }
            stuck = 0
            failedRestarts = 0
            timer = makeTimer(on: queue, every: Self.interval) { [weak self] in self?.check() }
            hangTimer = makeTimer(on: hangQueue, every: .seconds(10)) { [weak self] in
                self?.checkHang()
            }
        }
    }

    /// Stops checking. Waits for a check or restart in progress, so the caller can stop the core
    /// without racing it.
    func stop() {
        // `giveUp` runs on the queue and may stop the tunnel, and so the watchdog, right away.
        if DispatchQueue.getSpecific(key: onQueue) != nil {
            cancelTimers()
        } else {
            queue.sync { cancelTimers() }
        }
    }

    private func cancelTimers() {
        timer?.cancel()
        timer = nil
        hangTimer?.cancel()
        hangTimer = nil
    }

    // MARK: Checks

    private func check() {
        guard timer != nil else { return }
        lock.withLock { busySince = Date() }
        defer { lock.withLock { busySince = nil } }

        let (accepted, refused) = lock.withLock {
            defer { (self.accepted, self.refused) = (0, 0) }
            return (self.accepted, self.refused)
        }
        if !engine.isRunning {
            restart(because: "stopped")
            return
        }
        failedRestarts = 0
        guard accepted == 0, refused >= Self.stuckDrops else {
            stuck = 0
            return
        }
        stuck += 1
        logger.error("Core refused \(refused) packets and took none (\(self.stuck)/\(Self.stuckChecks))")
        if stuck >= Self.stuckChecks {
            restart(because: "stopped taking packets")
        }
    }

    private func restart(because reason: String) {
        stuck = 0
        logger.error("Core \(reason, privacy: .public): restarting it")
        if restartEngine() {
            logger.notice("Core restarted")
            return
        }
        failedRestarts += 1
        logger.error("Core restart failed (\(self.failedRestarts)/\(Self.maxFailedRestarts))")
        guard failedRestarts >= Self.maxFailedRestarts else { return }
        logger.fault("Core does not start again: stopping the tunnel so the Mac keeps its network")
        cancelTimers()
        giveUp()
    }

    /// Runs on its own queue: a core that blocks (a deadlock) also blocks the check calling it.
    private func checkHang() {
        guard let since = lock.withLock({ busySince }),
            Date().timeIntervalSince(since) > Self.hangLimit
        else { return }
        // Stopping the tunnel cleanly would wait on the same blocked core. Ending the process
        // makes macOS remove the tunnel, and the Mac's own network takes over again.
        logger.fault("Core blocked for over \(Int(Self.hangLimit)) s: ending the extension")
        exit(EXIT_FAILURE)
    }

    private func makeTimer(
        on queue: DispatchQueue, every interval: DispatchTimeInterval,
        _ handler: @escaping () -> Void
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }
}
