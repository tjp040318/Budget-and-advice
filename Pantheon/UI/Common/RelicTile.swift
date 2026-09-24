import SwiftUI
import UIKit

// MARK: - One relic, one anatomy (2026-09-24, Docs/PLAN.md *Relics the genre's way*)
//
// The genre's rune tile says five things with no words at 46 points: the
// grade as stars riding its top edge, the level at the bottom left, the set
// in the stone, the slot, and the wearer's face at the bottom right — and it
// is the same tile in the flower, in Before/After and in the grid. Ours was
// a 38-point stone with 5-point stars under it and three badges crowding its
// corners, and the unit sheet's ring drew no stars at all. So every grid,
// row and card draws `RelicTile`, the rosette draws `RelicSocket`s round the
// Boon, and what a relic's numbers MEAN — how often a sub has rolled, what a
// set does in two words, what the next level brings — is `RelicReading`,
// pure and tested. The kit's other parts are in RelicKit.swift.

// MARK: - The tile

/// The tile's three sizes: 60 points for a card's header and the bag panel,
/// 48 in a grid, 36 in a NOW/THEN row. Every measure of the tile is a
/// fraction of the side (the builders' spec §3.1).
enum RelicTileSize: CaseIterable {
    case large
    case medium
    case small

    /// The square's side.
    var side: CGFloat {
        switch self {
        case .large: return 60
        case .medium: return 48
        case .small: return 36
        }
    }

    var cornerRadius: CGFloat { side * 0.16 }
    /// The bronze rim, outermost.
    var rimWidth: CGFloat { self == .small ? 1.2 : 1.5 }
    /// The quality's enamel band inside the rim.
    var enamelWidth: CGFloat { self == .small ? 1.5 : 2 }
    /// The painted stone, centred at 0.53 of the side.
    var stoneSide: CGFloat { side * 0.74 }
    /// "+15", never under the numeric floor.
    var levelPoint: CGFloat { max(11.5, side * 0.25) }
    var levelOutline: CGFloat {
        switch self {
        case .large: return 1.4
        case .medium: return 1.2
        case .small: return 1.0
        }
    }
    /// The wearer's face at the bottom right.
    var wearerSide: CGFloat { side * 0.36 }
    /// The slot numeral at the left.
    var slotPoint: CGFloat { self == .large ? 13 : 11.5 }
    /// The lock, check or ring at the right, never under twelve points.
    var markSide: CGFloat { max(12, side * 0.3) }
    /// The gold selection ring and how far outside the tile it stands.
    var ringWidth: CGFloat { self == .small ? 1.5 : 2 }
    var ringOffset: CGFloat { self == .small ? 2 : 2.5 }
}

/// The badge on a tile's right edge: nothing, a lock, the draft's gold check
/// (Manage: this relic goes on when Apply is pressed), or select mode's
/// check (chosen) or hollow ring (not).
enum RelicTileMark: Equatable {
    case none
    case locked
    case inDraft
    case selectable(Bool)
}

/// A relic as one object, the same in every grid, row and card: the bronze
/// rim, the quality's enamel band, a basalt floor lit in the quality's colour
/// (and the halo when awakened), the painted stone with its tinted rim, the
/// level at the bottom left ("+15" in star gold), the slot at the left when
/// the grid is not filtered to one slot, the wearer's face at the bottom
/// right, the mark on the right, and the grade as six packed stars riding
/// the top edge. A gold ring when selected, a halo ring when awakened, and a
/// gold flare the caller animates when a power-up lands.
///
/// It is NOT a button: the caller wraps it (the whole square is the tap
/// target). The static layers are one drawing group — a grid of forty tiles
/// is otherwise 360 outlined texts — padded so the stars above the top edge
/// and the face past the corner are inside it; the rings and the flare are
/// outside it. `dimmed` (a locked relic in select mode) fades all but the
/// mark.
struct RelicTile: View {
    let relic: Relic
    var size: RelicTileSize = .medium
    /// The face in the bottom-right corner.
    var wearer: ResolvedUnit? = nil
    /// The slot numeral on the left.
    var showsSlot: Bool = false
    /// The badge on the right.
    var mark: RelicTileMark = .none
    /// The gold ring.
    var isSelected: Bool = false
    /// 0.42, for a locked relic in select mode.
    var dimmed: Bool = false
    /// The power-up's gold flash, animated in and out by the caller.
    var flare: Bool = false

    /// The point size of the grade's stars: six packed stars exactly span
    /// the side (8.1, 6.5 and 4.9 points).
    static func starPoint(for size: RelicTileSize) -> CGFloat {
        size.side / (6 * StarRow.packedAdvance)
    }

    private static let edgeInk: Color = Color(hex: "#120C06")
    private static let ringGold: Color = Color(hex: "#FFE08A")

    private var side: CGFloat { size.side }
    private var quality: RelicQuality { relic.resolvedQuality }

