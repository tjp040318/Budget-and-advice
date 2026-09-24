import SwiftUI

// MARK: - The carved name card (2026-09-24, Docs/FEEL.md W2.13)
//
// Summoners War's, Genshin's and Raid's reveals end on a designed object,
// not on loose lines of text over the sky; ours was a name, a star row and
// an epithet floating over the dusk (`5-reveal-b`). This is the object: a
// plaque of dark glass rimmed in the grade's own metal (`Rarity.frame`, the
// frame every card of the grade wears) slides in from the right as the
// figure lands, the element's crest pinned to its left edge; painted gold
// stars stamp in one by one, each throwing motes and ringing the next note
// of the glockenspiel's climb; the name slams down in carved gold on the
// figure's high point and a light runs across it once; the second line
// (epithet · pantheon · role) and the chips — NEW, what a duplicate did,
// FEATURED — follow. It stands in the right 45% of the frame, clear of the
// figure on the left.
//
// Two keyframe timelines replace the three `@State` timers the words ran on
// (`shownStars`, `nameSlam`, `detailsShown`), whose asyncAfters landed all
// five star ticks inside 70 ms behind a stalled main thread (run 221): the
// ARRIVAL (the plaque, the crest, the stars), set off by the figure's first
// drawn frame, and the NAMING (the slam, the sweep, the rim's flash, the
// details), set off by the victory clip's high point on the scene's own
// clock (`SummonStageView`'s `onApex`). Two, so the name can land on the
// pose whenever the pose peaks — during the stars (412's raise, 0.56 s) or
// after them (88's chest pound, 1.26 s) — without cutting a star short.
// Each publishes its value into the environment, and the card reads both.

/// Where the card stands: out of sight, arrived with the figure, named on
/// the clip's high point, or finished at once by a tap. The number is the
/// reveal's sequence, so every pull sets the timelines off afresh.
enum RevealCardBeat: Equatable {
    case hidden
    case arrived(Int)
    case named(Int)
    case complete(Int)

    /// The arrival timeline's trigger: it runs once the card has arrived and
    /// is not restarted when the name lands.
    var arrival: RevealCardBeat {
        switch self {
        case .hidden: return .hidden
        case .arrived(let run), .named(let run): return .arrived(run)
        case .complete(let run): return .complete(run)
        }
    }

    /// The naming timeline's trigger.
    var naming: RevealCardBeat {
        switch self {
        case .hidden, .arrived: return .hidden
        case .named(let run): return .named(run)
        case .complete(let run): return .complete(run)
        }
    }
}

/// How the card's stars are paced: when the first begins to stamp after the
/// card arrives, how far apart they fall, and how long one stamp takes.
/// The first begins as the flash clears (it began at 0.3 s before); a 5★'s
/// five land at 0.37–0.89 s.
struct RevealCardTiming: Equatable {
    var stars: Int
    var starStart: Double
    var spacing: Double
    var stamp: Double

    static func standard(stars: Int) -> RevealCardTiming {
        RevealCardTiming(stars: max(1, stars), starStart: 0.26, spacing: 0.13, stamp: 0.16)
    }

    /// A Quick 3★ (`RevealSkip.quickSummons`): the stars in a blink.
    static func quick(stars: Int) -> RevealCardTiming {
        RevealCardTiming(stars: max(1, stars), starStart: 0.06, spacing: 0.06, stamp: 0.1)
    }

    /// Seconds the stars take, from the first stamp beginning to the last
    /// one landing.
    var run: Double {
        Double(max(0, stars - 1)) * spacing + stamp
    }

    /// Seconds from the card's arrival to star `index` landing: its tick.
    func landing(_ index: Int) -> Double {
        starStart + Double(index) * spacing + stamp * 0.7
    }

    /// How far star `index` has stamped, 0…1, `clock` seconds into the run.
    func progress(of index: Int, at clock: Double) -> Double {
        let since: Double = clock - Double(index) * spacing
        return min(1, max(0, since / max(0.01, stamp)))
    }

    /// How far star `index`'s motes have flown, 0…1: from the moment it
    /// lands, over half a second.
    func motes(of index: Int, at clock: Double) -> Double {
        let since: Double = clock - Double(index) * spacing - stamp * 0.7
        return min(1, max(0, since / 0.5))
    }

