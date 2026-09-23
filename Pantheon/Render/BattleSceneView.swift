import SwiftUI
import SceneKit
import SpriteKit
import UIKit

/// Bridges the SceneKit battle stage into SwiftUI, and lays the unit plates
/// over it.
///
/// The controller is created once and owned by the battle view model, not by
/// this struct — SwiftUI rebuilds `View` values constantly, and rebuilding a
/// scene graph on every layout pass would drop the battle.
///
/// The plates — every unit's health bar and attack bar — are a SpriteKit
/// scene drawn over the 3D view (`overlaySKScene`), the mechanism Apple's
/// own SceneKit samples use for a HUD, so a bar is drawn in points, as crisp
/// as the rest of the HUD and the same size in both rows. The coordinator is
/// the renderer's delegate and places them under the units' feet on every
/// frame, from the camera about to draw.
struct BattleSceneView: UIViewRepresentable {

    let controller: BattleSceneController
    /// Called with the combatant a tap landed on, for target selection.
    var onTapUnit: ((UUID) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        // The camera is directed by CameraDirector; free orbit would fight it.
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.overlaySKScene = controller.plates
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTapUnit = onTapUnit
        context.coordinator.controller = controller
        if view.scene !== controller.scene { view.scene = controller.scene }
        if view.overlaySKScene !== controller.plates { view.overlaySKScene = controller.plates }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, onTapUnit: onTapUnit)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var onTapUnit: ((UUID) -> Void)?
        weak var view: SCNView?
        weak var controller: BattleSceneController?

        init(controller: BattleSceneController, onTapUnit: ((UUID) -> Void)?) {
            self.controller = controller
            self.onTapUnit = onTapUnit
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view, let onTapUnit else { return }
            let point = recognizer.location(in: view)
            let hits = view.hitTest(point, options: [
                .boundingBoxOnly: true,
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            // Walk up from whatever geometry was hit to the owning UnitNode.
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let unitNode = current as? UnitNode {
                        onTapUnit(unitNode.combatantID)
                        return
                    }
                    node = current.parent
                }
            }
        }

        /// The clips have been applied for this frame: swing every cape on
        /// the field from the pose its figure now holds.
        func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
            ClothSimulation.shared.step(in: renderer.scene, at: time)
        }

        /// The frame is about to be drawn with the camera where it now
        /// stands: put every plate under its unit's feet for it.
        func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
            controller?.layoutPlates(in: renderer)
        }
    }
}

// MARK: - The unit plates

/// The screen-space layer of unit plates over the battle: one `UnitPlate`
/// per fighter, in points. Transparent, never touched by the player (taps go
/// through to the 3D view), sized to the view by `resizeFill`.
final class UnitPlateOverlay: SKScene {

    private var plates: [UUID: UnitPlate] = [:]
    /// Every touch of a SpriteKit node — adding a plate, a bar's new value,
    /// a status row — is queued here from the main thread and run on the
    /// render thread just before the frame is drawn (`drainPending`, from
    /// `BattleSceneController.layoutPlates`). SpriteKit's scene graph is not
    /// thread-safe, and the first arena run with the plates died mid-fight
    /// with the main thread rebuilding a status row while the renderer was
    /// placing the plates. One thread handles the graph now.
    private let pendingLock = NSLock()
    private var pending: [() -> Void] = []

    func perform(_ work: @escaping () -> Void) {
        pendingLock.lock()
        pending.append(work)
        pendingLock.unlock()
    }

    /// Runs the queued work. Called on the render thread.
    func drainPending() {
        pendingLock.lock()
        let work = pending
        pending.removeAll()
        pendingLock.unlock()
        for item in work { item() }
    }