    var body: some View {
        // Room round the square for what rides past its edges — the stars'
        // half above the top, the face past the corner — so the drawing
        // group, which clips to its own bounds, keeps them.
        let room: CGFloat = max(8, side * 0.2)
        return layered
            .padding(room)
            .drawingGroup()
            .padding(-room)
            .shadow(color: RelicPalette.star.opacity(flare ? 0.9 : 0), radius: flare ? side * 0.25 : 0)
            .overlay { outerRings }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RelicReading.spokenTile(relic, wearerName: wearer?.name))
    }

    // MARK: Layers 1–11 (the drawing group)

    private var layered: some View {
        ZStack {
            dimmable
                .opacity(dimmed ? 0.42 : 1)
            markLayer
        }
        .frame(width: side, height: side)
    }

    private var dimmable: some View {
        ZStack {
            face
            levelLabel
            slotNumeral
            wearerBadge
        }
        .frame(width: side, height: side)
        .overlay(alignment: .top) {
            stars
        }
    }

    /// Rim, enamel, floor and stone.
    private var face: some View {
        let corner = size.cornerRadius
        let rim = size.rimWidth
        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(RelicPalette.bronzeRim)
            RoundedRectangle(cornerRadius: max(0, corner - rim), style: .continuous)
                .fill(quality.enamel)
                .padding(rim)
            basaltFloor
                .padding(rim + size.enamelWidth)
            RelicStoneArt(relic: relic, side: size.stoneSide, glyphPoint: side * 0.42)
                .position(x: side / 2, y: side * 0.53)
        }
        .frame(width: side, height: side)
    }

    /// The basalt floor, lit from behind the stone in the quality's colour
    /// and, when awakened, the halo's.
    private var basaltFloor: some View {
        let inset = size.rimWidth + size.enamelWidth
        let floorShape = RoundedRectangle(cornerRadius: max(0, size.cornerRadius - inset), style: .continuous)
        let centre = UnitPoint(x: 0.5, y: 0.53)
        return ZStack {
            floorShape.fill(RelicPalette.basaltBody)
            RadialGradient(colors: [quality.glowColor.opacity(quality.glowStrength), Color.clear],
                           center: centre, startRadius: 0, endRadius: side * 0.48)
            if relic.isAwakened {
                RadialGradient(colors: [RelicPalette.halo.opacity(0.42), Color.clear],
                               center: centre, startRadius: 0, endRadius: side * 0.46)
            }
        }
        .clipShape(floorShape)
    }

    /// "+12" at the bottom left, outlined; star gold at +15; none at +0.
    @ViewBuilder
    private var levelLabel: some View {
        if relic.level > 0 {
            OutlinedText(
                text: "+\(relic.level)",
                font: Theme.numeric(size.levelPoint).weight(.black),
                fill: relic.level >= relic.maxLevel ? RelicPalette.star : Color.white,
                edge: Self.edgeInk,
                width: size.levelOutline
            )
            .fixedSize()
            .padding(.leading, side * 0.06)
            .padding(.bottom, side * 0.04)
            .frame(width: side, height: side, alignment: .bottomLeading)
        }
    }

    /// The slot at the left edge, its centre level with the stone's.
    @ViewBuilder
    private var slotNumeral: some View {
        if showsSlot {
            OutlinedText(
                text: "\(relic.slot)",
                font: Theme.numeric(size.slotPoint).weight(.black),
                fill: RelicPalette.value,
                edge: Self.edgeInk,
                width: 1.0
            )
            .fixedSize()
            .padding(.leading, side * 0.05)
            .frame(width: side, height: side, alignment: .leading)
            .offset(y: side * 0.03)
        }
    }

    /// The wearer's face, overhanging the bottom-right corner a little.
    @ViewBuilder
    private var wearerBadge: some View {
        if let wearer {
            WearerBadge(unit: wearer, size: size.wearerSide)
                .frame(width: side, height: side, alignment: .bottomTrailing)
                .offset(x: side * 0.04, y: side * 0.04)
        }
    }

    /// The grade: six packed stars at most, their middle on the top edge.
    private var stars: some View {
        let point = Self.starPoint(for: size)
        return StarRow(stars: relic.grade, size: point, packed: true)
            .shadow(color: RelicPalette.starEdge, radius: 0.8)
            .offset(y: -point * StarRow.packedBox / 2)
    }

    // MARK: The mark

    /// On the right edge, its centre at 0.4 of the side.
    private var markCentre: CGPoint {
        CGPoint(x: side - side * 0.04 - size.markSide / 2, y: side * 0.40)
    }

    @ViewBuilder
    private var markLayer: some View {
        switch mark {
        case .none:
            EmptyView()
        case .locked:
            lockDisc
                .position(markCentre)
        case .inDraft:
            checkDisc
                .position(markCentre)
        case .selectable(let chosen):
            if chosen {
                checkDisc
                    .position(markCentre)
            } else {
                hollowRing
                    .position(markCentre)
            }
        }
    }

    private var lockDisc: some View {
        let disc = size.markSide
        return ZStack {
            Circle().fill(Self.edgeInk.opacity(0.9))
            Circle().strokeBorder(RelicPalette.bronze, lineWidth: 0.8)
            Image(systemName: "lock.fill")
                .font(.system(size: disc * 0.55, weight: .bold))
                .foregroundStyle(RelicPalette.star)
        }
        .frame(width: disc, height: disc)
    }

    private var checkDisc: some View {
        let disc = size.markSide
        return ZStack {
            Circle().fill(RelicPalette.goldLeaf)
            Circle().strokeBorder(Color(hex: "#5C4611"), lineWidth: 1)
            Image(systemName: "checkmark")
                .font(.system(size: disc * 0.55, weight: .heavy))
                .foregroundStyle(RelicPalette.goldInk)
        }
        .frame(width: disc, height: disc)
    }

    private var hollowRing: some View {
        Circle()
            .strokeBorder(RelicPalette.value.opacity(0.6), lineWidth: 1.2)
            .frame(width: size.markSide, height: size.markSide)
    }

    // MARK: Layers 12–13 (outside the group)

    private var outerRings: some View {
        ZStack {
            if relic.isAwakened {
                RoundedRectangle(cornerRadius: size.cornerRadius + 1.5, style: .continuous)
                    .strokeBorder(RelicPalette.halo, lineWidth: 1.2)
                    .padding(-1.5)
                    .opacity(dimmed ? 0.42 : 1)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: size.cornerRadius + size.ringOffset, style: .continuous)
                    .strokeBorder(Self.ringGold, lineWidth: size.ringWidth)
                    .padding(-size.ringOffset)
                    .compositingGroup()
                    .shadow(color: RelicPalette.star.opacity(0.5), radius: 6)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A relic's painted stone with its rim tinted in the quality's enamel, or —
/// in a bundle without the art — the set's glyph in star gold. Both decoded
/// at the size they are drawn. Shared by the tile and the socket.
private struct RelicStoneArt: View {
    let relic: Relic
    let side: CGFloat
    let glyphPoint: CGFloat

    var body: some View {
        Group {
            if BundleArt.exists(relic.stoneImageName) {
                ZStack {
                    BundleImage(name: relic.stoneImageName, renderedAt: side)
                        .aspectRatio(contentMode: .fit)
                    rim
                }
            } else {
                Image(systemName: relic.set.glyph)
                    .font(.system(size: glyphPoint, weight: .bold))
                    .foregroundStyle(RelicPalette.star)
            }
        }
        .frame(width: side, height: side)
    }

    /// `relic_rim` is a template: white on clear, tinted here.
    @ViewBuilder
    private var rim: some View {
        if let image = BundleArt.thumbnail(Relic.rimImageName, maxPixel: pixels) {
            Image(uiImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(relic.resolvedQuality.enamel)
        }
    }

    private var pixels: Int {
        max(1, Int((side * UIScreen.main.scale).rounded(.up)))
    }
}

// MARK: - The socket and the rosette

/// One hexagonal socket of the rosette: a pointy-top hexagon of bronze rings
/// round a basalt floor, the stone in it with its level, or the slot's
/// numeral when it is empty; a bright gold ring and glow when its set is
/// complete on this unit. No stars and no face: the rosette says which sets
/// are there, the tiles and the card say the rest. A button over its own
/// hexagon.
struct RelicSocket: View {
    let slot: Int
    let relic: Relic?
    /// The hexagon's circumradius.
    var radius: CGFloat = 28
    /// Its set is complete on this unit.
    var inActiveSet: Bool = false
    let action: () -> Void

    private static let activeRim: Color = Color(hex: "#FFE08A")
    private static let edgeInk: Color = Color(hex: "#120C06")

    var body: some View {
        Button(action: action) {
            face
                .frame(width: radius * 2, height: radius * 2)
                .contentShape(BoonHexagon())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let relic else { return "Slot \(slot), empty" }
        return "Slot \(slot), \(RelicReading.spokenTile(relic))"
    }

    /// A hexagon of circumradius `r`, framed as the square `BoonHexagon`
    /// takes its radius from.
    private func hexagon(_ r: CGFloat, _ colour: Color) -> some View {
        BoonHexagon()
            .fill(colour)
            .frame(width: r * 2, height: r * 2)
    }

    private var face: some View {
        let floorRadius = radius - 3.2
        return ZStack {
            hexagon(radius, RelicPalette.bronzeDark)
            hexagon(radius - 0.8, inActiveSet ? Self.activeRim : RelicPalette.bronzeMid)
            hexagon(radius - 2.2, RelicPalette.bronze)
            hexagon(floorRadius, RelicPalette.basaltFoot)
            if let relic {
                glow(relic, floorRadius: floorRadius)
                RelicStoneArt(relic: relic, side: radius * 2 - 7, glyphPoint: radius * 0.8)
                levelLabel(relic)
            } else {
                emptyNumeral
            }
            if inActiveSet {
                activeRing
            }
        }
    }

    private func glow(_ relic: Relic, floorRadius: CGFloat) -> some View {
        let quality = relic.resolvedQuality
        return ZStack {
            RadialGradient(colors: [quality.glowColor.opacity(quality.glowStrength), Color.clear],
                           center: .center, startRadius: 0, endRadius: radius * 0.96)
            if relic.isAwakened {
                RadialGradient(colors: [RelicPalette.halo.opacity(0.42), Color.clear],
                               center: .center, startRadius: 0, endRadius: radius * 0.92)
            }
        }
        .frame(width: floorRadius * 2, height: floorRadius * 2)
        .clipShape(BoonHexagon())
    }

    @ViewBuilder
    private func levelLabel(_ relic: Relic) -> some View {
        if relic.level > 0 {
            OutlinedText(
                text: "+\(relic.level)",
                font: Theme.numeric(max(11.5, radius * 0.41)).weight(.black),
                fill: relic.level >= relic.maxLevel ? RelicPalette.star : Color.white,
                edge: Self.edgeInk,
                width: radius >= 26 ? 1.2 : 1.0
            )
            .fixedSize()
            .offset(y: radius * 0.62)
        }
    }

    /// The slot's numeral, its figure in Manrope: Cinzel's 1 is a Roman I.
    private var emptyNumeral: some View {
        Text.inscribed("\(slot)", letters: Theme.title(15), digits: Theme.numeric(14.5))
            .foregroundStyle(RelicPalette.eyebrow.opacity(0.85))
    }

    private var activeRing: some View {
        BoonHexagon()
            .stroke(Self.activeRim, lineWidth: 1.6)
            .frame(width: (radius - 1.5) * 2, height: (radius - 1.5) * 2)
            .compositingGroup()
            .shadow(color: RelicPalette.star.opacity(0.55), radius: 5)
    }
}

/// A unit's six relics as ONE object: seven pointy-top hexagons edge to
/// edge, the Boon's socket at the centre. A pointy-top rosette has no
/// neighbour at twelve o'clock, so slot 1 stands at eleven and the slots run
/// clockwise in reading order; the fixed-main slots 1, 3 and 5 make one
/// triangle and the free ones the other. R 28 on the unit sheet (151.5 ×
/// 145.2), R 19 on the collection's plates (102.7 × 98.5).
struct RelicRosette: View {
    let slots: [Int: Relic]
    let activeSets: Set<RelicSet>
    let boon: Boon?
    var radius: CGFloat = 28
    var gap: CGFloat = 3
    let onSlot: (Int) -> Void
    /// nil: the centre is not a button.
    var onCentre: (() -> Void)? = nil

    private static let centreRim: Color = Color(hex: "#E9C46A")

    /// A slot's centre as an offset from the Boon's, with `d = √3·R + gap`
    /// the distance between neighbours: 1 at eleven o'clock, then clockwise.
    nonisolated static func offset(of slot: Int, radius: CGFloat, gap: CGFloat) -> CGPoint {
        let root3 = CGFloat(3).squareRoot()
        let d = radius * root3 + gap
        let rise = d * root3 / 2
        switch slot {
        case 1: return CGPoint(x: -d / 2, y: -rise)
        case 2: return CGPoint(x: d / 2, y: -rise)
        case 3: return CGPoint(x: d, y: 0)
        case 4: return CGPoint(x: d / 2, y: rise)
        case 5: return CGPoint(x: -d / 2, y: rise)
        case 6: return CGPoint(x: -d, y: 0)
        default: return CGPoint.zero
        }
    }

    /// The rosette's frame: `2d + √3·R` wide, `√3·d + 2R` tall.
    nonisolated static func frameSize(radius: CGFloat, gap: CGFloat) -> CGSize {
        let root3 = CGFloat(3).squareRoot()
        let d = radius * root3 + gap
        return CGSize(width: 2 * d + root3 * radius, height: root3 * d + 2 * radius)
    }

    var body: some View {
        let frame = Self.frameSize(radius: radius, gap: gap)
        return ZStack {
            ForEach(Array(1...6), id: \.self) { slot in
                socket(slot)
                    .position(point(for: slot, in: frame))
            }
            centreSocket
                .position(x: frame.width / 2, y: frame.height / 2)
        }
        .frame(width: frame.width, height: frame.height)
    }

    private func point(for slot: Int, in frame: CGSize) -> CGPoint {
        let offset = Self.offset(of: slot, radius: radius, gap: gap)
        return CGPoint(x: frame.width / 2 + offset.x, y: frame.height / 2 + offset.y)
    }

    private func socket(_ slot: Int) -> some View {
        let relic = slots[slot]
        let active = relic.map { activeSets.contains($0.set) } ?? false
        return RelicSocket(slot: slot, relic: relic, radius: radius, inActiveSet: active) {
            onSlot(slot)
        }
    }

    // MARK: The Boon's socket

    @ViewBuilder
    private var centreSocket: some View {
        if let onCentre {
            Button(action: onCentre) {
                centreFace
                    .contentShape(BoonHexagon())
            }
            .buttonStyle(GamePressStyle(.plate))
            .accessibilityLabel(centreSpoken)
        } else {
            centreFace
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(centreSpoken)
        }
    }

    private var centreSpoken: String {
        guard let boon else { return "Boon socket, empty" }
        return "Boon, \(boon.displayName), \(boon.shortLine)"
    }

    private func hexagon(_ r: CGFloat, _ colour: Color) -> some View {
        BoonHexagon()
            .fill(colour)
            .frame(width: r * 2, height: r * 2)
    }

    private var centreFace: some View {
        ZStack {
            hexagon(radius, RelicPalette.bronzeDark)
            hexagon(radius - 0.8, Self.centreRim)
            hexagon(radius - 2.2, RelicPalette.bronze)
            hexagon(radius - 3.2, RelicPalette.basaltFoot)
            centreMark
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    @ViewBuilder
    private var centreMark: some View {
        if let boon {
            Image(systemName: boon.kind.glyph)
                .font(.system(size: radius * 0.62, weight: .black))
                .foregroundStyle(boon.kind.tint)
                .shadow(color: boon.kind.tint.opacity(0.8), radius: 4)
        } else if radius >= 26 {
            Text("BOON")
                .font(Theme.title(13))
                .foregroundStyle(RelicPalette.eyebrow.opacity(0.8))
                .lineLimit(1)
                .fixedSize()
        } else {
            Image(systemName: "seal")
                .font(.system(size: radius * 0.6, weight: .bold))
                .foregroundStyle(RelicPalette.eyebrow.opacity(0.8))
        }
    }
}

/// Manage's slot filter: the rosette's own geometry at R 12, each slot a
/// hexagon that toggles (several may be on — `RelicFilter.slots` is a set)
/// and the centre ALL, lit while nothing is chosen, which clears. 66 × 64.
struct RelicSlotDiagram: View {
    @Binding var selection: Set<Int>

    private static let radius: CGFloat = 12
    private static let gap: CGFloat = 2
    private static let offFill: Color = Color(hex: "#2A2119")

    var body: some View {
        let frame = RelicRosette.frameSize(radius: Self.radius, gap: Self.gap)
        return ZStack {
            ForEach(Array(1...6), id: \.self) { slot in
                slotButton(slot)
                    .position(point(for: slot, in: frame))
            }
            allButton
                .position(x: frame.width / 2, y: frame.height / 2)
        }
        .frame(width: frame.width, height: frame.height)
    }

    private func point(for slot: Int, in frame: CGSize) -> CGPoint {
        let offset = RelicRosette.offset(of: slot, radius: Self.radius, gap: Self.gap)
        return CGPoint(x: frame.width / 2 + offset.x, y: frame.height / 2 + offset.y)
    }

    private func toggle(_ slot: Int) {
        if selection.contains(slot) {
            _ = selection.remove(slot)
        } else {
            _ = selection.insert(slot)
        }
    }

    private func slotButton(_ slot: Int) -> some View {
        let isOn = selection.contains(slot)
        return Button {
            toggle(slot)
        } label: {
            ZStack {
                slotFace(isOn)
                Text("\(slot)")
                    .font(Theme.numeric(11.5).weight(.black))
                    .foregroundStyle(isOn ? RelicPalette.goldInk : RelicPalette.eyebrow)
            }
            .frame(width: Self.radius * 2, height: Self.radius * 2)
            .contentShape(BoonHexagon())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("Slot \(slot) filter, \(isOn ? "on" : "off")")
    }

    private var allButton: some View {
        let lit = selection.isEmpty
        return Button {
            selection = []
        } label: {
            ZStack {
                slotFace(lit)
                Text("ALL")
                    .font(Theme.body(11).weight(.black))
                    .foregroundStyle(lit ? RelicPalette.goldInk : RelicPalette.eyebrow)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: Self.radius * 2, height: Self.radius * 2)
            .contentShape(BoonHexagon())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(lit ? "All slots, on" : "All slots, off")
    }

    @ViewBuilder
    private func slotFace(_ isOn: Bool) -> some View {
        if isOn {
            BoonHexagon()
                .fill(RelicPalette.goldLeaf)
        } else {
            BoonHexagon()
                .fill(Self.offFill)
                .overlay(BoonHexagon().stroke(RelicPalette.bronze, lineWidth: 1))
        }
    }
}

// MARK: - NOW over THEN

/// A build before and after a change, the genre's Before → After: NOW over
/// THEN, six small tiles each, a THEN tile that differs ringed in gold (an
/// emptied slot dashed in rose), and — unless `readOnly` — a × on each THEN
/// tile that empties that slot. 273 × 78. A tile opens its card (`onTile`).
struct BuildRows: View {
    let now: [Int: Relic]
    let then: [Int: Relic]
    var readOnly: Bool = false
    /// Opens the relic's card.
    var onTile: (Relic) -> Void = { _ in }
    /// Empties that slot in THEN.
    var onClear: (Int) -> Void = { _ in }

    private static let cellSide: CGFloat = 36
    private static let cellGap: CGFloat = 5
    private static let labelWidth: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(title: "NOW", tint: RelicPalette.dim, relics: now, isThen: false)
            row(title: "THEN", tint: RelicPalette.eyebrow, relics: then, isThen: true)
        }
    }

    private func row(title: String, tint: Color, relics: [Int: Relic], isThen: Bool) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(Theme.body(11).weight(.black))
                .tracking(0.6)
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.labelWidth, alignment: .leading)
            HStack(spacing: Self.cellGap) {
                ForEach(Array(1...6), id: \.self) { slot in
                    cell(slot: slot, relic: relics[slot], isThen: isThen)
                }
            }
        }
        .frame(height: Self.cellSide)
    }

    private func differs(_ slot: Int) -> Bool {
        then[slot]?.id != now[slot]?.id
    }

    @ViewBuilder
    private func cell(slot: Int, relic: Relic?, isThen: Bool) -> some View {
        if let relic {
            filledCell(slot: slot, relic: relic, isThen: isThen)
        } else {
            emptyCell(slot: slot, changed: isThen && differs(slot))
        }
    }

    private func filledCell(slot: Int, relic: Relic, isThen: Bool) -> some View {
        Button {
            onTile(relic)
        } label: {
            RelicTile(relic: relic, size: .small, isSelected: isThen && differs(slot))
        }
        .buttonStyle(GamePressStyle(.plate))
        .frame(width: Self.cellSide, height: Self.cellSide)
        .overlay(alignment: .topTrailing) {
            if isThen && !readOnly {
                clearBadge(slot)
            }
        }
    }

    /// A 14-point × on the tile's top-trailing corner, standing 4 points
    /// out; its tap area reaches 6 points further.
    private func clearBadge(_ slot: Int) -> some View {
        Button {
            onClear(slot)
        } label: {
            ZStack {
                Circle().fill(Color(hex: "#120C06").opacity(0.9))
                Circle().strokeBorder(RelicPalette.bronze, lineWidth: 0.8)
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(RelicPalette.value)
            }
            .frame(width: 14, height: 14)
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.medallion))
        .offset(x: 10, y: -10)
        .accessibilityLabel("Empty slot \(slot)")
    }

    private func emptyCell(slot: Int, changed: Bool) -> some View {
        let outline = RoundedRectangle(cornerRadius: 5.8, style: .continuous)
        return ZStack {
            outline.fill(RelicPalette.well)
            outline.strokeBorder(changed ? RelicPalette.loss : RelicPalette.bronze,
                                 style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            // Its figure in Manrope: Cinzel's 1 is a Roman I.
            Text.inscribed("\(slot)", letters: Theme.title(13), digits: Theme.numeric(12.6))
                .foregroundStyle(RelicPalette.quiet)
        }
        .frame(width: Self.cellSide, height: Self.cellSide)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(changed ? "Slot \(slot), emptied" : "Slot \(slot), empty")
    }
}

// MARK: - Reading a relic

/// What the next sub stat waits on: a level, the choice already owed on the
/// card, or the awakening's fifth.
enum NextSubStat: Equatable {
    case atLevel(Int)
    case waiting
    case awaken
}

/// The pure half of the relic screens: what a relic's numbers MEAN, read off
/// the relic itself with no view and no actor, so the tests can pin it.
enum RelicReading {

    // MARK: Roll marks

    /// How many times each sub stat has rolled, index-aligned with
    /// `relic.subStats`; nil at the gemmed index. Rolls are not stored — a
    /// stored count would be exact but costs an Optional save field and five
    /// mutation points in `RelicService` — so they are READ: each roll is
    /// its grade's base × 0.75–1.25, so a sub's count is its rolled value
    /// (never the honing, which is kept apart) over the base, capped at one
    /// more than the roll levels taken; and the relic's own quality, levels
    /// and awakening fix the TOTAL, which settles the near-ties. Measured on
    /// 20,000 simulated relics a case: exact on 99.8% of 6★ Legends at +12
    /// and every Rare and below, where the plain estimate managed 94.6%. A
    /// gemmed relic keeps the plain estimate — the gem took an unknown number
    /// of rolls with it — and so does a relic more than two off the total (a
    /// reappraisal that replayed its pending roll).
    static func rollCounts(_ relic: Relic) -> [Int?] {
        let level = relic.level
        // A roll owed at +3/+6/+9/+12 is a level reached whose roll is not
        // yet on the relic; the awakening's fifth is owed at +15 instead.
        let rollWaiting = relic.hasPendingRoll && level % 3 == 0 && level <= 12
        let taken = max(0, min(level, 12) / 3 - (rollWaiting ? 1 : 0))
        let fifthPresent = relic.isAwakened && !(relic.hasPendingRoll && relic.isMaxLevel)
        let events = relic.resolvedQuality.subStatCount + taken + (fifthPresent ? 1 : 0)
        // One growth per roll level taken, on top of the roll it came with.
        let cap = 1 + taken

        var raw: [Double] = []
        var counts: [Int] = []
        for sub in relic.subStats {
            let base = RelicService.subStatBase(kind: sub.kind, grade: relic.grade)
            let ratio: Double = base > 0 ? sub.value / base : 1
            raw.append(ratio)
            counts.append(min(cap, max(1, Int(ratio.rounded()))))
        }

        if let gem = relic.gemmed {
            var marked: [Int?] = []
            for (index, count) in counts.enumerated() {
                marked.append(index == gem ? nil : count)
            }
            return marked
        }
        let total = counts.reduce(0, +)
        if abs(total - events) <= 2 {
            settle(&counts, raw: raw, events: events, cap: cap)
        }
        return counts.map { Optional($0) }
    }

    /// Moves the estimate to the known total one roll at a time, each time
    /// on the sub whose value sits nearest the boundary it crosses.
    private static func settle(_ counts: inout [Int], raw: [Double], events: Int, cap: Int) {
        while counts.reduce(0, +) > events {
            var pick: Int? = nil
            var nearest = Double.infinity
            for index in counts.indices where counts[index] > 1 {
                let margin: Double = raw[index] - (Double(counts[index]) - 0.5)
                if margin < nearest {
                    nearest = margin
                    pick = index
                }
            }
            guard let chosen = pick else { break }
            counts[chosen] -= 1
        }
        while counts.reduce(0, +) < events {
            var pick: Int? = nil
            var nearest = -Double.infinity
            for index in counts.indices where counts[index] < cap {
                let margin: Double = raw[index] - (Double(counts[index]) + 0.5)
                if margin > nearest {
                    nearest = margin
                    pick = index
                }
            }
            guard let chosen = pick else { break }
            counts[chosen] += 1
        }
    }

    // MARK: Sets

    /// A set in two or three words, shown beside its name wherever a set
    /// appears; the full sentence stays one tap away in the set reference.
    /// Every percentage here is in `effectDescription` (a test holds the two
    /// together).
    static func shortEffect(_ set: RelicSet) -> String {
        switch set {
        case .fury: return "ATK +35%"
        case .aegis: return "DEF +35%"
        case .bulwark: return "HP +35%"
        case .zephyr: return "SPD +25%"
        case .thunder: return "CRIT Rate +30%"
        case .ruin: return "CRIT DMG +40%"
        case .oracle: return "ACC +20%"
        case .wards: return "RES +20%"
        case .ichor: return "Bar +25% a turn"
        case .wrath: return "Extra turn 22%"
        case .styx: return "Drain 35%"
        case .chains: return "Slow 25%"
        case .fates: return "Shield 15% HP"
        case .nemesis: return "Bar +4% per 7% lost"
        case .titanfall: return "DMG +30% · no heal"
        case .vigil: return "Counter 15%"
        }
    }

    // MARK: Numbers

    /// A change as the player reads it: the difference of the two figures
    /// as `StatKind.format` prints them, so "+12% → +17%" says 5%, not the
    /// raw difference's 6% (the arithmetic of the old relic picker's
    /// `StatKind.shownChange`, deleted with it on 2026-09-24). No sign.
    static func shownChange(_ kind: StatKind, from before: Double, to after: Double) -> String {
        let scale: Double = kind.isPercentage ? 100 : 1
        let shown = Int((after * scale).rounded()) - Int((before * scale).rounded())
        return kind.isPercentage ? "\(shown)%" : "\(shown)"
    }

    /// What the next sub stat waits on, or nil when none is to come.
    static func nextSubStat(_ relic: Relic) -> NextSubStat? {
        let adds = relic.subStats.count < relic.subStatCap
        if relic.hasPendingRoll && adds {
            return .waiting
        }
        if adds && relic.level < relic.maxLevel {
            let upcoming = ((relic.level + 1)...relic.maxLevel).first { RelicService.levelRollsSubStat($0) }
            if let upcoming {
                return .atLevel(upcoming)
            }
        }
        if relic.grade >= 6 && relic.isMaxLevel && relic.subStats.count >= 4 && !relic.isAwakened {
            return .awaken
        }
        return nil
    }

    /// The main stat at +15, ordinary (×3) or awakened (×3.6).
    static func peakMain(_ relic: Relic, awakened: Bool) -> StatModifier {
        let top = awakened ? Relic.awakenedPeak : Relic.peak
        return StatModifier(relic.mainStat.kind, relic.mainStat.value * top)
    }

    // MARK: Builds

    /// How many of the six slots a draft changes.
    static func draftChanges(now: [Int: UUID], then: [Int: UUID]) -> Int {
        (1...6).filter { now[$0] != then[$0] }.count
    }

    /// What Auto-equip would put on the unit, computed on a copy so Manage
    /// can show it before anything moves: its whole build afterwards, the
    /// slots it already wore included.
    static func fillEmpty(unitID: UUID, player: Player) -> [Int: UUID] {
        var copy = player
        RelicService.autoEquip(unitID: unitID, player: &copy)
        return copy.unit(unitID)?.equippedRelics ?? [:]
    }

    /// The role a relic suits best, and how well: the highest efficiency
    /// over every role (the first role wins a tie).
    static func bestFit(_ relic: Relic) -> (role: CombatRole, value: Double) {
        var best: (role: CombatRole, value: Double) = (role: CombatRole.attacker, value: -1)
        for role in CombatRole.allCases {
            let value = RelicService.efficiency(relic, for: role)
            if value > best.value {
                best = (role: role, value: value)
            }
        }
        return best
    }

    // MARK: Words

    /// A tile read aloud: "Legend Fury relic, slot 2, 6 stars, plus 15,
    /// awakened, worn by Zeus, locked".
    static func spokenTile(_ relic: Relic, wearerName: String? = nil) -> String {
        var words = "\(relic.resolvedQuality.displayName) \(relic.set.displayName) relic, "
            + "slot \(relic.slot), \(relic.grade) stars, plus \(relic.level)"
        if relic.isAwakened {
            words += ", awakened"
        }
        if let wearerName {
            words += ", worn by \(wearerName)"
        }
        if relic.isLocked {
            words += ", locked"
        }
        return words
    }
}

// MARK: - The kit on one page

#if DEBUG
/// One sample the gallery draws a tile of.
private struct RelicKitSample: Identifiable {
    let id: Int
    let relic: Relic
    let wearer: ResolvedUnit?
    let showsSlot: Bool
    let mark: RelicTileMark
    let isSelected: Bool
    let dimmed: Bool
}

/// Every part of the kit on one scrolling page over the reliquary, for the
/// CI tour (`-tour-relics kit`, frame `11-relics-kit`) and for judging a
/// change to the kit before any screen uses it: the tile at three sizes in
/// six states, the sockets and both rosettes, the slot filter, NOW → THEN,
/// the plates, wells, tablets and dots, the rails, dials and roll marks,
/// the ledgers and set lines, the stones, and the four confirmation cards.
///
/// The tile's six states are generated the same way every run
/// (`SeededRandom(seed: 1)`, a local copy, never saved) so the frame is
/// comparable run to run; the rosettes, NOW → THEN and the cards draw the
/// tour save's own relics and faces when it has them.
struct RelicKitGallery: View {
    @EnvironmentObject private var store: GameStore
    @State private var galleryFilter: Set<Int> = [2, 4]

    /// The tile matrix's column: a 60-point tile, its ring and its face's
    /// overhang, and a gap.
    private static let pitch: CGFloat = 66

    var body: some View {
        GameScreen("Relic kit", subtitle: "Every part of the reliquary, in every state") {
            BarCount(value: "\(store.player.relics.count) relics", systemImage: "hexagon.fill")
        } content: {
            // Every row is under 700 points, inside the 734 of the design
            // phone's safe width (the builders' spec §1).
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    tilesAndRosettes
                    socketsAndBuild
                    platesAndWells
                    railsAndDials
                    ledgers
                    setsAndStones
                    confirmCards
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                ReliquaryBackdrop()
            }
        }
    }

    // MARK: Samples

    /// The six states: a worn Legend +15; a locked Hero +12 with its slot; a
    /// Rare +9 in the draft, selected; a Normal +0 in select mode; an
    /// awakened Legend, chosen; a locked Magic +3 dimmed in select mode.
    private var samples: [RelicKitSample] {
        let relics = sampleRelics
        let faces = Array(store.resolvedUnits.sorted { $0.power > $1.power }.prefix(2))
        let first = faces.first
        let second = faces.count > 1 ? faces[1] : faces.first
        return [
            RelicKitSample(id: 0, relic: relics[0], wearer: first, showsSlot: false, mark: .none,
                           isSelected: false, dimmed: false),
            RelicKitSample(id: 1, relic: relics[1], wearer: nil, showsSlot: true, mark: .locked,
                           isSelected: false, dimmed: false),
            RelicKitSample(id: 2, relic: relics[2], wearer: second, showsSlot: true, mark: .inDraft,
                           isSelected: true, dimmed: false),
            RelicKitSample(id: 3, relic: relics[3], wearer: nil, showsSlot: true, mark: .selectable(false),
                           isSelected: false, dimmed: false),
            RelicKitSample(id: 4, relic: relics[4], wearer: first, showsSlot: false, mark: .selectable(true),
                           isSelected: false, dimmed: false),
            RelicKitSample(id: 5, relic: relics[5], wearer: nil, showsSlot: true, mark: .locked,
                           isSelected: false, dimmed: true),
        ]
    }

    /// The six relics the page draws: the tour save's own where it holds one
    /// of the same grade, slot, quality, level and awakening as a state's
    /// recipe, and the generated recipe where it does not — so a save's real
    /// stones show, in the same six states, every run.
    private var sampleRelics: [Relic] {
        let owned: [Relic] = store.player.relics
        return Self.generatedRelics().map { (recipe: Relic) -> Relic in
            guard var match = owned.first(where: { Self.matches($0, recipe) }) else { return recipe }
            match.isLocked = recipe.isLocked
            return match
        }
    }

    private static func matches(_ relic: Relic, _ recipe: Relic) -> Bool {
        guard relic.grade == recipe.grade, relic.slot == recipe.slot, relic.level == recipe.level else { return false }
        return relic.resolvedQuality == recipe.resolvedQuality && relic.isAwakened == recipe.isAwakened
    }

    /// Six relics in the six states, the same every run.
    private static func generatedRelics() -> [Relic] {
        var rng = SeededRandom(seed: 1)
        var made: [Relic] = []
        made.append(sample(grade: 6, slot: 2, of: .fury, quality: .legend, level: 15, rng: &rng))
        var locked = sample(grade: 6, slot: 3, of: .vigil, quality: .hero, level: 12, rng: &rng)
        locked.isLocked = true
        made.append(locked)
        made.append(sample(grade: 5, slot: 1, of: .zephyr, quality: .rare, level: 9, rng: &rng))
        made.append(sample(grade: 4, slot: 4, of: .fates, quality: .normal, level: 0, rng: &rng))
        made.append(sample(grade: 6, slot: 6, of: .wrath, quality: .legend, level: 15, awakened: true, rng: &rng))
        var small = sample(grade: 3, slot: 6, of: .oracle, quality: .magic, level: 3, rng: &rng)
        small.isLocked = true
        made.append(small)
        return made
    }

    private static func sample(grade: Int, slot: Int, of family: RelicSet, quality: RelicQuality, level: Int,
                               awakened: Bool = false, rng: inout SeededRandom) -> Relic {
        var relic = RelicService.generate(grade: grade, slot: slot, set: family, quality: quality,
                                          awakened: awakened, rng: &rng)
        for _ in 0..<level {
            RelicService.upgradeOnce(&relic, rng: &rng)
        }
        return relic
    }

    /// The strongest unit's six, or the samples by slot on a save with none.
    private var build: (unit: ResolvedUnit?, slots: [Int: Relic]) {
        let strongest = store.resolvedUnits.max { $0.power < $1.power }
        var slots: [Int: Relic] = [:]
        for relic in strongest?.relics ?? [] where slots[relic.slot] == nil {
            slots[relic.slot] = relic
        }
        if slots.isEmpty {
            for relic in sampleRelics where slots[relic.slot] == nil {
                slots[relic.slot] = relic
            }
        }
        return (unit: strongest, slots: slots)
    }

    private func caption(_ words: String) -> some View {
        Text(words.uppercased())
            .font(Theme.body(11).weight(.black))
            .tracking(0.8)
            .foregroundStyle(RelicPalette.eyebrow)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Tiles and rosettes

    private var tilesAndRosettes: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                caption("The tile · 60 · 48 · 36")
                tileRow(.large)
                tileRow(.medium)
                tileRow(.small)
            }
            VStack(alignment: .leading, spacing: 6) {
                caption("Rosettes · R 28 · R 19")
                rosettes
            }
        }
    }

    private func tileRow(_ size: RelicTileSize) -> some View {
        HStack(spacing: 0) {
            ForEach(samples) { sample in
                RelicTile(relic: sample.relic, size: size, wearer: sample.wearer, showsSlot: sample.showsSlot,
                          mark: sample.mark, isSelected: sample.isSelected, dimmed: sample.dimmed)
                    .frame(width: Self.pitch, alignment: .leading)
            }
        }
        .padding(.top, 6)
    }

    private var rosettes: some View {
        let current = build
        let complete: [RelicSet] = current.unit?.activeRelicSets.map { $0.set } ?? []
        let active: Set<RelicSet> = Set(complete)
        return HStack(alignment: .top, spacing: 12) {
            RelicRosette(slots: current.slots, activeSets: active, boon: current.unit?.boon,
                         radius: 28, gap: 3, onSlot: { _ in }, onCentre: {})
            RelicRosette(slots: current.slots, activeSets: active, boon: current.unit?.boon,
                         radius: 19, gap: 2, onSlot: { _ in })
        }
    }

    // MARK: Sockets, the filter, NOW → THEN

    private var socketsAndBuild: some View {
        let relics = sampleRelics
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                caption("Sockets · empty · filled · set")
                HStack(spacing: 8) {
                    RelicSocket(slot: 4, relic: nil) {}
                    RelicSocket(slot: 1, relic: relics[2]) {}
                    RelicSocket(slot: 2, relic: relics[0], inActiveSet: true) {}
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                caption("Slot filter")
                RelicSlotDiagram(selection: $galleryFilter)
            }
            VStack(alignment: .leading, spacing: 6) {
                caption("Now → then · two changes")
                buildRows(relics)
            }
        }
    }

    private func buildRows(_ relics: [Relic]) -> some View {
        let now = build.slots
        var then = now
        then[2] = relics[0]
        then[6] = nil
        return BuildRows(now: now, then: then, onTile: { _ in }, onClear: { _ in })
            .padding(.top, 4)
    }

    // MARK: Plates, wells, tablets

    private var platesAndWells: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                caption("Plates")
                HStack(spacing: 8) {
                    RelicPlateButton(title: "Relics", count: "214", itemKey: "relic_cache") {}
                    RelicPlateButton(title: "Stones", count: "23", itemKey: "whetstone_legend") {}
                }
                .frame(width: 336)
                HStack(spacing: 8) {
                    RelicPlateButton(title: "Revert", height: 46, isEnabled: false) {}
                        .frame(width: 72)
                    RelicPlateButton(title: "All off", height: 46) {}
                        .frame(width: 84)
                    RelicPlateButton(title: "Sell · 3", finish: .wine, height: 46) {}
                    RelicPlateLabel(title: "Best six", systemImage: "wand.and.stars", height: 46,
                                    trailingSystemImage: "chevron.down")
                }
                .frame(width: 440)
                iconPlates
            }
            VStack(alignment: .leading, spacing: 8) {
                caption("Wells · tablets")
                RelicWellButton(eyebrow: "Set", value: "Fury", set: .fury, isActive: true) {}
                    .frame(width: 180)
                RelicWellButton(eyebrow: "Main", value: "Any", isActive: false) {}
                    .frame(width: 180)
                tablets
            }
        }
    }

    private var iconPlates: some View {
        HStack(spacing: 7) {
            RelicIconPlate(title: "Change", systemImage: "arrow.left.arrow.right") {}
            RelicIconPlate(title: "Remove", systemImage: "minus.circle") {}
            RelicIconPlate(title: "Hone", itemKey: "whetstone_hero", systemImage: "seal.fill") {}
            RelicIconPlate(title: "Reroll +9", systemImage: "arrow.triangle.2.circlepath", isEnabled: false) {}
            RelicIconPlate(title: "Sell", itemKey: "drachma", finish: .wine) {}
        }
        .frame(width: 440)
    }

    private var tablets: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                TabletRod(height: 166)
                VStack(spacing: 8) {
                    UnitSheetTablet(title: "Info", isOn: true, waiting: false) {}
                    UnitSheetTablet(title: "Relics", isOn: false, waiting: true) {}
                    UnitSheetTablet(title: "Regalia", isOn: false, waiting: false) {}
                }
            }
            VStack(spacing: 10) {
                WaitDot()
                WaitDot(count: 3)
                WaitDot(count: 12)
            }
            .padding(.top, 6)
        }
    }

    // MARK: Rails, dials, marks

    private var railsAndDials: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                caption("Level rail · +0 · +9 · +15")
                LevelRail(level: 0)
                LevelRail(level: 9)
                LevelRail(level: 15)
            }
            .frame(width: 220)
            VStack(alignment: .leading, spacing: 8) {
                caption("Odds · fit")
                HStack(spacing: 10) {
                    OddsDial(chance: 1.0)
                    OddsDial(chance: 0.65)
                    OddsDial(chance: 0.4)
                    RelicFitDial(value: 0.82)
                    RelicFitDial(value: 0.5, size: 28)
                    RelicFitDial(value: 0.3, size: 28)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                caption("Roll marks · 1 to 5")
                ForEach(Array(1...5), id: \.self) { count in
                    RollMarks(count: count)
                }
            }
        }
    }

    // MARK: Ledgers, sets, stones

    private static let ledgerRows: [StatLedgerRow] = [
        StatLedgerRow(label: "HP", value: "7,301", change: "+2,573", tone: .gain),
        StatLedgerRow(label: "ATK", value: "313", change: "+80", tone: .gain),
        StatLedgerRow(label: "DEF", value: "417", change: "−25", tone: .loss),
        StatLedgerRow(label: "SPD", value: "106", change: "+16", tone: .gain),
        StatLedgerRow(label: "CRIT Rate", value: "29%", change: "+14%", tone: .gain),
        StatLedgerRow(label: "CRIT DMG", value: "76%", change: nil, tone: .none),
        StatLedgerRow(label: "Accuracy", value: "17%", change: "+7%", tone: .gain),
        StatLedgerRow(label: "Resistance", value: "28%", change: nil, tone: .none),
    ]

    /// The two ledgers and the number plates: 198 + 20 + 284 points.
    private var ledgers: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                caption("Ledger · info")
                StatLedger(rows: Self.ledgerRows, style: .info)
            }
            VStack(alignment: .leading, spacing: 8) {
                caption("Ledger · manage")
                StatLedger(rows: Self.ledgerRows, style: .manage)
                caption("Number plates")
                HStack(spacing: 8) {
                    NumberPlate(eyebrow: "Sub stats", before: "4", after: "5")
                    NumberPlate(eyebrow: "ATK at +15", before: "+93", after: "+112")
                }
                .frame(width: 284)
            }
        }
    }

    /// The set lines beside the stones: 284 + 20 + 300 points.
    private var setsAndStones: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                caption("Set lines · full · compact · no unit")
                setLines
            }
            VStack(alignment: .leading, spacing: 8) {
                caption("Stones")
                RelicStonesPopover()
            }
        }
    }

    private var setLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            SetEffectRow(set: .fury, piecesOnUnit: 2, style: .full)
            SetEffectRow(set: .vigil, piecesOnUnit: 3, style: .full)
            SetEffectRow(set: .nemesis, piecesOnUnit: 0, style: .full)
            SetEffectRow(set: .zephyr, piecesOnUnit: 1, style: .compact, onInfo: {})
            SetEffectRow(set: .fates, piecesOnUnit: nil, style: .compact)
        }
        .frame(width: 284)
    }

    // MARK: The confirmation cards

    private var confirmCards: some View {
        let relics = sampleRelics
        let awakenable = relics[0]
        let total = relics.reduce(0) { $0 + RelicService.sellValue($1) }
        let asks: [RelicConfirm] = [
            .sell(relics: relics, total: total),
            .reappraise(relic: relics[1], cost: RelicService.reappraisalCost(relics[1])),
            .awaken(relic: awakenable, paying: awakenable.set.aetherElement),
            .leaveDraft(changes: 2),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            caption("The confirmation card · sell · reroll · awaken · leave")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(asks.enumerated()), id: \.offset) { _, ask in
                        RelicConfirmCard(confirm: ask, onConfirm: {}, onCancel: {})
                            .frame(width: 420, height: 340)
                            .clipped()
                    }
                }
            }
        }
    }
}
#endif
