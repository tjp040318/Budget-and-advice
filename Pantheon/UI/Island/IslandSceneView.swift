import SwiftUI
import SceneKit
import UIKit

/// A piece standing in one of the island's slots, for the living layer.
struct IslandDecorPlacement: Equatable {
    let slot: DecorSlot
    let decoration: IslandDecoration
}

/// A tap on a figure: a token the living layer acts on once. Two taps on
/// the same figure are two tokens, so the second hops it again.
struct IslandReaction: Equatable {
    let id: UUID
    let index: Int

    init(index: Int) {
        id = UUID()
        self.index = index
    }
}

/// A decoration standing in the living layer: the prop, its shadow and,
/// for a brazier, its flame, its light and the glow on the sand.
private struct IslandDecorEntry {
    let placement: IslandDecorPlacement
    let holder: SCNNode
    let shadow: SCNNode
    let flame: SCNNode?
    let lamp: SCNNode?
    let glow: SCNNode?
    /// The prop's own height and width, in metres.
    let metres: Float
    let width: Float
}

/// A particle system placed at a point of the painting.
private struct IslandWeatherEntry {
    let node: SCNNode
    let point: CGPoint
    let depth: Float
}

/// The island's living layer: the player's team standing about on the
/// painting in their idle clips, the decorations the player has stood on
/// the sand, sparks over the summoning pool, a flame at the obelisk's tip,
/// the sun's glitter on the sea and fireflies in the scrub after dark, drawn
/// by SceneKit into a transparent view between the painting and the
/// buildings' bubbles. Since 2026-09-17 it follows the camera: every point
/// is placed off the painting's frame, which pans and zooms, and the figures
/// react to a tap (`IslandReaction`) or stir by themselves.
///
/// The camera is orthographic and looks straight at the painting, so one
/// world unit is one screen point and a figure's feet go on a point of the
/// painting directly: `IslandView.camera` says where the painting lands,
/// the stand says where on it, and the figure is scaled to about a tenth of
/// the screen's height at rest — the size Summoners War's island draws its
/// monsters at — and grows with the zoom.
struct IslandSceneView: UIViewRepresentable {
    let units: [ResolvedUnit]
    /// Where each unit stands, in painting coordinates (0...1).
    let stands: [CGPoint]
    let decorations: [IslandDecorPlacement]
    /// The painting's frame in the view's own coordinates.
    let paintingFrame: CGRect
    let viewSize: CGSize
    /// The hour's light on the figures.
    let lightHex: String
    let isNight: Bool
    /// The camera's zoom: the figures and the pieces grow with the painting.
    let zoom: CGFloat
    /// A tap on a figure, acted on once.
    var reaction: IslandReaction? = nil
    /// False while another tab is up. `SCNView` renders continuously here so
    /// the figures idle; a hidden one drawing four skinned characters thirty
    /// times a second is a tax on whichever screen is showing, so it stops
    /// playing the moment the island is not the screen.
    var isActive: Bool = true
    /// Called on the main thread when a figure stirs by itself, with its
    /// index, so the screen can name it.
    var onStir: ((Int) -> Void)? = nil

    /// A figure's height as a fraction of the stage's (`stageHeight`).
    static let figureHeight: CGFloat = 0.11

    /// The height the island's figures, props and weather are sized from.
    /// It was the screen's height until 2026-09-23, when the tab bar went
    /// from lying OVER the island to being laid out below it: the island's
    /// view lost about 79 points and every figure, brazier and ember shrank
    /// a fifth, although the painting stayed the same size (on a landscape
    /// phone it covers the view by its width). So the stage is the
    /// painting's own displayed height, zoom included, scaled so the
    /// reference phone (874 x 402 before the change, the painting drawn
    /// 491.6 points tall) keeps every size it had.
    static func stageHeight(paintingFrame: CGRect) -> CGFloat {
        let reference: CGFloat = 402.0 / 491.6
        return paintingFrame.height * reference
    }

    /// The scrub where the fireflies come out at night, on the painting.
    static let fireflyPatches: [CGPoint] = [
        CGPoint(x: 0.22, y: 0.50), CGPoint(x: 0.57, y: 0.53), CGPoint(x: 0.80, y: 0.55)
    ]