    /// The plates' layer and, over it, the floating words and numbers'
    /// (run 220: the numbers were 3D planes drawn UNDER this overlay, so a
    /// plate covered "810!" and "373" and sat across "Red Land Blaze").
    /// Two layers so the reckoning can fade the whole field's chrome as one.
    private let plateLayer = SKNode()
    private let floatLayer = SKNode()
    /// The words and numbers in flight. Render thread only: added through
    /// `perform`, moved and retired by `BattleSceneController.layoutFloats`.
    private(set) var floats: [FloatingLabel] = []

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        isUserInteractionEnabled = false
        plateLayer.zPosition = 0
        addChild(plateLayer)
        floatLayer.zPosition = 100
        addChild(floatLayer)
    }

    required init?(coder: NSCoder) { fatalError("UnitPlateOverlay is created in code") }

    func plate(for id: UUID) -> UnitPlate? { plates[id] }

    @discardableResult
    func addPlate(for id: UUID, elementHex: String) -> UnitPlate {
        if let old = plates[id] { perform { old.removeFromParent() } }
        let plate = UnitPlate(elementHex: elementHex)
        plate.host = self
        plates[id] = plate
        perform { [weak self] in self?.plateLayer.addChild(plate) }
        return plate
    }

    /// A word or a number off a unit, over every plate. The picture is drawn
    /// by the caller; the node is made and placed on the render thread.
    func addFloat(image: UIImage, over unit: UnitNode, lift: Float, lead: CGFloat, pop: Bool, scatter: CGFloat, rise: CGFloat) {
        let anchor = unit.convertPosition(SCNVector3(0, lift, 0), to: nil)
        let born = CACurrentMediaTime()
        perform { [weak self] in
            guard let self else { return }
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            sprite.size = image.size
            sprite.alpha = 0
            let label = FloatingLabel(
                node: sprite, unit: unit, lift: lift, fallback: anchor,
                born: born, pop: pop, scatter: scatter, lead: lead, rise: rise
            )
            self.floatLayer.addChild(sprite)
            self.floats.append(label)
        }
    }

    /// Takes the finished words off the field. Render thread.
    func retireFloats(_ finished: [FloatingLabel]) {
        guard !finished.isEmpty else { return }
        for label in finished { label.node.removeFromParent() }
        floats.removeAll { label in finished.contains { $0 === label } }
    }

    func removeAllFloats() {
        perform { [weak self] in
            guard let self else { return }
            for label in self.floats { label.node.removeFromParent() }
            self.floats.removeAll()
        }
    }

    /// The whole field's chrome — every plate and every floating word —
    /// faded out while the reckoning is up (run 220: three plates showed
    /// through its scrim under the TURNS/DEALT/TAKEN tiles), and back.
    func setFieldHidden(_ hidden: Bool) {
        perform { [weak self] in
            guard let self else { return }
            for layer in [self.plateLayer, self.floatLayer] {
                layer.removeAction(forKey: "field")
                layer.run(.fadeAlpha(to: hidden ? 0 : 1, duration: 0.25), withKey: "field")
            }
        }
    }

    func removePlate(for id: UUID) {
        guard let plate = plates[id] else { return }
        plates[id] = nil
        perform { plate.removeFromParent() }
    }

    func removeAllPlates() {
        let gone = Array(plates.values)
        plates.removeAll()
        perform { for plate in gone { plate.removeFromParent() } }
    }
}

/// One floating word or number (2026-09-23, run 220), in points on the
/// overlay rather than a plane in the 3D scene: a fixed size whatever the
/// camera does — a zoom made a crit 75 points tall and ran it off the top —
/// and drawn over the plates rather than under them. Its motion is worked
/// out from its age on every frame (`BattleSceneController.layoutFloats`),
/// so the clamp to the frame can be applied to where it really is.
final class FloatingLabel {
    /// Pop, rise and fade, in seconds: the pop's overshoot and settle, then
    /// the second the 3D numbers took to rise, the last half of it fading.
    static let popTime: TimeInterval = 0.13
    static let riseTime: TimeInterval = 1.0
    static let fadeTime: TimeInterval = 0.5

