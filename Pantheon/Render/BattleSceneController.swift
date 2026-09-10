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
    ///
    /// It used to divide the event queue's holds and nothing else: every
    /// skeletal clip still played at its authored speed, so at the x2 the
    /// auto-repeat actually runs at, each attack was about half finished when
    /// the next event replaced it and the figures twitched between fragments
    /// of swings. SceneKit has no per-node speed multiplier to lean on (that
    /// is SpriteKit), so the units are told and scale their own clips and
    /// actions by hand.
    var speedMultiplier: Double = 1.0 {
        didSet {
            for node in unitNodes.values { node.playbackSpeed = speedMultiplier }
        }
    }

    /// Authored seconds at the current playback speed. Every duration in this
    /// file is written for x1 and passes through here on its way to a timer,
    /// so fast-forward shortens the whole fight by one factor rather than by
    /// several that drift apart.
    private func beat(_ seconds: TimeInterval) -> TimeInterval {
        seconds / max(0.25, speedMultiplier)
    }

    /// How long a melee unit takes to close on its victim.
    private static let dashDuration: TimeInterval = 0.30

    /// Where in a clip the blow actually lands, as a fraction of the clip's
    /// contract duration.
    ///
    /// Nothing in the pipeline has ever known this: `AnimationClip` carries a
    /// duration and no contact frame, so the impact was spawned on a detached
    /// timer at a flat 45% of the clip while the damage event — the flash, the
    /// number, the sound, the haptic and the freeze — waited for the WHOLE
    /// clip to finish. Every basic attack therefore played as a slash arc, six
    /// tenths of a second of nothing, and then a victim flinching at something
    /// that had already happened; on an ultimate the gap was over a second.
    /// Two half-hits are why the fight read as numbers changing rather than as
    /// something being struck. This table is the one place the moment of
    /// contact is written down, and `UnitNode.play` retimes every one-shot to
    /// its contract so the fraction means the same thing whatever length Meshy
    /// happened to author the clip at.
    private static func contactFraction(of clip: AnimationClip) -> Double {
        switch clip {
        case .attackBasic: return 0.42
        case .attackHeavy: return 0.55
        case .castRelease: return 0.60
        case .ultimate: return 0.62
        default: return 0.50
        }
    }

    /// How far a blow shoves its victim, by weight: a glance barely moves it,
    /// a killing blow throws it off its stance.
    private static func recoilStrength(for weight: HitWeight) -> Float {
        switch weight {
        case .light: return 0.45
        case .normal: return 1.00
        case .heavy: return 1.60
        case .critical: return 1.90
        case .lethal: return 2.40
        }
    }

    private(set) var unitNodes: [UUID: UnitNode] = [:]
    private var cameraNode = SCNNode()
    private var director: CameraDirector?
    private var queue: [BattleEvent] = []
    private var isPlaying = false
    /// Bumped by flush(). A playNext continuation scheduled before the flush
    /// compares its captured value and steps aside, instead of draining an
    /// empty queue and reporting "finished" a second time — which in auto-battle
    /// would take a second turn.
    private var playbackGeneration = 0
    private(set) var environment: BattleEnvironment = .duatGate
    /// The clip of the most recent cast, so its hits know how hard to land.
    private var lastCastClip: AnimationClip = .attackBasic
    /// What the last caster was, so a hit can sound like what struck it: a
    /// blade for a melee cut, a heavier body for a two-handed blow, and the
    /// caster's element for anything cast from a distance.
    private var lastCastColour: Juice.HitColour = .blade
    /// How long the event being presented should hold, in authored seconds,
    /// when the event's own declared duration is not what the picture needs:
    /// a cast holds only as far as the contact frame, and a heavy hit dwells
    /// on it. Set inside `present`, consumed by `playNext`, cleared before
    /// every event — only the arm that presents one knows, for instance,
    /// whether the caster had to close the distance first.
    private var holdOverride: TimeInterval?
    /// The rest of that clip — the follow-through after contact — repaid at
    /// the next turn boundary. The cast no longer waits for it (the damage
    /// lands on the contact frame and the swing finishes underneath), but the
    /// NEXT unit must, or it begins its turn over the top of the last one's
    /// swing and its walk back to its mark.
    private var castRecovery: TimeInterval = 0

    // MARK: - Setup

    func build(combatants: [Combatant], environment: BattleEnvironment) {
        self.environment = environment
        scene.rootNode.removeAction(forKey: "cast_impact")
        scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        unitNodes.removeAll()
        holdOverride = nil
        castRecovery = 0

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
            // The 3D set: a floating platform, ruins and statues, braziers,
            // mist and dust, with the environment's painting far behind it
            // for parallax. `StageBuilder` also sets the fog and the sky.
            StageBuilder.buildBattleStage(environment, into: scene)
        }

        // Image-based lighting if the HDR shipped; a coloured ambient if not.
        if let iblURL = Bundle.main.url(forResource: environment.environmentMap, withExtension: "hdr")
            ?? Bundle.main.url(forResource: environment.environmentMap, withExtension: "exr") {
            scene.lightingEnvironment.contents = iblURL
            scene.lightingEnvironment.intensity = 1.6
        } else {
            // A flat colour as the lighting environment lights every surface
            // uniformly in that colour, which is what washed the whole stage
            // green. It is a stand-in until a real .hdr ships, so keep it weak
            // enough to be ambient fill and let the three real lights shape the
            // figure.
            scene.lightingEnvironment.contents = UIColor(hex: environment.keyLightHex)
            scene.lightingEnvironment.intensity = 0.35
        }

    }

    /// Opaque over the near three-quarters of the stage, fading to nothing at
    /// the far edge, so the platform dissolves into the backdrop instead of
    /// ending in a hard line. The image's top row maps to the plane's far edge.
    private static let floorFade: UIImage = {
        let size = CGSize(width: 4, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            for row in 0..<Int(size.height) {
                let fromTop = CGFloat(row) / size.height
                let alpha = min(1, max(0, (fromTop - 0.04) / 0.30))
                context.cgContext.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                context.cgContext.fill(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 1))
            }
        }
    }()

    /// The centre of `image` at the aspect ratio of `size`.
    static func cropped(_ image: UIImage, toAspectOf size: CGSize) -> UIImage {
        guard size.width > 0, size.height > 0, let cg = image.cgImage else { return image }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let target = size.width / size.height
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > target {
            rect.size.width = height * target
            rect.origin.x = (width - rect.size.width) / 2
        } else {
            rect.size.height = width / target
            rect.origin.y = (height - rect.size.height) / 2
        }
        guard let piece = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: piece, scale: image.scale, orientation: image.imageOrientation)
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
        // Solved numerically for a landscape phone (852 × 393 points): the
        // genre's view is higher and further back than the first landscape
        // solve (35°, 5.5 m up, 24° down), which stood the player line a
        // third of the screen tall and hid the far edge of the platform. From
        // 7.2 m up, 11 m back and 30° down at 34°, the near player rank's
        // feet land at 77% of the screen height and its heads at 53% (a
        // figure a quarter of the screen tall), the near enemy rank's feet at
        // 46% and heads at 27%, the far rank's heads at 20%, the platform's
        // far edge at 22% with the painting above it — both lines in one
        // frame with room round them, and a boss seen whole.
        camera.fieldOfView = 34
        camera.zNear = 0.1
        camera.zFar = 120
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        // Bloom only on real highlights: at 0.55 over 0.85 a sunlit sandstone
        // floor became a sheet of light and a boss's glow a wall of yellow.
        camera.bloomIntensity = 0.3
        camera.bloomThreshold = 0.94
        camera.bloomBlurRadius = 10
        camera.colorFringeStrength = 0.35
        camera.vignettingIntensity = 0.3
        camera.vignettingPower = 1.2
        camera.screenSpaceAmbientOcclusionIntensity = 0.6
        camera.screenSpaceAmbientOcclusionRadius = 0.6
        camera.motionBlurIntensity = 0.25

        cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 7.2, 11.0)
        cameraNode.eulerAngles = SCNVector3(-0.524, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        director = CameraDirector(cameraNode: cameraNode)
    }

    /// Positions both teams. The camera sits on the +Z side, so the player's
    /// line stands nearest it at +Z and faces away, toward the enemies at -Z,
    /// who face +Z — toward the player and the camera. A model's authored
    /// facing is +Z (Docs/ART_PIPELINE.md), hence the half-turn on the near
    /// side. Ranks are staggered so nobody is hidden behind anybody.
    private func place(combatants: [Combatant], entering: Bool = false) {
        // A 5v5 is ten characters plus a full post stack; a 1v1 can afford the
        // detailed mesh. The loader falls back to the full model when no reduced
        // export has been shipped.
        let detail = ModelLibrary.detail(forCombatantCount: combatants.count + (entering ? unitNodes.count : 0))
        for combatant in combatants {
            let node = UnitNode(combatant: combatant, detail: detail)
            node.playbackSpeed = speedMultiplier
            let home = position(for: combatant, teamSize: sideCount(combatant.side, in: combatants))
            node.eulerAngles.y = combatant.side == .player ? .pi : 0
            if entering {
                // A later wave walks on from the far side of the field.
                node.position = SCNVector3(home.x, home.y, home.z - 3.0)
                node.opacity = 0
                let walk = SCNAction.move(to: home, duration: beat(0.7))
                walk.timingMode = .easeOut
                node.runAction(.group([walk, .fadeIn(duration: beat(0.45))]))
            } else {
                node.position = home
            }
            scene.rootNode.addChildNode(node)
            unitNodes[combatant.id] = node
        }
    }

    /// How many combatants a side is fielding, so the line can be centred on
    /// the count rather than on a fixed number of columns.
    private func sideCount(_ side: BattleSide, in combatants: [Combatant]) -> Int {
        let placed = unitNodes.values.filter { $0.combatant.side == side }.count
        return max(1, combatants.filter { $0.side == side }.count + placed)
    }

    /// ONE RANK ABREAST, centred, both sides.
    ///
    /// It used to be two columns 2.6 m apart in ranks 1.6 m deep, which is a
    /// PORTRAIT formation in a LANDSCAPE frame. Measured off the photographed
    /// frames: a four-unit team spanned 3.9 m of a 14.9 m-wide view, so the
    /// whole cast was a clump filling under a quarter of the width and the
    /// other three quarters was bare floor. Worse, both sides used the same x
    /// formula, so the enemy line was a shrunk copy of the player line centred
    /// on the same point and every player unit sat within thirty pixels of an
    /// enemy's column — in the dungeon frames an enemy is seventy per cent
    /// hidden behind Zeus, which is arithmetic rather than bad luck.
    ///
    /// A line abreast spends the team's extent on WIDTH, which a landscape
    /// frame has in surplus, instead of on DEPTH, which it is short of. It is
    /// also what the genre does: Summoners War stands its five in a row.
    ///
    /// The enemy line is pushed half a step sideways so no enemy ever stands
    /// directly behind a player whatever the camera's yaw, and a side of more
    /// than five falls back to a second rank behind the first rather than
    /// spreading wider than the camera will frame.
    private func position(for combatant: Combatant, teamSize: Int) -> SCNVector3 {
        let sideSign: Float = combatant.side == .player ? 1 : -1
        let perRank = 5
        let rank = Float(combatant.slot / perRank)
        let indexInRank = combatant.slot % perRank
        let inThisRank = max(1, min(perRank, teamSize - Int(rank) * perRank))

        // 2.0 m of shoulder room puts a five-wide line at a 4.0 m half-width,
        // which is what `CameraDirector.minHalfWidth` is solved for: the camera
        // will not zoom in past five metres, so a narrower line simply sits
        // small in the middle of the frame however tight the framing gets.
        let spacing: Float = 2.0
        let centred = Float(indexInRank) - Float(inThisRank - 1) / 2
        let stagger: Float = combatant.side == .player ? 0 : spacing / 2
        let x = centred * spacing + stagger

        // Both sides' second ranks stand FURTHER from the camera than their
        // first — smaller and higher in the frame — and are offset by half a
        // step so nobody hides behind the unit in front.
        let halfStep: Float = rank.truncatingRemainder(dividingBy: 2) == 0 ? 0 : spacing / 2
        let depth = 2.6 + rank * 1.7
        return SCNVector3(x + halfStep, 0, sideSign * depth)
    }

    // MARK: - Playback

    func enqueue(_ events: [BattleEvent]) {
        queue.append(contentsOf: events)
        if !isPlaying { playNext() }
    }

    /// Drops queued animation and snaps to the end state. Used by the skip button.
    func flush(combatants: [Combatant]) {
        playbackGeneration += 1
        queue.removeAll()
        isPlaying = false
        holdOverride = nil
        castRecovery = 0
        // A cast's impact is a scene action waiting for its contact frame; a
        // skip must take it with the rest of the queue rather than let it
        // burst over a field that has already jumped to the end state.
        scene.rootNode.removeAction(forKey: "cast_impact")
        // And the same for a swing still waiting out its dash: the queue it
        // belonged to is gone, so it would otherwise land a lone attack over
        // a battle that has already been resolved.
        for node in unitNodes.values { node.cancelPendingClip() }
        Juice.release(scene)
        sync(combatants: combatants)
        delegate?.battleSceneDidFinishPlayback(self)
    }

    /// Forces every node to match engine truth. Called after a skip and at the
    /// end of each turn, so a dropped animation can never desync the display.
    func sync(combatants: [Combatant]) {
        for combatant in combatants {
            guard let node = unitNodes[combatant.id] else { continue }
            node.setHealth(fraction: combatant.healthFraction, animated: false)
            node.setStatuses(combatant.statuses)
            if !combatant.isAlive { node.markDefeated() }
        }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            director?.returnHome()
            returnEveryoneHome()
            delegate?.battleSceneDidFinishPlayback(self)
            return
        }

        isPlaying = true
        let event = queue.removeFirst()
        delegate?.battleScene(self, willPresent: event)
        holdOverride = nil
        let frozen = present(event)

        // A cast holds only until the blade lands — `holdOverride` — so the damage
        // event that carries the flash, the flinch, the shove, the number and
        // the freeze is presented ON the contact frame with the rest of the
        // swing still playing underneath it. Everything else keeps the
        // duration the event itself declares.
        var span = holdOverride ?? event.presentationDuration
        switch event {
        case .turnBegan, .waveStarted, .battleEnded:
            // Repay whatever is left of the follow-through the cast did not
            // wait for, so the last attacker finishes its swing and walks back
            // to its mark before the next one moves. Two units moving at once
            // for no reason on screen is most of what made the fight hard to
            // read.
            span += castRecovery
            castRecovery = 0
        case .skillCast:
            // The cast's own hold IS the run-up to contact; its follow-through
            // starts where that ends.
            break
        default:
            // Everything that plays after the contact frame — the numbers, the
            // statuses, the later hits of a multi-hit skill — is time the
            // swing is finishing in, so it comes off what is still owed.
            // Without this a five-hit skill would add three quarters of a
            // second of nothing to the front of the next turn.
            castRecovery = max(0, castRecovery - span)
        }

        // A freeze-frame steals time from the event's hold; give it back so the
        // cadence between hits stays what the event durations say it is.
        let hold = max(0.02, beat(span)) + frozen
        let generation = playbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.playNext()
        }
    }

    // MARK: - Presenting one event

    /// Returns how long the world froze for this event, if it did.
    @discardableResult
    private func present(_ event: BattleEvent) -> TimeInterval {
        switch event {
        case .battleStart:
            for node in unitNodes.values { node.play(.idleCombat) }

        case .turnBegan(let actor, _):
            returnEveryoneHome()
            highlight(actor)

        case .turnSkipped(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("SKIPPED", at: node.headWorldPosition, color: UIColor(hex: "#C8C8C8")!)

        case .skillCast(let actor, _, let name, let targets, let shot, let animation, let vfx):
            guard let casterNode = unitNodes[actor] else { return 0 }
            let targetNode = targets.first.flatMap { unitNodes[$0] }
            lastCastClip = animation
            // A melee unit swinging is steel or stone; anything else is its
            // element. `castRelease` and the ultimate are always the element,
            // because that is what the effect on screen already shows.
            if animation == .castRelease || animation == .ultimate || !casterNode.spec.melee {
                lastCastColour = .element(casterNode.element)
            } else {
                lastCastColour = animation == .attackHeavy ? .blunt : .blade
            }
            Juice.prepareHaptics()
            AudioLibrary.shared.play(.whoosh, volume: animation == .ultimate ? 1.0 : 0.6)
            director?.perform(shot, on: casterNode, target: targetNode)
            // A melee unit closes on its one victim before the swing and stays
            // there through the hits; casters, archers and line-wide skills
            // strike from where they stand.
            var walkUp: TimeInterval = 0
            if let targetNode, casterNode.spec.melee, targets.count == 1,
               targetNode.side != casterNode.side,
               animation == .attackBasic || animation == .attackHeavy {
                casterNode.dash(toward: targetNode, duration: beat(Self.dashDuration))
                // The swing waits for the feet. These two lines used to be
                // consecutive statements, so the clip and the leap started on
                // the same frame and the wind-up — the only part of an attack
                // that carries anticipation — played four metres away in
                // mid-air; the figure arrived a quarter of the way through its
                // own cut. The 80 ms overlap is deliberate: the wind-up begins
                // as the weight comes down, which is what ties a leap and a
                // swing into one motion.
                walkUp = max(0, Self.dashDuration
                    * (UnitNode.dashGather + UnitNode.dashFlight) - 0.08)
            }
            casterNode.play(animation, after: beat(walkUp))
            floatText(name, at: casterNode.headWorldPosition, color: .white, scale: 0.7)

            // The frame the blade lands, measured from the start of the CLIP
            // rather than of the turn, and held by the queue so the damage
            // event arrives on it. What is left of the clip is repaid to the
            // next turn as recovery.
            let contact = walkUp + animation.fallbackDuration * Self.contactFraction(of: animation)
            holdOverride = contact
            castRecovery = animation.fallbackDuration * (1 - Self.contactFraction(of: animation))

            // A skill with no effect of its own lands in its caster's element,
            // and a closing strike draws its slash across the victim.
            let tint = UIColor(hex: casterNode.spec.auraHex) ?? .white
            let effect = vfx == "impact_generic" ? "impact_\(casterNode.element.rawValue)" : vfx
            let slashes = casterNode.spec.melee && targets.count == 1
                && (animation == .attackBasic || animation == .attackHeavy)
            // The burst is a SCENE action, not a `DispatchQueue.asyncAfter`: a
            // hit freezes the scene for up to 150 ms and a wall-clock timer
            // keeps counting through a freeze that the animation it is timed
            // against does not. The key means a second cast cancels the first
            // one's pending burst instead of letting it fire into a field that
            // has moved on, and the position is read when it fires, so an
            // effect can no longer bloom where a victim used to stand.
            scene.rootNode.removeAction(forKey: "cast_impact")
            scene.rootNode.runAction(.sequence([
                .wait(duration: beat(contact)),
                SCNAction.run { [weak self] _ in
                    // SceneKit runs this on its rendering thread; everything
                    // below touches the scene graph, so it hops to main first.
                    DispatchQueue.main.async {
                        guard let self else { return }
                        // Lightning has its own sound; everything else lands on
                        // the hit sound `Juice` picks from the damage that
                        // arrives on this same frame.
                        if vfx == "thunderbolt" || vfx == "thunderclap" || vfx == "keraunos" {
                            AudioLibrary.shared.play(.thunder, volume: vfx == "keraunos" ? 1.0 : 0.7)
                        }
                        for targetID in targets {
                            guard let node = self.unitNodes[targetID] else { continue }
                            VFXLibrary.spawn(
                                effect, at: node.chestWorldPosition, in: self.scene,
                                tint: tint, scale: node.spec.height / 1.9
                            )
                            if slashes {
                                VFXLibrary.spawn(
                                    "slash", at: node.chestWorldPosition, in: self.scene,
                                    tint: tint, scale: node.spec.height / 1.9 * (animation == .attackHeavy ? 1.3 : 1.0)
                                )
                            }
                        }
                    }
                }
            ]), forKey: "cast_impact")

        case .damage(_, let target, let amount, let isCritical, let isGlancing, let matchup, let remaining, _, _):
            guard let node = unitNodes[target] else { return 0 }

            // How hard did that land? Lethal beats critical beats the clip.
            let weight: HitWeight
            if remaining <= 0 {
                weight = .lethal
            } else if isCritical {
                weight = .critical
            } else if lastCastClip == .ultimate || lastCastClip == .attackHeavy || lastCastClip == .castRelease {
                weight = .heavy
            } else if isGlancing {
                weight = .light
            } else {
                weight = .normal
            }
            let profile = Juice.profile(for: weight)

            // Everything a blow does now happens on ONE frame: the burst and
            // the slash arc (spawned by the cast, timed to this instant), the
            // white flash, the flinch, the shove, the number, the sound, the
            // haptic and the freeze. They used to be spread over more than a
            // second, which is why a hit read as a light show followed by a
            // bookkeeping update. The shove is the part that was missing
            // altogether: a body that never moves is not being hit.
            node.play(.hitReact)
            node.flashHit()
            node.recoil(strength: Self.recoilStrength(for: weight))
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))

            let color: UIColor
            var label = "\(Int(amount.rounded()))"
            if isCritical {
                color = UIColor(hex: "#FFD24F")!
                label = "\(label)!"
                VFXLibrary.spawn("crit", at: node.chestWorldPosition, in: scene, tint: color)
            } else if isGlancing {
                color = UIColor(hex: "#9AA3B0")!
                label = "\(label) glance"
            } else if matchup == .advantage {
                color = UIColor(hex: "#7FE8A0")!
            } else {
                color = .white
            }
            floatText(label, at: node.headWorldPosition, color: color, scale: profile.numberScale, pop: true)

            // A heavy blow is worth dwelling on. The freeze punctuates the
            // frame of contact itself; this holds the frame just after it, so
            // the shove and the shake are seen finishing before the next
            // number starts. An ordinary hit keeps the fast cadence a
            // multi-hit skill needs, and a glance is not worth a beat at all.
            switch weight {
            case .lethal: holdOverride = 0.55
            case .critical: holdOverride = 0.48
            case .heavy: holdOverride = 0.42
            case .normal, .light: break
            }

            return Juice.impact(weight, colour: lastCastColour, scene: scene, director: director, speed: speedMultiplier)

        case .healed(_, let target, let amount, let remaining):
            guard let node = unitNodes[target] else { return 0 }
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))
            floatText("+\(Int(amount.rounded()))", at: node.headWorldPosition, color: UIColor(hex: "#7FE8A0")!)
            VFXLibrary.spawn("heal", at: node.position, in: scene, tint: UIColor(hex: "#7FE8A0")!)

        case .shieldAbsorbed(let target, let amount, _):
            guard let node = unitNodes[target] else { return 0 }
            floatText("\(Int(amount.rounded())) blocked", at: node.headWorldPosition, color: UIColor(hex: "#6BD8F2")!, scale: 0.8)

        case .statusApplied(_, let target, let kind, let turns):
            guard let node = unitNodes[target] else { return 0 }
            node.applyStatus(kind, turns: turns)
            VFXLibrary.spawn(kind.isBuff ? "buff" : "debuff", at: node.position, in: scene, tint: .white)
            floatText(kind.displayName, at: node.headWorldPosition,
                      color: kind.isBuff ? UIColor(hex: "#6BD8F2")! : UIColor(hex: "#F2726B")!, scale: 0.7)

        case .statusResisted(_, let target, _):
            guard let node = unitNodes[target] else { return 0 }
            floatText("RESIST", at: node.headWorldPosition, color: UIColor(hex: "#C8C8C8")!, scale: 0.8)

        case .statusExpired(let target, let kind), .statusRemoved(let target, let kind, _):
            unitNodes[target]?.removeStatus(kind)

        case .cooldownStarted, .attackBarChanged:
            break

        case .counterattack(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("COUNTER", at: node.headWorldPosition, color: UIColor(hex: "#FFD24F")!, scale: 0.9)
            node.play(.attackBasic)
            // A counter interrupts whatever the caster was in the middle of,
            // so the follow-through owed by that cast is void; leaving it
            // would add a second of nothing to the next turn.
            castRecovery = 0

        case .extraTurnGranted(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("EXTRA TURN", at: node.headWorldPosition, color: UIColor(hex: "#FFD24F")!, scale: 0.9)

        case .passiveTriggered(let actor, let name):
            guard let node = unitNodes[actor] else { return 0 }
            floatText(name, at: node.headWorldPosition, color: UIColor(hex: "#E8C86A")!, scale: 0.9)
            VFXLibrary.spawn("stormlord_surge", at: node.position, in: scene, tint: UIColor(hex: "#E8C86A")!)

        case .revived(let target, _):
            unitNodes[target]?.revive(healthFraction: 0.3)

        case .defeated(let target):
            unitNodes[target]?.markDefeated()

        case .waveStarted(_, _, let opponents):
            // The fallen wave leaves the field so the marks are free, and
            // the next one comes on from the back.
            for (id, node) in unitNodes where node.side == .opponent && node.isDefeated {
                node.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
                unitNodes[id] = nil
            }
            registerMaxHealth(opponents)
            place(combatants: opponents, entering: true)
            Juice.haptic(.light)

        case .battleEnded(let result):
            director?.returnHome()
            Juice.notify(result.outcome == .victory ? .success : .error)
            AudioLibrary.shared.play(result.outcome == .victory ? .victory : .defeat)
            for (_, node) in unitNodes where !node.isDefeated {
                if (result.outcome == .victory && node.side == .player)
                    || (result.outcome == .defeat && node.side == .opponent) {
                    node.play(.victory)
                }
            }
        }
        return 0
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

    /// Every unit that dashed walks back to its mark. Called as a turn begins
    /// and when the queue drains, so nobody is left standing in the enemy line.
    private func returnEveryoneHome() {
        for node in unitNodes.values { node.returnHome(duration: beat(0.30)) }
    }

    // MARK: - Floating text

    private func floatText(_ text: String, at position: SCNVector3, color: UIColor, scale: CGFloat = 1.0, pop: Bool = false) {
        guard let image = FloatingTextRenderer.image(text: text, color: color) else { return }

        let width = CGFloat(0.018) * image.size.width * scale
        let height = CGFloat(0.018) * image.size.height * scale
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
        // Damage numbers scatter a little sideways so a multi-hit reads as a
        // burst rather than a stack of identical labels.
        let scatter: Float = pop ? Float.random(in: -0.22...0.22) : 0
        node.position = SCNVector3(position.x + scatter, position.y + 0.25, position.z)
        node.renderingOrder = 1_000
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        node.constraints = [billboard]
        scene.rootNode.addChildNode(node)

        let rise = SCNAction.moveBy(x: 0, y: 1.1, z: 0, duration: 1.0)
        rise.timingMode = .easeOut
        let drift = SCNAction.sequence([
            .group([rise, .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.5)])]),
            .removeFromParentNode()
        ])
        if pop {
            // The plane is authored at final size; start small and let the pop
            // overshoot and settle before the drift takes over.
            node.scale = SCNVector3(0.35, 0.35, 0.35)
            node.runAction(.sequence([Juice.popAction(scale: 1.0), drift]))
        } else {
            node.runAction(drift)
        }
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

        // A rounded semibold with a thin edge and a soft shadow: the heavy
        // black-outlined figures of the first build were too big and too
        // thick to sit over a painted stage.
        let base = UIFont.systemFont(ofSize: 34, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 34) } ?? base
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = CGSize(width: 0, height: 1.5)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .strokeColor: UIColor.black.withAlphaComponent(0.9),
            .strokeWidth: -2.0,
            .shadow: shadow
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
