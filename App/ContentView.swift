import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, log, filters, browsers, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .log: "Query Log"
        case .filters: "Filters"
        case .browsers: "Browsers"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "shield.lefthalf.filled"
        case .log: "list.bullet.rectangle"
        case .filters: "line.3.horizontal.decrease.circle"
        case .browsers: "safari"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    /// The row the sidebar highlights, which moves at once on a click.
    @State private var highlighted: SidebarItem = .home
    /// The page on the right, which follows once the highlight has slid over: building a page
    /// takes a moment, and doing it first would freeze the highlight on the old row.
    @State private var page: SidebarItem = .home

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: highlighted, choose: choose)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch page {
            case .home: HomeView()
            case .log: QueryLogView()
            case .filters: FiltersView()
            case .browsers: BrowsersView()
            case .settings: SettingsView()
            }
        }
    }

    private func choose(_ item: SidebarItem) {
        guard item != highlighted else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            highlighted = item
        } completion: {
            // Several quick clicks: show where the highlight ended up.
            page = highlighted
        }
    }
}

/// The sidebar rows as buttons, so the selection can slide between rows and a row reacts while
/// it is pressed (a `List` changes its native highlight without animation).
private struct Sidebar: View {
    let selection: SidebarItem
    let choose: (SidebarItem) -> Void
    @Namespace private var highlight
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 2) {
            ForEach(SidebarItem.allCases) { item in
                Button { choose(item) } label: {
                    SidebarRow(item: item, selected: item == selection, highlight: highlight)
                }
                .buttonStyle(SidebarButtonStyle())
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            let items = SidebarItem.allCases
            guard let index = items.firstIndex(of: selection) else { return }
            switch direction {
            case .up where index > 0: choose(items[index - 1])
            case .down where index < items.count - 1: choose(items[index + 1])
            default: break
            }
        }
        .onAppear { focused = true }
    }
}

private struct SidebarRow: View {
    let item: SidebarItem
    let selected: Bool
    let highlight: Namespace.ID
    @Environment(\.controlActiveState) private var activeState
    /// Bumped each time this row becomes selected, so its icon bounces once.
    @State private var bounces = 0
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 15))
                .frame(width: 20)
                .foregroundStyle(selected && windowActive ? Color.white : Color.accentColor)
                .symbolEffect(.bounce, value: bounces)
            Text(item.title)
                .foregroundStyle(selected && windowActive ? Color.white : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(windowActive ? Color.accentColor : Color.primary.opacity(0.12))
                    .matchedGeometryEffect(id: "highlight", in: highlight)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0))
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .onChange(of: selected) { _, isSelected in
            if isSelected { bounces += 1 }
        }
    }

    /// Like the native sidebar: the accent highlight only in the front window.
    private var windowActive: Bool { activeState == .key || activeState == .active }
}

/// Presses the row in slightly while the mouse button is down.
private struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