    let node: SKSpriteNode
    /// The unit it came off, followed while it lives — a victim's recoil, a
    /// caster's leap — and the point it was raised from once it is gone.
    weak var unit: UnitNode?
    let lift: Float
    let fallback: SCNVector3
    let born: TimeInterval
    let pop: Bool
    /// Points sideways off the anchor, so a multi-hit reads as a burst.
    let scatter: CGFloat
    /// Points above the anchor it starts at, and how far it rises from there.
    let lead: CGFloat
    let rise: CGFloat

    init(node: SKSpriteNode, unit: UnitNode?, lift: Float, fallback: SCNVector3,
         born: TimeInterval, pop: Bool, scatter: CGFloat, lead: CGFloat, rise: CGFloat) {
        self.node = node
        self.unit = unit
        self.lift = lift
        self.fallback = fallback
        self.born = born
        self.pop = pop
        self.scatter = scatter
        self.lead = lead
        self.rise = rise
    }

    var life: TimeInterval { (pop ? FloatingLabel.popTime : 0) + FloatingLabel.riseTime }

    /// Where in the world it hangs this frame.
    var anchor: SCNVector3 {
        guard let unit else { return fallback }
        let feet = unit.worldPosition
        return SCNVector3(feet.x, feet.y + lift, feet.z)
    }

    /// The pop: from a third of its size past full and back, the genre's
    /// number landing; 1 for a word, which fades in instead.
    func scale(at age: TimeInterval) -> CGFloat {
        guard pop else { return 1 }
        let grow = 0.07
        if age < grow {
            let t = CGFloat(age / grow)
            let eased = 1 - (1 - t) * (1 - t)
            return 0.35 + (1.12 - 0.35) * eased
        }
        if age < FloatingLabel.popTime {
            let t = CGFloat((age - grow) / (FloatingLabel.popTime - grow))
            return 1.12 - 0.12 * t
        }
        return 1
    }

    /// How far it has risen, in points: eased out over the rise.
    func risen(at age: TimeInterval) -> CGFloat {
        let start = pop ? FloatingLabel.popTime : 0
        let t = CGFloat(min(1, max(0, (age - start) / FloatingLabel.riseTime)))
        return rise * (1 - (1 - t) * (1 - t))
    }

    func alpha(at age: TimeInterval) -> CGFloat {
        let fadeFrom = life - FloatingLabel.fadeTime
        if age > fadeFrom { return CGFloat(max(0, 1 - (age - fadeFrom) / FloatingLabel.fadeTime)) }
        if !pop, age < 0.1 { return CGFloat(age / 0.1) }
        return 1
    }
}

/// One fighter's bars, the genre's way — and OVER THE HEAD, where the genre
/// keeps them (2026-09-15; the owner, with Summoners War's frame beside
/// ours: "The health bars are not above the heads"). One dark rounded
/// track holding a green health bar with a gradient fill and a cream trail
/// that lingers a beat after a hit, and the thinner light-blue attack bar
/// under it that fills toward the unit's turn and turns gold when it is
/// ready; the LEVEL BADGE on the track's left end, a dark disc ringed in
/// the element's colour with the number in it, the genre's mark; the
/// status tiles above the track; the matchup arrow above those; and a gold
/// rim while the unit acts. Every size here is in points and the same in
/// both rows, which is what makes health comparable across the field and
/// the bars as crisp as the HUD.
final class UnitPlate: SKNode {

    static let barWidth: CGFloat = 66
    static let hpHeight: CGFloat = 6.5
    static let atbHeight: CGFloat = 3
    /// The gap between the two bars, and the track's padding round them.
    static let barGap: CGFloat = 1.5
    static let trackPad: CGFloat = 1.75
    static var trackHeight: CGFloat { hpHeight + barGap + atbHeight + 2 * trackPad }
    /// The track's bottom edge stands this far above the projected top of
    /// the head.
    static let riseAboveHead: CGFloat = 12
    static let tile: CGFloat = 12
    static let badgeSize: CGFloat = 19

