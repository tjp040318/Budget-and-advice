import SwiftUI
import SceneKit
import UIKit

/// The reveal after a summon.
///
/// This is the moment the whole genre is built around, so it is staged rather
/// than shown: a charge, a flash, the figure, the stars ticking in one by one,
/// the name slamming down, then the details. A ten-pull reveals one at a time
/// with the option to skip to the grid; a tap during the sequence completes it
/// instantly, a tap after it advances.
struct SummonRevealView: View {
    let results: [SummonResult]
    /// The scroll the summon spent, drawn in the charge. Nil infers one from
    /// the result (`scrollShown`), and an awakening draws none.
    var scroll: ScrollType? = nil
    let onFinish: () -> Void

    @State private var index = 0
    @State private var showAll = false

    // The staged reveal, in order. `charging` starts TRUE so the very first
    // frame, drawn before the stage has been built, is already the charge.
    @State private var charging = true
    /// When the charge's clock started: the moment its stage finished
    /// building and drawing itself once (`stageReady`). Nil until then, and
    /// the charge holds its opening pose — its rings still turning — while
    /// it waits.
    @State private var chargeStart: Date?
    /// How long this charge runs: 1.25 s for every grade, 1.4 s for a 5★
    /// (`ChargeLadder.span`). It was 0.8 s under a 4★, which told a common
    /// pull by its length alone.
    @State private var chargeDuration: TimeInterval = ChargeLadder.baseSpan
    /// The sequence whose charge is waiting on its stage to be built.
    @State private var awaitingStage: Int?
    /// The stage in the view tree (`stageKey`). It goes in a beat AFTER the
    /// reveal's first frame, so that frame is the charge, not a stall.
    @State private var mountedStage: String?
    /// The stage that has finished building and its warm-up.
    @State private var readyStage: String?
    /// When the flash went off, and how long it takes to clear (see
    /// `flashOpacity`). Nil when there is no flash on the screen.
    @State private var flashAt: Date?
    @State private var flashSpan: TimeInterval = 0.55
    /// When this pull's charge came on the screen. The rings turn and the
    /// motes climb from here, before the stage is ready and the charge's own
    /// clock (`chargeStart`) begins, so the wait is never a frozen picture.
    @State private var ambientStart = Date()
    @State private var revealed = false
    /// The name card's moment (Docs/FEEL.md W2.13): its two keyframe
    /// timelines replace the three timers the words ran on (`shownStars`,
    /// `nameSlam`, `detailsShown`).
    @State private var cardBeat: RevealCardBeat = .hidden
    @State private var cardTiming = RevealCardTiming.standard(stars: 3)
    /// The sequence whose card has arrived (`cardArrives`) and whose name has
    /// landed (`nameLands`), so the figure's first frame, the clip's high
    /// point and their fallbacks each act once.
    @State private var arrivedFor: Int?
    @State private var namedFor: Int?
    /// A tap during a 5★'s charge that came before its stage was ready: the
    /// charge lands the moment the stage is (Docs/FEEL.md W2.23).
    @State private var landOnReady = false
    /// This pull plays as a Quick summons flash (`RevealSkip.playsQuick`).
    @State private var quickPull = false
    /// The CI's one automatic Skip has been pressed (`-tour-reveal-skip`).
    @State private var tourSkipped = false
    /// This reveal's step back of the music (`AudioLibrary.duck`), let go
    /// when it leaves.
    @State private var musicDuck: Int?
    @State private var rays: Double = 0
    /// Bumped whenever a sequence is started or cut short, so a stale timer
    /// from a skipped reveal cannot land on the next one.
    @State private var sequence = 0

    private var current: SummonResult? {
        results.indices.contains(index) ? results[index] : nil
    }

    /// The pull's name is on its card: a tap moves on rather than finishing
    /// the words.
    private var isFullyRevealed: Bool { namedFor == sequence }

