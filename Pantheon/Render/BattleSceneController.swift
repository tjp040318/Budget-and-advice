import Foundation
import SceneKit
import UIKit

protocol BattleSceneDelegate: AnyObject {
    /// Called as each event begins presenting, so the HUD stays in step with
    /// what is on screen rather than with what the engine already decided.
    func battleScene(_ controller: BattleSceneController, willPresent event: BattleEvent)
    /// Called when the queue drains.
    func battleSceneDidFinishPlayback(_ controller: BattleSceneController)
}

/// Owns the 3D battle: the stage, the lighting, the units, and the playback of
/// the engine's event stream.
///
/// The engine has already decided everything by the time this runs. Playback is
/// pure presentation, which is why a battle can be fast-forwarded, skipped or
/// replayed without the outcome changing.
final class BattleSceneController: NSObject {

    let scene = SCNScene()
    weak var delegate: BattleSceneDelegate?

    /// 1.0 is normal, 2.0 is the fast-forward toggle, 4.0 is "skip animation".
    var speedMultiplier: Double = 1.0

    private(set) var unitNodes: [UUID: UnitNode] = [:]
    private var cameraNode = SCNNode()
    private var director: CameraDirector?
    private var queue: [BattleEvent] = []
    private var isPlaying = false
    /// Bumped by flush(). A playNext continuation scheduled before the flush
    /// compares its captured value and steps aside, instead of draining an
    /// empty queue and reporting "finished" a second time — which in auto-battle
    /// would take a second turn.
    private var playbackGeneration = 0
    private(set) var environment: BattleEnvironment = .duatGate
    /// The clip of the most recent cast, so its hits know how hard to land.
    private var lastCastClip: AnimationClip = .attackBasic

    // MARK: - Setup

    func build(combatants: [Combatant], environment: BattleEnvironment) {
        self.environment = environment
        scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        unitNodes.removeAll()

        buildStage()
        buildLighting()
        buildCamera()
        registerMaxHealth(combatants)
        place(combatants: combatants)
    }

    private func buildStage() {
        // A real environment scene wins; otherwise a clean procedural platform,
        // which is enough to read positions and shadows correctly.
        if let url = Bundle.main.url(
            forResource: environment.sceneName, withExtension: "scn", subdirectory: "Environments"
        ) ?? Bundle.main.url(forResource: environment.sceneName, withExtension: "scn"),
           let loaded = try? SCNScene(url: url, options: nil) {
            for child in loaded.rootNode.childNodes {
                scene.rootNode.addChildNode(child)
            }
        } else {
            // A finite stage, not an infinite floor. The camera looks down at
            // 39°, and an infinite plane would fill the whole frame; a 30 × 10 m
            // platform whose far edge fades out leaves the painting visible
            // above the enemy line, which is the diorama the genre is.
            let platform = SCNPlane(width: 30, height: 10)
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(hex: environment.fogHex)?.mixed(with: .black, amount: 0.5)
            material.roughness.contents = 0.75
            material.transparent.contents = Self.floorFade
            material.transparencyMode = .aOne
            material.writesToDepthBuffer = true
            platform.firstMaterial = material
            let ground = SCNNode(geometry: platform)
            ground.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            ground.position = SCNVector3(0, 0, 0)
            scene.rootNode.addChildNode(ground)
        }

        // Image-based lighting if the HDR shipped; a coloured ambient if not.
        if let iblURL = Bundle.main.url(forResource: environment.environmentMap, withExtension: "hdr")
            ?? Bundle.main.url(forResource: environment.environmentMap, withExtension: "exr") {
            scene.lightingEnvironment.contents = iblURL
            scene.lightingEnvironment.intensity = 1.6
        } else {
            // A flat colour as the lighting environment lights every surface
            // uniformly in that colour, which is what washed the whole stage
            // green. It is a stand-in until a real .hdr ships, so keep it weak
            // enough to be ambient fill and let the three real lights shape the
            // figure.
            scene.lightingEnvironment.contents = UIColor(hex: environment.keyLightHex)
            scene.lightingEnvironment.intensity = 0.35
        }

        // A painted backdrop if the art shipped, otherwise the fog colour. One
        // 2048x2048 image per stage replaces the flat void behind the fighters,
        // which is the single largest visual difference between this and a
        // finished game — see Docs/ART_PIPELINE.md for the prompts.
        //
        // SceneKit stretches a background image over the viewport. On a phone
        // that turned a square painting into a tall thin one, so it is cropped
        // to the screen's aspect first, keeping the centre.
        if let backdrop = UIImage(named: "\(environment.sceneName)_bg") {
            scene.background.contents = Self.cropped(backdrop, toAspectOf: UIScreen.main.bounds.size)
        } else {
            scene.background.contents = UIColor(hex: environment.fogHex)?
                .mixed(with: .black, amount: 0.35)
        }
        scene.fogStartDistance = 16
        scene.fogEndDistance = 44
        scene.fogColor = UIColor(hex: environment.fogHex) ?? .darkGray
        scene.fogDensityExponent = 1.4
    }

