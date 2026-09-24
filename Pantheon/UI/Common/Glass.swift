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
///
/// FULL-BLEED since run 216 (`bleeds`, on by default): the painting runs
/// under the side safe areas and the home indicator to the glass, while the
/// words and controls laid over it stay inside the safe area. Every place
/// photographed in cream columns — 62 points a side and a strip under the
/// foot — because the backdrop was sized to the safe frame and
/// `GameScreen`'s cream showed round it. The expansion is
/// `ignoresSafeArea`, which never changes the size reported to the parent,
/// so it is still safe as a `.background` or a `ZStack`'s bottom layer; it
/// only reaches an edge its frame TOUCHES, so put it outside any horizontal
/// padding. `bleeds: false` keeps it to the safe frame — for a painting a
/// 3D stage is registered to, until the stage shares the wider frame.
struct PlaceBackdrop: View {
    let painting: String
    var focus: UnitPoint = .center
    var wash: Color = .clear
    var topScrim: Double = 0.55
    var footScrim: Double = 0.62
    var bleeds: Bool = true

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
        .ignoresSafeArea(.container, edges: bleeds ? [.horizontal, .bottom] : [])
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
///
/// Each mote is LIGHT, not a dot (run 221's judges: "hard, flat dots … in a
/// still frame they read as dust on the screen", beside the Titan's card, on
/// the Arena's meter, above SWEEP): a soft halo three times its size at a
/// quarter of its brightness under a small bright core, both radial falloffs
/// with no edge, ADDED to the painting (`plusLighter`) as the light shafts
/// are. They can be born `footClearance` points above the canvas's foot —
/// halo and all — and rise from there, so none drifts through the band
/// under it: `PlaceAmbience` keeps a place's motes out of its deck and the
/// home indicator's band that way, where a speck read as a mark on the
/// glass. Called directly (the Arena's gap between two plates, Hell's
/// embers on the chapter map) a canvas uses all of its height.
struct Motes: View {
    var count: Int = 22
    var color: Color = Color(hex: "#FFD678")
    var seed: UInt64 = 900
    /// The band at the canvas's foot the motes never enter.
    var footClearance: CGFloat = 0

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
        let color = self.color
        let clearance = Double(max(0, footClearance))
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let width = Double(size.width)
                let height = Double(size.height)
                for (index, mote) in motes.enumerated() {
                    let halo: Double = mote.size * 3
                    // Born with the whole halo above the clear band, gone a
                    // little past the top.
                    let start: Double = height - clearance - halo
                    guard start > 0 else { continue }
                    let travel = (t * mote.speed + mote.phase).truncatingRemainder(dividingBy: 1)
                    let y: Double = start - travel * (start + height * 0.05)
                    let x: Double = width * mote.x + sin(t * 0.7 + Double(index)) * mote.sway
                    let pulse = 0.25 + 0.55 * (0.5 + 0.5 * sin(t * 2.1 + Double(index) * 1.3))
                    let fade = travel < 0.1 ? travel / 0.1 : (travel > 0.85 ? (1 - travel) / 0.15 : 1)
                    let alpha: Double = pulse * fade
                    let centre = CGPoint(x: x, y: y)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2)),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(0.25 * alpha), color.opacity(0)]),
                            center: centre, startRadius: 0, endRadius: CGFloat(halo)
                        )
                    )
                    let core: Double = max(0.9, mote.size * 0.7)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - core, y: y - core, width: core * 2, height: core * 2)),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(alpha), color.opacity(alpha * 0.55), color.opacity(0)]),
                            center: centre, startRadius: 0, endRadius: CGFloat(core)
                        )
                    )
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// The air of a painted place, over the painting and under the words: light
/// shafts (none when `shafts` is empty) and motes (none when `motes` is 0).
///
/// It is the summon hall's private `HallAmbience` made shared, and its
/// defaults ARE the hall's (the three hall shafts, 26 motes of #FFE29A, seed
/// 910), so `PlaceAmbience()` is the summon screen's air. The
/// Arena lays dust over its sand (`shafts: []`, 24, #F2C987, seed 930), the
/// Hall of Ka its one sanctuary shaft (`LightShaft.sanctuary`, 18, seed 944),
/// the Labyrinth its key light's motes (`shafts: []`, 18), and the bazaar its
/// brazier sparks (`shafts: []`, 18, #FFB866 — a seed of its own, since 930
/// is the Arena's). One seed per screen keeps two places from sharing a sky.
///
/// It bleeds to the glass with the backdrop it lies over (`bleeds`, on by
/// default since run 216), so the air and the painting share one frame.
///
/// The motes keep out of the place's foot (`moteClearance`, 80 points of the
/// bled frame): the deck — a 46-point button row, its 10 points of padding
/// and the 21-point home indicator — is where a mote drifting over a button
/// or under the gesture bar read as dust (run 221: above SWEEP on the
/// briefing). A place whose foot is not a deck says less.
struct PlaceAmbience: View {
    var shafts: [LightShaft] = LightShaft.hall
    var motes: Int = 26
    var moteColor: Color = Color(hex: "#FFE29A")
    var seed: UInt64 = 910
    var bleeds: Bool = true
    var moteClearance: CGFloat = 80

