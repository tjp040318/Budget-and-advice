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
/// the renderer's delegate and stands them over the units' heads on every
/// frame, from the camera about to draw.
struct BattleSceneView: UIViewRepresentable {

    let controller: BattleSceneController
    /// Called with the combatant a tap landed on, for target selection.
    var onTapUnit: ((UUID) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let view = BattleStageView()
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
        (view as? BattleStageView)?.reportSafeArea()
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
        /// stands: stand every plate over its unit's head for it.
        func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
            controller?.layoutPlates(in: renderer)
        }
    }
}

/// The battle's view, which tells the plate overlay where the phone's
/// unsafe edges are. The view runs under the notch and the home indicator
/// (`BattleView` ignores the safe area for it) while the HUD sits inside
/// them, so a word held "eight points inside the frame" sat in the notch's
/// inset, and a number whose unit was off the bottom of a skill zoom landed
/// on the gear (run 221, "542 blocked"). Read on the main thread, where
/// UIKit wants it, and handed to the overlay's render-thread queue.
final class BattleStageView: SCNView {
    private var reported: UIEdgeInsets?
    private weak var reportedTo: UnitPlateOverlay?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportSafeArea()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        reportSafeArea()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportSafeArea()
    }

    /// The window's insets: this view fills the window, and a view SwiftUI
    /// lays out past the safe area is not guaranteed to be told its own.
    func reportSafeArea() {
        guard let overlay = overlaySKScene as? UnitPlateOverlay else { return }
        let insets = window?.safeAreaInsets ?? safeAreaInsets
        guard insets != reported || overlay !== reportedTo else { return }
        reported = insets
        reportedTo = overlay
        overlay.setSafeArea(insets)
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
    /// The plates themselves, inside `plateLayer`, dimmed while a cut-in's
    /// band is up (`setPlatesDimmed`). A node of its own, so the band's dim
    /// and the reckoning's fade (`setFieldHidden`) never undo each other.
    private let dimLayer = SKNode()
    /// The words and numbers in flight. Render thread only: added through
    /// `perform`, moved and retired by `BattleSceneController.layoutFloats`.
    private(set) var floats: [FloatingLabel] = []

    /// The view's unsafe edges, in the overlay's points (`BattleStageView`
    /// reports them from the main thread). Render thread only.
    private(set) var safeArea: UIEdgeInsets = .zero

    func setSafeArea(_ insets: UIEdgeInsets) {
        perform { [weak self] in self?.safeArea = insets }
    }

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        isUserInteractionEnabled = false
        plateLayer.zPosition = 0
        addChild(plateLayer)
        plateLayer.addChild(dimLayer)
        floatLayer.zPosition = 100
        addChild(floatLayer)
    }

    required init?(coder: NSCoder) { fatalError("UnitPlateOverlay is created in code") }

    func plate(for id: UUID) -> UnitPlate? { plates[id] }

    @discardableResult
    func addPlate(for id: UUID, elementHex: String, wearsMarker: Bool = false) -> UnitPlate {
        if let old = plates[id] { perform { old.removeFromParent() } }
        let plate = UnitPlate(elementHex: elementHex, wearsMarker: wearsMarker)
        plate.host = self
        plates[id] = plate
        perform { [weak self] in self?.dimLayer.addChild(plate) }
        return plate
    }

    /// A word or a number off a unit, over every plate. The picture is drawn
    /// by the caller; the node is made and placed on the render thread.
    /// `side` is metres across the unit (a boss's words stand beside its
    /// head) and `align` −1 puts the label's trailing edge on that point.
    func addFloat(image: UIImage, over unit: UnitNode, lift: Float, side: Float = 0, align: CGFloat = 0,
                  pop: Bool, scatter: CGFloat, rise: CGFloat) {
        let anchor = unit.convertPosition(SCNVector3(side, lift, 0), to: nil)
        let born = CACurrentMediaTime()
        perform { [weak self] in
            guard let self else { return }
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            sprite.size = image.size
            sprite.alpha = 0
            let label = FloatingLabel(
                node: sprite, unit: unit, lift: lift, side: side, align: align, fallback: anchor,
                born: born, pop: pop, scatter: scatter, rise: rise
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

    /// The plates at a quarter while a cut-in's band is up, and back as it
    /// goes. The floating numbers stay: an ultimate's hits land as the band
    /// leaves, and they are its payoff.
    func setPlatesDimmed(_ dimmed: Bool) {
        perform { [weak self] in
            guard let self else { return }
            self.dimLayer.removeAction(forKey: "dim")
            self.dimLayer.run(.fadeAlpha(to: dimmed ? 0.25 : 1, duration: dimmed ? 0.15 : 0.3), withKey: "dim")
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
    /// Metres across the unit: a boss's words stand beside its head.
    let side: Float
    /// −1 sets the label's trailing edge on its anchor; 0 centres it.
    let align: CGFloat
    let fallback: SCNVector3
    let born: TimeInterval
    let pop: Bool
    /// Points sideways off the anchor, so a multi-hit reads as a burst.
    let scatter: CGFloat
    /// How far it rises, in points, before anything in its way stops it.
    let rise: CGFloat

    // The render thread's memory of it, frame to frame
    // (`BattleSceneController.layoutFloats`).
    /// 0…1: faded out while its anchor is off the frame, back when it returns.
    var visibility: CGFloat = 1
    /// Whether it has been placed on the frame at least once.
    var placed = false
    /// Whether a layout pass has seen it at all, on the frame or off it: a
    /// float on the frame at its FIRST pass was born there and pops; one
    /// first seen off it fades in when its unit arrives. Its age could not
    /// say which — a float's first pass comes a frame after it is made, and
    /// a slow frame (the simulator's, an ultimate's) outlasted any limit.
    var laidOut = false
    /// Points it is pushed up by the floats newer than it on the same unit
    /// and by its unit's plate, eased so a push slides rather than jumps.
    var push: CGFloat = 0
    var pushed = false

    init(node: SKSpriteNode, unit: UnitNode?, lift: Float, side: Float, align: CGFloat, fallback: SCNVector3,
         born: TimeInterval, pop: Bool, scatter: CGFloat, rise: CGFloat) {
        self.node = node
        self.unit = unit
        self.lift = lift
        self.side = side
        self.align = align
        self.fallback = fallback
        self.born = born
        self.pop = pop
        self.scatter = scatter
        self.rise = rise
    }

    var life: TimeInterval { (pop ? FloatingLabel.popTime : 0) + FloatingLabel.riseTime }

    /// Where in the world it hangs this frame.
    var anchor: SCNVector3 {
        guard let unit else { return fallback }
        guard side == 0 else { return unit.convertPosition(SCNVector3(side, lift, 0), to: nil) }
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
/// status tiles above the track; the matchup arrow beside the track's
/// right end, level with the bars (it floated 30 points over the plate
/// until run 221, under the top edge on the far row); and a gold rim while
/// the unit acts. Every size here is in points and the same in both rows,
/// which is what makes health comparable across the field and the bars as
/// crisp as the HUD.
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
    /// A status tile, and the step from one tile's centre to the next: the
    /// tile and the turn chip hanging past its corner. 12 points, with the
    /// turns at about 3, until run 221 (under the 11-point floor).
    static let tile: CGFloat = 16
    static let tileStep: CGFloat = 21
    /// The level badge: 22 points round an 11-point Manrope number (19 round
    /// a 9-point one until run 221).
    static let badgeSize: CGFloat = 22
    /// The matchup marker beside the track's right end.
    static let markerSize: CGFloat = 17
    /// Half the dark track: the bars, their padding and a point each side.
    static var trackHalfWidth: CGFloat { (barWidth + 2 * trackPad + 2) / 2 }
    /// The badge's centre, over the track's left end, the genre's way; it
    /// covers the bar's first five points, as the smaller one did.
    static var badgeCentreX: CGFloat { -(barWidth / 2 + trackPad + 4.5) }
    /// The marker's centre, a point and a half past the track's right end.
    static var markerCentreX: CGFloat { trackHalfWidth + 1.5 + markerSize / 2 }
    /// How far the plate draws left of its centre and below it: the badge.
    static var reachLeft: CGFloat { -badgeCentreX + badgeSize / 2 }
    static var reachBelow: CGFloat { badgeSize / 2 }
    /// The most it draws above its centre: a row of status tiles with their
    /// chips.
    static var tallestReach: CGFloat { trackHeight / 2 + 1.5 + tile + 6 }
    /// How far it draws right of its centre: the track's end, or the
    /// marker's for a plate that wears one — an opponent's — reserved
    /// whether or not one is up, so a row of plates does not re-stagger
    /// every time the turn changes hands.
    let reachRight: CGFloat
    /// How far it draws above its centre now: the badge, or the tiles while
    /// any are up. Render thread.
    private(set) var reachAbove: CGFloat = UnitPlate.badgeSize / 2
    /// How far the row of status tiles reaches left and right of the
    /// plate's centre while one is up, the turn chips included; zero with
    /// none. The declutter keeps a neighbour off the row as well as off the
    /// badge and track (run 224's arena: a plate lifted clear of its
    /// neighbour's badge alone put that neighbour's third turn chip, "2",
    /// on its own badge's ring beside its "40" — "240"). Render thread.
    private(set) var tilesLeft: CGFloat = 0
    private(set) var tilesRight: CGFloat = 0
    /// Whether a row of status tiles is up. Render thread.
    var wearsTiles: Bool { tilesRight > tilesLeft }

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

    init(elementHex: String, wearsMarker: Bool = false) {
        let w = UnitPlate.barWidth
        let h = UnitPlate.hpHeight
        let a = UnitPlate.atbHeight
        self.elementHex = elementHex
        reachRight = wearsMarker
            ? UnitPlate.markerCentreX + UnitPlate.markerSize / 2
            : UnitPlate.trackHalfWidth
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
        let badgeNode = SKSpriteNode(color: .clear, size: CGSize(width: UnitPlate.markerSize, height: UnitPlate.markerSize))
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
        levelBadge.position = CGPoint(x: UnitPlate.badgeCentreX, y: 0)
        levelBadge.zPosition = 5
        addChild(levelBadge)
        applyLevel(1)

        // The status tiles stand on the track.
        statusRow.position = CGPoint(x: 0, y: track / 2 + 1.5 + UnitPlate.tile / 2)
        statusRow.zPosition = 4
        addChild(statusRow)

        // The matchup marker beside the track's right end, level with the
        // bars, where it is read with the health it is about.
        badge.position = CGPoint(x: UnitPlate.markerCentreX, y: 0)
        badge.zPosition = 5
        addChild(badge)
    }

    /// The number in the badge: the unit's level.
    func setLevel(_ level: Int) {
        later { [self] in applyLevel(level) }
    }

    private func applyLevel(_ level: Int) {
        levelBadge.texture = PlateArt.levelBadge(level: level, hex: elementHex)
        // A level of three figures is a pill, grown leftward off the track.
        let width = PlateArt.levelBadgeWidth(for: level)
        levelBadge.size = CGSize(width: width, height: UnitPlate.badgeSize)
        levelBadge.position = CGPoint(x: UnitPlate.badgeCentreX - (width - UnitPlate.badgeSize) / 2, y: 0)
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
    /// kind, the longest-lasting of each, five at most (a sixth at 16
    /// points would run the row half a plate past either end). The pictures
    /// are drawn here, on the caller's thread; the row is rebuilt on the
    /// renderer's.
    func setStatuses(_ statuses: [ActiveStatus]) {
        var byKind: [StatusKind: Int] = [:]
        for status in statuses { byKind[status.kind] = max(byKind[status.kind] ?? 0, status.turnsRemaining) }
        let shown = byKind.sorted { $0.key.rawValue < $1.key.rawValue }.prefix(5)
        let tiles = shown.compactMap { StatusIconRenderer.plateTile(kind: $0.key, turns: $0.value) }
        later { [self] in applyStatuses(tiles) }
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

    private func applyStatuses(_ tiles: [StatusIconRenderer.PlateTile]) {
        statusRow.removeAllChildren()
        reachAbove = tiles.isEmpty ? UnitPlate.badgeSize / 2 : UnitPlate.tallestReach
        tilesLeft = 0
        tilesRight = 0
        guard !tiles.isEmpty else { return }
        let step = UnitPlate.tileStep
        let totalWidth = step * CGFloat(tiles.count - 1)
        var rowLeft: CGFloat = 0
        var rowRight: CGFloat = 0
        for (index, tile) in tiles.enumerated() {
            // The picture is the tile and its chip; the anchor is the tile's
            // centre, so the row lines up on the tiles.
            let sprite = SKSpriteNode(texture: SKTexture(image: tile.image))
            sprite.size = tile.image.size
            sprite.anchorPoint = tile.anchor
            let x: CGFloat = -totalWidth / 2 + step * CGFloat(index)
            sprite.position = CGPoint(x: x, y: 0)
            // Each chip over its right-hand neighbour's corner.
            sprite.zPosition = CGFloat(tiles.count - index)
            statusRow.addChild(sprite)
            let width: CGFloat = tile.image.size.width
            rowLeft = min(rowLeft, x - tile.anchor.x * width)
            rowRight = max(rowRight, x + (1 - tile.anchor.x) * width)
        }
        tilesLeft = rowLeft
        tilesRight = rowRight
    }

    private func applyMatchup(_ image: UIImage?) {
        guard let image else {
            badge.isHidden = true
            return
        }
        badge.texture = SKTexture(image: image)
        badge.size = CGSize(width: UnitPlate.markerSize, height: UnitPlate.markerSize)
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

    /// The level badge's width: the disc, or for a level of three figures a
    /// pill a little wider, rather than a smaller number.
    static func levelBadgeWidth(for level: Int) -> CGFloat {
        level >= 100 ? UnitPlate.badgeSize + 8 : UnitPlate.badgeSize
    }

    /// The level badge on the track's left end: a dark disc, a ring in the
    /// element's colour, the level in white Manrope at the 11-point floor
    /// with a dark edge. It was 9-point system heavy, 7.5 for three figures
    /// — about 8 on the phone (run 221) — in a 19-point disc.
    static func levelBadge(level: Int, hex: String) -> SKTexture {
        let size = CGSize(width: levelBadgeWidth(for: level), height: UnitPlate.badgeSize)
        return texture("level_\(level)_\(hex)", size: size) { context, rect in
            let disc = rect.insetBy(dx: 1.2, dy: 1.2)
            let path = UIBezierPath(roundedRect: disc, cornerRadius: disc.height / 2).cgPath
            paintGradient(context, in: disc, path: path, top: color("#3A2F24"), bottom: color("#130E0A"))
            let outer = rect.insetBy(dx: 0.6, dy: 0.6)
            context.addPath(UIBezierPath(roundedRect: outer, cornerRadius: outer.height / 2).cgPath)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(1)
            context.strokePath()
            let ring = rect.insetBy(dx: 1.7, dy: 1.7)
            context.addPath(UIBezierPath(roundedRect: ring, cornerRadius: ring.height / 2).cgPath)
            context.setStrokeColor(color(hex).cgColor)
            context.setLineWidth(1.8)
            context.strokePath()
            let font = UIFont(name: Theme.numberFace, size: Theme.bodyFloor)
                ?? UIFont.systemFont(ofSize: Theme.bodyFloor, weight: .heavy)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
            shadow.shadowOffset = CGSize(width: 0, height: 0.6)
            shadow.shadowBlurRadius = 0.8
            let text = NSAttributedString(string: "\(level)", attributes: [
                .font: font, .foregroundColor: UIColor.white, .shadow: shadow,
            ])
            // The figures' cap height centred in the disc.
            let width = text.size().width
            let baseline = rect.midY + font.capHeight / 2
            text.draw(at: CGPoint(x: rect.midX - width / 2, y: baseline - font.ascender))
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
