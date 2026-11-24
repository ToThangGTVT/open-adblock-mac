import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var tunnel: TunnelManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExtensionBanner()
                ProtectionCard()
                if let status = tunnel.status, tunnel.state == .on {
                    HStack(spacing: 16) {
                        StatTile(title: "Queries today", value: status.todayTotal.formatted(), tint: .blue)
                        StatTile(title: "Blocked today", value: status.todayBlocked.formatted(), tint: .red)
                        StatTile(
                            title: "Blocked share",
                            value: status.todayTotal == 0
                                ? "–"
                                : (Double(status.todayBlocked) / Double(status.todayTotal))
                                    .formatted(.percent.precision(.fractionLength(1))),
                            tint: .orange)
                    }
                    TopBlockedCard(domains: status.topBlocked)
                    TrafficCard(status: status)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Home")
    }
}

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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            Button(button, action: action)
        }
        .padding(16)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProtectionCard: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var store: SettingsStore

    private var subtitle: String {
        switch tunnel.state {
        case .loading: "Loading…"
        case .off: "Ads and trackers are not being blocked."
        case .connecting: "Starting the filtering tunnel…"
        case .on: "Every app on this Mac is filtered."
        case .disconnecting: "Stopping…"
        case .failed(let message): message
        }
    }

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: tunnel.state.isOn ? "shield.lefthalf.filled" : "shield.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(tunnel.state.isOn ? Color.green : Color.secondary)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(tunnel.state.isOn ? "Protection is on" : "Protection is off")
                    .font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
                if let error = tunnel.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
            Spacer()
            Toggle(
                "Protection",
                isOn: Binding(
                    get: { tunnel.state.isOn }, set: { tunnel.setEnabled($0, settings: store.settings) })
            )
            .toggleStyle(.switch)
            .controlSize(.large)
            .labelsHidden()
            .disabled(tunnel.state == .loading || tunnel.state == .disconnecting)
        }
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TopBlockedCard: View {
    let domains: [DomainCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Most blocked today").font(.headline)
            if domains.isEmpty {
                Text("Nothing blocked yet.").foregroundStyle(.secondary)
            } else {
                let top = Double(domains.first?.count ?? 1)
                ForEach(domains) { item in
                    HStack {
                        Text(item.domain).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(item.count.formatted()).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .background(alignment: .leading) {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.12))
                                .frame(width: proxy.size.width * Double(item.count) / top)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TrafficCard: View {
    let status: TunnelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Since protection started").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Connections").foregroundStyle(.secondary)
                    Text(status.connections.formatted()).monospacedDigit()
                }
                GridRow {
                    Text("Uploaded").foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: status.tcpBytesUp, countStyle: .binary))
                }
                GridRow {
                    Text("Downloaded").foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: status.tcpBytesDown, countStyle: .binary))
                }
                GridRow {
                    Text("Rules loaded").foregroundStyle(.secondary)
                    Text(status.rulesLoaded.formatted()).monospacedDigit()
                }
                if let started = status.startedAt {
                    GridRow {
                        Text("Started").foregroundStyle(.secondary)
                        Text(started, style: .relative)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
