import SwiftUI

// MARK: - Glass: the shared parts of a PLACE screen (2026-09-22, phase B)
//
// Phase A's rule, as a test a frame passes or fails: a screen that is a PLACE
// (somewhere the player goes, with its own painting) shows the painting
// full-bleed and puts its words on dark glass; a screen that is DATA stays
// cream marble. Phase B rebuilds seven screen groups to that rule at once, and
// the research for it (PLAN.md, *Phase B of the premium pass*) found four
// proposals naming a glass section header four ways, two `GlassBead`s of
// incompatible types and three edits to the same private ambience struct. So
// the parts are written ONCE, here, before any screen is touched, and every
// place screen builds on them.
//
// What is where:
// - Here: `PlaceBackdrop`, `LightShaft`/`LightShafts`/`Motes`/`PlaceAmbience`,
//   `GlassPlate`, `GlassSectionHeader`, `GlassSection`, `GlassRailPlate`,
//   `GlassRowPlate`, `PlaceRail`/`PlaceRailLabel`/`PlaceRailRow`, `GlassBead`,
//   `GlassCapsule`, `PlaceTitle`, `InfoGlyph`/`InfoDot`, `GlassMeter`,
//   `UnitPortraitTile`, `EmptyUnitSlot`, `CostWell`, `RequirementTile`,
//   `ClaimStatus`/`ClaimPlate`, `MarbleRowPlate`, `GrantReceipt`.
// - Components.swift: `PaintingFill(name:focus:)`, `RewardTile(... onGlass:)`,
//   `EmptyState(... onGlass:)`, `PrimaryButton` (a disabled `.glass` stays
//   glass; `PrimaryButton.height`), `ChromeArt`, `MedallionIcon`, `UnitCard`.
// - Theme.swift: the words-on-glass colours (`onGlass`, `onGlassDim`,
//   `onGlassGold`, `onGlassEyebrow`, `onGlassSuccess`, `onGlassDanger`,
//   `onGlassWarning`), `glass`, `glassRim`, `socketFill`, `goldText`.
//
// Two rules the critic added and every caller of these keeps: a tab screen's
// content is measured UNDER the 58-point `GameTabBar`, and nothing here or on
// a place screen uses `ViewThatFits` (it lays out every candidate) — measure
// a width with a `GeometryReader` instead.

// MARK: - The place itself

/// The ground of every PLACE screen: near-black under the painting (so a
/// missing painting is a dark room, never cream), the painting cropped to its
/// `focus`, an optional colour wash, and the summon hall's two dark scrims —
/// black `topScrim` fading out over 110 points so carved words read at the
/// top, and black `footScrim` fading in over 130 so the deck reads at the
/// foot. It never takes a tap and it is exactly the size it is given (the
/// scrims are overlays, which are never measured), so it is safe as a
/// `.background` or as the bottom layer of a `ZStack`.
///
/// Motes and light shafts are NOT in it — that is `PlaceAmbience`, laid over
/// it — so the two cannot collide. Used by the Arena, the dungeon levels and
/// the Halls, the Titans wing, the Hall of Ka, the stage briefing and the
/// bazaar; it replaces five sets of inline scrims those screens wrote.
struct PlaceBackdrop: View {
    let painting: String
    var focus: UnitPoint = .center
    var wash: Color = .clear
    var topScrim: Double = 0.55
    var footScrim: Double = 0.62

