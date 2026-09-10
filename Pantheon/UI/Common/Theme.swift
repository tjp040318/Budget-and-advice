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

    /// The indigo wash for a raised plate that is not a panel — the island's
    /// landmark discs are the one caller left. Kept as it was;
    /// `drawnPanelPlate` is what a panel uses now.
    static let panelPlate = LinearGradient(
        colors: [surfaceHigh, surfaceRaised, surface],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The body of a code-drawn panel: the painted panel's own centre, which
    /// samples at (22, 23, 28), with just enough gradient that it does not
    /// read as a flat fill. See `drawnPanel` for why it is not `panelPlate`.
    static let drawnPanelPlate = LinearGradient(
        colors: [Color(hex: "#1E1D2A"), Color(hex: "#16151F")],
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
    /// One knob for the whole app's type. The genre runs small — a landscape
    /// phone is 430 points tall and Summoners War fits a team, a grid and a
    /// bar into it — and the first playtest asked for exactly that density.
    static let fontScale: CGFloat = 0.9

    static func display(_ size: CGFloat) -> Font {
        .system(size: size * fontScale, weight: .black, design: .default)
    }

    static func title(_ size: CGFloat = 20) -> Font {
        .system(size: size * fontScale, weight: .heavy, design: .default)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size * fontScale, weight: .medium, design: .default)
    }

    /// Numbers are monospaced so columns of stats line up, which matters more
    /// here than in most apps — the whole game is comparing two stat blocks.
    static func numeric(_ size: CGFloat = 15) -> Font {
        .system(size: size * fontScale, weight: .bold, design: .monospaced)
    }

    // MARK: - Shapes
    //
    // One scale for each of the three things a screen keeps re-deciding:
    // how round a thing is, how tall a control is, and how far content sits
    // from a panel's edge. Before this the screens carried `cornerRadius: 6`
    // in five places, 8 in four, 10 in two and 14 in two; control heights of
    // 22, 24, 26, 28, 30, 32 and 34 for the same class of object; and chip
    // padding of 3, 4, 5, 6, 7 and 9. Read the object, not the number.

    /// A panel or a sheet.
    static let cornerRadius: CGFloat = 12
    /// A card, a plate, a primary button.
    static let tightCorner: CGFloat = 8
    /// Anything control-sized. It *is* the strip's radius
    /// (`ScreenChrome.corner`), so a filter tile in the strip and a tile in
    /// the grid below it are the same shape rather than nearly the same.
    static let tileCorner: CGFloat = ScreenChrome.corner

    /// A read-only tag: a set name, a role, PASSIVE. Deliberately not the
    /// strip's 26 — the unit sheet's tag row cannot afford ten more points.
    static let chipHeight: CGFloat = 16
    /// Horizontal padding inside a chip.
    static let chipPadding: CGFloat = 6

    /// Anything tappable that sits inline in a screen's content. The same
    /// height as a control in the strip (`ScreenChrome.control`), so the two
    /// rails line up.
    static let controlHeight: CGFloat = ScreenChrome.control

    /// A screen's primary action. `PrimaryButton` measures this today — a
    /// 13pt title at `fontScale` plus its 10pt of vertical padding — so
    /// anything that calls itself a button and stands beside one should ask
    /// for this rather than guess.
    static let buttonHeight: CGFloat = 34

    /// What a panel's content has to clear horizontally.
    ///
    /// `ui_panel`'s flat gold band measures 7.4pt thick at the shipped
    /// `Chrome.shrink` scale (31 px of a 512 px @3x texture) and its corner
    /// ornament reaches further, so the bare `.padding(8)` that sits under
    /// every `Theme.panel(...)` puts the first row of content 0.6pt off the
    /// metal: a section header's title or its accessory prints on the band.
    ///
    /// Horizontal only, on purpose. A landscape frame is 430 points tall and
    /// cannot pay four more points of height per panel, so `panelPadding`
    /// stays the vertical figure. `panelContentInset()` applies both.
    static let panelInset: CGFloat = 12
    /// The vertical padding inside a panel, unchanged from what the screens
    /// already used.
    static let panelPadding: CGFloat = 8

    /// The caption block under a unit card's square portrait — name, then
    /// level and power.
    ///
    /// One expression so `UnitCard` and `EmptyTeamSlot` cannot drift apart
    /// again: the slot is `size * 1.35` today and the card is `size` plus a
    /// fixed ~27pt caption, so they agree only near size 76 and every real
    /// team row is ragged (38 gives 65 against 51 in the arena, 46 gives 73
    /// against 62 on the campaign screen, and the row's height jumps as a
    /// unit is added or removed).
    ///
    /// The 20pt floor is what two lines of text need; 0.36 is what the
    /// caption measures once its fonts scale with the card. **Both
    /// components must adopt this in one edit** — the figure assumes
    /// `UnitCard`'s caption fonts scale with `size`; while they are fixed,
    /// its caption is ~27pt whatever the card.
    static func cardCaptionHeight(for size: CGFloat) -> CGFloat {
        max(20, size * 0.36)
    }

    /// The full height of a unit card of this size, caption included.
    static func cardHeight(for size: CGFloat) -> CGFloat {
        size + cardCaptionHeight(for: size)
    }

    /// The standard panel: gradient body, bevelled edge, and a drop shadow so
    /// it floats off the backdrop instead of being painted onto it.
    ///
    /// `radius` applies to the drawn branch only — the painted texture brings
    /// its own corners, and a small panel is the only one that gets the drawn
    /// one, so a radius passed here is honoured exactly when the panel is
    /// under `Chrome.paintedPanelMinimum`.
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

    /// The code-drawn panel: near-black body, bevelled edge, gold rim, drop
    /// shadow — a smaller sibling of the painted one rather than a different
    /// object.
    ///
    /// It used to be `panelPlate`, an indigo #2A274F → #141328 with a #3B3766
    /// hairline, against the painted panel's near-black centre inside a gold
    /// frame. Nothing was shared: no fill, no border. A screen that shows both
    /// at once shows two materials — the Team Picker's Lineup panel is ~100pt
    /// and painted, the Leader skill panel under it is ~60pt and drawn, in the
    /// same 300pt rail. Matching the plate to the texture's centre also raises
    /// contrast: `textSecondary` goes from ~5.1:1 on `surfaceHigh` to ~6.1:1
    /// here.
    private static func drawnPanel(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(drawnPanelPlate)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(bevel, lineWidth: 1)
            )
            .overlay(
                // The gold edge is what answers the painted panel's band. A
                // full point rather than a hairline, or a small panel does not
                // separate from a near-black backdrop.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(goldDim.opacity(0.55), lineWidth: 1)
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

    /// The kit is drawn at 1/1.4 of its painted size: the corner ornaments
    /// and the button ends were sized for a portrait phone, and on a
    /// landscape one they ate the screen (a 31-point ornament on every side
    /// of every panel). The insets below are divided by the same number.
    static let shrink: CGFloat = 1.4

    static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        var loaded = UIImage(named: name)
        if let source = loaded, let cg = source.cgImage {
            loaded = UIImage(cgImage: cg, scale: source.scale * shrink, orientation: source.imageOrientation)
        }
        cache[name] = loaded
        return loaded
    }

    /// Smallest side a painted panel may be drawn at. Below this the corner
    /// ornament from opposite sides overlaps and the panel reads as a frame
    /// with no middle.
    static let paintedPanelMinimum: CGFloat = 130 / shrink

    private static func scaled(_ top: CGFloat, _ leading: CGFloat, _ bottom: CGFloat, _ trailing: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top / shrink, leading: leading / shrink, bottom: bottom / shrink, trailing: trailing / shrink)
    }

    /// ui_panel: 512² → 171pt at full size. Corner ornament reaches ~18% in.
    static let panelInsets = scaled(31, 31, 31, 31)
    /// ui_button_gold: 640×192 → 213×64pt at full size. Ornate ends are ~22% of the width.
    static let goldButtonInsets = scaled(8, 47, 8, 47)
    /// ui_button_dark: same size, plain ends.
    static let darkButtonInsets = scaled(10, 17, 10, 17)
    /// ui_ribbon: 640×128 → 213×43pt at full size.
    static let ribbonInsets = scaled(9, 17, 9, 17)

    /// How far in a label has to start so it does not print on the gold
    /// plate's ornate ends — the same 47/1.4 = 33.6pt the 9-slice reserves.
    /// `PrimaryButton` applies no horizontal padding at all today, so a long
    /// title (the campaign briefing's "BEGIN ×20 — 3 ENERGY EACH" in a 260pt
    /// button, against 193pt of flat middle) is centred over the scarabs.
    static var goldButtonLabelInset: CGFloat { goldButtonInsets.leading }

    /// The dark plate's ends are plain, so this is air rather than clearance.
    static let darkButtonLabelInset: CGFloat = 18

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

