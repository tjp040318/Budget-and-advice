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
    let onFinish: () -> Void

    @State private var index = 0
    @State private var showAll = false

    // The staged reveal, in order.
    @State private var charging = false
    @State private var flash: Double = 0
    @State private var revealed = false
    @State private var shownStars = 0
    @State private var nameSlam = false
    @State private var detailsShown = false
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
            if !showAll, let current {
                SummonStageView(result: current, revealed: revealed)
                    .id(current.id)
                    .ignoresSafeArea()
            }

            if showAll {
                grid
            } else if let current {
                single(current)
            }

            // The flash on reveal. White over the rarity tint, gone in half a
            // second; long enough to hide the figure popping in.
            Color.white
                .opacity(flash * 0.85)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    Button(showAll ? "Done" : "Skip") {
                        AudioLibrary.shared.play(.uiTap)
                        if showAll { onFinish() } else { sequence += 1; showAll = true }
                    }
                    .font(Theme.body(14).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(12)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { revealNext() }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Theme.backdrop

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

                // The corners go back into the dark. A landscape frame is wide
                // enough that the glow and the rays reach all four of them, and
                // a lit corner is the cheapest-looking thing in a reveal: the
                // eye is drawn to the brightest pixel, and it should be the
                // character. Centred on the figure, not on the screen, so the
                // fall-off frames the character rather than the layout.
                RadialGradient(
                    colors: [.clear, Theme.ink.opacity(0.10), Theme.ink.opacity(0.42), Theme.ink.opacity(0.82)],
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
                            .font(.system(size: 26, weight: .black))
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
                    .font(Theme.display(38))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.textPrimary, Theme.textPrimary.opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: tint(for: result).opacity(0.9), radius: 14)
                    .scaleEffect(nameSlam ? 1 : 1.9)
                    .opacity(nameSlam ? 1 : 0)
                    .animation(.spring(response: 0.36, dampingFraction: 0.55), value: nameSlam)

                VStack(spacing: 6) {
                    Text(result.blueprint.epithet)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)

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

                    if result.isAwakening {
                        Text("AWAKENED")
                            .font(Theme.body(12).weight(.black))
                            .tracking(2.4)
                            .foregroundStyle(Theme.gold)
                            .shadow(color: Theme.gold.opacity(0.9), radius: 6)
                    } else if result.isNew {
                        Text("NEW")
                            .font(Theme.body(12).weight(.black))
                            .tracking(2.4)
                            .foregroundStyle(Theme.gold)
                            .shadow(color: Theme.gold.opacity(0.9), radius: 6)
                    } else {
                        Text("Duplicate — one skill levelled up")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if result.fromPity {
                        Text("Guaranteed by pity")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .opacity(detailsShown ? 1 : 0)
                .offset(y: detailsShown ? 0 : 10)
                .animation(.easeOut(duration: 0.3), value: detailsShown)
            }
            .frame(maxWidth: .infinity)
            }

            Text(index + 1 < results.count ? "Tap to continue  (\(index + 1)/\(results.count))" : "Tap to finish")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                // Over the lit floor of the set now, not a dark gradient.
                .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
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
        revealed = true
        shownStars = result.stars
        nameSlam = true
        detailsShown = true
        flash = 0
    }

    /// The staged reveal. Every step checks it still belongs to the current
    /// sequence, so a skipped or advanced reveal cannot fire stale steps.
    private func revealNext() {
        guard let result = current else { return }
        sequence += 1
        let mine = sequence
        let stars = result.stars
        let big = stars >= 4

        charging = true
        revealed = false
        shownStars = 0
        nameSlam = false
        detailsShown = false
        flash = 0

        AudioLibrary.shared.play(.summonCharge, volume: big ? 1.0 : 0.7)

        // The charge is longer for a high grade, on purpose. Anticipation is
        // the reward; a 5★ should make the player wait a beat.
        let chargeTime: TimeInterval = big ? 1.25 : 0.8

        after(chargeTime) {
            guard mine == sequence else { return }
            charging = false
            flash = 1
            withAnimation(.easeOut(duration: big ? 0.55 : 0.4)) { flash = 0 }
            revealed = true
            AudioLibrary.shared.play(.summonBurst, volume: big ? 1.0 : 0.75)
            Juice.haptic(big ? .heavy : .medium)
        }

        let starStart = chargeTime + 0.35
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

    private func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 12) {
            Text("Summoned")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)

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
            Text(result.blueprint.name)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
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

    final class Coordinator {
        var figure: SCNNode?
        var spinnerStarted = false
        var shown = false
        var tint: UIColor = .white
        var scene: SCNScene?
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
        node.opacity = 0
        scene.rootNode.addChildNode(node)
        context.coordinator.figure = node
        context.coordinator.tint = tint
        context.coordinator.scene = scene
        // A canonical export's rest pose is its bind pose, an A-pose, so the
        // figure gets the idle clip when one is in the bundle and stands
        // still only when there is nothing to play.
        let assetName = result.blueprint.model.assetName
        if let idle = ModelLibrary.shared.animation(.idle, for: assetName)
            ?? ModelLibrary.shared.animation(.idleCombat, for: assetName) {
            node.addAnimation(idle, forKey: "idle")
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
        camera.contrast = 0.12
        camera.saturation = 1.08
        camera.vignettingIntensity = 0.32
        camera.vignettingPower = 1.15
        camera.colorFringeStrength = 0.25

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
        key.intensity = 780
        key.color = tint.mixed(with: .white, amount: 0.82)
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
        fillLight.intensity = 300
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
        rim.intensity = 520
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
        ambient.intensity = 175
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        if revealed { show(context.coordinator) }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
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
        let x = halfWidth * (1 - 2 * 0.26)
        // A push-in in flight would fight this; a re-frame only happens on a
        // real change of shape, and the framing is what matters then.
        cameraNode.removeAction(forKey: "push")
        cameraNode.position = SCNVector3(x, coordinator.cameraY, coordinator.distance)
        // A camera node looks along its own -Z, and the aim shares the camera's
        // x so that this is a pure tilt.
        cameraNode.look(at: SCNVector3(x, coordinator.aimY, 0))
    }

    /// The figure fades in on the beam, once.
    private func show(_ coordinator: Coordinator) {
        guard !coordinator.shown, let figure = coordinator.figure, let scene = coordinator.scene else { return }
        coordinator.shown = true
        figure.runAction(.sequence([.wait(duration: 0.05), .fadeIn(duration: 0.35)]))
        VFXLibrary.summonBeam(at: SCNVector3(0, 0, 0), in: scene, tint: coordinator.tint)
        addContactShadow(to: scene)

        // The figure settles out of its three-quarter stance to face the player
        // as the stars tick in, then breathes: a slow sway of a fifth of a
        // radian either way, which is enough to keep the silhouette alive
        // without ever turning the face away. A reveal is the most-looked-at
        // second in the game and a dead-still model is the tell that it is a
        // prop rather than a character.
        let settle = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 1.5, usesShortestUnitArc: true)
        settle.timingMode = .easeOut
        let swayRight = SCNAction.rotateTo(x: 0, y: 0.20, z: 0, duration: 4.5, usesShortestUnitArc: true)
        swayRight.timingMode = .easeInEaseOut
        let swayLeft = SCNAction.rotateTo(x: 0, y: -0.20, z: 0, duration: 4.5, usesShortestUnitArc: true)
        swayLeft.timingMode = .easeInEaseOut
        figure.runAction(.sequence([settle, .repeatForever(.sequence([swayRight, swayLeft]))]), forKey: "turn")

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

    /// A soft patch of shade under the feet.
    ///
    /// No light in this scene casts a shadow, and none should: a shadow-casting
    /// key would have the summoning circle's additive quads — the mist planes
    /// and the beam — throwing solid black shapes of their own across the dais.
    /// A painted patch does the one job that matters, which is to stop the
    /// figure looking pasted onto the stone. It is drawn with a real alpha
    /// channel and composited normally rather than additively, for the reason
    /// written beside this view's clear background.
    private func addContactShadow(to scene: SCNScene) {
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
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 0.05), .fadeOpacity(to: 0.8, duration: 0.4)]))
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