    var body: some View {
        ZStack {
            Color(hex: "#0E0B08")
            PaintingFill(name: painting, focus: focus)
            wash
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color.black.opacity(topScrim), Color.black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(footScrim)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - The air of a place

/// One shaft of light falling across a painted room, in fractions of the
/// frame: where its top stands across the width, how wide it is, and how
/// bright. `hall` is the summon hall's three (the look it has had since
/// 2026-09-22 morning); `sanctuary` is one shaft laid along the light the
/// Hall of Ka's painting already has (`hall_of_ka_bg`: the painted shaft's
/// top spans 0.13–0.36 of the width).
struct LightShaft {
    var x: Double
    var width: Double
    var alpha: Double

    static let hall: [LightShaft] = [
        LightShaft(x: 0.30, width: 0.09, alpha: 0.16),
        LightShaft(x: 0.47, width: 0.06, alpha: 0.11),
        LightShaft(x: 0.66, width: 0.11, alpha: 0.09),
    ]

    static let sanctuary: [LightShaft] = [
        LightShaft(x: 0.22, width: 0.12, alpha: 0.10),
    ]
}

/// Soft shafts of light falling from the upper left across a room, drifting
/// slowly and breathing. The shafts are data since phase B, so the summon
/// hall and the Hall of Ka can each lay theirs where their painting's own
/// windows are.
struct LightShafts: View {
    var shafts: [LightShaft] = LightShaft.hall

    var body: some View {
        let shafts = self.shafts
        return TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for (index, shaft) in shafts.enumerated() {
                    let drift = sin(t * 0.13 + Double(index) * 2.1) * 0.02
                    let top = (shaft.x + drift) * size.width
                    let lean = size.width * 0.16
                    let w = shaft.width * size.width
                    var path = Path()
                    path.move(to: CGPoint(x: top - w * 0.5, y: -4))
                    path.addLine(to: CGPoint(x: top + w * 0.5, y: -4))
                    path.addLine(to: CGPoint(x: top + w * 1.1 + lean, y: size.height + 4))
                    path.addLine(to: CGPoint(x: top - w * 1.1 + lean, y: size.height + 4))
                    path.closeSubpath()
                    let breathe = 0.8 + 0.2 * sin(t * 0.4 + Double(index))
                    context.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [Color.white.opacity(shaft.alpha * breathe), Color.white.opacity(0)]),
                            startPoint: CGPoint(x: top, y: 0),
                            endPoint: CGPoint(x: top + lean, y: size.height * 0.9)
                        )
                    )
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// Rising motes of light over a painting — the launch screen's embers, for
/// any hero screen. Drawn on one canvas, so a mote costs nothing.
struct Motes: View {
    var count: Int = 22
    var color: Color = Color(hex: "#FFD678")
    var seed: UInt64 = 900

    private struct Mote {
        let x: Double
        let speed: Double
        let phase: Double
        let size: Double
        let sway: Double
    }

    private var motes: [Mote] {
        (0..<count).map { index in
            var rng = SeededRandom(seed: seed + UInt64(index))
            return Mote(
                x: rng.double(in: 0.02...0.98),
                speed: rng.double(in: 0.04...0.10),
                phase: rng.double(in: 0...1),
                size: rng.double(in: 1.2...3.0),
                sway: rng.double(in: 8...26)
            )
        }
    }

    var body: some View {
        let motes = self.motes
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for (index, mote) in motes.enumerated() {
                    let travel = (t * mote.speed + mote.phase).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1.05 - travel * 1.1)
                    let x = size.width * mote.x + sin(t * 0.7 + Double(index)) * mote.sway
                    let pulse = 0.25 + 0.55 * (0.5 + 0.5 * sin(t * 2.1 + Double(index) * 1.3))
                    let fade = travel < 0.1 ? travel / 0.1 : (travel > 0.85 ? (1 - travel) / 0.15 : 1)
                    let rect = CGRect(x: x - mote.size, y: y - mote.size, width: mote.size * 2, height: mote.size * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(pulse * fade)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The air of a painted place, over the painting and under the words: light
/// shafts (none when `shafts` is empty) and motes (none when `motes` is 0).
///
/// It is the summon hall's private `HallAmbience` made shared, and its
/// defaults ARE the hall's (the three hall shafts, 26 motes of #FFE29A, seed
/// 910), so `PlaceAmbience()` is the summon screen exactly as it was. The
/// Arena lays dust over its sand (`shafts: []`, 24, #F2C987, seed 930), the
/// Hall of Ka its one sanctuary shaft (`LightShaft.sanctuary`, 18, seed 944),
/// the Labyrinth its key light's motes (`shafts: []`, 18), and the bazaar its
/// brazier sparks (`shafts: []`, 18, #FFB866 — a seed of its own, since 930
/// is the Arena's). One seed per screen keeps two places from sharing a sky.
struct PlaceAmbience: View {
    var shafts: [LightShaft] = LightShaft.hall
    var motes: Int = 26
    var moteColor: Color = Color(hex: "#FFE29A")
    var seed: UInt64 = 910

    var body: some View {
        ZStack {
            if !shafts.isEmpty {
                LightShafts(shafts: shafts)
            }
            if motes > 0 {
                Motes(count: motes, color: moteColor, seed: seed)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Glass

/// A dark glass plate over art, with a gold rim and a lit top edge.
///
/// `opacity` is the glass's depth: the default is `Theme.glass`'s own 0.68,
/// which every plate of phase A draws; a modal card over a dimmed map (the
/// stage popup, 0.88) or a long paragraph (the chapter scroll, 0.86) goes
/// deeper so the words read. Used by every place screen's plates.
struct GlassPlate: View {
    var radius: CGFloat = Theme.cornerRadius
    var opacity: Double = 0.68

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(hex: "#17120E").opacity(opacity))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.glassRim, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(0, radius - 1), style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                    .padding(1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
    }
}

/// The one section label on glass, `SectionPanel`'s header for the dark side
/// of the rule: the section's name in carved Cinzel at 13 (the title floor —
/// one proposal wrote `title(10)`, which is 13 after the floor anyway and
/// read as if it were smaller), a gold hairline fading right, and an
/// accessory in numeric 11.5, optionally with its painted item. Both ends
/// take their own width (`fixedSize`), so a title never wraps ("OFFENC/E",
/// 2026-09-10) and an accessory never truncates; the hairline takes what is
/// left. `accessoryTint` carries meaning — the popup's power comparison is
/// `Theme.onGlassSuccess` or `Theme.onGlassDanger`.
///
/// Used by the Arena, the Labyrinth's drops, the Hall of Ka's ledgers, the
/// stage popup and the briefing (through `GlassSection`).
struct GlassSectionHeader: View {
    let title: String
    var accessory: String? = nil
    var accessoryItemKey: String? = nil
    var accessoryTint: Color = Theme.onGlassDim

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Theme.title(13))
                .tracking(1.6)
                .carved(glow: false)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(LinearGradient(colors: [Theme.gold.opacity(0.75), Theme.gold.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            if let accessory {
                HStack(spacing: 4) {
                    if let accessoryItemKey {
                        ItemIcon(key: accessoryItemKey, size: 16, glow: false)
                    }
                    Text(accessory)
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(accessoryTint)
                        .lineLimit(1)
                        .fixedSize()
                }
                .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            }
        }
    }
}

/// The glass twin of `SectionPanel`: a `GlassSectionHeader`, the content, 10
/// points of padding, on a `GlassPlate` of the given depth. Written
/// `GlassSection(title: "Your team", accessory: "Power 12,400") { … }`.
/// Used by the stage briefing (Opposition, Your team, Spoils), the Arena's
/// teams plate, the Labyrinth's drops and the Hall of Ka's ledger shell.
struct GlassSection<Content: View>: View {
    let title: String
    var accessory: String?
    var accessoryTint: Color
    var opacity: Double
    let content: () -> Content

    init(
        title: String,
        accessory: String? = nil,
        accessoryTint: Color = Theme.onGlassDim,
        opacity: Double = 0.68,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.accessoryTint = accessoryTint
        self.opacity = opacity
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: title, accessory: accessory, accessoryTint: accessoryTint)
            content()
        }
        .padding(10)
        .background(GlassPlate(radius: Theme.tightCorner + 4, opacity: opacity))
    }
}

// MARK: - The rail

/// The ground of a list rail down the side of a place: near-black glass
/// darkest at the screen's edge, fading toward the painting, with a gold
/// hairline down its inner edge. It is the summon screen's rail plate, shared
/// so the bazaar's stalls, the Labyrinth's floors, the Titans and the Hall of
/// Ka's roster are one object. Never takes a tap.
struct GlassRailPlate: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [Color(hex: "#0E0B08").opacity(0.86), Color(hex: "#0E0B08").opacity(0.62)],
                startPoint: .leading,
                endPoint: .trailing
            )
            Rectangle()
                .fill(
                    LinearGradient(colors: [Theme.gold.opacity(0.0), Theme.gold.opacity(0.7), Theme.gold.opacity(0.0)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 1)
        }
        .allowsHitTesting(false)
    }
}

/// One row's plate on a glass rail: off, a breath of white with a faint rim;
/// on, a gold plate with a bright rim and a glow — the summon screen's banner
/// rows. Floor rows, Titan tiles, stall rows and roster rows wear it, as a
/// row's `.background` — it takes the row's taps with it, so it is NOT
/// `allowsHitTesting(false)` like the rail plate under it.
struct GlassRowPlate: View {
    let isOn: Bool
    var radius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(isOn
                  ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#6A5020"), Color(hex: "#2E2210")],
                                                 startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(Color.white.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isOn ? Theme.gold.opacity(0.95) : Color.white.opacity(0.12), lineWidth: isOn ? 1.2 : 0.8)
            )
            .shadow(color: isOn ? Theme.gold.opacity(0.45) : .clear, radius: 8)
    }
}

/// A rail down the left of a place: a scrolling column on a `GlassRailPlate`
/// that ends in a fade instead of at the screen's edge (the summon rail's
/// last row was once guillotined through its own count). Put
/// `PlaceRailLabel`s and `PlaceRailRow`s (or a screen's own rows on
/// `GlassRowPlate`s) inside. Used by the bazaar's stalls, the Labyrinth's
/// floors, the Titans and the Hall of Ka's roster.
struct PlaceRail<Content: View>: View {
    let width: CGFloat
    let content: () -> Content

    init(width: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.width = width
        self.content = content
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                content()
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .mask(
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        )
        .background(GlassRailPlate())
    }
}

/// A section's name on a rail ("PANTHEONS", "STALLS"), carved, at the title
/// floor of 13.
struct PlaceRailLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(Theme.title(13))
            .tracking(2.0)
            .carved(glow: false)
            .lineLimit(1)
            .fixedSize()
            .padding(.top, 8)
            .padding(.leading, 4)
    }
}

/// One row of a rail: a 36-point dark disc with the thing's painting (its
/// `itemKey`) or its glyph in gold, its name in Cinzel at 13 on up to two
/// lines — never shrunk, never cut — an optional count in a gold bead, an
/// optional claim dot, on a `GlassRowPlate`. The bazaar's stall rows; the
/// Labyrinth and the Titans may use it for any row that is a name and a
/// count. A row that has nothing to spend dims itself at the call site
/// (`.opacity`), as the summon rail does.
struct PlaceRailRow: View {
    let title: String
    var itemKey: String? = nil
    var systemImage: String = "circle.fill"
    let isOn: Bool
    var accessory: String? = nil
    var dot: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            action()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.35))
                    if let itemKey, ItemArt.hasPainting(itemKey) {
                        ItemIcon(key: itemKey, size: 32, glow: false)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Theme.gold)
                    }
                }
                .frame(width: 36, height: 36)
                Text(title)
                    .font(Theme.title(13))
                    .foregroundStyle(isOn ? Color(hex: "#FFF1C2") : Theme.onGlass)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                if let accessory {
                    Text(accessory)
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .overlay(Capsule().strokeBorder(Theme.goldDim.opacity(0.7), lineWidth: 0.6))
                }
                if dot {
                    Circle()
                        .fill(Color(hex: "#E8BE50"))
                        .frame(width: 9, height: 9)
                        .shadow(color: Color(hex: "#E8BE50").opacity(0.8), radius: 4)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(GlassRowPlate(isOn: isOn))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Beads and titles

/// A reading, or a quiet action, on glass: a capsule of glass with a painted
/// item (or a glyph) and a word or number beside it, at its own width so it
/// never truncates — the summon header's chip beads made shared. With an
/// `action` it is a button (a light haptic and the tap sound). Used by the
/// Arena's Rate/Holds chip, the Labyrinth's beads ("B3/10", "New"), the
/// bazaar's clocks and the chapter's tier capsule. For custom content inside
/// the same capsule, `GlassCapsule`.
struct GlassBead: View {
    let text: String
    var systemImage: String? = nil
    var itemKey: String? = nil
    var tint: Color = Theme.onGlass
    var height: CGFloat = 26
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                action()
            } label: {
                face
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text)
        } else {
            face
        }
    }

    private var face: some View {
        HStack(spacing: 5) {
            if let itemKey, ItemArt.hasPainting(itemKey) {
                ItemIcon(key: itemKey, size: 16, glow: false)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .black))
            }
            Text(text)
                .font(Theme.numeric(12))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: height)
        .background(Capsule().fill(Theme.glass))
        .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 0.8))
        .fixedSize()
        .contentShape(Capsule())
    }
}

