import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, log, filters, browsers, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Protection"
        case .log: "Activity"
        case .filters: "Filters"
        case .browsers: "Browsers"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "shield.lefthalf.filled"
        case .log: "waveform.path.ecg"
        case .filters: "line.3.horizontal.decrease"
        case .browsers: "globe"
        case .settings: "gearshape.fill"
        }
    }

    /// Every page uses the system accent color, like a native sidebar.
    var tint: Color { Theme.accent }
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
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch page {
                case .home: HomeView()
                case .log: QueryLogView()
                case .filters: FiltersView()
                case .browsers: BrowsersView()
                case .settings: SettingsView()
                }
            }
        }
        .environment(\.navigate, choose)
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
        VStack(alignment: .leading, spacing: 0) {
            Brand()
                .padding(.horizontal, 14)
                .padding(.bottom, 18)

            VStack(spacing: 3) {
                ForEach(SidebarItem.allCases) { item in
                    Button { choose(item) } label: {
                        SidebarRow(item: item, selected: item == selection, highlight: highlight)
                    }
                    .buttonStyle(SidebarButtonStyle())
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .padding(.top, 4)
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

/// App icon and name at the top of the sidebar.
private struct Brand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("Open AdBlock").font(.system(size: 14, weight: .bold, design: .rounded))
                Text("Privacy Protection").font(.caption).foregroundStyle(.secondary)
            }
        }
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
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected && windowActive ? item.tint : .white)
                .frame(width: 24, height: 24)
                .background(
                    selected && windowActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(item.tint),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .symbolEffect(.bounce, value: bounces)
            Text(item.title)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected && windowActive ? Color.white : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(windowActive ? Theme.accent : Color.primary.opacity(0.12))
                    .matchedGeometryEffect(id: "highlight", in: highlight)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
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