    var body: some View {
        ZStack {
            if !shafts.isEmpty {
                LightShafts(shafts: shafts)
            }
            if motes > 0 {
                Motes(count: motes, color: moteColor, seed: seed, footClearance: moteClearance)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea(.container, edges: bleeds ? [.horizontal, .bottom] : [])
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
        // Out under the left inset when the rail stands on the safe edge, so
        // the glass meets the glass of the phone rather than a strip of bare
        // painting beside the sensor housing; and down under the home
        // indicator for the same reason — the bazaar's stalls ended on a hard
        // line 21 points above the foot with bare painting under it (run
        // 221). A rail over a tab bar does not touch the bottom inset, so
        // nothing there moves.
        .ignoresSafeArea(.container, edges: [.leading, .bottom])
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
///
/// `footSpace` lengthens the room after the last row past its 24 points —
/// what a `WholeRowRail` near its end asks for, so it can scroll its top row
/// whole to the top. It is part of the last clear rather than a row of its
/// own, which would add the rows' 5-point gap on top of what was asked
/// (run 221's plan over-provided by exactly that).
struct PlaceRail<Content: View>: View {
    let width: CGFloat
    let footSpace: CGFloat
    let content: () -> Content

    init(width: CGFloat, footSpace: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.width = width
        self.footSpace = footSpace
        self.content = content
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                content()
                Color.clear.frame(height: 24 + max(0, footSpace))
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        // A fade at BOTH ends (run 216): a row scrolled up under the strip
        // was cut on a hard line with only the foot fading.
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.025),
                                   .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
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
            // The row sits in a scrolling rail, so it wears the quiet press
            // and its tap stays here, on the lift of a real tap.
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
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel(title)
    }
}

// MARK: - A rail that opens on whole rows

/// A `PlaceRail` that opens on WHOLE rows, on the row the screen is about
/// (run 217): the Labyrinth's floors and Titans, and the Hall of Ka's roster.
/// Centring the focused row left the row above it cut in half under the
/// rail's head — B4's disc sliced through its label on frame 16, the Gale
/// Titan without its eyebrow or its rim on frame 39. Now the focused row
/// opens third from the top, the row at the top standing exactly where the
/// first stands at rest; near the end, where the rail could not scroll that
/// far, its foot is lengthened (`PlaceRail.footSpace`) so it can; and the
/// focused row always clears the foot's fade. The rows are measured, since a
/// Titan's name runs to two lines or three.
///
/// The opening follows the MEASUREMENTS, never a clock (run 220), and it
/// follows them until the player takes the rail (run 221). A rail passes
/// through heights on its way to its own — 87 points on the Titans rail and
/// 259 on the floors' against the 304 they came to — and a plan made once,
/// on the first of them, never landed: the Titans opened unscrolled with
/// the chosen Umbra under the foot, and B10's rail, scrolled while short,
/// was clamped past its top row when it grew. So the rail plans again
/// whenever its height or a row's changes; a height that cannot hold the
/// tallest row with a lead above and below it is one it is passing through,
/// and is not planned on; every scroll, first or repeated, is built from the
/// height measured at that moment, never the one planned on; and the landing
/// is read back 0.3 s after each scroll and repeated, twice at most, with
/// "missed" in the console when the third read still misses.
///
/// The player takes the rail by picking a row, or by scrolling it — the
/// landed row moving while the rail's height stands still — and from then on
/// nothing re-plans until the rail appears again. No drag gesture is laid
/// over the scroll to learn that: a simultaneous drag on a scroll view stops
/// it scrolling, or makes it jitter, on iOS 18 and iOS 26 (Apple's developer
/// forums, 2024–25), and this game ships to a phone on the newest iOS. A
/// rail with a row never measured a second after it appears centres the
/// focused row, the old behaviour, rather than showing it nowhere. Each step
/// prints a `[Rail]` line to the console.
///
/// The top edge is soft: a row scrolled up past where the top row stands
/// fades out over `WholeRowPlan.fadeSpan` of travel (`rowOpacity`, read off
/// the row's place in the scroll), so a row passing under the head dissolves
/// rather than being cut at full brightness on the rail's 8-point mask, and
/// the sliver of the row above an opened top row is not drawn at all. Only
/// the rows fade; the rail's glass stays whole.
struct WholeRowRail<Item: Identifiable, Row: View>: View {
    let width: CGFloat
    let items: [Item]
    /// The row to open on; nil opens at the top.
    let focus: Item.ID?
    let row: (Item) -> Row

    /// The rows' heights and places, the rail's height and where the opening
    /// stands, in a class so a measurement never lays the rail out again.
    @State private var gauge = RailRowGauge<Item.ID>()
    /// The room after the last row that lets the top row be whole at the
    /// rail's end (`PlaceRail.footSpace`).
    @State private var tail: CGFloat = 0

    init(width: CGFloat, items: [Item], focus: Item.ID?, @ViewBuilder row: @escaping (Item) -> Row) {
        self.width = width
        self.items = items
        self.focus = focus
        self.row = row
    }

    var body: some View {
        GeometryReader { geometry in
            // Read with each row's own place, in the same pass, so a row
            // that moved can be told from a rail that changed height.
            let railHeight = geometry.size.height
            ScrollViewReader { proxy in
                PlaceRail(width: width, footSpace: tail) {
                    ForEach(items) { item in
                        row(item)
                            .background {
                                GeometryReader { box in
                                    let place = RailRowPlace(
                                        height: box.size.height,
                                        top: box.frame(in: .scrollView).minY,
                                        viewport: railHeight
                                    )
                                    Color.clear
                                        .onAppear { measured(item.id, place, proxy: proxy) }
                                        .onChange(of: place) { _, now in
                                            measured(item.id, now, proxy: proxy)
                                        }
                                }
                                .allowsHitTesting(false)
                            }
                            .visualEffect { content, place in
                                content.opacity(WholeRowPlan.rowOpacity(top: place.frame(in: .scrollView).minY))
                            }
                            .id(item.id)
                    }
                }
                .onAppear {
                    gauge.pass += 1
                    gauge.touched = false
                    gauge.viewport = railHeight
                    settle(proxy, from: "appear")
                    let pass = gauge.pass
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        centreIfUnsettled(proxy, pass: pass)
                    }
                }
                .onChange(of: geometry.size.height) { _, height in
                    gauge.viewport = height
                    settle(proxy, from: "viewport")
                }
                .onChange(of: tail) { _, _ in
                    // The room at the foot is laid out by the next turn of
                    // the run loop; scrolled to before it, the scroll stops
                    // at the old end.
                    DispatchQueue.main.async { issue(proxy) }
                }
                .onChange(of: focus) { _, _ in
                    // A row picked on the rail: the rail stays under the
                    // finger that picked it.
                    gauge.touched = true
                }
                .onDisappear {
                    gauge.pass += 1
                    gauge.opened = false
                    gauge.waiting = false
                    gauge.landedID = nil
                }
            }
        }
        .frame(width: width)
    }

    /// One row's measurements, kept; a row whose height is new plans the
    /// opening again. The landed row moving while the rail's height stands
    /// still is a finger on the rail, and the rail is the player's.
    private func measured(_ id: Item.ID, _ place: RailRowPlace, proxy: ScrollViewProxy) {
        let resized = gauge.heights[id].map { abs($0 - place.height) > 0.5 } ?? true
        gauge.heights[id] = place.height
        gauge.tops[id] = place.top
        if !resized, !gauge.touched, !gauge.waiting, id == gauge.landedID,
           abs(place.viewport - gauge.landedViewport) < 0.5,
           abs(place.top - WholeRowPlan.lead) > 3 {
            gauge.touched = true
            #if DEBUG
            print("[Rail] focus=\(Self.describe(focus)) scrolled by the player; it is his now")
            #endif
        }
        if resized {
            settle(proxy, from: "row")
        }
    }

    /// Plans the opening from what is measured now, and issues it or sets the
    /// room it needs at the foot first. Called by every measurement; it does
    /// nothing once the player has the rail, while a planned scroll waits for
    /// its room, or when nothing has moved since the last scroll.
    private func settle(_ proxy: ScrollViewProxy, from source: String) {
        guard !gauge.touched, !gauge.waiting,
              let heights = measuredHeights(), let plan = currentPlan(heights) else { return }
        if gauge.opened, abs(gauge.viewport - gauge.plannedViewport) < 0.5, Self.same(heights, gauge.plannedHeights) {
            return
        }
        gauge.opened = false
        gauge.landedID = nil
        gauge.waiting = true
        gauge.source = source
        if abs(plan.tail - tail) < 0.5 {
            DispatchQueue.main.async { issue(proxy) }
        } else {
            // `onChange(of: tail)` issues the scroll once the room is in.
            tail = plan.tail
        }
    }

    /// Scrolls to the plan as it stands NOW — the rail may have changed
    /// height while the room at the foot was laid out — and reads the
    /// landing back.
    private func issue(_ proxy: ScrollViewProxy) {
        guard gauge.waiting else { return }
        guard !gauge.touched, let heights = measuredHeights(), let plan = currentPlan(heights) else {
            // A later measurement plans again.
            gauge.waiting = false
            return
        }
        if abs(plan.tail - tail) >= 0.5 {
            // The rail moved under the plan: its room first, and
            // `onChange(of: tail)` comes back here.
            tail = plan.tail
            return
        }
        gauge.waiting = false
        gauge.opened = true
        scroll(proxy, to: plan, heights: heights)
        #if DEBUG
        print("[Rail] focus=\(Self.describe(focus)) planned from \(gauge.source): viewport=\(Int(gauge.viewport.rounded())) "
              + "measured=\(heights.count)/\(items.count) top=\(Self.describe(items[plan.top].id)) "
              + "tail=\(Int(plan.tail.rounded())) anchor=\(plan.anchor)")
        #endif
        let pass = gauge.pass
        let issued = gauge.issued
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            check(proxy, attempt: 1, pass: pass, issued: issued)
        }
    }

    /// The top row should stand `WholeRowPlan.lead` below the rail's top. The
    /// plan is built again from the height measured now, and a scroll lost
    /// to a layout still in flight is repeated from it, twice at most.
    private func check(_ proxy: ScrollViewProxy, attempt: Int, pass: Int, issued: Int) {
        guard pass == gauge.pass, issued == gauge.issued, !gauge.touched, !gauge.waiting,
              let heights = measuredHeights(), let plan = currentPlan(heights) else { return }
        if abs(plan.tail - tail) >= 0.5 {
            // The rail changed height since the scroll: plan it again.
            gauge.opened = false
            gauge.waiting = true
            gauge.source = "check"
            tail = plan.tail
            return
        }
        let id = items[plan.top].id
        let top = gauge.tops[id]
        let miss = top.map { abs($0 - WholeRowPlan.lead) } ?? .infinity
        #if DEBUG
        let stood = top.map { "\(Int($0.rounded()))" } ?? "unmeasured"
        #endif
        if miss <= 1.5 {
            gauge.landedID = id
            gauge.landedViewport = gauge.viewport
            #if DEBUG
            print("[Rail] \(Self.describe(id)) landed at \(stood) after \(attempt) check(s)")
            #endif
        } else if attempt < 3 {
            #if DEBUG
            print("[Rail] \(Self.describe(id)) stood at \(stood), not \(Int(WholeRowPlan.lead)); "
                  + "scrolling again (\(attempt)) at viewport=\(Int(gauge.viewport.rounded()))")
            #endif
            scroll(proxy, to: plan, heights: heights)
            let again = gauge.issued
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                check(proxy, attempt: attempt + 1, pass: pass, issued: again)
            }
        } else {
            #if DEBUG
            print("[Rail] \(Self.describe(id)) missed at \(stood) after \(attempt) checks: "
                  + "viewport=\(Int(gauge.viewport.rounded())) anchor=\(plan.anchor)")
            #endif
        }
    }

