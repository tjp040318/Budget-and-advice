import SwiftUI

// MARK: - The Draft Arena's board: its parts (2026-09-23; Docs/DRAFT.md)
//
// Every piece the board is built from, on the house's glass: the crest of a
// crown, the red strike, the board's two buttons, a side's column of five
// places, the pick-order track and a tile of the roster. None holds the
// store; the screen (`DraftView`) and its model (`DraftBoardModel`) pass
// values in and take taps out.

extension DraftTier {
    var color: Color { Color(hex: accentHex) }
}

/// The board's two colours: the player's gold and the rival's crimson, on
/// the pick-order track, the places on the clock and the strike.
enum DraftPalette {
    static let you = Color(hex: "#E8BE50")
    static let rival = Color(hex: "#D8505A")
    static let strike = Color(hex: "#E23A46")
}

// MARK: - The crest

/// A crown as an emblem: the painted laurel wreath with a disc of the
/// crown's colour and its numeral carved on it — the arena's crest
/// (`ArenaCrest`) in the draft's colours. A painted `draft_crest_<name>`
/// draws instead when one is in the bundle (paid art, on the owner's word).
/// Under 40 points the disc alone: the numeral would fall under the floor.
struct DraftCrest: View {
    let tier: DraftTier
    var size: CGFloat = 44