/// A tag: a set name, a role, an archetype, PASSIVE, a count.
///
/// One shape for what was ten. The unit sheet alone drew three of them — set
/// names at 7/3 in `body(9).bold` on `surfaceHigh`, the pantheon, archetype
/// and role tags at 6/2 on a 0.18-opacity tint, and PASSIVE at 4/1 in
/// `body(7).black` on gold at 0.25 — with 6/3, 8/3, 5/1 and 9/3 variants on
/// the Labyrinth and relic screens. Three shapes for one object on one screen.
///
/// The convention: **filled for a count or a state, unfilled for a label.**
/// The height is `Theme.chipHeight`, not the strip's `ScreenChrome.control` —
/// a chip is read, not tapped, and the tag rows it lives in have no room.
struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Theme.gold
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .black))
            }
            Text(text)
                .font(Theme.body(9).weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Theme.ink : tint)
        .padding(.horizontal, Theme.chipPadding)
        .frame(height: Theme.chipHeight)
        .background(Capsule().fill(filled ? tint : Theme.surfaceHigh))
        .overlay(
            Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.35), lineWidth: 0.5)
        )
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

    /// The inset a panel's content needs so it does not sit on the painted
    /// frame's gold band: `Theme.panelInset` across, `Theme.panelPadding`
    /// down. Replaces the bare `.padding(8)` written under every
    /// `Theme.panel(...)` / `panelBackground()`.
    func panelContentInset() -> some View {
        self
            .padding(.horizontal, Theme.panelInset)
            .padding(.vertical, Theme.panelPadding)
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

    // `screen(_ title:)` used to live here: backdrop, a UIKit navigation bar
    // and its title style. `GameScreen` replaced it on every menu and it had
    // no call sites left, so it is gone rather than waiting to be picked up
    // again — a second chrome language is exactly what this pass is for.
}