    /// Depth from a height on the painting: lower on the painting is nearer
    /// the viewer, so it draws over what stands behind it. The camera is at
    /// z 120 looking down -z; the sand runs from about -6 (the hall's shore)
    /// to +8 (the surf).
    static func depth(_ paintingY: CGFloat) -> Float { Float((paintingY - 0.5) * 30) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling2X
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false
        view.delegate = context.coordinator.cloth
        // Thirty frames a second at every frame-rate choice (the island is
        // ambient), and the effects and shadow choices applied live, since
        // this view is never rebuilt (`Docs/SETTINGS.md` §2).
        GraphicsSettings.configure(view, for: .island)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.rendersContinuously != isActive {
            view.rendersContinuously = isActive
            view.isPlaying = isActive
        }
        context.coordinator.onStir = onStir
        context.coordinator.update(
            units: units, stands: stands, decorations: decorations, paintingFrame: paintingFrame,
            viewSize: viewSize, lightHex: lightHex, isNight: isNight, zoom: zoom, isActive: isActive
        )
        if let reaction { context.coordinator.react(reaction) }
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let scene = SCNScene()
        /// Steps the figures' capes each frame; the view's delegate is weak.
        let cloth = ClothStepper()
        var onStir: ((Int) -> Void)?

        private let cameraNode = SCNNode()
        private let keyLight = SCNNode()
        private let fillLight = SCNNode()
        private let figures = SCNNode()
        private let decor = SCNNode()
        private let weather = SCNNode()

        private var figureNodes: [UnitNode] = []
        private var figureShadows: [SCNNode] = []
        private var figureStands: [CGPoint] = []
        /// Each figure's height in its own metres, and whether its family
        /// shipped a victory clip to play when it is tapped.
        private var figureMetres: [Float] = []
        private var figureHasVictory: [Bool] = []
        private var figureBases: [SCNVector3] = []
        private var figuresKey = ""
        /// The wander (2026-09-17): a family that shipped a walk clip strolls
        /// the sand around its stand instead of hopping when it stirs. The
        /// offset is where the figure stands now, in fractions of the
        /// painting from its stand; a walk in progress is a `Walk`, moved by
        /// a custom action that reads the LATEST layout every frame, so a
        /// pan or a zoom during the stroll carries the walker with the sand.
        private var figureHasWalk: [Bool] = []
        private var figureOffsets: [CGPoint] = []
        private var walks: [Int: Walk] = [:]
        private var layout: (paintingFrame: CGRect, viewSize: CGSize, zoom: CGFloat)?
        /// How far from its stand a figure ever strolls, in fractions of the
        /// painting: the stands are on the sand, and a radius this small
        /// stays there (about 50 pt on the phone at zoom 1).
        /// (Instance constants, not statics: a static on a class named
        /// `Coordinator` makes the checker read every `Coordinator.x` in the
        /// tree, and the battle view's `#selector(Coordinator.handleTap)`
        /// is another class of that name.)
        private let wanderRadius = CGPoint(x: 0.028, y: 0.018)
        /// Metres a second, in the figure's own metres; the walk clip is a
        /// casual stroll and a little foot-slide at this size is invisible.
        private let wanderSpeed: CGFloat = 1.05

        private struct Walk {
            let from: CGPoint
            let to: CGPoint
            var progress: CGFloat = 0
            var offset: CGPoint {
                CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
            }
        }

        private var decorEntries: [IslandDecorEntry] = []
        private var decorKey = ""
        private var flameScales: [String: Float] = [:]

        private var weatherEntries: [IslandWeatherEntry] = []
        private var weatherKey = ""

        private var lastReaction: UUID?
        private var stirTimer: Timer?
        private var active = false

        init() {
            scene.background.contents = UIColor.clear

            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            camera.zNear = 1
            camera.zFar = 400
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 120)
            scene.rootNode.addChildNode(cameraNode)

            let key = SCNLight()
            key.type = .directional
            key.intensity = 900
            keyLight.light = key
            keyLight.eulerAngles = SCNVector3(-0.7, 0.5, 0)
            scene.rootNode.addChildNode(keyLight)

            let fill = SCNLight()
            fill.type = .ambient
            fill.intensity = 380
            fill.color = UIColor(white: 0.85, alpha: 1)
            fillLight.light = fill
            scene.rootNode.addChildNode(fillLight)

            scene.rootNode.addChildNode(figures)
            scene.rootNode.addChildNode(decor)
            scene.rootNode.addChildNode(weather)
        }

