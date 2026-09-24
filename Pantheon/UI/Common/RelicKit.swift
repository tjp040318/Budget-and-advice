import SwiftUI
import UIKit

// MARK: - The reliquary's kit (2026-09-24, Docs/PLAN.md *Relics the genre's way*)
//
// The owner, with Summoners War's rune screens beside ours: "Look how easy it
// is to see everything, and to understand what's going on. And look how clean
// and detailed the graphics are." The study behind the redesign measured why
// theirs reads and ours did not: their numbers sit on a dark well at 12–15:1,
// ours were pigments on cream at 1.5–3.5:1. So every relic screen is the
// RELIQUARY — the Hall of Ka's painting veiled to a quarter of its light
// under OPAQUE basalt panels with bronze frames — and a relic always lies on
// basalt, even on a cream plate.
//
// This file is the kit every relic screen builds from, written once before
// any screen (the builders' spec, §2): the palette and the quality colours on
// dark, the panel and the backdrop, the plates and the wells, the unit
// sheet's tablets, the dials, the rail and the roll marks, the stat ledger,
// the set line, the one confirmation card that replaces the system dialogs,
// and the stones popover. The relic tile, the socket and the rosette are in
// RelicTile.swift beside the pure reading of a relic (`RelicReading`).
//
// Two rules every part keeps: nothing is drawn under the type floors
// (`Theme`'s own), and a colour that is text on dark is one of the tokens
// below — never a cream-screen pigment, which reads as mud on basalt.

// MARK: - The palette

/// The reliquary's colours. Contrast figures are WCAG against the basalt well
/// (#15110D); every token is typed so `?:` between two of them is checked.
enum RelicPalette {
    /// The veil over the painting; behind everything.
    static let ground: Color = Color(hex: "#0E0B08")
    /// A panel's body, top to foot. The socket floor is `basaltFoot`.
    static let basaltTop: Color = Color(hex: "#1E1813")
    static let basaltFoot: Color = Color(hex: "#120E0A")
    /// A recess: dropdown wells, the main-stat well, empty slots, chips.
    static let well: Color = Color(hex: "#0B0907")
    /// The one-point lit lip at a well's foot — a recess is lit from below.
    static let wellLip: Color = Color(hex: "#6E5A30")
    /// Every metal rim, light to dark.
    static let bronzeLight: Color = Color(hex: "#F3D98A")
    static let bronzeMid: Color = Color(hex: "#C9A24A")
    static let bronze: Color = Color(hex: "#8C6D22")
    static let bronzeDark: Color = Color(hex: "#3E2E0F")
    /// A secondary plate's face.
    static let bronzeFaceTop: Color = Color(hex: "#6B5332")
    static let bronzeFaceFoot: Color = Color(hex: "#3E2E19")
    /// An unchosen tablet.
    static let tabletTop: Color = Color(hex: "#5A4128")
    static let tabletFoot: Color = Color(hex: "#34261A")
    /// Gold leaf: the chosen tablet, the draft check, a filter that is on.
    static let goldLeafTop: Color = Color(hex: "#F6DC8C")
    static let goldLeafMid: Color = Color(hex: "#D9A93F")
    static let goldLeafFoot: Color = Color(hex: "#A87618")
    /// Ink on gold leaf, 7.8:1 on its middle stop.
    static let goldInk: Color = Color(hex: "#2A1A05")
    /// Wine: Sell, and nothing else.
    static let wineTop: Color = Color(hex: "#7A2233")
    static let wineFoot: Color = Color(hex: "#3B0F18")
    static let wineRim: Color = Color(hex: "#F2939F")
    static let wineInk: Color = Color(hex: "#FFE9EC")
    /// Every number, 15.8:1.
    static let value: Color = Theme.onGlass
    /// Stat names and counts on plates, 14.2:1.
    static let label: Color = Theme.onGlassGold
    /// Secondary words, 9.9:1.
    static let dim: Color = Theme.onGlassDim
    /// An inactive set's effect, a sub still to come — 4.6:1, so 12 points
    /// and up only.
    static let quiet: Color = Color(hex: "#8F7B5E")
    /// A relic bonus, a gain, a complete set.
    static let gain: Color = Theme.onGlassSuccess
    /// A loss, a cost that is short.
    static let loss: Color = Theme.onGlassDanger
    /// A set in progress, some held.
    static let partial: Color = Theme.onGlassWarning
    /// Eyebrow labels and the numerals of empty sockets.
    static let eyebrow: Color = Theme.onGlassEyebrow
    /// Grade stars, "+15", a value at its peak.
    static let star: Color = Color(hex: "#FFD45A")
    static let starLight: Color = Color(hex: "#FFF1C2")
    static let starEdge: Color = Color(hex: "#1A1006")
    /// An awakened relic's light.
    static let halo: Color = Color(hex: "#FFE7A0")
    /// A whetstone's bonus on a sub stat.
    static let honed: Color = Color(hex: "#F0B86E")
    /// Something waits (a white rim goes round it).
    static let waitDot: Color = Color(hex: "#E0453A")

