import SwiftUI

struct FiltersView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var customRules = ""

    var body: some View {
        Form {
            Section {
                ForEach(FilterCatalog.all) { list in
                    ListRow(list: list, status: tunnel.status?.lists.first { $0.id == list.id })
                }
            } header: {
                Text("Block lists")
            } footer: {
                if let status = tunnel.status, tunnel.state == .on {
                    Text("\(status.rulesLoaded.formatted()) rules active in the engine.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("The filtering extension downloads enabled lists when protection is on and refreshes them daily.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextEditor(text: $customRules)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
                HStack {
                    Text("One rule per line: `||ads.example^` blocks a domain, `@@||example.com^` allows it.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") { store.settings.customRules = customRules }
                        .disabled(customRules == store.settings.customRules)
                }
            } header: {
                Text("Custom rules")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Filters")
        .toolbar {
            Button("Update Lists", systemImage: "arrow.clockwise") { tunnel.updateLists() }
                .disabled(tunnel.state != .on || tunnel.status?.lists.contains(where: \.downloading) == true)
        }
        .onAppear { customRules = store.settings.customRules }
    }
}

private struct ListRow: View {
    @EnvironmentObject private var store: SettingsStore
    let list: FilterList
    let status: ListStatus?

    private var setting: FilterListSetting? { store.settings.lists.first { $0.id == list.id } }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                Text(list.summary).font(.callout).foregroundStyle(.secondary)
                if let status, let updated = status.updated {
                    Text("\(status.entries.formatted()) entries · updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                if let error = status?.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            if status?.downloading == true {
                ProgressView().controlSize(.small)
            }
            Toggle(
                list.name,
                isOn: Binding(
                    get: { setting?.enabled ?? false },
                    set: { store.setList(list.id, enabled: $0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}
