import SwiftUI
import UIKit

/// The app's visual language, in one place.
///
/// The brief is a collection RPG, not a utility app, and the difference is
/// almost entirely depth and rarity. Two rules drive everything below:
///
/// 1. **Nothing is a flat fill.** Every surface is a gradient with a light top
///    edge and a dark bottom rim, so panels read as objects with a thickness
///    rather than as coloured rectangles. A single hairline stroke on a solid
///    fill is what makes an interface look like Settings.
/// 2. **Rarity is the loudest thing on screen.** A 5★ and a 1★ must be
///    distinguishable across the room, before a single word is read. The frame
///    carries that, not a text label — see `Rarity`.
///
/// Colours are still derived from the same hex strings the 3D layer uses, so a
/// Radiance unit is the same yellow on its card and in its aura.
enum Theme {

    // MARK: - Palette

    /// Deep indigo rather than neutral charcoal. The warm gold and the element
    /// colours have nothing to sit against on a grey, and the whole screen goes
    /// muddy — which was the single biggest problem with the first pass.
    static let ink = Color(hex: "#07060F")
    static let surface = Color(hex: "#141328")
    static let surfaceRaised = Color(hex: "#1F1D3D")
    static let surfaceHigh = Color(hex: "#2A274F")
    static let stroke = Color(hex: "#3B3766")

    static let gold = Color(hex: "#F5D57A")
    static let goldDim = Color(hex: "#9C8244")
    static let goldDeep = Color(hex: "#6B5220")

    static let textPrimary = Color(hex: "#F4F1FF")
    static let textSecondary = Color(hex: "#9E97C4")

    static let danger = Color(hex: "#FF5B57")
    static let success = Color(hex: "#4BE38F")
    static let info = Color(hex: "#5FC8FF")

    // MARK: - Metal