    /// A panel body, top to foot.
    static let basaltBody: LinearGradient = LinearGradient(
        colors: [basaltTop, basaltFoot], startPoint: .top, endPoint: .bottom
    )
    /// Every metal rim: light, bronze, dark, top to foot.
    static let bronzeRim: LinearGradient = LinearGradient(
        colors: [bronzeLight, bronze, bronzeDark], startPoint: .top, endPoint: .bottom
    )
    /// A secondary plate.
    static let bronzeFace: LinearGradient = LinearGradient(
        colors: [bronzeFaceTop, bronzeFaceFoot], startPoint: .top, endPoint: .bottom
    )
    /// An unchosen tablet.
    static let tabletFace: LinearGradient = LinearGradient(
        colors: [tabletTop, tabletFoot], startPoint: .top, endPoint: .bottom
    )
    /// The chosen tablet, the draft check, a slot filter that is on.
    static let goldLeaf: LinearGradient = LinearGradient(
        colors: [goldLeafTop, goldLeafMid, goldLeafFoot], startPoint: .top, endPoint: .bottom
    )
    /// Sell.
    static let wineFace: LinearGradient = LinearGradient(
        colors: [wineTop, wineFoot], startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Quality on dark

/// The quality as the relic screens draw it ON DARK. `rarity` and `inkColor`
/// (RelicInventoryView.swift) stay for cream; these are the reliquary's.
///
/// Legend is amber-orange here, not gold: gold is the chrome's own colour,
/// Legend was the least distinct quality on cream (the audit's #8), and the
/// genre's players read the ladder grey < green < blue < purple < orange.
/// `Rarity.legendary`, which the 5★ unit cards wear, keeps its gold.
extension RelicQuality {
    /// The quality as TEXT on the basalt well (8.4–11.3:1).
    var tone: Color {
        switch self {
        case .normal: return Color(hex: "#A9B0C4")
        case .magic: return Color(hex: "#4BE38F")
        case .rare: return Color(hex: "#5FC8FF")
        case .hero: return Color(hex: "#C29BFF")
        case .legend: return Color(hex: "#FFB547")
        }
    }

    /// The band inside a tile's bronze rim, and the tint of a stone's rim.
    var enamel: LinearGradient {
        LinearGradient(colors: enamelStops, startPoint: .top, endPoint: .bottom)
    }

    /// The light the stone stands in, as a radial behind it.
    var glowColor: Color {
        switch self {
        case .normal: return Color(hex: "#8A93AD")
        case .magic: return Color(hex: "#4BE38F")
        case .rare: return Color(hex: "#5FC8FF")
        case .hero: return Color(hex: "#B478FF")
        case .legend: return Color(hex: "#FF9F2E")
        }
    }

    /// How strongly `glowColor` shows, rarer brighter.
    var glowStrength: Double {
        switch self {
        case .normal: return 0.14
        case .magic: return 0.18
        case .rare: return 0.22
        case .hero: return 0.28
        case .legend: return 0.34
        }
    }

    private var enamelStops: [Color] {
        switch self {
        case .normal: return [Color(hex: "#C9CEDB"), Color(hex: "#6E7590")]
        case .magic: return [Color(hex: "#7FD6A0"), Color(hex: "#2F7A50")]
        case .rare: return [Color(hex: "#7FC4FF"), Color(hex: "#2A5FA8")]
        case .hero: return [Color(hex: "#C89BFF"), Color(hex: "#6B34B8")]
        case .legend: return [Color(hex: "#FFD27A"), Color(hex: "#D9731C")]
        }
    }
}

// MARK: - The panel and the room

/// The reliquary's OPAQUE data panel: basalt, a shade at its top, a bronze
/// rim with a dark line inside it and a lit edge inside that, and four gold
/// studs at the corners. Opaque on purpose — thirty stones seen through
/// translucent glass over a painting is busy, and the genre's panels are
/// opaque. Use it as `.background(BasaltPanel())`, with 12 points of
/// padding inside; it never takes a tap.
struct BasaltPanel: View {
    var radius: CGFloat = 12
    var studs: Bool = true

    private static let studFill: Color = Color(hex: "#E9C46A")
    private static let studEdge: Color = Color(hex: "#5C4611")

    var body: some View {
        ZStack {
            slab
            if studs {
                studLayer
            }
        }
        // One silhouette casts one shadow: without the group every layer
        // above would cast its own (the khaki socket of 2026-09-23).
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.45), radius: 8, y: 3)
        .allowsHitTesting(false)
    }

    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var slab: some View {
        ZStack {
            outline.fill(RelicPalette.basaltBody)
            topShade
            outline.strokeBorder(RelicPalette.bronzeRim, lineWidth: 1.5)
            outline.inset(by: 1.5).stroke(Color.black.opacity(0.55), lineWidth: 0.75)
            litEdge
        }
    }

    /// Black at 0.35 falling to nothing over the top 18% of the height.
    private var topShade: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.35), location: 0),
                .init(color: Color.black.opacity(0), location: 0.18),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(outline)
    }

    private var litEdge: some View {
        RoundedRectangle(cornerRadius: max(0, radius - 1), style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                               startPoint: .top, endPoint: .center),
                lineWidth: 1
            )
            .padding(2)
    }

    private var studLayer: some View {
        ZStack {
            stud(at: .topLeading)
            stud(at: .topTrailing)
            stud(at: .bottomLeading)
            stud(at: .bottomTrailing)
        }
    }

    /// A 4.2-point square turned 45° — six points across — its centre five
    /// points in from the corner.
    private func stud(at corner: Alignment) -> some View {
        Rectangle()
            .fill(Self.studFill)
            .overlay(Rectangle().stroke(Self.studEdge, lineWidth: 0.5))
            .frame(width: 4.2, height: 4.2)
            .rotationEffect(.degrees(45))
            .frame(width: 6, height: 6)
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
    }
}

/// The room behind every relic screen: the Hall of Ka's sanctuary veiled to
/// about a quarter of its light. Use it as `.background { ReliquaryBackdrop() }`
/// OUTSIDE the content's horizontal padding, so it bleeds to the glass. The
/// day a reliquary painting of its own exists, it swaps in here (`painting`).
struct ReliquaryBackdrop: View {
    static let painting = "hall_of_ka_bg"

    var body: some View {
        PlaceBackdrop(
            painting: Self.painting,
            focus: UnitPoint(x: 0.5, y: 0.55),
            wash: RelicPalette.ground.opacity(0.74),
            topScrim: 0.5,
            footScrim: 0.6
        )
    }
}

// MARK: - Wells

