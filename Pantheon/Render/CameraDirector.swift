import Foundation
import SceneKit

/// Moves the battle camera — which, by default, it does not.
///
/// The genre keeps one fixed three-quarter view for the whole fight: a basic
/// attack, a special, an enemy's turn, none of them touches the frame, and
/// the eye never has to find the field again. Summoners War moves its camera
/// only for a handful of ultimates and the odd cut-in, and shakes it on a
/// heavy hit. So: every shot is an offset from a fixed "home" framing that
/// shows both teams; with the camera **fixed** (the default) the only move
/// is a short push toward an ultimate's caster and back, and the hit shake;
/// with **cinematic** on (More → Sound & camera) the old cuts, leans and
/// orbits play. Shots always return home, a new shot cancels the previous
/// one and clears its look-at, so the camera can never end a turn somewhere
/// unexpected — the failure mode that makes cinematic cameras in turn-based
/// games feel broken, and the one the phone photographed.
final class CameraDirector {

    /// The player's choice, read at shot time. Off is the genre's fixed view.
    static let cinematicKey = "cinematicCamera"
    static var isCinematic: Bool { UserDefaults.standard.bool(forKey: cinematicKey) }

    private let cameraNode: SCNNode
    private let homePosition: SCNVector3
    private let homeEuler: SCNVector3
    private var isBusy = false

    /// Field of view at rest, read off the camera it was handed so the home
    /// framing and the scene's solve cannot disagree. Shots narrow it to
    /// compress the frame.
    private let homeFOV: CGFloat

    init(cameraNode: SCNNode) {
        self.cameraNode = cameraNode
        self.homePosition = cameraNode.position
        self.homeEuler = cameraNode.eulerAngles
        self.homeFOV = cameraNode.camera?.fieldOfView ?? 35
    }

    /// Frames the whole battlefield. The default state between actions.
    func returnHome(duration: TimeInterval = 0.5) {
        cameraNode.removeAllActions()
        // Cancelling a shot's action skips its completion, which is what
        // cleared the look-at constraint: left in place, it turned the
        // home framing into a stare at the last victim's chest from five
        // metres up, which is the "camera in a weird spot" of the playtest.
        cameraNode.constraints = []
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
        // The fixed camera: nothing moves for a basic, a special or an
        // enemy's turn; an ultimate earns the one push.
        guard Self.isCinematic else {
            if shot == .cinematicOrbit {
                push(toward: caster, completion: completion)
            } else {
                completion?()
            }
            return
        }

        cameraNode.removeAllActions()
        cameraNode.constraints = []
        isBusy = true

        let casterPosition = caster.chestWorldPosition
        let duration = shot.duration

        switch shot {
        case .standard:
            // Not a cut, but not dead either: a lean of a tenth of the way
            // toward the action and a touch of zoom, held through the hits and
            // released when the queue drains. A camera that never moves is
            // most of what makes a turn-based fight look like a diorama.
            let focus = target.map { lerp(casterPosition, $0.chestWorldPosition, 0.5) } ?? casterPosition
            let toward = lerp(homePosition, focus, 0.10)
            let move = SCNAction.move(to: toward, duration: 0.35)
            move.timingMode = .easeOut
            cameraNode.runAction(move)
            animateFOV(to: homeFOV * 0.94, duration: 0.35)
            completion?()

        case .pushIn:
            // A quarter of the way, not a third: the stylised models are
            // chunkier than the first ones and a third cut the caster's crest
            // off at the top of the frame in the arena tour.
            let toward = lerp(homePosition, casterPosition, 0.25)
            let move = SCNAction.move(to: SCNVector3(toward.x, toward.y + 0.5, toward.z), duration: duration * 0.4)
            move.timingMode = .easeOut
            run(.sequence([move, .wait(duration: duration * 0.3)]), lookAt: caster, fov: 36, completion: completion)

        case .impactClose:
            let focus = target ?? caster
            let position = focus.chestWorldPosition
            // Over the shoulder, a stride further back than before, so a
            // two-metre figure keeps its head and feet in a landscape frame.
            let offset = SCNVector3(position.x + 2.0, position.y + 0.9, position.z + 2.4)
            let move = SCNAction.move(to: offset, duration: duration * 0.35)
            move.timingMode = .easeOut
            run(.sequence([move, .wait(duration: duration * 0.4)]), lookAt: focus, fov: 34, completion: completion)

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
            // The camera looks along its own -Z, so `look(at:)` is the
            // orientation; the hand-rolled yaw this replaced was a half turn
            // off and showed the empty side of the stage for the whole shot.
            let orbit = SCNAction.customAction(duration: duration * 0.8) { node, elapsed in
                let t = Float(elapsed / (duration * 0.8))
                let angle = Float.pi * 0.55 * t - Float.pi * 0.25
                node.position = SCNVector3(
                    casterPosition.x + sin(angle) * radius,
                    casterPosition.y + 1.6 - t * 0.5,
                    casterPosition.z + cos(angle) * radius
                )
                node.look(at: casterPosition)
            }
            run(.sequence([orbit, .wait(duration: duration * 0.2)]), lookAt: nil, fov: 42, completion: completion)
        }
    }

    /// The fixed camera's one move: a dolly a fifth of the way toward an
    /// ultimate's caster with a touch of zoom, a hold while the clip lands,
    /// and back. No cut, no orbit, the same orientation throughout, so the
    /// field never leaves the frame.
    private func push(toward caster: UnitNode, completion: (() -> Void)?) {
        cameraNode.removeAllActions()
        cameraNode.constraints = []
        isBusy = true
        let toward = lerp(homePosition, caster.chestWorldPosition, 0.18)
        let move = SCNAction.move(to: toward, duration: 0.45)
        move.timingMode = .easeOut
        let back = SCNAction.move(to: homePosition, duration: 0.5)
        back.timingMode = .easeInEaseOut
        animateFOV(to: homeFOV * 0.86, duration: 0.45)
        cameraNode.runAction(.sequence([move, .wait(duration: 0.9), back])) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.animateFOV(to: self.homeFOV, duration: 0.4)
                self.isBusy = false
                completion?()
            }
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