    /// A star's size through its stamp: in from 2.2 times, falling fast to
    /// 0.92 by 70% of the way and settling at 1 — a stamp, not a pop. Under
    /// Reduce Motion, from 1.25 straight to 1.
    static func stampScale(_ progress: Double, calm: Bool) -> Double {
        let p: Double = min(1, max(0, progress))
        if calm {
            return 1.25 - 0.25 * p
        }
        if p < 0.7 {
            let fall: Double = p / 0.7
            return 2.2 - (2.2 - 0.92) * fall * fall
        }
        let settle: Double = (p - 0.7) / 0.3
        return 0.92 + 0.08 * settle
    }
}

/// The arrival timeline's value: the plaque sliding in (0 off to the right,
/// 1 in place), the crest's pop and the stars' clock, in seconds of the
/// stars' run.
struct RevealArrivalFrame: Equatable {
    var plaque: Double = 0
    var crest: Double = 0
    var starClock: Double = 0

    /// Where a timeline stands at rest after `beat`: a card rebuilt in the
    /// middle of a reveal shows the end of what it has passed, never the
    /// empty start.
    static func resting(_ beat: RevealCardBeat, timing: RevealCardTiming) -> RevealArrivalFrame {
        switch beat {
        case .hidden:
            return RevealArrivalFrame()
        case .arrived, .named, .complete:
            return RevealArrivalFrame(plaque: 1, crest: 1, starClock: timing.run)
        }
    }
}

/// The naming timeline's value: the name's presence and scale (it slams
/// from 1.8 times), the light running across it (0…1), the rim's flash on
/// the slam, and the details following.
struct RevealNamingFrame: Equatable {
    var name: Double = 0
    var nameScale: Double = 1.8
    var sweep: Double = 0
    var flash: Double = 0
    var details: Double = 0

    static func resting(_ beat: RevealCardBeat) -> RevealNamingFrame {
        switch beat {
        case .hidden, .arrived:
            return RevealNamingFrame()
        case .named, .complete:
            return RevealNamingFrame(name: 1, nameScale: 1, sweep: 1, flash: 0, details: 1)
        }
    }
}

extension RevealArrivalFrame {
    /// This frame, raised to at least `floor` on every track: the card once
    /// its arrival has had the time to run is never below its resting
    /// state, whatever the timeline reports (`RevealNameCard.settled`).
    func atLeast(_ floor: RevealArrivalFrame) -> RevealArrivalFrame {
        RevealArrivalFrame(
            plaque: max(plaque, floor.plaque),
            crest: max(crest, floor.crest),
            starClock: max(starClock, floor.starClock)
        )
    }
}

extension RevealNamingFrame {
    /// This frame, or its resting state once the naming has had the time to
    /// run: the name and the details in, the slam's scale and the flash
    /// spent, the sweep past.
    func settled(on beat: RevealCardBeat) -> RevealNamingFrame {
        switch beat {
        case .hidden, .arrived:
            return self
        case .named, .complete:
            let rest: RevealNamingFrame = RevealNamingFrame.resting(beat)
            return RevealNamingFrame(
                name: max(name, rest.name),
                nameScale: rest.nameScale,
                sweep: max(sweep, rest.sweep),
                flash: rest.flash,
                details: max(details, rest.details)
            )
        }
    }
}

/// One keyframe track's plan for a beat, fixed in shape so the builder is
/// the same on every beat (the press's rule, `GamePressBody`): jump to
/// `from`, hold there for `hold` seconds, then go to `to` over `run`.
private struct RevealCardStep {
    let from: Double
    let hold: Double
    let to: Double
    let run: Double

    /// A track standing still at `value`.
    static func still(_ value: Double) -> RevealCardStep {
        RevealCardStep(from: value, hold: 0.001, to: value, run: 0.001)
    }
}

/// The card. `beat` sets its two timelines off; `timing` paces its stars.
struct RevealNameCard: View {
    let result: SummonResult
    let beat: RevealCardBeat
    let timing: RevealCardTiming

    /// The beat the card has had the time to finish, `settleDelay` behind
    /// `beat`: below it the card is never drawn short of that beat's resting
    /// state (`RevealArrivalFrame.atLeast`, `RevealNamingFrame.settled(on:)`),
    /// so a timeline that stalls or restarts can cost the motion but never
    /// the words.
    @State private var settled: RevealCardBeat = .hidden
    /// The latest `settleLater` call's number: a pending catch-up that a
    /// newer beat overtook (or a return to hidden cancelled) does nothing.
    @State private var settleToken: Int = 0
    /// Longer than the longest timeline on the card: the arrival's plaque
    /// (0.6 s) and stars (0.26 s + a 5★'s 0.68 s), the naming's details
    /// (0.58 s).
    static let settleDelay: TimeInterval = 1.2

