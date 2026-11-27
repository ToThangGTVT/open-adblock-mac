import AppKit
import SwiftUI

struct QueryLogView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", blocked = "Blocked", allowed = "Allowed"
        var id: String { rawValue }
    }

    @EnvironmentObject private var tunnel: TunnelManager
    @State private var filter: Filter = .all
    @State private var search = ""

    private func entries() -> [LogEntry] {
        (tunnel.status?.recent ?? []).filter { entry in
            switch filter {
            case .all: true
            case .blocked: entry.blocked
            case .allowed: !entry.blocked
            }
        }
        .filter {
            search.isEmpty || $0.url.localizedCaseInsensitiveContains(search)
                || ($0.app?.name.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        let entries = entries()
        let recent = tunnel.status?.recent ?? []
        let blocked = recent.lazy.filter(\.blocked).count

        VStack(alignment: .leading, spacing: 14) {
            if tunnel.state == .on {
                HStack(spacing: 10) {
                    SummaryChip(icon: "tray.full.fill", tint: Theme.info, title: "Recent", value: recent.count)
                    SummaryChip(icon: "hand.raised.fill", tint: Theme.blocked, title: "Blocked", value: blocked)
                    SummaryChip(
                        icon: "checkmark.shield.fill", tint: Theme.accent, title: "Allowed",
                        value: recent.count - blocked)
                }
            }

            Group {
                if tunnel.state != .on {
                    ContentUnavailableView {
                        Label("Protection is off", systemImage: "shield.slash")
                    } description: {
                        Text("Turn protection on to watch requests live.")
                    }
                } else if entries.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView(
                            "No requests yet", systemImage: "waveform.path.ecg",
                            description: Text("Requests show up here as apps make them."))
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                } else {
                    LogTable(entries: entries)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 2)
            }
        }
        .padding(20)
        .pageBackground()
        .navigationTitle("Activity")
        .navigationSubtitle(tunnel.state == .on ? "Live" : "Paused while protection is off")
        .searchable(text: $search, placement: .toolbar, prompt: "Search URLs or apps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Clear", systemImage: "trash") { tunnel.clearLog() }
                    .disabled(tunnel.state != .on)
                    .help("Clear the activity log")
            }
        }
    }
}

private struct SummaryChip: View {
    let icon: String
    let tint: Color
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).foregroundStyle(.secondary)
            Text(value.formatted()).fontWeight(.semibold).monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.1), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.2), lineWidth: 2) }
    }
}

private struct LogTable: View {
    let entries: [LogEntry]

    var body: some View {
        Table(entries) {
            TableColumn("Time") { entry in
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(72)
            TableColumn("App") { entry in
                AppLabel(app: entry.app, dns: entry.kind == "dns")
            }
            .width(min: 90, ideal: 150, max: 260)
            TableColumn("Request") { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.blocked ? "xmark.shield.fill" : "checkmark.shield.fill")
                        .foregroundStyle(entry.blocked ? Theme.blocked : Theme.accent.opacity(0.8))
                    Text(entry.url).lineLimit(1).truncationMode(.middle).help(entry.url)
                        .foregroundStyle(entry.blocked ? Theme.blocked : Color.primary)
                }
            }
            TableColumn("Status") { entry in
                if entry.blocked {
                    Pill(text: "Blocked", tint: Theme.blocked)
                } else if entry.cached {
                    Pill(text: "Cached", tint: Theme.info)
                } else {
                    Pill(text: "Allowed", tint: Theme.accent)
                }
            }
            .width(84)
            TableColumn("Rule") { entry in
                Text(entry.rule ?? "").lineLimit(1).font(.callout.monospaced()).foregroundStyle(.secondary)
                    .help(entry.rule ?? "")
            }
        }
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
    }
}

/// An app's icon and name. DNS rows have no app: macOS resolves names in mDNSResponder.
private struct AppLabel: View {
    let app: AppInfo?
    let dns: Bool

    var body: some View {
        if let app {
            HStack(spacing: 6) {
                Image(nsImage: AppIcons.icon(for: app)).resizable().frame(width: 16, height: 16)
                Text(app.name).lineLimit(1).truncationMode(.tail)
            }
            .help(app.bundleID ?? app.path ?? app.name)
        } else {
            Text(dns ? "System DNS" : "Unknown").foregroundStyle(.tertiary).lineLimit(1)
                .help(dns ? "Apps resolve names through macOS (mDNSResponder), so DNS lookups have no app" : "")
        }
    }
}

/// Icons looked up once per app (the table redraws with every status update).
@MainActor
private enum AppIcons {
    private static var cache: [AppInfo: NSImage] = [:]

    static func icon(for app: AppInfo) -> NSImage {
        if let icon = cache[app] { return icon }
        let path = app.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
            ?? app.path
        let icon = path.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        cache[app] = icon
        return icon
    }
}
