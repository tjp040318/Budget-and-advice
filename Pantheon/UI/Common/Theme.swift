import SwiftUI

/// The app's visual language, in one place.
///
/// Everything is dark, gold-accented and high-contrast, because the screen is
/// mostly 3D and the UI has to sit on top of it without competing. Colours are
/// derived from the same hex strings the 3D layer uses, so a Radiance unit is
/// the same yellow on its card and in its aura.
enum Theme {

    // MARK: - Palette

    static let ink = Color(hex: "#0B0D14")
    static let surface = Color(hex: "#151A26")
    static let surfaceRaised = Color(hex: "#1E2534")
    static let stroke = Color(hex: "#2E374A")
    static let gold = Color(hex: "#E8C86A")
    static let goldDim = Color(hex: "#A08A45")
    static let textPrimary = Color(hex: "#F0F2F7")
    static let textSecondary = Color(hex: "#98A0B4")
    static let danger = Color(hex: "#E8574F")
    static let success = Color(hex: "#5FD98A")
    static let info = Color(hex: "#5FA8D8")

    // MARK: - Type

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .serif)
    }

    static func title(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }

    static func numeric(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    // MARK: - Shapes

    static let cornerRadius: CGFloat = 14
    static let tightCorner: CGFloat = 9

    /// The standard panel background: raised surface, hairline stroke.
    static func panel(_ radius: CGFloat = cornerRadius) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }

    /// The screen background — a slow vertical gradient so flat panels read.
    static var backdrop: some View {
        LinearGradient(
            colors: [ink, Color(hex: "#12172A"), ink],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension Color {
    /// Parses `#RRGGBB`. Falls back to magenta so a typo is visible rather than
    /// silently transparent.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .pink
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Element {
    var color: Color { Color(hex: accentHex) }
}

extension Pantheon {
    var color: Color { Color(hex: accentHex) }
}

extension ArenaTier {
    var color: Color { Color(hex: accentHex) }
}

// MARK: - Reusable modifiers

struct PanelBackground: ViewModifier {
    var radius: CGFloat = Theme.cornerRadius
    func body(content: Content) -> some View {
        content.background(Theme.panel(radius))
    }
}

extension View {
    func panelBackground(radius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(PanelBackground(radius: radius))
    }

    /// Standard screen chrome: backdrop, dark mode, and a title bar style.
    func screen(_ title: String) -> some View {
        self
            .background(Theme.backdrop)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
    }
}