    /// The crest's side, and the column's place: its left edge at 55% of
    /// the screen's width, clear of the figure standing on the 26% line.
    static let crestSize: CGFloat = 56
    static let clearOfFigure: CGFloat = 0.55
    static let trailingMargin: CGFloat = 18
    static let widest: CGFloat = 410
    static let narrowest: CGFloat = 220

    var body: some View {
        let arrival: RevealCardBeat = beat.arrival
        let naming: RevealCardBeat = beat.naming
        let calm: Bool = Motion.isCalm

        // The arrival's three tracks for this beat.
        let plaque: RevealCardStep
        let crest: RevealCardStep
        let stars: RevealCardStep
        switch arrival {
        case .arrived:
            plaque = RevealCardStep(from: 0, hold: 0.001, to: 1, run: 0.6)
            crest = RevealCardStep(from: 0, hold: 0.08, to: 1, run: 0.55)
            stars = RevealCardStep(from: 0, hold: timing.starStart, to: timing.run, run: timing.run)
        case .complete:
            plaque = .still(1)
            crest = .still(1)
            stars = .still(timing.run)
        case .hidden, .named:
            plaque = .still(0)
            crest = .still(0)
            stars = .still(0)
        }

        // The naming's five: the name in over 70 ms, its scale falling from
        // 1.8 through 0.955 (the dip, the weight landing) and springing to
        // 1; the sweep 0.14 s after, the rim's flash on the impact, the
        // details a quarter of a second behind. Under Reduce Motion the
        // name comes in from 1.12 with no dip, no sweep and no ring.
        let name: RevealCardStep
        let scale: RevealCardStep
        let dip: Double
        let sweep: RevealCardStep
        let flash: RevealCardStep
        let flashPeak: Double
        let details: RevealCardStep
        switch naming {
        case .named:
            let from: Double = calm ? 1.12 : 1.8
            name = RevealCardStep(from: 0, hold: 0.001, to: 1, run: 0.07)
            scale = RevealCardStep(from: from, hold: 0.13, to: 1, run: 0.36)
            dip = calm ? 1 : 0.955
            sweep = calm ? .still(0) : RevealCardStep(from: 0, hold: 0.14, to: 1, run: 0.65)
            flash = RevealCardStep(from: 0, hold: 0.05, to: 0, run: 0.5)
            flashPeak = 1
            details = RevealCardStep(from: 0, hold: 0.24, to: 1, run: 0.34)
        case .complete:
            name = .still(1)
            scale = .still(1)
            dip = 1
            sweep = .still(1)
            flash = .still(0)
            flashPeak = 0
            details = .still(1)
        case .hidden, .arrived:
            name = .still(0)
            scale = .still(1.8)
            dip = 1.8
            sweep = .still(0)
            flash = .still(0)
            flashPeak = 0
            details = .still(0)
        }

        let settle: Spring = Motion.settleSpring.spring
        let panel: Spring = Motion.panelSpring.spring
        let pop: Spring = Motion.popSpring.spring
        // Under Reduce Motion no spring on the card rings (`Motion`'s
        // contract: a spring's travel and overshoot become a short ease).
        // The crest and the name settle on the plaque's own curve, the
        // panel's, damped to within half a per cent of its mark; the crest
        // dissolves in at its size (`RevealCardBody.crest`) rather than
        // popping from a third of it (review, 2026-09-24).
        let crestSpring: Spring = calm ? panel : pop
        let nameSpring: Spring = calm ? panel : settle

        let settledBeat: RevealCardBeat = settled
        let arrivalFloor: RevealArrivalFrame = RevealArrivalFrame.resting(settledBeat.arrival, timing: timing)
        return KeyframeAnimator(initialValue: RevealArrivalFrame.resting(arrival, timing: timing), trigger: arrival) { arrivalFrame in
            KeyframeAnimator(initialValue: RevealNamingFrame.resting(naming), trigger: naming) { namingFrame in
                RevealCardBody(
                    result: result,
                    timing: timing,
                    arrival: arrivalFrame.atLeast(arrivalFloor),
                    naming: namingFrame.settled(on: settledBeat.naming)
                )
            } keyframes: { _ in
                KeyframeTrack(\.name) {
                    MoveKeyframe(name.from)
                    LinearKeyframe(name.from, duration: name.hold)
                    LinearKeyframe(name.to, duration: name.run)
                }
                KeyframeTrack(\.nameScale) {
                    MoveKeyframe(scale.from)
                    CubicKeyframe(dip, duration: scale.hold)
                    SpringKeyframe(scale.to, duration: scale.run, spring: nameSpring)
                }
                KeyframeTrack(\.sweep) {
                    MoveKeyframe(sweep.from)
                    LinearKeyframe(sweep.from, duration: sweep.hold)
                    CubicKeyframe(sweep.to, duration: sweep.run)
                }
                KeyframeTrack(\.flash) {
                    MoveKeyframe(flash.from)
                    LinearKeyframe(flashPeak, duration: flash.hold)
                    CubicKeyframe(flash.to, duration: flash.run)
                }
                KeyframeTrack(\.details) {
                    MoveKeyframe(details.from)
                    LinearKeyframe(details.from, duration: details.hold)
                    CubicKeyframe(details.to, duration: details.run)
                }
            }
        } keyframes: { _ in
            KeyframeTrack(\.plaque) {
                MoveKeyframe(plaque.from)
                LinearKeyframe(plaque.from, duration: plaque.hold)
                SpringKeyframe(plaque.to, duration: plaque.run, spring: panel)
            }
            KeyframeTrack(\.crest) {
                MoveKeyframe(crest.from)
                LinearKeyframe(crest.from, duration: crest.hold)
                SpringKeyframe(crest.to, duration: crest.run, spring: crestSpring)
            }
            KeyframeTrack(\.starClock) {
                MoveKeyframe(stars.from)
                LinearKeyframe(stars.from, duration: stars.hold)
                LinearKeyframe(stars.to, duration: stars.run)
            }
        }
        .onAppear {
            // A card built in the middle of a reveal (a new pull's card, or
            // one rebuilt) starts from where the reveal stands.
            if settled == .hidden, beat != .hidden { settleLater(beat) }
        }
        .onChange(of: beat) { _, newBeat in
            settleLater(newBeat)
        }
    }

