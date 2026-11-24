import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, log, filters, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .log: "Query Log"
        case .filters: "Filters"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "shield.lefthalf.filled"
        case .log: "list.bullet.rectangle"
        case .filters: "line.3.horizontal.decrease.circle"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection ?? .home {
            case .home: HomeView()
            case .log: QueryLogView()
            case .filters: FiltersView()
            case .settings: SettingsView()
            }
        }
    }
}
