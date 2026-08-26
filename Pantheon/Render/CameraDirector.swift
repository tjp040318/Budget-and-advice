import Foundation
import SceneKit

/// Moves the battle camera.
///
/// Every shot is an offset from a fixed "home" framing that shows both teams.
/// Shots always return home, and a new shot cancels the previous one, so the
/// camera can never end a turn somewhere unexpected — which is the failure mode
/// that makes cinematic cameras in turn-based games feel broken.
final class CameraDirector {

    private let cameraNode: SCNNode
    private let homePosition: SCNVector3
    private let homeEuler: SCNVector3
    private var isBusy = false

    /// Field of view at rest. Shots narrow it to compress the frame.
    private let homeFOV: CGFloat = 45

    init(cameraNode: SCNNode) {
        self.cameraNode = cameraNode
        self.homePosition = cameraNode.position
        self.homeEuler = cameraNode.eulerAngles
    }

    /// Frames the whole battlefield. The default state between actions.
    func returnHome(duration: TimeInterval = 0.5) {
        cameraNode.removeAllActions()
        let move = SCNAction.move(to: homePosition, duration: duration)
        move.timingMode = .easeInEaseOut
        let rotate = SCNAction.rotateTo(
            x: CGFloat(homeEuler.x), y: CGFloat(homeEuler.y), z: CGFloat(homeEuler.z),
            duration: duration
        )
        rotate.timingMode = .easeInEaseOut
        cameraNode.runAction(.group([move, rotate]))
        animateFOV(to: homeFOV, duration: duration)
        isBusy = false
    }

    /// Plays a shot on a caster, optionally aimed at a victim.
    func perform(
        _ shot: CameraShot,
        on caster: UnitNode,
        target: UnitNode?,
        completion: (() -> Void)? = nil
    ) {
        guard shot != .standard else {
            completion?()
            return
        }
        cameraNode.removeAllActions()
        isBusy = true

        let casterPosition = caster.chestWorldPosition
        let duration = shot.duration

        switch shot {
        case .standard:
            completion?()

        case .pushIn:
            let toward = lerp(homePosition, casterPosition, 0.32)
            let move = SCNAction.move(to: SCNVector3(toward.x, toward.y + 0.4, toward.z), duration: duration * 0.4)
            move.timingMode = .easeOut
            run(.sequence([move, .wait(duration: duration * 0.3)]), lookAt: caster, fov: 36, completion: completion)

        case .impactClose:
            let focus = target ?? caster
            let position = focus.chestWorldPosition
            let offset = SCNVector3(position.x + 1.4, position.y + 0.6, position.z + 1.6)
            let move = SCNAction.move(to: offset, duration: duration * 0.35)
            move.timingMode = .easeOut
            run(.sequence([move, .wait(duration: duration * 0.4)]), lookAt: focus, fov: 32, completion: completion)

        case .heroLowAngle:
            let offset = SCNVector3(casterPosition.x + 1.2, 0.7, casterPosition.z + 2.6)
            let move = SCNAction.move(to: offset, duration: duration * 0.35)
            move.timingMode = .easeInEaseOut
            run(.sequence([move, .wait(duration: duration * 0.5)]), lookAt: caster, fov: 40, completion: completion)

        case .cinematicOrbit:
            // Start wide and behind, sweep around the caster, land facing them.
            let radius: Float = 4.2
            let start = SCNVector3(casterPosition.x - radius, casterPosition.y + 1.6, casterPosition.z + radius)
            cameraNode.position = start
            let orbit = SCNAction.customAction(duration: duration * 0.8) { [weak self] node, elapsed in
                guard let self else { return }
                let t = Float(elapsed / (duration * 0.8))
                let angle = Float.pi * 0.55 * t - Float.pi * 0.25
                node.position = SCNVector3(
                    casterPosition.x + sin(angle) * radius,
                    casterPosition.y + 1.6 - t * 0.5,
                    casterPosition.z + cos(angle) * radius
                )
                self.look(at: casterPosition, from: node)
            }
            run(.sequence([orbit, .wait(duration: duration * 0.2)]), lookAt: nil, fov: 42, completion: completion)
        }
    }

    /// A short shake, used on critical hits and on the ultimate's landing frame.
    func shake(intensity: Float = 0.12, duration: TimeInterval = 0.3) {
        let origin = cameraNode.position
        let shake = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = Float(elapsed / duration)
            let decay = (1 - t)
            // Deterministic wobble rather than random, so it reads as impact
            // rather than as noise.
            let phase = Float(elapsed) * 60
            node.position = SCNVector3(
                origin.x + sin(phase) * intensity * decay,
                origin.y + cos(phase * 1.4) * intensity * decay * 0.6,
                origin.z
            )
        }
        cameraNode.runAction(.sequence([shake, .move(to: origin, duration: 0.06)]), forKey: "shake")
    }

    // MARK: - Helpers

    private func run(
        _ action: SCNAction,
        lookAt node: UnitNode?,
        fov: CGFloat,
        completion: (() -> Void)?
    ) {
        if let node {
            let constraint = SCNLookAtConstraint(target: node)
            constraint.isGimbalLockEnabled = true
            constraint.influenceFactor = 0.25
            cameraNode.constraints = [constraint]
        }
        animateFOV(to: fov, duration: 0.25)
        cameraNode.runAction(action) { [weak self] in
            DispatchQueue.main.async {
                self?.cameraNode.constraints = []
                completion?()
            }
        }
    }

    private func look(at point: SCNVector3, from node: SCNNode) {
        let direction = SCNVector3(point.x - node.position.x, point.y - node.position.y, point.z - node.position.z)
        let horizontal = sqrt(direction.x * direction.x + direction.z * direction.z)
        node.eulerAngles = SCNVector3(
            atan2(direction.y, horizontal),
            atan2(direction.x, direction.z),
            0
        )
    }

    private func animateFOV(to value: CGFloat, duration: TimeInterval) {
        guard let camera = cameraNode.camera else { return }
        let start = camera.fieldOfView
        let action = SCNAction.customAction(duration: duration) { _, elapsed in
            let t = CGFloat(elapsed) / CGFloat(duration)
            camera.fieldOfView = start + (value - start) * min(1, t)
        }
        cameraNode.runAction(action, forKey: "fov")
    }

    private func lerp(_ a: SCNVector3, _ b: SCNVector3, _ t: Float) -> SCNVector3 {
        SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }
}