    /// `settled` catches up with `beat` once its timelines have had the
    /// time to run. A newer beat cancels the catch-up still pending, and a
    /// return to hidden takes effect at once.
    private func settleLater(_ target: RevealCardBeat) {
        let mine: Int = settleToken + 1
        settleToken = mine
        if target == .hidden {
            settled = .hidden
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) {
            guard settleToken == mine else { return }
            settled = target
        }
    }

    // The three helpers below are pure and `nonisolated`: a `View` is
    // main-actor isolated in the iOS 18 SDK, so a static on one is too, and
    // the tests call them from plain code (run 200's nine errors were the
    // same call on a `@MainActor` class; CLAUDE.md).

    /// The name's two lines: an awakened form's title is "Name, Epithet"
    /// ("Sekhmet, Bringer of the Seven Arrows", 36 letters): the name is
    /// carved and the rest stands over it as an eyebrow.
    nonisolated static func names(for result: SummonResult) -> (main: String, eyebrow: String?) {
        let full: String = result.isAwakening
            ? (result.blueprint.awakening?.awakenedName ?? result.blueprint.name)
            : result.blueprint.name
        guard let comma = full.range(of: ", ") else { return (full, nil) }
        let main = String(full[full.startIndex..<comma.lowerBound])
        let rest = String(full[comma.upperBound...])
        return (main, rest.isEmpty ? nil : rest)
    }

    /// The line under the name: the epithet, the pantheon, the role.
    nonisolated static func secondLine(for result: SummonResult) -> String {
        let blueprint: UnitBlueprint = result.blueprint
        return "\(blueprint.epithet) · \(blueprint.pantheon.displayName) · \(blueprint.role.displayName)"
    }