/// One of the genre's black property wells: an eyebrow, the set's stone when
/// the choice is one set, the value, and a chevron — the Relics screen's SET,
/// MAIN, SUB and MORE. Thirty points tall; the caller sets the width (and
/// shortens the value to fit it) and opens a popover from it.
struct RelicWellButton: View {
    let eyebrow: String
    let value: String
    var set: RelicSet? = nil
    let isActive: Bool
    let action: () -> Void

    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            wellLabel
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("\(eyebrow), \(value)")
    }

    private var wellLabel: some View {
        HStack(spacing: 6) {
            Text(eyebrow.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(0.6)
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
            if let chosen = self.set {
                RelicSetEmblem(set: chosen, size: 20)
            }
            Text(value)
                .font(Theme.body(13).weight(.bold))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(RelicPalette.eyebrow)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(wellGround)
        .contentShape(outline)
    }

    private var wellGround: some View {
        outline
            .fill(RelicPalette.well)
            .overlay(outline.strokeBorder(isActive ? RelicPalette.goldLeafMid : RelicPalette.bronze, lineWidth: 1))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(RelicPalette.wellLip)
                    .frame(height: 1)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 1)
            }
    }
}

extension RelicWellButton {
    /// The spec's short form, `RelicWellButton("SET", value: …, isActive: …)`.
    init(_ eyebrow: String, value: String, set: RelicSet? = nil, isActive: Bool, action: @escaping () -> Void) {
        self.init(eyebrow: eyebrow, value: value, set: set, isActive: isActive, action: action)
    }
}

// MARK: - Plates

/// The two materials of a secondary plate: bronze, and wine for Sell.
enum RelicPlateFinish {
    case bronze
    case wine
}

/// A plate's material alone: the bronze or wine face, a gloss, the rim and a
/// dark line inside it. Shared by the labelled and the icon plates.
private struct RelicPlateMaterial: View {
    let finish: RelicPlateFinish
    var radius: CGFloat = 8

    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        ZStack {
            outline.fill(finish == .wine ? RelicPalette.wineFace : RelicPalette.bronzeFace)
            LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)],
                           startPoint: .top, endPoint: .center)
                .clipShape(outline)
            rim
            outline.inset(by: 1.2).stroke(Color.black.opacity(0.5), lineWidth: 0.6)
        }
    }

    @ViewBuilder
    private var rim: some View {
        if finish == .wine {
            outline.strokeBorder(RelicPalette.wineRim, lineWidth: 1.2)
        } else {
            outline.strokeBorder(RelicPalette.bronzeRim, lineWidth: 1.2)
        }
    }
}