    /// Polished gold. Three stops, not two: the pale band across the upper
    /// third is what reads as metal instead of as an orange rectangle.
    static let goldPlate = LinearGradient(
        colors: [Color(hex: "#8A6B28"), Color(hex: "#F7E39B"),
                 Color(hex: "#D9AE4E"), Color(hex: "#7A5A20")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The wash used on raised panels.
    static let panelPlate = LinearGradient(
        colors: [surfaceHigh, surfaceRaised, surface],
        startPoint: .top,
        endPoint: .bottom
    )

    /// A one-pixel highlight along the top edge and a dark rim along the
    /// bottom. Cheap, and it does most of the work of making a panel solid.
    static let bevel = LinearGradient(
        colors: [Color.white.opacity(0.28), Color.white.opacity(0.04),
                 Color.clear, Color.black.opacity(0.45)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Type

    /// Headline voice. Heavy and wide-tracked; the previous serif fought with
    /// the rounded titles and neither won.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }

    static func title(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .heavy, design: .default)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Numbers are monospaced so columns of stats line up, which matters more
    /// here than in most apps — the whole game is comparing two stat blocks.
    static func numeric(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    // MARK: - Shapes

    static let cornerRadius: CGFloat = 14
    static let tightCorner: CGFloat = 10

    /// The standard panel: gradient body, bevelled edge, and a drop shadow so
    /// it floats off the backdrop instead of being painted onto it.
    static func panel(_ radius: CGFloat = cornerRadius) -> some View {
        // The painted panel's corner ornament is 31pt on each side. Below
        // roughly twice that the four corners meet and the ornament becomes the
        // whole panel, swamping whatever it is framing — which is exactly what
        // happened to the 86pt actor plate in battle. Small panels get the
        // drawn one, which scales down cleanly.
        GeometryReader { geometry in
            let fitsPainted = geometry.size.width >= Chrome.paintedPanelMinimum
                && geometry.size.height >= Chrome.paintedPanelMinimum
            if fitsPainted, let painted = Chrome.slice("ui_panel", Chrome.panelInsets) {
                painted
                    .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 4)
            } else {
                drawnPanel(radius)
            }
        }
    }

    /// The code-drawn panel: gradient body, bevelled edge, drop shadow.
    private static func drawnPanel(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(panelPlate)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(bevel, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 4)
    }

    /// The screen background. A radial lift behind the centre keeps the middle
    /// of the screen from going dead flat under a stack of panels.
    static var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#100D22"), ink, Color(hex: "#0B0918")],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: "#2C2258").opacity(0.55), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Painted chrome

/// The painted UI kit — panels, buttons, frames — as 9-slice textures.
///
/// This is the half of the genre's look that code-drawn shapes cannot reach:
/// a carved gold frame is a painting, not a stroke. Every consumer asks here
/// first and draws its gradient fallback if the file is missing, so the kit
/// can ship one texture at a time.
///
/// Files are `@3x` so a 512px source is ~171pt logical; the cap insets below
/// are in those logical points and were measured off the art, not guessed.
/// Sum of opposite insets is the smallest size a texture can be drawn at
/// without its corners overlapping.
enum Chrome {
    private static var cache: [String: UIImage?] = [:]

    static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        let loaded = UIImage(named: name)
        cache[name] = loaded
        return loaded
    }

    /// Smallest side a painted panel may be drawn at. Below this the corner
    /// ornament from opposite sides overlaps and the panel reads as a frame
    /// with no middle.
    static let paintedPanelMinimum: CGFloat = 130

    /// ui_panel: 512² → 171pt. Corner ornament reaches ~18% in.
    static let panelInsets = EdgeInsets(top: 31, leading: 31, bottom: 31, trailing: 31)
    /// ui_button_gold: 640×192 → 213×64pt. Ornate ends are ~22% of the width.
    static let goldButtonInsets = EdgeInsets(top: 8, leading: 47, bottom: 8, trailing: 47)
    /// ui_button_dark: same size, plain ends.
    static let darkButtonInsets = EdgeInsets(top: 10, leading: 17, bottom: 10, trailing: 17)
    /// ui_ribbon: 640×128 → 213×43pt.
    static let ribbonInsets = EdgeInsets(top: 9, leading: 17, bottom: 9, trailing: 17)

    static func slice(_ name: String, _ insets: EdgeInsets) -> Image? {
        guard let ui = image(name) else { return nil }
        return Image(uiImage: ui).resizable(capInsets: insets, resizingMode: .stretch)
    }
}

// MARK: - Rarity

/// What a star grade looks like.
///
/// In this genre the frame *is* the rarity readout — a player identifies a
/// pull before reading a single word. Everything that draws a unit routes its
/// colours through here so the language is identical on a card, in a team slot
/// and on the summon reveal.
enum Rarity: Int, CaseIterable {
    case common = 1, uncommon, rare, epic, legendary, mythic

    init(stars: Int) {
        self = Rarity(rawValue: min(6, max(1, stars))) ?? .common
    }

    /// Frame metal. Two stops minimum, and the top stop is always the lighter
    /// one so the frame catches light from above like everything else.
    var frame: LinearGradient {
        LinearGradient(colors: frameStops, startPoint: .top, endPoint: .bottom)
    }

    private var frameStops: [Color] {
        switch self {
        case .common:    return [Color(hex: "#6E7590"), Color(hex: "#3B4157")]
        case .uncommon:  return [Color(hex: "#7FD6A0"), Color(hex: "#2F7A50")]
        case .rare:      return [Color(hex: "#7FC4FF"), Color(hex: "#2A5FA8")]
        case .epic:      return [Color(hex: "#C89BFF"), Color(hex: "#6B34B8")]
        case .legendary: return [Color(hex: "#FFE49B"), Color(hex: "#C08A23")]
        case .mythic:    return [Color(hex: "#FFB4C8"), Color(hex: "#FF6A3D"),
                                 Color(hex: "#C0308A")]
        }
    }

    /// The colour that bleeds out past the frame. Rarer means further.
    var glow: Color {
        switch self {
        case .common:    return Color(hex: "#6E7590")
        case .uncommon:  return Color(hex: "#4BE38F")
        case .rare:      return Color(hex: "#5FC8FF")
        case .epic:      return Color(hex: "#B478FF")
        case .legendary: return Color(hex: "#FFCB57")
        case .mythic:    return Color(hex: "#FF7BA8")
        }
    }

    var glowRadius: CGFloat {
        switch self {
        case .common, .uncommon: return 0
        case .rare: return 5
        case .epic: return 9
        case .legendary: return 13
        case .mythic: return 18
        }
    }

    var frameWidth: CGFloat { self >= .epic ? 2.5 : 1.5 }

    /// Only the top grades earn an animated sheen. If everything shimmers,
    /// nothing reads as special.
    var hasSheen: Bool { self >= .legendary }

    /// The painted frame for this grade, if it shipped. Square, with a
    /// transparent centre, designed to sit over the portrait.
    var frameImageName: String {
        switch self {
        case .common: return "ui_frame_common"
        case .uncommon: return "ui_frame_uncommon"
        case .rare: return "ui_frame_rare"
        case .epic: return "ui_frame_epic"
        case .legendary: return "ui_frame_legendary"
        case .mythic: return "ui_frame_mythic"
        }
    }

    var hasPaintedFrame: Bool { Chrome.image(frameImageName) != nil }
}

extension Rarity: Comparable {
    static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Colour parsing

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

/// A moving band of light across a surface. Used only on the rarest frames and
/// on the summon reveal, where the whole point is spectacle.
struct Sheen: View {
    var cornerRadius: CGFloat = Theme.tightCorner
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            let span = geometry.size.width + geometry.size.height
            LinearGradient(
                colors: [.clear, .white.opacity(0.42), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: span * 0.35)
            .rotationEffect(.degrees(28))
            .offset(x: phase * span)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
    }
}

extension View {
    func panelBackground(radius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(PanelBackground(radius: radius))
    }

    /// Frames a view in its rarity's metal, with the matching outer glow.
    func rarityFrame(_ rarity: Rarity, radius: CGFloat = Theme.tightCorner) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(rarity.frame, lineWidth: rarity.hasPaintedFrame ? 0 : rarity.frameWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(rarity.hasPaintedFrame ? 0 : 0.22), lineWidth: 0.5)
            )
            .shadow(color: rarity.glow.opacity(rarity.glowRadius > 0 ? 0.7 : 0),
                    radius: rarity.glowRadius, x: 0, y: 0)
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