    /// A light band across the name at `sweep` (0 before the name, 1 past
    /// it): clear, a white band 0.28 of the width across, clear.
    nonisolated static func sweepStops(_ sweep: Double) -> [Gradient.Stop] {
        let centre: Double = -0.25 + 1.5 * sweep
        let lead: CGFloat = CGFloat(min(1, max(0, centre - 0.14)))
        let middle: CGFloat = CGFloat(min(1, max(0, centre)))
        let tail: CGFloat = CGFloat(min(1, max(0, centre + 0.14)))
        let lit: Double = centre > -0.14 && centre < 1.14 ? 0.85 : 0
        return [
            Gradient.Stop(color: Color.white.opacity(0), location: 0),
            Gradient.Stop(color: Color.white.opacity(0), location: lead),
            Gradient.Stop(color: Color.white.opacity(lit), location: middle),
            Gradient.Stop(color: Color.white.opacity(0), location: tail),
            Gradient.Stop(color: Color.white.opacity(0), location: 1),
        ]
    }

    /// The painted gold of a star: a bright crown, the metal, a deep foot.
    static let starGold = LinearGradient(
        colors: [Color(hex: "#FFF6D2"), Color(hex: "#F4CE63"), Color(hex: "#C08A26")],
        startPoint: .top, endPoint: .bottom
    )
}

/// The card itself, drawn from the two timelines' values, handed in as
/// values. Until run 250 the animators wrote them into the environment and
/// this view read them from there, and the card never showed: every reveal
/// frame of that run had the figure and no words, while the tour's console
/// printed the name landing. The values are parameters now, and the card
/// rests at the end of each beat whatever a timeline reports
/// (`RevealNameCard.settled`).
private struct RevealCardBody: View {
    let result: SummonResult
    let timing: RevealCardTiming
    let arrival: RevealArrivalFrame
    let naming: RevealNamingFrame

