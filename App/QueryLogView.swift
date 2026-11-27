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
        .filter { search.isEmpty || $0.url.localizedCaseInsensitiveContains(search) }
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
        .searchable(text: $search, placement: .toolbar, prompt: "Search URLs")
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
