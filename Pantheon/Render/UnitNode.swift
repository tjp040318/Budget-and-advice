import Foundation
import SceneKit
import UIKit

/// One combatant on the 3D stage.
///
/// Owns the model, its animation state, the world-space health bar and the
/// status pips. The battle scene talks to it in game terms — "play a hit react",
/// "set health to 0.4" — and never touches SceneKit nodes directly.
final class UnitNode: SCNNode {

    let combatantID: UUID
    let spec: ModelSpec
    let side: BattleSide
    private(set) var isDefeated = false

    private let modelContainer: SCNNode
    private let healthBarRoot: SCNNode
    private let healthFill: SCNNode
    private let statusRow: SCNNode
    private let selectionRing: SCNNode
    private let elementTint: UIColor

    private var currentClip: AnimationClip = .idleCombat
    private var barWidth: CGFloat { CGFloat(spec.height) * 0.5 }

    init(combatant: Combatant, detail: ModelLibrary.DetailLevel = .high) {
        // Everything is built into locals first: Swift forbids touching `self`
        // before `super.init()`, so the scene graph is assembled here and wired
        // up immediately afterwards.
        let tint = UIColor(hex: combatant.element.accentHex) ?? .white
        let modelHeight = CGFloat(combatant.model.height)
        let barHeight = modelHeight * 0.045
        let width = modelHeight * 0.5

        let container = ModelLibrary.shared.node(
            for: combatant.model,
            archetype: combatant.archetype,
            element: combatant.element,
            detail: detail
        )

        // Health bar: a dark plate with a coloured fill that scales from its
        // left edge, parented to a billboard so it always faces the camera.
        let barRoot = SCNNode()
        let backing = SCNNode(geometry: SCNPlane(width: width, height: barHeight))
        backing.geometry?.firstMaterial = UnitNode.flatMaterial(UIColor.black.withAlphaComponent(0.65))
        barRoot.addChildNode(backing)

        let fillGeometry = SCNPlane(width: width, height: barHeight * 0.78)
        fillGeometry.firstMaterial = UnitNode.flatMaterial(
            combatant.side == .player ? UIColor(hex: "#5FD98A")! : UIColor(hex: "#E8574F")!
        )
        let fill = SCNNode(geometry: fillGeometry)
        // Pivot on the left edge so scaling shrinks toward the left.
        fill.pivot = SCNMatrix4MakeTranslation(Float(-width / 2), 0, 0)
        fill.position = SCNVector3(Float(-width / 2), 0, 0.001)
        barRoot.addChildNode(fill)

        let statuses = SCNNode()
        statuses.position = SCNVector3(0, Float(barHeight * 1.4), 0)
        barRoot.addChildNode(statuses)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        barRoot.constraints = [billboard]
        barRoot.position = SCNVector3(0, combatant.model.height * 1.16, 0)

        // Ground ring under the unit — the readable "who is this" cue.
        let ringGeometry = SCNTorus(ringRadius: modelHeight * 0.22, pipeRadius: 0.012)
        ringGeometry.firstMaterial = UnitNode.flatMaterial(tint.withAlphaComponent(0.85))
        let ring = SCNNode(geometry: ringGeometry)
        ring.position = SCNVector3(0, 0.01, 0)
        ring.opacity = 0.0

        self.combatantID = combatant.id
        self.spec = combatant.model
        self.side = combatant.side
        self.elementTint = tint
        self.modelContainer = container
        self.healthBarRoot = barRoot
        self.healthFill = fill
        self.statusRow = statuses
        self.selectionRing = ring

        super.init()

        name = "combatant_\(combatant.id.uuidString)"
        addChildNode(container)
        addChildNode(barRoot)
        addChildNode(ring)

        play(.idleCombat)
        setHealth(fraction: combatant.healthFraction, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("UnitNode is created in code") }

    // MARK: - Animation

    /// Plays a clip. Falls back to a procedural motion when the export has no
    /// animation for it, so the battle never freezes waiting on missing art.
    func play(_ clip: AnimationClip, completion: (() -> Void)? = nil) {
        guard !isDefeated || clip == .death else { completion?(); return }
        // Restarting a looping clip every frame would reset its phase, so an
        // idle that is already running is left alone.
        guard clip != currentClip || !clip.loops else { completion?(); return }
        currentClip = clip

        if let animation = ModelLibrary.shared.animation(clip, for: spec.assetName) {
            modelContainer.addAnimation(animation, forKey: clip.rawValue)
            if !clip.loops {
                let duration = animation.duration > 0 ? animation.duration : clip.fallbackDuration
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    completion?()
                    if self?.isDefeated == false { self?.play(.idleCombat) }
                }
            } else {
                completion?()
            }
            return
        }

        playProcedural(clip, completion: completion)
    }

    /// Stand-in motion built from SCNActions. Crude by design — it communicates
    /// timing and intent so combat pacing can be tuned before real animation.
    private func playProcedural(_ clip: AnimationClip, completion: (() -> Void)?) {
        modelContainer.removeAction(forKey: "clip")
        let facing: Float = side == .player ? 1 : -1

        let action: SCNAction
        switch clip {
        case .idle, .idleCombat:
            let up = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.012, z: 0, duration: 1.1)
            up.timingMode = .easeInEaseOut
            action = .repeatForever(.sequence([up, up.reversed()]))

        case .attackBasic:
            let lunge = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(facing) * 0.45, duration: 0.16)
            lunge.timingMode = .easeOut
            action = .sequence([lunge, .wait(duration: 0.12), lunge.reversed()])