/// `RelicPlateButton`'s look without the button — for a `Menu`'s label, which
/// cannot hold a button of its own: the unit sheet's BEST SIX ▾ and the relic
/// card's TO ▾ (`trailingSystemImage: "chevron.down"`). The icon, the title
/// over its count, centred on the plate.
struct RelicPlateLabel: View {
    let title: String
    var count: String? = nil
    var countTint: Color = RelicPalette.label
    var itemKey: String? = nil
    var systemImage: String? = nil
    var finish: RelicPlateFinish = .bronze
    var height: CGFloat = 44
    var trailingSystemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            icon
            words
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(RelicPalette.eyebrow)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(RelicPlateMaterial(finish: finish))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.4), radius: 3, y: 2)
    }

    @ViewBuilder
    private var icon: some View {
        if let itemKey, ItemArt.hasPainting(itemKey) {
            ItemIcon(key: itemKey, size: 26, glow: false)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(RelicPalette.label)
        }
    }

    private var words: some View {
        VStack(spacing: 0) {
            // Its figures in Manrope: Cinzel's 1 is a Roman I ("SELL · 3").
            Text.inscribed(title.uppercased(), letters: Theme.title(13), digits: Theme.numeric(12.6))
                .tracking(1.2)
                .foregroundStyle(finish == .wine ? RelicPalette.wineInk : RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
            if let count {
                Text(count)
                    .font(Theme.numeric(12.5))
                    .foregroundStyle(countTint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Every secondary action on the relic screens: a bronze plate (wine for
/// Sell) with an icon and a title over an optional count — RELICS 214,
/// STONES 23, REVERT, ALL OFF. The gold primary is always `PrimaryButton`.
/// The press is `GamePressStyle(.plate)`, whose touch-down plays the tap, so
/// an action given here plays no tap of its own.
struct RelicPlateButton: View {
    let title: String
    var count: String? = nil
    var countTint: Color = RelicPalette.label
    var itemKey: String? = nil
    var systemImage: String? = nil
    var finish: RelicPlateFinish = .bronze
    var height: CGFloat = 44
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RelicPlateLabel(
                title: title,
                count: count,
                countTint: countTint,
                itemKey: itemKey,
                systemImage: systemImage,
                finish: finish,
                height: height
            )
        }
        .buttonStyle(GamePressStyle(.plate))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let count else { return title }
        return "\(title), \(count)"
    }
}

extension RelicPlateButton {
    /// The spec's short form, `RelicPlateButton("Revert", height: 46, …)`.
    init(
        _ title: String,
        count: String? = nil,
        countTint: Color = RelicPalette.label,
        itemKey: String? = nil,
        systemImage: String? = nil,
        finish: RelicPlateFinish = .bronze,
        height: CGFloat = 44,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(title: title, count: count, countTint: countTint, itemKey: itemKey,
                  systemImage: systemImage, finish: finish, height: height, isEnabled: isEnabled, action: action)
    }
}

/// An icon over a word: the relic card's action row (CHANGE, REMOVE, HONE,
/// REROLL, SELL) and the bag panel's small plates. At least 50 wide, and
/// flexible. The materials are `RelicPlateButton`'s.
struct RelicIconPlate: View {
    let title: String
    var itemKey: String? = nil
    var systemImage: String? = nil
    var finish: RelicPlateFinish = .bronze
    var height: CGFloat = 52
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            face
        }
        .buttonStyle(GamePressStyle(.plate))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
    }

    private var face: some View {
        VStack(spacing: 3) {
            icon
            Text(title.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(0.6)
                .foregroundStyle(finish == .wine ? RelicPalette.wineInk : RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .frame(minWidth: 50, maxWidth: .infinity)
        .frame(height: height)
        .background(RelicPlateMaterial(finish: finish))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.4), radius: 3, y: 2)
    }

    @ViewBuilder
    private var icon: some View {
        if let itemKey, ItemArt.hasPainting(itemKey) {
            ItemIcon(key: itemKey, size: 22, glow: false)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(RelicPalette.label)
        }
    }
}

extension RelicIconPlate {
    /// The spec's short form, `RelicIconPlate("Sell", itemKey: "drachma", …)`.
    init(
        _ title: String,
        itemKey: String? = nil,
        systemImage: String? = nil,
        finish: RelicPlateFinish = .bronze,
        height: CGFloat = 52,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(title: title, itemKey: itemKey, systemImage: systemImage, finish: finish,
                  height: height, isEnabled: isEnabled, action: action)
    }
}

// MARK: - The unit sheet's tablets

/// One of the unit sheet's five vertical tabs, 80 × 50: a bronze tablet with
/// its word debossed when off, gold leaf with the word embossed when on, and
/// a red dot on its corner when something on that tab waits.
struct UnitSheetTablet: View {
    let title: String
    let isOn: Bool
    let waiting: Bool
    let action: () -> Void

    private static let offInk: Color = Color(hex: "#D9C9A6")
    private static let onRim: Color = Color(hex: "#F3D98A")

    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            tablet
                .overlay(alignment: .topTrailing) {
                    if waiting {
                        WaitDot()
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let selected = isOn ? ", selected" : ""
        let pending = waiting ? ", something to do" : ""
        return "\(title) tab\(selected)\(pending)"
    }

    private var tablet: some View {
        ZStack {
            outline.fill(isOn ? RelicPalette.goldLeaf : RelicPalette.tabletFace)
            if isOn {
                LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                               startPoint: .top, endPoint: .center)
                    .clipShape(outline)
            }
            rim
            word
        }
        .frame(width: 80, height: 50)
        .contentShape(outline)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.45), radius: 3, y: 2)
    }

    @ViewBuilder
    private var rim: some View {
        if isOn {
            outline.strokeBorder(Self.onRim, lineWidth: 1.2)
        } else {
            outline.strokeBorder(RelicPalette.bronzeRim, lineWidth: 1.2)
                .opacity(0.8)
        }
    }

    /// Debossed (a dark edge above) when off, embossed (a light edge below)
    /// when on.
    @ViewBuilder
    private var word: some View {
        if isOn {
            Text(title.uppercased())
                .font(Theme.title(13))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.goldInk)
                .shadow(color: Color.white.opacity(0.45), radius: 0, y: 0.6)
                .lineLimit(1)
                .fixedSize()
        } else {
            Text(title.uppercased())
                .font(Theme.title(13))
                .tracking(0.8)
                .foregroundStyle(Self.offInk)
                .shadow(color: Color.black.opacity(0.6), radius: 0, y: -0.6)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// The fluted bronze column the tablets hang on: six points wide, lit down
/// its middle, with two flutes. It never takes a tap.
struct TabletRod: View {
    let height: CGFloat

    private static let shade: Color = Color(hex: "#6B5332")
    private static let light: Color = Color(hex: "#C9A24A")
    private static let fluteInk: Color = Color(hex: "#3E2E0F")

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Self.shade, Self.light, Self.shade],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    flute(at: 1.5)
                    flute(at: 4.5)
                }
            }
            .frame(width: 6, height: height)
            .allowsHitTesting(false)
    }

    /// A 0.75-point line centred `centre` points from the rod's leading edge.
    private func flute(at centre: CGFloat) -> some View {
        Rectangle()
            .fill(Self.fluteInk.opacity(0.6))
            .frame(width: 0.75)
            .offset(x: centre - 0.375)
    }
}

/// Something waits: a red dot with a white rim, twelve points, or eighteen
/// with a count in it.
struct WaitDot: View {
    var count: Int? = nil

    var body: some View {
        let side: CGFloat = count == nil ? 12 : 18
        return ZStack {
            Capsule().fill(RelicPalette.waitDot)
            Capsule().strokeBorder(Color.white, lineWidth: 1.5)
            if let count {
                Text("\(count)")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 4)
            }
        }
        .frame(minWidth: side)
        .frame(height: side)
        .fixedSize(horizontal: true, vertical: false)
        .shadow(color: Color.black.opacity(0.4), radius: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\($0) waiting" } ?? "Something waiting")
    }
}

// MARK: - Numbers