    private let hpFill: SKSpriteNode
    private let hpMask: SKSpriteNode
    private let trailMask: SKSpriteNode
    private let atbFill: SKSpriteNode
    private let atbMask: SKSpriteNode
    private let statusRow = SKNode()
    private let badge: SKSpriteNode
    private let levelBadge: SKSpriteNode
    private let elementHex: String
    private let rim: SKSpriteNode
    private let fullTexture: SKTexture
    private let lowTexture: SKTexture
    private let atbTexture: SKTexture
    private let readyTexture: SKTexture
    private var shownFraction: CGFloat = 1
    /// The overlay this plate is on, whose queue every change goes through.
    weak var host: UnitPlateOverlay?

    init(elementHex: String) {
        let w = UnitPlate.barWidth
        let h = UnitPlate.hpHeight
        let a = UnitPlate.atbHeight
        self.elementHex = elementHex
        let full = PlateArt.fill("hp", width: w, height: h, radius: 2, top: "#9CF2B0", bottom: "#3DB868")
        let low = PlateArt.fill("hp_low", width: w, height: h, radius: 2, top: "#FFD27A", bottom: "#E0762E")
        let trail = PlateArt.fill("hp_trail", width: w, height: h, radius: 2, top: "#FFF6E6", bottom: "#E8CBA8")
        let atb = PlateArt.fill("atb", width: w, height: a, radius: 1.25, top: "#B4EEFF", bottom: "#3AA6DE")
        let ready = PlateArt.fill("atb_ready", width: w, height: a, radius: 1.25, top: "#FFF3C4", bottom: "#E8B44A")
        fullTexture = full
        lowTexture = low
        atbTexture = atb
        readyTexture = ready

        let hpFillNode = SKSpriteNode(texture: full)
        hpFillNode.size = CGSize(width: w, height: h)
        let trailFillNode = SKSpriteNode(texture: trail)
        trailFillNode.size = CGSize(width: w, height: h)
        let atbFillNode = SKSpriteNode(texture: atb)
        atbFillNode.size = CGSize(width: w, height: a)
        let badgeNode = SKSpriteNode(color: .clear, size: CGSize(width: 18, height: 18))
        badgeNode.isHidden = true
        let levelNode = SKSpriteNode(color: .clear, size: CGSize(width: UnitPlate.badgeSize, height: UnitPlate.badgeSize))
        let track = UnitPlate.trackHeight
        let rimNode = SKSpriteNode(texture: PlateArt.rim("rim_acting", width: w + 12, height: track + 8, radius: 7, hex: "#F2C75C"))
        rimNode.size = CGSize(width: w + 12, height: track + 8)
        rimNode.isHidden = true

        hpFill = hpFillNode
        hpMask = UnitPlate.mask(width: w, height: h)
        trailMask = UnitPlate.mask(width: w, height: h)
        atbFill = atbFillNode
        atbMask = UnitPlate.mask(width: w, height: a)
        badge = badgeNode
        levelBadge = levelNode
        rim = rimNode
        super.init()

        // One track for both bars, its centre on the node's origin: the
        // health bar in the upper part, the attack bar under it.
        let hpY: CGFloat = (a + UnitPlate.barGap) / 2
        let atbY: CGFloat = -(h + UnitPlate.barGap) / 2

        rim.position = .zero
        rim.zPosition = 0
        addChild(rim)

        let hpTrack = SKSpriteNode(texture: PlateArt.track("plate_track", width: w + 2 * UnitPlate.trackPad + 2, height: track, radius: 4))
        hpTrack.size = CGSize(width: w + 2 * UnitPlate.trackPad + 2, height: track)
        hpTrack.position = .zero
        hpTrack.zPosition = 1
        addChild(hpTrack)

        let trailCrop = SKCropNode()
        trailCrop.maskNode = trailMask
        trailCrop.addChild(trailFillNode)
        trailCrop.position = CGPoint(x: 0, y: hpY)
        trailCrop.zPosition = 2
        addChild(trailCrop)

        let hpCrop = SKCropNode()
        hpCrop.maskNode = hpMask
        hpCrop.addChild(hpFill)
        hpCrop.position = CGPoint(x: 0, y: hpY)
        hpCrop.zPosition = 3
        addChild(hpCrop)

        let atbCrop = SKCropNode()
        atbCrop.maskNode = atbMask
        atbCrop.addChild(atbFill)
        atbCrop.position = CGPoint(x: 0, y: atbY)
        atbCrop.zPosition = 3
        addChild(atbCrop)

        // The level badge overlaps the track's left end, the genre's way.
        levelBadge.position = CGPoint(x: -w / 2 - UnitPlate.trackPad - 3, y: 0)
        levelBadge.zPosition = 5
        addChild(levelBadge)
        applyLevel(1)

        // The status tiles stand on the track; the matchup arrow above them.
        statusRow.position = CGPoint(x: 0, y: track / 2 + 1.5 + UnitPlate.tile / 2)
        statusRow.zPosition = 4
        addChild(statusRow)

        badge.position = CGPoint(x: 0, y: track / 2 + 1.5 + UnitPlate.tile + 3 + 9)
        badge.zPosition = 4
        addChild(badge)
    }