    var body: some View {
        ZStack {
            backdrop

            // The set fills the screen edge to edge behind the words: an
            // inset view showed its own rectangle where the floor stopped.
            //
            // Keyed on WHAT is on the beam (`stageKey`), never on the
            // result's UUID (run 220). The tour builds its result in its own
            // body, so every re-render of the tour minted a new UUID, and
            // `.id(current.id)` tore the stage down and built it again: four
            // builds of Sekhmet in one reveal, 1.4 s, 2.1 s and 0.4 s of
            // main thread, and the 3-second frame fell inside the second —
            // an empty dusk with only Skip on it.
            if !showAll, let current {
                let key = stageKey(current)
                if mountedStage == key {
                    SummonStageView(
                        result: current,
                        revealed: revealed,
                        onReady: { stageReady(key) },
                        onShown: { plan in stageShown(key, plan: plan) },
                        onApex: { stageApex(key) }
                    )
                    .id(key)
                    .ignoresSafeArea()
                }
                // The charge stands OVER the set, where the figure will
                // land, so it reads whether the set has drawn yet or not.
                if charging {
                    chargeLayer(current)
                }
            }

            if showAll {
                grid
            } else if let current {
                single(current)
            }

            // The flash on reveal. White over the rarity tint, gone in half a
            // second; it covers the figure arriving whole on the beam.
            //
            // Read off the wall clock (2026-09-23, run 221), not animated:
            // a SwiftUI fade starts on the first frame after its change, so
            // a main thread held up behind the stage started it a second
            // late and froze it at 28% — the 3-second frame was the words
            // under a white veil. Drawn as a function of the time since it
            // went off, it is wherever it should be the moment a frame is
            // drawn at all.
            if let flashAt {
                TimelineView(.animation) { timeline in
                    Color.white
                        .opacity(Self.flashOpacity(at: timeline.date, since: flashAt, span: flashSpan))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Skip never swallows a 5★ (Docs/FEEL.md W2.23): a tap goes to
            // the next pull worth seeing and says which; a hold of 0.6 s
            // skips everything.
            VStack {
                HStack {
                    Spacer()
                    RevealSkipControl(
                        label: skipLabel,
                        offersHold: !showAll && results.count > 1,
                        onTap: { skipTapped() },
                        onHold: { skipAll() }
                    )
                    .padding(12)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            LightningArt.prepare()
            RevealFlipbook.prepare()
            // The music steps back for the rite (Docs/FEEL.md W2.7).
            musicDuck = AudioLibrary.shared.duck(to: Self.musicUnderReveal, fade: 0.5)
            revealNext()
        }
        // The stage goes when the reveal does (2026-09-24). A dismissed
        // full-screen cover can keep its content on iOS 17, and with it the
        // stage's scene, its figure and every texture it uploaded (run 242:
        // about 30 MB a reveal, never given back). Unmounting it here hands
        // it to `SummonStageView.dismantleUIView` whatever the cover does.
        .onDisappear {
            sequence += 1
            awaitingStage = nil
            mountedStage = nil
            readyStage = nil
            hushCharge(over: 0.2)
            AudioLibrary.shared.unduck(musicDuck, fade: 1.0)
        }
    }

    /// What Skip says: where a tap on it goes, or Done over the summary.
    private var skipLabel: RevealSkipLabel {
        if showAll { return .done }
        let target: RevealSkipTarget = RevealSkip.target(in: results, at: index, landed: revealed)
        return RevealSkip.label(in: results, for: target, at: index)
    }

    /// The island's music under a reveal, as a share of its own level: about
    /// 10 dB down, so the charge's stems and the burst sit on top of it.
    private static let musicUnderReveal: Float = 0.3

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            // DUSK since 2026-09-18. The reveal stood on the interface's cream
            // (`Theme.backdrop`) and every figure on it read pale — a figure is
            // judged against what is behind it, and the genre knows it: every
            // summon in the genre happens against a dark sky with a shaft of
            // light (Summoners War's night circle, Raid's portal room). The
            // temple keeps its marble, lit by the same key as the figure; the
            // sky between the columns is this — deep indigo over a violet dusk
            // and an ember horizon — and the corners fall to ink, so the words
            // on the right are cream and gold on dark, the way a reveal's are.
            LinearGradient(
                stops: [
                    .init(color: Self.duskZenith, location: 0.0),
                    .init(color: Self.duskViolet, location: 0.45),
                    .init(color: Self.duskEmber, location: 0.72),
                    .init(color: Self.duskGround, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if let current {
                let tint = tint(for: current)

                // Rays for the top grades. They rotate slowly the whole time
                // and only become visible on the reveal. Half the old strength:
                // `.plusLighter` adds, so eight arms at 0.35 over a glow that
                // was itself at 0.55 put the left of the screen within a few
                // per cent of white before the 3D layer drew a single pixel.
                // They also fade in now rather than switching on, which is what
                // made them read as a decal laid over the shot.
                if current.stars >= 4 {
                    AngularGradient(
                        colors: [tint.opacity(0.0), tint.opacity(0.20), tint.opacity(0.0),
                                 tint.opacity(0.20), tint.opacity(0.0), tint.opacity(0.20),
                                 tint.opacity(0.0), tint.opacity(0.20), tint.opacity(0.0)],
                        center: .center
                    )
                    .scaleEffect(2.4)
                    .opacity(revealed ? 1 : 0)
                    // The fade is scoped to sit UNDER the rotation, not over
                    // it. An `.animation(_:value:)` governs every animatable
                    // change in the subtree it wraps at the instant its value
                    // flips, and the instant `revealed` flips is exactly when
                    // `rays` is mid-flight in the `repeatForever` started in
                    // `onAppear` below — so with the rotation inside the
                    // wrapper a 0.7 s ease-out is in a position to retarget
                    // the spin and leave the rays parked for the rest of the
                    // reveal. Opacity and a rotation about the same centre
                    // commute, so keeping them in this order costs nothing.
                    .animation(.easeOut(duration: 0.7), value: revealed)
                    .rotationEffect(.degrees(rays))
                    .blendMode(.plusLighter)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                            rays = 360
                        }
                    }
                }

                // The glow behind the figure: gathers during the charge, blooms
                // on the reveal.
                //
                // This is not a background. The stage view above it is
                // transparent on purpose, so between the pillars and above the
                // temple THIS is the sky, and a flat 0.55 of the rarity colour
                // held out to a 360 pt radius covered most of a 852 x 393 frame
                // in one unbroken sheet — the "very bright, close to blown out
                // in the upper left" the playtest called on the Hoplite reveal.
                // It peaks lower now and falls off inside the frame instead of
                // at its edge, which also puts a gradient behind the figure
                // rather than a wash, and the figure reads against it.
                //
                // Two glows since 2026-09-24. Through the charge it is the
                // LADDER's light, read off the charge's clock (`chargeSky`):
                // it was the grade's colour from the first frame, violet for
                // a 4★ and gold for a 5★ before a single rung was climbed —
                // the plainest tell on the screen. On the reveal it blooms in
                // the grade's colour, which is honest by then.
                if charging {
                    TimelineView(.animation) { timeline in
                        chargeSky(current, at: timeline.date)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
                RadialGradient(
                    colors: [tint.opacity(revealed ? 0.40 : 0),
                             tint.opacity(revealed ? 0.19 : 0),
                             tint.opacity(revealed ? 0.06 : 0),
                             .clear],
                    center: .init(x: 0.27, y: 0.5),
                    startRadius: 0,
                    endRadius: revealed ? 320 : 130
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.5), value: revealed)

                // The corners go back to the plain ground. A landscape frame
                // is wide enough that the glow and the rays reach all four of
                // them, and a corner left to the rays is the cheapest-looking
                // thing in a reveal, so the fall-off returns them to the cream
                // the rest of the interface stands on. Centred on the figure,
                // not on the screen, so it frames the character rather than
                // the layout. Cream, not ink: the ground is `Theme.backdrop`
                // and the words on the right are ink, and an ink corner stood
                // the name and the epithet on the one dark patch of the frame.
                RadialGradient(
                    colors: [.clear, Self.duskGround.opacity(0.10), Self.duskGround.opacity(0.42), Self.duskGround.opacity(0.82)],
                    center: .init(x: 0.30, y: 0.52),
                    startRadius: 0,
                    endRadius: 560
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    private func tint(for result: SummonResult) -> Color {
        Rarity(stars: result.stars).glow
    }

    /// The dusk the reveal stands in (see `backdrop`), and the cream its
    /// words are set in.
    private static let duskZenith = Color(hex: "#12162B")
    private static let duskViolet = Color(hex: "#3A2C4E")
    private static let duskEmber = Color(hex: "#9C5F33")
    private static let duskGround = Color(hex: "#15110F")
    private static let duskInk = Color(hex: "#D9CDB3")
    /// The name's gold, pale at the top of the letters and deeper at their
    /// foot; NEW and AWAKENED wear it too.
    private static let nameGold = LinearGradient(colors: [Color(hex: "#FFF3C4"), Color(hex: "#E2C15E")],
                                                 startPoint: .top, endPoint: .bottom)

    /// The flash's white at `date`: 0.85 when it goes off, falling straight
    /// to nothing over `span`, whatever the frames in between were doing.
    private static func flashOpacity(at date: Date, since start: Date, span: TimeInterval) -> Double {
        let elapsed = max(0, date.timeIntervalSince(start))
        return 0.85 * max(0, 1 - elapsed / max(0.05, span))
    }

    // MARK: - The charge

    /// The anticipation beat, drawn in SwiftUI over the set (2026-09-23).
    ///
    /// Run 220's frame three seconds into a 5★ summon was the dusk and Skip
    /// and nothing else: the charge was a gathering of the rarity glow
    /// BEHIND a stage that had not drawn yet. The genre never shows an empty
    /// beat — Summoners War's scroll burns over its circle in a pillar of
    /// light before the monster steps out — so this is the same: the scroll
    /// the player spent (the painting the summon room hangs over its ring)
    /// in front of two rune rings turning opposite ways in the element's
    /// colour, a beam rising from the floor where the feet will land, motes
    /// climbing it, and a white flare in the last quarter that the flash
    /// takes over. The scale CLIMBS (2026-09-24, `ChargeLadder`): every
    /// charge opens as a 3★'s did — a cool blue-white, a narrow beam, dim
    /// slow rings — and a 4★ or better steps up to violet, a 5★ to gold
    /// with lightning round the beam. It was set by the grade from the first
    /// frame (`grandeur`), which told the pull before the charge began. The
    /// element keeps the rings and the pool of light on the floor; the
    /// ladder's light is the beam's, the motes', the flare's and the
    /// scroll's glow.
    ///
    /// One blend mode, on the beam alone (`chargeBeamLayer`): its light is
    /// ADDED to the set, as a column of light is in every summon in the
    /// genre. Drawn plainly over the set, run 234's 5★ beam peaked at
    /// 201–225 with a core about 15 points wide and its ember flanks lost
    /// on the Duat's orange — a streak, not a pillar. A blend over a
    /// SceneKit view is not new here (the victory chest's flash is
    /// `.plusLighter` over its SCNView), and should one ever be resolved
    /// without the platform view under it, plus-lighter over nothing is the
    /// beam drawn plainly, never black. Everything else is drawn plainly.
    ///
    /// The rings are the painted `rune_ring` keyed to its drawn lines
    /// (`RuneLinesArt`) and used as a MASK over the element's colour, so the
    /// black and the painted glow between the lines are simply absent.
    /// Everything is a pure function of two clocks read off a
    /// `TimelineView`, so a stale animation cannot retarget it: the charge's
    /// own (`chargeClock`), which gathers it, and the ambient one, which
    /// turns the rings and lifts the motes from the first frame, while the
    /// stage is still being built and drawn.
    private func chargeLayer(_ result: SummonResult) -> some View {
        GeometryReader { frame in
            TimelineView(.animation) { timeline in
                chargeScene(result,
                            clock: chargeClock(at: timeline.date),
                            ambient: max(0, timeline.date.timeIntervalSince(ambientStart)),
                            size: frame.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Seconds since the charge's clock started; zero while the stage is
    /// still being built, which holds the opening pose.
    private func chargeClock(at date: Date) -> TimeInterval {
        guard let chargeStart else { return 0 }
        return max(0, date.timeIntervalSince(chargeStart))
    }

    /// How far the charge has gathered at `clock`: the clock itself, or,
    /// under the CI's hold (`chargeHold`), no further than its fraction of
    /// the span.
    private func gatheredClock(_ clock: TimeInterval) -> TimeInterval {
        let span: TimeInterval = max(0.1, chargeDuration)
        guard let hold = Self.chargeHold else { return clock }
        return min(clock, span * hold)
    }

    /// The sky's glow through the charge (`backdrop`): the ladder's light,
    /// gathering in over 0.9 s from the pull's first frame and a quarter
    /// brighter and a little wider for each rung climbed — at gold 0.30,
    /// under the reveal's own 0.40.
    private func chargeSky(_ result: SummonResult, at date: Date) -> some View {
        let gathered: TimeInterval = gatheredClock(chargeClock(at: date))
        let rgb: ChargeRGB = ChargeLadder.light(stars: result.stars, element: result.blueprint.element, at: gathered)
        let light: Color = rgb.color
        let level: CGFloat = ChargeLadder.rung(stars: result.stars, at: gathered)
        let since: TimeInterval = max(0, date.timeIntervalSince(ambientStart))
        let gatherIn: Double = min(1, since / 0.9)
        let lift: Double = 1 + 0.25 * Double(level)
        let peak: Double = 0.20 * gatherIn * lift
        let colours: [Color] = [light.opacity(peak), light.opacity(peak * 0.45), light.opacity(peak * 0.15), .clear]
        let radius: CGFloat = 130 + 25 * level
        return RadialGradient(colors: colours, center: .init(x: 0.27, y: 0.5), startRadius: 0, endRadius: radius)
    }

    private func chargeScene(_ result: SummonResult, clock: TimeInterval, ambient: TimeInterval,
                             size: CGSize) -> some View {
        let look = chargeLook(result, clock: clock, ambient: ambient, size: size)
        // One small builder per layer, every number worked out beforehand in
        // `ChargeLook`: the one ZStack of eight layers with its sums inline
        // was more than the owner's Xcode could type-check "in reasonable
        // time" (2026-09-23, the build failed on his machine; CI's Xcode 16
        // accepted it). Nothing drawn changed.
        return ZStack {
            chargePool(look)
            chargeRings(look)
            // A Dark 5★'s violet-black, over the rings and under the light.
            chargeVeil(look)
            // The scroll's glow UNDER the beam and the scroll itself over it
            // (run 234): drawn as the scroll's own shadow, the glow lay over
            // the column and turned it red below the roll, so the pillar
            // faded out before it reached the scroll it holds up.
            chargeScrollGlow(result, look: look)
            // The beam, rising from the floor as the charge gathers: OVER the
            // rings, so the pillar of light runs through them to the scroll
            // (the genre's scroll burns in its column; run 221 drew the
            // column under the rings and lost it).
            chargeBeamLayer(look)
            chargeLightning(look)
            chargeMotes(look)
            chargeFlare(look)
            chargeScrollLayer(result, look: look)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Every number the charge draws with, as typed values, so no layer's
    /// view expression holds arithmetic.
    private struct ChargeLook {
        /// The element's colour: the rings' glyphs and the pool of light.
        let colour: Color
        /// The ladder's light (`ChargeLadder.light`): the beam's flanks, the
        /// motes, the flare, the scroll's glow and the sky behind.
        let light: Color
        /// The white at the heart of the beam, the flare and the motes;
        /// pale violet once a Dark 5★ has split.
        let core: Color
        /// Where the ladder stands, 0 on the ground to 1 at gold.
        let grand: CGFloat
        let ambient: TimeInterval
        let x: CGFloat
        let feet: CGFloat
        let heart: CGFloat
        let poolSide: CGFloat
        let poolRadius: CGFloat
        let poolStretch: CGFloat
        let poolOpacity: Double
        let ringSize: CGFloat
        let innerRingSize: CGFloat
        let ringScale: CGFloat
        let outerTurn: Double
        let innerTurn: Double
        let outerRingOpacity: Double
        let innerRingOpacity: Double
        let beamWidth: CGFloat
        let beamHeight: CGFloat
        let beamCentre: CGFloat
        let beamOpacity: Double
        let moteSpread: CGFloat
        let motes: Int
        /// How many motes are lit: 4 on the ground, 8 at violet, 12 at gold,
        /// each fading in as the ladder passes it (`chargeMote`).
        let moteLevel: CGFloat
        /// How far the motes have risen, in beam-heights (`ChargeLadder.travel`).
        let moteTravel: Double
        let side: CGFloat
        let flareSide: CGFloat
        let flareRadius: CGFloat
        let flareScale: CGFloat
        let flareOpacity: Double
        let scrollTilt: Double
        let scrollScale: CGFloat
        let scrollGlow: CGFloat
        let scrollY: CGFloat
        /// A Dark 5★'s violet-black veil, 0 for every other pull.
        let shade: Double
        let veilSide: CGFloat
        /// The lightning round a 5★'s beam: its strength (0 below gold), its
        /// colour, its size and place, and the frame each bolt is on.
        let lightning: Double
        let boltTint: Color
        let boltSide: CGFloat
        let boltY: CGFloat
        let boltLeftX: CGFloat
        let boltRightX: CGFloat
        let boltLeft: Int
        let boltRight: Int
    }

    private func chargeLook(_ result: SummonResult, clock: TimeInterval, ambient: TimeInterval,
                            size: CGSize) -> ChargeLook {
        let stars: Int = result.stars
        let element: Element = result.blueprint.element
        let colour: Color = element.color
        let span: TimeInterval = max(0.1, chargeDuration)
        // Held (the CI's charge frames, `chargeHold`) at a fraction of the
        // way: the rings and the motes keep turning at the rung reached, the
        // gathering stops there.
        let gathered: TimeInterval = gatheredClock(clock)
        // The gather runs on the BASE span for every grade (review,
        // 2026-09-24): over the pull's own span a 5★'s beam rose visibly
        // slower from the first frame — 12 points shorter at 0.35 s, before
        // any rung — which read the grade the ladder keeps hidden until the
        // gold. A 5★ holds at full gather for its extra 0.15 s, and its
        // flare runs over the LAST 0.35 s of its own span, which a 3★ and a
        // 4★ start at 0.90 s, as before, and a 5★ at 1.05 s, past the gold.
        let progress: CGFloat = CGFloat(min(1, gathered / ChargeLadder.baseSpan))
        let rest: CGFloat = 1 - progress
        let gather: CGFloat = 1 - rest * rest * rest
        let flareStart: TimeInterval = span - 0.35
        let flareRamp: CGFloat = CGFloat((gathered - flareStart) / 0.35)
        let flare: CGFloat = max(0, min(1, flareRamp))

        // THE LADDER (2026-09-24). `level` is 0 on the ground every charge
        // opens on, 1 at violet, 2 at gold; `grand` is the same on the 0…1
        // scale the old `grandeur` used, so a charge that has climbed to its
        // grade's rung ends exactly as that grade's charge always looked.
        let level: CGFloat = ChargeLadder.rung(stars: stars, at: gathered)
        let grand: CGFloat = level / 2
        let goldReached: CGFloat = stars >= 5 ? ChargeLadder.climbed(ChargeLadder.goldAt, at: gathered) : 0
        let parted: CGFloat = ChargeLadder.split(stars: stars, element: element, at: gathered)
        // What a pace that climbs with the ladder has covered: the charge's
        // own climb to where it is held, then the held rung's pace. The
        // rings' turn and the motes' rise are read off it, so a step
        // quickens them without a jump in where they stand.
        let heldFor: TimeInterval = max(0, clock - gathered)
        let ladderTravel: CGFloat = ChargeLadder.travel(stars: stars, to: gathered) + level * CGFloat(heldFor)
        let lightRGB: ChargeRGB = ChargeLadder.light(stars: stars, element: element, at: gathered)
        let light: Color = lightRGB.color
        let darkParting: CGFloat = element == .umbra ? parted : 0
        let core: Color = ChargeRGB.white.mixed(with: ChargeLadder.umbraCore, by: darkParting).color

        // The figure's line and height, as the stage's camera is solved
        // (`SummonStageView.frameCamera`): its centre line 26% in from the
        // left, its feet 7% above the bottom edge, its heart a little above
        // the frame's middle.
        let height: CGFloat = size.height
        let x: CGFloat = size.width * SummonStageView.figureLine
        let feet: CGFloat = height * 0.93
        let heart: CGFloat = height * 0.42

        // A 5★'s pillar is 0.28 of the frame's height across (run 221: at
        // 0.20, and drawn under the rings, it showed as a faint streak below
        // them); the ground's is a thin shaft, a violet one 0.19. Through the
        // gather the gold stands at 0.85, the violet at 0.65 and the ground
        // at 0.45, and the flare lifts each by 15% more: run 234's 5★
        // gathered at 0.68, and its white never reached 230.
        let beamShare: CGFloat = 0.10 + 0.18 * grand
        let beamWidth: CGFloat = height * beamShare
        let beamRise: CGFloat = 0.30 + 0.70 * gather
        let beamHeight: CGFloat = feet * beamRise
        let beamCentre: CGFloat = feet - beamHeight / 2
        let beamBase: CGFloat = 0.45 + 0.40 * grand
        let beamFlare: CGFloat = 1 + 0.15 * flare
        let beamLight: CGFloat = min(1, beamBase * beamFlare)
        let beamOpacity: Double = Double(beamLight)
        // The motes keep the sway they had with the narrower beam. All
        // twelve are laid out from the first frame and lit as the ladder
        // reaches them, so none pops in at a step; they rise at 0.55 of the
        // beam a second on the ground and 0.85 at gold.
        let spreadShare: CGFloat = 0.10 + 0.10 * grand
        let moteSpread: CGFloat = height * spreadShare
        let motes: Int = 12
        let moteLevel: CGFloat = 4 + 8 * grand
        let moteGround: Double = 0.55 * ambient
        let moteClimb: Double = 0.15 * Double(ladderTravel)
        let moteTravel: Double = moteGround + moteClimb

        // A pool of the element's light on the floor under the feet.
        let poolSide: CGFloat = height * 0.40
        let poolRadius: CGFloat = height * 0.20
        let poolStretch: CGFloat = 1 + 0.4 * grand
        let poolLight: CGFloat = 0.45 + 0.45 * gather
        let poolOpacity: Double = Double(poolLight)

        // Two rings, turning opposite ways, closing in as it gathers.
        let ringShare: CGFloat = 0.44 + 0.18 * grand
        let ringSize: CGFloat = height * ringShare
        let innerRingSize: CGFloat = ringSize * 0.62
        let ringScale: CGFloat = 1.10 - 0.12 * gather
        // 24° a second on the ground, 42 at violet, 60 at gold: the rest pace
        // over the whole wait, and 18° a second more for every rung, over
        // the time since it was climbed (`ladderTravel`).
        let groundTurn: Double = 24 * ambient
        let climbTurn: Double = 18 * Double(ladderTravel)
        let outerTurn: Double = groundTurn + climbTurn
        let innerTurn: Double = -outerTurn * 1.6
        let outerLight: CGFloat = 0.50 + 0.40 * grand
        let innerLight: CGFloat = 0.36 + 0.40 * grand

        // The flare the flash takes over.
        let sideShare: CGFloat = 0.24 + 0.07 * grand
        let side: CGFloat = height * sideShare
        let flareSide: CGFloat = side * 1.8
        let flareRadius: CGFloat = side * 0.9
        let flareScale: CGFloat = 0.6 + 0.8 * flare
        let flareLight: CGFloat = 0.45 + 0.45 * grand
        let flareOpacity: Double = Double(flare * flareLight)

        // The scroll itself, straightening and swelling in the light.
        let sway: Double = sin(ambient * 2.6)
        let bob: CGFloat = CGFloat(sway) * 4 * rest
        let scrollTilt: Double = -12 * Double(rest)
        let scrollScale: CGFloat = 1 + 0.16 * gather
        let glowShare: CGFloat = 0.08 + 0.14 * gather
        let scrollGlow: CGFloat = side * glowShare
        let scrollY: CGFloat = heart + bob

        // A Dark 5★'s split: a veil of violet-black a frame's height across,
        // at half strength once it has parted.
        let shade: Double = 0.5 * Double(darkParting)
        let veilSide: CGFloat = height * 1.1

        // THE LIGHTNING (2026-09-24): a 5★'s tell, from the gold rung on.
        // `vfx_lightning_sheet`'s sixteen frames, two bolts either side of
        // the beam half a cycle apart, so one strikes while the other fades.
        // A cell's bolt comes down from its top to a splash 85% of the way
        // down it, so a cell standing 0.35 of its side above the feet puts
        // the splash on the dais beside the beam's foot. Its size, strength
        // and white are MEASURED: composited as `.plusLighter` adds over run
        // 242's held 5★ charge (whose beam already clips 7% of the left of
        // the frame by design), 0.72 of the frame high at 0.8 took the
        // worst strike to 19% of the left and 13% of the near floor over 240
        // (framelight's measure); 0.62 at 0.55 with a quarter of white takes
        // it to about 12% and 7.5%, and the bolt still reads as lightning.
        // The temple is lit less since the same day (figure-first light), so
        // the CI frame should clip less than the mock. 24 frames a second;
        // half the rate and about half the strength under Reduce Motion
        // (`MotionComfort`), since a flicker is what that setting asks to be
        // spared.
        let calm: Bool = MotionComfort.isReduced
        let boltSide: CGFloat = height * 0.62
        let boltY: CGFloat = feet - boltSide * 0.35
        let boltReach: CGFloat = beamWidth * 0.5 + boltSide * 0.12
        let boltRate: Double = calm ? 12 : 24
        let boltTick: Int = Int(ambient * boltRate)
        let cycle: Int = LightningArt.frameCount
        let boltLeft: Int = boltTick % cycle
        let boltRight: Int = (boltTick + cycle / 2) % cycle
        let boltStrength: CGFloat = calm ? 0.3 : 0.55
        let lightning: Double = Double(goldReached * boltStrength)
        let boltTint: Color = lightRGB.mixed(with: ChargeRGB.white, by: 0.25).color
        let boltLeftX: CGFloat = x - boltReach
        let boltRightX: CGFloat = x + boltReach

        return ChargeLook(
            colour: colour, light: light, core: core, grand: grand, ambient: ambient,
            x: x, feet: feet, heart: heart,
            poolSide: poolSide, poolRadius: poolRadius, poolStretch: poolStretch, poolOpacity: poolOpacity,
            ringSize: ringSize, innerRingSize: innerRingSize, ringScale: ringScale,
            outerTurn: outerTurn, innerTurn: innerTurn,
            outerRingOpacity: Double(outerLight), innerRingOpacity: Double(innerLight),
            beamWidth: beamWidth, beamHeight: beamHeight, beamCentre: beamCentre, beamOpacity: beamOpacity,
            moteSpread: moteSpread, motes: motes, moteLevel: moteLevel, moteTravel: moteTravel,
            side: side, flareSide: flareSide, flareRadius: flareRadius,
            flareScale: flareScale, flareOpacity: flareOpacity,
            scrollTilt: scrollTilt, scrollScale: scrollScale, scrollGlow: scrollGlow, scrollY: scrollY,
            shade: shade, veilSide: veilSide,
            lightning: lightning, boltTint: boltTint, boltSide: boltSide, boltY: boltY,
            boltLeftX: boltLeftX, boltRightX: boltRightX,
            boltLeft: boltLeft, boltRight: boltRight
        )
    }

    /// A pool of the element's light on the floor under the feet.
    private func chargePool(_ look: ChargeLook) -> some View {
        let colours: [Color] = [look.colour.opacity(0.85), look.colour.opacity(0.25), look.colour.opacity(0)]
        let light = RadialGradient(colors: colours, center: .center, startRadius: 0, endRadius: look.poolRadius)
        return Circle()
            .fill(light)
            .frame(width: look.poolSide, height: look.poolSide)
            .scaleEffect(x: look.poolStretch, y: 0.22)
            .opacity(look.poolOpacity)
            .position(x: look.x, y: look.feet)
    }

    /// Two rings, turning opposite ways, closing in as it gathers.
    private func chargeRings(_ look: ChargeLook) -> some View {
        Group {
            chargeRing(colour: look.colour, diameter: look.ringSize)
                .scaleEffect(look.ringScale)
                .rotationEffect(.degrees(look.outerTurn))
                .opacity(look.outerRingOpacity)
                .position(x: look.x, y: look.heart)
            chargeRing(colour: look.colour, diameter: look.innerRingSize)
                .scaleEffect(look.ringScale)
                .rotationEffect(.degrees(look.innerTurn))
                .opacity(look.innerRingOpacity)
                .position(x: look.x, y: look.heart)
        }
    }

    /// The beam, ADDED to whatever is under it: the set, the rings and the
    /// scroll's glow (see `chargeLayer` for why this one layer blends).
    private func chargeBeamLayer(_ look: ChargeLook) -> some View {
        chargeBeam(light: look.light, core: look.core)
            .frame(width: look.beamWidth, height: look.beamHeight)
            .opacity(look.beamOpacity)
            .blendMode(.plusLighter)
            .position(x: look.x, y: look.beamCentre)
    }

    /// The violet-black a Dark 5★ splits into (2026-09-24): a veil over the
    /// rings and the set round the beam, drawn PLAINLY — an added layer can
    /// only brighten, and this is the light going out. Transparent for
    /// every other pull.
    private func chargeVeil(_ look: ChargeLook) -> some View {
        let ink: Color = Self.veilInk
        let colours: [Color] = [ink.opacity(0.95), ink.opacity(0.55), ink.opacity(0)]
        let dark = RadialGradient(colors: colours, center: .center, startRadius: 0, endRadius: look.veilSide / 2)
        return Circle()
            .fill(dark)
            .frame(width: look.veilSide, height: look.veilSide)
            .opacity(look.shade)
            .position(x: look.x, y: look.heart)
    }

    /// The lightning round a 5★'s beam (2026-09-24), the genre's nat-5 tell:
    /// two bolts of `vfx_lightning_sheet`, the right one mirrored, ADDED to
    /// the set like the beam. Nothing is drawn below the gold rung.
    private func chargeLightning(_ look: ChargeLook) -> some View {
        ZStack {
            chargeBolt(frame: look.boltLeft, mirrored: false, look: look)
                .position(x: look.boltLeftX, y: look.boltY)
            chargeBolt(frame: look.boltRight, mirrored: true, look: look)
                .position(x: look.boltRightX, y: look.boltY)
        }
    }

    /// One bolt: the painted frame taken to grey and multiplied by the
    /// ladder's light lifted toward white, so the sheet's blue bolt strikes
    /// gold (white-gold or violet once a Light or Dark 5★ has split). The
    /// frame is read only once `LightningArt` has cut it; until then there
    /// is no bolt rather than a wait.
    @ViewBuilder
    private func chargeBolt(frame: Int, mirrored: Bool, look: ChargeLook) -> some View {
        if look.lightning > 0, let cell = LightningArt.frame(frame) {
            Image(uiImage: cell)
                .resizable()
                .interpolation(.medium)
                .saturation(0)
                .colorMultiply(look.boltTint)
                .frame(width: look.boltSide, height: look.boltSide)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .opacity(look.lightning)
                .blendMode(.plusLighter)
        }
    }

    /// Motes climbing the beam: all twelve laid out, each lit as the ladder
    /// reaches it (`moteLevel`).
    private func chargeMotes(_ look: ChargeLook) -> some View {
        ForEach(0..<look.motes, id: \.self) { mote in
            chargeMote(mote, look: look)
                .position(Self.motePoint(mote, travel: look.moteTravel, clock: look.ambient,
                                         x: look.x, feet: look.feet, spread: look.moteSpread))
        }
    }

    /// The flare the flash takes over.
    private func chargeFlare(_ look: ChargeLook) -> some View {
        let colours: [Color] = [look.core.opacity(0.9), look.light.opacity(0.4), look.light.opacity(0)]
        let light = RadialGradient(colors: colours, center: .center, startRadius: 0, endRadius: look.flareRadius)
        return Circle()
            .fill(light)
            .frame(width: look.flareSide, height: look.flareSide)
            .scaleEffect(look.flareScale)
            .opacity(look.flareOpacity)
            .position(x: look.x, y: look.heart)
    }

    /// The scroll's glow: its silhouette in the ladder's light at 0.85 (the
    /// element's colour until 2026-09-24), blurred as far as its shadow was
    /// (`scrollGlow`), in the scroll's own place and turn. It was the
    /// scroll's `.shadow` until run 234, and a shadow is drawn with its
    /// view, so the glow could not go under the beam while the scroll stayed
    /// over it (`chargeScene`).
    private func chargeScrollGlow(_ result: SummonResult, look: ChargeLook) -> some View {
        look.light.opacity(0.85)
            .frame(width: look.side, height: look.side)
            .mask { chargeScroll(result, side: look.side, colour: look.colour) }
            .rotationEffect(.degrees(look.scrollTilt))
            .scaleEffect(look.scrollScale)
            .blur(radius: look.scrollGlow)
            .position(x: look.x, y: look.scrollY)
    }

    /// The scroll itself, straightening and swelling in the light, over the
    /// beam; its glow is `chargeScrollGlow`, under it.
    private func chargeScrollLayer(_ result: SummonResult, look: ChargeLook) -> some View {
        chargeScroll(result, side: look.side, colour: look.colour)
            .rotationEffect(.degrees(look.scrollTilt))
            .scaleEffect(look.scrollScale)
            .position(x: look.x, y: look.scrollY)
    }

    /// The violet-black a Dark 5★'s charge parts into (`chargeVeil`).
    private static let veilInk = Color(hex: "#0C0614")

    /// A column of light: `core` (white) held flat across the middle fifth
    /// of its width, the ladder's light either side (the element's colour
    /// until 2026-09-24), clear at the edges; full from the floor up behind
    /// the scroll, fading out over its top third. Added to the set
    /// (`chargeBeamLayer`), so the core burns to white on whatever stands
    /// behind it and the colour lights the set rather than painting over it.
    ///
    /// Run 234's beam peaked at ONE stop, white at 0.95 between flanks of
    /// the colour at 0.55, so only its centre line was white at all, and
    /// its top half faded out: the scroll hangs at 0.42 of the frame's
    /// height, inside that fade. The mock of the held charge (run 234's
    /// frame with the old beam taken out and this one added) reads 252–255
    /// on the axis from the floor to the inner ring, over 230 across 40–55
    /// points; drawn plainly instead, 223–236 across 10–25.
    private func chargeBeam(light: Color, core: Color) -> some View {
        let across: [Gradient.Stop] = [
            .init(color: light.opacity(0), location: 0),
            .init(color: light.opacity(0.35), location: 0.20),
            .init(color: core.opacity(0.95), location: 0.40),
            .init(color: core.opacity(0.95), location: 0.60),
            .init(color: light.opacity(0.35), location: 0.80),
            .init(color: light.opacity(0), location: 1),
        ]
        // Top to foot. The last twentieth eases to half into the pool of
        // light under the feet: added white stopping dead on the floor line
        // read as the end of a bar in the mock, not light meeting the floor.
        let upward: [Gradient.Stop] = [
            .init(color: Color.white.opacity(0), location: 0),
            .init(color: Color.white, location: 0.35),
            .init(color: Color.white, location: 0.95),
            .init(color: Color.white.opacity(0.5), location: 1),
        ]
        return LinearGradient(stops: across, startPoint: .leading, endPoint: .trailing)
            .mask {
                LinearGradient(stops: upward, startPoint: .top, endPoint: .bottom)
            }
    }

    /// The painted rune ring in the element's colour, its drawn LINES only
    /// (`RuneLinesArt`), with a glow of the same colour round them: 4 points
    /// at 0.7, where 6 at 0.9 merged the glows of the dense rune bands and
    /// moved the stone between the lines by 20 levels (measured on the mock
    /// of the held charge; 14 at this).
    @ViewBuilder
    private func chargeRing(colour: Color, diameter: CGFloat) -> some View {
        if let lines = RuneLinesArt.image {
            colour
                .frame(width: diameter, height: diameter)
                .mask {
                    Image(uiImage: lines)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
                .shadow(color: colour.opacity(0.7), radius: 4)
        } else {
            Circle()
                .strokeBorder(colour.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 10]))
                .frame(width: diameter, height: diameter)
        }
    }

    /// The scroll spent, as the summon room hangs it; an awakening spends
    /// none and gathers the unit's own light instead.
    @ViewBuilder
    private func chargeScroll(_ result: SummonResult, side: CGFloat, colour: Color) -> some View {
        if let spent = scrollShown(for: result), ItemArt.hasPainting(ItemArt.key(scroll: spent)) {
            ItemIcon(key: ItemArt.key(scroll: spent), size: side, glow: false)
                // The painted scrolls carry a ragged rim of their sheet's
                // dark ground; the summon room's feathered capsule along the
                // roll's diagonal lets it go (`SummoningCircle`).
                .mask {
                    Capsule()
                        .frame(width: side * 1.34, height: side * 0.44)
                        .rotationEffect(.degrees(-45))
                        .blur(radius: side * 0.025)
                }
        } else if let spent = scrollShown(for: result) {
            Image(systemName: spent.glyph)
                .font(.system(size: side * 0.4, weight: .black))
                .foregroundStyle(colour)
        } else {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white, colour.opacity(0.8), colour.opacity(0)],
                    center: .center, startRadius: 0, endRadius: side * 0.45
                ))
                .frame(width: side * 0.9, height: side * 0.9)
        }
    }

    /// The scroll to draw: the one the caller named, else the one the result
    /// must have come from (light and dark only from the Light & Dark
    /// scroll, a featured unit from a pantheon's banner), and none for an
    /// awakening, which spends no scroll.
    private func scrollShown(for result: SummonResult) -> ScrollType? {
        if result.isAwakening { return nil }
        if let scroll { return scroll }
        switch result.blueprint.element {
        case .radiance, .umbra: return .lightDark
        default: return result.isFeatured ? .pantheonic : .mystical
        }
    }

    /// How far up the beam a mote is, 0 at the floor to 1 at the top:
    /// `travel` beam-heights risen (`ChargeLook.moteTravel`), each mote a
    /// golden-ratio step behind the one before. Read off the distance risen
    /// rather than a clock times a speed, so a rung that quickens the motes
    /// does not jump them (2026-09-24).
    private static func moteRise(_ mote: Int, travel: Double) -> CGFloat {
        let phase: Double = Double(mote) * 0.618
        return CGFloat((travel + phase).truncatingRemainder(dividingBy: 1))
    }

    private static func motePoint(_ mote: Int, travel: Double, clock: TimeInterval,
                                  x: CGFloat, feet: CGFloat, spread: CGFloat) -> CGPoint {
        let rise: CGFloat = moteRise(mote, travel: travel)
        let sway: CGFloat = CGFloat(sin(Double(mote) * 2.3 + clock * 1.9))
        return CGPoint(x: x + sway * spread * 0.8, y: feet - rise * feet * 0.85)
    }

    /// A mote of light: one soft falloff, white at its heart through the
    /// ladder's light to nothing (run 221: a hard white dot on a flat disc
    /// of colour read as a bullet, not as light), lit once the ladder has
    /// reached it.
    private func chargeMote(_ mote: Int, look: ChargeLook) -> some View {
        let rise: CGFloat = Self.moteRise(mote, travel: look.moteTravel)
        let dot: CGFloat = 3 + 2 * look.grand + CGFloat(mote % 3)
        let lit: CGFloat = min(1, max(0, look.moteLevel - CGFloat(mote)))
        let fade: CGFloat = min(1, rise * 5) * (1 - rise) * lit
        return Circle()
            .fill(RadialGradient(
                colors: [look.core, look.light.opacity(0.7), look.light.opacity(0)],
                center: .center, startRadius: 0, endRadius: dot * 1.3
            ))
            .frame(width: dot * 2.6, height: dot * 2.6)
            .opacity(Double(fade))
    }

    /// `-tour-reveal-hold charge[:F]` (DEBUG only): the charge plays and
    /// never lands, its gathering held at F of its span, so the CI can
    /// photograph a rung whatever second it shoots. `charge` alone holds at
    /// 0.7, as the flag always did; since 2026-09-24 `charge:0.8` holds a
    /// 5★'s charge (1.4 s) at 1.12 s, on the gold rung with its lightning,
    /// and `charge:0.5` at 0.7 s, on the violet one. Nil without the flag.
    private static let chargeHold: Double? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-reveal-hold"), at + 1 < args.count else { return nil }
        let value: String = args[at + 1]
        guard value == "charge" || value.hasPrefix("charge:") else { return nil }
        let asked: Double? = Double(String(value.dropFirst("charge:".count)))
        return min(1, max(0, asked ?? 0.7))
        #else
        return nil
        #endif
    }()

    // MARK: - One at a time

    /// Landscape: the stage fills the frame with the figure on the left, and
    /// the name card (`RevealNameCard`, Docs/FEEL.md W2.13) stands in the
    /// right 45% of the screen, its left edge at 55% of the width wherever
    /// the phone's safe area falls, clear of the figure on its 26% line.
    /// Read off the whole screen (`ignoresSafeArea`), so the column is the
    /// same share of the glass on every phone.
    private func single(_ result: SummonResult) -> some View {
        GeometryReader { frame in
            let size: CGSize = frame.size
            let insets: EdgeInsets = frame.safeAreaInsets
            let left: CGFloat = size.width * RevealNameCard.clearOfFigure
            let right: CGFloat = size.width - insets.trailing - RevealNameCard.trailingMargin
            let column: CGFloat = min(RevealNameCard.widest, max(RevealNameCard.narrowest, right - left))
            let hintY: CGFloat = size.height - max(insets.bottom, 8) - 22
            ZStack(alignment: .topLeading) {
                Color.clear
                RevealNameCard(result: result, beat: cardBeat, timing: cardTiming)
                    .frame(width: column, alignment: .leading)
                    .id(index)
                    .position(x: right - column / 2, y: size.height * 0.47)
                // On a glass plate over the lit floor of the set: bare text
                // there read as a caption lost on the stone (runs 217–221).
                Text(index + 1 < results.count ? "Tap to continue  (\(index + 1)/\(results.count))" : "Tap to finish")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.onGlass)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(GlassPlate(radius: 12))
                    .opacity(isFullyRevealed ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: isFullyRevealed)
                    .position(x: size.width / 2, y: hintY)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    // MARK: - Sequencing

    private func advance() {
        if !isFullyRevealed {
            guard let current else { return }
            // A tap during a 5★'s charge jumps to its flash, never past it
            // (Docs/FEEL.md W2.23): the one pull a thumb must not swallow.
            if !revealed && current.stars >= 5 {
                landNow()
                return
            }
            // Any other tap mid-sequence finishes it now rather than being
            // ignored.
            sequence += 1
            completeInstantly(current)
            return
        }
        AudioLibrary.shared.play(.uiTap)
        if index + 1 < results.count {
            index += 1
            revealNext()
        } else if results.count > 1 {
            enterGrid()
        } else {
            onFinish()
        }
    }

    // MARK: - Skip (Docs/FEEL.md W2.23)

    /// A tap on Skip: to the flash of the pull on the beam while it is worth
    /// seeing and still charging, else on to the next pull worth seeing,
    /// else the summary (`RevealSkip.target`); Done over the summary.
    private func skipTapped() {
        if showAll {
            onFinish()
            return
        }
        switch RevealSkip.target(in: results, at: index, landed: revealed) {
        case .land:
            landNow()
        case .pull(let next):
            jump(to: next)
        case .summary:
            enterGrid()
        }
    }

    /// A hold on Skip: everything, straight to the summary.
    private func skipAll() {
        guard !showAll else { return }
        enterGrid()
    }

    /// On to pull `next`, the ones between left for the summary. Its figure
    /// starts parsing now, while the stage it replaces comes down.
    private func jump(to next: Int) {
        guard results.indices.contains(next), next != index else { return }
        let target = results[next]
        ModelLibrary.shared.warm(forms: [(spec: target.blueprint.model, awakened: target.isAwakening || target.unit.isAwakened)])
        index = next
        revealNext()
    }

    /// The pull on the beam lands now: its charge cut short at the flash,
    /// the flash and the figure's entrance played whole. A stage still
    /// building lands the moment it is ready (`beginCharge`).
    private func landNow() {
        guard let result = current, !revealed else { return }
        guard chargeStart != nil else {
            landOnReady = true
            return
        }
        sequence += 1
        land(sequence, result: result)
    }

    /// The grid of every pull, from Skip or the last pull of a ten-pull.
    /// Skip mid-charge left `charging` true (review, 2026-09-24), and the
    /// charge sky's `TimelineView` behind the grid redrew every frame for
    /// as long as it stood — at 120 Hz on ProMotion — still climbing the
    /// skipped pull's ladder to violet or gold at the grid's left. The
    /// charge, its wait for a stage and any flash end here.
    private func enterGrid() {
        sequence += 1
        charging = false
        awaitingStage = nil
        flashAt = nil
        showAll = true
        hushCharge(over: 0.2)
    }

    private func completeInstantly(_ result: SummonResult) {
        hushCharge(over: 0.15)
        charging = false
        awaitingStage = nil
        revealed = true
        arrivedFor = sequence
        namedFor = sequence
        cardTiming = RevealCardTiming.standard(stars: result.stars)
        cardBeat = .complete(sequence)
        flashAt = nil
    }

    /// Fades out what is left of a pull's sound over `fade` seconds: its
    /// charge's stems, and with `bursts` the flash's burst still ringing
    /// (Docs/FEEL.md W2.7). Nothing that is not sounding is touched.
    private func hushCharge(over fade: TimeInterval, bursts: Bool = false) {
        let sounds: [AudioLibrary.Sound] = bursts
            ? ChargeLadder.stemSounds + ChargeLadder.burstSounds
            : ChargeLadder.stemSounds
        AudioLibrary.shared.fadeOut(sounds, over: fade)
    }

    /// What is on the beam: the pull's place in the list, the family and
    /// the form. Two pulls of the same family are two stages (the index),
    /// and a re-render that hands over an equal result with a new UUID is
    /// the same stage (see `body`).
    private func stageKey(_ result: SummonResult) -> String {
        "\(index)|\(result.blueprint.id)|\(result.isAwakening || result.unit.isAwakened)"
    }

    /// The staged reveal. Every step checks it still belongs to the current
    /// sequence, so a skipped or advanced reveal cannot fire stale steps.
    ///
    /// The charge's CLOCK waits for the stage (2026-09-23). Building the set
    /// and the figure is main-thread work (1.4 s on the CI's simulator for
    /// an unparsed family), and a charge timed from `onAppear` spent that
    /// time frozen: on the next pull of a ten-pull the build ate the whole
    /// beat and the figure popped in with no anticipation at all. So the
    /// stage goes into the tree a beat after this frame (the charge's
    /// opening pose, its rings turning on the ambient clock, is what is on
    /// screen while it builds and draws itself once out of sight — see
    /// `SummonStageView.makeUIView`), tells `stageReady` when it is done,
    /// and the beat starts then; a fallback starts it anyway should that
    /// word never come.
    private func revealNext() {
        guard let result = current else { return }
        sequence += 1
        let mine = sequence
        let key = stageKey(result)
        // What is left of the last pull's sound goes: a skipped charge's
        // stems, and a burst still ringing — a 5★'s choir holds three
        // seconds in E, and under this charge's open fifth on D it clashes.
        hushCharge(over: 0.3, bursts: true)

        charging = true
        revealed = false
        cardBeat = .hidden
        arrivedFor = nil
        namedFor = nil
        landOnReady = false
        quickPull = RevealSkip.playsQuick(result, quick: RevealSkip.quickSummons)
        flashAt = nil
        ambientStart = Date()
        chargeStart = nil
        chargeDuration = ChargeLadder.span(stars: result.stars)

        // The next pull's figure parses on a background queue while this one
        // is on the beam, so its stage clones from the cache.
        if results.indices.contains(index + 1) {
            let next = results[index + 1]
            ModelLibrary.shared.warm(forms: [(spec: next.blueprint.model, awakened: next.isAwakening || next.unit.isAwakened)])
        }

        if readyStage == key {
            beginCharge(mine)
            return
        }
        awaitingStage = mine
        if mountedStage != key {
            after(0.05) {
                guard let now = current, stageKey(now) == key else { return }
                mountedStage = key
            }
        }
        // Past the stage's own give-up (`SummonStageView.warmUpLimit`, from
        // the end of its build), so this only fires for a stage that never
        // built at all.
        after(Self.stageFallback) {
            guard awaitingStage == mine else { return }
            beginCharge(mine)
        }
    }

    /// The stage has built its set and its figure and drawn them once.
    private func stageReady(_ key: String) {
        readyStage = key
        guard let waiting = awaitingStage, waiting == sequence,
              let current, stageKey(current) == key else { return }
        beginCharge(waiting)
    }

    /// The figure has been DRAWN on the beam: the card arrives on it now.
    private func stageShown(_ key: String, plan: RevealEntrancePlan) {
        guard revealed, let current, stageKey(current) == key else { return }
        cardArrives(sequence, plan: plan)
    }

    /// The figure's victory clip has reached its high point, on the scene's
    /// own clock (`SummonStageView.Coordinator.apexReached`): the name
    /// slams now.
    private func stageApex(_ key: String) {
        guard revealed, let current, stageKey(current) == key else { return }
        nameLands(sequence)
    }

    /// Starts the charge's clock, and at its end the flash and the figure.
    /// The words wait for the figure (`stageShown`), never for a timer
    /// started here: run 221 timed them from this moment, a main thread
    /// held up behind the stage let every timer fire at once — all five
    /// star ticks inside 70 ms — and the 3-second frame was the name card
    /// over an empty dais.
    ///
    /// The charge SOUNDS (Docs/FEEL.md W2.7) are three stems on the ladder's
    /// own rungs: the base under every pull from its first frame, the rise
    /// (a timpani roll and a cymbal) from the violet rung for a 4★ or
    /// better, the tell (the key lifting, a bell, a choir) from the gold
    /// rung for a 5★ alone — each read off the pull's own stars, never
    /// anything looser, and none of them louder for a better pull before
    /// its rung. The Light & Dark scroll adds its bell tree and choir from
    /// the first frame, read off the scroll SPENT (never off the result's
    /// element, which would tell the pull).
    private func beginCharge(_ mine: Int) {
        guard mine == sequence, let result = current else { return }
        awaitingStage = nil
        chargeStart = Date()
        // A Quick 3★, or a 5★ tapped while its stage was still building,
        // goes straight to the flash.
        if quickPull || landOnReady {
            landOnReady = false
            land(mine, result: result)
            return
        }
        let chargeTime = ChargeLadder.span(stars: result.stars)

        // The stems that start with the charge: the same for every grade.
        for stem in ChargeLadder.stems(stars: result.stars, scroll: scroll) where stem.at <= 0 {
            AudioLibrary.shared.play(stem.sound, volume: stem.volume)
        }
        let held: TimeInterval? = Self.chargeHold.map { chargeTime * $0 }
        scheduleRungs(result, mine: mine, until: held)
        scheduleTourSkip(mine)
        if held != nil { return }

        after(chargeTime) {
            land(mine, result: result)
        }
    }

    /// The flash: the charge ends, the figure is on the beam under a white
    /// that clears on the wall clock, and the grade's burst sounds — a chime
    /// for a 3★, a brass stab for a 4★, a gong under a choir for a 5★
    /// (Docs/FEEL.md W2.7). An awakening's reveal sounds its grade's burst
    /// too: its own rite rang at the altar's pillar before the reveal.
    private func land(_ mine: Int, result: SummonResult) {
        guard mine == sequence else { return }
        charging = false
        awaitingStage = nil
        let big = result.stars >= 4
        let stamp = Date()
        let span: TimeInterval = quickPull ? RevealSkip.quickFlash : (big ? 0.55 : 0.4)
        flashSpan = span
        flashAt = stamp
        revealed = true
        // The charge gives way to the burst: its stems fade out over 50 ms
        // and the burst sounds 40 ms after the flash on the audio clock, so
        // it lands on its own and the sum never clips (`ChargeLadder`).
        AudioLibrary.shared.fadeOut(ChargeLadder.stemSounds, over: ChargeLadder.stemFade)
        AudioLibrary.shared.schedule(
            AudioLibrary.Sound.burst(forStars: result.stars),
            volume: quickPull ? ChargeLadder.quickBurstVolume : 1,
            in: ChargeLadder.burstLead
        )
        Juice.haptic(big ? .heavy : .medium)
        // Off the screen once it has faded, so nothing redraws it.
        after(span + 0.1) {
            if flashAt == stamp { flashAt = nil }
        }
        // Should the stage never say its figure has drawn, the card lands
        // anyway rather than never.
        after(Self.wordsFallback) { cardArrives(mine, plan: nil) }
    }

    /// The card arrives with the figure's first drawn frame (or the
    /// fallback), once per sequence: the plaque slides in, the crest pops,
    /// and the stars stamp in one by one, each on the next note of the
    /// glockenspiel's climb. The name waits for the clip's high point
    /// (`stageApex`), with a fallback past it should that never come; a
    /// Quick 3★ does not wait for the pose.
    private func cardArrives(_ mine: Int, plan: RevealEntrancePlan?) {
        guard mine == sequence, arrivedFor != mine, let result = current else { return }
        arrivedFor = mine
        let timing: RevealCardTiming = quickPull
            ? RevealCardTiming.quick(stars: result.stars)
            : RevealCardTiming.standard(stars: result.stars)
        cardTiming = timing
        cardBeat = .arrived(mine)
        scheduleStarTicks(result, timing: timing, mine: mine)
        if quickPull {
            after(Self.quickName) { nameLands(mine) }
        } else {
            let apex: TimeInterval = plan?.apexDelay ?? RevealEntrance.defaultApex
            after(apex + Self.apexFallback) { nameLands(mine) }
        }
    }

    /// The name slams onto the card, the details follow: once per sequence,
    /// on the clip's high point or its fallback.
    private func nameLands(_ mine: Int) {
        guard mine == sequence, namedFor != mine, let result = current else { return }
        if arrivedFor != mine {
            cardArrives(mine, plan: nil)
        }
        namedFor = mine
        cardBeat = .named(mine)
        Juice.haptic(result.stars >= 4 ? .heavy : .medium)
        #if DEBUG
        if RevealEntrance.touring { print("[TourCue] reveal-named \(result.blueprint.id)") }
        #endif
    }

    /// The stars' ticks: each star lands on the next note of the
    /// glockenspiel's scale (`AudioLibrary.Sound.star`), a light touch each
    /// and a firmer one on a 4★'s or 5★'s last. Side effects, so timers
    /// like the flash's, silenced by a skip or the next pull.
    private func scheduleStarTicks(_ result: SummonResult, timing: RevealCardTiming, mine: Int) {
        let stars: Int = max(1, result.stars)
        let big: Bool = stars >= 4
        let volume: Float = ChargeLadder.starVolume(stars: stars)
        for i in 0..<stars {
            after(timing.landing(i)) {
                guard mine == sequence else { return }
                AudioLibrary.shared.play(AudioLibrary.Sound.star(i), volume: volume)
                Juice.haptic(i == stars - 1 && big ? .medium : .light)
            }
        }
    }

    /// The rungs' stems and touch, each once, at the second the charge's
    /// picture climbs it (`ChargeLadder`): at violet the rise (a timpani
    /// roll swelling under a cymbal) and a medium tap, at gold the tell (a
    /// bell, the choir swelling in the lifted key, the lightning's crackle)
    /// and a heavy one. The picture is a pure function of the clock; these
    /// are the side effects, so they are timers like the flash, and a skip
    /// or the next pull (`sequence`) silences one still waiting. A held
    /// charge (the CI) sounds only the rungs before its hold.
    private func scheduleRungs(_ result: SummonResult, mine: Int, until hold: TimeInterval?) {
        let limit: TimeInterval = hold ?? .infinity
        for stem in ChargeLadder.stems(stars: result.stars, scroll: scroll) where stem.at > 0 && stem.at <= limit {
            after(stem.at) {
                guard mine == sequence else { return }
                AudioLibrary.shared.play(stem.sound, volume: stem.volume)
                if let touch = stem.touch { Juice.haptic(touch) }
            }
        }
    }

    /// `-tour-reveal-skip` (DEBUG, the CI's frame of a Skip that could not
    /// swallow a 5★): Skip is pressed once, half a second into the first
    /// pull's charge, as a thumb would press it.
    private func scheduleTourSkip(_ mine: Int) {
        #if DEBUG
        guard Self.tourAutoSkip, !tourSkipped else { return }
        tourSkipped = true
        after(0.5) {
            guard mine == sequence else { return }
            let target = RevealSkip.target(in: results, at: index, landed: revealed)
            print("[TourCue] reveal-skip \(target)")
            skipTapped()
        }
        #endif
    }

    /// Whether the CI presses Skip once (`scheduleTourSkip`).
    private static let tourAutoSkip: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-tour-reveal-skip")
        #else
        return false
        #endif
    }()

    /// A Quick 3★'s name, not waiting for the pose.
    private static let quickName: TimeInterval = 0.22

    /// How long past the clip's expected high point the name lands should
    /// the stage never report it.
    private static let apexFallback: TimeInterval = 0.6

    /// How long a pull waits on a stage that never reports before its charge
    /// starts anyway: past the stage's build and its own warm-up limit.
    private static let stageFallback: TimeInterval = 6.5

    /// How long after the flash the words land if the figure never reports
    /// its first frame.
    private static let wordsFallback: TimeInterval = 2.5

    private func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 12) {
            // Carved gold on the dusk the grid stands on; the ink it was set
            // in vanished against the sky.
            Text("Summoned")
                .font(Theme.display(30))
                .carved()

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(results) { result in
                        gridTile(result)
                    }
                }
                .padding(.horizontal, 16)
            }

            PrimaryButton(title: "Continue", action: onFinish)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .padding(.top, 50)
    }

    private func gridTile(_ result: SummonResult) -> some View {
        let rarity = Rarity(stars: result.stars)
        return VStack(spacing: 4) {
            ZStack {
                if BundleImage.exists(result.blueprint.model.portraitName(awakened: result.unit.isAwakened || result.isAwakening)) {
                    // Decoded at the tile's 74 points, not the card's 1024
                    // pixels: a full decode is 4 MB a tile (2026-09-24).
                    BundleImage(name: result.blueprint.model.portraitName(awakened: result.unit.isAwakened || result.isAwakening), renderedAt: 74)
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: Theme.tightCorner)
                        .fill(
                            LinearGradient(
                                colors: [tint(for: result).opacity(0.5), Theme.surface],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    Text(String(result.blueprint.name.prefix(1)))
                        .font(Theme.display(30))
                        .foregroundStyle(Theme.textPrimary)
                }
                if result.isNew {
                    Text("NEW")
                        .font(Theme.body(7).weight(.black))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                } else if let skillUp = result.skillUp {
                    SummonDuplicateChip(skillUp: skillUp)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                }
            }
            .frame(width: 74, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            .overlay(
                Group {
                    if let frame = Chrome.image(rarity.frameImageName) {
                        Image(uiImage: frame).resizable()
                    }
                }
            )
            .shadow(color: rarity.glow.opacity(rarity.glowRadius > 0 ? 0.7 : 0), radius: rarity.glowRadius)

            StarRow(stars: result.stars, size: 8)
            // Two lines, never an ellipsis: "The Unwrapped King" is wider
            // than a 74-point tile.
            Text(result.blueprint.name)
                .font(Theme.body(11))
                .foregroundStyle(Self.duskInk)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A duplicate's chip on a summon tile (2026-09-24): what the copy did, in
/// a word or two — a skill-up it really made, or that the kit is capped
/// (`SummonSkillUp`). The ten-pull summary of the next wave wears the same
/// chip beside NEW.
struct SummonDuplicateChip: View {
    let skillUp: SummonSkillUp

    var body: some View {
        Text(label)
            .font(Theme.body(11).weight(.black))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(chipGround)
            .foregroundStyle(ink)
            .fixedSize()
    }

    private var label: String {
        switch skillUp {
        case .levelled(_, let from, let to):
            let rise: Int = to - from
            return "SKILL +\(rise)"
        case .maxed:
            return "MAXED"
        }
    }

    /// Gold ink on dark glass for a skill-up; cream on the deep gold for a
    /// capped kit, the Regalia's metal.
    @ViewBuilder
    private var chipGround: some View {
        switch skillUp {
        case .levelled: Capsule().fill(Theme.glass)
        case .maxed: Capsule().fill(Theme.goldDeep)
        }
    }

    private var ink: Color {
        switch skillUp {
        case .levelled: return Theme.onGlassGold
        case .maxed: return Theme.onGlass
        }
    }
}

/// A tiny SceneKit stage that drops the summoned unit in on a beam.
///
/// It reuses `ModelLibrary`, so it shows the real model the moment one exists
/// and the portrait sprite or placeholder rig until then.
struct SummonStageView: UIViewRepresentable {
    let result: SummonResult
    /// Flips true when the charge ends; the figure appears on the beam then.
    var revealed: Bool = true
    /// Called once, on the main queue, when the set and the figure are built
    /// AND have been drawn once out of sight (the warm-up, `makeUIView`): the
    /// reveal starts its charge's clock from here, not from `onAppear`.
    var onReady: (() -> Void)? = nil
    /// Called once, on the main queue, after the first frame that DREW the
    /// figure on the beam, with the entrance's plan: the reveal times its
    /// card's stars from here, so they can never land on an empty dais.
    var onShown: ((RevealEntrancePlan) -> Void)? = nil
    /// Called once, on the main queue, when the figure's victory clip
    /// reaches its high point on the scene's own clock (Docs/FEEL.md W2.4):
    /// the reveal slams the name down on it.
    var onApex: (() -> Void)? = nil

    /// Where the figure's centre line stands, as a fraction of the width
    /// from the left: the camera is solved for it (`frameCamera`) and the
    /// reveal's SwiftUI charge is drawn on it.
    static let figureLine: CGFloat = 0.26

    /// How long, from the end of the build, the stage waits for its warm-up
    /// to be drawn before it comes in anyway. The CI's simulator compiled
    /// this set and figure in about two and a half seconds; a phone takes a
    /// fraction of one.
    static let warmUpLimit: TimeInterval = 4.0

    // MARK: Figure-first light (2026-09-24, Docs/FEEL.md L1)
    //
    // Principle 1 of the genre, measured on the owner's Summoners War
    // frames: the figure is the most coloured, best-separated thing on the
    // screen, and the set is quiet stone. Ours was the other way round on
    // this stage — the lit columns outshone the god. So the reveal has two
    // light layers. A node is lit by a light only when their category masks
    // share a bit, and a category is NOT inherited, so every node of both
    // is marked (`markFigure`, `separateTheSet`).

    /// The figure's light category, and the temple's.
    static let figureCategory: Int = 2
    static let setCategory: Int = 4
    /// A figure light's mask: the figure's layer and SceneKit's default
    /// category (1), so anything added to the figure unmarked is still lit
    /// as the figure is.
    static let figureLights: Int = figureCategory | 1
    /// The temple's key, as a share of the figure's.
    static let templeKeyShare: CGFloat = 0.6
    /// How far a brazier's fire reaches, in metres: 6 before, which carried
    /// it 3.6 m to the figure; 3 keeps it on the pillars beside it.
    static let brazierReach: CGFloat = 3
    /// The house's dim after the flash: a third of a stop, 2^(-1/3), in
    /// linear light.
    static let houseDim: Double = 0.7937
    /// It begins as the flash starts to clear and eases over most of a
    /// second, under the push-in and the first stars.
    static let dimDelay: TimeInterval = 0.3
    static let dimDuration: TimeInterval = 0.9
    /// A prop's paint and its white rim on this stage (`tuneSetMaterial`):
    /// the set at 0.80 of its saturation while the figure keeps its whole
    /// paint, and the rim `StageBuilder.loadProp` gives a prop (0.18) cut to
    /// under the figure's own 0.12.
    static let setSaturation: Double = 0.80
    static let propRim: Double = 0.06

    /// `-tour-layers off` (DEBUG, the CI lab): the reveal lit as it was
    /// before 2026-09-24 — one rig for the figure and the temple, the
    /// braziers at 6 m, no dim — photographed beside the layered rig every
    /// run (`5-reveal-awakened-layers-off`).
    static var layersOff: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-layers"), at + 1 < args.count else { return false }
        return args[at + 1] == "off"
        #else
        return false
        #endif
    }

    /// Every node of the figure in the figure's layer. Called as it is built
    /// and again at the flash: a category is not inherited, so a node the
    /// model gains later must be marked as well.
    static func markFigure(_ figure: SCNNode) {
        figure.enumerateHierarchy { node, _ in
            node.categoryBitMask = figureCategory
        }
    }

    /// The temple as a light layer of its own: every node under the
    /// summoning circle's `stage` in the set's category, its braziers
    /// lighting only the set and reaching `brazierReach`, and its lit
    /// materials the stage's OWN — returned with the colour each takes when
    /// the house goes down (`Coordinator.dimTheHouse`).
    ///
    /// Own copies, because a prop is a clone of `StageBuilder.propCache`'s
    /// and shares its geometry and materials with every battle that stands
    /// it: dimmed or re-tuned in place, the columns of the next fight would
    /// be dimmed too. A copied geometry shares its vertex data, so a copy
    /// costs a few material records, freed with the stage. A brazier's light
    /// is copied as well before it is changed, for the same reason; its
    /// flicker sets whichever light its node carries.
    static func separateTheSet(in scene: SCNScene) -> [RevealHouseMaterial] {
        guard let stage = scene.rootNode.childNode(withName: "stage", recursively: false) else { return [] }
        var house: [RevealHouseMaterial] = []
        stage.enumerateHierarchy { node, _ in
            node.categoryBitMask = setCategory
            if let shared = node.light, let light = shared.copy() as? SCNLight {
                light.categoryBitMask = setCategory
                if light.type == .omni {
                    light.attenuationEndDistance = brazierReach
                }
                node.light = light
            }
            guard let geometry = node.geometry, let own = geometry.copy() as? SCNGeometry else { return }
            var materials: [SCNMaterial] = []
            for shared in geometry.materials {
                guard let material = shared.copy() as? SCNMaterial else {
                    materials.append(shared)
                    continue
                }
                materials.append(material)
                if material.shaderModifiers?[.fragment] != nil {
                    tuneSetMaterial(material)
                }
                if let dimmed = houseDimmed(material) {
                    house.append(RevealHouseMaterial(material: material, dimmed: dimmed))
                    holdMultiplyStage(material)
                }
            }
            own.materials = materials
            node.geometry = own
        }
        return house
    }

    /// A prop's own copy in the set's paint and rim. The uniforms
    /// `MaterialTuner.tune` binds are bound again by value, as `tune` binds
    /// them — a prop is never tinted — so the copy renders as the shared
    /// material did whatever `copy()` keeps of them; then the two the set
    /// changes.
    private static func tuneSetMaterial(_ material: SCNMaterial) {
        let metalMap: Bool = material.metalness.contents != nil && !(material.metalness.contents is NSNumber)
        material.setValue(NSNumber(value: Float(metalMap ? 1 : 0)), forKey: "hasMetalMap")
        material.setValue(NSNumber(value: Float(FigureStageLighting.metalShine ? 1 : 0)), forKey: "metalShine")
        material.setValue(NSNumber(value: Float(0)), forKey: "costumeHue")
        material.setValue(NSNumber(value: Float(0)), forKey: "costumeSaturation")
        material.setValue(NSNumber(value: Float(0)), forKey: "costumeMix")
        material.setValue(NSNumber(value: Float(45.0 / 360.0)), forKey: "costumeSourceHue")
        material.setValue(NSNumber(value: Float(32.0 / 360.0)), forKey: "costumeBand")
        material.setValue(NSNumber(value: Float(0)), forKey: "costumeGlow")
        material.setValue(NSValue(scnVector3: SCNVector3(1, 1, 1)), forKey: "rimColor")
        material.setValue(NSNumber(value: Float(MaterialTuner.rimPower)), forKey: "rimPower")
        material.setValue(NSNumber(value: Float(setSaturation)), forKey: "paintSaturation")
        material.setValue(NSNumber(value: Float(propRim)), forKey: "rimStrength")
    }

    /// The colour a set material's `multiply` takes when the house goes
    /// down: what it multiplies by now (white, or the floor's tint) a third
    /// of a stop darker in linear light. Nil for what is not lit — a
    /// constant material is a light of its own (the rune ring, the mist)
    /// and keeps its brightness — and for a multiply that is a picture.
    private static func houseDimmed(_ material: SCNMaterial) -> UIColor? {
        guard material.lightingModel != .constant else { return nil }
        let now: UIColor
        if let colour = material.multiply.contents as? UIColor {
            now = colour
        } else if material.multiply.contents == nil {
            now = .white
        } else {
            return nil
        }
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        guard now.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return UIColor(red: darkened(red), green: darkened(green), blue: darkened(blue), alpha: alpha)
    }

    /// A multiply left white becomes a white SceneKit can see (0.999, which
    /// no frame can), so the set's shaders carry their multiply stage from
    /// the build and the warm-up compiles them with it. A material property
    /// at its default may be left out of the shader SceneKit generates, and
    /// the dim would then add it at the flash — a compile on the very beat
    /// the warm-up exists to keep clear (run 221's 21 compiles).
    private static func holdMultiplyStage(_ material: SCNMaterial) {
        let now: UIColor? = material.multiply.contents as? UIColor
        guard material.multiply.contents == nil || now.map(isWhite) == true else { return }
        material.multiply.contents = UIColor(white: 0.999, alpha: 1)
    }

    private static func isWhite(_ colour: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        let least: CGFloat = min(red, min(green, blue))
        return least >= 0.999
    }

    /// One sRGB component, `houseDim` darker in linear light.
    private static func darkened(_ value: CGFloat) -> CGFloat {
        let encoded: Double = Double(min(1, max(0, value)))
        let linear: Double = encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        let dimmed: Double = linear * houseDim
        let back: Double = dimmed <= 0.0031308 ? dimmed * 12.92 : 1.055 * pow(dimmed, 1 / 2.4) - 0.055
        return CGFloat(back)
    }

    /// The stage's state, and its render delegate (the view holds its
    /// delegate weakly; SwiftUI holds this): it steps the cape, runs the
    /// warm-up and reports the figure's first frame on the beam. The render
    /// thread only reads the figure and sends work to the main queue; every
    /// change to the scene or to the reveal is made there.
    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var figure: SCNNode?
        /// Steps the figure's cape each frame, from this delegate.
        let cloth = ClothStepper()
        var spinnerStarted = false
        var tint: UIColor = .white
        var scene: SCNScene?
        /// The contact shadow under the feet: built with the set, drawn in
        /// the warm-up, faded in by `show`.
        var contactShadow: SCNNode?
        /// The summon beam's column, drawn in the warm-up only
        /// (`warmBeamTwin`).
        var warmBeam: SCNNode?
        weak var view: SCNView?
        var onReady: (() -> Void)?
        var onShown: ((RevealEntrancePlan) -> Void)?
        var onApex: (() -> Void)?
        /// The entrance (Docs/FEEL.md W2.4): the victory clip wrapped in its
        /// player in `makeUIView`, the pull's grade (the hold's length), the
        /// flipbook planes on the dais, and the rig the camera kicks on.
        var entrance: RevealEntranceClip?
        var stars = 3
        var flipbook: RevealFlipbookPlayer?
        var cameraRig: SCNNode?
        /// Where the slow push-in ends: the camera waits pulled back through
        /// the entrance, so a victory's raised arms stay in the frame, and
        /// pushes in once the figure settles into its idle (`startPush`).
        var pushHome: SCNVector3?
        /// The main queue's alone: the hold in progress, and the stage has
        /// begun to come down (`beginTeardown`).
        private var holdGeneration = 0
        private var tornDown = false
        /// The camera and the three numbers its framing was solved from, kept
        /// so the push-in on the reveal and a re-frame after a layout can both
        /// work from the same solve rather than each guessing at it.
        var cameraNode: SCNNode?
        var visibleHeight: Float = 0
        var distance: Float = 0
        var aimY: Float = 0
        var cameraY: Float = 0
        /// The viewport shape the camera was last placed for. Only the
        /// horizontal half of the framing depends on it, and re-solving on
        /// every SwiftUI update would fight the push-in, so it is re-applied
        /// only when the shape actually changes.
        var framedAspect: Float = 0
        /// The set's own copies of its lit materials and the colour each
        /// one's `multiply` takes when the house goes down after the flash
        /// (`dimTheHouse`, `SummonStageView.separateTheSet`); empty under
        /// `-tour-layers off`.
        var houseMaterials: [RevealHouseMaterial] = []
        /// The main queue's alone: the house has gone down.
        private var houseDown = false

        /// Read and written on the render thread and the main one, so only
        /// under `lock`.
        private let lock = NSLock()
        private var phase: RevealStageWarmUp = .drawing
        private var framesDrawn = 0
        private var onStage = false
        private var shownReported = false
        /// The main queue's alone.
        private var readied = false

        /// Whether `show` has put the figure on the beam.
        var shown: Bool {
            lock.lock()
            defer { lock.unlock() }
            return onStage
        }

        func markShown() {
            lock.lock()
            onStage = true
            lock.unlock()
        }

        func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
            cloth.renderer(renderer, didApplyAnimationsAtTime: time)
        }

        /// The render thread's half of the warm-up and of the figure's first
        /// frame on the beam: a frame has just been drawn, and what it drew
        /// is the presentation tree.
        func renderer(_ renderer: SCNSceneRenderer, didRenderScene rendered: SCNScene, atTime time: TimeInterval) {
            guard let figure else { return }
            let opacity = figure.presentation.opacity
            lock.lock()
            switch phase {
            case .drawing:
                // The first frame compiles every shader it needs; the second
                // is drawn with all of them in hand.
                framesDrawn += 1
                let drawn = framesDrawn >= 2
                if drawn { phase = .drawn }
                lock.unlock()
                if drawn {
                    DispatchQueue.main.async { [weak self] in self?.clearWarmUp() }
                }
            case .drawn:
                lock.unlock()
            case .clearing:
                let clear = onStage || opacity < 0.01
                if clear { phase = .ready }
                lock.unlock()
                if clear {
                    DispatchQueue.main.async { [weak self] in self?.finishWarmUp() }
                }
            case .ready:
                let first = onStage && !shownReported && opacity > 0.5
                if first { shownReported = true }
                lock.unlock()
                if first {
                    DispatchQueue.main.async { [weak self] in self?.figureShown() }
                }
            }
        }

        /// The warm-up has been drawn: whatever waits for the flash goes back
        /// out of sight — unless the reveal has asked for it already — and
        /// the stage waits for a frame drawn that way before it comes in.
        func clearWarmUp() {
            lock.lock()
            guard phase == .drawn else {
                lock.unlock()
                return
            }
            let keep = onStage
            lock.unlock()
            // The twin carries no particles, so it can go at once (a host
            // taken down while its motes lived crashed the fight twice).
            warmBeam?.removeFromParentNode()
            warmBeam = nil
            if !keep {
                figure?.opacity = 0
                contactShadow?.opacity = 0
            }
            // The entrance's flipbook planes were drawn at full strength for
            // the warm-up; out of sight until their frames play.
            if flipbook?.hasStarted != true {
                flipbook?.hideAll()
            }
            lock.lock()
            phase = .clearing
            lock.unlock()
        }

        /// The stage is drawn with nothing on the beam: it comes in over the
        /// charge, and the reveal starts the charge's clock.
        func finishWarmUp() {
            guard !readied else { return }
            readied = true
            if let view {
                UIView.animate(withDuration: 0.25) { view.alpha = 1 }
            }
            onReady?()
        }

        /// A warm-up that has not reported in `warmUpLimit` (a view that is
        /// not drawing) is cleared and the stage comes in anyway.
        func giveUpWarmUp() {
            lock.lock()
            if phase == .drawing { phase = .drawn }
            lock.unlock()
            clearWarmUp()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.finishWarmUp()
            }
        }

        /// The first frame with the figure on the beam: the reveal's card is
        /// timed from here. A figure with no entrance settles toward the
        /// player from here too; one with an entrance turns once its victory
        /// has handed back to its idle (`entranceDone`).
        func figureShown() {
            if entrance == nil, let figure { SummonStageView.settle(figure) }
            onShown?(entrancePlan)
        }

        /// What the reveal's card is told: how long from this frame until
        /// the clip's high point.
        var entrancePlan: RevealEntrancePlan {
            let hold: TimeInterval = RevealEntrance.hold(stars: stars)
            guard let entrance else {
                return RevealEntrancePlan(apexDelay: hold + RevealEntrance.defaultApex, plays: false)
            }
            return RevealEntrancePlan(apexDelay: hold + entrance.apexIn, plays: true)
        }

        // MARK: The entrance (Docs/FEEL.md W2.4)

        /// The flash: the scene HOLDS — every clip, particle and action
        /// stopped under the white, the fight's own freeze (`Juice.impact`)
        /// — for 70 ms, 110 ms for a 5★, and then the entrance goes. The
        /// view keeps drawing through the hold, so the figure's first frame
        /// is still reported (`figureShown`) and the card arrives under the
        /// flash.
        func beginEntrance() {
            guard !tornDown, let scene else { return }
            holdGeneration += 1
            let generation = holdGeneration
            scene.isPaused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + RevealEntrance.hold(stars: stars)) { [weak self] in
                self?.releaseHold(generation)
            }
        }

        /// The hold lets go: the victory clip plays from its cut, the camera
        /// kicks, the flipbooks play, and the clip's own clock — an action
        /// on the figure, which runs and pauses with the scene exactly as
        /// the clip does — reports its high point, its end and its hand-back
        /// to the idle. A figure with no clip gets the high point at the
        /// flash's clearing and pushes in at once.
        private func releaseHold(_ generation: Int) {
            guard generation == holdGeneration, !tornDown, let scene, let figure else { return }
            scene.isPaused = false
            kickCamera()
            flipbook?.start()
            guard let entrance else {
                figure.runAction(.sequence([
                    .wait(duration: RevealEntrance.defaultApex),
                    .run { [weak self] _ in
                        DispatchQueue.main.async { self?.apexReached() }
                    },
                ]), forKey: RevealEntrance.clockKey)
                startPush()
                return
            }
            // Into the live scene first, then the player, then `play()`: the
            // one order SceneKit starts a clip in (`SCNNode.startLoop`).
            figure.addAnimationPlayer(entrance.player, forKey: RevealEntrance.playerKey)
            entrance.player.play()
            let apexIn: TimeInterval = entrance.apexIn
            let endIn: TimeInterval = entrance.endIn
            let tail: TimeInterval = max(0, endIn - apexIn)
            figure.runAction(.sequence([
                .wait(duration: apexIn),
                .run { [weak self] _ in
                    DispatchQueue.main.async { self?.apexReached() }
                },
                .wait(duration: tail),
                .run { [weak self] _ in
                    DispatchQueue.main.async { self?.entranceEnding() }
                },
                .wait(duration: RevealEntrance.blendOut),
                .run { [weak self] _ in
                    DispatchQueue.main.async { self?.entranceDone() }
                },
            ]), forKey: RevealEntrance.clockKey)
        }

        /// The clip's high point: the reveal slams the name down. Under the
        /// CI's `-tour-reveal-hold apex` the scene stops here for good, the
        /// frames of the flipbooks with it.
        func apexReached() {
            guard !tornDown else { return }
            if RevealEntrance.touring { print("[TourCue] reveal-apex") }
            if RevealEntrance.tourHoldsAtApex {
                scene?.isPaused = true
                flipbook?.freeze()
            }
            onApex?()
        }

        /// The window of the clip is over: it blends back into the idle,
        /// which has run under it all along.
        private func entranceEnding() {
            guard !tornDown else { return }
            entrance?.player.stop(withBlendOutDuration: RevealEntrance.blendOut)
        }

        /// The idle has the figure again: the player comes off, the figure
        /// turns to face the player and breathes (`settle`), and the camera
        /// pushes in on it.
        private func entranceDone() {
            guard !tornDown, let figure else { return }
            figure.removeAnimation(forKey: RevealEntrance.playerKey)
            SummonStageView.settle(figure)
            startPush()
        }

        /// The kick: the camera's rig jumps back along the line of sight by
        /// 4% of the camera's distance in 70 ms and springs home over 0.6 s
        /// with a small overshoot. Not under Reduce Motion.
        private func kickCamera() {
            guard !MotionComfort.isReduced, let rig = cameraRig, let cameraNode else { return }
            let front = cameraNode.worldFront
            let reach: Float = distance * RevealEntrance.kickShare
            let back = SCNVector3(-front.x * reach, -front.y * reach, -front.z * reach)
            let out = SCNAction.move(to: back, duration: RevealEntrance.kickOut)
            out.timingMode = .easeOut
            let home = SCNAction.move(to: SCNVector3(0, 0, 0), duration: RevealEntrance.kickBack)
            home.timingFunction = { progress in RevealEntrance.kickReturn(progress) }
            rig.runAction(.sequence([out, home]), forKey: RevealEntrance.kickKey)
        }

        /// The slow push toward the figure, a twelfth of the distance, eased
        /// out: the shot settling on the god once its entrance is done.
        func startPush() {
            guard !tornDown, let cameraNode, let home = pushHome else { return }
            pushHome = nil
            let push = SCNAction.move(to: home, duration: 1.7)
            push.timingMode = .easeOut
            cameraNode.runAction(push, forKey: "push")
        }

        /// The stage has begun to come down (`dismantleUIView`): the hold
        /// never lets go and the flipbooks stop.
        func beginTeardown() {
            tornDown = true
            holdGeneration += 1
            flipbook?.stop()
        }

        /// THE HOUSE GOES DOWN (2026-09-24, Docs/FEEL.md L1): after the flash
        /// the set dims a further third of a stop, the way a theatre darkens
        /// its house when the curtain goes up, and the god is left the one
        /// lit thing on the stage. Done on the set's MATERIALS
        /// (`multiply`, which scales what they render after every light and
        /// the studio environment), not on its lights: the floor, the rock
        /// and the props are physically based, so the image-based light is
        /// half of what reaches them, and a scene's environment cannot be
        /// dimmed for the set without the figure. Main thread, once, over
        /// `SummonStageView.dimDuration` at SceneKit's own pacing.
        func dimTheHouse() {
            guard !houseDown, !houseMaterials.isEmpty else { return }
            houseDown = true
            SCNTransaction.begin()
            SCNTransaction.animationDuration = SummonStageView.dimDuration
            for entry in houseMaterials {
                entry.material.multiply.contents = entry.dimmed
            }
            SCNTransaction.commit()
        }

        /// Lets go of every node and the scene (`dismantleUIView`), on the
        /// main thread once the renderer has stopped.
        func release() {
            flipbook?.stop()
            flipbook = nil
            entrance = nil
            figure = nil
            scene = nil
            contactShadow = nil
            warmBeam = nil
            cameraNode = nil
            cameraRig = nil
            view = nil
            onReady = nil
            onShown = nil
            onApex = nil
            houseMaterials = []
        }

        /// One line per stage gone (2026-09-24): CI run 242's summon stress
        /// climbed about 30 MB a reveal and never came down, and this is how
        /// the next run's console says whether each reveal's stage really
        /// leaves — `[Mem] reveal stage released`, with the model cache's
        /// live clones beside the footprint. `dismantleUIView` holds this
        /// coordinator until its teardown is done, so the line is printed
        /// with the stage already gone.
        deinit {
            #if DEBUG
            MemoryProbe.log("reveal stage released")
            #endif
        }
    }

    /// The renderer's grip on the stage is let go this long after it stops,
    /// before the graph comes down: past any frame already in flight, and
    /// the settle an effect's host is given before it leaves
    /// (`VFXLibrary.retireSettle`).
    static let teardownSettle: TimeInterval = 0.5

    /// THE STAGE LEAVES WITH ITS VIEW (2026-09-24). CI run 242's memory
    /// stress took the footprint from 76 MB to 1,439 MB over thirty single
    /// summons and three ten-pulls, about 30 MB a reveal and never given
    /// back, while six battles stayed flat: the battle retires its stage,
    /// and this view had no `dismantleUIView` at all. So each reveal's
    /// scene, its figure's clone, the temple and every texture the renderer
    /// had uploaded lived as long as SwiftUI kept the old view, and a live
    /// clone pins its family's entry in the model cache (a prototype a
    /// clone came from is never evicted). SwiftUI calls this on the main
    /// thread as the view leaves.
    ///
    /// The order is the render thread's: the renderer stops FIRST, so no
    /// frame is built while the graph changes; then every particle system
    /// comes off the way an effect's host leaves the stage
    /// (`VFXLibrary.dismiss`: its systems off, hidden — a host removed while
    /// its motes lived crashed the fight twice), and every action and
    /// animation stops, the figure's idle with them; and only
    /// `teardownSettle` later do the root's children go, the view let go of
    /// its scene and the coordinator of its nodes. The cape's chain needs no
    /// reset: `ClothStepper` holds none, and `ClothSimulation` drops a chain
    /// the moment its figure is gone.
    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.beginTeardown()
        uiView.isPlaying = false
        uiView.rendersContinuously = false
        uiView.delegate = nil
        guard let root = uiView.scene?.rootNode else {
            coordinator.release()
            return
        }
        for child in root.childNodes where carriesParticles(child) {
            VFXLibrary.dismiss(child, reportsLive: false)
        }
        root.enumerateHierarchy { node, _ in
            node.removeAllActions()
            node.removeAllAnimations()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + teardownSettle) {
            for child in root.childNodes {
                child.removeFromParentNode()
            }
            uiView.scene = nil
            coordinator.release()
        }
    }

    /// Whether a node or anything under it carries a particle system.
    private static func carriesParticles(_ node: SCNNode) -> Bool {
        var found = false
        node.enumerateHierarchy { child, stop in
            guard let systems = child.particleSystems, !systems.isEmpty else { return }
            found = true
            stop.pointee = true
        }
        return found
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        // Transparent on purpose: the SwiftUI rays and the radial glow behind
        // this view are the sky, and they have to show between the pillars and
        // over the temple. The price is that this scene has no tolerance for a
        // quad that writes alpha where it means to write nothing — an additive
        // material over a painting with no alpha channel adds nothing to the
        // colour but still writes the node's opacity into the frame buffer,
        // and that prints the quad's own rectangle over the backdrop as a
        // straight-edged darkening (the translucent rectangle behind Shabti's
        // head; the cause and the fix are in `StageBuilder.mistPlanes`). The
        // rule for anything added here has two branches and the wrong one is
        // the trap. A quad that ADDS light must write no alpha at all —
        // `colorBufferWriteMask = [.red, .green, .blue]`, which is what
        // `mistPlanes` and `runeRing` now carry — and must NOT try to derive
        // an alpha channel from the painting with `transparencyMode`
        // `.rgbZero`, which reads 0.0 as opaque and so inverts art painted
        // bright on black. A quad that BLENDS, like the contact shadow at the
        // bottom of this file, needs a real alpha channel in its image
        // instead. The battle stage hides the same mistake behind a black
        // view and a backdrop painting; this one cannot.
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isPlaying = true
        view.delegate = context.coordinator
        // Sixty frames a second by default (SceneKit's own, which this view
        // always drew at), and the Settings screen's effects and shadows
        // (`Docs/SETTINGS.md` §2); the warm-up below draws whatever they leave.
        GraphicsSettings.configure(view, for: .reveal)

        let tint = UIColor(hex: result.blueprint.model.auraHex) ?? .white
        let height = result.blueprint.model.height

        let awakened = result.isAwakening || result.unit.isAwakened
        let node = ModelLibrary.shared.node(
            for: result.blueprint.model,
            archetype: result.blueprint.archetype,
            element: result.blueprint.element,
            awakened: awakened
        )
        if awakened {
            node.addParticleSystem(VFXLibrary.aura(tint: tint, scale: height / 1.9))
        }
        node.position = SCNVector3(0, 0, 0)
        // Whole for the warm-up (below), then out of sight until the flash.
        node.opacity = 1
        scene.rootNode.addChildNode(node)
        context.coordinator.figure = node
        context.coordinator.tint = tint
        context.coordinator.scene = scene
        // A canonical export's rest pose is its bind pose, an A-pose, so the
        // figure gets the idle clip when one is in the bundle and stands
        // still only when there is nothing to play.
        // The clips of the mesh on the stage (`ModelLibrary.clipAsset`): an
        // awakened figure plays its own rig's idle, never the base rig's.
        let assetName = ModelLibrary.shared.clipAsset(for: result.blueprint.model, awakened: awakened)
        if let idle = ModelLibrary.shared.animation(.idle, for: assetName)
            ?? ModelLibrary.shared.animation(.idleCombat, for: assetName) {
            node.startLoop(idle, key: "idle")
        }
        // THE ENTRANCE'S CLIP (Docs/FEEL.md W2.4): the family's victory,
        // wrapped in its player now so the flash only adds and plays it —
        // from the model cache the summon room's warm pass filled, or parsed
        // here, in the build the charge's opening pose already covers, never
        // at the flash (`RevealEntranceClip`, `RevealEntrance`).
        let entrance: RevealEntranceClip? = Self.entranceClip(for: assetName)
        context.coordinator.entrance = entrance
        context.coordinator.stars = result.stars
        if let entrance {
            let length = String(format: "%.2f", entrance.length)
            print("[Reveal] entrance: \(assetName) plays its victory as \(entrance.cut.preset) (\(length) s clip, "
                  + "\(entrance.cut.start)–\(entrance.cut.end) s, high point \(entrance.cut.apex) s)")
        }
        // The stance to open on. With a victory, the preset's own, measured
        // so the chest faces a little toward the words through the window
        // the reveal plays (`RevealEntranceCut.stance`); without one, the
        // three-quarter stance the reveal always opened on. The turn to face
        // the player waits for the entrance (see `show`), and it is no longer
        // a perpetual full spin: a 16-second revolution had the character
        // showing the player its back for four seconds out of every sixteen,
        // and a fair share of reveals put the unit's name over its shoulder
        // blades. A model's authored facing is +Z and the camera sits on +Z,
        // so zero yaw is face-on.
        node.eulerAngles.y = entrance?.cut.stance ?? -0.42

        // The summoning circle: a rune dais on a floating rock, a half-ring of
        // pillars and braziers behind the figure, mist and dust, in the
        // summoned unit's pantheon and element colour. The SwiftUI glow and
        // rays show through between the pillars.
        StageBuilder.buildSummoningCircle(pantheon: result.blueprint.pantheon, tint: tint, into: scene)

        // The figure and the temple on separate lights (L1), unless the lab
        // asks for the rig as it was.
        let layered = !Self.layersOff
        if layered {
            Self.markFigure(node)
            context.coordinator.houseMaterials = Self.separateTheSet(in: scene)
        }

        // What the flash brings, built now so the warm-up draws it: the
        // shadow under the feet, and a twin of the beam's column (the beam
        // itself is spawned at the reveal, motes and all).
        let shadow = contactShadowNode()
        shadow.opacity = 0.8
        scene.rootNode.addChildNode(shadow)
        context.coordinator.contactShadow = shadow
        let twin = Self.warmBeamTwin(tint: tint)
        scene.rootNode.addChildNode(twin)
        context.coordinator.warmBeam = twin
        // And the entrance's flipbooks (W2.4), at full strength for the
        // warm-up like everything else the flash shows: the shockwave flat
        // on the dais, and for a 5★ the sunburst standing behind the figure.
        var tracks: [RevealFlipbookPlayer.Track] = []
        let ringTint: UIColor = tint.mixed(with: .white, amount: 0.5)
        if let ring = RevealFlipbook.groundRing(height: height, tint: ringTint) {
            scene.rootNode.addChildNode(ring.node)
            tracks.append(RevealFlipbookPlayer.Track(node: ring.node, frames: ring.frames,
                                                     delay: 0, life: RevealEntrance.ringLife))
        }
        if result.stars >= 5 {
            let gold: UIColor = UIColor(Rarity(stars: 5).glow).mixed(with: tint, amount: 0.25)
            if let burst = RevealFlipbook.standingBurst(height: height, tint: gold.withAlphaComponent(0.85)) {
                scene.rootNode.addChildNode(burst.node)
                tracks.append(RevealFlipbookPlayer.Track(node: burst.node, frames: burst.frames,
                                                         delay: RevealEntrance.burstDelay, life: RevealEntrance.burstLife))
            }
        }
        context.coordinator.flipbook = tracks.isEmpty ? nil : RevealFlipbookPlayer(tracks: tracks)

        // MARK: The framing
        //
        // Solved from the figure's height rather than dialled in, because the
        // playtest's note was that the character "reads small in a wide frame"
        // and a distance eyeballed at one aspect ratio is exactly what a wider
        // screen breaks. Pinning the projection direction is the first half of
        // that: left on `.automatic`, SceneKit picks the axis the field of view
        // applies to from the viewport's shape, so the whole solve would rest
        // on undocumented behaviour — `CameraDirector.init` makes the same
        // point about the battle lens. Vertical, and the height of the frame is
        // then a known quantity on any phone.
        //
        // A 30 degree lens, not the old 38: from the distance that fills the
        // frame, the longer lens keeps the figure's proportions instead of
        // swelling whatever is nearest the camera, which is most of the
        // difference between a hero shot and a webcam, and it also draws the
        // pillars and the temple behind larger, so the room reads as a room.
        // The figure stands 84% of the frame's height — 38 degrees from 2.05
        // heights back stood it 71% and left a third of the frame empty over
        // its head — with 7% of floor under its feet and 9% of air above it.
        let lens: Float = 30
        let fill: Float = 0.84
        let visibleHeight = height / fill
        let distance = visibleHeight / (2 * tan(lens * .pi / 180 / 2))
        // The aim point is half a frame below the top edge less the headroom,
        // so the head lands 9% down from the top whatever the unit's height.
        let aimY = height + visibleHeight * 0.09 - visibleHeight / 2

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(lens)
        camera.projectionDirection = .vertical
        // The near plane stays on SceneKit's default metre, and that is a
        // decision rather than an omission. Nothing in this set is ever seen
        // within a metre of the lens: the camera sits a tenth of a height
        // below its aim point, so the bottom edge of a 30 degree frame runs
        // 12.4 degrees below horizontal and does not reach the floor until
        // 2.8 m out even for the shortest unit, and the mist planes are
        // pushed behind the figure by `buildSummoningCircle`. The dust is the
        // exception, and it is why the metre matters. It is a 9 x 5 x 9 m box
        // centred at z = -1, so it reaches z = +3.5, while the solve below
        // puts a 1.5 m unit's camera at z = 3.33 — INSIDE it. A 3.5 cm mote
        // 5 cm from the lens subtends 39 degrees against a 30 degree frame,
        // which is the whole reveal washed out in one tinted blur, so the
        // near plane is the only thing clipping them and it has to stay where
        // it is. The far plane is generous because the temple prop sits at
        // z = -6.4 and a tall summon backs the camera off to 8 m.
        camera.zNear = 1
        camera.zFar = 200
        camera.wantsHDR = true
        // THE SHOULDER (2026-09-17, evening): `whitePoint` at SceneKit's
        // default 1.0 clips every lit surface at or over 1.0 flat to paper —
        // the battle learned it on 2026-09-15 (BattleSceneController) and
        // this camera never got it, which is half of why the owner's awakened
        // Ares photographed as a pale smear on the reveal. Same number as the
        // battle's so the figure looks the same on every stage.
        camera.whitePoint = 1.85
        // No exposure adaptation: on a black stage it meters the dark and
        // pushes the exposure up, and a gold character (Sekhmet) went white.
        camera.wantsExposureAdaptation = false
        // The reveal was still blooming at 0.6 over 0.82 — the exact setting
        // the battle stage abandoned when a sunlit sandstone floor became a
        // sheet of light. A marble temple did the same thing: the playtest's
        // Hoplite shot is blown out across the top left, and most of that is
        // bloom feeding on lit stone. Highlights only now, at the battle's own
        // threshold, and the lights below no longer hand it a whole wall.
        camera.bloomIntensity = 0.34
        camera.bloomThreshold = 0.93
        camera.bloomBlurRadius = 12
        // Grade rather than brighten. Contrast and saturation make a reveal
        // read rich without moving anything nearer to white, and the vignette
        // keeps the corners of a wide frame from competing with the figure —
        // the same job the SwiftUI vignette does behind this view, done here
        // for the parts of the frame the set covers. All three need
        // `wantsHDR`, which is on.
        // Eased 2026-09-20 (from 0.16, 1.12 and 0.25): the figure is lit by
        // the physically based model now and the paint's saturation is
        // tempered in the surface shader; a grade that pushed both back up
        // put the cartoon back. The saturation is the painting's own.
        camera.contrast = 0.10
        camera.saturation = 1.0
        camera.vignettingIntensity = 0.32
        camera.vignettingPower = 1.15
        camera.colorFringeStrength = 0.10

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        // On a rig of its own (W2.4): the entrance's kick moves the rig and
        // the push-in moves the camera, so the two never fight over one
        // position. The rig stands on the origin, so the camera's place in
        // it is its place in the world.
        let rig = SCNNode()
        rig.name = "reveal_camera_rig"
        scene.rootNode.addChildNode(rig)
        rig.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        context.coordinator.cameraRig = rig
        context.coordinator.cameraNode = cameraNode
        context.coordinator.visibleHeight = visibleHeight
        context.coordinator.distance = distance
        context.coordinator.aimY = aimY
        // A hint of a low angle: the camera sits a tenth of a height below what
        // it is aimed at, so it looks very slightly up at the character. The
        // old camera sat above the chest and looked down, and looking down at
        // something is most of what makes it read small.
        context.coordinator.cameraY = aimY - height * 0.10
        frameCamera(view, context.coordinator)

        // MARK: The light
        //
        // The reveal was lit like a spotlight demo: an 850 key, a 1,300 rim and
        // a 240 ambient is roughly 2.4 exposures before a surface's albedo is
        // applied, and a directional rim has no falloff, so it hit the front
        // faces of the pillars four metres behind the figure exactly as hard as
        // it hit the figure's edge. That is what is blown out along the top
        // left of the Hoplite shot: not the character, the temple behind it.
        // Four lights now, summing to about one exposure on a mid surface, with
        // the fill doing the work the rim was being over-driven to do.

        // Key from the front-left, mostly white: a key in the element colour on
        // top of the element recolour and the rim made the fourth tour's
        // Sekhmet one shade of red. The rim carries the colour; the key shows
        // the design.
        //
        // FIGURE-FIRST (2026-09-24, Docs/FEEL.md L1). The temple outshone the
        // god: in `5-reveal-a`, `-b` and `-awakened` the lit columns were
        // brighter than the figure, because every light here lit both. Now
        // the figure and the set are two light layers (`markFigure`,
        // `separateTheSet`): the figure keeps the whole rig — the key, the
        // cool fill and the tinted rim — and the temple is lit by its own key
        // at `templeKeyShare` of the figure's, the ambient, the environment
        // and its braziers, which reach 3 m now and warm only the set.
        // The key is ONE light at the temple's share, lighting both and
        // casting the figure's shadow exactly as the whole key did, and a
        // lift from the same place makes up the figure's own share: that
        // keeps the shadow on the dais as it was, whatever SceneKit does with
        // a shadow cast by a light that does not light the ground it falls
        // on. `-tour-layers off` photographs the rig as it was.
        let keyColour: UIColor = tint.mixed(with: .white, amount: FigureStageLighting.keyTintMix)
        let key = SCNLight()
        key.type = .directional
        key.intensity = FigureStageLighting.keyIntensity * (layered ? Self.templeKeyShare : 1)
        key.color = keyColour
        // The one shadow in the scene: the figure's, deferred and soft; the
        // quads never cast (`restrictShadows`, below and in `show`).
        FigureStageLighting.castShadows(from: key)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-3, 5, 4)
        keyNode.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(keyNode)
        if layered {
            let lift = SCNLight()
            lift.type = .directional
            lift.intensity = FigureStageLighting.keyIntensity * (1 - Self.templeKeyShare)
            lift.color = keyColour
            lift.categoryBitMask = Self.figureLights
            let liftNode = SCNNode()
            liftNode.light = lift
            // A child with no transform of its own: the key's place and aim.
            keyNode.addChildNode(liftNode)
        }

        // Fill from the other side, cool and weak. Without one, the shadow side
        // of a dark model is crushed to the ambient and the only way to find
        // the silhouette again is to over-drive the rim — which is how the rim
        // reached 1,300 and took the temple with it. A fill is the cheaper fix
        // and it keeps the costume readable.
        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.intensity = FigureStageLighting.fillIntensity
        fillLight.color = UIColor(hex: "#7C93D6") ?? .white
        if layered { fillLight.categoryBitMask = Self.figureLights }
        let fillNode = SCNNode()
        fillNode.light = fillLight
        fillNode.position = SCNVector3(5, 3, 4)
        fillNode.eulerAngles = SCNVector3(-0.45, 0.75, 0)
        scene.rootNode.addChildNode(fillNode)

        // Rim from behind, strongly tinted, for a lit silhouette edge — at 520
        // rather than 1,300, which is enough to draw an edge on the figure and
        // not enough to light a wall.
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = FigureStageLighting.rimIntensity
        rim.color = tint
        // The figure's alone since 2026-09-24: a directional rim has no
        // falloff, and it lit the columns behind as hard as the figure.
        if layered { rim.categoryBitMask = Self.figureLights }
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(2, 4, -5)
        rimNode.eulerAngles = SCNVector3(-0.5, 2.6, 0)
        scene.rootNode.addChildNode(rimNode)

        // Ambient floor so nothing goes fully black. Lower than it was, because
        // ambient is the one light that lifts every surface at once and it was
        // paying for the rim's over-exposure everywhere.
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = FigureStageLighting.ambientIntensity
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // The studio environment, so gold reflects something and the shadow
        // side is lit by a sky and a ground rather than a flat ambient; and
        // the figure the only caster (2026-09-18).
        FigureStageLighting.applyEnvironment(to: scene)
        FigureStageLighting.restrictShadows(in: scene, to: node)
        // A light unit's reveal a third of a stop down (run 221): its white
        // and gold light on a marble temple blew the column behind the
        // awakened Ares — 3.1% of the left half over 240, one patch two
        // thirds clipped — where the lab's frame 0.4 under clipped 0.01%.
        let radianceTrim: CGFloat = result.blueprint.element == .radiance ? -0.3 : 0
        camera.exposureOffset = FigureStageLighting.exposureOffset + radianceTrim

        // THE WARM-UP (2026-09-23, run 221). Everything the flash will show —
        // the figure, its shadow on the dais, the beam's column — is drawn
        // once while this view is all but invisible, then put out of sight
        // again, and only then is the reveal told the stage is ready. A
        // shader is compiled the first time something is drawn with it, and
        // run 221 drew the figure, the beam and the shadow for the first time
        // AT the flash: 21 compiles on SceneKit's thread, the main thread
        // held up 955 ms and then 419 ms behind them, and the three-second
        // frame was the name card over an empty dais under a stalled veil.
        // Drawing them, rather than `prepare(_:completionHandler:)`, is what
        // makes certain of it: the shadow pass, the deferred shadow and a
        // blended material's pipelines are built for the frame that draws
        // them, and a frame is what the warm-up is. The figure arrives whole
        // at the flash (`show`), so its opaque pipeline is the one it needs.
        // The charge's opening pose, its rings already turning, covers the
        // wait; the render delegate (`Coordinator`) runs it, and
        // `warmUpLimit` ends it should the view never draw.
        view.alpha = 0.01
        context.coordinator.view = view
        context.coordinator.onReady = onReady
        context.coordinator.onShown = onShown
        context.coordinator.onApex = onApex
        if revealed { show(context.coordinator) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.warmUpLimit) { [weak coordinator = context.coordinator] in
            coordinator?.giveUpWarmUp()
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onReady = onReady
        context.coordinator.onShown = onShown
        context.coordinator.onApex = onApex
        frameCamera(view, context.coordinator)
        if revealed { show(context.coordinator) }
    }

    /// Places the camera for a viewport of this shape.
    ///
    /// Only the sideways half of the framing depends on the aspect ratio, and
    /// `makeUIView` runs before the view has been laid out, so the phone's own
    /// 852 x 393 stands in until the first real layout arrives and the figure
    /// lands a quarter of the way in from the left on any landscape screen
    /// rather than on the one the numbers were typed for.
    private func frameCamera(_ view: SCNView, _ coordinator: Coordinator) {
        guard let cameraNode = coordinator.cameraNode else { return }
        let bounds = view.bounds
        // 852 x 393 points is the phone's landscape frame — the same one the
        // battle camera is solved for — and it stands in until a real layout.
        let phoneAspect: Float = 852 / 393
        let aspect = bounds.height > 0 ? Float(bounds.width / bounds.height) : phoneAspect
        guard abs(aspect - coordinator.framedAspect) > 0.01 else { return }
        coordinator.framedAspect = aspect

        // The figure's centre line stands 26% of the way in from the left edge,
        // leaving the right half of the screen to the name and the stars. The
        // camera is shifted, not turned: a yaw would swing the character into a
        // three-quarter view and lean the columns behind it, where a shift
        // keeps it square to the lens and the temple upright — the same reason
        // a view camera has a rising front.
        let halfWidth = coordinator.visibleHeight * aspect / 2
        let x = halfWidth * (1 - 2 * Float(Self.figureLine))
        // A push-in in flight would fight this; a re-frame only happens on a
        // real change of shape, and the framing is what matters then.
        cameraNode.removeAction(forKey: "push")
        cameraNode.position = SCNVector3(x, coordinator.cameraY, coordinator.distance)
        // A camera node looks along its own -Z, and the aim shares the camera's
        // x so that this is a pure tilt.
        cameraNode.look(at: SCNVector3(x, coordinator.aimY, 0))
        // Home now: a push-in still waiting would end on the old framing.
        coordinator.pushHome = nil
    }

    /// The figure arrives on the beam, once: whole and at once, under the
    /// flash (2026-09-23). It faded in over a third of a second until run
    /// 221, which the flash hid anyway, and the fade drew it through
    /// SceneKit's blended pass — its far arm through its chest — on a
    /// pipeline of its own, compiled at the flash. The shadow and the beam
    /// were drawn in the warm-up, so nothing here is drawn for the first
    /// time.
    private func show(_ coordinator: Coordinator) {
        guard !coordinator.shown, let figure = coordinator.figure, let scene = coordinator.scene else { return }
        coordinator.markShown()
        figure.opacity = 1
        coordinator.contactShadow?.runAction(.fadeOpacity(to: 0.8, duration: 0.3))
        VFXLibrary.summonBeam(at: SCNVector3(0, 0, 0), in: scene, tint: coordinator.tint)
        // The beam's quads arrived after the figure: they cast nothing.
        FigureStageLighting.restrictShadows(in: scene, to: figure)
        // Figure-first light (L1): the figure's layer read again as it
        // arrives — a category is not inherited, so anything the model
        // gained since the build must carry it too — and, once the flash has
        // begun to clear, the house goes down.
        if !coordinator.houseMaterials.isEmpty {
            Self.markFigure(figure)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dimDelay) { [weak coordinator] in
                coordinator?.dimTheHouse()
            }
        }
        // The turn toward the player waits for the entrance to hand back to
        // the idle (`Coordinator.entranceDone`), or, with no clip, for the
        // figure's first frame on the beam (`figureShown`).

        // The camera starts a twelfth of the distance back and pushes in once
        // the entrance is done (`Coordinator.startPush`): it pushed in over
        // the beat the name landed on until 2026-09-24, and a victory's
        // raised arms and weapons (the hands reach 1.11 of the figure's
        // height in the cheer) left the top of the frame as it closed in.
        // It eases out, so it reads as the shot settling rather than as a
        // zoom. Backing off along the node's own front keeps the aim exactly
        // where the solve put it, so nothing drifts on the way in.
        if let cameraNode = coordinator.cameraNode {
            let home = cameraNode.position
            let front = cameraNode.worldFront
            let back = coordinator.distance * 0.12
            cameraNode.position = SCNVector3(home.x - front.x * back,
                                             home.y - front.y * back,
                                             home.z - front.z * back)
            coordinator.pushHome = home
        }

        // THE ENTRANCE (Docs/FEEL.md W2.4): the hold, then the victory, the
        // kick, the flipbooks and the high point (`Coordinator.beginEntrance`).
        coordinator.beginEntrance()
    }

    /// The figure settles out of its three-quarter stance to face the player
    /// as the stars tick in, then breathes: a slow sway of a fifth of a
    /// radian either way, which is enough to keep the silhouette alive
    /// without ever turning the face away. A reveal is the most-looked-at
    /// second in the game and a dead-still model is the tell that it is a
    /// prop rather than a character.
    ///
    /// "Face the player" is read off the FEET, not assumed (2026-09-18):
    /// a family with no `idle` plays its combat idle here, a guard stance
    /// whose feet point off the mesh's forward — Sekhmet showed her
    /// profile and the awakened Ares his back on three runs of frames,
    /// lit by the cool fill on the side the camera saw. The correction
    /// turns the feet toward the lens and the sway swings about it.
    /// Called on the figure's first frame on the beam (`figureShown`): the
    /// joints' presentation positions are all zero until the renderer has
    /// posed the figure once, and run 186 read a zero heel-to-toe vector
    /// off joints it had found by name. Reading them there, rather than on
    /// a timer, also keeps the main thread off the scene while SceneKit's
    /// thread is busy — run 221's timer read them in the middle of the
    /// flash's shader compiles and waited 955 ms.
    nonisolated private static func settle(_ figure: SCNNode) {
        let facing = facingCorrection(for: figure)
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(facing), z: 0, duration: 1.5, usesShortestUnitArc: true)
        turn.timingMode = .easeOut
        let swayRight = SCNAction.rotateTo(x: 0, y: CGFloat(facing + 0.20), z: 0, duration: 4.5, usesShortestUnitArc: true)
        swayRight.timingMode = .easeInEaseOut
        let swayLeft = SCNAction.rotateTo(x: 0, y: CGFloat(facing - 0.20), z: 0, duration: 4.5, usesShortestUnitArc: true)
        swayLeft.timingMode = .easeInEaseOut
        figure.runAction(.sequence([turn, .repeatForever(.sequence([swayRight, swayLeft]))]), forKey: "turn")
    }

    /// The yaw that turns the figure's feet toward the camera (+Z), read off
    /// the animated pose at the moment of the reveal: the heel-to-toe
    /// direction of both feet, averaged, in world space (the rigs are
    /// Mixamo-named, `LeftFoot` → `LeftToeBase`; the older exports end in
    /// `_End`). Zero when the joints are not found, which leaves the stance
    /// as it was; the correction is printed once so a run's console says
    /// what it read. The joints are matched by the END of the node's name,
    /// case blind: an exact `childNode(withName: "LeftFoot")` found nothing
    /// on runs 184 and 185 — SceneKit names a USD joint node by more than
    /// its last path component — and the whole correction sat idle.
    nonisolated private static func facingCorrection(for figure: SCNNode) -> Float {
        var seen: [String] = []
        func point(_ suffix: String) -> SCNVector3? {
            let wanted = suffix.lowercased()
            let hit = figure.childNodes(passingTest: { node, stop in
                guard let name = node.name?.lowercased(), name.hasSuffix(wanted) else { return false }
                stop.pointee = true
                return true
            }).first
            if let name = hit?.name { seen.append(name) }
            return hit?.presentation.worldPosition
        }
        var dx: Float = 0, dz: Float = 0, found = 0
        for (heel, toe) in [("LeftFoot", "LeftToeBase"), ("RightFoot", "RightToeBase"),
                            ("LeftFoot", "LeftToe_End"), ("RightFoot", "RightToe_End")] {
            guard let h = point(heel), let t = point(toe) else { continue }
            dx += t.x - h.x
            dz += t.z - h.z
            found += 1
        }
        guard found > 0 else {
            let names = figure.childNodes(passingTest: { _, _ in true }).compactMap(\.name).prefix(12)
            print("[Reveal] facing: no foot joints found; stance kept (nodes: \(names.joined(separator: ", ")))")
            return 0
        }
        guard dx * dx + dz * dz > 1e-6 else {
            print("[Reveal] facing: \(found) feet found but not yet posed (a zero heel-to-toe vector); stance kept")
            return 0
        }
        let yaw = atan2(dx, dz)
        let correction = figure.eulerAngles.y - yaw
        print("[Reveal] facing: feet at \(Int(yaw * 180 / .pi))°, figure turned to \(Int(correction * 180 / .pi))° from \(found) feet (\(seen.joined(separator: ", ")))")
        return correction
    }

    /// A soft patch of shade under the feet.
    ///
    /// No light in this scene casts a shadow, and none should: a shadow-casting
    /// key would have the summoning circle's additive quads — the mist planes
    /// and the beam — throwing solid black shapes of their own across the dais.
    /// A painted patch does the one job that matters, which is to stop the
    /// figure looking pasted onto the stone. It is drawn with a real alpha
    /// channel and composited normally rather than additively, for the reason
    /// written beside this view's clear background.
    ///
    /// Built with the set, out of sight (the warm-up draws it once first);
    /// `show` fades it in.
    private func contactShadowNode() -> SCNNode {
        let size = CGFloat(result.blueprint.model.height) * 0.75
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Self.contactShadowImage
        material.writesToDepthBuffer = false
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        // An SCNPlane stands in the XY plane facing +Z; a quarter turn back
        // about X lays it on the dais facing up. A centimetre of clearance
        // keeps it off the stone it would otherwise fight for depth.
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.position = SCNVector3(0, 0.012, 0)
        node.renderingOrder = 5
        node.opacity = 0
        return node
    }

    /// The family's victory clip wrapped for the entrance, unless the family
    /// is denied one (`RevealEntrance.denied`) or has none; nil enters the
    /// figure idling, as every reveal did before 2026-09-24.
    private static func entranceClip(for assetName: String) -> RevealEntranceClip? {
        guard !RevealEntrance.denied.contains(assetName),
              let clip = ModelLibrary.shared.animation(.victory, for: assetName) else { return nil }
        return RevealEntranceClip(clip: clip)
    }

    /// The column of `VFXLibrary.summonBeam` — the same cylinder under the
    /// same material, which is what its shader is compiled for — drawn in
    /// the warm-up only and taken down after it. The beam itself is spawned
    /// at the reveal, as it always was: its motes rise from a particle
    /// system, and a node carrying one may not leave the scene while its
    /// motes live (the fight's two crashes of 2026-09-15). The twin carries
    /// none; the motes draw with the braziers' particle shader, which the
    /// set's own flames have compiled. Should the beam's material change,
    /// change it here too.
    private static func warmBeamTwin(tint: UIColor) -> SCNNode {
        let beam = SCNCylinder(radius: 0.8, height: 14)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = tint.withAlphaComponent(0.25)
        material.emission.contents = tint
        material.blendMode = .add
        material.writesToDepthBuffer = false
        beam.firstMaterial = material
        let node = SCNNode(geometry: beam)
        node.position = SCNVector3(0, 7, 0)
        return node
    }

    /// Black in the middle, transparent at the rim, with the alpha channel the
    /// stage's own sprites turned out not to have.
    static let contactShadowImage: UIImage = {
        let side: CGFloat = 256
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let colors = [UIColor.black.withAlphaComponent(0.85).cgColor,
                          UIColor.black.withAlphaComponent(0.40).cgColor,
                          UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            let locations: [CGFloat] = [0, 0.45, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: locations) else { return }
            let centre = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(gradient,
                                                 startCenter: centre, startRadius: 0,
                                                 endCenter: centre, endRadius: side / 2,
                                                 options: [])
        }
    }()
}

/// One of the reveal set's own lit materials and the `multiply` colour it
/// takes when the house goes down (`SummonStageView.separateTheSet`,
/// `Coordinator.dimTheHouse`).
struct RevealHouseMaterial {
    let material: SCNMaterial
    let dimmed: UIColor
}

/// Where a reveal stage's warm-up stands (`SummonStageView.makeUIView`).
private enum RevealStageWarmUp {
    /// Out of sight, drawing everything the flash will show.
    case drawing
    /// Drawn; the main queue is putting it all out of sight again.
    case drawn
    /// Waiting for a frame drawn with nothing on the beam.
    case clearing
    /// In view: the charge's clock has started, and the first frame with
    /// the figure on the beam is reported.
    case ready
}

/// The charge's rune rings, keyed once per launch (`SummonRevealView`'s
/// `chargeRing` draws the element's colour through it).
enum RuneLinesArt {
    /// `rune_ring` keyed to its drawn lines, as a white mask (2026-09-23).
    ///
    /// Run 221 masked the painting by its luminance through a 1.6 contrast,
    /// and the charge's rings printed as one filled red disc about 210
    /// points across, laid over the temple like a film: the painting is
    /// gold lines at luminance 0.78–1.0 over a teal GLOW at 0.45–0.55 that
    /// fills its bands, and any mask that lets the glow through fills the
    /// ring. Keyed here instead — alpha a smoothstep of the luminance from
    /// 0.60 to 0.85, so the glow and the gold lines' soft shoulders go and
    /// the lines stay, and nothing inside 0.44–0.48 of the radius, where
    /// the spokes and the star converge into a blot at this size and the
    /// scroll stands anyway. Judged on a mock of the held charge over the
    /// run's own set against the old mask and the thresholds either side.
    /// Once per launch (`prepare`, off the main thread); the SwiftUI filters
    /// it replaces ran every frame.
    static let image: UIImage? = keyed()

    /// Keys the rings on a background queue, so the charge's first frame
    /// never pays for it: the loop is a million pixels, a tenth of a
    /// second or more in the Debug build a phone runs from Xcode. Called
    /// when the summon room appears; the charge reads whatever is ready.
    static func prepare() {
        DispatchQueue.global(qos: .utility).async { _ = image }
        // The gold rung's lightning, cut on the same visit (2026-09-24).
        LightningArt.prepare()
        // And the entrance's flipbooks (Docs/FEEL.md W2.4), so the first
        // reveal's stage never cuts them on the main thread.
        RevealFlipbook.prepare()
    }

    private static func keyed() -> UIImage? {
        guard let source = BundleArt.image("rune_ring")?.cgImage else { return nil }
        let width = source.width
        let height = source.height
        // Device RGB is sRGB on iOS: the levels read below are the file's
        // own, the ones the thresholds were measured on.
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)

        // The line ramp as a table over the 256 luminance levels.
        let lineFloor = 0.60
        let lineFull = 0.85
        var ramp = [UInt8](repeating: 0, count: 256)
        for level in 0..<256 {
            let t = min(1, max(0, (Double(level) / 255 - lineFloor) / (lineFull - lineFloor)))
            ramp[level] = UInt8((t * t * (3 - 2 * t) * 255).rounded())
        }
        // The hub, as squared distances from the centre in pixels.
        let half = Double(min(width, height)) / 2
        let hubClear = (half * 0.44) * (half * 0.44)
        let hubOpen = (half * 0.48) * (half * 0.48)
        let centreX = Double(width) / 2
        let centreY = Double(height) / 2

        ramp.withUnsafeBufferPointer { table in
            for y in 0..<height {
                let dy = Double(y) + 0.5 - centreY
                let row = pixels + y * rowBytes
                for x in 0..<width {
                    let dx = Double(x) + 0.5 - centreX
                    let reach = dx * dx + dy * dy
                    let pixel = row + x * 4
                    // Rec. 709 luminance in integers (the weights sum to 256).
                    let level = (54 * Int(pixel[0]) + 183 * Int(pixel[1]) + 19 * Int(pixel[2])) >> 8
                    var alpha = Double(table[min(255, level)])
                    if reach < hubOpen {
                        alpha = reach <= hubClear ? 0 : alpha * (reach - hubClear) / (hubOpen - hubClear)
                    }
                    // White at that alpha, premultiplied.
                    let value = UInt8(min(255, max(0, alpha.rounded())))
                    pixel[0] = value
                    pixel[1] = value
                    pixel[2] = value
                    pixel[3] = value
                }
            }
        }
        guard let keyed = context.makeImage() else { return nil }
        return UIImage(cgImage: keyed)
    }
}

/// The charge's rarity ladder (2026-09-24, Docs/FEEL.md W1.5).
///
/// Until this the grade showed on the FIRST frame: the beam's width, the
/// rings' pace, the charge's length, the charge sound's volume and the glow
/// behind it were all read off the stars, so a 3★ was a thin, short, cyan
/// charge from its first frame and the suspense was over before it began.
/// The genre does the opposite on purpose. Summoners War gives a 4★ and a
/// 5★ the same animation so the player asks "is it a 4 or a 5?", and a 5★
/// breaks into lightning; Genshin's meteor turns from blue or purple to
/// gold; and the writing on gacha psychology puts the peak of a pull DURING
/// the animation, not at the reveal. So every charge opens the same — a
/// cool blue-white, a narrow beam, slow rings — and climbs: at `violetAt` a
/// 4★ or better turns violet (the beam widens, the rings quicken, a sting
/// and a tap); at `goldAt` a 5★ breaks into gold with lightning round the
/// beam; at `splitAt` a Light or Dark 5★ parts white-gold or violet-black.
/// Each step is a smoothstep over `step` seconds.
///
/// The rungs stand at SECONDS into the charge, not at fractions of it: a
/// 5★'s charge is 0.15 s longer (`span`), and as fractions its violet step
/// would land 50 ms after a 4★'s, a tell however small. On seconds a 4★ and
/// a 5★ are the same charge until the gold.
///
/// Nothing here is ever faked: a rung is climbed only by the grade that
/// owns it, read off the pull's own stars — violet means a real 4★ or
/// better, gold a real 5★. Every function is pure, so the charge stays a
/// function of the wall clock (`SummonRevealView.chargeLayer`).
enum ChargeLadder {
    /// How long a charge runs: every grade the same, a 5★ a beat longer.
    static let baseSpan: TimeInterval = 1.25
    static let fiveStarSpan: TimeInterval = 1.4
    /// The rungs, in seconds into the charge: 35%, 70% and 85% of the base
    /// span.
    static let violetAt: TimeInterval = 0.4375
    static let goldAt: TimeInterval = 0.875
    static let splitAt: TimeInterval = 1.0625
    /// How long a step takes.
    static let step: TimeInterval = 0.15

    /// The ground every charge opens on: a cool blue-white.
    static let ground = ChargeRGB(0.81, 0.90, 1.0)
    /// The grade language's own colours (`Rarity.glow`), so the ladder and
    /// every card frame in the game say a grade the same way.
    static let violet = ChargeRGB(Rarity(stars: 4).glow)
    static let gold = ChargeRGB(Rarity(stars: 5).glow)
    /// A Light 5★ parts into white-gold, a Dark one into a deep violet with
    /// its veil (`SummonRevealView.chargeVeil`) and a pale violet core.
    static let radianceSplit = ChargeRGB(1.0, 0.95, 0.80)
    static let umbraSplit = ChargeRGB(0.48, 0.24, 0.84)
    static let umbraCore = ChargeRGB(0.85, 0.76, 1.0)

    static func span(stars: Int) -> TimeInterval {
        stars >= 5 ? fiveStarSpan : baseSpan
    }

    /// One stem of the charge's sound (Docs/FEEL.md W2.7): what plays, how
    /// many seconds into the charge, how loud, and the touch that comes
    /// with it.
    struct Stem: Equatable {
        let sound: AudioLibrary.Sound
        let at: TimeInterval
        let volume: Float
        let touch: UIImpactFeedbackGenerator.FeedbackStyle?
    }

    /// The charge's stems for a pull of `stars` from `scroll`, the sound of
    /// the ladder: the base under every pull from the first frame, and the
    /// Light & Dark scroll's bell tree and choir with it when that is the
    /// scroll SPENT; the rise from the violet rung for a 4★ or better; the
    /// tell from the gold rung for a 5★ alone. The rungs read the pull's own
    /// stars and nothing looser — the scroll, a feature, the element never
    /// ring one — and everything at the first frame is the same for every
    /// grade, so no sound tells the pull before its rung does.
    static func stems(stars: Int, scroll: ScrollType?) -> [Stem] {
        var stems: [Stem] = [Stem(sound: .summonChargeBase, at: 0, volume: stemVolume, touch: nil)]
        if scroll == .lightDark {
            stems.append(Stem(sound: .summonChargeLightDark, at: 0, volume: stemVolume, touch: nil))
        }
        if stars >= 4 {
            stems.append(Stem(sound: .summonChargeRise, at: violetAt, volume: stemVolume, touch: .medium))
        }
        if stars >= 5 {
            stems.append(Stem(sound: .summonChargeTell, at: goldAt, volume: stemVolume, touch: .heavy))
        }
        return stems
    }

    // The reveal's MIX (Docs/FEEL.md W2.7). A phone's mixer sums its
    // players with nothing after it to catch a sum over full scale, and the
    // reveal plays up to four sounds at once, so these numbers are the ones
    // `summon_mix_check` in tools/sfx.py sums (`STEM_VOLUME`, `STEM_FADE`,
    // `BURST_LEAD`, `STAR_VOLUMES`, `QUICK_BURST_VOLUME`), kept in step with
    // it by hand: every grade's sum peaks at or under 0.90 of full scale.

    /// Every stem plays at this volume; the files are levelled as a mix.
    static let stemVolume: Float = 0.85

    /// Every sound a stem can be, for the fade that clears them.
    static let stemSounds: [AudioLibrary.Sound] = [
        .summonChargeBase, .summonChargeLightDark, .summonChargeRise, .summonChargeTell,
    ]

    /// Every burst a flash can sound, for the fade on to the next pull: a
    /// 5★'s choir in E major rings three seconds, and under the next
    /// charge's open fifth on D it would be a clash.
    static let burstSounds: [AudioLibrary.Sound] = [.summonBurst3, .summonBurst4, .summonBurst5]

    /// At the flash the stems fade out over this long…
    static let stemFade: TimeInterval = 0.05

    /// …and the burst sounds this long after it, on the audio clock
    /// (`AudioLibrary.schedule`), so it lands on its own. Sound 40 ms behind
    /// the picture is well inside what reads as together; sound AHEAD of it
    /// would not be.
    static let burstLead: TimeInterval = 0.04

    /// A Quick 3★'s burst: its stars stamp inside the chime's first 300 ms.
    static let quickBurstVolume: Float = 0.8

    /// The stars ring over the grade's burst, a little softer the bigger
    /// the burst under them: over a 3★'s chime 0.7, a 4★'s brass 0.65, a
    /// 5★'s choir 0.55 (at 0.7 the 5★'s sum reached 1.04 of full scale).
    static func starVolume(stars: Int) -> Float {
        if stars >= 5 { return 0.55 }
        if stars == 4 { return 0.65 }
        return 0.7
    }

    /// 0 at the foot of the rung at `rungAt`, 1 once it is climbed, a
    /// smoothstep between.
    static func climbed(_ rungAt: TimeInterval, at clock: TimeInterval) -> CGFloat {
        let t: Double = min(1, max(0, (clock - rungAt) / step))
        let eased: Double = t * t * (3 - 2 * t)
        return CGFloat(eased)
    }

    /// Where the ladder stands at `clock` seconds: 0 on the ground, 1 at
    /// violet, 2 at gold; a grade never climbs past its own rung.
    static func rung(stars: Int, at clock: TimeInterval) -> CGFloat {
        var level: CGFloat = 0
        if stars >= 4 { level += climbed(violetAt, at: clock) }
        if stars >= 5 { level += climbed(goldAt, at: clock) }
        return level
    }

    /// How far a Light or Dark 5★ has parted from the gold, 0…1; 0 for
    /// every other pull.
    static func split(stars: Int, element: Element, at clock: TimeInterval) -> CGFloat {
        guard stars >= 5, element.isLightOrDark else { return 0 }
        return climbed(splitAt, at: clock)
    }

    /// The ladder's light at `clock`: the ground's blue-white, mixed to
    /// violet, then gold, then the Light or Dark split, step by step.
    static func light(stars: Int, element: Element, at clock: TimeInterval) -> ChargeRGB {
        var light: ChargeRGB = ground
        if stars >= 4 { light = light.mixed(with: violet, by: climbed(violetAt, at: clock)) }
        if stars >= 5 { light = light.mixed(with: gold, by: climbed(goldAt, at: clock)) }
        let parted: CGFloat = split(stars: stars, element: element, at: clock)
        if parted > 0 {
            let far: ChargeRGB = element == .umbra ? umbraSplit : radianceSplit
            light = light.mixed(with: far, by: parted)
        }
        return light
    }

    /// The area under `rung` from the charge's start to `clock`, in
    /// rung-seconds: what a pace that quickens with every rung has covered
    /// beyond the ground's. The rings' turn and the motes' rise are read off
    /// it, so a step changes their pace without a jump in where they stand.
    static func travel(stars: Int, to clock: TimeInterval) -> CGFloat {
        var sum: CGFloat = 0
        if stars >= 4 { sum += climbedArea(violetAt, to: clock) }
        if stars >= 5 { sum += climbedArea(goldAt, to: clock) }
        return sum
    }

    /// The integral of `climbed(rungAt, at: τ)` for τ from 0 to `clock`:
    /// `step · (x³ − x⁴/2)` through the step, then half a step plus the
    /// time since it ended.
    static func climbedArea(_ rungAt: TimeInterval, to clock: TimeInterval) -> CGFloat {
        let since: Double = clock - rungAt
        guard since > 0 else { return 0 }
        guard since < step else {
            let after: Double = since - step
            return CGFloat(step / 2 + after)
        }
        let x: Double = since / step
        let cube: Double = x * x * x
        let area: Double = step * (cube - cube * x / 2)
        return CGFloat(area)
    }
}

/// A colour as three sRGB numbers, for mixing the ladder's light by the
/// clock (2026-09-24).
struct ChargeRGB {
    var red: Double
    var green: Double
    var blue: Double

    static let white = ChargeRGB(1, 1, 1)

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A SwiftUI colour's own components, read once through UIKit.
    init(_ color: Color) {
        var r: CGFloat = 1
        var g: CGFloat = 1
        var b: CGFloat = 1
        var a: CGFloat = 1
        _ = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b))
    }

    func mixed(with other: ChargeRGB, by amount: CGFloat) -> ChargeRGB {
        let t: Double = Double(min(1, max(0, amount)))
        let r: Double = red + (other.red - red) * t
        let g: Double = green + (other.green - green) * t
        let b: Double = blue + (other.blue - blue) * t
        return ChargeRGB(r, g, b)
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// The sixteen frames of `vfx_lightning_sheet` (2026-09-24), the lightning
/// the charge's gold rung strikes round the beam (`SummonRevealView
/// .chargeBolt`). The sheet is the painted 4 × 4 flipbook the fight's
/// lightning plays (tools/vfx_sheets.py): a bolt forming, striking a
/// splash of light on the ground, branching, and fading, on a clear ground.
/// Each cell is drawn once into its own bitmap on a background queue —
/// cut from the sheet it would have been decoded again on the charge's
/// frames — about 4 MB for the sixteen, kept for the session. The charge
/// reads a frame without waiting: until the cut is done it draws no bolt.
enum LightningArt {
    static let frameCount = 16
    private static let lock = NSLock()
    private static var frames: [UIImage] = []
    private static var started = false

    /// Cuts the sheet once, off the main thread (the summon room's
    /// `RuneLinesArt.prepare` and the reveal's appearance both ask).
    static func prepare() {
        lock.lock()
        let first = !started
        started = true
        lock.unlock()
        guard first else { return }
        DispatchQueue.global(qos: .utility).async {
            let cut = cutSheet()
            lock.lock()
            frames = cut
            lock.unlock()
        }
    }

    /// Frame `number` of the sixteen, once cut; nil until then.
    static func frame(_ number: Int) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard frames.indices.contains(number) else { return nil }
        return frames[number]
    }

    private static func cutSheet() -> [UIImage] {
        guard let sheet = BundleArt.uncachedImage("vfx_lightning_sheet")?.cgImage else { return [] }
        let side: Int = min(sheet.width, sheet.height) / 4
        guard side > 0 else { return [] }
        var cut: [UIImage] = []
        for row in 0..<4 {
            for column in 0..<4 {
                let cell = CGRect(x: column * side, y: row * side, width: side, height: side)
                guard let cropped = sheet.cropping(to: cell),
                      let drawn = redrawn(cropped, side: side) else { continue }
                cut.append(UIImage(cgImage: drawn))
            }
        }
        return cut.count == frameCount ? cut : []
    }

    /// A cell drawn into a bitmap of its own, premultiplied, so drawing it
    /// never decodes the sheet again.
    private static func redrawn(_ cell: CGImage, side: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cell, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
}