    /// One scroll to a plan, noted as the rail's latest.
    private func scroll(_ proxy: ScrollViewProxy, to plan: WholeRowPlan, heights: [CGFloat]) {
        gauge.plannedViewport = gauge.viewport
        gauge.plannedHeights = heights
        gauge.issued += 1
        proxy.scrollTo(items[plan.top].id, anchor: UnitPoint(x: 0, y: plan.anchor))
    }

    /// A second after the rail appears, a planned scroll still waiting is
    /// issued, and a rail with a row never measured centres the focused row
    /// rather than leaving it anywhere. Neither is expected; the console
    /// says which ran.
    private func centreIfUnsettled(_ proxy: ScrollViewProxy, pass: Int) {
        guard pass == gauge.pass, !gauge.opened, !gauge.touched, let focus else { return }
        if gauge.waiting {
            issue(proxy)
            return
        }
        if let heights = measuredHeights(), currentPlan(heights) != nil {
            settle(proxy, from: "late")
            return
        }
        #if DEBUG
        let measured = items.filter { (gauge.heights[$0.id] ?? 0) > 0 }.count
        print("[Rail] focus=\(Self.describe(focus)) unsettled after 1 s: viewport=\(Int(gauge.viewport.rounded())) "
              + "measured=\(measured)/\(items.count); centring")
        #endif
        proxy.scrollTo(focus, anchor: .center)
    }

