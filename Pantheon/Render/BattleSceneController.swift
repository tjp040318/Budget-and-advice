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
    private var environment: BattleEnvironment = .duatGate

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
            let ground = SCNNode(geometry: SCNFloor())
            if let floor = ground.geometry as? SCNFloor {
                floor.reflectivity = 0.08
                floor.reflectionFalloffEnd = 6
            }
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(hex: environment.fogHex)?.mixed(with: .black, amount: 0.5)
            material.roughness.contents = 0.75
            ground.geometry?.firstMaterial = material
            scene.rootNode.addChildNode(ground)
        }

        // Image-based lighting if the HDR shipped; a coloured ambient if not.
        if let iblURL = Bundle.main.url(forResource: environment.environmentMap, withExtension: "hdr")
            ?? Bundle.main.url(forResource: environment.environmentMap, withExtension: "exr") {
            scene.lightingEnvironment.contents = iblURL
            scene.lightingEnvironment.intensity = 1.6
        } else {
            scene.lightingEnvironment.contents = UIColor(hex: environment.keyLightHex)
            scene.lightingEnvironment.intensity = 0.9
        }

        scene.background.contents = UIColor(hex: environment.fogHex)?.mixed(with: .black, amount: 0.35)
        scene.fogStartDistance = 14
        scene.fogEndDistance = 42
        scene.fogColor = UIColor(hex: environment.fogHex) ?? .darkGray
        scene.fogDensityExponent = 1.4
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
        camera.fieldOfView = 45
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
        // Slightly above eye level, angled down, framing both lines.
        cameraNode.position = SCNVector3(0, 3.4, 9.4)
        cameraNode.eulerAngles = SCNVector3(-0.20, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        director = CameraDirector(cameraNode: cameraNode)
    }

    /// Positions both teams. Players face +Z from the near side; opponents face
    /// -Z from the far side, staggered so nobody is hidden behind anybody.
    private func place(combatants: [Combatant]) {
        // A 5v5 is ten characters plus a full post stack; a 1v1 can afford the
        // detailed mesh. The loader falls back to the full model when no reduced
        // export has been shipped.
        let detail = ModelLibrary.detail(forCombatantCount: combatants.count)
        for combatant in combatants {
            let node = UnitNode(combatant: combatant, detail: detail)
            node.position = position(for: combatant)
            node.eulerAngles.y = combatant.side == .player ? 0 : .pi
            scene.rootNode.addChildNode(node)
            unitNodes[combatant.id] = node
        }
    }

    private func position(for combatant: Combatant) -> SCNVector3 {
        let sideSign: Float = combatant.side == .player ? 1 : -1
        // Two ranks of two, so a four-unit team reads clearly from the camera.
        let column = Float(combatant.slot % 2)
        let rank = Float(combatant.slot / 2)
        let x = (column - 0.5) * 2.4 + (rank.truncatingRemainder(dividingBy: 2) == 0 ? 0 : 0.6)
        let z = sideSign * (2.6 + rank * 1.9)
        return SCNVector3(x, 0, z)
    }

    // MARK: - Playback

    func enqueue(_ events: [BattleEvent]) {
        queue.append(contentsOf: events)
        if !isPlaying { playNext() }
    }

    /// Drops queued animation and snaps to the end state. Used by the skip button.
    func flush(combatants: [Combatant]) {
        queue.removeAll()
        isPlaying = false
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
        present(event)

        let hold = max(0.02, event.presentationDuration / max(0.25, speedMultiplier))
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            self?.playNext()
        }
    }

    // MARK: - Presenting one event

    private func present(_ event: BattleEvent) {
        switch event {
        case .battleStart:
            for node in unitNodes.values { node.play(.idleCombat) }

        case .turnBegan(let actor, _):
            highlight(actor)

        case .turnSkipped(let actor, _):
            guard let node = unitNodes[actor] else { return }
            floatText("SKIPPED", at: node.headWorldPosition, color: UIColor(hex: "#C8C8C8")!)

        case .skillCast(let actor, _, let name, let targets, let shot, let animation, let vfx):
            guard let casterNode = unitNodes[actor] else { return }
            let targetNode = targets.first.flatMap { unitNodes[$0] }
            director?.perform(shot, on: casterNode, target: targetNode)
            casterNode.play(animation)
            floatText(name, at: casterNode.headWorldPosition, color: .white, scale: 0.7)

            // The effect lands a beat after the cast begins, matching the swing.
            let tint = UIColor(hex: casterNode.spec.auraHex) ?? .white
            let delay = animation.fallbackDuration * 0.45 / max(0.25, speedMultiplier)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                for targetID in targets {
                    guard let node = self.unitNodes[targetID] else { continue }
                    VFXLibrary.spawn(
                        vfx, at: node.chestWorldPosition, in: self.scene,
                        tint: tint, scale: node.spec.height / 1.9
                    )
                }
            }

        case .damage(_, let target, let amount, let isCritical, let isGlancing, let matchup, let remaining, _, _):
            guard let node = unitNodes[target] else { return }
            node.play(.hitReact)
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))

            let color: UIColor
            var label = "\(Int(amount.rounded()))"
            if isCritical {
                color = UIColor(hex: "#FFD24F")!
                label = "\(label)!"
                director?.shake(intensity: 0.14, duration: 0.25)
                VFXLibrary.spawn("crit", at: node.chestWorldPosition, in: scene, tint: color)
            } else if isGlancing {
                color = UIColor(hex: "#9AA3B0")!
                label = "\(label) glance"
            } else if matchup == .advantage {
                color = UIColor(hex: "#7FE8A0")!
            } else {
                color = .white
            }
            floatText(label, at: node.headWorldPosition, color: color, scale: isCritical ? 1.25 : 1.0)

        case .healed(_, let target, let amount, let remaining):
            guard let node = unitNodes[target] else { return }
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))
            floatText("+\(Int(amount.rounded()))", at: node.headWorldPosition, color: UIColor(hex: "#7FE8A0")!)
            VFXLibrary.spawn("heal", at: node.position, in: scene, tint: UIColor(hex: "#7FE8A0")!)

        case .shieldAbsorbed(let target, let amount, _):
            guard let node = unitNodes[target] else { return }
            floatText("\(Int(amount.rounded())) blocked", at: node.headWorldPosition, color: UIColor(hex: "#6BD8F2")!, scale: 0.8)

        case .statusApplied(_, let target, let kind, _):
            guard let node = unitNodes[target] else { return }
            VFXLibrary.spawn(kind.isBuff ? "buff" : "debuff", at: node.position, in: scene, tint: .white)
            floatText(kind.displayName, at: node.headWorldPosition,
                      color: kind.isBuff ? UIColor(hex: "#6BD8F2")! : UIColor(hex: "#F2726B")!, scale: 0.7)

        case .statusResisted(_, let target, _):
            guard let node = unitNodes[target] else { return }
            floatText("RESIST", at: node.headWorldPosition, color: UIColor(hex: "#C8C8C8")!, scale: 0.8)

        case .statusExpired, .statusRemoved, .cooldownStarted, .attackBarChanged:
            break

        case .counterattack(let actor, _):
            guard let node = unitNodes[actor] else { return }
            floatText("COUNTER", at: node.headWorldPosition, color: UIColor(hex: "#FFD24F")!, scale: 0.9)
            node.play(.attackBasic)

        case .extraTurnGranted(let actor, _):
            guard let node = unitNodes[actor] else { return }
            floatText("EXTRA TURN", at: node.headWorldPosition, color: UIColor(hex: "#FFD24F")!, scale: 0.9)

        case .passiveTriggered(let actor, let name):
            guard let node = unitNodes[actor] else { return }
            floatText(name, at: node.headWorldPosition, color: UIColor(hex: "#E8C86A")!, scale: 0.9)
            VFXLibrary.spawn("stormlord_surge", at: node.position, in: scene, tint: UIColor(hex: "#E8C86A")!)

        case .revived(let target, _):
            unitNodes[target]?.revive(healthFraction: 0.3)

        case .defeated(let target):
            unitNodes[target]?.markDefeated()

        case .battleEnded(let result):
            director?.returnHome()
            for (_, node) in unitNodes where !node.isDefeated {
                if (result.outcome == .victory && node.side == .player)
                    || (result.outcome == .defeat && node.side == .opponent) {
                    node.play(.victory)
                }
            }
        }
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

    private func floatText(_ text: String, at position: SCNVector3, color: UIColor, scale: CGFloat = 1.0) {
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
        node.position = SCNVector3(position.x, position.y + 0.25, position.z)
        node.renderingOrder = 1_000
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        node.constraints = [billboard]
        scene.rootNode.addChildNode(node)

        let rise = SCNAction.moveBy(x: 0, y: 1.1, z: 0, duration: 1.0)
        rise.timingMode = .easeOut
        node.runAction(.sequence([
            .group([rise, .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.5)])]),
            .removeFromParentNode()
        ]))
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
