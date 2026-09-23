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
    /// How long this charge runs: 1.25 s for a 4★ or better, 0.8 s under.
    @State private var chargeDuration: TimeInterval = 1.25
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
    @State private var shownStars = 0
    @State private var nameSlam = false
    @State private var detailsShown = false
    /// The sequence whose words have been set going (`startWords`), so the
    /// figure's first frame and the fallback cannot start them twice.
    @State private var wordsFor: Int?
    @State private var rays: Double = 0
    /// Bumped whenever a sequence is started or cut short, so a stale timer
    /// from a skipped reveal cannot land on the next one.
    @State private var sequence = 0

    private var current: SummonResult? {
        results.indices.contains(index) ? results[index] : nil
    }

    private var isFullyRevealed: Bool { detailsShown }

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
                        onShown: { stageShown(key) }
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

            VStack {
                HStack {
                    Spacer()
                    Button(showAll ? "Done" : "Skip") {
                        AudioLibrary.shared.play(.uiTap)
                        if showAll { onFinish() } else { sequence += 1; showAll = true }
                    }
                    .font(Theme.title(13))
                    .tracking(1.2)
                    .foregroundStyle(Color(hex: "#FFE9A8"))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(GlassPlate(radius: 17))
                    .padding(12)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.light)
        .onAppear { revealNext() }
    }

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
                RadialGradient(
                    colors: [tint.opacity(revealed ? 0.40 : (charging ? 0.20 : 0)),
                             tint.opacity(revealed ? 0.19 : (charging ? 0.09 : 0)),
                             tint.opacity(revealed ? 0.06 : (charging ? 0.03 : 0)),
                             .clear],
                    center: .init(x: 0.27, y: 0.5),
                    startRadius: 0,
                    endRadius: revealed ? 320 : 130
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.5), value: revealed)
                .animation(.easeInOut(duration: 0.9), value: charging)

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
    /// takes over. The grade sets the scale (`grandeur`): a 3★'s rings are
    /// dim and slow and its beam thin, a 5★'s are bright, fast and wide.
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
            chargeMotes(look)
            chargeFlare(look)
            chargeScrollLayer(result, look: look)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Every number the charge draws with, as typed values, so no layer's
    /// view expression holds arithmetic.
    private struct ChargeLook {
        let colour: Color
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
        let side: CGFloat
        let flareSide: CGFloat
        let flareRadius: CGFloat
        let flareScale: CGFloat
        let flareOpacity: Double
        let scrollTilt: Double
        let scrollScale: CGFloat
        let scrollGlow: CGFloat
        let scrollY: CGFloat
    }

    private func chargeLook(_ result: SummonResult, clock: TimeInterval, ambient: TimeInterval,
                            size: CGSize) -> ChargeLook {
        let grand: CGFloat = Self.grandeur(stars: result.stars)
        let colour: Color = result.blueprint.element.color
        let span: TimeInterval = max(0.1, chargeDuration)
        // Held (the CI's charge frame) at seven tenths of the way: the
        // rings and the motes keep turning, the gathering stops short of the
        // flare.
        let gathered: TimeInterval = Self.holdsCharge ? min(clock, span * 0.7) : clock
        let progress: CGFloat = CGFloat(min(1, gathered / span))
        let rest: CGFloat = 1 - progress
        let gather: CGFloat = 1 - rest * rest * rest
        let flareRamp: CGFloat = (progress - 0.72) / 0.28
        let flare: CGFloat = max(0, flareRamp)

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
        // them); a 3★'s stays a thin shaft. Through the gather a 5★'s
        // stands at 0.85, a 4★'s at 0.65 and a 3★'s at 0.45, and the flare
        // lifts each by 15% more: run 234's 5★ gathered at 0.68, and its
        // white never reached 230.
        let beamShare: CGFloat = 0.10 + 0.18 * grand
        let beamWidth: CGFloat = height * beamShare
        let beamRise: CGFloat = 0.30 + 0.70 * gather
        let beamHeight: CGFloat = feet * beamRise
        let beamCentre: CGFloat = feet - beamHeight / 2
        let beamBase: CGFloat = 0.45 + 0.40 * grand
        let beamFlare: CGFloat = 1 + 0.15 * flare
        let beamLight: CGFloat = min(1, beamBase * beamFlare)
        let beamOpacity: Double = Double(beamLight)
        // The motes keep the sway they had with the narrower beam.
        let spreadShare: CGFloat = 0.10 + 0.10 * grand
        let moteSpread: CGFloat = height * spreadShare
        let moteCount: CGFloat = (8 * grand).rounded()
        let motes: Int = 4 + Int(moteCount)

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
        let turnRate: Double = Double(24 + 36 * grand)
        let outerTurn: Double = ambient * turnRate
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

        return ChargeLook(
            colour: colour, grand: grand, ambient: ambient,
            x: x, feet: feet, heart: heart,
            poolSide: poolSide, poolRadius: poolRadius, poolStretch: poolStretch, poolOpacity: poolOpacity,
            ringSize: ringSize, innerRingSize: innerRingSize, ringScale: ringScale,
            outerTurn: outerTurn, innerTurn: innerTurn,
            outerRingOpacity: Double(outerLight), innerRingOpacity: Double(innerLight),
            beamWidth: beamWidth, beamHeight: beamHeight, beamCentre: beamCentre, beamOpacity: beamOpacity,
            moteSpread: moteSpread, motes: motes,
            side: side, flareSide: flareSide, flareRadius: flareRadius,
            flareScale: flareScale, flareOpacity: flareOpacity,
            scrollTilt: scrollTilt, scrollScale: scrollScale, scrollGlow: scrollGlow, scrollY: scrollY
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
        chargeBeam(colour: look.colour)
            .frame(width: look.beamWidth, height: look.beamHeight)
            .opacity(look.beamOpacity)
            .blendMode(.plusLighter)
            .position(x: look.x, y: look.beamCentre)
    }

    /// Motes climbing the beam.
    private func chargeMotes(_ look: ChargeLook) -> some View {
        ForEach(0..<look.motes, id: \.self) { mote in
            chargeMote(mote, clock: look.ambient, grand: look.grand, colour: look.colour)
                .position(Self.motePoint(mote, clock: look.ambient, grand: look.grand,
                                         x: look.x, feet: look.feet, spread: look.moteSpread))
        }
    }

    /// The flare the flash takes over.
    private func chargeFlare(_ look: ChargeLook) -> some View {
        let colours: [Color] = [Color.white.opacity(0.9), look.colour.opacity(0.4), look.colour.opacity(0)]
        let light = RadialGradient(colors: colours, center: .center, startRadius: 0, endRadius: look.flareRadius)
        return Circle()
            .fill(light)
            .frame(width: look.flareSide, height: look.flareSide)
            .scaleEffect(look.flareScale)
            .opacity(look.flareOpacity)
            .position(x: look.x, y: look.heart)
    }

    /// The scroll's glow: its silhouette in the element's colour at 0.85,
    /// blurred as far as its shadow was (`scrollGlow`), in the scroll's own
    /// place and turn. It was the scroll's `.shadow` until run 234, and a
    /// shadow is drawn with its view, so the glow could not go under the
    /// beam while the scroll stayed over it (`chargeScene`).
    private func chargeScrollGlow(_ result: SummonResult, look: ChargeLook) -> some View {
        look.colour.opacity(0.85)
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

    /// 0 for a 3★ or under, 0.5 for a 4★, 1 for a 5★ or better.
    private static func grandeur(stars: Int) -> CGFloat {
        CGFloat(min(2, max(0, stars - 3))) / 2
    }

    /// A column of light: white held flat across the middle fifth of its
    /// width, the element's colour either side, clear at the edges; full
    /// from the floor up behind the scroll, fading out over its top third.
    /// Added to the set (`chargeBeamLayer`), so the core burns to white on
    /// whatever stands behind it and the colour lights the set rather than
    /// painting over it.
    ///
    /// Run 234's beam peaked at ONE stop, white at 0.95 between flanks of
    /// the colour at 0.55, so only its centre line was white at all, and
    /// its top half faded out: the scroll hangs at 0.42 of the frame's
    /// height, inside that fade. The mock of the held charge (run 234's
    /// frame with the old beam taken out and this one added) reads 252–255
    /// on the axis from the floor to the inner ring, over 230 across 40–55
    /// points; drawn plainly instead, 223–236 across 10–25.
    private func chargeBeam(colour: Color) -> some View {
        let across: [Gradient.Stop] = [
            .init(color: colour.opacity(0), location: 0),
            .init(color: colour.opacity(0.35), location: 0.20),
            .init(color: Color.white.opacity(0.95), location: 0.40),
            .init(color: Color.white.opacity(0.95), location: 0.60),
            .init(color: colour.opacity(0.35), location: 0.80),
            .init(color: colour.opacity(0), location: 1),
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

    /// How far up the beam a mote is, 0 at the floor to 1 at the top.
    private static func moteRise(_ mote: Int, clock: TimeInterval, grand: CGFloat) -> CGFloat {
        let speed: Double = 0.55 + 0.30 * Double(grand)
        let phase: Double = Double(mote) * 0.618
        return CGFloat((clock * speed + phase).truncatingRemainder(dividingBy: 1))
    }

    private static func motePoint(_ mote: Int, clock: TimeInterval, grand: CGFloat,
                                  x: CGFloat, feet: CGFloat, spread: CGFloat) -> CGPoint {
        let rise: CGFloat = moteRise(mote, clock: clock, grand: grand)
        let sway: CGFloat = CGFloat(sin(Double(mote) * 2.3 + clock * 1.9))
        return CGPoint(x: x + sway * spread * 0.8, y: feet - rise * feet * 0.85)
    }

    /// A mote of light: one soft falloff, white at its heart through the
    /// element's colour to nothing (run 221: a hard white dot on a flat
    /// disc of colour read as a bullet, not as light).
    private func chargeMote(_ mote: Int, clock: TimeInterval, grand: CGFloat, colour: Color) -> some View {
        let rise: CGFloat = Self.moteRise(mote, clock: clock, grand: grand)
        let dot: CGFloat = 3 + 2 * grand + CGFloat(mote % 3)
        let fade: CGFloat = min(1, rise * 5) * (1 - rise)
        return Circle()
            .fill(RadialGradient(
                colors: [Color.white, colour.opacity(0.7), colour.opacity(0)],
                center: .center, startRadius: 0, endRadius: dot * 1.3
            ))
            .frame(width: dot * 2.6, height: dot * 2.6)
            .opacity(Double(fade))
    }

    /// `-tour-reveal-hold charge` (DEBUG only): the charge plays and never
    /// lands, so the CI can photograph the beat whatever second it shoots.
    private static var holdsCharge: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-reveal-hold"), at + 1 < args.count else { return false }
        return args[at + 1] == "charge"
        #else
        return false
        #endif
    }

    // MARK: - One at a time

    /// Landscape: the stage fills the left half and the words the right, so
    /// a short screen gives the figure its full height.
    private func single(_ result: SummonResult) -> some View {
        VStack(spacing: 0) {
            // The stage is behind this whole view (see `body`), its camera
            // offset so the figure lands on the left; the words take the right.
            HStack(spacing: 12) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                // Stars tick in one at a time, each one arriving oversized.
                HStack(spacing: 4) {
                    ForEach(0..<max(1, result.stars), id: \.self) { i in
                        Image(systemName: "star.fill")
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(
                                LinearGradient(colors: [Color(hex: "#FFF3C4"), Theme.gold, Color(hex: "#C9992F")],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                            .shadow(color: Theme.gold.opacity(0.8), radius: 6)
                            .opacity(i < shownStars ? 1 : 0)
                            .scaleEffect(i < shownStars ? 1 : 2.4)
                            .animation(.spring(response: 0.28, dampingFraction: 0.5), value: shownStars)
                    }
                }
                .frame(height: 34)

                Text(result.isAwakening ? (result.blueprint.awakening?.awakenedName ?? result.blueprint.name) : result.blueprint.name)
                    .font(Theme.display(46))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Self.nameGold)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .shadow(color: tint(for: result).opacity(0.9), radius: 14)
                    .scaleEffect(nameSlam ? 1 : 1.9)
                    .opacity(nameSlam ? 1 : 0)
                    .animation(.spring(response: 0.36, dampingFraction: 0.55), value: nameSlam)

                VStack(spacing: 6) {
                    Text(result.blueprint.epithet)
                        .font(Theme.title(15))
                        .foregroundStyle(Self.duskInk)

                    HStack(spacing: 8) {
                        ElementBadge(element: result.blueprint.element)
                        Text(result.blueprint.pantheon.displayName)
                            .font(Theme.body(11).weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(result.blueprint.pantheon.color.opacity(0.18)))
                            .foregroundStyle(result.blueprint.pantheon.color)
                    }
                    .padding(.top, 2)

                    // In the name's own gold with a hard black edge (run
                    // 221): `Theme.gold` in a gold glow measured (157,118,63)
                    // on the dusk, about 3:1, the dimmest thing on the card.
                    if result.isAwakening {
                        Text("AWAKENED")
                            .font(Theme.title(14))
                            .tracking(3.0)
                            .foregroundStyle(Self.nameGold)
                            .shadow(color: .black.opacity(0.9), radius: 1, y: 1)
                    } else if result.isNew {
                        Text("NEW")
                            .font(Theme.title(14))
                            .tracking(3.0)
                            .foregroundStyle(Self.nameGold)
                            .shadow(color: .black.opacity(0.9), radius: 1, y: 1)
                    } else {
                        // Cream on the dusk: the interface's ink-brown
                        // secondary sat on the dark sky at about 2:1.
                        Text("Duplicate — one skill levelled up")
                            .font(Theme.body(12))
                            .foregroundStyle(Self.duskInk)
                    }

                    if result.fromPity {
                        Text("Guaranteed by pity")
                            .font(Theme.body(11))
                            .foregroundStyle(Self.duskInk)
                    }
                }
                .opacity(detailsShown ? 1 : 0)
                .offset(y: detailsShown ? 0 : 10)
                .animation(.easeOut(duration: 0.3), value: detailsShown)
            }
            .frame(maxWidth: .infinity)
            }

            // On a glass plate over the lit floor of the set: bare text there
            // read as a caption lost on the stone (runs 217–221).
            Text(index + 1 < results.count ? "Tap to continue  (\(index + 1)/\(results.count))" : "Tap to finish")
                .font(Theme.body(13))
                .foregroundStyle(Theme.onGlass)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(GlassPlate(radius: 12))
                .opacity(isFullyRevealed ? 1 : 0)
                .padding(.bottom, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    // MARK: - Sequencing

    private func advance() {
        if !isFullyRevealed {
            // A tap mid-sequence finishes it now rather than being ignored.
            guard let current else { return }
            sequence += 1
            completeInstantly(current)
            return
        }
        AudioLibrary.shared.play(.uiTap)
        if index + 1 < results.count {
            index += 1
            revealNext()
        } else if results.count > 1 {
            sequence += 1
            showAll = true
        } else {
            onFinish()
        }
    }

    private func completeInstantly(_ result: SummonResult) {
        charging = false
        awaitingStage = nil
        revealed = true
        wordsFor = sequence
        shownStars = result.stars
        nameSlam = true
        detailsShown = true
        flashAt = nil
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

        charging = true
        revealed = false
        shownStars = 0
        nameSlam = false
        detailsShown = false
        wordsFor = nil
        flashAt = nil
        ambientStart = Date()
        chargeStart = nil
        chargeDuration = Self.chargeTime(stars: result.stars)

        // The next pull's figure parses on a background queue while this one
        // is on the beam, so its stage clones from the cache.
        if results.indices.contains(index + 1) {
            ModelLibrary.shared.warm([results[index + 1].blueprint.model])
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

    /// The figure has been DRAWN on the beam: the words land on it now.
    private func stageShown(_ key: String) {
        guard revealed, let current, stageKey(current) == key else { return }
        startWords(sequence)
    }

    /// Starts the charge's clock, and at its end the flash and the figure.
    /// The words wait for the figure (`stageShown`), never for a timer
    /// started here: run 221 timed them from this moment, a main thread
    /// held up behind the stage let every timer fire at once — all five
    /// star ticks inside 70 ms — and the 3-second frame was the name card
    /// over an empty dais.
    private func beginCharge(_ mine: Int) {
        guard mine == sequence, let result = current else { return }
        awaitingStage = nil
        chargeStart = Date()
        let big = result.stars >= 4
        let chargeTime = Self.chargeTime(stars: result.stars)

        AudioLibrary.shared.play(.summonCharge, volume: big ? 1.0 : 0.7)
        if Self.holdsCharge { return }

        after(chargeTime) {
            guard mine == sequence else { return }
            charging = false
            let stamp = Date()
            let span: TimeInterval = big ? 0.55 : 0.4
            flashSpan = span
            flashAt = stamp
            revealed = true
            AudioLibrary.shared.play(.summonBurst, volume: big ? 1.0 : 0.75)
            Juice.haptic(big ? .heavy : .medium)
            // Off the screen once it has faded, so nothing redraws it.
            after(span + 0.1) {
                if flashAt == stamp { flashAt = nil }
            }
            // Should the stage never say its figure has drawn, the words
            // land anyway rather than never.
            after(Self.wordsFallback) { startWords(mine) }
        }
    }

    /// The stars tick in one at a time, the name slams down, the details
    /// follow: timed from the figure's first drawn frame (or the fallback),
    /// once per sequence. The first star lands 0.3 s after the figure, as
    /// the flash clears, which is where it landed when the flash and the
    /// figure were one timer.
    private func startWords(_ mine: Int) {
        guard mine == sequence, wordsFor != mine, let result = current else { return }
        wordsFor = mine
        let stars = result.stars
        let big = stars >= 4

        let starStart: TimeInterval = 0.3
        for i in 0..<stars {
            after(starStart + Double(i) * 0.14) {
                guard mine == sequence else { return }
                shownStars = i + 1
                AudioLibrary.shared.play(.starTick, volume: 0.8)
                Juice.haptic(i == stars - 1 && big ? .medium : .light)
            }
        }

        let nameAt = starStart + Double(stars) * 0.14 + 0.12
        after(nameAt) {
            guard mine == sequence else { return }
            nameSlam = true
            if big { Juice.haptic(.heavy) }
        }
        after(nameAt + 0.28) {
            guard mine == sequence else { return }
            detailsShown = true
        }
    }

    /// The charge is longer for a high grade, on purpose. Anticipation is
    /// the reward; a 5★ should make the player wait a beat.
    private static func chargeTime(stars: Int) -> TimeInterval {
        stars >= 4 ? 1.25 : 0.8
    }

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
                    BundleImage(name: result.blueprint.model.portraitName(awakened: result.unit.isAwakened || result.isAwakening))
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
    /// figure on the beam: the reveal times its stars and its name from
    /// here, so they can never land on an empty dais.
    var onShown: (() -> Void)? = nil

    /// Where the figure's centre line stands, as a fraction of the width
    /// from the left: the camera is solved for it (`frameCamera`) and the
    /// reveal's SwiftUI charge is drawn on it.
    static let figureLine: CGFloat = 0.26

    /// How long, from the end of the build, the stage waits for its warm-up
    /// to be drawn before it comes in anyway. The CI's simulator compiled
    /// this set and figure in about two and a half seconds; a phone takes a
    /// fraction of one.
    static let warmUpLimit: TimeInterval = 4.0

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
        var onShown: (() -> Void)?
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

        /// The first frame with the figure on the beam: it settles toward the
        /// player from here, and the reveal's words are timed from here.
        func figureShown() {
            if let figure { SummonStageView.settle(figure) }
            onShown?()
        }
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
        // A three-quarter stance to open on. The turn itself waits for the
        // reveal (see `show`), and it is no longer a perpetual full spin: a
        // 16-second revolution had the character showing the player its back
        // for four seconds out of every sixteen, and the name slams down at a
        // fixed beat, so a fair share of reveals put the unit's name over its
        // shoulder blades. A model's authored facing is +Z and the camera sits
        // on +Z, so zero yaw is face-on.
        node.eulerAngles.y = -0.42

        // The summoning circle: a rune dais on a floating rock, a half-ring of
        // pillars and braziers behind the figure, mist and dust, in the
        // summoned unit's pantheon and element colour. The SwiftUI glow and
        // rays show through between the pillars.
        StageBuilder.buildSummoningCircle(pantheon: result.blueprint.pantheon, tint: tint, into: scene)

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
        scene.rootNode.addChildNode(cameraNode)
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
        let key = SCNLight()
        key.type = .directional
        key.intensity = FigureStageLighting.keyIntensity
        key.color = tint.mixed(with: .white, amount: FigureStageLighting.keyTintMix)
        // The one shadow in the scene: the figure's, deferred and soft; the
        // quads never cast (`restrictShadows`, below and in `show`).
        FigureStageLighting.castShadows(from: key)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-3, 5, 4)
        keyNode.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(keyNode)

        // Fill from the other side, cool and weak. Without one, the shadow side
        // of a dark model is crushed to the ambient and the only way to find
        // the silhouette again is to over-drive the rim — which is how the rim
        // reached 1,300 and took the temple with it. A fill is the cheaper fix
        // and it keeps the costume readable.
        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.intensity = FigureStageLighting.fillIntensity
        fillLight.color = UIColor(hex: "#7C93D6") ?? .white
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
        if revealed { show(context.coordinator) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.warmUpLimit) { [weak coordinator = context.coordinator] in
            coordinator?.giveUpWarmUp()
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onReady = onReady
        context.coordinator.onShown = onShown
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
        // The turn toward the player waits for the figure's first frame on
        // the beam (`settle`, from the coordinator's `figureShown`).

        // A slow push toward the figure over the beat the name lands on. It is
        // small — a twelfth of the distance — and it eases out, so it reads as
        // the shot settling rather than as a zoom, and it is the one camera
        // move in the reveal. Backing off along the node's own front keeps the
        // aim exactly where the solve put it, so nothing drifts on the way in.
        if let cameraNode = coordinator.cameraNode {
            let home = cameraNode.position
            let front = cameraNode.worldFront
            let back = coordinator.distance * 0.12
            cameraNode.position = SCNVector3(home.x - front.x * back,
                                             home.y - front.y * back,
                                             home.z - front.z * back)
            let push = SCNAction.move(to: home, duration: 1.7)
            push.timingMode = .easeOut
            cameraNode.runAction(push, forKey: "push")
        }
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
