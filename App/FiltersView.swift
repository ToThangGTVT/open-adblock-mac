import SwiftUI

struct FiltersView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var customRules = ""

    var body: some View {
        Form {
            Section {
                ForEach(FilterCatalog.all) { list in
                    ListRow(list: list)
                }
                if let error = store.downloadError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            } header: {
                Text("Block lists")
            } footer: {
                if let status = tunnel.status, tunnel.state == .on {
                    Text("\(status.rulesLoaded.formatted()) rules active in the engine.")
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
            Button("Update Lists", systemImage: "arrow.clockwise") {
                Task { await store.updateAll() }
            }
            .disabled(!store.downloading.isEmpty)
        }
        .onAppear { customRules = store.settings.customRules }
    }
}

private struct ListRow: View {
    @EnvironmentObject private var store: SettingsStore
    let list: FilterList

    private var setting: FilterListSetting? { store.settings.lists.first { $0.id == list.id } }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                Text(list.summary).font(.callout).foregroundStyle(.secondary)
                if let setting, let updated = setting.updated {
                    Text("\((setting.rules ?? 0).formatted()) entries · updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if store.downloading.contains(list.id) {
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