/// A number that is about to change, on a well: an eyebrow over "4 → 5" or
/// "+93 → +112", the new figure in the gain green. Fifty-four points tall,
/// flexible width.
struct NumberPlate: View {
    let eyebrow: String
    let before: String
    var after: String? = nil

    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(eyebrow.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
            figures
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(outline.fill(RelicPalette.well))
        .overlay(outline.strokeBorder(RelicPalette.bronze, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var figures: some View {
        HStack(spacing: 8) {
            Text(before)
                .font(Theme.numeric(20).weight(.heavy))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
            if let after {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(RelicPalette.eyebrow)
                Text(after)
                    .font(Theme.numeric(20).weight(.heavy))
                    .foregroundStyle(RelicPalette.gain)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var spoken: String {
        guard let after else { return "\(eyebrow), \(before)" }
        return "\(eyebrow), \(before) to \(after)"
    }
}

extension NumberPlate {
    /// The spec's short form, `NumberPlate("SUB STATS", "4", "5")`.
    init(_ eyebrow: String, _ before: String, _ after: String? = nil) {
        self.init(eyebrow: eyebrow, before: before, after: after)
    }
}

/// A power-up's odds as a ring, 48 × 48: green when sure, gold from 60%,
/// rose below, the percentage in the middle.
struct OddsDial: View {
    let chance: Double

    private static let track: Color = Color(hex: "#3A2E20")

    private var clamped: Double { max(0, min(1, chance)) }
    private var percent: Int { Int((clamped * 100).rounded()) }

    private var tint: Color {
        if clamped >= 1 { return RelicPalette.gain }
        return clamped >= 0.6 ? RelicPalette.star : RelicPalette.loss
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Self.track, lineWidth: 4)
                .padding(2)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
            // "100%" is 38 points at 15: a hair of tracking keeps it off
            // the ring's inner edge (40 across).
            Text("\(percent)%")
                .font(Theme.numeric(15))
                .tracking(-0.3)
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 48, height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Success chance \(percent) percent")
    }
}

extension OddsDial {
    /// The spec's short form, `OddsDial(chance)`.
    init(_ chance: Double) {
        self.init(chance: chance)
    }
}

/// How well a relic fits a role, as a ring — the old `EfficiencyDial`'s
/// thresholds on dark: green from 70%, gold from 45%, dim below. Forty
/// points by default; 28 in a row.
struct RelicFitDial: View {
    let value: Double
    var size: CGFloat = 40

    private static let track: Color = Color(hex: "#3A2E20")

    private var clamped: Double { max(0, min(1, value)) }
    private var percent: Int { Int((clamped * 100).rounded()) }
    /// Three points at 40, two and a half at 28.
    private var lineWidth: CGFloat { max(2.5, min(3, size * 0.075)) }

    private var tint: Color {
        if clamped >= 0.7 { return RelicPalette.gain }
        return clamped >= 0.45 ? RelicPalette.star : RelicPalette.dim
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Self.track, lineWidth: lineWidth)
                .padding(lineWidth / 2)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
            Text("\(percent)%")
                .font(Theme.numeric(11.5))
                .tracking(-0.2)
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fit \(percent) percent")
    }
}

extension RelicFitDial {
    /// The spec's short form, `RelicFitDial(best.value, size: 28)`.
    init(_ value: Double, size: CGFloat = 40) {
        self.init(value: value, size: size)
    }
}

/// A relic's level as a rail, sixteen points tall: a well channel filled with
/// gold leaf to the level, a stud at +3, +6, +9 and +12 (lit once reached —
/// the levels that roll a sub stat), a ring round the next level, and a crown
/// just past the end that lights at +15.
struct LevelRail: View {
    let level: Int
    var maxLevel: Int = 15

    private static let studShut: Color = Color(hex: "#2A2119")
    private static let studEdge: Color = Color(hex: "#5C4611")
    private static let studLevels: [Int] = [3, 6, 9, 12]

    private var top: Int { max(1, maxLevel) }
    private var reached: Int { max(0, min(top, level)) }

    var body: some View {
        HStack(spacing: 5) {
            GeometryReader { proxy in
                channel(width: proxy.size.width)
            }
            .frame(height: 16)
            Image(systemName: "crown.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(reached >= top ? RelicPalette.star : RelicPalette.dim)
        }
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(reached) of \(top)")
    }

    /// Where a level stands along a channel `width` wide.
    private func stepX(_ step: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(step) / CGFloat(top)
    }

    private func channel(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(RelicPalette.well)
                .overlay(Capsule().strokeBorder(RelicPalette.bronzeDark, lineWidth: 1))
                .frame(width: width, height: 8)
            if reached > 0 {
                Capsule()
                    .fill(RelicPalette.goldLeaf)
                    .frame(width: max(8, stepX(reached, width: width)), height: 8)
            }
            ForEach(Self.studLevels, id: \.self) { step in
                stud(lit: reached >= step)
                    .position(x: stepX(step, width: width), y: 8)
            }
            if reached + 1 < top {
                Circle()
                    .stroke(RelicPalette.star.opacity(0.9), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .position(x: stepX(reached + 1, width: width), y: 8)
            }
        }
        .frame(width: width, height: 16)
    }

    @ViewBuilder
    private func stud(lit: Bool) -> some View {
        if lit {
            Circle()
                .fill(RelicPalette.star)
                .overlay(Circle().strokeBorder(Self.studEdge, lineWidth: 1))
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(Self.studShut)
                .overlay(Circle().strokeBorder(RelicPalette.bronze, lineWidth: 1))
                .frame(width: 10, height: 10)
        }
    }
}

/// How many times a sub stat has rolled, as five diamonds (52 points wide):
/// the lit ones gold, the rest dark. `nil` — a gemmed sub, whose rolls went
/// with the gem — draws nothing and takes no width. The counts are read off
/// the values (`RelicReading.rollCounts`); nothing stores them.
struct RollMarks: View {
    let count: Int?

    private static let shut: Color = Color(hex: "#3A2E20")

    var body: some View {
        if let count {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    diamond(lit: index < count)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count == 1 ? "1 roll" : "\(count) rolls")
        }
    }

    private func diamond(lit: Bool) -> some View {
        Rectangle()
            .fill(lit ? RelicPalette.star : Self.shut)
            .overlay(Rectangle().stroke(RelicPalette.starEdge, lineWidth: 0.8))
            .frame(width: 5.7, height: 5.7)
            .rotationEffect(.degrees(45))
            .frame(width: 8, height: 8)
    }
}

// MARK: - The stat ledger

/// One line of a stat ledger: the stat, its value, and what changes it.
struct StatLedgerRow {
    let label: String
    let value: String
    let change: String?
    let tone: LedgerTone
}

/// What colour a ledger's change reads in.
enum LedgerTone {
    case gain
    case loss
    case none
}

/// The unit sheet's single column (`info`) or Manage's two columns
/// (`manage`).
enum StatLedgerStyle {
    case info
    case manage
}

/// A unit's stats as the genre prints them: fixed columns of name, value and
/// change, so the eye runs down the numbers. `.info` is one column of eight
/// rows of 20 with a 6-point break after the fourth; `.manage` is two columns
/// of four rows of 19 — rows 0–3 then 4–7 — 284 points in all. Every text
/// takes its own width: a rare seven-character change overhangs into the gap
/// rather than being cut.
struct StatLedger: View {
    let rows: [StatLedgerRow]
    let style: StatLedgerStyle

    var body: some View {
        Group {
            switch style {
            case .info:
                infoColumn
            case .manage:
                manageColumns
            }
        }
    }

    // MARK: .info

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.prefix(4).enumerated()), id: \.offset) { _, row in
                    infoRow(row)
                }
            }
            if rows.count > 4 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.dropFirst(4).enumerated()), id: \.offset) { _, row in
                        infoRow(row)
                    }
                }
            }
        }
    }

    private func infoRow(_ row: StatLedgerRow) -> some View {
        HStack(spacing: 0) {
            Text(row.label)
                .font(Theme.body(13).weight(.semibold))
                .foregroundStyle(RelicPalette.label)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 76, alignment: .leading)
            Text(row.value)
                .font(Theme.numeric(16))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 58, alignment: .trailing)
            Color.clear
                .frame(width: 8, height: 1)
            changeText(row, font: Theme.numeric(14))
                .frame(width: 56, alignment: .leading)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(row))
    }

    // MARK: .manage

    private var manageColumns: some View {
        HStack(alignment: .top, spacing: 6) {
            manageColumn(Array(rows.prefix(4)))
            manageColumn(Array(rows.dropFirst(4).prefix(4)))
        }
    }

    private func manageColumn(_ column: [StatLedgerRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(column.enumerated()), id: \.offset) { _, row in
                manageCell(row)
            }
        }
        .frame(width: 139, alignment: .topLeading)
    }

    private func manageCell(_ row: StatLedgerRow) -> some View {
        HStack(spacing: 2) {
            Text(row.label)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(RelicPalette.label)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 58, alignment: .leading)
            Text(row.value)
                .font(Theme.numeric(13))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 41, alignment: .trailing)
            changeText(row, font: Theme.numeric(11.5))
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 19)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(row))
    }

    // MARK: Shared

    @ViewBuilder
    private func changeText(_ row: StatLedgerRow, font: Font) -> some View {
        if let change = row.change {
            Text(change)
                .font(font)
                .foregroundStyle(Self.tint(row.tone))
                .lineLimit(1)
                .fixedSize()
        } else {
            Color.clear
                .frame(height: 1)
        }
    }

    private static func tint(_ tone: LedgerTone) -> Color {
        switch tone {
        case .gain: return RelicPalette.gain
        case .loss: return RelicPalette.loss
        case .none: return RelicPalette.dim
        }
    }

    private static func spoken(_ row: StatLedgerRow) -> String {
        guard let change = row.change else { return "\(row.label) \(row.value)" }
        return "\(row.label) \(row.value), \(change)"
    }
}