    /// The number in the badge: the unit's level.
    func setLevel(_ level: Int) {
        later { [self] in applyLevel(level) }
    }

    private func applyLevel(_ level: Int) {
        levelBadge.texture = PlateArt.levelBadge(level: level, hex: elementHex)
    }

    required init?(coder: NSCoder) { fatalError("UnitPlate is created in code") }

    /// A crop mask anchored on the bar's left edge, so a scale in x is a fill
    /// that empties toward the left with its round ends intact.
    private static func mask(width: CGFloat, height: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(color: .white, size: CGSize(width: width, height: height + 2))
        node.anchorPoint = CGPoint(x: 0, y: 0.5)
        node.position = CGPoint(x: -width / 2, y: 0)
        return node
    }

    // MARK: State

    /// Queues a change on the overlay, or applies it at once for a plate
    /// that is not on one yet.
    private func later(_ work: @escaping () -> Void) {
        if let host { host.perform(work) } else { work() }
    }

    /// The health bar. A hit drops the fill at once and the cream trail
    /// follows after a beat, so the size of the blow is read off the bar;
    /// a heal lifts both together.
    func setHealth(_ fraction: Double, animated: Bool) {
        later { [self] in applyHealth(fraction, animated: animated) }
    }

    /// The attack bar: the fraction of the way to the unit's next turn, gold
    /// and pulsing once it is full.
    func setAttackBar(_ value: Double, animated: Bool) {
        later { [self] in applyAttackBar(value, animated: animated) }
    }

    /// The buffs and debuffs as a row of tiles over the health bar: one per
    /// kind, the longest-lasting of each, six at most. The pictures are
    /// drawn here, on the caller's thread; the row is rebuilt on the
    /// renderer's.
    func setStatuses(_ statuses: [ActiveStatus]) {
        var byKind: [StatusKind: Int] = [:]
        for status in statuses { byKind[status.kind] = max(byKind[status.kind] ?? 0, status.turnsRemaining) }
        let shown = byKind.sorted { $0.key.rawValue < $1.key.rawValue }.prefix(6)
        let images = shown.compactMap { StatusIconRenderer.image(kind: $0.key, turns: $0.value) }
        later { [self] in applyStatuses(images) }
    }

    /// The advantage arrow at the bar's right end on a player's turn.
    func setMatchup(_ matchup: Element.Matchup?) {
        let image = matchup.map { MatchupIconRenderer.image(for: $0) }
        later { [self] in applyMatchup(image) }
    }

    /// The gold rim while this unit acts.
    func setActing(_ acting: Bool) {
        later { [self] in applyActing(acting) }
    }

    /// The plate goes with its unit: out with a death, back with a revival.
    func setDefeated(_ defeated: Bool) {
        later { [self] in
            removeAction(forKey: "fade")
            run(defeated ? .fadeOut(withDuration: 0.4) : .fadeIn(withDuration: 0.3), withKey: "fade")
        }
    }

    /// A plate arriving with a later wave fades in with its unit.
    func enter(over duration: TimeInterval) {
        later { [self] in
            alpha = 0
            run(.fadeIn(withDuration: duration), withKey: "fade")
        }
    }