        func update(
            units: [ResolvedUnit], stands: [CGPoint], decorations: [IslandDecorPlacement], paintingFrame: CGRect,
            viewSize: CGSize, lightHex: String, isNight: Bool, zoom: CGFloat, isActive: Bool
        ) {
            guard viewSize.width > 0, viewSize.height > 0, paintingFrame.width > 0 else { return }
            cameraNode.camera?.orthographicScale = Double(viewSize.height / 2)
            keyLight.light?.color = UIColor(hex: lightHex) ?? UIColor.white
            keyLight.light?.intensity = isNight ? 620 : 900
            fillLight.light?.intensity = isNight ? 300 : 380

            // The figures are rebuilt only when the team changes; a pan or a
            // zoom moves and rescales what stands, which is cheap enough to
            // do on every drag event.
            let standing = Array(units.prefix(stands.count))
            let unitKey = standing.map { $0.id.uuidString + ($0.unit.isAwakened ? "a" : "") }.joined(separator: ",")
            if figuresKey != unitKey {
                figuresKey = unitKey
                rebuildFigures(standing, stands: stands)
            }
            layoutFigures(paintingFrame: paintingFrame, viewSize: viewSize, zoom: zoom)

            let placementKey = decorations.map { "\($0.slot.id):\($0.decoration.id)" }.joined(separator: ",")
            if decorKey != placementKey {
                decorKey = placementKey
                rebuildDecor(decorations)
            }
            layoutDecor(paintingFrame: paintingFrame, viewSize: viewSize, zoom: zoom, isNight: isNight)

            // The particle systems are sized off the screen and the zoom, so
            // they are rebuilt at each eighth of a zoom step and when night
            // falls; their positions follow the painting every update.
            let key = "\(Int(viewSize.height))@\(Int(zoom * 8))\(isNight ? "n" : "d")"
            if weatherKey != key {
                weatherKey = key
                rebuildWeather(viewSize: viewSize, paintingFrame: paintingFrame, zoom: zoom, isNight: isNight)
            }
            for entry in weatherEntries {
                let point = screenPoint(entry.point, paintingFrame: paintingFrame, viewSize: viewSize)
                entry.node.position = SCNVector3(Float(point.x), Float(point.y), entry.depth)
            }

            active = isActive
            if isActive {
                armStir()
            } else {
                stirTimer?.invalidate()
                stirTimer = nil
            }
        }

        func stop() {
            stirTimer?.invalidate()
            stirTimer = nil
            active = false
        }

        // MARK: - Figures

        private func rebuildFigures(_ units: [ResolvedUnit], stands: [CGPoint]) {
            let started = Perf.begin()
            defer { Perf.end(started, "island: \(units.count) figures rebuilt", over: 30) }
            let live = !figureNodes.isEmpty
            // The old figures stop their strolls and hops and leave through
            // `VFXLibrary.dismiss`: an awakened one carries a live aura, and a
            // node freed with its motes alive is 2026-09-15's crash.
            for child in figures.childNodes {
                child.enumerateHierarchy { node, _ in node.removeAllActions() }
                VFXLibrary.dismiss(child, reportsLive: false)
            }
            figureNodes = []
            figureShadows = []
            figureStands = []
            figureMetres = []
            figureHasVictory = []
            figureBases = []
            figureHasWalk = []
            figureOffsets = []
            walks = [:]
            for (index, unit) in units.enumerated() {
                let combatant = Combatant(resolved: unit, side: .player, slot: index, isLeader: index == 0)
                let node = UnitNode(combatant: combatant, detail: .high)
                node.hideBattleDecorations()
                figures.addChildNode(node)
                // A team changed while the island was up goes into a scene
                // that is already rendering, where an idle attached before
                // the figure was in it never starts (the Hall of Ka's frozen
                // Zeus, 2026-09-17): started again from inside the scene.
                if live { node.restartIdle() } else { node.play(node.restingIdle) }
                let shadow = shadow()
                figures.addChildNode(shadow)
                figureNodes.append(node)
                figureShadows.append(shadow)
                figureStands.append(stands[index])
                figureMetres.append(max(0.5, unit.blueprint.model.height))
                let asset = unit.blueprint.model.assetName
                figureHasVictory.append(
                    Bundle.main.url(forResource: "\(asset)_victory", withExtension: "usdz", subdirectory: ModelLibrary.modelDirectory) != nil
                )
                figureHasWalk.append(
                    Bundle.main.url(forResource: "\(asset)_walk", withExtension: "usdz", subdirectory: ModelLibrary.modelDirectory) != nil
                )
                figureOffsets.append(.zero)
                figureBases.append(SCNVector3(0, 0, 0))
            }
        }