// MARK: - A set's line

/// A set's line in its two sizes: `.full`, 40 tall, the name over its short
/// effect; `.compact`, 26 tall, all on one line.
enum SetEffectStyle {
    case full
    case compact
}

/// A set as the genre shows it where it matters: its stone, its name, how
/// many pieces the unit wears of it ("2/2 ✓", "1/4"), and its effect in two
/// or three words (`RelicReading.shortEffect`). A complete set glows and
/// reads in full strength; one in progress is amber; an inactive effect is
/// quiet. With no unit (`piecesOnUnit: nil`) the count is left out and the
/// line reads at full strength — it describes the set, not a build. `onInfo`
/// adds the "i" that opens the set reference.
struct SetEffectRow: View {
    let set: RelicSet
    let piecesOnUnit: Int?
    let style: SetEffectStyle
    var onInfo: (() -> Void)? = nil

    private var pieces: Int { piecesOnUnit ?? 0 }
    private var needed: Int { max(1, self.set.piecesRequired) }
    private var complete: Bool { pieces >= needed }
    private var completions: Int { pieces / needed }
    /// A line with no unit describes the set, so it reads at full strength.
    private var reads: Bool { complete || piecesOnUnit == nil }

    var body: some View {
        Group {
            switch style {
            case .full:
                fullRow
            case .compact:
                compactRow
            }
        }
    }

    // MARK: .full

