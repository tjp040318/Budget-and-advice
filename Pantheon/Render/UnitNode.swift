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
    let element: Element
    let side: BattleSide
    private(set) var isDefeated = false
    /// The asset whose clips this unit plays: the awakened mesh's own when
    /// one has shipped, otherwise the base's.
    private let clipAsset: String

    private let modelContainer: SCNNode
    private let healthBarRoot: SCNNode
    private let healthFill: SCNNode
    private let statusRow: SCNNode
    private let selectionRing: SCNNode
    private let elementTint: UIColor

    /// Nil until the first clip plays. It used to start as `.idleCombat`, so
    /// the `play(.idleCombat)` in `init` was refused as "already running" and
    /// every unit stood in its bind pose — the A-pose in the first battle
    /// screenshots — until its first attack.
    private var currentClip: AnimationClip?
    private var barWidth: CGFloat { CGFloat(spec.height) * 0.5 }

    /// Where the unit stands between actions, captured the first time it
    /// dashes, so `returnHome` can put it back. Nil until then.
    private var homePosition: SCNVector3?
    private var homeYaw: Float = 0

    init(combatant: Combatant, detail: ModelLibrary.DetailLevel = .high) {
        // Everything is built into locals first: Swift forbids touching `self`
        // before `super.init()`, so the scene graph is assembled here and wired
        // up immediately afterwards.
        let tint = UIColor(hex: combatant.element.accentHex) ?? .white
        let modelHeight = CGFloat(combatant.model.height)
        // Wide and thick enough to read from the fixed camera five metres
        // up: the genre's bars are as wide as the figure.
        let barHeight = modelHeight * 0.07
        let width = modelHeight * 0.85

        let container = ModelLibrary.shared.node(
            for: combatant.model,
            archetype: combatant.archetype,
            element: combatant.element,
            detail: detail,
            awakened: combatant.isAwakened
        )
        if combatant.isAwakened {
            // The awakened aura: a slow rise of light in the element colour
            // from the feet, for as long as the unit stands.
            container.addParticleSystem(VFXLibrary.aura(tint: tint, scale: Float(modelHeight) / 1.9))
        }

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
        barRoot.position = SCNVector3(0, combatant.model.height * 1.12, 0)

        // Ground ring under the unit — the readable "who is this" cue.
        let ringGeometry = SCNTorus(ringRadius: modelHeight * 0.22, pipeRadius: 0.012)
        ringGeometry.firstMaterial = UnitNode.flatMaterial(tint.withAlphaComponent(0.85))
        let ring = SCNNode(geometry: ringGeometry)
        ring.position = SCNVector3(0, 0.01, 0)
        ring.opacity = 0.0

        self.combatantID = combatant.id
        self.spec = combatant.model
        self.element = combatant.element
        self.side = combatant.side
        // The clips come from the mesh on the stage: the awakened export when
        // it shipped, the base one, or the stand-in's own when the base is
        // still on the way.
        let library = ModelLibrary.shared
        if combatant.isAwakened && library.hasModel(combatant.model.awakenedAssetName) {
            self.clipAsset = combatant.model.awakenedAssetName
        } else if library.hasModel(combatant.model.assetName) {
            self.clipAsset = combatant.model.assetName
        } else {
            self.clipAsset = combatant.model.standInAsset ?? combatant.model.assetName
        }
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

    /// For the island: no health bar and no selection ring, just the figure.
    func hideBattleDecorations() {
        healthBarRoot.isHidden = true
        selectionRing.isHidden = true
    }

    // MARK: - Animation

    /// Plays a clip. Falls back to a procedural motion when the export has no
    /// animation for it, so the battle never freezes waiting on missing art.
    func play(_ clip: AnimationClip, completion: (() -> Void)? = nil) {
        guard !isDefeated || clip == .death else { completion?(); return }
        // Restarting a looping clip every frame would reset its phase, so an
        // idle that is already running is left alone.
        guard clip != currentClip || !clip.loops else { completion?(); return }
        currentClip = clip

        if let shared = ModelLibrary.shared.animation(clip, for: clipAsset) {
            // The library hands out one cached animation per clip, so the copy
            // is what gets configured for this use of it.
            let animation = (shared.copy() as? CAAnimation) ?? shared
            if clip == .death {
                // A one-shot animation is removed when it ends and the model
                // snaps back to its rest pose, which for a death means the
                // corpse stands back up in an A-pose. Hold the last frame.
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards
            }
            // Library clips run long: a 2.5 s punch against a 1.3 s contract
            // leaves the caster still winding up when the hit lands. One-shots
            // are played at the pace the engine times its hits to, but never
            // more than twice their authored speed — faster than that the
            // swing was a flicker; the contracts were lengthened instead.
            if !clip.loops, clip != .death, animation.duration > clip.fallbackDuration * 1.1 {
                animation.speed = Float(min(2.0, animation.duration / clip.fallbackDuration))
            }
            modelContainer.addAnimation(animation, forKey: clip.rawValue)
            if !clip.loops {
                let played = animation.duration > 0 ? animation.duration / Double(max(0.1, animation.speed)) : clip.fallbackDuration
                let duration = played
                if clip == .death {
                    modelContainer.runAction(.sequence([.wait(duration: duration), .fadeOpacity(to: 0.6, duration: 0.6)]))
                }
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
        // Toward the enemy line: the player's side stands at +Z and attacks
        // into -Z, the opponents the reverse.
        let facing: Float = side == .player ? -1 : 1

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

        // SceneKit calls this on its rendering thread, part-way through the
        // node's own action update. Touching the action list from in there —
        // which `playProcedural` does immediately, via `removeAction` — mutates
        // the collection SceneKit is iterating and aborts the process. Hop to
        // main before going anywhere near the scene graph.
        modelContainer.runAction(action, forKey: "clip") { [weak self] in
            DispatchQueue.main.async {
                completion?()
                guard let self, !self.isDefeated, !clip.loops else { return }
                self.playProcedural(.idleCombat, completion: nil)
            }
        }
    }

    // MARK: - Movement

    /// Closes on a victim for a melee strike: a fast dash to a stride short of
    /// it, turning to face it on the way. The genre's melee attacks all do
    /// this — a swing from four metres away reads as mime — and the unit
    /// stays there through the hits until `returnHome`.
    func dash(toward target: UnitNode, duration: TimeInterval) {
        if homePosition == nil {
            homePosition = position
            homeYaw = eulerAngles.y
        }
        let from = position
        let to = target.position
        let dx = to.x - from.x, dz = to.z - from.z
        let distance = max(0.001, (dx * dx + dz * dz).squareRoot())
        let stride = spec.height * 0.7
        let travel = max(0, distance - stride)
        let destination = SCNVector3(from.x + dx / distance * travel, from.y, from.z + dz / distance * travel)
        removeAction(forKey: "dash")
        let move = SCNAction.move(to: destination, duration: duration)
        move.timingMode = .easeInEaseOut
        // The model is authored facing +Z, so this yaw faces the victim.
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(atan2(dx, dz)), z: 0, duration: duration, usesShortestUnitArc: true)
        runAction(.group([move, turn]), forKey: "dash")
        // A leap, not a slide: the figure lifts on the way and lands on the
        // wind-up, which is what makes a closing strike read as one motion.
        let lift = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.16, z: 0, duration: duration * 0.5)
        lift.timingMode = .easeOut
        let land = SCNAction.moveBy(x: 0, y: -CGFloat(spec.height) * 0.16, z: 0, duration: duration * 0.5)
        land.timingMode = .easeIn
        modelContainer.removeAction(forKey: "hop")
        modelContainer.runAction(.sequence([lift, land]), forKey: "hop")
    }

    /// Back to the spot it stood on, facing the way it did. Nothing happens
    /// for a unit that never dashed.
    func returnHome(duration: TimeInterval) {
        guard let home = homePosition else { return }
        removeAction(forKey: "dash")
        let move = SCNAction.move(to: home, duration: duration)
        move.timingMode = .easeInEaseOut
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(homeYaw), z: 0, duration: duration, usesShortestUnitArc: true)
        runAction(.group([move, turn]), forKey: "dash")
    }

    /// A white flash over the whole model on the frame a hit lands, fading
    /// over a fifth of a second. The emission is what the tint left there,
    /// and it is put back.
    func flashHit() {
        modelContainer.enumerateHierarchy { child, _ in
            guard let materials = child.geometry?.materials else { return }
            for material in materials {
                let previous = material.emission.contents
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0
                material.emission.contents = UIColor(white: 0.8, alpha: 1)
                SCNTransaction.commit()
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.22
                material.emission.contents = previous
                SCNTransaction.commit()
            }
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
    /// What the unit is under right now, drawn as icons over its bar.
    private var activeStatuses: [ActiveStatus] = []

    /// The buffs and debuffs on a unit, as the genre shows them: a row of
    /// icons over the health bar, a blue tile for a buff and a red one for a
    /// debuff, the effect's glyph on it and the turns left in the corner.
    /// The coloured dots of the first build told the player nothing.
    func setStatuses(_ statuses: [ActiveStatus]) {
        activeStatuses = statuses
        statusRow.childNodes.forEach { $0.removeFromParentNode() }
        // One tile per kind, the longest-lasting of each, six at most.
        var byKind: [StatusKind: Int] = [:]
        for status in statuses { byKind[status.kind] = max(byKind[status.kind] ?? 0, status.turnsRemaining) }
        let shown = byKind.sorted { $0.key.rawValue < $1.key.rawValue }.prefix(6)
        guard !shown.isEmpty else { return }

        let pip = CGFloat(spec.height) * 0.16
        let spacing = pip * 1.12
        let totalWidth = spacing * CGFloat(shown.count - 1)

        for (index, entry) in shown.enumerated() {
            let plane = SCNPlane(width: pip, height: pip)
            plane.firstMaterial = UnitNode.imageMaterial(StatusIconRenderer.image(kind: entry.key, turns: entry.value))
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(
                Float(-totalWidth / 2 + spacing * CGFloat(index)), Float(pip * 0.55), 0.002
            )
            statusRow.addChildNode(node)
        }
    }

    /// A status the moment it lands, so the icon shows with the hit rather
    /// than after the turn settles.
    func applyStatus(_ kind: StatusKind, turns: Int) {
        var statuses = activeStatuses.filter { $0.kind != kind }
        statuses.append(ActiveStatus(kind: kind, turnsRemaining: turns))
        setStatuses(statuses)
    }

    func removeStatus(_ kind: StatusKind) {
        setStatuses(activeStatuses.filter { $0.kind != kind })
    }

    private static func imageMaterial(_ image: UIImage?) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        return material
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
        modelContainer.removeAnimation(forKey: AnimationClip.death.rawValue)
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

/// Draws a status tile: a rounded square in the buff or debuff colour, the
/// effect's glyph in white, the turns left in the corner. One texture per
/// kind and count, cached.
enum StatusIconRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(kind: StatusKind, turns: Int) -> UIImage? {
        let key = "\(kind.rawValue)|\(turns)"
        if let cached = cache[key] { return cached }

        let side: CGFloat = 72
        let size = CGSize(width: side, height: side)
        let fill = kind.isBuff ? UIColor(hex: "#2E8FBF") ?? .systemBlue : UIColor(hex: "#B8403A") ?? .systemRed
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            fill.setFill()
            path.fill()
            UIColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3
            path.stroke()

            let configuration = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
            if let symbol = UIImage(systemName: kind.glyph, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let box: CGFloat = 40
                let scale = min(box / max(1, symbol.size.width), box / max(1, symbol.size.height))
                let drawn = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                symbol.draw(in: CGRect(
                    x: (side - drawn.width) / 2, y: (side - drawn.height) / 2 - 3,
                    width: drawn.width, height: drawn.height
                ))
            }

            if turns > 0 {
                let label = NSAttributedString(string: "\(turns)", attributes: [
                    .font: UIFont.systemFont(ofSize: 20, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.black.withAlphaComponent(0.9),
                    .strokeWidth: -3.5,
                ])
                let textSize = label.size()
                label.draw(at: CGPoint(x: side - textSize.width - 7, y: side - textSize.height - 4))
            }
        }
        if cache.count > 200 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
