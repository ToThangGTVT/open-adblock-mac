import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var tunnel: TunnelManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ExtensionBanner()
                HeroCard()
                if let status = tunnel.status, tunnel.state == .on {
                    StatsRow(status: status)
                    HStack(alignment: .top, spacing: 18) {
                        TopBlockedCard(domains: status.topBlocked)
                        SessionCard(status: status)
                            .frame(width: 260)
                    }
                }
                ShieldsCard()
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.45), value: tunnel.state)
        }
        .pageBackground()
        .navigationTitle("Protection")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        guard tunnel.state == .on, let status = tunnel.status else { return tunnel.state.shortTitle }
        return "\(status.todayBlocked.formatted()) blocked today"
    }
}

// MARK: - Extension banner

/// Shown until macOS has the system extension running.
private struct ExtensionBanner: View {
    @EnvironmentObject private var installer: ExtensionInstaller

    var body: some View {
        switch installer.state {
        case .ready, .unknown, .activating:
            EmptyView()
        case .needsApproval:
            banner(
                "Allow the Open AdBlock extension",
                "macOS needs your approval once: System Settings › General › Login Items & Extensions › Network Extensions.",
                button: "Open System Settings"
            ) { installer.openApprovalSettings() }
        case .failed(let message):
            banner("The filtering extension could not be installed", message, button: "Try Again") {
                installer.activate()
            }
        }
    }

    private func banner(_ title: String, _ detail: String, button: String, action: @escaping () -> Void)
        -> some View
    {
        HStack(alignment: .center, spacing: 14) {
            IconBadge(systemName: "exclamationmark.shield.fill", tint: Theme.warning, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Theme.warning)
        }
        .padding(16)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.35), lineWidth: 2)
        }
    }
}

// MARK: - Hero

private struct HeroCard: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var store: SettingsStore

    private var subtitle: String {
        switch tunnel.state {
        case .loading: "Looking up the filtering tunnel…"
        case .off: "Ads, trackers and malicious domains can reach this Mac. Turn protection on to filter every app."
        case .connecting: "Starting the filtering tunnel…"
        case .on: "Ads, trackers and malicious domains are blocked in every app on this Mac."
        case .disconnecting: "Stopping the filtering tunnel…"
        case .failed(let message): message
        }
    }

    var body: some View {
        HStack(spacing: 28) {
            PowerButton()
            VStack(alignment: .leading, spacing: 10) {
                Pill(
                    text: tunnel.state.shortTitle.uppercased(),
                    icon: tunnel.state.isOn ? "checkmark" : (tunnel.state.isBusy ? nil : "exclamationmark"),
                    tint: tunnel.state.tint)
                Text(tunnel.state.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .contentTransition(.opacity)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = tunnel.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(Theme.blocked).textSelection(.enabled)
                    if tunnel.lastErrorNeedsSettings {
                        VPNSettingsHelp()
                    }
                }
                if tunnel.state == .on, let started = tunnel.status?.startedAt {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text("Protected for ") + Text(started, style: .relative)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tunnel.state.tint.opacity(0.25), lineWidth: 2)
        }
    }
}