    // MARK: Applied on the render thread

    private func applyHealth(_ fraction: Double, animated: Bool) {
        let clamped = CGFloat(min(1, max(0, fraction)))
        // Never below a sliver while there is health at all.
        let target = fraction > 0 ? max(0.03, clamped) : 0.001
        hpMask.removeAction(forKey: "hp")
        trailMask.removeAction(forKey: "trail")
        if animated {
            let drop = SKAction.scaleX(to: target, duration: 0.18)
            drop.timingMode = .easeOut
            hpMask.run(drop, withKey: "hp")
            if target < shownFraction {
                let follow = SKAction.scaleX(to: target, duration: 0.32)
                follow.timingMode = .easeIn
                trailMask.run(.sequence([.wait(forDuration: 0.35), follow]), withKey: "trail")
            } else {
                let lift = SKAction.scaleX(to: target, duration: 0.18)
                lift.timingMode = .easeOut
                trailMask.run(lift, withKey: "trail")
            }
        } else {
            hpMask.xScale = target
            trailMask.xScale = target
        }
        hpFill.texture = clamped < 0.3 ? lowTexture : fullTexture
        shownFraction = target
    }

    private func applyAttackBar(_ value: Double, animated: Bool) {
        let target = CGFloat(min(1, max(0, value)))
        let shown = max(0.001, target)
        atbMask.removeAction(forKey: "atb")
        if animated {
            let move = SKAction.scaleX(to: shown, duration: 0.45)
            move.timingMode = .easeInEaseOut
            atbMask.run(move, withKey: "atb")
        } else {
            atbMask.xScale = shown
        }
        let ready = target >= 0.999
        atbFill.texture = ready ? readyTexture : atbTexture
        atbFill.removeAction(forKey: "pulse")
        if ready {
            atbFill.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.65, duration: 0.45),
                .fadeAlpha(to: 1.0, duration: 0.45)
            ])), withKey: "pulse")
        } else {
            atbFill.alpha = 1
        }
    }

    private func applyStatuses(_ images: [UIImage]) {
        statusRow.removeAllChildren()
        guard !images.isEmpty else { return }
        let spacing = UnitPlate.tile + 1
        let totalWidth = spacing * CGFloat(images.count - 1)
        for (index, image) in images.enumerated() {
            let tile = SKSpriteNode(texture: SKTexture(image: image))
            tile.size = CGSize(width: UnitPlate.tile, height: UnitPlate.tile)
            tile.position = CGPoint(x: -totalWidth / 2 + spacing * CGFloat(index), y: 0)
            statusRow.addChild(tile)
        }
    }

    private func applyMatchup(_ image: UIImage?) {
        guard let image else {
            badge.isHidden = true
            return
        }
        badge.texture = SKTexture(image: image)
        badge.size = CGSize(width: 18, height: 18)
        badge.isHidden = false
    }

    private func applyActing(_ acting: Bool) {
        rim.removeAction(forKey: "pulse")
        rim.isHidden = !acting
        if acting {
            rim.alpha = 1
            rim.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 0.6),
                .fadeAlpha(to: 1.0, duration: 0.6)
            ])), withKey: "pulse")
        }
    }

}

/// The plates' pictures, drawn once each with Core Graphics at 3× and kept:
/// a track, a fill, a pip and a rim.
enum PlateArt {

    private static var cache: [String: SKTexture] = [:]

    private static func texture(_ key: String, size: CGSize, draw: (CGContext, CGRect) -> Void) -> SKTexture {
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext, CGRect(origin: .zero, size: size))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    private static func color(_ hex: String) -> UIColor {
        UIColor(hex: hex) ?? .white
    }

