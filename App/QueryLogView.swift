import SwiftUI

struct QueryLogView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", blocked = "Blocked", allowed = "Allowed"
        var id: String { rawValue }
    }

    @EnvironmentObject private var tunnel: TunnelManager
    @State private var filter: Filter = .all
    @State private var search = ""

    private var entries: [LogEntry] {
        (tunnel.status?.recent ?? []).filter { entry in
            switch filter {
            case .all: true
            case .blocked: entry.blocked
            case .allowed: !entry.blocked
            }
        }
        .filter { search.isEmpty || $0.domain.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            if tunnel.state != .on {
                ContentUnavailableView(
                    "Protection is off", systemImage: "list.bullet.rectangle",
                    description: Text("Turn protection on to see DNS queries."))
            } else if entries.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                Table(entries) {
                    TableColumn("Time") { entry in
                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(80)
                    TableColumn("Domain") { entry in
                        Text(entry.domain).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("Status") { entry in
                        Label(
                            entry.blocked ? "Blocked" : (entry.cached ? "Cached" : "Allowed"),
                            systemImage: entry.blocked ? "xmark.octagon.fill" : "checkmark.circle"
                        )
                        .foregroundStyle(entry.blocked ? Color.red : Color.secondary)
                    }
                    .width(100)
                    TableColumn("Rule") { entry in
                        Text(entry.rule ?? "").lineLimit(1).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Query Log")
        .searchable(text: $search, prompt: "Domain")
        .toolbar {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Button("Clear", systemImage: "trash") { tunnel.clearLog() }
                .disabled(tunnel.state != .on)
        }
    }
}
