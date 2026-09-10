import SwiftUI
import SceneKit
import UIKit

/// The island's living layer: the player's team standing about on the
/// painting in their idle clips, sparks over the summoning pool and a flame
/// at the obelisk's tip, drawn by SceneKit into a transparent view between
/// the painting and the plaques. Phase A of the living island: figures and
/// weather; the buildings stay painted.
///
/// The camera is orthographic and looks straight at the painting, so one
/// world unit is one screen point and a figure's feet go on a point of the
/// painting directly: `IslandView.fill` says where the painting lands, the
/// stand says where on it, and the figure is scaled to about a tenth of the
/// screen's height, the size Summoners War's island draws its monsters at.
struct IslandSceneView: UIViewRepresentable {
    let units: [ResolvedUnit]
    /// Where each unit stands, in painting coordinates (0...1).
    let stands: [CGPoint]
    /// The painting's frame in the view's own coordinates.
    let paintingFrame: CGRect
    let viewSize: CGSize
    /// The hour's light on the figures.
    let lightHex: String
    /// False while another tab is up. `SCNView` renders continuously here so
    /// the figures idle; a hidden one drawing four skinned characters thirty
    /// times a second is a tax on whichever screen is showing, so it stops
    /// playing the moment the island is not the screen.
    var isActive: Bool = true

    /// A figure's height as a fraction of the screen's.
    static let figureHeight: CGFloat = 0.11

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.rendersContinuously != isActive {
            view.rendersContinuously = isActive
            view.isPlaying = isActive
        }
        context.coordinator.update(
            units: units, stands: stands, paintingFrame: paintingFrame, viewSize: viewSize, lightHex: lightHex
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let scene = SCNScene()
        private let cameraNode = SCNNode()
        private let keyLight = SCNNode()
        private let figures = SCNNode()
        private let weather = SCNNode()
        private var figuresKey = ""
        private var weatherKey = ""

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

            let ambient = SCNNode()
            let fill = SCNLight()
            fill.type = .ambient
            fill.intensity = 380
            fill.color = UIColor(white: 0.85, alpha: 1)
            ambient.light = fill
            scene.rootNode.addChildNode(ambient)

            scene.rootNode.addChildNode(figures)
            scene.rootNode.addChildNode(weather)
        }

        func update(units: [ResolvedUnit], stands: [CGPoint], paintingFrame: CGRect, viewSize: CGSize, lightHex: String) {
            guard viewSize.width > 0, viewSize.height > 0 else { return }
            cameraNode.camera?.orthographicScale = Double(viewSize.height / 2)
            keyLight.light?.color = UIColor(hex: lightHex) ?? UIColor.white

            let sizeKey = "\(Int(viewSize.width))x\(Int(viewSize.height))@\(Int(paintingFrame.minX)),\(Int(paintingFrame.minY))"
            let unitKey = units.map { $0.id.uuidString + ($0.unit.isAwakened ? "a" : "") }.joined(separator: ",")
            if figuresKey != sizeKey + unitKey {
                figuresKey = sizeKey + unitKey
                let started = Perf.begin()
                defer { Perf.end(started, "island: \(min(units.count, stands.count)) figures rebuilt", over: 30) }
                figures.childNodes.forEach { $0.removeFromParentNode() }
                for (index, unit) in units.prefix(stands.count).enumerated() {
                    let combatant = Combatant(resolved: unit, side: .player, slot: index, isLeader: index == 0)
                    let node = UnitNode(combatant: combatant, detail: .high)
                    node.hideBattleDecorations()
                    let point = screenPoint(stands[index], paintingFrame: paintingFrame, viewSize: viewSize)
                    let scale = Float(viewSize.height * IslandSceneView.figureHeight) / max(0.5, unit.blueprint.model.height)
                    node.scale = SCNVector3(scale, scale, scale)
                    node.position = SCNVector3(Float(point.x), Float(point.y), Float(index) * -2)
                    figures.addChildNode(node)
                    figures.addChildNode(shadow(at: point, width: CGFloat(scale) * 1.1))
                }
            }

            if weatherKey != sizeKey {
                weatherKey = sizeKey
                weather.childNodes.forEach { $0.removeFromParentNode() }
                let unit = viewSize.height / 100

                // Sparks rising off the summoning pool.
                let pool = screenPoint(CGPoint(x: 0.44, y: 0.50), paintingFrame: paintingFrame, viewSize: viewSize)
                let sparks = SCNNode()
                sparks.position = SCNVector3(Float(pool.x), Float(pool.y), 4)
                sparks.addParticleSystem(sparkle(
                    tint: UIColor(hex: "#7FE0FF") ?? UIColor.cyan,
                    size: unit * 1.1, spread: paintingFrame.width * 0.055, rise: unit * 9, rate: 14
                ))
                weather.addChildNode(sparks)

                // The flame at the obelisk's tip.
                let tip = screenPoint(CGPoint(x: 0.888, y: 0.235), paintingFrame: paintingFrame, viewSize: viewSize)
                let flame = SCNNode()
                flame.position = SCNVector3(Float(tip.x), Float(tip.y), 4)
                flame.addParticleSystem(sparkle(
                    tint: UIColor(hex: "#FFD27A") ?? UIColor.orange,
                    size: unit * 1.6, spread: unit * 1.2, rise: unit * 6, rate: 22
                ))
                weather.addChildNode(flame)
            }
        }

        /// A painting point in the view's world, where a screen point is a
        /// world unit and the origin is the screen's centre.
        private func screenPoint(_ anchor: CGPoint, paintingFrame: CGRect, viewSize: CGSize) -> CGPoint {
            CGPoint(
                x: paintingFrame.minX + anchor.x * paintingFrame.width - viewSize.width / 2,
                y: viewSize.height / 2 - (paintingFrame.minY + anchor.y * paintingFrame.height)
            )
        }

        /// A soft dark pill under the feet, so the figure sits on the sand
        /// instead of floating over it.
        private func shadow(at point: CGPoint, width: CGFloat) -> SCNNode {
            let plane = SCNPlane(width: width, height: width * 0.3)
            plane.cornerRadius = width * 0.15
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0, alpha: 0.32)
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(Float(point.x), Float(point.y) + Float(width * 0.03), -4)
            return node
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
    }
}
