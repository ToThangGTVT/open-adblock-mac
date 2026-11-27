import Darwin
import Foundation
import os

private let logger = Logger(subsystem: "io.github.tothanggtvt.openadblock.mac", category: "apps")

/// Names the app behind each tunnelled flow. Packets carry no owner, so the flow's local port is
/// looked up among every process's sockets (libproc, as `lsof` does; the extension runs as root).
///
/// The core gets a small stable id per app (`connectionOwner`) and reports it back as the event's
/// `uid`; `info(for:)` turns that id into what the log shows.
final class AppDirectory: @unchecked Sendable {
    static let shared = AppDirectory()

    private struct Socket {
        var remotePort: UInt16
        var pid: pid_t
    }

    /// Host-proxied browser flows get their id from the core: FNV-1a of the bundle id, high bit set
    /// (open-adblock-core crates/engine/src/app_proxy.rs).
    private static let proxied: [UInt32: AppInfo] = Dictionary(
        KnownBrowser.all.map { (fnv1a($0.id) | 0x8000_0000, AppInfo(name: $0.name, bundleID: $0.id, path: nil)) },
        uniquingKeysWith: { first, _ in first })

    private let lock = NSLock()
    /// (protocol, local port) → sockets, from the last scan.
    private var sockets: [UInt32: [Socket]] = [:]
    private var scannedAt: UInt64 = 0
    private var ids: [String: UInt32] = [:]
    private var apps: [UInt32: AppInfo] = [:]
    private var reportedScan = false
    private let ownPID = getpid()

    /// The id of the app owning the flow from `sourcePort` to `destinationPort`, or nil when unknown.
    /// DNS to the tunnel's resolver is left unattributed: on macOS it always comes from
    /// mDNSResponder on behalf of some app.
    func owner(protocol proto: UInt8, sourcePort: UInt16, destinationPort: UInt16) -> Int64? {
        guard proto == UInt8(IPPROTO_TCP) || proto == UInt8(IPPROTO_UDP), destinationPort != 53 else {
            return nil
        }
        let asked = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        lock.lock()
        defer { lock.unlock() }
        var pid = find(proto, sourcePort, destinationPort)
        // A new socket is not in the last scan. Concurrent misses share one rescan.
        if pid == nil, scannedAt < asked {
            scan()
            pid = find(proto, sourcePort, destinationPort)
        }
        guard let pid, let path = Self.path(of: pid) else { return nil }
        return Int64(id(for: path))
    }

    /// What the log shows for an event's `uid`.
    func info(for uid: UInt32) -> AppInfo? {
        if uid & 0x8000_0000 != 0 { return Self.proxied[uid] }
        return lock.withLock { apps[uid] }
    }

    // MARK: Sockets

    private static func key(_ proto: UInt8, _ port: UInt16) -> UInt32 { UInt32(proto) << 16 | UInt32(port) }

    private func find(_ proto: UInt8, _ sourcePort: UInt16, _ destinationPort: UInt16) -> pid_t? {
        let candidates = sockets[Self.key(proto, sourcePort)] ?? []
        // Unconnected UDP sockets have no remote port.
        return (candidates.first { $0.remotePort == destinationPort }
            ?? candidates.first { $0.remotePort == 0 })?.pid
    }

    private func scan() {
        var found: [UInt32: [Socket]] = [:]
        var visible = 0
        let count = proc_listallpids(nil, 0)
        var pids = [pid_t](repeating: 0, count: Int(max(count, 0)) + 64)
        let listed = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        for pid in pids.prefix(Int(max(listed, 0))) where pid > 0 && pid != ownPID {
            let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard size > 0 else { continue }
            visible += 1
            var fds = [proc_fdinfo](
                repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.stride + 16)
            let filled = fds.withUnsafeMutableBytes {
                proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
            }
            for fd in fds.prefix(Int(max(filled, 0)) / MemoryLayout<proc_fdinfo>.stride)
            where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                var info = socket_fdinfo()
                let read = proc_pidfdinfo(
                    pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
                guard read == Int32(MemoryLayout<socket_fdinfo>.size) else { continue }
                let family = info.psi.soi_family
                guard family == AF_INET || family == AF_INET6 else { continue }
                let inet = info.psi.soi_kind == Int32(SOCKINFO_TCP)
                    ? info.psi.soi_proto.pri_tcp.tcpsi_ini : info.psi.soi_proto.pri_in
                let proto = UInt8(truncatingIfNeeded: info.psi.soi_protocol)
                let local = UInt16(bigEndian: UInt16(truncatingIfNeeded: inet.insi_lport))
                let remote = UInt16(bigEndian: UInt16(truncatingIfNeeded: inet.insi_fport))
                guard local != 0 else { continue }
                found[Self.key(proto, local), default: []].append(Socket(remotePort: remote, pid: pid))
            }
        }
        sockets = found
        scannedAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        if !reportedScan {
            reportedScan = true
            logger.info("App lookup sees \(visible) of \(listed) processes, \(found.count) sockets")
        }
    }

    // MARK: Apps

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private func id(for executable: String) -> UInt32 {
        let app = Self.identify(executable)
        let key = app.path ?? app.name
        if let id = ids[key] { return id }
        // Small ids stay clear of the core's proxied ids (high bit).
        let id = UInt32(ids.count + 1)
        ids[key] = id
        apps[id] = app
        return id
    }

    /// The outermost `.app` around an executable (a Chrome helper belongs to Google Chrome), or
    /// the executable itself for command-line tools and daemons.
    private static func identify(_ executable: String) -> AppInfo {
        let components = executable.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return AppInfo(name: String(components.last ?? Substring(executable)), bundleID: nil, path: executable)
        }
        let path = "/" + components[...index].joined(separator: "/")
        let bundle = Bundle(path: path)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? String(components[index].dropLast(4))
        return AppInfo(name: name, bundleID: bundle?.bundleIdentifier, path: path)
    }

    private static func fnv1a(_ text: String) -> UInt32 {
        text.utf8.reduce(0x811c_9dc5) { ($0 ^ UInt32($1)) &* 0x0100_0193 }
    }
}
