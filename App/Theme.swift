import SwiftUI

/// The app's look: flat, solid colors that follow the system. The main color is the accent color
/// chosen in System Settings › Appearance; states use the standard system colors, which adapt to
/// light and dark mode.
enum Theme {
    /// The main color, and the color of "protected".
    static let accent = Color.accentColor
    static let blocked = Color.red
    static let warning = Color.orange
    static let info = Color.blue
    static let violet = Color.purple
    static let slate = Color.gray

    static let cornerRadius: CGFloat = 14
}

// MARK: - Cards

/// A raised surface for one block of content.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 18
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.55 : 0.9))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 2)
            }
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardBackground(padding: padding)) }

    /// The page backdrop: the plain window color.
    func pageBackground() -> some View {
        background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

// MARK: - Icons and labels

/// An SF Symbol on a rounded colored square, like the icons in System Settings.
struct IconBadge: View {
    let systemName: String
    var tint: Color = Theme.accent
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// A section title inside a card.
struct CardTitle: View {
    let title: String
    let icon: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 13, weight: .semibold))
            Text(title).font(.headline)
        }
    }
}

/// A section header for grouped forms.
struct SectionLabel: View {
    let title: String
    let icon: String
    var tint: Color = Theme.accent

    init(_ title: String, icon: String, tint: Color = Theme.accent) {
        self.title = title
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
    }
}

/// A small colored capsule.
struct Pill: View {
    let text: String
    var icon: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Protection state

extension TunnelManager.State {
    var title: String {
        switch self {
        case .loading: "Checking…"
        case .off: "You're not protected"
        case .connecting: "Turning on protection…"
        case .on: "You're protected"
        case .disconnecting: "Turning off…"
        case .failed: "Protection failed"
        }
    }

    var shortTitle: String {
        switch self {
        case .on: "Protected"
        case .connecting: "Connecting"
        case .disconnecting: "Stopping"
        case .loading: "Checking"
        case .off: "Not protected"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .on: Theme.accent
        case .connecting, .disconnecting, .loading: Theme.info
        case .off: Theme.slate
        case .failed: Theme.warning
        }
    }

    var isBusy: Bool { self == .connecting || self == .disconnecting || self == .loading }

    /// The solid fill for the power button and status icons.
    var fill: Color {
        switch self {
        case .on: Theme.accent
        case .failed: Theme.warning
        case .off: Theme.slate
        case .connecting, .disconnecting, .loading: Theme.info
        }
    }
}

// MARK: - Navigation

extension EnvironmentValues {
    /// Moves the main window to a page; set by `ContentView`.
    @Entry var navigate: (SidebarItem) -> Void = { _ in }
}