/// The same glass capsule as `GlassBead`, holding anything: a countdown in a
/// `TimelineView`, a reading with its `InfoDot`. It takes its own width.
/// Used by the bazaar's "Resets in" and the Night Market's "New stock in".
struct GlassCapsule<Content: View>: View {
    let height: CGFloat
    let content: () -> Content

    init(height: CGFloat = 28, @ViewBuilder content: @escaping () -> Content) {
        self.height = height
        self.content = content
    }

    var body: some View {
        HStack(spacing: 5) {
            content()
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Capsule().fill(Theme.glass))
        .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 0.8))
        .fixedSize()
    }
}

/// A place's carved header: a gold eyebrow in tracked Cinzel at 13 over a
/// display title in carved gold, as the summon room draws its banner's name.
/// The title shrinks to fit one line but never under the title floor of 13.
/// Used by the bazaar's stall headers, the Labyrinth's floor title and the
/// starter selector.
struct PlaceTitle: View {
    var eyebrow: String? = nil
    let title: String
    var size: CGFloat = 26

    private var shrink: CGFloat {
        max(0.6, min(1, Theme.titleFloor / max(size, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(Theme.title(13))
                    .tracking(2.4)
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(title.uppercased())
                .font(Theme.display(size))
                .carved()
                .lineLimit(1)
                .minimumScaleFactor(shrink)
        }
    }
}

// MARK: - The little ?

/// The circled question mark itself, in one place so every ? is the same
/// object. It is drawn at 14 points inside a 26-point tap area: the glyph
/// has to be small enough to read as an aside rather than as a control, and
/// the target has to be big enough to hit with a thumb over a moving painting.
///
/// It is the OUTLINE `questionmark.circle`, not the filled one, because the
/// filled one is already the Unknown Scroll's own glyph (`ScrollType.glyph`)
/// and appears on that scroll's menu row, in the strip, and on both summon
/// plates whenever it is the scroll in hand.
///
/// Moved out of SummonView.swift, where it was private, in phase B
/// (2026-09-22): four proposals each planned the move, so it was done once,
/// here. The summon screen, the Arena, the Labyrinth, the Hall of Ka and the
/// bazaar draw it.
struct InfoGlyph: View {
    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(Theme.onGlassEyebrow)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
    }
}

/// A little ? that opens one short answer beside the thing it explains.
///
/// This is what the owner asked for in place of the slabs — "with little ? to
/// view other details" — and it is a popover rather than a sheet on purpose:
/// `.presentationCompactAdaptation(.popover)` keeps it a popover on a phone,
/// so the answer appears next to the question with the room still behind it,
/// where a sheet would cover the room to answer a question about it. Moved
/// out of SummonView.swift unchanged (2026-09-22).
struct InfoDot<Detail: View>: View {
    let title: String
    @ViewBuilder var detail: () -> Detail
    @State private var isOpen = false