        case .attackHeavy, .castRelease:
            let wind = SCNAction.rotateBy(x: -0.22, y: 0, z: 0, duration: 0.28)
            let strike = SCNAction.rotateBy(x: 0.34, y: 0, z: 0, duration: 0.1)
            let lunge = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(facing) * 0.6, duration: 0.12)
            action = .sequence([
                wind, .group([strike, lunge]), .wait(duration: 0.2),
                .group([.rotateBy(x: -0.12, y: 0, z: 0, duration: 0.2), lunge.reversed()])
            ])

        case .ultimate:
            let rise = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.35, z: 0, duration: 0.6)
            rise.timingMode = .easeOut
            let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.9)
            let slam = SCNAction.moveBy(x: 0, y: CGFloat(-spec.height) * 0.35, z: 0, duration: 0.22)
            slam.timingMode = .easeIn
            action = .sequence([rise, spin, slam, .wait(duration: 0.35)])

        case .castLoop:
            action = .repeatForever(.rotateBy(x: 0, y: 0.6, z: 0, duration: 1.5))

        case .hitReact:
            let knock = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(-facing) * 0.18, duration: 0.08)
            action = .sequence([knock, .wait(duration: 0.08), knock.reversed()])

        case .death:
            let fall = SCNAction.rotateBy(x: -.pi / 2.2, y: 0, z: 0, duration: 0.55)
            fall.timingMode = .easeIn
            action = .group([fall, .fadeOpacity(to: 0.15, duration: 0.7)])

        case .victory:
            let jump = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.18, z: 0, duration: 0.3)
            jump.timingMode = .easeOut
            action = .repeat(.sequence([jump, jump.reversed()]), count: 3)

        case .summonReveal:
            action = .sequence([
                .fadeOpacity(to: 1, duration: 0.6),
                .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1.6)
            ])
        }

        modelContainer.runAction(action, forKey: "clip") { [weak self] in
            completion?()
            guard let self, !self.isDefeated, !clip.loops else { return }
            self.playProcedural(.idleCombat, completion: nil)
        }
    }

    // MARK: - State

    func setHealth(fraction: Double, animated: Bool = true) {
        let clamped = Float(min(1, max(0, fraction)))
        let scale = SCNVector3(max(0.0001, clamped), 1, 1)
        if animated {
            let action = SCNAction.customAction(duration: 0.25) { node, elapsed in
                let t = Float(elapsed / 0.25)
                let current = node.scale.x
                node.scale = SCNVector3(current + (clamped - current) * t, 1, 1)
            }
            healthFill.runAction(action)
        } else {
            healthFill.scale = scale
        }

        // The bar shifts toward red as it empties, so a low unit is obvious
        // even in a crowded frame.
        let full = side == .player ? UIColor(hex: "#5FD98A")! : UIColor(hex: "#E8574F")!
        let danger = UIColor(hex: "#F2A03C")!
        healthFill.geometry?.firstMaterial?.diffuse.contents =
            clamped < 0.3 ? danger : full
    }

    func setHighlighted(_ highlighted: Bool) {
        selectionRing.removeAllActions()
        if highlighted {
            selectionRing.opacity = 1.0
            selectionRing.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.45, duration: 0.6),
                .fadeOpacity(to: 1.0, duration: 0.6)
            ])))
        } else {
            selectionRing.runAction(.fadeOpacity(to: 0, duration: 0.2))
        }
    }

    /// Rebuilds the little status pips above the health bar.
    func setStatuses(_ statuses: [StatusKind]) {
        statusRow.childNodes.forEach { $0.removeFromParentNode() }
        let unique = Array(Set(statuses)).sorted { $0.rawValue < $1.rawValue }.prefix(6)
        guard !unique.isEmpty else { return }

        let pip = barWidth * 0.11
        let spacing = pip * 1.25
        let totalWidth = spacing * CGFloat(unique.count - 1)

        for (index, kind) in unique.enumerated() {
            let plane = SCNPlane(width: pip, height: pip)
            plane.cornerRadius = pip / 2
            plane.firstMaterial = UnitNode.flatMaterial(
                kind.isBuff ? UIColor(hex: "#6BD8F2")! : UIColor(hex: "#F2726B")!
            )
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(
                Float(-totalWidth / 2 + spacing * CGFloat(index)), 0, 0.002
            )
            statusRow.addChildNode(node)
        }
    }

    func markDefeated() {
        guard !isDefeated else { return }
        play(.death)
        isDefeated = true
        healthBarRoot.runAction(.fadeOut(duration: 0.4))
        selectionRing.runAction(.fadeOut(duration: 0.3))
    }

    func revive(healthFraction: Double) {
        isDefeated = false
        modelContainer.removeAllActions()
        modelContainer.eulerAngles = SCNVector3Zero
        modelContainer.opacity = 1
        healthBarRoot.runAction(.fadeIn(duration: 0.3))
        setHealth(fraction: healthFraction, animated: false)
        play(.idleCombat)
    }

    /// World position for spawning a VFX or a damage number on this unit.
    func attachmentPoint(_ name: String?) -> SCNNode {
        guard let name, let found = modelContainer.childNode(withName: name, recursively: true) else {
            let fallback = SCNNode()
            fallback.position = SCNVector3(0, spec.height * 0.55, 0)
            addChildNode(fallback)
            return fallback
        }
        return found
    }

    var chestWorldPosition: SCNVector3 {
        convertPosition(SCNVector3(0, spec.height * 0.6, 0), to: nil)
    }

    var headWorldPosition: SCNVector3 {
        convertPosition(SCNVector3(0, spec.height * 1.05, 0), to: nil)
    }

    private static func flatMaterial(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        return material
    }
}