    private var fullRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                emblem(28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        name
                        Spacer(minLength: 4)
                        countLabel
                    }
                    effect
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            infoButton
        }
        .frame(height: 40)
    }

    // MARK: .compact

    private var compactRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                emblem(22)
                name
                countLabel
                Spacer(minLength: 6)
                effect
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            infoButton
        }
        .frame(height: 26)
    }

    // MARK: Parts

    @ViewBuilder
    private func emblem(_ side: CGFloat) -> some View {
        if complete {
            RelicSetEmblem(set: self.set, size: side)
                .compositingGroup()
                .shadow(color: RelicPalette.star.opacity(0.6), radius: 5)
        } else {
            RelicSetEmblem(set: self.set, size: side)
        }
    }

    private var name: some View {
        Text(self.set.displayName.uppercased())
            .font(Theme.title(13))
            .foregroundStyle(reads ? RelicPalette.value : RelicPalette.dim)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var countLabel: some View {
        if piecesOnUnit != nil {
            HStack(spacing: 2) {
                Text("\(pieces)/\(needed)")
                    .font(Theme.numeric(12))
                    .lineLimit(1)
                    .fixedSize()
                if complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                }
            }
            .foregroundStyle(countTint)
        }
    }

    private var countTint: Color {
        if complete { return RelicPalette.gain }
        return pieces > 0 ? RelicPalette.partial : RelicPalette.dim
    }

    private var effect: some View {
        Text(RelicReading.shortEffect(self.set))
            .font(Theme.body(12).weight(.semibold))
            .foregroundStyle(reads ? RelicPalette.label : RelicPalette.quiet)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var infoButton: some View {
        if let onInfo {
            Button(action: onInfo) {
                ZStack {
                    Circle().strokeBorder(RelicPalette.eyebrow, lineWidth: 1.2)
                    Text("i")
                        .font(Theme.body(11).weight(.black))
                        .foregroundStyle(RelicPalette.eyebrow)
                }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .buttonStyle(GamePressStyle(.medallion))
            .accessibilityLabel("About the \(self.set.displayName) set")
        }
    }

    private var spoken: String {
        let effectWords = RelicReading.shortEffect(self.set)
        guard piecesOnUnit != nil else { return "\(self.set.displayName) set, \(effectWords)" }
        let state = complete ? (completions > 1 ? "complete twice" : "complete") : "not complete"
        return "\(self.set.displayName) set, \(pieces) of \(needed) pieces, \(state), \(effectWords)"
    }
}

// MARK: - The confirmation card

/// What a relic screen asks before it does something that cannot be undone.
/// It replaces the five system confirmation dialogs the relic screens had:
/// bulk sell, single sell, reappraise, awaken, and the drop card's sell —
/// plus Manage's "leave with a draft".
enum RelicConfirm: Equatable {
    case sell(relics: [Relic], total: Int)
    case reappraise(relic: Relic, cost: Int)
    case awaken(relic: Relic, paying: Element)
    case leaveDraft(changes: Int)
}

extension RelicConfirm {
    /// The card's carved title: "SELL 3 RELICS", "REROLL SUB STATS",
    /// "AWAKEN THIS RELIC", "2 CHANGES NOT APPLIED".
    var title: String {
        switch self {
        case .sell(let relics, _):
            return relics.count == 1 ? "Sell 1 relic" : "Sell \(relics.count) relics"
        case .reappraise:
            return "Reroll sub stats"
        case .awaken:
            return "Awaken this relic"
        case .leaveDraft(let changes):
            return changes == 1 ? "1 change not applied" : "\(changes) changes not applied"
        }
    }
}

/// The game's own confirmation, over the screen that asked: the room dimmed
/// to 0.6 black (a tap on it cancels), and a basalt card at most 380 wide
/// with a carved title, what is about to happen as tiles and numbers rather
/// than a sentence, and two halves — Cancel (Leave, for a draft) and the
/// confirm: gold, or wine for a sale.
///
/// Present it as an overlay the size of the screen, `if let confirm {
/// RelicConfirmCard(confirm: confirm) { … } onCancel: { … } }`. The card
/// rises from 0.94 with a fade on `Motion.pop` by itself; both answers (and
/// the dimmed room) are delivered inside `withAnimation(Motion.exit)`, so the
/// caller's `confirm = nil` fades it out. The sale's plate plays the confirm
/// sound `PrimaryButton` plays; the caller adds any haptic.
struct RelicConfirmCard: View {
    let confirm: RelicConfirm
    let onConfirm: () -> Void
    let onCancel: () -> Void
    /// A tap on the dimmed room: no answer, the card away and the screen
    /// kept. It is `onCancel` when not given, which keeps the screen for
    /// every card but the draft's, whose cancel is LEAVE: a stray tap
    /// beside that card threw the draft away (the review of 2026-09-24).
    var onStay: (() -> Void)? = nil

    @EnvironmentObject private var store: GameStore
    @State private var cardRisen = false

    /// The card's corner, and its widest.
    private static let corner: CGFloat = 12
    private static let widest: CGFloat = 380

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                scrim
                card(width: min(Self.widest, max(0, proxy.size.width - 48)))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(Motion.pop) {
                cardRisen = true
            }
        }
    }

    private var scrim: some View {
        Color.black
            .opacity(cardRisen ? 0.6 : 0)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                answer(onStay ?? onCancel)
            }
            .accessibilityLabel("Close")
            .accessibilityAddTraits(.isButton)
    }

    private func card(width: CGFloat) -> some View {
        VStack(spacing: 12) {
            header
            details
            buttons
        }
        .padding(16)
        .frame(width: width)
        .background(BasaltPanel(radius: Self.corner))
        // A tap on the card's own ground is not a tap on the room behind it:
        // the panel never takes one, so the card holds them here.
        .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .onTapGesture {}
        .scaleEffect(cardRisen ? 1 : 0.94)
        .opacity(cardRisen ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Delivers an answer inside the exit curve, so the caller's state change
    /// takes the card away on it.
    private func answer(_ action: () -> Void) {
        withAnimation(Motion.exit) {
            action()
        }
    }

    private var header: some View {
        // One line at its own width: the longest, "12 CHANGES NOT APPLIED",
        // is about 250 of the card's 348 points.
        Text.inscribed(confirm.title.uppercased(), letters: Theme.title(15), digits: Theme.numeric(14.5))
            .tracking(1.2)
            .carved(glow: false)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var details: some View {
        switch confirm {
        case .sell(let relics, let total):
            sellDetails(relics, total: total)
        case .reappraise(let relic, let cost):
            reappraiseDetails(relic, cost: cost)
        case .awaken(let relic, let paying):
            awakenDetails(relic, paying: paying)
        case .leaveDraft:
            EmptyView()
        }
    }

    // MARK: Sell

    /// Eight tiles fit the card's 348 points (323); past eight, seven and a
    /// chip for the rest, so the row never runs past the rim.
    private func sellDetails(_ relics: [Relic], total: Int) -> some View {
        let shown: [Relic] = relics.count <= 8 ? relics : Array(relics.prefix(7))
        let rest = relics.count - shown.count
        return VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(shown) { relic in
                    RelicTile(relic: relic, size: .small)
                }
                if rest > 0 {
                    moreChip(rest)
                }
            }
            .padding(.top, 4)
            HStack(spacing: 8) {
                ItemIcon(key: "drachma", size: 26)
                Text("+\(total.formatted())")
                    .font(Theme.numeric(22).weight(.heavy))
                    .foregroundStyle(RelicPalette.star)
                    .lineLimit(1)
                    .fixedSize()
            }
            wearersLine(relics)
        }
    }

    private func moreChip(_ rest: Int) -> some View {
        Text("+\(rest)")
            .font(Theme.numeric(11.5))
            .foregroundStyle(RelicPalette.dim)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(RelicPalette.well))
            .overlay(Capsule().strokeBorder(RelicPalette.bronze, lineWidth: 1))
    }

    /// The faces of the units whose relics come off, up to four.
    @ViewBuilder
    private func wearersLine(_ relics: [Relic]) -> some View {
        let wearers = Self.wearerIDs(relics).compactMap { store.resolved($0) }
        if !wearers.isEmpty {
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ForEach(Array(wearers.prefix(4))) { unit in
                        WearerBadge(unit: unit, size: 20)
                    }
                }
                Text("come off")
                    .font(Theme.body(12))
                    .foregroundStyle(RelicPalette.dim)
            }
        }
    }

    /// Each wearer once, in the order their relics were given.
    private static func wearerIDs(_ relics: [Relic]) -> [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for relic in relics {
            guard let wearer = relic.equippedBy, !seen.contains(wearer) else { continue }
            seen.insert(wearer)
            ordered.append(wearer)
        }
        return ordered
    }

    // MARK: Reroll

    private func reappraiseDetails(_ relic: Relic, cost: Int) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                RelicTile(relic: relic, size: .medium)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(RelicPalette.value)
                        Text("SUBS ROLL AGAIN")
                            .font(Theme.body(12).weight(.black))
                            .foregroundStyle(RelicPalette.value)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    keptLine
                }
                Spacer(minLength: 0)
            }
            CostWell(key: "drachma", amount: cost, affordable: store.player.wallet.drachma >= cost, height: 40)
        }
    }

    private var keptLine: some View {
        HStack(spacing: 4) {
            Text("KEPT")
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .fixedSize()
            ForEach(["MAIN", "LEVEL", "SET", "SLOT"], id: \.self) { word in
                Text(word)
                    .font(Theme.body(11).weight(.black))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Capsule().fill(RelicPalette.well))
            }
        }
    }

    // MARK: Awaken

    private func awakenDetails(_ relic: Relic, paying: Element) -> some View {
        let cost = RelicService.awakeningCost(for: relic, paying: paying)
        let elementalID = Aether.id(for: paying)
        let kind = relic.mainStat.kind
        let now = RelicReading.peakMain(relic, awakened: false)
        let then = RelicReading.peakMain(relic, awakened: true)
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                RequirementTile(key: elementalID, have: Aether.count(elementalID, player: store.player),
                                need: cost.elemental, size: 48)
                RequirementTile(key: Aether.pure, have: Aether.count(Aether.pure, player: store.player),
                                need: cost.pure, size: 48)
            }
            HStack(spacing: 8) {
                NumberPlate(eyebrow: "Sub stats", before: "\(relic.subStats.count)",
                            after: "\(relic.subStats.count + 1)")
                NumberPlate(eyebrow: "\(kind.displayName) at +15", before: "+\(kind.format(now.value))",
                            after: "+\(kind.format(then.value))")
            }
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 8) {
            RelicPlateButton(title: cancelTitle, height: PrimaryButton.height) {
                answer(onCancel)
            }
            confirmButton
        }
    }

    private var cancelTitle: String {
        if case .leaveDraft = confirm { return "Leave" }
        return "Cancel"
    }

    @ViewBuilder
    private var confirmButton: some View {
        switch confirm {
        case .sell:
            RelicPlateButton(title: "Sell", finish: .wine, height: PrimaryButton.height) {
                AudioLibrary.shared.play(.uiConfirm, volume: 0.7)
                answer(onConfirm)
            }
        case .leaveDraft:
            PrimaryButton(title: "Apply") {
                answer(onConfirm)
            }
        case .reappraise, .awaken:
            PrimaryButton(title: "Confirm") {
                answer(onConfirm)
            }
        }
    }
}