    var body: some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            isOpen = true
        } label: {
            InfoGlyph()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(Theme.body(10).weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(Theme.goldDim)
                detail()
            }
            .padding(14)
            .frame(width: 272)
            .background(Theme.surface)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - A meter on glass

/// One bar on glass. `StatBar`'s recessed cream track reads as a pale stripe
/// on a dark plate, so this track is black at half with a thin glass rim; the
/// fill is the tint's gradient with a specular line and a soft glow, at least
/// as wide as it is tall once the value is above zero. `projected` draws the
/// genre's ghost — the gain a power-up would bring, pulsing pale gold ahead
/// of the fill — and `reachesNext` runs the ghost to the end (the gain
/// crosses a level). The Arena's tier meter and the Hall of Ka's EXP gauge
/// (which was a `ProjectedGauge` in its proposal) are this one bar; the
/// relic power-up may take it later.
struct GlassMeter: View {
    let value: Double
    let maximum: Double
    var projected: Double? = nil
    var reachesNext: Bool = false
    var tint: Color = Theme.gold
    var height: CGFloat = 6

    private func fraction(_ amount: Double) -> CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(min(1, max(0, amount / maximum)))
    }

    private var ghost: CGFloat? {
        if reachesNext { return 1 }
        guard let projected, projected > value else { return nil }
        return fraction(projected)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let filled = fraction(value)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.5))
                if let ghostFraction = ghost {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        let pulse = 0.475 + 0.125 * sin(timeline.date.timeIntervalSinceReferenceDate * 3)
                        Capsule()
                            .fill(Theme.onGlassGold.opacity(pulse))
                            .frame(width: max(height, width * ghostFraction))
                    }
                }
                if filled > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.95), tint, tint.opacity(0.65)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(
                            Capsule()
                                .fill(Color.white.opacity(0.4))
                                .frame(height: max(1, height * 0.28))
                                .padding(.horizontal, height * 0.3)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(.top, height * 0.16)
                        )
                        .frame(width: max(height, width * filled))
                        .shadow(color: tint.opacity(0.6), radius: 3)
                }
                Capsule().strokeBorder(Theme.glassRim.opacity(0.7), lineWidth: 0.8)
            }
        }
        .frame(height: height)
    }
}