    private static func paintGradient(_ context: CGContext, in rect: CGRect, path: CGPath, top: UIColor, bottom: UIColor) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
        }
        context.restoreGState()
    }

    /// The dark rounded track a bar sits in, with a hairline of shadow round
    /// it so it reads over a bright floor.
    static func track(_ key: String, width: CGFloat, height: CGFloat, radius: CGFloat) -> SKTexture {
        texture(key, size: CGSize(width: width, height: height)) { context, rect in
            let inner = rect.insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: inner, cornerRadius: radius).cgPath
            paintGradient(context, in: inner, path: path, top: color("#2A211A").withAlphaComponent(0.92), bottom: color("#120D09").withAlphaComponent(0.92))
            context.addPath(path)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
    }

    /// A bar's fill: a vertical gradient with a light edge along the top.
    static func fill(_ key: String, width: CGFloat, height: CGFloat, radius: CGFloat, top: String, bottom: String) -> SKTexture {
        texture(key, size: CGSize(width: width, height: height)) { context, rect in
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
            paintGradient(context, in: rect, path: path, top: color(top), bottom: color(bottom))
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            context.fill(CGRect(x: rect.minX + 1, y: rect.minY + 0.5, width: rect.width - 2, height: max(0.8, rect.height * 0.14)))
            context.restoreGState()
        }
    }

    /// The element pip at the bar's left end: a small sphere in the element's
    /// colour with a dark rim and a glint.
    static func pip(_ hex: String) -> SKTexture {
        texture("pip_\(hex)", size: CGSize(width: 10, height: 10)) { context, rect in
            let circle = rect.insetBy(dx: 0.75, dy: 0.75)
            let path = UIBezierPath(ovalIn: circle).cgPath
            let base = color(hex)
            paintGradient(context, in: circle, path: path, top: base, bottom: base.withAlphaComponent(0.6))
            context.addPath(path)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1)
            context.strokePath()
            context.setFillColor(UIColor.white.withAlphaComponent(0.55).cgColor)
            context.fillEllipse(in: CGRect(x: circle.minX + 2, y: circle.minY + 1.5, width: 2.6, height: 1.8))
        }
    }

    /// The level badge on the track's left end: a dark disc, a ring in the
    /// element's colour, the level in white with a dark edge.
    static func levelBadge(level: Int, hex: String) -> SKTexture {
        let size = UnitPlate.badgeSize
        return texture("level_\(level)_\(hex)", size: CGSize(width: size, height: size)) { context, rect in
            let disc = rect.insetBy(dx: 1.2, dy: 1.2)
            let path = UIBezierPath(ovalIn: disc).cgPath
            paintGradient(context, in: disc, path: path, top: color("#3A2F24"), bottom: color("#130E0A"))
            context.addPath(UIBezierPath(ovalIn: rect.insetBy(dx: 0.6, dy: 0.6)).cgPath)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(1)
            context.strokePath()
            context.addPath(UIBezierPath(ovalIn: rect.insetBy(dx: 1.6, dy: 1.6)).cgPath)
            context.setStrokeColor(color(hex).cgColor)
            context.setLineWidth(1.7)
            context.strokePath()
            let text = "\(level)" as NSString
            let font = UIFont.systemFont(ofSize: level >= 100 ? 7.5 : 9, weight: .heavy)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
            shadow.shadowOffset = CGSize(width: 0, height: 0.6)
            shadow.shadowBlurRadius = 0.8
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph, .shadow: shadow,
            ]
            let height = font.lineHeight
            text.draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2 - 0.3, width: rect.width, height: height), withAttributes: attributes)
        }
    }

    /// A soft gold rim round the acting unit's plate.
    static func rim(_ key: String, width: CGFloat, height: CGFloat, radius: CGFloat, hex: String) -> SKTexture {
        texture(key, size: CGSize(width: width, height: height)) { context, rect in
            let base = color(hex)
            for (inset, lineWidth, alpha) in [(2.0, 4.0, 0.16), (2.5, 2.5, 0.35), (3.0, 1.2, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
                let path = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: radius).cgPath
                context.addPath(path)
                context.setStrokeColor(base.withAlphaComponent(alpha).cgColor)
                context.setLineWidth(lineWidth)
                context.strokePath()
            }
        }
    }
}