    /// Every row's height in order, or nil while one is unmeasured.
    private func measuredHeights() -> [CGFloat]? {
        let heights = items.map { gauge.heights[$0.id] ?? 0 }
        return heights.contains(where: { $0 <= 0 }) ? nil : heights
    }

    /// Where the rail opens at its height now; nil with no focus, or at a
    /// height the rail is only passing through — one that cannot hold the
    /// tallest row with a lead above and below it (87 points on run 221's
    /// Titans rail, whose rows run to 82).
    private func currentPlan(_ heights: [CGFloat]) -> WholeRowPlan? {
        guard let focus, let index = items.firstIndex(where: { $0.id == focus }) else { return nil }
        guard gauge.viewport >= (heights.max() ?? 0) + 2 * WholeRowPlan.lead else { return nil }
        return WholeRowPlan(heights: heights, focus: index, viewport: gauge.viewport)
    }

    private static func same(_ a: [CGFloat], _ b: [CGFloat]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.5 }
    }

    private static func describe(_ id: Item.ID?) -> String {
        id.map { "\($0)" } ?? "nil"
    }
}

/// One row as its background reads it, in ONE layout pass: its height, its
/// top in the scroll's own space, and the rail's height at that moment.
private struct RailRowPlace: Equatable {
    let height: CGFloat
    let top: CGFloat
    let viewport: CGFloat
}