    /// Opaque over the near three-quarters of the stage, fading to nothing at
    /// the far edge, so the platform dissolves into the backdrop instead of
    /// ending in a hard line. The image's top row maps to the plane's far edge.
    private static let floorFade: UIImage = {
        let size = CGSize(width: 4, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            for row in 0..<Int(size.height) {
                let fromTop = CGFloat(row) / size.height
                let alpha = min(1, max(0, (fromTop - 0.04) / 0.30))
                context.cgContext.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                context.cgContext.fill(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 1))
            }
        }
    }()

    /// The centre of `image` at the aspect ratio of `size`.
    static func cropped(_ image: UIImage, toAspectOf size: CGSize) -> UIImage {
        guard size.width > 0, size.height > 0, let cg = image.cgImage else { return image }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let target = size.width / size.height
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > target {
            rect.size.width = height * target
            rect.origin.x = (width - rect.size.width) / 2
        } else {
            rect.size.height = width / target
            rect.origin.y = (height - rect.size.height) / 2
        }
        guard let piece = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: piece, scale: image.scale, orientation: image.imageOrientation)
    }

    private func buildLighting() {
        // Key: a shadow-casting directional light from the front-left.
        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(hex: environment.keyLightHex) ?? .white
        key.intensity = 1_400
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        key.shadowColor = UIColor.black.withAlphaComponent(0.55)
        key.maximumShadowDistance = 30
        key.automaticallyAdjustsShadowProjection = true

        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-6, 10, 6)
        keyNode.eulerAngles = SCNVector3(-0.85, -0.6, 0)
        scene.rootNode.addChildNode(keyNode)

        // Fill: cool, opposite side, no shadow — keeps dark models readable.
        let fill = SCNLight()
        fill.type = .directional
        fill.color = UIColor(hex: "#7F9BD8") ?? .blue
        fill.intensity = 450
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(7, 5, -5)
        fillNode.eulerAngles = SCNVector3(-0.5, 2.3, 0)
        scene.rootNode.addChildNode(fillNode)

        // Ambient floor so nothing goes fully black.
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(hex: environment.fogHex)?.mixed(with: .white, amount: 0.3)
        ambient.intensity = 260
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private func buildCamera() {
        let camera = SCNCamera()
        // Solved numerically for a landscape phone (852 × 393 points) with the
        // HUD's single top row and the bottom bar's two ends taken off: the
        // near player rank's feet land at 84% of the screen height and its
        // heads at 50%, so a figure is a third of the screen tall the way the
        // genre frames them; the near enemy rank's feet at 52% and heads at
        // 27%, the far rank's heads at 22%, all below the top row; the far
        // player column at 64% of the width. The previous portrait solve
        // (44°, 8.75 m up, 39° down) put the enemy heads under the strip.
        camera.fieldOfView = 35
        camera.zNear = 0.1
        camera.zFar = 120
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.55
        camera.bloomThreshold = 0.85
        camera.bloomBlurRadius = 14
        camera.colorFringeStrength = 0.6
        camera.vignettingIntensity = 0.35
        camera.vignettingPower = 1.2
        camera.screenSpaceAmbientOcclusionIntensity = 0.6
        camera.screenSpaceAmbientOcclusionRadius = 0.6
        camera.motionBlurIntensity = 0.25

        cameraNode = SCNNode()
        cameraNode.camera = camera
        // Lower and shallower than the portrait camera was: a wide frame looks
        // across the stage rather than down at it.
        cameraNode.position = SCNVector3(0, 5.5, 9.75)
        cameraNode.eulerAngles = SCNVector3(-0.419, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        director = CameraDirector(cameraNode: cameraNode)
    }

    /// Positions both teams. The camera sits on the +Z side, so the player's
    /// line stands nearest it at +Z and faces away, toward the enemies at -Z,
    /// who face +Z — toward the player and the camera. A model's authored
    /// facing is +Z (Docs/ART_PIPELINE.md), hence the half-turn on the near
    /// side. Ranks are staggered so nobody is hidden behind anybody.
    private func place(combatants: [Combatant]) {
        // A 5v5 is ten characters plus a full post stack; a 1v1 can afford the
        // detailed mesh. The loader falls back to the full model when no reduced
        // export has been shipped.
        let detail = ModelLibrary.detail(forCombatantCount: combatants.count)
        for combatant in combatants {
            let node = UnitNode(combatant: combatant, detail: detail)
            node.position = position(for: combatant)
            node.eulerAngles.y = combatant.side == .player ? .pi : 0
            scene.rootNode.addChildNode(node)
            unitNodes[combatant.id] = node
        }
    }

    private func position(for combatant: Combatant) -> SCNVector3 {
        let sideSign: Float = combatant.side == .player ? 1 : -1
        // Two ranks of two, so a four-unit team reads clearly from the camera.
        // A landscape frame has the width to spare, so columns sit 2.6 m apart
        // and ranks 1.6 m deep. Both sides' back ranks stand FURTHER from the
        // camera than their front ranks — smaller and higher on screen — and
        // are staggered by HALF a column, so the third unit stands in the gap
        // between the front pair rather than behind one of them. The first
        // landscape frames had the player's back rank nearer the camera than
        // the front, so its feet ran off the bottom edge; the next had it
        // half a metre off the front unit's shoulder, which from a camera 24°
        // above the floor put Zeus behind Anubis with only his robe showing.
        let column = Float(combatant.slot % 2)
        let rank = Float(combatant.slot / 2)
        let x = (column - 0.5) * 2.6 + (rank.truncatingRemainder(dividingBy: 2) == 0 ? 0 : 1.3)
        let depth = combatant.side == .player ? (2.2 - rank * 1.6) : (2.2 + rank * 1.6)
        let z = sideSign * depth
        return SCNVector3(x, 0, z)
    }

    // MARK: - Playback

    func enqueue(_ events: [BattleEvent]) {
        queue.append(contentsOf: events)
        if !isPlaying { playNext() }
    }

    /// Drops queued animation and snaps to the end state. Used by the skip button.
    func flush(combatants: [Combatant]) {
        playbackGeneration += 1
        queue.removeAll()
        isPlaying = false
        Juice.release(scene)
        sync(combatants: combatants)
        delegate?.battleSceneDidFinishPlayback(self)
    }

    /// Forces every node to match engine truth. Called after a skip and at the
    /// end of each turn, so a dropped animation can never desync the display.
    func sync(combatants: [Combatant]) {
        for combatant in combatants {
            guard let node = unitNodes[combatant.id] else { continue }
            node.setHealth(fraction: combatant.healthFraction, animated: false)
            node.setStatuses(combatant.statuses.map(\.kind))
            if !combatant.isAlive { node.markDefeated() }
        }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            director?.returnHome()
            delegate?.battleSceneDidFinishPlayback(self)
            return
        }

        isPlaying = true
        let event = queue.removeFirst()
        delegate?.battleScene(self, willPresent: event)
        let frozen = present(event)

        // A freeze-frame steals time from the event's hold; give it back so the
        // cadence between hits stays what the event durations say it is.
        let hold = max(0.02, event.presentationDuration / max(0.25, speedMultiplier)) + frozen
        let generation = playbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.playNext()
        }
    }

    // MARK: - Presenting one event

    /// Returns how long the world froze for this event, if it did.
    @discardableResult
    private func present(_ event: BattleEvent) -> TimeInterval {
        switch event {
        case .battleStart:
            for node in unitNodes.values { node.play(.idleCombat) }

        case .turnBegan(let actor, _):
            highlight(actor)

        case .turnSkipped(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("SKIPPED", at: node.headWorldPosition, color: UIColor(hex: "#C8C8C8")!)

        case .skillCast(let actor, _, let name, let targets, let shot, let animation, let vfx):
            guard let casterNode = unitNodes[actor] else { return 0 }
            let targetNode = targets.first.flatMap { unitNodes[$0] }
            lastCastClip = animation
            Juice.prepareHaptics()
            AudioLibrary.shared.play(.whoosh, volume: animation == .ultimate ? 1.0 : 0.6)
            director?.perform(shot, on: casterNode, target: targetNode)
            casterNode.play(animation)
            floatText(name, at: casterNode.headWorldPosition, color: .white, scale: 0.7)

            // The effect lands a beat after the cast begins, matching the swing.
            let tint = UIColor(hex: casterNode.spec.auraHex) ?? .white
            let delay = animation.fallbackDuration * 0.45 / max(0.25, speedMultiplier)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                // Lightning has its own sound; everything else lands on the
                // hit sound `Juice` picks from the damage that follows.
                if vfx == "thunderbolt" || vfx == "thunderclap" || vfx == "keraunos" {
                    AudioLibrary.shared.play(.thunder, volume: vfx == "keraunos" ? 1.0 : 0.7)
                }
                for targetID in targets {
                    guard let node = self.unitNodes[targetID] else { continue }
                    VFXLibrary.spawn(
                        vfx, at: node.chestWorldPosition, in: self.scene,
                        tint: tint, scale: node.spec.height / 1.9
                    )
                }
            }

        case .damage(_, let target, let amount, let isCritical, let isGlancing, let matchup, let remaining, _, _):
            guard let node = unitNodes[target] else { return 0 }
            node.play(.hitReact)
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))

            // How hard did that land? Lethal beats critical beats the clip.
            let weight: HitWeight
            if remaining <= 0 {
                weight = .lethal
            } else if isCritical {
                weight = .critical
            } else if lastCastClip == .ultimate || lastCastClip == .attackHeavy || lastCastClip == .castRelease {
                weight = .heavy
            } else if isGlancing {
                weight = .light
            } else {
                weight = .normal
            }
            let profile = Juice.profile(for: weight)

            let color: UIColor
            var label = "\(Int(amount.rounded()))"
            if isCritical {
                color = UIColor(hex: "#FFD24F")!
                label = "\(label)!"
                VFXLibrary.spawn("crit", at: node.chestWorldPosition, in: scene, tint: color)
            } else if isGlancing {
                color = UIColor(hex: "#9AA3B0")!
                label = "\(label) glance"
            } else if matchup == .advantage {
                color = UIColor(hex: "#7FE8A0")!
            } else {
                color = .white
            }
            floatText(label, at: node.headWorldPosition, color: color, scale: profile.numberScale, pop: true)

            return Juice.impact(weight, scene: scene, director: director, speed: speedMultiplier)

        case .healed(_, let target, let amount, let remaining):
            guard let node = unitNodes[target] else { return 0 }
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))
            floatText("+\(Int(amount.rounded()))", at: node.headWorldPosition, color: UIColor(hex: "#7FE8A0")!)
            VFXLibrary.spawn("heal", at: node.position, in: scene, tint: UIColor(hex: "#7FE8A0")!)

        case .shieldAbsorbed(let target, let amount, _):
            guard let node = unitNodes[target] else { return 0 }
            floatText("\(Int(amount.rounded())) blocked", at: node.headWorldPosition, color: UIColor(hex: "#6BD8F2")!, scale: 0.8)

        case .statusApplied(_, let target, let kind, _):
            guard let node = unitNodes[target] else { return 0 }
            VFXLibrary.spawn(kind.isBuff ? "buff" : "debuff", at: node.position, in: scene, tint: .white)
            floatText(kind.displayName, at: node.headWorldPosition,
                      color: kind.isBuff ? UIColor(hex: "#6BD8F2")! : UIColor(hex: "#F2726B")!, scale: 0.7)

        case .statusResisted(_, let target, _):
            guard let node = unitNodes[target] else { return 0 }
            floatText("RESIST", at: node.headWorldPosition, color: UIColor(hex: "#C8C8C8")!, scale: 0.8)

        case .statusExpired, .statusRemoved, .cooldownStarted, .attackBarChanged:
            break

        case .counterattack(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("COUNTER", at: node.headWorldPosition, color: UIColor(hex: "#FFD24F")!, scale: 0.9)
            node.play(.attackBasic)

        case .extraTurnGranted(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("EXTRA TURN", at: node.headWorldPosition, color: UIColor(hex: "#FFD24F")!, scale: 0.9)

        case .passiveTriggered(let actor, let name):
            guard let node = unitNodes[actor] else { return 0 }
            floatText(name, at: node.headWorldPosition, color: UIColor(hex: "#E8C86A")!, scale: 0.9)
            VFXLibrary.spawn("stormlord_surge", at: node.position, in: scene, tint: UIColor(hex: "#E8C86A")!)

        case .revived(let target, _):
            unitNodes[target]?.revive(healthFraction: 0.3)

        case .defeated(let target):
            unitNodes[target]?.markDefeated()

        case .battleEnded(let result):
            director?.returnHome()
            Juice.notify(result.outcome == .victory ? .success : .error)
            AudioLibrary.shared.play(result.outcome == .victory ? .victory : .defeat)
            for (_, node) in unitNodes where !node.isDefeated {
                if (result.outcome == .victory && node.side == .player)
                    || (result.outcome == .defeat && node.side == .opponent) {
                    node.play(.victory)
                }
            }
        }
        return 0
    }

    /// The engine reports absolute remaining health; the node only knows its
    /// own geometry, so the caller converts. Kept in one place to avoid drift.
    private var maxHealthByUnit: [UUID: Double] = [:]

    func registerMaxHealth(_ combatants: [Combatant]) {
        for combatant in combatants { maxHealthByUnit[combatant.id] = combatant.maxHealth }
    }

    private func healthFraction(remaining: Double, node: UnitNode) -> Double {
        guard let maxHealth = maxHealthByUnit[node.combatantID], maxHealth > 0 else { return 1 }
        return remaining / maxHealth
    }

    private func highlight(_ actorID: UUID) {
        for (id, node) in unitNodes { node.setHighlighted(id == actorID) }
    }

    // MARK: - Floating text

    private func floatText(_ text: String, at position: SCNVector3, color: UIColor, scale: CGFloat = 1.0, pop: Bool = false) {
        guard let image = FloatingTextRenderer.image(text: text, color: color) else { return }

        let width = CGFloat(0.02) * image.size.width * scale
        let height = CGFloat(0.02) * image.size.height * scale
        let plane = SCNPlane(width: width, height: height)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .alpha
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        // Damage numbers scatter a little sideways so a multi-hit reads as a
        // burst rather than a stack of identical labels.
        let scatter: Float = pop ? Float.random(in: -0.22...0.22) : 0
        node.position = SCNVector3(position.x + scatter, position.y + 0.25, position.z)
        node.renderingOrder = 1_000
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        node.constraints = [billboard]
        scene.rootNode.addChildNode(node)

        let rise = SCNAction.moveBy(x: 0, y: 1.1, z: 0, duration: 1.0)
        rise.timingMode = .easeOut
        let drift = SCNAction.sequence([
            .group([rise, .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.5)])]),
            .removeFromParentNode()
        ])
        if pop {
            // The plane is authored at final size; start small and let the pop
            // overshoot and settle before the drift takes over.
            node.scale = SCNVector3(0.35, 0.35, 0.35)
            node.runAction(.sequence([Juice.popAction(scale: 1.0), drift]))
        } else {
            node.runAction(drift)
        }
    }
}

/// Renders damage numbers and skill names to a texture.
///
/// SCNText produces real geometry, which is expensive and hard to read at small
/// sizes. A rasterised label with a stroke stays legible against any background
/// and costs one texture per string, which is cached.
enum FloatingTextRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(text: String, color: UIColor) -> UIImage? {
        let key = "\(text)|\(color.hashValue)"
        if let cached = cache[key] { return cached }

        let font = UIFont.systemFont(ofSize: 44, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .strokeColor: UIColor.black,
            .strokeWidth: -4.0
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        guard size.width > 0, size.height > 0 else { return nil }

        let padded = CGSize(width: size.width + 16, height: size.height + 12)
        let renderer = UIGraphicsImageRenderer(size: padded)
        let image = renderer.image { _ in
            string.draw(at: CGPoint(x: 8, y: 6))
        }

        // Bound the cache: strings are mostly numbers and repeat heavily, but a
        // long battle should not grow it without limit.
        if cache.count > 400 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