    var body: some View {
        let calm: Bool = Motion.isCalm
        let travel: Double = calm ? 0 : (1 - arrival.plaque) * 90
        let shown: Double = min(1, max(0, arrival.plaque * 1.8))
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .leading) {
                plaque(calm: calm)
                    .padding(.leading, RevealNameCard.crestSize / 2)
                crest(calm: calm)
            }
            details
        }
        .offset(x: CGFloat(travel))
        .opacity(shown)
    }

    // MARK: The plaque

    private func plaque(calm: Bool) -> some View {
        let names = RevealNameCard.names(for: result)
        return VStack(alignment: .leading, spacing: 4) {
            starRow(calm: calm)
            if let eyebrow = names.eyebrow {
                Text(eyebrow.uppercased())
                    .font(Theme.title(12))
                    .tracking(1.4)
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                    .opacity(naming.name)
            }
            nameView(names.main, calm: calm)
            Text(RevealNameCard.secondLine(for: result))
                .font(Theme.body(13).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                .opacity(naming.details)
        }
        .padding(.leading, RevealNameCard.crestSize / 2 + 14)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plaqueGround)
        .overlay(alignment: .topTrailing) {
            chips
                .offset(y: -11)
                .padding(.trailing, 14)
        }
    }

    /// Dark glass rimmed in the grade's metal, lit on the name's slam. One
    /// compositing group before its shadows, or every layer casts its own
    /// (the tab socket's khaki halo, run 222).
    private var plaqueGround: some View {
        let rarity = Rarity(stars: result.stars)
        let flash: Double = naming.flash
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#120D0A").opacity(0.8))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0)],
                                     startPoint: .top, endPoint: .center))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rarity.glow.opacity(0.16 * flash))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(rarity.frame, lineWidth: 2)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                .padding(2)
        }
        .compositingGroup()
        .shadow(color: rarity.glow.opacity(0.3 + 0.5 * flash), radius: CGFloat(8 + 10 * flash))
        .shadow(color: Color.black.opacity(0.45), radius: 10, y: 4)
    }

    // MARK: The crest

    /// The element's crest, 56 points: a medallion in the element's colour
    /// rimmed in the grade's metal, its glyph carved in it — `ElementBadge`'s
    /// language at the size of a seal, pinned half over the plaque's edge.
    /// It pops in from a third of its size; under Reduce Motion it dissolves
    /// in at its own size with the plaque, on the plaque's settled curve.
    private func crest(calm: Bool) -> some View {
        let element: Element = result.blueprint.element
        let rarity = Rarity(stars: result.stars)
        let pale: Bool = element == .radiance
        let pop: Double = arrival.crest
        let size: CGFloat = RevealNameCard.crestSize
        let grow: Double = calm ? 1 : 0.35 + 0.65 * pop
        let shown: Double = calm ? min(1, max(0, pop)) : min(1, max(0, pop * 2))
        let face = RadialGradient(
            colors: [element.color.opacity(0.95), element.color, Color.black.opacity(0.55)],
            center: UnitPoint(x: 0.38, y: 0.32), startRadius: 1, endRadius: size * 0.62
        )
        return ZStack {
            Circle()
                .fill(Color(hex: "#120D0A"))
            Circle()
                .fill(face)
                .padding(3)
            Circle()
                .strokeBorder(rarity.frame, lineWidth: 3)
            Circle()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                .padding(5)
            Image(systemName: element.glyph)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(pale ? Theme.ink : Color.white)
                .shadow(color: pale ? Color.white.opacity(0.4) : Color.black.opacity(0.7), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: element.color.opacity(0.6), radius: 8)
        .shadow(color: Color.black.opacity(0.5), radius: 3, y: 2)
        .scaleEffect(CGFloat(grow))
        .opacity(shown)
    }

    // MARK: The stars

    private func starRow(calm: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<max(1, result.stars), id: \.self) { index in
                RevealStar(
                    progress: timing.progress(of: index, at: arrival.starClock),
                    motes: timing.motes(of: index, at: arrival.starClock),
                    calm: calm,
                    seed: index
                )
            }
        }
        .frame(height: 26, alignment: .leading)
    }

    // MARK: The name

    /// Carved gold, slammed down onto the plaque from its leading edge, and
    /// a light run across it once: the same text laid over itself in a
    /// moving white band, ADDED, so the sweep follows every letter.
    private func nameView(_ title: String, calm: Bool) -> some View {
        let long: Bool = title.count > 11
        let font: Font = Theme.display(long ? 28 : 36)
        let lines: Int = long ? 2 : 1
        let scale: CGFloat = CGFloat(naming.nameScale)
        let stops: [Gradient.Stop] = RevealNameCard.sweepStops(naming.sweep)
        return Text(title)
            .font(font)
            .lineLimit(lines)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.leading)
            .carved(multiline: long)
            .overlay {
                if !calm {
                    Text(title)
                        .font(font)
                        .lineLimit(lines)
                        .minimumScaleFactor(0.55)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(scale, anchor: .leading)
            .opacity(naming.name)
    }

    // MARK: The chips

    /// Pinned over the plaque's top edge at the right: AWAKENED, or NEW, or
    /// what a duplicate did (`SummonDuplicateChip`, W1.5), and FEATURED.
    private var chips: some View {
        HStack(spacing: 5) {
            if result.isAwakening {
                goldChip("AWAKENED")
            } else if result.isNew {
                goldChip("NEW")
            } else if let skillUp = result.skillUp {
                SummonDuplicateChip(skillUp: skillUp)
            }
            if result.isFeatured && !result.isAwakening {
                Text("FEATURED")
                    .font(Theme.title(11))
                    .tracking(1.2)
                    .foregroundStyle(Theme.onGlassGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.glass))
                    .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 1))
                    .fixedSize()
            }
        }
        .scaleEffect(CGFloat(0.8 + 0.2 * naming.details))
        .opacity(naming.details)
    }

    private func goldChip(_ word: String) -> some View {
        Text(word)
            .font(Theme.title(12))
            .tracking(1.6)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.goldText))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
            .shadow(color: Theme.gold.opacity(0.55), radius: 5)
            .fixedSize()
    }

    // MARK: What the pull did

    /// Under the plaque: a new form's Codex page, what a duplicate did, and
    /// pity's hand. Nothing for an awakening, whose card is the whole story.
    private var details: some View {
        let fade: Double = naming.details
        return VStack(alignment: .leading, spacing: 6) {
            if !result.isAwakening {
                if result.isNew {
                    if let pay = result.codexDivinity, pay > 0 {
                        codexLine(pay)
                    }
                } else {
                    duplicateLine
                }
            }
            if result.fromPity {
                Text("Guaranteed by pity")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
            }
        }
        .padding(.leading, RevealNameCard.crestSize / 2 + 6)
        .opacity(fade)
        .offset(y: CGFloat(1 - fade) * 8)
    }

    /// What a duplicate did, as the summon did it (`SummonSkillUp`, W1.5):
    /// the skill that rose, as its own icon, and its levels; or that the kit
    /// is capped and the copy is the Regalia's; or, for a result that did
    /// not record it, only that the form is already in the book.
    @ViewBuilder
    private var duplicateLine: some View {
        if let skillUp = result.skillUp {
            switch skillUp {
            case .levelled(let skill, let from, let to):
                skillUpLine(skill: skill, from: from, to: to)
            case .maxed:
                maxedLine
            }
        } else {
            Text("Already in the Codex")
                .font(Theme.body(12))
                .foregroundStyle(Theme.onGlassDim)
                .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
        }
    }

    /// The skill that rose: its icon as the unit sheet draws it (the kit's
    /// own resolution, `SkillArt.keys`), its name and "Lv 3 → 4", on glass.
    private func skillUpLine(skill index: Int, from: Int, to: Int) -> some View {
        let blueprint: UnitBlueprint = result.blueprint
        let ranged: Bool = !blueprint.model.melee
        let keys: [String] = SkillArt.keys(for: blueprint.skills, element: blueprint.element, ranged: ranged)
        let key: String? = keys.indices.contains(index) ? keys[index] : nil
        let skill: Skill? = blueprint.skills.indices.contains(index) ? blueprint.skills[index] : nil
        let name: String = skill?.name ?? "A skill"
        return HStack(spacing: 10) {
            if let skill {
                SkillIcon(skill: skill, element: blueprint.element, ranged: ranged, resolvedKey: key,
                          size: 38, socket: true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("SKILL UP")
                    .font(Theme.title(11))
                    .tracking(1.6)
                    .foregroundStyle(Theme.onGlassEyebrow)
                Text(name)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.onGlass)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Lv \(from) → \(to)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.onGlassGold)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(GlassPlate(radius: 14))
    }

    /// Every skill at its cap: nothing rose, and the copy is food for the
    /// family's Regalia in the Hall of Ka, named when the family has one.
    private var maxedLine: some View {
        let regalia: String? = RegaliaService.regalia(forBlueprint: result.blueprint.id)?.name
        return HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.onGlassGold)
            VStack(alignment: .leading, spacing: 1) {
                Text("Skills maxed — feed to the Regalia")
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.onGlass)
                    .fixedSize(horizontal: false, vertical: true)
                if let regalia {
                    Text(regalia)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlassDim)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(GlassPlate(radius: 14))
    }

    /// A new form's Codex page and what claiming it pays
    /// (`SummonService.codexPay`): paid on the claim in the Codex, never
    /// here.
    private func codexLine(_ pay: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.onGlassGold)
            Text("Codex page")
                .font(Theme.body(12).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
            ItemIcon(key: "divinity", size: 20, glow: false)
            Text("+\(pay) to claim")
                .font(Theme.numeric(12))
                .foregroundStyle(Theme.onGlassGold)
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(GlassPlate(radius: 14))
    }
}