        private func layoutFigures(paintingFrame: CGRect, viewSize: CGSize, zoom: CGFloat) {
            layout = (paintingFrame, viewSize, zoom)
            for (index, node) in figureNodes.enumerated() {
                let scale = Float(IslandSceneView.stageHeight(paintingFrame: paintingFrame) * IslandSceneView.figureHeight) / figureMetres[index]
                node.scale = SCNVector3(scale, scale, scale)
                let width = CGFloat(scale) * 1.1
                figureShadows[index].scale = SCNVector3(Float(width), Float(width), 1)
                // A walker is placed every frame by its own action, from the
                // layout just stored.
                if walks[index] != nil { continue }
                let spot = standingPoint(index, offset: figureOffsets[index])
                let point = spot.point
                let base = SCNVector3(Float(point.x), Float(point.y), spot.depth)
                // Set only when it moved: a hop in progress is a relative
                // move from wherever the figure stands, and re-setting the
                // same position under it every update would stall it.
                let old = figureBases[index]
                if old.x != base.x || old.y != base.y || old.z != base.z {
                    figureBases[index] = base
                    node.removeAction(forKey: "hop")
                    node.position = base
                }
                placeShadow(index, at: point, depth: spot.depth)
            }
        }

        /// Where a figure stands, its stand plus an offset, in the view's
        /// world, with the depth its height on the painting gives it.
        private func standingPoint(_ index: Int, offset: CGPoint) -> (point: CGPoint, depth: Float) {
            guard let layout else { return (.zero, 0) }
            let spot = CGPoint(x: figureStands[index].x + offset.x, y: figureStands[index].y + offset.y)
            return (screenPoint(spot, paintingFrame: layout.paintingFrame, viewSize: layout.viewSize),
                    IslandSceneView.depth(spot.y))
        }

        private func placeShadow(_ index: Int, at point: CGPoint, depth: Float) {
            let shadow = figureShadows[index]
            let width = CGFloat(shadow.scale.x)
            shadow.position = SCNVector3(Float(point.x), Float(point.y) + Float(width * 0.03), depth - 1.5)
        }

        /// A tap on a figure: acted on once per token.
        func react(_ reaction: IslandReaction) {
            guard reaction.id != lastReaction else { return }
            lastReaction = reaction.id
            hop(reaction.index)
        }

        /// The figure hops on the spot and plays its victory clip where the
        /// family shipped one, its basic swing where not; back to its idle
        /// after.
        private func hop(_ index: Int) {
            guard figureNodes.indices.contains(index) else { return }
            let node = figureNodes[index]
            stopWalk(index)
            let rise = CGFloat(node.scale.y * figureMetres[index]) * 0.14
            node.removeAction(forKey: "hop")
            node.position = figureBases[index]
            let up = SCNAction.moveBy(x: 0, y: rise, z: 0, duration: 0.17)
            up.timingMode = .easeOut
            let down = SCNAction.moveBy(x: 0, y: -rise, z: 0, duration: 0.2)
            down.timingMode = .easeIn
            node.runAction(.sequence([up, down]), forKey: "hop")
            node.play(figureHasVictory[index] ? .victory : .attackBasic) { [weak node] in
                guard let node else { return }
                node.play(node.restingIdle)
            }
        }