// MARK: - The stones

/// The six stones the player holds — WHETSTONE and GEM, three tiers each —
/// as painted tiles with their counts, and where they come from. Opened from
/// the unit sheet's STONES plate as a popover; it keeps itself a popover on a
/// phone and wears the basalt to its edges.
struct RelicStonesPopover: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            stoneRow(.whetstone)
            stoneRow(.gem)
            Text("Hone & gem on a relic's card · from the Titans, Hell bosses, deep Labyrinth floors and the Tower")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(RelicPalette.basaltFoot)
        .presentationBackground(RelicPalette.basaltFoot)
        .presentationCompactAdaptation(.popover)
    }

    private func stoneRow(_ kind: RelicStone.Kind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.displayName.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
            HStack(spacing: 10) {
                ForEach(RelicStone.Tier.allCases, id: \.self) { tier in
                    stoneTile(RelicStone(kind: kind, tier: tier))
                }
            }
        }
    }

    private func stoneTile(_ stone: RelicStone) -> some View {
        let held = RelicService.stoneCount(stone, player: store.player)
        let socket = RoundedRectangle(cornerRadius: 48 * 0.18, style: .continuous)
        return VStack(spacing: 1) {
            ZStack {
                socket.fill(Theme.socketFill)
                socket.strokeBorder(Theme.bronzeFrame, lineWidth: 1)
                ItemIcon(key: stone.id, size: 38, glow: false)
            }
            .frame(width: 48, height: 48)
            Text("×\(held)")
                .font(Theme.numeric(12.5))
                .foregroundStyle(held > 0 ? RelicPalette.value : RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
            Text(stone.tier.displayName)
                .font(Theme.body(11))
                .foregroundStyle(stone.tier.quality.tone)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stone.displayName), \(held) held")
    }
}