/// What a `WholeRowRail` has measured and where its opening stands, kept out
/// of its view state.
private final class RailRowGauge<ID: Hashable> {
    var heights: [ID: CGFloat] = [:]
    /// Each row's top in the scroll's own space: `lead` for the top row once
    /// the rail has opened.
    var tops: [ID: CGFloat] = [:]
    /// The rail's height, from its reader.
    var viewport: CGFloat = 0
    /// What the latest scroll was planned from, and why it was planned.
    var plannedViewport: CGFloat = 0
    var plannedHeights: [CGFloat] = []
    var source = ""
    /// A planned scroll waits for its room at the foot.
    var waiting = false
    /// A scroll has been issued for what is measured now.
    var opened = false
    /// The row the last read found standing at `lead`, and the rail's height
    /// then.
    var landedID: ID?
    var landedViewport: CGFloat = 0
    /// The player has picked a row or scrolled the rail: nothing re-plans.
    var touched = false
    /// Bumped on every appearance and disappearance, and on every scroll, so
    /// a late read of an earlier one does nothing.
    var pass = 0
    var issued = 0
}

/// Where a `WholeRowRail` opens, from its rows' heights and its own height.
/// The layout numbers are `PlaceRail`'s: 8 over the first row, 5 between
/// rows, 5 and 24 after the last (and `footSpace` past that), the foot
/// fading from 88% of the height — change them here if `PlaceRail` changes.
private struct WholeRowPlan {
    /// Where the first row stands at rest, and where the top row stands once
    /// opened: `PlaceRail`'s top padding.
    static let lead: CGFloat = 8
    static let rowGap: CGFloat = 5
    static let trail: CGFloat = 5 + 24
    static let fadeFrom: CGFloat = 0.88
    /// How far into the foot's fade the focused row may reach: four points
    /// of a 36-point fade is 89% bright.
    static let fadeGrace: CGFloat = 4
    /// The travel over which a row scrolled up past `lead` fades out. The
    /// row above an opened top row is at least a row and a gap past it
    /// (51 points on the floor rail), so it is never drawn.
    static let fadeSpan: CGFloat = 28

