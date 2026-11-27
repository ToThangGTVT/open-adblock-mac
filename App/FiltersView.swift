import SwiftUI

struct FiltersView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var customRules = ""
    @State private var catalog: CatalogSource?

    var body: some View {
        let active = store.settings.lists.filter(\.enabled).count
        form
            .pageBackground()
            .navigationTitle("Filters")
            .navigationSubtitle(
                tunnel.state == .on && (tunnel.status?.rulesLoaded ?? 0) > 0
                    ? "\(active) lists active · \((tunnel.status?.rulesLoaded ?? 0).formatted()) rules"
                    : "\(active) lists active")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Update Lists", systemImage: "arrow.clockwise") { tunnel.updateLists() }
                        .help("Download the latest version of every list")
                        .disabled(
                            tunnel.state != .on || tunnel.status?.lists.contains(where: \.downloading) == true)
                }
            }
        .sheet(item: $catalog) { source in
            CatalogSheet(source: source)
        }
        .onAppear { customRules = store.settings.customRules }
    }

    private var form: some View {
        Form {
            ListSection(source: .dns, catalog: $catalog)
            ListSection(source: .browser, catalog: $catalog)

            Section {
                TextEditor(text: $customRules)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                HStack {
                    Text("One rule per line: `||ads.example^` blocks a domain, `@@||example.com^` allows it. With browser filtering on, paths, `##` cosmetic rules and `+js()` scriptlets work too.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") { store.settings.customRules = customRules }
                        .buttonStyle(.borderedProminent)
                        .disabled(customRules == store.settings.customRules)
                }
            } header: {
                SectionLabel("Custom rules", icon: "pencil.and.list.clipboard", tint: Theme.warning)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct ListSection: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var tunnel: TunnelManager
    let source: CatalogSource
    @Binding var catalog: CatalogSource?
    @State private var newURL = ""

    private var lists: [FilterListSetting] { store.settings.lists.filter { $0.browser == source.browser } }

    var body: some View {
        Section {
            if lists.isEmpty {
                Text("No lists yet.").foregroundStyle(.secondary)
            }
            ForEach(lists) { list in
                ListRow(list: list, status: tunnel.status?.lists.first { $0.id == list.id })
            }
            HStack {
                TextField("Add a list by URL (https://…)", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addURL)
                Button("Add", action: addURL).disabled(URL(string: newURL)?.scheme != "https")
                Button("Browse Catalog…", systemImage: "books.vertical") { catalog = source }
                    .buttonStyle(.borderedProminent)
            }
        } header: {
            SectionLabel(
                source.title, icon: source == .dns ? "network.badge.shield.half.filled" : "globe",
                tint: source == .dns ? Theme.accent : SidebarItem.browsers.tint)
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
    }

    private var footer: String {
        switch source {
        case .dns:
            "Domain lists, applied to every app through DNS."
        case .browser:
            store.settings.https.enabled
                ? "Applied inside the browsers chosen under Browsers (HTTPS filtering)."
                : "Turn on browser filtering under Browsers to use these lists."
        }
    }

    private func addURL() {
        guard let url = URL(string: newURL.trimmingCharacters(in: .whitespaces)), url.scheme == "https",
            url.host?.isEmpty == false
        else { return }
        store.add(
            FilterListSetting(
                id: "url:\(CertificateTrust.fingerprint(Data(url.absoluteString.utf8)).prefix(16))",
                name: url.host ?? url.absoluteString, url: url, browser: source.browser, enabled: true))
        newURL = ""
    }
}

private struct ListRow: View {
    @EnvironmentObject private var store: SettingsStore
    let list: FilterListSetting
    let status: ListStatus?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(
                systemName: list.browser ? "doc.text.fill" : "list.bullet.rectangle.fill",
                tint: list.enabled ? (list.browser ? SidebarItem.browsers.tint : Theme.accent) : Theme.slate,
                size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name).fontWeight(.medium)
                Text(list.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if let status, let updated = status.updated {
                    Text("\(status.entries.formatted()) entries · updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                if let error = status?.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Theme.blocked)
                }
            }
            Spacer()
            if status?.downloading == true {
                ProgressView().controlSize(.small)
            }
            Button("Remove", systemImage: "trash") { store.remove(list.id) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this list")
            Toggle(
                list.name,
                isOn: Binding(get: { list.enabled }, set: { store.setList(list.id, enabled: $0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}

/// The AdGuard catalog for one source, grouped like the registry, with search.
private struct CatalogSheet: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var catalogs: CatalogStore
    @Environment(\.dismiss) private var dismiss
    let source: CatalogSource
    @State private var search = ""
    @State private var recommendedOnly = false

    private var entries: [CatalogEntry] {
        (catalogs.entries[source] ?? []).filter { entry in
            (!recommendedOnly || entry.recommended)
                && (search.isEmpty || entry.name.localizedCaseInsensitiveContains(search)
                    || entry.summary.localizedCaseInsensitiveContains(search)
                    || entry.languages.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    private var groups: [(name: String, entries: [CatalogEntry])] {
        var order: [String] = []
        var grouped: [String: [CatalogEntry]] = [:]
        for entry in entries {
            if grouped[entry.group] == nil { order.append(entry.group) }
            grouped[entry.group, default: []].append(entry)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconBadge(systemName: "books.vertical.fill", tint: SidebarItem.filters.tint, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title).font(.title3.weight(.semibold))
                    Text("Pick the lists to add").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if source == .browser {
                    Toggle("Recommended only", isOn: $recommendedOnly).toggleStyle(.checkbox)
                }
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            .padding()
            Divider()
            Group {
                if catalogs.loading.contains(source) && entries.isEmpty {
                    ProgressView("Loading catalog…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = catalogs.errors[source], entries.isEmpty {
                    ContentUnavailableView {
                        Label("Catalog unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await catalogs.load(source, force: true) } }
                    }
                } else {
                    List {
                        ForEach(groups, id: \.name) { group in
                            Section(group.name) {
                                ForEach(group.entries) { entry in CatalogRow(entry: entry) }
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("Catalog by AdGuard; each list keeps its own license.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 640, height: 560)
        .task { await catalogs.load(source) }
    }
}

private struct CatalogRow: View {
    @EnvironmentObject private var store: SettingsStore
    let entry: CatalogEntry

    private var added: Bool { store.settings.lists.contains { $0.id == entry.id || $0.url == entry.url } }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                    if entry.recommended {
                        Pill(text: "Recommended", icon: "star.fill", tint: Theme.accent)
                    }
                }
                if !entry.summary.isEmpty {
                    Text(entry.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if !entry.languages.isEmpty {
                    Text(entry.languages.joined(separator: ", ")).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle(
                entry.name,
                isOn: Binding(
                    get: { added },
                    set: { adding in
                        if adding {
                            store.add(entry.setting)
                        } else {
                            store.settings.lists.removeAll { $0.id == entry.id || $0.url == entry.url }
                        }
                    })
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }
}