/// One painted star: stamped in from over twice its size, throwing six
/// motes of gold as it lands.
private struct RevealStar: View {
    let progress: Double
    let motes: Double
    let calm: Bool
    let seed: Int

    var body: some View {
        let scale: CGFloat = CGFloat(RevealCardTiming.stampScale(progress, calm: calm))
        let opacity: Double = min(1, progress * 3)
        return ZStack {
            ForEach(0..<6, id: \.self) { index in
                mote(index)
            }
            Image(systemName: "star.fill")
                .font(.system(size: 21, weight: .black))
                .foregroundStyle(Color.black.opacity(0.75))
                .offset(y: 1)
                .blur(radius: 0.6)
            Image(systemName: "star.fill")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(RevealNameCard.starGold)
                .shadow(color: Theme.gold.opacity(0.75), radius: 5)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .frame(width: 24, height: 24)
    }

    private func mote(_ index: Int) -> some View {
        let degrees: Double = Double(index) * 60 + Double(seed) * 23 + 15
        let angle: Double = degrees * Double.pi / 180
        let eased: Double = 1 - (1 - motes) * (1 - motes)
        let reach: Double = 5 + 17 * eased
        let fade: Double = motes > 0 && motes < 1 && !calm ? (1 - motes) * 0.95 : 0
        let x: CGFloat = CGFloat(cos(angle) * reach)
        let y: CGFloat = CGFloat(sin(angle) * reach)
        return Circle()
            .fill(RadialGradient(colors: [Color.white, Theme.gold, Theme.gold.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: 3))
            .frame(width: 6, height: 6)
            .offset(x: x, y: y)
            .opacity(fade)
    }
}