    /// A row's opacity from its top edge in the scroll's own space: whole at
    /// `lead` and below, gone `fadeSpan` above it.
    static func rowOpacity(top: CGFloat) -> Double {
        let lift = WholeRowPlan.lead - top
        return Double(min(1, max(0, 1 - lift / WholeRowPlan.fadeSpan)))
    }

    /// The row that opens at the top.
    let top: Int
    /// The scroll anchor that puts that row `lead` below the rail's top:
    /// `scrollTo` lines up the same unit point of the row and of the rail,
    /// so the row's top lands at `lead` when y is lead / (rail − row).
    let anchor: CGFloat
    /// The room past the rail's own foot (`PlaceRail.footSpace`), zero while
    /// the rail reaches anyway: exactly what brings the rail's end to the
    /// top row's offset. It is part of the foot's clear, not a row of its
    /// own — as a row it added the 5-point gap on top (run 221).
    let tail: CGFloat

    init(heights: [CGFloat], focus: Int, viewport: CGFloat) {
        guard !heights.isEmpty, heights.indices.contains(focus) else {
            top = 0
            anchor = 0
            tail = 0
            return
        }
        var tops: [CGFloat] = []
        var y = Self.lead
        for height in heights {
            tops.append(y)
            y += height + Self.rowGap
        }
        let last = heights.count - 1
        // How far the rail scrolls with no room added.
        let reach = max(0, tops[last] + heights[last] + Self.trail - viewport)
        let clear = viewport * Self.fadeFrom + Self.fadeGrace
        let offsets = tops.map { $0 - Self.lead }
        // The focused row third from the top, but no further down the rail
        // than the first row-aligned stop at or past its natural end.
        var row = max(0, focus - 2)
        if let end = offsets.firstIndex(where: { $0 >= reach - 0.5 }) {
            row = min(row, end)
        }
        // And the focused row whole above the foot's fade.
        while row < focus, tops[focus] + heights[focus] - offsets[row] > clear {
            row += 1
        }
        top = row
        anchor = Self.lead / max(1, viewport - heights[row])
        tail = max(0, offsets[row] - reach)
    }
}

// MARK: - Beads and titles

/// A reading, or a quiet action, on glass: a capsule of glass with a painted
/// item (or a glyph) and a word or number beside it, at its own width so it
/// never truncates — the summon header's chip beads made shared. With an
/// `action` it is a button (the plate's press: the tick and the tap on
/// touch-down, `GamePressStyle`). Used by the
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
                action()
            } label: {
                face
            }
            .buttonStyle(GamePressStyle(.plate))
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
///
/// `centered: true` for a ceremony screen whose title stands centred on its
/// plate (the starter selector; run 216 had its eyebrow and title flush
/// left, 50 points off the plate's centre).
struct PlaceTitle: View {
    var eyebrow: String? = nil
    let title: String
    var size: CGFloat = 26
    var centered: Bool = false