        /// Every 9–15 s one figure stirs by itself, so the island is never
        /// four statues; the screen is told which so it can name it.
        private func armStir() {
            guard stirTimer == nil, !figureNodes.isEmpty else { return }
            let delay = Double.random(in: 9...15)
            stirTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.stirTimer = nil
                guard self.active, !self.figureNodes.isEmpty else { return }
                let index = Int.random(in: 0..<self.figureNodes.count)
                if self.figureHasWalk[index], self.walks[index] == nil, self.layout != nil {
                    self.wander(index)
                } else {
                    self.hop(index)
                    self.onStir?(index)
                }
                self.armStir()
            }
        }

        /// A stroll to a new spot on the sand near the stand: the figure
        /// turns to face the way it goes, plays its walk clip along a custom
        /// action that reads the latest layout every frame, and turns back
        /// to the viewer with its idle when it arrives.
        private func wander(_ index: Int) {
            guard figureNodes.indices.contains(index), let layout else { return }
            let node = figureNodes[index]
            let from = figureOffsets[index]
            var to = from
            // Somewhere at least a stride away, inside the wander radius.
            for _ in 0..<8 {
                let candidate = CGPoint(x: CGFloat.random(in: -wanderRadius.x...wanderRadius.x),
                                        y: CGFloat.random(in: -wanderRadius.y...wanderRadius.y))
                if hypot(candidate.x - from.x, (candidate.y - from.y) * 1.6) > 0.012 { to = candidate; break }
            }
            if to == from { return }
            let start = standingPoint(index, offset: from).point
            let end = standingPoint(index, offset: to).point
            let distance = hypot(end.x - start.x, end.y - start.y)
            let pointsPerMetre = CGFloat(node.scale.y)
            let duration = max(0.8, Double(distance / (pointsPerMetre * wanderSpeed)))
            // A model is authored facing +Z, toward the viewer; up the
            // painting is away, so the heading is atan2(dx, -dy).
            let yaw = atan2(to.x - from.x, -(to.y - from.y) * (layout.paintingFrame.height / layout.paintingFrame.width))
            walks[index] = Walk(from: from, to: to)
            node.removeAction(forKey: "hop")
            node.removeAction(forKey: "walk")
            let turn = SCNAction.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.25, usesShortestUnitArc: true)
            // The stroll itself is stepped on the MAIN thread by a timer
            // (`startStroll(_:node:to:began:duration:)`), not by a custom
            // action: SceneKit runs an action's block on its render thread,
            // and this one wrote `walks` and read the layout and the figure
            // arrays while the main thread rebuilt them for a team change — a
            // Swift dictionary written from two threads at once (2026-09-24,
            // the move `UnitNode.swingTrail` made for run 239). The timer also
            // ENDS the walk: a scene-time wait for the end froze with the
            // island when the player left it mid-stroll, and the figure came
            // back walking in place at its goal.
            node.runAction(turn, forKey: "walk")
            startStroll(index, node: node, to: to, began: CACurrentMediaTime() + 0.25, duration: duration)
            node.play(.walk)
        }

        /// Moves a strolling figure along its walk, sixty times a second on
        /// the main thread, reading the latest layout each step so a pan or a
        /// pinch mid-walk carries it along; holds while the island is not on
        /// screen, and at the end turns the figure back to the viewer with
        /// its idle. Stops by itself when the walk is over, cut short,
        /// replaced, or the figures were rebuilt.
        private func startStroll(_ index: Int, node: UnitNode, to: CGPoint, began: CFTimeInterval, duration: TimeInterval) {
            // A box, not two captured vars: the timer's block is @Sendable,
            // and a mutated captured var in one does not compile.
            let clock = StrollClock(began: began, last: CACurrentMediaTime())
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak node] timer in
                guard let self, let node,
                      self.figureNodes.indices.contains(index), self.figureNodes[index] === node,
                      var walk = self.walks[index], walk.to == to else {
                    timer.invalidate()
                    return
                }
                let now = CACurrentMediaTime()
                defer { clock.last = now }
                guard self.active else {
                    clock.began += now - clock.last      // the island is away: the walk waits for it
                    return
                }
                let t = min(1, max(0, CGFloat((now - clock.began) / duration)))
                // Ease at both ends so the figure sets off and arrives
                // rather than starting at full stride.
                walk.progress = t * t * (3 - 2 * t)
                self.walks[index] = walk
                let spot = self.standingPoint(index, offset: walk.offset)
                node.position = SCNVector3(Float(spot.point.x), Float(spot.point.y), spot.depth)
                self.placeShadow(index, at: spot.point, depth: spot.depth)
                if t >= 1 {
                    timer.invalidate()
                    node.runAction(SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.3, usesShortestUnitArc: true),
                                   forKey: "walk")
                    self.settleWalk(index, at: to)
                    node.play(node.restingIdle)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }

        /// The walk is over, or cut short by a tap: the figure stands where
        /// it is and that spot is its place until the next stroll.
        private func settleWalk(_ index: Int, at offset: CGPoint) {
            guard figureNodes.indices.contains(index) else { return }
            walks[index] = nil
            figureOffsets[index] = offset
            let spot = standingPoint(index, offset: offset)
            let base = SCNVector3(Float(spot.point.x), Float(spot.point.y), spot.depth)
            figureBases[index] = base
            figureNodes[index].position = base
            placeShadow(index, at: spot.point, depth: spot.depth)
        }

        private func stopWalk(_ index: Int) {
            guard let walk = walks[index] else { return }
            let node = figureNodes[index]
            node.removeAction(forKey: "walk")
            node.eulerAngles = SCNVector3Zero
            settleWalk(index, at: walk.offset)
        }

        // MARK: - Decorations

        private func rebuildDecor(_ placements: [IslandDecorPlacement]) {
            // A brazier's flame is a live particle host (`VFXLibrary.dismiss`).
            decor.childNodes.forEach { VFXLibrary.dismiss($0, reportsLive: false) }
            decorEntries = []
            flameScales = [:]
            for placement in placements {
                guard let prop = StageBuilder.loadProp(placement.decoration.asset) else { continue }
                let box = bounds(of: prop)
                let metres = max(0.2, box.max.y - box.min.y)
                // Centred on its footprint with its feet on the holder's
                // origin, so the holder's position is where the piece stands.
                let holder = SCNNode()
                prop.position = SCNVector3(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2)
                holder.addChildNode(prop)
                decor.addChildNode(holder)
                let shadow = shadow()
                decor.addChildNode(shadow)

                var flame: SCNNode?
                var lamp: SCNNode?
                var glow: SCNNode?
                if placement.decoration.burns {
                    let tint = UIColor(hex: placement.decoration.flameHex) ?? UIColor.orange
                    let fire = SCNNode()
                    decor.addChildNode(fire)
                    flame = fire

                    let light = SCNNode()
                    let omni = SCNLight()
                    omni.type = .omni
                    omni.color = tint
                    omni.intensity = 800
                    light.light = omni
                    decor.addChildNode(light)
                    lamp = light

                    // A warm pool on the sand under the bowl, additive, on a
                    // parent whose opacity the hour sets while the child
                    // flickers on its own.
                    let plane = SCNPlane(width: 1, height: 0.42)
                    let material = SCNMaterial()
                    material.diffuse.contents = UIImage(named: "spark")
                    material.multiply.contents = tint
                    material.lightingModel = .constant
                    material.blendMode = .add
                    material.writesToDepthBuffer = false
                    material.readsFromDepthBuffer = false
                    material.isDoubleSided = true
                    plane.materials = [material]
                    let disc = SCNNode(geometry: plane)
                    let flickerUp = SCNAction.fadeOpacity(to: 1.0, duration: 0.35)
                    let flickerDown = SCNAction.fadeOpacity(to: 0.62, duration: 0.45)
                    disc.runAction(.repeatForever(.sequence([flickerUp, flickerDown])))
                    let host = SCNNode()
                    host.addChildNode(disc)
                    decor.addChildNode(host)
                    glow = host
                }
                decorEntries.append(IslandDecorEntry(
                    placement: placement, holder: holder, shadow: shadow, flame: flame, lamp: lamp, glow: glow,
                    metres: metres, width: max(0.2, box.max.x - box.min.x)
                ))
            }
        }

        private func layoutDecor(paintingFrame: CGRect, viewSize: CGSize, zoom: CGFloat, isNight: Bool) {
            for entry in decorEntries {
                let point = screenPoint(entry.placement.slot.point, paintingFrame: paintingFrame, viewSize: viewSize)
                // The piece's height on screen, in points.
                let target = Float(IslandSceneView.stageHeight(paintingFrame: paintingFrame) * entry.placement.decoration.height)
                let scale = target / entry.metres
                let depth = IslandSceneView.depth(entry.placement.slot.point.y)
                entry.holder.scale = SCNVector3(scale, scale, scale)
                entry.holder.position = SCNVector3(Float(point.x), Float(point.y), depth)
                let width = CGFloat(entry.width * scale) * 1.15
                entry.shadow.scale = SCNVector3(Float(width), Float(width), 1)
                entry.shadow.position = SCNVector3(Float(point.x), Float(point.y) + Float(width * 0.03), depth - 1.5)

                guard let flame = entry.flame else { continue }
                let rim = Float(point.y) + target * 0.86
                flame.position = SCNVector3(Float(point.x), rim, depth + 1)
                // The flame is sized in points per metre and rebuilt when
                // the zoom has moved it by more than a twentieth.
                let key = entry.placement.slot.id
                if abs((flameScales[key] ?? 0) - scale) > scale * 0.05 {
                    flameScales[key] = scale
                    flame.removeAllParticleSystems()
                    let tint = UIColor(hex: entry.placement.decoration.flameHex) ?? UIColor.orange
                    flame.addParticleSystem(fire(tint: tint, pointsPerMetre: scale))
                }
                if let lamp = entry.lamp {
                    lamp.position = SCNVector3(Float(point.x), rim + target * 0.2, depth + 8)
                    lamp.light?.attenuationStartDistance = 0
                    lamp.light?.attenuationEndDistance = CGFloat(target) * 3.2
                    lamp.light?.intensity = isNight ? 1_400 : 800
                }
                if let glow = entry.glow {
                    glow.scale = SCNVector3(target * 2.2, target * 2.2, 1)
                    glow.position = SCNVector3(Float(point.x), Float(point.y) + target * 0.05, depth - 1)
                    glow.opacity = isNight ? 0.85 : 0.45
                }
            }
        }

        /// A brazier's fire in a world where a metre is `scale` points:
        /// `VFXLibrary.flame` sizes its emitter and motes in metres and its
        /// speed in metres a second, so the speed is scaled here too.
        private func fire(tint: UIColor, pointsPerMetre scale: Float) -> SCNParticleSystem {
            let system = VFXLibrary.flame(tint: tint, scale: scale)
            system.particleVelocity = CGFloat(1.3 * scale)
            system.particleVelocityVariation = CGFloat(0.5 * scale)
            system.acceleration = SCNVector3(0, 1.6 * scale, 0)
            return system
        }

        /// The box round everything under `node`, in `node`'s own space. A
        /// prop is a wrapper round the file's nodes, so its own bounding box
        /// says nothing; the children's are gathered corner by corner.
        private func bounds(of node: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
            var lo = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
            var hi = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
            var found = false
            node.enumerateHierarchy { child, _ in
                guard child.geometry != nil else { return }
                let (a, b) = child.boundingBox
                let corners = [
                    SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, a.y, a.z), SCNVector3(a.x, b.y, a.z), SCNVector3(b.x, b.y, a.z),
                    SCNVector3(a.x, a.y, b.z), SCNVector3(b.x, a.y, b.z), SCNVector3(a.x, b.y, b.z), SCNVector3(b.x, b.y, b.z)
                ]
                for corner in corners {
                    let p = node.convertPosition(corner, from: child)
                    lo = SCNVector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                    hi = SCNVector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
                    found = true
                }
            }
            guard found else { return (SCNVector3(0, 0, 0), SCNVector3(1, 1, 1)) }
            return (lo, hi)
        }

        // MARK: - Weather

        private func rebuildWeather(viewSize: CGSize, paintingFrame: CGRect, zoom: CGFloat, isNight: Bool) {
            // Every host here carries a live looping system: each leaves the
            // way a particle carrier does (`VFXLibrary.dismiss`: systems off
            // on this thread, hidden now, removed half a second of frames
            // later), never freed on the spot mid-pinch (2026-09-24).
            weather.childNodes.forEach { VFXLibrary.dismiss($0, reportsLive: false) }
            weatherEntries = []
            let unit = IslandSceneView.stageHeight(paintingFrame: paintingFrame) / 100

            func add(_ point: CGPoint, depth: Float, _ system: SCNParticleSystem) {
                let node = SCNNode()
                node.addParticleSystem(system)
                weather.addChildNode(node)
                weatherEntries.append(IslandWeatherEntry(node: node, point: point, depth: depth))
            }

            // Sparks rising off the summoning pool.
            add(CGPoint(x: 0.44, y: 0.50), depth: 7, sparkle(
                tint: UIColor(hex: "#7FE0FF") ?? UIColor.cyan,
                size: unit * 1.1, spread: paintingFrame.width * 0.055, rise: unit * 9, rate: 14
            ))
            // The flame at the obelisk's tip.
            add(CGPoint(x: 0.888, y: 0.235), depth: 4, sparkle(
                tint: UIColor(hex: "#FFD27A") ?? UIColor.orange,
                size: unit * 1.6, spread: unit * 1.2, rise: unit * 6, rate: 22
            ))
            // The sun's glitter on the sea, in the band of its reflection;
            // the moon's after dark.
            add(CGPoint(x: 0.72, y: 0.26), depth: -9, glitter(
                tint: UIColor(hex: isNight ? "#CFE2FF" : "#FFE9A6") ?? UIColor.white,
                size: unit * 0.9, spread: paintingFrame.width * 0.24, band: paintingFrame.height * 0.05
            ))
            if isNight {
                for patch in IslandSceneView.fireflyPatches {
                    add(patch, depth: IslandSceneView.depth(patch.y) + 2, fireflies(
                        size: unit * 0.7, spread: paintingFrame.width * 0.06, band: paintingFrame.height * 0.05, drift: unit * 1.2
                    ))
                }
            }
        }

        private func sparkle(tint: UIColor, size: CGFloat, spread: CGFloat, rise: CGFloat, rate: CGFloat) -> SCNParticleSystem {
            let system = SCNParticleSystem()
            system.birthRate = rate
            system.particleLifeSpan = 2.0
            system.particleLifeSpanVariation = 0.8
            system.emitterShape = SCNBox(width: spread, height: size, length: size, chamferRadius: 0)
            system.particleSize = size
            system.particleSizeVariation = size * 0.5
            system.particleColor = tint
            system.particleColorVariation = SCNVector4(0.04, 0.04, 0.04, 0.35)
            system.particleVelocity = rise
            system.particleVelocityVariation = rise * 0.4
            system.emittingDirection = SCNVector3(0, 1, 0)
            system.spreadingAngle = 30
            system.blendMode = .additive
            system.isLightingEnabled = false
            system.particleImage = UIImage(named: "spark")
            return system
        }

        /// Slow points of light that twinkle in a flat band and barely move.
        private func glitter(tint: UIColor, size: CGFloat, spread: CGFloat, band: CGFloat) -> SCNParticleSystem {
            let system = SCNParticleSystem()
            system.birthRate = 9
            system.particleLifeSpan = 1.6
            system.particleLifeSpanVariation = 0.8
            system.birthLocation = .volume
            system.emitterShape = SCNBox(width: spread, height: band, length: 1, chamferRadius: 0)
            system.particleSize = size
            system.particleSizeVariation = size * 0.5
            system.particleColor = tint
            system.particleVelocity = 0
            system.particleVelocityVariation = size * 0.3
            system.spreadingAngle = 180
            system.blendMode = .additive
            system.isLightingEnabled = false
            system.particleImage = UIImage(named: "spark")
            system.propertyControllers = [.opacity: twinkle([0, 1, 0.3, 1, 0], times: [0, 0.25, 0.5, 0.75, 1])]
            return system
        }

        /// Few, small, long-lived, drifting through the scrub and blinking.
        private func fireflies(size: CGFloat, spread: CGFloat, band: CGFloat, drift: CGFloat) -> SCNParticleSystem {
            let system = SCNParticleSystem()
            system.birthRate = 2.5
            system.particleLifeSpan = 5
            system.particleLifeSpanVariation = 2
            system.birthLocation = .volume
            system.emitterShape = SCNBox(width: spread, height: band, length: 1, chamferRadius: 0)
            system.particleSize = size
            system.particleSizeVariation = size * 0.3
            system.particleColor = UIColor(hex: "#D8FF80") ?? UIColor.green
            system.particleVelocity = drift
            system.particleVelocityVariation = drift * 0.6
            system.spreadingAngle = 180
            system.blendMode = .additive
            system.isLightingEnabled = false
            system.particleImage = UIImage(named: "spark")
            system.propertyControllers = [.opacity: twinkle([0, 1, 0.1, 1, 0.1, 1, 0], times: [0, 0.15, 0.35, 0.5, 0.7, 0.85, 1])]
            return system
        }

        /// An opacity curve over a particle's life.
        private func twinkle(_ values: [Float], times: [Float]) -> SCNParticlePropertyController {
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = values.map { NSNumber(value: $0) }
            animation.keyTimes = times.map { NSNumber(value: $0) }
            return SCNParticlePropertyController(animation: animation)
        }

        // MARK: - Helpers

        /// A painting point in the view's world, where a screen point is a
        /// world unit and the origin is the screen's centre.
        private func screenPoint(_ anchor: CGPoint, paintingFrame: CGRect, viewSize: CGSize) -> CGPoint {
            CGPoint(
                x: paintingFrame.minX + anchor.x * paintingFrame.width - viewSize.width / 2,
                y: viewSize.height / 2 - (paintingFrame.minY + anchor.y * paintingFrame.height)
            )
        }

        /// A soft dark pill under the feet, a unit wide, scaled to the figure
        /// when it is placed, so it sits on the sand instead of floating.
        private func shadow() -> SCNNode {
            let plane = SCNPlane(width: 1, height: 0.3)
            plane.cornerRadius = 0.15
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0, alpha: 0.32)
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            plane.materials = [material]
            return SCNNode(geometry: plane)
        }
    }
}

/// A stroll's clock on the island (`startStroll`): when it began, pushed
/// back by every moment the island was away, and the last tick. Main thread.
private final class StrollClock {
    var began: CFTimeInterval
    var last: CFTimeInterval
    init(began: CFTimeInterval, last: CFTimeInterval) {
        self.began = began
        self.last = last
    }
}