// MARK: - A unit's face

/// A unit as a face alone — portrait, element, level, stars, the grade's
/// metal — with NO name, so nothing can be cut. `UnitCard`'s cream name strip
/// is half a small card: it truncated every name in run 211's arena
/// ("Anubi…", "Sekh…", "Azure…") and "Sun-Scar…" in the stage popup, and it
/// is a cream slab on glass; the genre's team rows over art are faces.
/// `tag` is a ribbon across the top edge (BOSS, WAVE 3), `isLeader` a crown
/// there. The name is in the accessibility label.
///
/// Used by the Arena's teams, the stage popup's and briefing's enemies and
/// team, the Hall of Ka's rail and fodder, the collection's Stage rail, the
/// selector and the mileage board — it replaces the Arena's `UnitFace`, the
/// chapter's private tile and the Hall's `UnitCardCaption`.
struct UnitPortraitTile: View {
    let unit: ResolvedUnit
    var size: CGFloat = 56
    var tag: String? = nil
    var tagTint: Color = Theme.onGlassDanger
    var isLeader: Bool = false

    private var corner: CGFloat { max(6, min(Theme.tightCorner, size * 0.14)) }
    private var wear: CGFloat { max(0.6, min(1, size / 80)) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return ZStack(alignment: .topLeading) {
            portrait
                .frame(width: size, height: size)
            LinearGradient(colors: [.clear, .clear, Theme.ink.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
            ElementBadge(element: unit.element, compact: true, scale: wear)
                .padding(max(2, 4 * wear))
            Text("\(unit.level)")
                .font(Theme.numeric(11.5))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .frame(height: 15)
                .background(Capsule().fill(Color.black.opacity(0.62)))
                .overlay(Capsule().strokeBorder(Theme.goldDim.opacity(0.8), lineWidth: 0.6))
                .padding(max(2, 3 * wear))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars,
                    size: max(5.5, min(9, size * 0.13)))
                .padding(.bottom, max(2, 3 * wear))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .rarityFrame(Rarity(stars: unit.stars), radius: corner, painted: false)
        .overlay(alignment: .top) {
            if isLeader || tag != nil {
                HStack(spacing: 3) {
                    if isLeader {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Theme.goldText)
                            .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                    }
                    if let tag {
                        Text(tag.uppercased())
                            .font(Theme.body(11).weight(.black))
                            .tracking(1.0)
                            .foregroundStyle(tagTint)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Capsule().fill(Color(hex: "#17120E").opacity(0.9)))
                            .overlay(Capsule().strokeBorder(tagTint.opacity(0.8), lineWidth: 0.8))
                    }
                }
                .offset(y: -8)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unit.name), level \(unit.level), \(unit.stars) stars")
    }

    /// The card's painting at the tile's own size, or the element-tinted
    /// initial `UnitCard` draws before a family has art.
    @ViewBuilder
    private var portrait: some View {
        let name = unit.blueprint.model.portraitName(awakened: unit.unit.isAwakened)
        if BundleImage.exists(name) {
            BundleImage(name: name, renderedAt: size)
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RadialGradient(
                    colors: [unit.element.color.opacity(0.75), unit.element.color.opacity(0.25), Color(hex: "#17120E")],
                    center: .init(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: size * 0.85
                )
                Text(String(unit.name.prefix(1)))
                    .font(Theme.display(size * 0.46))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            }
        }
    }
}

/// An empty place for a unit, the same square as `UnitPortraitTile`: a dark
/// well with a dashed glass rim and a plus on glass, or the cream plate with
/// a dashed stroke on marble. Used by the Arena's teams, the briefing's team
/// and the Hall of Ka's fodder slots.
struct EmptyUnitSlot: View {
    var size: CGFloat = 56
    var onGlass: Bool = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: max(6, min(Theme.tightCorner, size * 0.14)), style: .continuous)
        return shape
            .fill(onGlass ? Color.black.opacity(0.28) : Theme.plate.opacity(0.55))
            .overlay(
                shape.strokeBorder(onGlass ? Theme.glassRim : Theme.stroke,
                                   style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            )
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(onGlass ? Theme.onGlassEyebrow : Theme.goldDim)
            )
            .frame(width: size, height: size)
            .contentShape(shape)
    }
}

