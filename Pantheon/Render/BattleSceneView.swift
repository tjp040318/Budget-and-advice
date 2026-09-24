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
        view.antialiasingMode = Self.antialiasing
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        // The camera is directed by CameraDirector; free orbit would fight it.
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.overlaySKScene = controller.plates
        view.delegate = context.coordinator
        // The frame rate (60 by default, as it always was), the effects and
        // the shadows the player chose in Settings (`Docs/SETTINGS.md` §2);
        // after the delegate, which the helper's governor forwards to.
        GraphicsSettings.configure(view, for: .battle)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    /// 4× multisampling on a phone with 6 GB or more (read as over 5 GB,
    /// since a phone reports a little under its rating), 2× below it
    /// (2026-09-24). The genre's figures measure twice our edge strength, and
    /// at 19° the floor's grout and the far parapet are long near-horizontal
    /// edges that 2× leaves stepped. On Apple's tile GPUs the extra samples
    /// are resolved on the tile, so 4× costs little time; what it can cost is
    /// memory if the sample buffers are ever kept off the tile, which the
    /// deferred shadows and the ambient occlusion may force — half-float
    /// colour and depth, twelve bytes a sample, about 145 MB at a Pro's
    /// 2556 × 1179 against 72 MB at 2×, and 173 against 87 on a Pro Max: 70
    /// to 90 MB more (2026-09-24, review; the first note said 50 and left
    /// the depth out) — and the crashes of 2026-09-23 were memory. So the
    /// 4 GB phones keep 2×, and CI's `-tour-stress battle` footprint
    /// (`shots/memory.txt`) is read against the last run's before this ships: a
    /// battle peak more than about 60 MB over it moves the gate to 7 GB.
    /// Jittering stays off: it is a still-frame supersampler, and the fight
    /// never holds still.
    static var antialiasing: SCNAntialiasingMode {
        ProcessInfo.processInfo.physicalMemory >= 5 * 1_024 * 1_024 * 1_024 ? .multisampling4X : .multisampling2X
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

    /// The view lets go of the fight when the fight closes (2026-09-24). The
    /// reveal, the altar, the collection's Stage and the chest each tear
    /// their stage down as their view leaves, because CI run 242 caught a
    /// view without it holding its scene, its figures and every texture it
    /// had uploaded after it was gone; this view had none either. The graph
    /// is NOT taken apart here: the battle's model owns the controller and
    /// its scene, and they go with the model when the cover closes (the
    /// controller's `deinit` says so in the console). What the view holds is
    /// dropped: the renderer stops at once, so the frame the cover slides
    /// away on is the last one drawn, and `SummonStageView.teardownSettle`
    /// later, past the slide and any frame in flight, the view lets go of
    /// the scene, the plates and the coordinator's links.
    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        uiView.isPlaying = false
        uiView.rendersContinuously = false
        uiView.delegate = nil
        uiView.gestureRecognizers?.forEach { uiView.removeGestureRecognizer($0) }
        coordinator.onTapUnit = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + SummonStageView.teardownSettle) {
            uiView.overlaySKScene = nil
            uiView.scene = nil
            coordinator.view = nil
            coordinator.controller = nil
        }
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
                        // An enemy tapped on the player's turn wears a
                        // reticle in the acting unit's colour (Docs/FEEL.md
                        // W1.9); the controller decides whether it may.
                        controller?.stampReticle(on: unitNode, in: view)
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

        /// A frame was drawn: the veil over a new fight lifts a few frames
        /// after its stage is built (`BattleSceneController.frameDrawn`).
        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            controller?.frameDrawn()
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
    /// Between the plates and the words: a kill's speed lines and a tapped
    /// enemy's reticle (Docs/FEEL.md W1.3, W1.9).
    private let burstLayer = SKNode()
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
        burstLayer.zPosition = 90
        addChild(burstLayer)
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
    /// `overshoot` is how far past its size a popped label springs (a
    /// crit's further than a hit's), `jitter` how long it trembles as it
    /// lands, and `hold` how much longer than a word it hangs (the skill
    /// banner's).
    func addFloat(image: UIImage, over unit: UnitNode, lift: Float, side: Float = 0, align: CGFloat = 0,
                  pop: Bool, scatter: CGFloat, rise: CGFloat,
                  overshoot: CGFloat = FloatingLabel.standardOvershoot, jitter: TimeInterval = 0,
                  hold: TimeInterval = 0) {
        let anchor = unit.convertPosition(SCNVector3(side, lift, 0), to: nil)
        let born = CACurrentMediaTime()
        perform { [weak self] in
            guard let self else { return }
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            sprite.size = image.size
            sprite.alpha = 0
            let label = FloatingLabel(
                node: sprite, unit: unit, lift: lift, side: side, align: align, fallback: anchor,
                born: born, pop: pop, scatter: scatter, rise: rise,
                overshoot: overshoot, jitter: jitter, hold: hold
            )
            self.floatLayer.addChild(sprite)
            self.floats.append(label)
        }
    }

    // MARK: A kill's speed lines and the reticle (Docs/FEEL.md W1.3, W1.9)

    /// A kill's speed lines waiting for their unit's place on the screen,
    /// which only the renderer knows (`placeBursts`). Render thread only.
    private var pendingBursts: [SpeedLineBurst] = []

    /// A burst of thin speed lines in `tint` round a unit struck dead (the
    /// impact frame of a kill), `lift` metres up it. Main thread; placed on
    /// the render thread when the next frame is laid out.
    func burstSpeedLines(over unit: UnitNode, lift: Float, tint: UIColor) {
        let burst = SpeedLineBurst(unit: unit, lift: lift, tint: tint)
        perform { [weak self] in self?.pendingBursts.append(burst) }
    }

    /// The bursts asked for since the last frame, drawn where their units
    /// stand in it. Render thread, from `BattleSceneController.layoutPlates`.
    func placeBursts(in renderer: SCNSceneRenderer) {
        guard !pendingBursts.isEmpty else { return }
        let bursts = pendingBursts
        pendingBursts.removeAll()
        let height = size.height
        for burst in bursts {
            guard let unit = burst.unit else { continue }
            let feet = unit.worldPosition
            let projected = renderer.projectPoint(SCNVector3(feet.x, feet.y + burst.lift, feet.z))
            guard projected.z > 0, projected.z < 1 else { continue }
            spawnSpeedLines(at: CGPoint(x: CGFloat(projected.x), y: height - CGFloat(projected.y)), tint: burst.tint)
        }
    }

    /// The lines themselves: sixteen thin strokes of light round the point,
    /// each a random length, flying outward and gone in a quarter second
    /// over a flash at the heart — the anime impact frame's lines.
    private func spawnSpeedLines(at centre: CGPoint, tint: UIColor) {
        let line = PlateArt.speedLine()
        let count = 16
        for index in 0..<count {
            let angle: CGFloat = CGFloat(index) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.12...0.12)
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            let start: CGFloat = CGFloat.random(in: 34...52)
            let travel: CGFloat = CGFloat.random(in: 36...58)
            let stroke = SKSpriteNode(texture: line)
            stroke.size = CGSize(width: 3.2, height: CGFloat.random(in: 46...82))
            stroke.color = tint
            stroke.colorBlendFactor = 0.7
            stroke.blendMode = .add
            stroke.position = CGPoint(x: centre.x + direction.dx * start, y: centre.y + direction.dy * start)
            stroke.zRotation = angle - .pi / 2
            stroke.alpha = 0
            let move = SKAction.moveBy(x: direction.dx * travel, y: direction.dy * travel, duration: 0.26)
            move.timingMode = .easeOut
            let show = SKAction.sequence([.fadeAlpha(to: 1, duration: 0.03), .fadeOut(withDuration: 0.23)])
            stroke.run(.sequence([.group([move, show]), .removeFromParent()]))
            burstLayer.addChild(stroke)
        }
        let core = SKSpriteNode(texture: PlateArt.burstCore())
        core.size = CGSize(width: 72, height: 72)
        core.color = tint
        core.colorBlendFactor = 0.45
        core.blendMode = .add
        core.position = centre
        core.setScale(0.6)
        core.run(.sequence([
            .group([.scale(to: 1.3, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))
        burstLayer.addChild(core)
    }

    /// The last reticle stamped, so a new stamp takes its place. Render thread.
    private weak var reticle: SKSpriteNode?

    /// A reticle stamped on a tapped enemy (W1.9), at `point` in the
    /// overlay's points (origin at the bottom), in `tint`: it lands from a
    /// size and a half and a quarter turn, holds a third of a second, and
    /// fades. Main thread; drawn on the render thread.
    func stampReticle(at point: CGPoint, tint: UIColor) {
        // Under Reduce Motion it fades in where it lands, at its size and
        // square, rather than spinning down out of a larger one. Read here,
        // on the main thread.
        let calm = MotionComfort.isReduced
        perform { [weak self] in
            guard let self else { return }
            self.reticle?.removeFromParent()
            let mark = SKSpriteNode(texture: PlateArt.reticle())
            mark.size = CGSize(width: 60, height: 60)
            mark.color = tint
            mark.colorBlendFactor = 0.85
            mark.position = point
            mark.alpha = 0
            mark.setScale(calm ? 1 : 1.7)
            mark.zRotation = calm ? 0 : CGFloat.pi / 4
            let land = SKAction.group([
                .fadeAlpha(to: 1, duration: 0.13),
                .scale(to: 1, duration: 0.13),
                .rotate(toAngle: 0, duration: 0.13, shortestUnitArc: true),
            ])
            land.timingMode = .easeOut
            mark.run(.sequence([land, .wait(forDuration: 0.32), .fadeOut(withDuration: 0.25), .removeFromParent()]))
            self.burstLayer.addChild(mark)
            self.reticle = mark
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
            // A new run's field has none of the last one's speed lines or
            // reticle either.
            self.pendingBursts.removeAll()
            self.burstLayer.removeAllChildren()
        }
    }

    /// The whole field's chrome — every plate and every floating word —
    /// faded out while the reckoning is up (run 220: three plates showed
    /// through its scrim under the TURNS/DEALT/TAKEN tiles), and back.
    func setFieldHidden(_ hidden: Bool) {
        perform { [weak self] in
            guard let self else { return }
            for layer in [self.plateLayer, self.burstLayer, self.floatLayer] {
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

/// A kill's speed lines waiting for their unit's place on the screen
/// (`UnitPlateOverlay.placeBursts`): the unit, how far up it, the colour.
struct SpeedLineBurst {
    weak var unit: UnitNode?
    let lift: Float
    let tint: UIColor

    init(unit: UnitNode, lift: Float, tint: UIColor) {
        self.unit = unit
        self.lift = lift
        self.tint = tint
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
    /// Points it is moved sideways off ANOTHER unit's plate (run 234: a
    /// "RESIST" stopped under its own plate lay across its neighbour's
    /// level badge). Out of a plate's way at once, eased back.
    var slide: CGFloat = 0
    /// 0…1: out of sight while it has no place clear of every other plate
    /// within reach of its unit, faded back in when it has one.
    var crowdAlpha: CGFloat = 1

    /// How far past its size a popped label springs before it settles: an
    /// eighth for a number, a quarter for a crit (Docs/FEEL.md W1.2).
    static let standardOvershoot: CGFloat = 1.12
    let overshoot: CGFloat
    /// Seconds a crit trembles as it lands (0 for everything else).
    let jitter: TimeInterval
    /// Seconds it hangs past a word's life before it fades: the skill
    /// banner's (W1.9).
    let hold: TimeInterval

    init(node: SKSpriteNode, unit: UnitNode?, lift: Float, side: Float, align: CGFloat, fallback: SCNVector3,
         born: TimeInterval, pop: Bool, scatter: CGFloat, rise: CGFloat,
         overshoot: CGFloat = FloatingLabel.standardOvershoot, jitter: TimeInterval = 0, hold: TimeInterval = 0) {
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
        self.overshoot = overshoot
        self.jitter = jitter
        self.hold = hold
    }

    var life: TimeInterval { (pop ? FloatingLabel.popTime : 0) + FloatingLabel.riseTime + hold }

    /// A crit's tremble as it lands, in points: two and a half at first,
    /// dying away over `jitter`, at a rate the eye reads as a shudder.
    func shake(at age: TimeInterval) -> CGPoint {
        guard jitter > 0 else { return .zero }
        let into: TimeInterval = age - FloatingLabel.popTime * 0.5
        guard into > 0, into < jitter else { return .zero }
        let left = CGFloat(1 - into / jitter)
        let amplitude: CGFloat = 2.5 * left
        let x: CGFloat = amplitude * CGFloat(sin(into * 2 * Double.pi * 28))
        let y: CGFloat = amplitude * 0.6 * CGFloat(cos(into * 2 * Double.pi * 23))
        return CGPoint(x: x, y: y)
    }

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
        let peak = overshoot
        if age < grow {
            let t = CGFloat(age / grow)
            let eased = 1 - (1 - t) * (1 - t)
            return 0.35 + (peak - 0.35) * eased
        }
        if age < FloatingLabel.popTime {
            let t = CGFloat((age - grow) / (FloatingLabel.popTime - grow))
            return peak - (peak - 1) * t
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
/// ours: "The health bars are not above the heads"). A SILVER FRAME round a
/// dark well holding a glossy green health bar and a cream trail that
/// lingers a beat after a hit, and the blue attack bar under it that fills
/// toward the unit's turn and turns gold when it is ready; the LEVEL BADGE
/// over the frame's left end, a metal sphere in the element's colour with
/// the number in heavy white on it, the genre's mark; the status tiles
/// above the frame; the matchup arrow beside its right end, level with the
/// bars (it floated 30 points over the plate until run 221, under the top
/// edge on the far row); and a gold rim while the unit acts. Every size
/// here is in points and the same in both rows, which is what makes health
/// comparable across the field and the bars as crisp as the HUD.
///
/// SUMMONERS WAR'S PLATE, MEASURED (2026-09-24; the owner, with two of his
/// frames: "I want THIS level"). His phone's pixels, at 3 to the point: a
/// frame 16 points from the silver's top edge to its foot (a bevel of 1.3
/// light over 1.7 warm, a dark line inside it and a point of dark shadow
/// outside), a 6.4-point green bar lit at its top (146, 233, 115) and shaded
/// at its foot (48, 168, 19) over (80, 215, 36), a 1.3-point dark rule, a
/// 4-point blue bar (44, 187, 235), 65 points of bar from the badge to the
/// frame's end; and a 28-point sphere ringed in the same silver. Ours was a
/// 14.5-point see-through dark track with a mint bar, a 3-point attack bar
/// and a 22-point flat disc — a plate that read as a web page's progress
/// bar next to his.
final class UnitPlate: SKNode {

    static let barWidth: CGFloat = 65
    static let hpHeight: CGFloat = 6.5
    /// 4 (was 3): the genre's attack bar is two thirds of the health bar's
    /// height, read at a glance for who moves next.
    static let atbHeight: CGFloat = 4
    /// The dark rule between the two bars, and the well's padding round them.
    static let barGap: CGFloat = 1
    static let trackPad: CGFloat = 0.75
    /// The silver bevel round the well, and the dark edge outside it.
    static let bevel: CGFloat = 1.5
    static let frameEdge: CGFloat = 0.75
    /// The dark well the bars lie in.
    static var wellHeight: CGFloat { hpHeight + barGap + atbHeight + 2 * trackPad }
    /// The EXP bar the triumph lays in the well: both bars' height and the
    /// rule between them, so it reads as one gold bar (W1.7).
    static var expHeight: CGFloat { hpHeight + barGap + atbHeight }
    /// The whole frame, edge to edge: 16 points of silver and well, and the
    /// dark edge round them (17.5).
    static var trackHeight: CGFloat { wellHeight + 2 * (bevel + frameEdge) }
    /// The frame's bottom edge stands this far above the projected top of
    /// the head.
    static let riseAboveHead: CGFloat = 12
    /// How far the triumph's LEVEL UP rises out of the plate into its place
    /// just over the track (`levelUpMoment`).
    static let levelUpRise: CGFloat = 16
    /// A status tile, and the step from one tile's centre to the next: the
    /// tile and the turn chip hanging past its corner. 12 points, with the
    /// turns at about 3, until run 221 (under the 11-point floor).
    static let tile: CGFloat = 16
    static let tileStep: CGFloat = 21
    /// The level badge: 27 points (22 until 2026-09-24; his is 28), the
    /// sphere and its silver ring.
    static let badgeSize: CGFloat = 27
    /// The matchup marker beside the frame's right end.
    static let markerSize: CGFloat = 17
    /// The frame's reach right of the plate's centre: the bars, the well's
    /// padding, the bevel and the edge.
    static var trackHalfWidth: CGFloat { barWidth / 2 + trackPad + bevel + frameEdge }
    /// The badge's centre, over the frame's left end, the genre's way: its
    /// ring meets the green half a point short of the bar's start, as his
    /// does, so the whole bar shows. The frame runs on under the badge to
    /// its centre (`frameLeft`), so no gap opens at the badge's shoulders.
    static var badgeCentreX: CGFloat { -(barWidth / 2 + 0.5 + badgeSize / 2) }
    /// Where the frame starts, under the badge.
    static var frameLeft: CGFloat { badgeCentreX }
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

    /// The plate's parts, in a node of their own under the plate, so the
    /// declutter can fade a VISITING plate — its unit off its mark, leaping
    /// at or standing over a victim — that has no clear place to stand
    /// (`crowdAlpha`, run 234's 8-aoe-a). The plate's own alpha belongs to
    /// the death, the revival and a wave's entry (`setDefeated`, `enter`),
    /// whose fade actions would undo a fade written over them.
    private let parts = SKNode()
    /// The health bar, its trail and the attack bar, as one node, so the
    /// triumph can swap them for the EXP bar in one move (`showExperience`).
    private let bars = SKNode()
    /// The gold EXP bar the triumph fills (Docs/FEEL.md W1.7): the whole
    /// well's height, hidden until then.
    private let expCrop = SKCropNode()
    private let expMask: SKSpriteNode
    /// The level on the badge. Render thread.
    private(set) var level: Int = 1
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

    /// 1 drawn, 0 out of sight by the declutter's word (`BattleSceneController.
    /// layoutPlates`): a visiting plate is drawn only where it is clear of
    /// every plate drawn, and fades back in there. Render thread.
    var crowdAlpha: CGFloat {
        get { parts.alpha }
        set { parts.alpha = newValue }
    }

    init(elementHex: String, wearsMarker: Bool = false) {
        let w = UnitPlate.barWidth
        let h = UnitPlate.hpHeight
        let a = UnitPlate.atbHeight
        self.elementHex = elementHex
        reachRight = wearsMarker
            ? UnitPlate.markerCentreX + UnitPlate.markerSize / 2
            : UnitPlate.trackHalfWidth
        // Glossy, the genre's (2026-09-24): lit along the top, deep at the
        // foot — his green, not the mint (114, 216, 140) that read as flat.
        let full = PlateArt.gloss("hp", width: w, height: h, radius: 1.5, stops: PlateArt.healthStops)
        let low = PlateArt.gloss("hp_low", width: w, height: h, radius: 1.5, stops: PlateArt.lowHealthStops)
        let trail = PlateArt.fill("hp_trail", width: w, height: h, radius: 1.5, top: "#FFF6E6", bottom: "#E8CBA8")
        let atb = PlateArt.gloss("atb", width: w, height: a, radius: 1.5, stops: PlateArt.attackStops)
        let ready = PlateArt.gloss("atb_ready", width: w, height: a, radius: 1.5, stops: PlateArt.readyStops)
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
        // The rim's crisp line half a point outside the frame's right end
        // and its top and foot; its left side runs under the badge.
        let rimSize = CGSize(width: 2 * UnitPlate.trackHalfWidth + 7, height: track + 7)
        let rimNode = SKSpriteNode(texture: PlateArt.rim("rim_acting", width: rimSize.width, height: rimSize.height, radius: 7, hex: "#F2C75C"))
        rimNode.size = rimSize
        rimNode.isHidden = true

        hpFill = hpFillNode
        hpMask = UnitPlate.mask(width: w, height: h)
        trailMask = UnitPlate.mask(width: w, height: h)
        atbFill = atbFillNode
        atbMask = UnitPlate.mask(width: w, height: a)
        expMask = UnitPlate.mask(width: w, height: UnitPlate.expHeight)
        badge = badgeNode
        levelBadge = levelNode
        rim = rimNode
        super.init()

        // One frame for both bars, its well centred on the node's origin:
        // the health bar in the upper part, the attack bar under it.
        let hpY: CGFloat = (a + UnitPlate.barGap) / 2
        let atbY: CGFloat = -(h + UnitPlate.barGap) / 2

        // Every part in `parts`, at the plate's origin and z, so where each
        // is drawn is unchanged.
        parts.position = .zero
        parts.zPosition = 0
        addChild(parts)

        rim.position = .zero
        rim.zPosition = 0
        parts.addChild(rim)

        // The silver frame, from under the badge's centre to its right end.
        let frameWidth: CGFloat = UnitPlate.trackHalfWidth - UnitPlate.frameLeft
        let frameNode = SKSpriteNode(texture: PlateArt.frame("plate_frame", width: frameWidth, height: track))
        frameNode.size = CGSize(width: frameWidth, height: track)
        frameNode.position = CGPoint(x: (UnitPlate.trackHalfWidth + UnitPlate.frameLeft) / 2, y: 0)
        frameNode.zPosition = 1
        parts.addChild(frameNode)

        // The bars in a node of their own at the plate's origin and z, so
        // where each is drawn is unchanged and the triumph can hide all
        // three at once.
        bars.position = .zero
        bars.zPosition = 2
        parts.addChild(bars)

        let trailCrop = SKCropNode()
        trailCrop.maskNode = trailMask
        trailCrop.addChild(trailFillNode)
        trailCrop.position = CGPoint(x: 0, y: hpY)
        trailCrop.zPosition = 0
        bars.addChild(trailCrop)

        let hpCrop = SKCropNode()
        hpCrop.maskNode = hpMask
        hpCrop.addChild(hpFill)
        hpCrop.position = CGPoint(x: 0, y: hpY)
        hpCrop.zPosition = 1
        bars.addChild(hpCrop)

        let atbCrop = SKCropNode()
        atbCrop.maskNode = atbMask
        atbCrop.addChild(atbFill)
        atbCrop.position = CGPoint(x: 0, y: atbY)
        atbCrop.zPosition = 1
        bars.addChild(atbCrop)

        // The EXP bar: the well's whole height, gold, hidden until the
        // triumph fills it.
        let expFillNode = SKSpriteNode(texture: PlateArt.gloss("exp", width: w, height: UnitPlate.expHeight,
                                                               radius: 2, stops: PlateArt.experienceStops))
        expFillNode.size = CGSize(width: w, height: UnitPlate.expHeight)
        expCrop.maskNode = expMask
        expCrop.addChild(expFillNode)
        expCrop.position = .zero
        expCrop.zPosition = 3
        expCrop.isHidden = true
        parts.addChild(expCrop)

        // The level badge over the frame's left end, the genre's way.
        levelBadge.position = CGPoint(x: UnitPlate.badgeCentreX, y: 0)
        levelBadge.zPosition = 5
        parts.addChild(levelBadge)
        applyLevel(1)

        // The status tiles stand on the frame.
        statusRow.position = CGPoint(x: 0, y: track / 2 + 1.5 + UnitPlate.tile / 2)
        statusRow.zPosition = 4
        parts.addChild(statusRow)

        // The matchup marker beside the frame's right end, level with the
        // bars, where it is read with the health it is about.
        badge.position = CGPoint(x: UnitPlate.markerCentreX, y: 0)
        badge.zPosition = 5
        parts.addChild(badge)
    }

    /// The number in the badge: the unit's level.
    func setLevel(_ level: Int) {
        later { [self] in applyLevel(level) }
    }

    private func applyLevel(_ level: Int) {
        self.level = level
        levelBadge.texture = PlateArt.levelBadge(level: level, hex: elementHex)
        // A level of three figures is a pill, grown leftward off the frame.
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

    /// THE TRIUMPH'S EXP BAR (Docs/FEEL.md W1.7): the health and attack bars
    /// give way to one gold bar that stands at `from` and, `delay` seconds
    /// on, fills to `to`; a unit that levelled fills to the end first, the
    /// badge takes its new level, LEVEL UP rises over the plate and the bar
    /// runs on from empty. The status tiles, the matchup marker and the
    /// acting rim leave with the health it replaces. The picture of LEVEL UP
    /// is drawn here, on the caller's (the main) thread, where the float
    /// renderer's cache lives; the bar is set on the renderer's.
    func showExperience(from: Double, to: Double, levels: Int, after delay: TimeInterval) {
        let banner: UIImage? = levels > 0 ? FloatingTextRenderer.flourish("LEVEL UP", ink: .total, size: 18) : nil
        // Read here, on the main thread, for the render thread's moment.
        let calm = MotionComfort.isReduced
        later { [self] in
            applyExperience(from: from, to: to, levels: levels, delay: delay, banner: banner, calm: calm)
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

    private func applyExperience(from: Double, to: Double, levels: Int, delay: TimeInterval, banner: UIImage?,
                                 calm: Bool) {
        bars.isHidden = true
        applyStatuses([])
        badge.isHidden = true
        applyActing(false)
        expCrop.isHidden = false
        let start = CGFloat(min(1, max(0, from)))
        let end = CGFloat(min(1, max(0, to)))
        expMask.removeAction(forKey: "exp")
        expMask.xScale = max(0.001, start)
        var steps: [SKAction] = [.wait(forDuration: max(0, delay))]
        if levels > 0 {
            // To the end, the level taken, then on from empty.
            let rest: CGFloat = 1 - start
            let fillUp = SKAction.scaleX(to: 1, duration: TimeInterval(0.2 + 0.5 * rest))
            fillUp.timingMode = .easeIn
            let onward = SKAction.scaleX(to: max(0.001, end), duration: TimeInterval(0.25 + 0.5 * end))
            onward.timingMode = .easeOut
            steps.append(fillUp)
            steps.append(.run { [weak self] in self?.levelUpMoment(levels: levels, banner: banner, calm: calm) })
            steps.append(.wait(forDuration: 0.18))
            steps.append(.scaleX(to: 0.001, duration: 0))
            steps.append(onward)
        } else {
            let fill = SKAction.scaleX(to: max(0.001, end), duration: TimeInterval(0.35 + 0.6 * abs(end - start)))
            fill.timingMode = .easeOut
            steps.append(fill)
        }
        expMask.run(.sequence(steps), withKey: "exp")
    }

    /// The moment a unit's bar reaches the end of its level: the badge takes
    /// the new level with a pop, a flash runs over the full bar, and LEVEL
    /// UP rises from the plate and STAYS over it, breathing, until the
    /// reckoning takes the plates — the triumph is under two and a half
    /// seconds, and a word that faded a second after it landed left the
    /// beat's last second with no sign of who had levelled. Render thread
    /// (an action's block).
    ///
    /// The words rise OUT OF the plate into their place just over the track
    /// (2026-09-24, review): they rose 16 points past it, and with the heads
    /// where the triumph framed them the words stood under the VICTORY
    /// stamp's band (`CameraDirector.teamLowering` says where they are now).
    /// Under Reduce Motion (`calm`, read on the main thread) the badge takes
    /// its level without the bump and the words fade in where they rest.
    private func levelUpMoment(levels: Int, banner: UIImage?, calm: Bool) {
        applyLevel(level + levels)
        levelBadge.removeAction(forKey: "bump")
        if !calm {
            levelBadge.run(.sequence([.scale(to: 1.35, duration: 0.08), .scale(to: 1, duration: 0.2)]), withKey: "bump")
        }
        let flash = SKSpriteNode(color: .white, size: CGSize(width: UnitPlate.barWidth, height: UnitPlate.expHeight))
        flash.blendMode = .add
        flash.alpha = 0.85
        flash.zPosition = 4
        flash.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        parts.addChild(flash)
        guard let banner else { return }
        let words = SKSpriteNode(texture: SKTexture(image: banner))
        words.size = banner.size
        let rest: CGFloat = UnitPlate.trackHeight / 2 + banner.size.height / 2 + 4
        let travel: CGFloat = calm ? 0 : UnitPlate.levelUpRise
        words.position = CGPoint(x: 0, y: rest - travel)
        words.zPosition = 6
        words.alpha = 0
        words.setScale(calm ? 1 : 0.6)
        let rise = SKAction.moveBy(x: 0, y: travel, duration: 0.5)
        rise.timingMode = .easeOut
        let pop: SKAction = calm
            ? .wait(forDuration: 0)
            : .sequence([.scale(to: 1.15, duration: 0.1), .scale(to: 1, duration: 0.12)])
        let arrive = SKAction.group([rise, pop, .fadeIn(withDuration: calm ? 0.3 : 0.1)])
        let dim = SKAction.fadeAlpha(to: 0.82, duration: 0.7)
        dim.timingMode = .easeInEaseOut
        let lift = SKAction.fadeAlpha(to: 1, duration: 0.7)
        lift.timingMode = .easeInEaseOut
        words.run(.sequence([arrive, .repeatForever(.sequence([dim, lift]))]), withKey: "levelUp")
        parts.addChild(words)
    }

}

/// The plates' pictures, drawn once each with Core Graphics at 3× and kept:
/// the frame, the fills, the level badge, a pip and a rim.
enum PlateArt {

    private static var cache: [String: SKTexture] = [:]
    /// The cache is read and written on the MAIN thread (a plate's init, as
    /// `place` builds a wave) and on SceneKit's RENDER thread (a queued
    /// `setLevel` drawing a new level badge from `drainPending`), and a
    /// Swift dictionary written on one thread while another reads it is
    /// undefined — a crash when an insert grows its storage under the other
    /// thread's lookup (2026-09-24). Held around the lookup and the insert,
    /// never around the drawing; two threads that draw the same key at once
    /// keep the first.
    private static let lock = NSLock()

    private static func texture(_ key: String, size: CGSize, draw: (CGContext, CGRect) -> Void) -> SKTexture {
        lock.lock()
        let hit = cache[key]
        lock.unlock()
        if let hit { return hit }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext, CGRect(origin: .zero, size: size))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        lock.lock(); defer { lock.unlock() }
        if let won = cache[key] { return won }
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

    /// A vertical gradient of several stops, clipped to `path`: the gloss
    /// on a bar and the bevel of the silver, which two stops cannot draw.
    private static func paintStops(_ context: CGContext, in rect: CGRect, path: CGPath, stops: [(CGFloat, String)]) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        let colors = stops.map { color($0.1).cgColor } as CFArray
        let locations: [CGFloat] = stops.map { $0.0 }
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

    private static func capsule(_ rect: CGRect) -> CGPath {
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).cgPath
    }

    /// The genre's glossy greens, read off the owner's frame row by row
    /// (2026-09-24): a darker first row where the bar meets the frame's
    /// line, the light at a tenth down (146, 233, 115), the body
    /// (80, 215, 36) and the foot (48, 168, 19).
    static let healthStops: [(CGFloat, String)] = [
        (0, "#6FB957"), (0.09, "#92E973"), (0.22, "#7CF454"), (0.45, "#50D724"),
        (0.72, "#30C80E"), (0.88, "#26BD05"), (1, "#2A9A12"),
    ]
    /// Under 30%: the same gloss in amber.
    static let lowHealthStops: [(CGFloat, String)] = [
        (0, "#C99240"), (0.09, "#FFE3A0"), (0.22, "#FFD467"), (0.45, "#FFB43C"),
        (0.72, "#F2901F"), (0.88, "#E57A12"), (1, "#B85E10"),
    ]
    /// His attack bar's blue (44, 187, 235), lit at the top and deep at the
    /// foot, where ours was a pale sky (129, 199, 235).
    static let attackStops: [(CGFloat, String)] = [
        (0, "#54A0AE"), (0.12, "#6ECFE8"), (0.3, "#3FC0EC"), (0.5, "#2CBBEB"),
        (0.7, "#12B6E0"), (0.85, "#2EA7C6"), (1, "#2B8AA3"),
    ]
    /// A full attack bar: the same gloss in gold.
    static let readyStops: [(CGFloat, String)] = [
        (0, "#B0893A"), (0.12, "#FFF0B8"), (0.3, "#FFDD7A"), (0.5, "#F5C64E"),
        (0.7, "#E8B03A"), (0.85, "#D69A2A"), (1, "#A8751C"),
    ]
    /// The triumph's EXP bar (W1.7): a deeper, warmer gold than a full
    /// attack bar, lit along its top.
    static let experienceStops: [(CGFloat, String)] = [
        (0, "#A67A26"), (0.08, "#FFF3C4"), (0.24, "#FFE08A"), (0.5, "#F2BE45"),
        (0.76, "#DC9C2C"), (0.9, "#C1851F"), (1, "#8C5E14"),
    ]

    // MARK: The effects' strokes (W1.3, W1.9), white, tinted where they are used

    /// A speed line: a thin stroke of light, bright in its middle and gone
    /// at both ends.
    static func speedLine() -> SKTexture {
        texture("speed_line", size: CGSize(width: 4, height: 64)) { context, rect in
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0), cornerRadius: 1.7).cgPath
            paintStops(context, in: rect, path: path, stops: [
                (0, "#FFFFFF00"), (0.3, "#FFFFFFB0"), (0.55, "#FFFFFFFF"), (0.8, "#FFFFFF90"), (1, "#FFFFFF00"),
            ])
        }
    }

    /// The flash at the heart of a kill's burst: a soft round glow.
    static func burstCore() -> SKTexture {
        texture("burst_core", size: CGSize(width: 64, height: 64)) { context, rect in
            let colours = [
                UIColor.white.withAlphaComponent(0.95).cgColor,
                UIColor.white.withAlphaComponent(0.35).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.4, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours,
                                            locations: locations) else { return }
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: rect.width / 2, options: [])
        }
    }

    /// The reticle a tap stamps on an enemy: a ring with four ticks pointing
    /// in at the quarters and a dot at its heart, over a dark edge so it
    /// reads on pale stone.
    static func reticle() -> SKTexture {
        texture("reticle", size: CGSize(width: 60, height: 60)) { context, rect in
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 21
            let ring = UIBezierPath(arcCenter: centre, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            let ticks = UIBezierPath()
            for quarter in 0..<4 {
                let angle: CGFloat = CGFloat(quarter) * .pi / 2
                let outer = CGPoint(x: centre.x + cos(angle) * (radius + 7), y: centre.y + sin(angle) * (radius + 7))
                let inner = CGPoint(x: centre.x + cos(angle) * (radius - 8), y: centre.y + sin(angle) * (radius - 8))
                ticks.move(to: outer)
                ticks.addLine(to: inner)
            }
            context.setLineCap(.round)
            // The dark edge under the strokes.
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(4.6)
            context.addPath(ring.cgPath)
            context.strokePath()
            context.addPath(ticks.cgPath)
            context.strokePath()
            // The strokes, white, tinted by the sprite.
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2.2)
            context.addPath(ring.cgPath)
            context.strokePath()
            context.addPath(ticks.cgPath)
            context.strokePath()
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: centre.x - 2.2, y: centre.y - 2.2, width: 4.4, height: 4.4))
        }
    }
    /// The frame's silver, top to foot: a cool light edge (his (201, 192,
    /// 193)) and a warm foot (his (173, 158, 140)), the bevel being the
    /// first and last tenth; the middle is under the well.
    private static let frameSilverStops: [(CGFloat, String)] = [
        (0, "#A89EA0"), (0.04, "#DDD6D6"), (0.094, "#B4ADAC"), (0.5, "#A0978F"),
        (0.906, "#A28F7E"), (0.95, "#BDA990"), (1, "#7C6A5C"),
    ]
    /// The badge's ring, the same silver over its own height.
    private static let ringSilverStops: [(CGFloat, String)] = [
        (0, "#A69C9C"), (0.03, "#DDD6D6"), (0.07, "#BDB6B4"), (0.5, "#A89F9A"),
        (0.93, "#AB9882"), (0.965, "#BCA88F"), (1, "#7A685A"),
    ]
    /// The dark line inside the silver, round the well and the sphere.
    private static let innerLineHex = "#211917"
    /// The dark edge outside the silver: its shadow on whatever it stands over.
    private static let outerEdgeHex = "#1C1512"

    /// A bar's gloss: several stops, no painted highlight over them.
    static func gloss(_ key: String, width: CGFloat, height: CGFloat, radius: CGFloat, stops: [(CGFloat, String)]) -> SKTexture {
        texture(key, size: CGSize(width: width, height: height)) { context, rect in
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
            paintStops(context, in: rect, path: path, stops: stops)
        }
    }

    /// THE FRAME (2026-09-24, the owner's plate): a dark edge, a bevel of
    /// silver (`UnitPlate.bevel`) with a bright crown along its middle, a dark
    /// line inside it, and the well the bars lie in — near-opaque, his dark
    /// warm grey (61, 52, 53), where ours let the floor through at 8%.
    static func frame(_ key: String, width: CGFloat, height: CGFloat) -> SKTexture {
        texture(key, size: CGSize(width: width, height: height)) { context, rect in
            let edge = UnitPlate.frameEdge
            let bevel = UnitPlate.bevel
            context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath)
            context.setFillColor(color(outerEdgeHex).withAlphaComponent(0.8).cgColor)
            context.fillPath()
            let silver = rect.insetBy(dx: edge, dy: edge)
            let silverRadius: CGFloat = 3.25
            paintStops(context, in: silver, path: UIBezierPath(roundedRect: silver, cornerRadius: silverRadius).cgPath,
                       stops: frameSilverStops)
            // The crown: the tube's light, all the way round — his frame's
            // right end peaks at (240, 230, 228).
            let crownInset: CGFloat = bevel * 0.45
            let crown = silver.insetBy(dx: crownInset, dy: crownInset)
            context.addPath(UIBezierPath(roundedRect: crown, cornerRadius: silverRadius - crownInset).cgPath)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.26).cgColor)
            context.setLineWidth(0.6)
            context.strokePath()
            let well = silver.insetBy(dx: bevel, dy: bevel)
            context.addPath(UIBezierPath(roundedRect: well, cornerRadius: 1.75).cgPath)
            context.setFillColor(color(innerLineHex).cgColor)
            context.fillPath()
            let floor = well.insetBy(dx: 0.5, dy: 0.5)
            paintGradient(context, in: floor, path: UIBezierPath(roundedRect: floor, cornerRadius: 1.25).cgPath,
                          top: color("#3D3434"), bottom: color("#2E2626"))
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

    /// The level badge's width: the sphere, or for a level of three figures
    /// a pill a little wider, rather than a smaller number.
    static func levelBadgeWidth(for level: Int) -> CGFloat {
        level >= 100 ? UnitPlate.badgeSize + 10 : UnitPlate.badgeSize
    }

    /// The badge's figures: Manrope's heaviest cut, the genre's fat numerals.
    private static let badgeFace = "Manrope-ExtraBold"
    private static let badgeFigures: CGFloat = 13
    /// The figures' dark edge OUTSIDE the letters, his umber (65, 39, 2).
    private static let badgeFigureEdge: CGFloat = 1.7

    /// THE LEVEL BADGE (2026-09-24, the owner's plate): a metal sphere in
    /// the element's colour — lit at its upper left, deep at its foot, the
    /// floor's light thrown back on its underside and a glint — in a ring of
    /// the frame's silver, and the level in heavy white figures with a thick
    /// dark edge drawn under them (a stroke pass, then the fill, so the edge
    /// never eats the letters), 13 points with a 1.7-point edge: his are
    /// 11.7 points tall and 19.7 across "40". It was a flat dark disc ringed
    /// in the element with 11-point Manrope-Bold in it — his is read from
    /// across the field, ours had to be looked for.
    static func levelBadge(level: Int, hex: String) -> SKTexture {
        let size = CGSize(width: levelBadgeWidth(for: level), height: UnitPlate.badgeSize)
        return texture("level_\(level)_\(hex)", size: size) { context, rect in
            let edge = rect.insetBy(dx: 0.25, dy: 0.25)
            context.addPath(capsule(edge))
            context.setFillColor(color(outerEdgeHex).withAlphaComponent(0.85).cgColor)
            context.fillPath()
            let ring = edge.insetBy(dx: 0.75, dy: 0.75)
            paintStops(context, in: ring, path: capsule(ring), stops: ringSilverStops)
            let crown = ring.insetBy(dx: 0.7, dy: 0.7)
            context.addPath(capsule(crown))
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.26).cgColor)
            context.setLineWidth(0.6)
            context.strokePath()
            let socket = ring.insetBy(dx: 1.6, dy: 1.6)
            context.addPath(capsule(socket))
            context.setFillColor(color(innerLineHex).cgColor)
            context.fillPath()
            paintSphere(context, in: socket.insetBy(dx: 0.55, dy: 0.55), tint: color(hex))

            let points = badgeFigures
            let font = UIFont(name: badgeFace, size: points)
                ?? UIFont(name: Theme.numberFace, size: points)
                ?? UIFont.systemFont(ofSize: points, weight: .heavy)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
            shadow.shadowOffset = CGSize(width: 0, height: 0.5)
            shadow.shadowBlurRadius = 0.8
            let outline = NSAttributedString(string: "\(level)", attributes: [
                .font: font,
                .strokeColor: color("#3A2206"),
                .strokeWidth: 2 * badgeFigureEdge / points * 100,
                .shadow: shadow,
            ])
            let fill = NSAttributedString(string: "\(level)", attributes: [
                .font: font, .foregroundColor: UIColor.white,
            ])
            // The figures' cap height centred on the sphere.
            let width = fill.size().width
            let baseline = rect.midY + font.capHeight / 2
            let origin = CGPoint(x: rect.midX - width / 2, y: baseline - font.ascender)
            context.setLineJoin(.round)
            outline.draw(at: origin)
            fill.draw(at: origin)
        }
    }

    /// A metal sphere (or, for three figures, a capsule) in `tint`: a radial
    /// light from its upper left through the colour to a deep shade, the
    /// floor's bounce on its underside, and a glint. His light sphere runs
    /// (230, 239, 255) at the top to (103, 102, 113) at the foot, with the
    /// bounce lifting its last rows to (142, 144, 171).
    private static func paintSphere(_ context: CGContext, in rect: CGRect, tint: UIColor) {
        let space = CGColorSpaceCreateDeviceRGB()
        let h = rect.height
        context.saveGState()
        context.addPath(capsule(rect))
        context.clip()
        // The colour itself from a fifth of the way out: his spheres are
        // deep and saturated with a small light, and a first cut that mixed
        // white through the middle read as pastel beside them.
        let body = [
            tint.mixed(with: .white, amount: 0.72).cgColor,
            tint.mixed(with: .white, amount: 0.14).cgColor,
            tint.mixed(with: .black, amount: 0.12).cgColor,
            tint.mixed(with: .black, amount: 0.68).cgColor,
        ] as CFArray
        let bodyStops: [CGFloat] = [0, 0.22, 0.52, 1]
        let focus = CGPoint(x: rect.midX - 0.14 * h, y: rect.minY + 0.3 * h)
        let reach: CGFloat = hypot(rect.maxX - focus.x, rect.maxY - focus.y)
        if let gradient = CGGradient(colorsSpace: space, colors: body, locations: bodyStops) {
            context.drawRadialGradient(gradient, startCenter: focus, startRadius: 0,
                                       endCenter: focus, endRadius: reach, options: [.drawsAfterEndLocation])
        }
        let fade: [CGFloat] = [0, 1]
        let bounce = CGPoint(x: rect.midX, y: rect.maxY + 0.1 * h)
        let bounceColors = [
            tint.mixed(with: .white, amount: 0.35).withAlphaComponent(0.4).cgColor,
            tint.withAlphaComponent(0).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: bounceColors, locations: fade) {
            context.drawRadialGradient(gradient, startCenter: bounce, startRadius: 0,
                                       endCenter: bounce, endRadius: 0.5 * h, options: [])
        }
        let glint = CGPoint(x: rect.midX - 0.17 * h, y: rect.minY + 0.24 * h)
        let glintColors = [
            UIColor.white.withAlphaComponent(0.85).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: glintColors, locations: fade) {
            context.drawRadialGradient(gradient, startCenter: glint, startRadius: 0,
                                       endCenter: glint, endRadius: 0.2 * h, options: [])
        }
        context.restoreGState()
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