/// The big round switch: emerald and pulsing while protected, slate while off.
private struct PowerButton: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var store: SettingsStore
    @State private var hovering = false

    private let size: CGFloat = 132

    var body: some View {
        Button {
            tunnel.setEnabled(!tunnel.state.isOn, settings: store.settings)
        } label: {
            ZStack {
                Circle()
                    .fill(tunnel.state.fill)
                    .frame(width: size, height: size)
                if tunnel.state.isBusy {
                    SpinnerArc(size: size + 12)
                }
                VStack(spacing: 4) {
                    Image(systemName: tunnel.state.isOn ? "lock.shield.fill" : "power")
                        .font(.system(size: 46, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(tunnel.state.isOn ? "ON" : "OFF")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
            }
            .frame(width: size + 20, height: size + 20)
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(tunnel.state == .loading || tunnel.state == .disconnecting)
        .onHover { inside in withAnimation(.easeOut(duration: 0.2)) { hovering = inside } }
        .help(tunnel.state.isOn ? "Turn protection off" : "Turn protection on")
        .accessibilityLabel(tunnel.state.isOn ? "Turn protection off" : "Turn protection on")
    }

}

private struct SpinnerArc: View {
    let size: CGFloat
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(Theme.info, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// What to do when macOS refuses to start an Open AdBlock configuration, with a button that opens
/// the right System Settings pane.
struct VPNSettingsHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In System Settings › VPN, turn “Open AdBlock” on (browser filtering is listed under Network › Filters). If it still fails, remove that entry, then turn protection on again here: the app recreates it. This also happens after switching between a debug and a released build of the app.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open VPN Settings…") { TunnelManager.openVPNSettings() }
        }
        .padding(.top, 4)
    }
}

// MARK: - Stats

private struct StatsRow: View {
    let status: TunnelStatus

    private var share: Double {
        status.todayTotal == 0 ? 0 : Double(status.todayBlocked) / Double(status.todayTotal)
    }

    var body: some View {
        HStack(spacing: 18) {
            StatTile(
                icon: "network", tint: Theme.info, title: "Requests today",
                value: status.todayTotal.formatted(), caption: "DNS queries checked")
            StatTile(
                icon: "hand.raised.fill", tint: Theme.blocked, title: "Blocked today",
                value: status.todayBlocked.formatted(), caption: "Ads, trackers and threats")
            HStack(spacing: 14) {
                RingGauge(value: share, tint: Theme.accent)
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocked share").font(.callout).foregroundStyle(.secondary)
                    Text(status.todayTotal == 0 ? "–" : share.formatted(.percent.precision(.fractionLength(1))))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("of today's requests").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .card()
        }
    }
}

private struct StatTile: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: icon, tint: tint, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .card()
    }
}

struct RingGauge: View {
    let value: Double
    let tint: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(value, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
            Image(systemName: "shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Top blocked

private struct TopBlockedCard: View {
    let domains: [DomainCount]
    @Environment(\.navigate) private var navigate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardTitle(title: "Most blocked today", icon: "flame.fill", tint: Theme.blocked)
                Spacer()
                Button("View activity") { navigate(.log) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
            if domains.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    Text("Nothing blocked yet today.").foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                let top = Double(domains.first?.count ?? 1)
                VStack(spacing: 10) {
                    ForEach(domains) { item in
                        DomainBar(domain: item.domain, count: item.count, fraction: Double(item.count) / top)
                    }
                }
            }
        }
        .card()
    }
}

private struct DomainBar: View {
    let domain: String
    let count: Int
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(String(domain.trimmingCharacters(in: CharacterSet(charactersIn: "w.")).prefix(1)).uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.blocked)
                .frame(width: 24, height: 24)
                .background(Theme.blocked.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(domain).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(count.formatted()).monospacedDigit().foregroundStyle(.secondary).font(.callout)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(Theme.blocked)
                            .frame(width: max(6, proxy.size.width * fraction))
                    }
                }
                .frame(height: 5)
            }
        }
    }
}

// MARK: - Session

private struct SessionCard: View {
    let status: TunnelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "This session", icon: "chart.bar.fill", tint: Theme.info)
            VStack(spacing: 12) {
                metric("arrow.triangle.branch", Theme.violet, "Connections", status.connections.formatted())
                metric(
                    "arrow.up.circle.fill", Theme.info, "Uploaded",
                    ByteCountFormatter.string(fromByteCount: status.tcpBytesUp, countStyle: .binary))
                metric(
                    "arrow.down.circle.fill", Theme.accent, "Downloaded",
                    ByteCountFormatter.string(fromByteCount: status.tcpBytesDown, countStyle: .binary))
                metric("list.bullet.rectangle.fill", Theme.warning, "Rules loaded", status.rulesLoaded.formatted())
            }
        }
        .card()
    }

    private func metric(_ icon: String, _ tint: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 18)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
    }
}

// MARK: - Shields

/// Each protection layer, whether it is working, and a shortcut to where it is set up.
private struct ShieldsCard: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.navigate) private var navigate

    private var on: Bool { tunnel.state == .on }

    var body: some View {
        let settings = store.settings
        let dnsLists = settings.enabledLists(browser: false).count
        let browserLists = settings.enabledLists(browser: true).count
        let encrypted = [.https, .tls, .quic].contains(settings.upstream.protocol)

        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Protection layers", icon: "square.stack.3d.up.fill")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ShieldTile(
                    icon: "network.badge.shield.half.filled", tint: Theme.accent,
                    title: "Ad & tracker blocking",
                    detail: "\(dnsLists) block \(dnsLists == 1 ? "list" : "lists") for every app",
                    active: on && dnsLists > 0
                ) { navigate(.filters) }
                ShieldTile(
                    icon: "lock.fill", tint: Theme.info,
                    title: "Encrypted DNS",
                    detail: encrypted ? settings.upstream.protocol.title : "Plain DNS: queries are readable on the network",
                    active: on && encrypted
                ) { navigate(.settings) }
                ShieldTile(
                    icon: "globe", tint: Theme.info,
                    title: "Browser filtering",
                    detail: settings.https.enabled
                        ? "\(browserLists) filter \(browserLists == 1 ? "list" : "lists"), cosmetic rules"
                        : "Off: turn on to remove in-page ads",
                    active: on && settings.https.enabled && tunnel.browserProxy == .connected
                ) { navigate(.browsers) }
                ShieldTile(
                    icon: "eye.slash.fill", tint: Theme.violet,
                    title: "Anti-censorship (DPI)",
                    detail: settings.dpi ? "Disguises the first packets of connections" : "Off",
                    active: on && settings.dpi
                ) { navigate(.settings) }
            }
        }
        .card()
    }
}

private struct ShieldTile: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemName: icon, tint: active ? tint : Theme.slate, size: 34)
                    .saturation(active ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: active ? "checkmark.circle.fill" : "minus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(active ? Theme.accent : Color.secondary.opacity(0.6))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(hovering ? 0.07 : 0.035),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
    }
}