    var body: some View {
        let painted = "draft_crest_\(tier.displayName.lowercased())"
        return Group {
            if BundleImage.exists(painted) {
                BundleImage(name: painted, renderedAt: size)
                    .aspectRatio(contentMode: .fit)
            } else if size >= 40 {
                ZStack {
                    RadialGradient(
                        colors: [tier.color.opacity(0.45), tier.color.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                    ItemIcon(key: "laurels", size: size, glow: false)
                    disc(size * 0.5)
                        .offset(y: -size * 0.06)
                    Text(tier.numeral)
                        .font(Theme.display(size * 0.22))
                        .carved(glow: false)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: -size * 0.06)
                }
            } else {
                disc(size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.displayName)
    }

    private func disc(_ diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(tier.color)
            Circle().fill(
                LinearGradient(colors: [Color.white.opacity(0.38), Color.clear, Color.black.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
            )
            Circle().strokeBorder(Theme.goldText, lineWidth: max(1, diameter * 0.07))
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: tier.color.opacity(0.6), radius: diameter * 0.15)
    }
}

// MARK: - The strike

/// The red X over a struck unit, or over the one the player is about to
/// strike: two crimson bars with a dark edge and a glow.
struct DraftStrike: View {
    let size: CGFloat

    var body: some View {
        let length = size * 0.92
        let weight = max(3, size * 0.12)
        return ZStack {
            Capsule()
                .fill(DraftPalette.strike)
                .frame(width: length, height: weight)
                .rotationEffect(.degrees(45))
            Capsule()
                .fill(DraftPalette.strike)
                .frame(width: length, height: weight)
                .rotationEffect(.degrees(-45))
        }
        .shadow(color: .black.opacity(0.85), radius: 1.5)
        .shadow(color: DraftPalette.strike.opacity(0.6), radius: 5)
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The board's buttons

enum DraftButtonTone {
    case gold, crimson, glass
}

/// A plate for the board's decisions — Lock in, Strike, Fight, Draft again —
/// in the arena's drawn gold (the FIGHT plate's), a crimson for the strike,
/// or glass for the quiet one; 42 points tall, its label on one line at its
/// own width. A disabled plate is dim glass, never cream.
struct DraftActionButton: View {
    let title: String
    var systemImage: String? = nil
    var tone: DraftButtonTone = .gold
    var isEnabled: Bool = true
    var minWidth: CGFloat = 118
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return Button {
            // The primary press ticks and taps on touch-down; the confirm
            // is the "done", as on `PrimaryButton` (2026-09-24).
            AudioLibrary.shared.play(.uiConfirm, volume: 0.7)
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .black))
                }
                Text(title.uppercased())
                    .font(Theme.title(14))
                    .tracking(1.2)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 14)
            .frame(minWidth: minWidth)
            .frame(height: 42)
            .background(plate)
            .overlay(shape.strokeBorder(rimColor, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: glowColor, radius: 6, y: 2)
        }
        .buttonStyle(GamePressStyle(.primary))
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    private var labelColor: Color {
        guard isEnabled else { return Theme.onGlassDim }
        switch tone {
        case .gold: return Theme.ink
        case .crimson: return Theme.onGlass
        case .glass: return Theme.onGlassGold
        }
    }

    private var rimColor: Color {
        guard isEnabled else { return Theme.glassRim.opacity(0.35) }
        switch tone {
        case .gold: return Color(hex: "#FFE9A8").opacity(0.6)
        case .crimson: return Color(hex: "#FF9AA2").opacity(0.55)
        case .glass: return Theme.glassRim
        }
    }

    private var glowColor: Color {
        guard isEnabled else { return .clear }
        switch tone {
        case .gold: return Theme.gold.opacity(0.35)
        case .crimson: return DraftPalette.strike.opacity(0.35)
        case .glass: return .clear
        }
    }

    /// A gradient or a colour per tone: an if/switch, never a `?:`.
    @ViewBuilder
    private var plate: some View {
        if !isEnabled {
            LinearGradient(
                colors: [Color(hex: "#3A2C1A").opacity(0.5), Color(hex: "#150F0A").opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            switch tone {
            case .gold:
                LinearGradient(
                    colors: [Color(hex: "#FFE9A8"), Color(hex: "#E2BF62"), Theme.gold],
                    startPoint: .top, endPoint: .bottom
                )
                .overlay(
                    LinearGradient(colors: [Color.white.opacity(0.35), Color.clear], startPoint: .top, endPoint: .center)
                )
            case .crimson:
                LinearGradient(
                    colors: [Color(hex: "#C8434E"), Color(hex: "#8E1F2B"), Color(hex: "#5E1119")],
                    startPoint: .top, endPoint: .bottom
                )
                .overlay(
                    LinearGradient(colors: [Color.white.opacity(0.22), Color.clear], startPoint: .top, endPoint: .center)
                )
            case .glass:
                LinearGradient(
                    colors: [Color(hex: "#3A2C1A").opacity(0.92), Color(hex: "#150F0A").opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }
}

// MARK: - A side's five places

/// One of a side's five places on the board, as its column draws it.
struct DraftSlotModel: Identifiable {
    let index: Int
    /// Its number among the ten, 1…10.
    let pickNumber: Int
    let unit: ResolvedUnit?
    var isPending: Bool = false
    var isOnClock: Bool = false
    var isStruck: Bool = false
    var isStrikeTarget: Bool = false
    var isLeader: Bool = false
    var isTappable: Bool = false

    var id: Int { index }
}

/// A side's column: its name and crest over its five places. The player's
/// column stands on the left with its faces at the outer edge; the rival's
/// mirrors it on the right, so the two fives face each other across the
/// board, as the genre lays a draft out.
struct DraftSideColumn: View {
    let side: DraftSide
    let title: String
    let detail: String
    let tier: DraftTier
    let slots: [DraftSlotModel]
    let slotHeight: CGFloat
    let nameSize: CGFloat
    let onTap: (UUID) -> Void

    var body: some View {
        VStack(spacing: DraftBoardMetrics.slotGap) {
            header
            ForEach(slots) { slot in
                DraftSlotRow(slot: slot, side: side, height: slotHeight, nameSize: nameSize) {
                    if let unit = slot.unit { onTap(unit.id) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "YOU" or the rival's name, carved, over the rating, beside the crest
    /// at the column's outer edge.
    private var header: some View {
        let isPlayer = side == .player
        return HStack(spacing: 6) {
            if !isPlayer { Spacer(minLength: 0) }
            if isPlayer { DraftCrest(tier: tier, size: 24) }
            VStack(alignment: isPlayer ? .leading : .trailing, spacing: 0) {
                Text(title.uppercased())
                    .font(Theme.title(13))
                    .tracking(1.2)
                    .carved(glow: false)
                    .lineLimit(1)
                    .fixedSize()
                Text(detail)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.onGlassDim)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                    .lineLimit(1)
                    .fixedSize()
            }
            if !isPlayer { DraftCrest(tier: tier, size: 24) }
            if isPlayer { Spacer(minLength: 0) }
        }
        .frame(height: DraftBoardMetrics.header)
    }
}

/// One place: the face (or the pick's number while it waits) and, toward
/// the board's middle, the name and one line under it — the role's glyph and
/// the power, or BANNED, LEADER, CHOSEN. The place on the clock breathes in
/// its side's colour.
struct DraftSlotRow: View {
    let slot: DraftSlotModel
    let side: DraftSide
    let height: CGFloat
    let nameSize: CGFloat
    let action: () -> Void

    private var tint: Color { side == .player ? DraftPalette.you : DraftPalette.rival }
    private var isPlayer: Bool { side == .player }

    var body: some View {
        let face = max(30, height - 8)
        return HStack(spacing: 7) {
            if isPlayer {
                faceView(face)
                words
            } else {
                words
                faceView(face)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(plate)
        .contentShape(Rectangle())
        .onTapGesture {
            guard slot.isTappable else { return }
            Juice.haptic(.light)
            action()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(slot.isTappable ? .isButton : [])
    }

    @ViewBuilder
    private func faceView(_ size: CGFloat) -> some View {
        if let unit = slot.unit {
            UnitPortraitTile(unit: unit, size: size)
                .saturation(slot.isStruck ? 0.1 : 1)
                .opacity(slot.isPending ? 0.75 : (slot.isStruck ? 0.6 : 1))
                .overlay {
                    if slot.isStruck || slot.isStrikeTarget {
                        DraftStrike(size: size)
                    }
                }
        } else {
            emptyFace(size)
        }
    }

    /// A place still to fill: a dark well with a dashed rim and the pick's
    /// number, in its side's colour when it is on the clock.
    private func emptyFace(_ size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(6, min(Theme.tightCorner, size * 0.14)), style: .continuous)
        return shape
            .fill(Color.black.opacity(0.3))
            .overlay(
                shape.strokeBorder(slot.isOnClock ? tint.opacity(0.9) : Theme.glassRim.opacity(0.7),
                                   style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            )
            .overlay(
                Text("\(slot.pickNumber)")
                    .font(Theme.numeric(15))
                    .foregroundStyle(slot.isOnClock ? tint : Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            )
            .frame(width: size, height: size)
    }

    private var words: some View {
        VStack(alignment: isPlayer ? .leading : .trailing, spacing: 2) {
            if let unit = slot.unit {
                Text(DraftService.captionName(unit))
                    .strikethrough(slot.isStruck, color: Theme.onGlassDanger)
                    .font(Theme.body(nameSize).weight(.bold))
                    .foregroundStyle(slot.isStruck ? Theme.onGlassDanger : Theme.onGlass)
                    .lineLimit(2)
                    .multilineTextAlignment(isPlayer ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                tagLine(unit)
            } else {
                Text(slot.isOnClock ? "ON THE CLOCK" : "PICK \(slot.pickNumber)")
                    .font(Theme.body(11).weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(slot.isOnClock ? tint : Theme.onGlassDim)
                    .lineLimit(2)
                    .multilineTextAlignment(isPlayer ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
        .frame(maxWidth: .infinity, alignment: isPlayer ? .leading : .trailing)
    }

    /// One line under the name, in order of what matters most: struck, the
    /// strike about to land, the leader, a pick not locked in, else the
    /// role's glyph and the power.
    @ViewBuilder
    private func tagLine(_ unit: ResolvedUnit) -> some View {
        if slot.isStruck {
            tag("BANNED", glyph: "xmark", color: Theme.onGlassDanger)
        } else if slot.isStrikeTarget {
            tag("STRIKE", glyph: "xmark", color: Theme.onGlassDanger)
        } else if slot.isLeader {
            tag("LEADER", glyph: "crown.fill", color: Theme.onGlassGold)
        } else if slot.isPending {
            tag("CHOSEN", glyph: "hand.tap.fill", color: DraftPalette.you)
        } else {
            HStack(spacing: 3) {
                Image(systemName: DraftRole(unit.role).glyph)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Theme.onGlassEyebrow)
                Text(unit.power.formatted())
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func tag(_ word: String, glyph: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: glyph)
                .font(.system(size: 9, weight: .black))
            Text(word)
                .font(Theme.body(11).weight(.heavy))
                .tracking(0.6)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(color)
    }

    /// The place's plate: breathing in the side's colour on the clock, gold
    /// under a leader, a crimson rim under a strike, else a breath of dark.
    @ViewBuilder
    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if slot.isOnClock {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                let pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 3.2))
                shape
                    .fill(tint.opacity(0.10))
                    .overlay(shape.strokeBorder(tint.opacity(pulse), lineWidth: 1.4))
                    .shadow(color: tint.opacity(0.4 * pulse), radius: 6)
            }
        } else if slot.isLeader {
            GlassRowPlate(isOn: true)
        } else if slot.isStruck || slot.isStrikeTarget {
            shape
                .fill(DraftPalette.strike.opacity(0.10))
                .overlay(shape.strokeBorder(DraftPalette.strike.opacity(0.7), lineWidth: 1))
        } else {
            shape
                .fill(Color.black.opacity(0.28))
                .overlay(shape.strokeBorder(Theme.glassRim.opacity(0.35), lineWidth: 0.8))
        }
    }
}

// MARK: - The pick-order track

/// The ten picks as ten numbered pips in the order they fall — one, then two
/// each way, then one — in the player's gold or the rival's crimson, with a
/// gap between turns: made ones lit, a pick not yet locked in half lit, the
/// turn on the clock breathing, the rest dark. The phase's words under them.
struct DraftOrderTrack: View {
    let order: [DraftSide]
    let made: Int
    let pending: Int
    let onClock: DraftSide?
    let prompt: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(Array(order.enumerated()), id: \.offset) { index, side in
                    if index > 0, order[index - 1] != side {
                        Color.clear.frame(width: 6, height: 1)
                    }
                    pip(index: index, side: side)
                }
            }
            Text(prompt.uppercased())
                .font(Theme.title(13))
                .tracking(1.4)
                .carved(glow: false)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prompt)
    }

    /// Whether a pick falls in the turn now on the clock: the run of the
    /// clock's side from the next pick on.
    private func inTurnOnClock(_ index: Int) -> Bool {
        guard let onClock, index >= made, index < order.count else { return false }
        var cursor = made
        while cursor < order.count, order[cursor] == onClock {
            if cursor == index { return true }
            cursor += 1
        }
        return false
    }

    @ViewBuilder
    private func pip(index: Int, side: DraftSide) -> some View {
        let tint = side == .player ? DraftPalette.you : DraftPalette.rival
        let ink = side == .player ? Theme.ink : Theme.onGlass
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let label = Text("\(index + 1)")
            .font(Theme.numeric(11.5))
        if index < made {
            label
                .foregroundStyle(ink)
                .frame(width: 23, height: 20)
                .background(shape.fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.6))
        } else if index < made + pending {
            label
                .foregroundStyle(Theme.onGlass)
                .frame(width: 23, height: 20)
                .background(shape.fill(tint.opacity(0.4)))
                .overlay(shape.strokeBorder(tint, lineWidth: 1))
        } else if inTurnOnClock(index) {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                let pulse = 0.5 + 0.5 * (0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 3.2))
                label
                    .foregroundStyle(tint)
                    .frame(width: 23, height: 20)
                    .background(shape.fill(Color.black.opacity(0.45)))
                    .overlay(shape.strokeBorder(tint.opacity(pulse), lineWidth: 1.4))
                    .shadow(color: tint.opacity(0.5 * pulse), radius: 4)
            }
        } else {
            label
                .foregroundStyle(Theme.onGlassDim.opacity(0.8))
                .frame(width: 23, height: 20)
                .background(shape.fill(Color.black.opacity(0.4)))
                .overlay(shape.strokeBorder(Theme.glassRim.opacity(0.4), lineWidth: 0.8))
        }
    }
}

// MARK: - The roster

/// A tile's state on the roster grid.
enum DraftTileState: Equatable {
    case open
    /// Among this turn's picks, not locked in: its place, 1 or 2.
    case pending(Int)
    /// In the player's five.
    case picked
    /// Another unit of the same monster is in the five, or chosen.
    case twin
    /// The rival is on the clock: a tap reads the unit, it cannot take it.
    case waiting
}

/// One of the player's units on the grid: its face, a gold ring and its
/// place while it is chosen, a gold check once it is in the five, dim when a
/// unit of the same monster is.
struct DraftRosterTile: View {
    let unit: ResolvedUnit
    let size: CGFloat
    let state: DraftTileState
    let action: () -> Void

    private var dimmed: Bool {
        switch state {
        case .picked, .twin: return true
        case .open, .pending, .waiting: return false
        }
    }

    private var place: Int? {
        if case .pending(let index) = state { return index }
        return nil
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: max(6, min(Theme.tightCorner, size * 0.14)), style: .continuous)
        return Button(action: action) {
            UnitPortraitTile(unit: unit, size: size)
                .opacity(dimmed ? 0.38 : 1)
                .overlay(shape.strokeBorder(place != nil ? DraftPalette.you : Color.clear, lineWidth: 2.5))
                .shadow(color: place != nil ? DraftPalette.you.opacity(0.6) : Color.clear, radius: 6)
                .overlay(alignment: .topTrailing) {
                    badge
                }
        }
        // A face of the roster's scrolling grid: quiet, and the board's
        // `tap` keeps its tick for a finished tap (2026-09-24).
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel("\(unit.name), \(DraftRole(unit.role).displayName), power \(unit.power)")
    }

    @ViewBuilder
    private var badge: some View {
        if let place {
            Text("\(place)")
                .font(Theme.numeric(11.5))
                .foregroundStyle(Theme.ink)
                .frame(width: 18, height: 18)
                .background(Circle().fill(DraftPalette.you))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8))
                .offset(x: 5, y: -5)
        } else if state == .picked {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 18, height: 18)
                .background(Circle().fill(DraftPalette.you))
                .offset(x: 5, y: -5)
        }
    }
}

/// The board's role filter: four glyph tiles in the strip's one material
/// beside the element tiles, the lit one toggling off on a second tap as the
/// element tiles do (`ElementFilterTiles`).
struct DraftRoleTiles: View {
    @Binding var selection: DraftRole?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(DraftRole.allCases) { role in
                tile(role)
            }
        }
    }

    private func tile(_ role: DraftRole) -> some View {
        let isOn = selection == role
        return Button {
            selection = isOn ? nil : role
        } label: {
            Image(systemName: role.glyph)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(isOn ? Theme.ink : Theme.onGlassGold)
                .frame(width: 30, height: ScreenChrome.control)
                .background(Group {
                    if isOn {
                        Capsule().fill(Theme.goldPlate)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1).padding(1.5))
                    } else {
                        ScreenChrome.well
                    }
                })
                .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(role.displayName)
    }
}

// MARK: - The coin

/// The toss: a drachma spinning on its axis and settling.
struct DraftCoin: View {
    var size: CGFloat = 84
    @State private var turn: Double = 0

    var body: some View {
        ItemIcon(key: "drachma", size: size, glow: true)
            .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0))
            .onAppear {
                withAnimation(.easeOut(duration: 1.6)) {
                    turn = 1_800
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - The board's sizes

/// Every size the board uses, solved once from the space it is given, in the
/// arena lobby's manner (`ArenaLobbyMetrics`): WIDE from 700 points (every
/// Face ID iPhone) and NARROW below it (an SE). On an iPhone 16 Pro the board
/// has 750 × 329 points: two 150-point columns of five 52-point places, and
/// a 410-point middle with room for six 52-point roster tiles a row.
struct DraftBoardMetrics {
    static let gap: CGFloat = 8
    static let header: CGFloat = 30
    static let slotGap: CGFloat = 5

    let side: CGFloat
    let slot: CGFloat
    let tile: CGFloat
    let banTile: CGFloat
    let nameSize: CGFloat
    let compact: Bool

    init(size: CGSize) {
        let wide = size.width >= 700
        side = wide ? 150 : 128
        let usable = size.height - 12 - DraftBoardMetrics.header - 5 * DraftBoardMetrics.slotGap
        slot = max(40, min(54, (usable / 5).rounded(.down)))
        tile = wide ? 52 : 46
        let middle = size.width - 2 * ScreenChrome.contentPadding - 2 * side - 2 * DraftBoardMetrics.gap
        banTile = max(40, min(64, ((middle - 20 - 84) / 5).rounded(.down)))
        nameSize = wide ? 12 : 11
        compact = size.height < 320
    }
}
