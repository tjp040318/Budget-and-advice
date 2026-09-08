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
                    .padding(16)
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
                // and only become visible on the reveal.
                if current.stars >= 4 {
                    AngularGradient(
                        colors: [tint.opacity(0.0), tint.opacity(0.35), tint.opacity(0.0),
                                 tint.opacity(0.35), tint.opacity(0.0), tint.opacity(0.35),
                                 tint.opacity(0.0), tint.opacity(0.35), tint.opacity(0.0)],
                        center: .center
                    )
                    .scaleEffect(2.4)
                    .rotationEffect(.degrees(rays))
                    .opacity(revealed ? 1 : 0)
                    .blendMode(.plusLighter)
                    .ignoresSafeArea()
                    .onAppear {
                        withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                            rays = 360
                        }
                    }
                }

                // The glow behind the figure: gathers during the charge, blooms
                // on the reveal.
                RadialGradient(
                    colors: [tint.opacity(revealed ? 0.55 : (charging ? 0.22 : 0)), .clear],
                    center: .init(x: 0.5, y: 0.42),
                    startRadius: 0,
                    endRadius: revealed ? 360 : 140
                )
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.5), value: revealed)
                .animation(.easeInOut(duration: 0.9), value: charging)
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
            HStack(spacing: 12) {
            SummonStageView(result: result)
                .id(result.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed ? 1 : 0.7)
                .animation(.spring(response: 0.5, dampingFraction: 0.68), value: revealed)

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

                Text(result.blueprint.name)
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

                    if result.isNew {
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
                .foregroundStyle(Theme.textSecondary)
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
        VStack(spacing: 16) {
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
                if BundleImage.exists(result.blueprint.model.portraitName) {
                    BundleImage(name: result.blueprint.model.portraitName)
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

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true

        let tint = UIColor(hex: result.blueprint.model.auraHex) ?? .white
        let height = result.blueprint.model.height

        let node = ModelLibrary.shared.node(
            for: result.blueprint.model,
            archetype: result.blueprint.archetype,
            element: result.blueprint.element
        )
        node.position = SCNVector3(0, 0, 0)
        node.opacity = 0
        scene.rootNode.addChildNode(node)
        // A canonical export's rest pose is its bind pose, an A-pose, so the
        // figure gets the idle clip when one is in the bundle and stands
        // still only when there is nothing to play.
        let assetName = result.blueprint.model.assetName
        if let idle = ModelLibrary.shared.animation(.idle, for: assetName)
            ?? ModelLibrary.shared.animation(.idleCombat, for: assetName) {
            node.addAnimation(idle, forKey: "idle")
        }
        // Fade in, then a slow perpetual turn — enough to show the model is
        // three-dimensional, not so fast the player never sees the face.
        node.runAction(.sequence([
            .wait(duration: 0.1),
            .fadeIn(duration: 0.35),
        ]))
        node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 16)))

        // A summoning circle under the feet: an additive tinted disc.
        let disc = SCNPlane(width: CGFloat(height) * 1.3, height: CGFloat(height) * 1.3)
        disc.cornerRadius = CGFloat(height) * 0.65
        let discMaterial = SCNMaterial()
        discMaterial.lightingModel = .constant
        discMaterial.diffuse.contents = tint.withAlphaComponent(0.35)
        discMaterial.blendMode = .add
        discMaterial.writesToDepthBuffer = false
        disc.firstMaterial = discMaterial
        let discNode = SCNNode(geometry: disc)
        discNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        discNode.position = SCNVector3(0, 0.01, 0)
        discNode.opacity = 0
        scene.rootNode.addChildNode(discNode)
        discNode.runAction(.sequence([.wait(duration: 0.1), .fadeIn(duration: 0.5)]))
        discNode.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: .pi * 2, duration: 9)))

        // Frame the figure: the camera looks at its chest from slightly above
        // and close enough that it fills most of the view.
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.wantsHDR = true
        // No exposure adaptation: on a black stage it meters the dark and
        // pushes the exposure up, and a gold character (Sekhmet) went white.
        // These lights were tuned on a black jackal; a bright figure needs
        // less rim and a higher bloom threshold to keep its texture.
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.6
        camera.bloomThreshold = 0.82
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, height * 0.52, height * 2.05)
        cameraNode.eulerAngles = SCNVector3(-0.04, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        // Key from the front-left in the element's colour.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1_050
        key.color = tint.mixed(with: .white, amount: 0.5)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-3, 5, 4)
        keyNode.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(keyNode)

        // Rim from behind, strongly tinted, for a lit silhouette edge.
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 1_300
        rim.color = tint
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(2, 4, -5)
        rimNode.eulerAngles = SCNVector3(-0.5, 2.6, 0)
        scene.rootNode.addChildNode(rimNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 240
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        VFXLibrary.summonBeam(at: SCNVector3(0, 0, 0), in: scene, tint: tint)

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