    private var shrink: CGFloat {
        max(0.6, min(1, Theme.titleFloor / max(size, 1)))
    }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 0) {
            if let eyebrow {
                // Its figures in Manrope: "LV.14" read "LV.I4" in Cinzel.
                Text.inscribed(eyebrow.uppercased(), letters: Theme.title(13), digits: Theme.numeric(12.6))
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

extension Text {
    /// Words in a carved face with their figures in Manrope. Cinzel's figures
    /// are inscriptional — its 1 is a Roman I — so the Labyrinth's "B1" read
    /// "BI", "B10" "BIO" and "LV.14" "LV.I4" at phone size (runs 220–221).
    /// The letters take `letters`, every run of 0–9 takes `digits`, which
    /// the caller sets a shade under the letters' size: Manrope's lining
    /// figures stand 0.72 of the em against Cinzel's 0.70 capitals, so 0.97
    /// of the size stands them level. One `Text`, so a modifier after it
    /// (`carved`, `tracking`) dresses both faces alike.
    static func inscribed(_ string: String, letters: Font, digits: Font) -> Text {
        var text = Text(verbatim: "")
        var run = ""
        var runIsFigures = false
        for character in string {
            let isFigure = character.isASCII && character.isNumber
            if isFigure != runIsFigures, !run.isEmpty {
                text = text + Text(verbatim: run).font(runIsFigures ? digits : letters)
                run = ""
            }
            runIsFigures = isFigure
            run.append(character)
        }
        if !run.isEmpty {
            text = text + Text(verbatim: run).font(runIsFigures ? digits : letters)
        }
        return text
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
///
/// `seated` sits the ? in the strip's own dark well (`ScreenChrome.well`, 34
/// points with its gold rim, the mark in pale gold) inside a 44 × 40 target,
/// for a ? that stands alone on a painting: the Labyrinth's rooms had the
/// bare 14-point glyph floating over the torchlight at the top right, with
/// no plate and a thumb-sized miss round it (run 221). Forty tall, not 44:
/// the room's title row is 42, and a taller ? would have grown it and taken
/// the two points a B10's drops plate has to spare in the room's middle.
struct InfoDot<Detail: View>: View {
    let title: String
    var seated: Bool = false
    @ViewBuilder var detail: () -> Detail
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            if seated {
                Image(systemName: "questionmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Theme.onGlassGold)
                    .frame(width: ScreenChrome.control, height: ScreenChrome.control)
                    .background(ScreenChrome.well)
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            } else {
                InfoGlyph()
            }
        }
        .buttonStyle(GamePressStyle(.medallion))
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
                    // The gain as LIGHT: a bright gold that pulses, with a
                    // glow. Pale cream at half over the black track read as a
                    // greyed, disabled bar (run 216, the Hall of Ka's feed).
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        let pulse = 0.85 + 0.10 * sin(timeline.date.timeIntervalSinceReferenceDate * 3)
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: "#FFE29A"), Color(hex: "#E0B64A")],
                                                 startPoint: .top, endPoint: .bottom))
                            .opacity(pulse)
                            .frame(width: max(height, width * ghostFraction))
                            .shadow(color: Theme.gold.opacity(0.6), radius: 4)
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
/// `tag` is a ribbon across the FOOT (BOSS, WAVE 3), `isLeader` a crown on
/// the top edge. The name is in the accessibility label.
///
/// Two layouts, by size (run 216). From 48 points: the element badge top
/// left, the level in a dark capsule top right, the stars along the foot.
/// Under 48 — the Arena's 40-point team rows, where the badge and the
/// capsule met as one pill across the top and the stars filled the foot, so
/// the face was a dark band between them — the genre's small icon: the
/// stars small along the top, the element a 12-point disc at the bottom
/// left, the level as bare outlined digits at the bottom right, and the
/// face clear in the middle. Stars are packed (`StarRow.packed`) and sized
/// to the room INSIDE the rim at every size (six never run into it), every
/// mark stands inside the rim (`inset`), and the stars are drawn bright:
/// the dim natural-star bronze on the ink foot could not be counted (the
/// Hall of Ka's judge).
///
/// The tag hangs INSIDE the tile at its foot, with the stars lifted over
/// it: on the top edge it hid the element and the level, and outside the
/// tile it met the row above (the popup's "Wave 1 of 3") or below.
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
    /// False on a face that is offered rather than owned — the selector's
    /// and the mileage board's, all level 1 — where the level is noise.
    var showsLevel: Bool = true

    private var corner: CGFloat { max(6, min(Theme.tightCorner, size * 0.14)) }
    private var wear: CGFloat { max(0.6, min(1, size / 80)) }
    private var isSmall: Bool { size < 48 }

    /// How far in from the tile's edge a mark may start: the grade's metal
    /// (`Rarity.frameWidth`, 2.5 points on a 4★ and up) and a point clear of
    /// it. Run 217's 40-point tiles had their level 2 points in, under the
    /// 2.5-point gold rim, and the "40" lost its last stroke.
    private var inset: CGFloat { Rarity(stars: unit.stars).frameWidth + 1 }

    /// The stars' point size: what the width INSIDE the rim allows at a
    /// packed star's real advance (`StarRow.packedAdvance`), capped at 15%
    /// of the tile, and a little smaller on a small tile, where they ride
    /// over the face. It divided the whole tile by 1.2 a star, while the
    /// symbol's own advance at 6 points is about 1.55: every 5★ row on the
    /// arena's 40-point tiles was 4 points wider than the tile, with half a
    /// star under each rim (run 217). Six stars on a 40-point tile come to
    /// about 4.3 points, the floor.
    private var starSize: CGFloat {
        let count = CGFloat(max(1, unit.stars))
        let room = (size - 2 * (inset + 0.5)) / (count * StarRow.packedAdvance)
        return max(4, min(isSmall ? 6 : 9, size * 0.15, room))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return ZStack(alignment: .topLeading) {
            portrait
                .frame(width: size, height: size)
            LinearGradient(colors: [.clear, .clear, Theme.ink.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
            if isSmall {
                smallMarks
            } else {
                largeMarks
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .rarityFrame(Rarity(stars: unit.stars), radius: corner, painted: false)
        .overlay(alignment: .top) {
            if isLeader {
                // Above the tile, standing on its rim. At −8 a 40-point
                // tile's crown came 3 points down into it and sat on the
                // middle star of the row along the top (run 217); −11 puts
                // its foot on the rim, clear of the stars. A large tile's
                // stars are at its foot, so its crown keeps the old seat.
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.goldText)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                    .offset(y: isSmall ? -11 : -8)
            }
        }
        .overlay(alignment: .bottom) {
            if let tag {
                Text(tag.uppercased())
                    .font(Theme.body(11).weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(tagTint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Capsule().fill(Color(hex: "#17120E").opacity(0.92)))
                    .overlay(Capsule().strokeBorder(tagTint.opacity(0.8), lineWidth: 0.8))
                    .offset(y: 4)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unit.name), level \(unit.level), \(unit.stars) stars")
    }

    /// From 48 points: the badge and the level across the top, the stars at
    /// the foot — lifted over the tag when there is one.
    @ViewBuilder
    private var largeMarks: some View {
        ElementBadge(element: unit.element, compact: true, scale: wear)
            .padding(max(inset, 4 * wear))
        if showsLevel {
            Text("\(unit.level)")
                .font(Theme.numeric(11.5))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .frame(height: 15)
                .background(Capsule().fill(Color.black.opacity(0.62)))
                .overlay(Capsule().strokeBorder(Theme.goldDim.opacity(0.8), lineWidth: 0.6))
                .padding(max(inset, 3 * wear))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        StarRow(stars: unit.stars, size: starSize, packed: true)
            .padding(.bottom, tag == nil ? max(inset, 3 * wear) : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Under 48 points: the stars small along the top on a breath of ink,
    /// the element disc and the bare level at the foot, the face between —
    /// every mark inside the rim (`inset`).
    @ViewBuilder
    private var smallMarks: some View {
        LinearGradient(colors: [Theme.ink.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: size * 0.32)
        StarRow(stars: unit.stars, size: starSize, packed: true)
            .padding(.top, inset)
            .frame(maxWidth: .infinity, alignment: .top)
        HStack(alignment: .bottom, spacing: 0) {
            Image(systemName: unit.element.glyph)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 12, height: 12)
                .background(Circle().fill(unit.element.color))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.6), radius: 1, y: 0.5)
            Spacer(minLength: 0)
            if showsLevel {
                OutlinedText(text: "\(unit.level)", font: Theme.numeric(11.5).weight(.black), width: 0.8)
                    .fixedSize()
            }
        }
        // Inside the rim with room for the digits' outline, which draws 0.8
        // past the text's frame: at 2 the gold rim took the "0" of "40".
        .padding(.horizontal, inset + 0.5)
        .padding(.bottom, inset - 0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// The card to draw: the unit's own, else the card of the mesh it
    /// fights in (`ModelSpec.standInAsset`) — the Colossus of the Sun and
    /// the Dragon of Longmen stand in as the Vault's Colossus and Apep and
    /// have no card of their own, so the popup and the briefing drew their
    /// initial. The same fallback as the chapter map's boss medallion
    /// (`ChapterMapArt.bossPortrait`).
    private var portraitName: String? {
        let model = unit.blueprint.model
        var names = [model.portraitName(awakened: unit.unit.isAwakened)]
        if let standIn = model.standInAsset {
            names.append("portrait_\(standIn)")
            names.append("portrait_\(standIn)_\(unit.element.rawValue)")
        }
        return names.first(where: { BundleImage.exists($0) })
    }

    /// The card's painting at the tile's own size, or the element-tinted
    /// initial `UnitCard` draws before a family has art.
    @ViewBuilder
    private var portrait: some View {
        if let name = portraitName {
            PortraitPainting(name: name, size: size)
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
                // The press is the tap and the firm tick; the claim's
                // confirm is the "done".
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
            .buttonStyle(GamePressStyle(.primary))
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