// MARK: - Costs

/// A price beside a button: the painted item and the amount in a dark well
/// as tall as the button (`PrimaryButton.height`), in cream when the player
/// can pay and in `onGlassDanger` when not — the genre's cost-on-the-button
/// read without changing `PrimaryButton`. Used by the Hall of Ka's footers
/// and relic awakening.
struct CostWell: View {
    let key: String
    let amount: Int
    var affordable: Bool = true
    var height: CGFloat = 46

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return HStack(spacing: 6) {
            ItemIcon(key: key, size: 20, glow: false)
            Text(amount.formatted())
                .font(Theme.numeric(14))
                .foregroundStyle(affordable ? Theme.onGlass : Theme.onGlassDanger)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(shape.fill(Color(hex: "#1C1610").opacity(0.9)))
        .overlay(shape.strokeBorder(Theme.goldDim.opacity(0.8), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// One cost on glass, read by its picture: the item painted in a dark socket
/// (`Theme.socketFill` in a bronze rim), a check on the corner once it is
/// met, "have / need" under it — green when met, amber when some is held,
/// rose when none — and an optional caption (where it drops) under that.
/// Used by the Hall of Ka's awakening essences; relic awakening's aether,
/// whetstones and boon pushes may take it.
struct RequirementTile: View {
    let key: String
    let have: Int
    let need: Int
    var caption: String? = nil
    var size: CGFloat = 56

    private var met: Bool { have >= need }

    private var countTint: Color {
        if met { return Theme.onGlassSuccess }
        return have > 0 ? Theme.onGlassWarning : Theme.onGlassDanger
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
        return VStack(spacing: 3) {
            ZStack {
                shape.fill(Theme.socketFill)
                shape.strokeBorder(Theme.bronzeFrame, lineWidth: 1)
                ItemIcon(key: key, size: size * 0.8, glow: false)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if met {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Theme.onGlassSuccess)
                        .background(Circle().fill(Color.black).padding(1))
                        .offset(x: 4, y: -4)
                }
            }
            Text("\(BarWallet.compact(have)) / \(need)")
                .font(Theme.numeric(11.5))
                .foregroundStyle(countTint)
                .lineLimit(1)
                .fixedSize()
            if let caption {
                Text(caption)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: size + 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Claims and receipts

/// Where a claimable thing stands: ready to take, not yet earned, taken.
/// Top level on purpose: `State` and `Phase` are SwiftUI's and another
/// type's names.
enum ClaimStatus {
    case ready, waiting, done
}

/// One claim control in three states, so a row that cannot be claimed never
/// reads as a link (run 211's Missions frame): gold with a gloss when ready,
/// a greyed plate when waiting, a seal and DONE when taken; on cream or on
/// glass. It replaces the identical private claim buttons of Missions and
/// Events and serves the gift, tribute and prize cards.
struct ClaimPlate: View {
    let status: ClaimStatus
    var title: String = "Claim"
    var onGlass: Bool = false
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch status {
        case .ready:
            Button {
                Juice.haptic(.medium)
                AudioLibrary.shared.play(.uiConfirm)
                action()
            } label: {
                Text(title.uppercased())
                    .font(Theme.title(13))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(shape.fill(Theme.goldPlate))
                    .overlay(
                        shape.fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear],
                                                  startPoint: .top, endPoint: .center))
                            .allowsHitTesting(false)
                    )
                    .overlay(shape.strokeBorder(Color(hex: "#FFE9A8").opacity(0.55), lineWidth: 1))
                    .shadow(color: Theme.gold.opacity(0.35), radius: 6, y: 2)
            }
            .buttonStyle(PlateButtonStyle())
        case .waiting:
            Text(title.uppercased())
                .font(Theme.title(13))
                .tracking(1.2)
                .foregroundStyle(onGlass ? Theme.onGlassDim.opacity(0.7) : Theme.textSecondary.opacity(0.75))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(shape.fill(onGlass ? Color.black.opacity(0.3) : Theme.surface))
                .overlay(shape.strokeBorder(onGlass ? Theme.glassRim.opacity(0.4) : Theme.stroke, lineWidth: 1))
        case .done:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(onGlass ? Theme.onGlassSuccess : Theme.success)
                Text("DONE")
                    .font(Theme.title(13))
                    .tracking(1.2)
                    .foregroundStyle(onGlass ? Theme.onGlassDim : Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
    }
}

/// The raised cream row of a DATA list: the drawn panel's marble with its
/// bevel and a dark hairline, and a gold rim and glow when the row has
/// something to take. The Missions' rows; the relic inventory, social mail
/// and the rate table may take it.
struct MarbleRowPlate: View {
    var isLit: Bool = false
    var radius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(Theme.drawnPanelPlate)
            .overlay(shape.strokeBorder(Theme.bevel, lineWidth: 1))
            .overlay(
                shape.strokeBorder(isLit ? Theme.gold : Color(hex: "#6B5636").opacity(0.28),
                                   lineWidth: isLit ? 1.5 : 1)
            )
            .shadow(color: isLit ? Theme.gold.opacity(0.35) : Color.black.opacity(0.10),
                    radius: isLit ? 7 : 3, y: isLit ? 0 : 2)
    }
}

/// What a claim or a purchase paid, as the genre's strip of painted reward
/// tiles rather than a sentence: a title and up to six `RewardTile`s, with a
/// "+N" bead for the rest (the Testing stall's "Every essence" pack pays 18
/// grants). On glass by default; `onGlass: false` sits it on a cream plate
/// with a gold rim for a marble screen. It never takes a tap; the caller
/// shows it and takes it away (`.transition` is set). Used by the bazaar and
/// the Missions, and later the island's offering toast and the events banner.
struct GrantReceipt: View {
    let title: String
    let grants: [ShopService.Grant]
    var onGlass: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if onGlass {
                    Text(title.uppercased())
                        .font(Theme.title(13))
                        .tracking(1.4)
                        .carved(glow: false)
                } else {
                    Text(title.uppercased())
                        .font(Theme.title(13))
                        .tracking(1.4)
                        .foregroundStyle(Theme.goldDim)
                }
            }
            .lineLimit(1)
            .fixedSize()
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(grants.prefix(6).enumerated()), id: \.offset) { _, grant in
                    RewardTile(grant: grant, size: 48, showsTitle: false, onGlass: onGlass)
                }
                if grants.count > 6 {
                    Text("+\(grants.count - 6)")
                        .font(Theme.numeric(13))
                        .foregroundStyle(onGlass ? Theme.onGlass : Theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Capsule().fill(onGlass ? Color.black.opacity(0.45) : Theme.surfaceHigh))
                        .overlay(Capsule().strokeBorder(onGlass ? Theme.glassRim : Theme.stroke, lineWidth: 0.8))
                        .frame(height: 48)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(receiptPlate)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .allowsHitTesting(false)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var receiptPlate: some View {
        if onGlass {
            GlassPlate(radius: 12, opacity: 0.82)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.plate.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.goldPlate, lineWidth: 1.5)
                )
        }
    }
}
