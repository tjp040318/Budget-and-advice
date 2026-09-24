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
    /// A boss stands sunk over the far rim with the HUD's wide bar for its
    /// health, so it wears no bar of its own and no ring at its feet (which
    /// would be a metre inside the rock).
    let isBoss: Bool
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
    /// The advantage arrow beside the 3D health bar. A boss never wears
    /// one (its matchup is the HUD's boss bar's), nor does a fallen unit.
    private let matchupBadge: SCNNode
    /// The screen-space plate that draws this unit's bars since 2026-09-11
    /// (`UnitPlateOverlay`, over the battle view). While one is attached the
    /// 3D bar above the head stays hidden; the island and the Hall of Ka,
    /// which have no overlay, keep it.
    weak var plate: UnitPlate? {
        didSet { if plate != nil { healthBarRoot.isHidden = true } }
    }
    /// The overlay the unit's head mark is drawn on (Docs/FEEL.md W2.22): a
    /// stunned, sleeping or frozen unit wears one — a boss too, which has no
    /// plate. Set by the battle; the island and the Hall of Ka have none.
    weak var markOverlay: UnitPlateOverlay?
    /// The head mark the unit wears now, so an unchanged one is not re-made.
    private var headMarkShown: HeadMarkKind?
    /// THE TURN CIRCLE (2026-09-24, Docs/FEEL.md W1.9): a flat rune disc
    /// under the acting unit, 0.95 of its width, in its element's colour,
    /// turning slowly over a soft pool of the same light, popped in as its
    /// turn begins (`setHighlighted`). It was a torus 2.8 cm thick that read
    /// as a thin purple ellipse (`6-battle-a`); the owner's Summoners War
    /// frames put a large glowing circle there.
    private let turnDisc: SCNNode
    /// Whether the turn disc is up (the acting unit's), so the others are
    /// not faded again on every turn.
    private var discLit = false
    /// How bright the turn disc stands at its peak: 0.9 on most sets and
    /// 60% of that on the pale marble ones (`StageBuilder.isPaleSet`), where
    /// an additive disc blew the floor. Set by the battle before the first
    /// turn.
    var turnDiscPeak: CGFloat = 0.9
    private let elementTint: UIColor
    /// A boss's paint, the mean of its diffuse texture in linear light
    /// (`UnitNode.measurePaint(of:key:)`); nil for everyone else, and for a
    /// boss whose paint is not a picture this can read.
    let paintAlbedo: Double?

    // MARK: Leaving the field (Docs/FEEL.md W2.8)

    /// Told once, on the main thread, when this unit's death has played
    /// out — its death clip ended AND it is marked defeated, in whichever
    /// order those came (the final blow starts the fall before the engine's
    /// `.defeated` is presented) — so the battle can take the body off the
    /// field. Nil on the island and the figure stages, where nobody falls;
    /// while it is nil a death ends as it always did, the body left at 0.6.
    var onFallen: ((UnitNode) -> Void)?
    /// The death clip has run its length.
    private var deathPlayedOut = false
    /// `onFallen` has been told for this death.
    private var fallReported = false
    /// Which life this is: a revive begins the next one, so the ending of a
    /// death clip still in flight from the last life (its clock had fired
    /// and its hop to the main thread was queued when a skip's `sync`
    /// revived the unit) cannot tell THIS life its death has played out,
    /// which would dissolve the body at the next death's first frame.
    private var lifeSerial = 0
    /// The body has been dissolved or sunk, so a revive brings it back.
    private(set) var hasLeftTheField = false
    /// The glyph left on the mark (`leaveMark`), taken up by a revive.
    private var fallenMark: SCNNode?
    /// The looping systems quieted as the body went (the awakened aura),
    /// with the birth rate each had.
    private var quietedSystems: [(system: SCNParticleSystem, rate: CGFloat)] = []
    /// A sunk boss's place before it sank, and its lights' strengths.
    private var sunkFrom: SCNVector3?
    private var sunkLights: [(light: SCNLight, rest: CGFloat)] = []

    /// Nil until the first clip plays. It used to start as `.idleCombat`, so
    /// the `play(.idleCombat)` in `init` was refused as "already running" and
    /// every unit stood in its bind pose — the A-pose in the first battle
    /// screenshots — until its first attack.
    private var currentClip: AnimationClip?

    /// Where the model container rests, read before anything has had a chance
    /// to animate it. The dash writes the container's height every frame to
    /// arc the leap and a recoil writes its depth, so both need a rest value
    /// to come back to that no bob, no interrupted leap and no accumulated
    /// `moveBy` can have drifted.
    private let containerRest: SCNVector3

    /// Whether this unit has taken up its idle once already. The FIRST idle
    /// starts on a random beat, because every unit is built in the same frame
    /// from the same cached animation and a rank that rises and falls in
    /// perfect unison reads as a screensaver rather than as a squad. Every
    /// idle after an action starts at once: a pause after a swing reads as a
    /// dropped frame.
    private var hasIdled = false

    /// Whether the dash arc is the thing writing the model container's pitch
    /// at the moment.
    ///
    /// The arc drives that angle as an ABSOLUTE value every frame, and the
    /// procedural clips below rotate it RELATIVELY, so the two must never
    /// both hold it: the arc's last frame would become the rotation's zero
    /// and the figure would finish every swing leaning a few degrees further
    /// back than it began — once per attack, compounding, for the rest of the
    /// fight. Ownership passes to the clip in `playProcedural` and is only
    /// ever set and cleared on the main thread; the arc's own blocks, which
    /// run on the render thread, do nothing but read it. A rigged family is
    /// untouched by any of this: a real clip animates the skeleton INSIDE the
    /// container and never touches the container's own angles, so it keeps
    /// the lean through the whole landing.
    private var dashOwnsPitch = false

    /// 1.0 normally, 2.0 or 3.0 on the speed control (Docs/FEEL.md W1.1),
    /// and under 1 through the final blow's slow motion
    /// (`BattleSceneController`, W1.7).
    ///
    /// SceneKit has no per-node speed multiplier — that is SpriteKit's `speed`
    /// — so the scale is applied by hand: to the CAAnimations in `play` and to
    /// every action duration through `beat`. Until it was, the event queue ran
    /// at x2 over clips that still played at x1, so each swing was about half
    /// finished when the next event replaced it and the field twitched between
    /// fragments of motion. The mode the player spends most of his time in had
    /// the worst motion in the game.
    ///
    /// A clip ALREADY RUNNING follows the pace too (2026-09-24,
    /// `retimeRunningClip`): its animation player's speed is set to the new
    /// pace over the one it began at, and so is the clock that hands a
    /// one-shot back to the idle (`scheduleClipEnd`). This re-seated a
    /// running LOOP instead, which the slow motion — a new pace every frame
    /// for a second — would have turned into every figure's breath restarted
    /// at a random phase sixty times a second.
    var playbackSpeed: Double = 1.0 {
        didSet { retimeRunningClip(from: oldValue) }
    }

    /// The pace the clip in hand began at: what its animation's own speed
    /// was set for in `play`.
    private var clipBaseSpeed: Double = 1.0
    /// The share of that pace the clip runs at now, read on the render
    /// thread by the clock that ends a one-shot (`scheduleClipEnd`).
    private let clipPace = ClipPace()
    /// A change of pace this big or bigger — a step of the speed control —
    /// re-seats a PROCEDURAL loop, which has no animation player to re-time;
    /// the slow motion's small steps never do.
    private static let reseatStep: Double = 0.25
    /// The slowest pace the fight runs at: `beat`'s floor, under the slow
    /// motion's 0.3. A one-shot's clock is long enough for its clip at it.
    static let slowestPace: Double = 0.25

    /// Keeps the clip in hand to the pace: its player's speed, the clock of
    /// its ending, and — for a procedural clip — its action's speed, or a
    /// fresh start for a loop on a big step.
    private func retimeRunningClip(from oldSpeed: Double) {
        let change: Double = abs(playbackSpeed - oldSpeed)
        guard change > 0.0005, let clip = currentClip else { return }
        let ratio: Double = playbackSpeed / max(0.05, clipBaseSpeed)
        clipPace.set(ratio)
        if let player = modelContainer.animationPlayer(forKey: clip.rawValue) {
            player.speed = CGFloat(ratio)
        } else if clip.loops, change >= Self.reseatStep {
            // `play` refuses to restart a loop that is already running, so the
            // procedural idle is re-seated by hand to pick up the new pace.
            currentClip = nil
            play(clip)
        } else if let running = modelContainer.action(forKey: "clip") {
            running.speed = CGFloat(ratio)
        }
    }

    /// Authored seconds at the current playback speed. Every duration in this
    /// file is written for x1 and divided here, so fast-forward shortens the
    /// dash, the recoil and the procedural motion by exactly as much as it
    /// shortens the clips.
    private func beat(_ seconds: TimeInterval) -> TimeInterval {
        seconds / max(0.25, playbackSpeed)
    }

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
        // A CONSTANT world size, not a fraction of the model's height.
        //
        // Two things were wrong with scaling it. The readability study named
        // the first: a bar whose full length is the unit's height means a
        // 1.85 m unit at full health and a 2.20 m unit at 84% draw the same
        // bar, so health is not comparable between two units even when you can
        // see both. And the CI tour showed the second on 2026-09-10 — at
        // `height * 0.85` a bar is 1.7 m wide for an ordinary unit and 3.8 m
        // for the Colossus, and the line is 2.0 m apart, so every bar lay
        // across its neighbours and one ran straight through two figures at
        // chest height. 1.15 m is under that spacing by enough that they never
        // touch, and every unit in the fight now draws the same bar, which is
        // the whole point of a bar.
        let barHeight: CGFloat = 0.125
        let width: CGFloat = 1.15

        // A boss wears the awakened LOOK — costume glow, the brighter rim —
        // and the aura, whatever its form. The Colossus is a sandstone giant
        // standing over the far rim in front of a painting of sandstone
        // giants, and the tour photographed it unlit against them as a
        // patch of wall: eight metres of boss, invisible. Light is what
        // separates a figure from its backdrop, and the aura rising from
        // below the rim is what says it climbed out of somewhere.
        let lit = combatant.isAwakened || combatant.isBoss
        let container = ModelLibrary.shared.node(
            for: combatant.model,
            archetype: combatant.archetype,
            element: combatant.element,
            detail: detail,
            awakened: lit
        )
        if lit {
            // The awakened aura: a slow rise of light in the element colour
            // from the feet, for as long as the unit stands.
            container.addParticleSystem(VFXLibrary.aura(tint: tint, scale: Float(modelHeight) / 1.9))
        }
        // A PALE boss keeps the rim and the aura but not the costume glow
        // (run 221): the sandstone Colossus under its warm spot was paper
        // white across the chest and arms, 12% of it clipped, and a glow
        // added on top of pale paint is light it did not need. A dark boss
        // — the serpent, the Hydra, the Jötunn — keeps all of it.
        let albedo = combatant.isBoss ? UnitNode.measurePaint(of: container, key: combatant.model.assetName) : nil
        if combatant.isBoss, !combatant.isAwakened, let albedo, albedo > UnitNode.paleAlbedo {
            container.enumerateHierarchy { child, _ in
                for material in child.geometry?.materials ?? [] {
                    material.setValue(NSNumber(value: Float(0)), forKey: "costumeGlow")
                }
            }
        }
        // And a pale boss's paint answers EVERY light a shade lower (run
        // 234): with its spot already cut to 0.58, the Colossus's right arm
        // and fist were still a flat cream plateau in 18-dungeon_battle-b/c —
        // red clipped at 255, 55% and 64% of the worst 64-px patches over
        // 240 — because the spot was never most of its light. The key, the
        // fill, the painting's environment and the braziers are the SET's,
        // tuned for figures of ordinary paint, and 0.24 of paint gives back
        // 1.7 times what `paleAlbedo` does of each (`paintResponse`).
        if combatant.isBoss, let albedo {
            let response = UnitNode.paintResponse(albedo: albedo)
            if response < 1 {
                container.enumerateHierarchy { child, _ in
                    for material in child.geometry?.materials ?? [] {
                        material.diffuse.intensity = response
                    }
                }
                print("[Boss] \(combatant.model.assetName): pale paint \(String(format: "%.3f", albedo)), answers \(String(format: "%.2f", Double(response))) of every light")
            }
        }

        // Health bar: a dark plate with a coloured fill that scales from its
        // left edge, parented to a billboard so it always faces the camera.
        let barRoot = SCNNode()
        // A light hairline round the plate, so an empty bar reads as an
        // empty bar and not as a dark smudge over the figure; the owner
        // photographed three enemies at the end of a long fight with bars
        // he read as "not showing" — they were showing near nothing.
        let edge = SCNNode(geometry: SCNPlane(width: width + 0.04, height: barHeight + 0.04))
        edge.geometry?.firstMaterial = UnitNode.flatMaterial(UIColor(white: 0.92, alpha: 0.55))
        edge.position = SCNVector3(0, 0, -0.001)
        barRoot.addChildNode(edge)
        let backing = SCNNode(geometry: SCNPlane(width: width, height: barHeight))
        backing.geometry?.firstMaterial = UnitNode.flatMaterial(UIColor.black.withAlphaComponent(0.78))
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
        // `.all`, not `[.X, .Y]`. Those two axes are enough to point a plane
        // at a camera that sits square on the centre line, and that is what
        // this was: the old camera had zero yaw. Giving it 13 degrees so the
        // fight reads in three dimensions left every one of these planes
        // unable to ROLL, so they came to rest tilted with the floor — the
        // CI tour photographed a health bar lying at waist height across two
        // figures like a plank. Freeing the roll costs nothing and is what
        // keeps a bar level on screen from any camera.
        billboard.freeAxes = .all
        barRoot.constraints = [billboard]
        // Clear of the head by a fixed margin rather than a fraction, so a
        // short unit's bar is not resting on its hair and a tall one's is not
        // adrift a metre above it.
        barRoot.position = SCNVector3(0, combatant.model.height + 0.34, 0)

        // The matchup arrow, hidden until a player's turn puts one up. A
        // boss's rode at 0.62 of its height as a 1.1 m billboard, which put
        // it ON the figure — a yellow disc on the Colossus's face, still
        // there as it sank in death (run 220, 18-dungeon_battle-b/c) — so
        // every badge hangs off the bar, and a boss's bar is hidden.
        let badge = SCNNode(geometry: SCNPlane(width: 0.5, height: 0.5))
        badge.geometry?.firstMaterial = UnitNode.imageMaterial(nil)
        badge.isHidden = true
        badge.position = SCNVector3(Float(width / 2) + 0.36, 0, 0.01)
        barRoot.addChildNode(badge)

        // The turn circle under the unit — the readable "whose turn is this"
        // cue (`turnDisc`), hidden until its turn begins.
        let disc = UnitNode.makeTurnDisc(diameter: modelHeight * CGFloat(UnitNode.turnDiscShare), tint: tint)

        self.combatantID = combatant.id
        self.spec = combatant.model
        self.isBoss = combatant.isBoss
        self.element = combatant.element
        self.side = combatant.side
        // The clips come from the mesh on the stage: the awakened export when
        // it shipped, the base one, or the stand-in's own when the base is
        // still on the way.
        self.clipAsset = ModelLibrary.shared.clipAsset(for: combatant.model, awakened: combatant.isAwakened)
        self.elementTint = tint
        self.paintAlbedo = albedo
        self.modelContainer = container
        self.containerRest = container.position
        self.healthBarRoot = barRoot
        self.healthFill = fill
        self.statusRow = statuses
        self.turnDisc = disc
        self.matchupBadge = badge

        super.init()

        name = "combatant_\(combatant.id.uuidString)"
        addChildNode(container)
        addChildNode(barRoot)
        addChildNode(disc)
        if isBoss {
            barRoot.isHidden = true
            disc.isHidden = true
        }
        // The figure's own light layer (Docs/FEEL.md L1), on every node.
        markFigure()

        play(.idleCombat)
        setHealth(fraction: combatant.healthFraction, animated: false)
    }

    // MARK: - The figure's light layer (Docs/FEEL.md L1)

    /// Every node of the unit in the figures' light category
    /// (`StageBuilder.figureCategory`), so the battle's figure fill and
    /// ambient light it and the set's do not. A category is NOT inherited, so
    /// this is called as the unit is built, when its idle is restarted on a
    /// new model's nodes, and by the battle after it hangs anything lit on
    /// the unit (a boss's spot and its aim). Harmless where no light is
    /// layered: every light's own mask is all categories until the battle
    /// splits them.
    func markFigure() {
        enumerateHierarchy { node, _ in
            node.categoryBitMask = StageBuilder.figureCategory
        }
    }

    /// The node that trembles inside a hit's freeze (`Juice`, `Tremor`): the
    /// model's container, which the recoil drives along the same ground.
    var tremorBody: SCNNode { modelContainer }

    required init?(coder: NSCoder) { fatalError("UnitNode is created in code") }

    /// The genre's advantage arrow beside the health bar — green up, yellow
    /// even, red down — for the unit whose turn it is against this one; nil
    /// takes it off.
    ///
    /// A fallen unit takes nil whatever it is asked (the arrow is for a
    /// target, and the dead are not one), and a boss never draws the 3D
    /// badge: without a plate it had nowhere to go but its own body.
    func setMatchup(_ matchup: Element.Matchup?) {
        let shown: Element.Matchup? = isDefeated ? nil : matchup
        plate?.setMatchup(shown)
        guard let arrow = shown, !isBoss else {
            matchupBadge.isHidden = true
            return
        }
        matchupBadge.geometry?.firstMaterial?.diffuse.contents = MatchupIconRenderer.image(for: arrow)
        matchupBadge.isHidden = false
    }

    /// For the island: no health bar and no turn circle, just the figure.
    func hideBattleDecorations() {
        healthBarRoot.isHidden = true
        turnDisc.isHidden = true
    }

    /// The clip a figure AT REST plays on a stage — the island, and a
    /// figure restarted there: the family's standing `idle` when it ships
    /// one (`tools/stand_idle.py` derives one from the combat idle for every
    /// family, 2026-09-18), the combat idle otherwise. No family shipped a
    /// plain idle before that day, so every stage played Meshy's crouched
    /// guard stance; the battle keeps the crouch, which is right there.
    var restingIdle: AnimationClip {
        ModelLibrary.shared.animation(.idle, for: clipAsset) != nil ? .idle : .idleCombat
    }

    // MARK: - The ground shadow

    /// The soft dark oval on the floor under the figure (2026-09-24), the
    /// genre's contact shadow: the owner's Summoners War frames put one under
    /// every unit — centre 46% darker than the floor, 37% on average, about
    /// 0.8 of the body's width — where ours measured 2–5% under a figure,
    /// because the key light's cast shadow falls BEHIND a figure lit from
    /// behind the camera and nothing sat under its feet. Nil on the island,
    /// the Hall of Ka and for a boss (sunk in the rim; nothing to stand on).
    private var groundShadow: SCNNode?

    /// Lays the shadow under the figure. One plane with a radial gradient,
    /// alpha-blended, reading the depth buffer and writing none, four
    /// centimetres over the floor so it never fights the tiles or the
    /// medallion's band (2 cm proud); a child of the unit, so it follows
    /// every step and dash, and `dash(toward:duration:)` shrinks and fades
    /// it as the figure leaps.
    /// Chosen over the key light's shadow alone: that shadow is a sample of
    /// a map spread over the whole set, soft and displaced, and a sharper
    /// one would cost a bigger map or a second cascade on every frame; a
    /// quad per unit costs a dozen triangles and one shared texture.
    ///
    /// ONE SHADOW PER FIGURE, AND IT IS THIS ONE (2026-09-24). The oval
    /// ignores `GraphicsSettings.shadows` on purpose: it is not a light's
    /// shadow but the genre's contact cue — Summoners War draws one under
    /// every unit on every phone — and with shadows off it is the only thing
    /// seating a figure on the stone. And a battle figure casts NO key-light
    /// shadow of its own, shadows on or off (the last line below). The key
    /// stands on the camera's side, so a figure's cast shadow falls right
    /// and back of it: measured from the solved camera, 9–21% of the oval
    /// the lens can see lay inside that shadow too, a crescent beside the
    /// right leg about 48% darker than the lit floor on average and 62% at
    /// worst (the key's shadow takes about a third off the floor it falls
    /// on), where the oval alone is 45% at its centre and the owner's
    /// Summoners War frames 46%; and the rest of the streak showed as a soft
    /// grey band off every figure on the marble, which those frames never
    /// have.
    /// So the key's shadow is the set's (the columns, the statues, the
    /// parapet), as `BattleSceneController.buildLighting` already says, and
    /// the shadow pass no longer draws the skinned figures (a boss, which
    /// has no oval, still casts). What a figure gives up is its self-shadow,
    /// faint on a map spread over 34 m and cast mostly onto faces turned
    /// from the lens, since the key is behind the camera. The figure stages
    /// (the reveal, the altar, the collection) cast from the figure alone
    /// and never call this.
    func attachGroundShadow() {
        guard groundShadow == nil, !isBoss else { return }
        let diameter = CGFloat(spec.height) * 0.5
        let plane = SCNPlane(width: diameter, height: diameter)
        plane.firstMaterial = UnitNode.groundShadowMaterial
        let node = SCNNode(geometry: plane)
        node.name = "ground_shadow"
        // An SCNPlane faces +Z; a quarter turn back about X lays it face up.
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.position = SCNVector3(0, 0.04, 0)
        node.castsShadow = false
        addChildNode(node)
        groundShadow = node
        // The figure throws no key-light shadow (above). Every node of the
        // model, once, before the unit is in the scene: `castsShadow` is a
        // node's own and no child takes it from its parent.
        modelContainer.enumerateHierarchy { child, _ in child.castsShadow = false }
    }

    /// Back to full size and strength, on the floor under the figure.
    private func settleGroundShadow() {
        guard let shadow = groundShadow else { return }
        shadow.removeAllActions()
        shadow.scale = SCNVector3(1, 1, 1)
        shadow.opacity = restingShadowOpacity
    }

    /// The shadow's strength while nothing moves the figure: whole under a
    /// living unit, half under a body, none once the body has left the field
    /// (W2.8). Every turn walks the fallen home too (`returnHome`), and it
    /// brought a body's oval back at half under the empty mark for the rest
    /// of the fight (review, 2026-09-24).
    private var restingShadowOpacity: CGFloat {
        if hasLeftTheField { return 0 }
        return isDefeated ? 0.5 : 1
    }

    /// One material for every unit's shadow: black, its alpha a radial
    /// falloff from 0.55 at the centre to nothing at the rim.
    private static let groundShadowMaterial: SCNMaterial = {
        let side: CGFloat = 128
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let colours = [
                UIColor.black.withAlphaComponent(0.55).cgColor,
                UIColor.black.withAlphaComponent(0.46).cgColor,
                UIColor.black.withAlphaComponent(0.22).cgColor,
                UIColor.black.withAlphaComponent(0.0).cgColor,
            ] as CFArray
            let stops: [CGFloat] = [0, 0.4, 0.72, 1]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: stops) {
                let centre = CGPoint(x: side / 2, y: side / 2)
                context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                                     endCenter: centre, endRadius: side / 2, options: [])
            }
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.diffuse.mipFilter = .linear
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        return material
    }()

    /// Starts the idle again from nothing, for a figure built before it was
    /// in a live scene: an idle attached to a detached node and carried
    /// into a scene that is already rendering never starts (the Hall of
    /// Ka's frozen Zeus, 2026-09-17), and the island rebuilds its figures
    /// into a live scene whenever the team changes.
    func restartIdle() {
        guard !isDefeated else { return }
        currentClip = nil
        modelContainer.removeAllAnimations()
        modelContainer.removeAllActions()
        // A figure rebuilt into a live scene may carry nodes it did not have
        // when it was built; the light layer is every node's own.
        markFigure()
        play(.idleCombat)
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
        // The clip begins at the pace of the moment; `retimeRunningClip`
        // keeps it to the pace from here.
        clipBaseSpeed = playbackSpeed
        clipPace.set(1)
        // A clip that has not started yet and the previous clip's own ending
        // are both stale the moment a new clip begins. The ending used to be a
        // wall-clock timer with no idea what was running when it fired, so on
        // a multi-hit skill the first hit's timer landed part-way through the
        // second hit's flinch and snapped the victim to a neutral stance while
        // it was still being hit.
        removeAction(forKey: "pending_clip")
        modelContainer.removeAction(forKey: "clip_end")
        modelContainer.removeAction(forKey: "clip")

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

            // The library gives every clip the same long cross-fade, which was
            // aimed at the stiff cut from idle to swing. On a LOOP that is
            // right — a loop is a state, and blending both ways is how one
            // state becomes another. On a ONE-SHOT it does the opposite of
            // what was wanted: the first fifth of an attack is the wind-up,
            // the pose furthest from idle and therefore the one a linear blend
            // flattens hardest, so the swing oozed out of the idle with no
            // readable start. A one-shot is an event: it must begin on its own
            // first frame and only blend on the way out. The 0.5 s hit react
            // was losing nearly half of itself to the two fades, which is why
            // a flinch was barely visible at all.
            animation.fadeInDuration = clip.loops ? 0.25 : 0.05
            animation.fadeOutDuration = clip.loops ? 0.25 : 0.16

            var rate = playbackSpeed
            if !clip.loops, clip != .death, animation.duration > 0.05 {
                // EVERY one-shot is retimed to its contract now, not only the
                // ones that run long. The fight is timed to `fallbackDuration`
                // — `BattleSceneController` presents the damage at a fraction
                // of it, the frame the blade lands — so a 1.0 s Meshy sword
                // slash left at its authored length put its contact frame
                // 0.3 s before the damage, and the hit-stop then froze a frame
                // with the attacker already relaxed back into its idle. The
                // clamp is because past 2x a swing is a flicker and below
                // 0.6x it is a mime.
                rate *= max(0.6, min(2.0, animation.duration / clip.fallbackDuration))
            }
            if clip.loops {
                // One cached animation, copied for everybody, started in the
                // same frame for everybody: the whole field breathed on the
                // same frame at the same rate for ever. A random phase and a
                // few per cent of drift in the rate is the cheapest way to
                // make a line of figures look like separate creatures.
                animation.timeOffset = Double.random(in: 0..<max(0.05, animation.duration))
                rate *= Double.random(in: 0.94...1.06)
            }
            animation.speed = Float(max(0.05, rate))

            modelContainer.addAnimation(animation, forKey: clip.rawValue)
            if !clip.loops {
                let played = animation.duration > 0
                    ? animation.duration / Double(max(0.05, animation.speed))
                    : beat(clip.fallbackDuration)
                // Off the battle's field the body stays, faded to 0.6; on it,
                // it leaves once the clip has played (`onFallen`, W2.8), and
                // stands whole until it does.
                if clip == .death, onFallen == nil {
                    modelContainer.runAction(.sequence([.wait(duration: played), .fadeOpacity(to: 0.6, duration: 0.6)]),
                                             forKey: "death_fade")
                }
                scheduleClipEnd(clip, after: played, completion: completion)
            } else {
                completion?()
            }
            return
        }

        playProcedural(clip, completion: completion)
    }

    /// Hands a one-shot back to the idle when it finishes.
    ///
    /// This is a scene action rather than a `DispatchQueue.asyncAfter`, for two
    /// reasons. A hit freezes the whole scene for up to 150 ms (`Juice.impact`)
    /// and a wall-clock timer keeps counting through a freeze that the
    /// animation it is timed against does not, so a five-hit ultimate lost
    /// nearly half a second off the end of its clip and the caster was yanked
    /// to idle before its follow-through. And an action is keyed, so the next
    /// clip cancels it instead of leaving a stale ending to fire mid-swing.
    ///
    /// COUNTED, not waited (2026-09-24). A wait of the clip's length at the
    /// pace it began at ended it early whenever the pace dropped under it —
    /// the final blow's slow motion (W1.7) runs a clip at 0.3 of its pace for
    /// most of a second, and the attacker would have been handed to its idle
    /// in the middle of its follow-through. The clock adds each frame's scene
    /// time at the pace the clip runs at now (`clipPace`, set with the
    /// player's speed by `retimeRunningClip`), so the ending lands where the
    /// clip does whatever the pace did on the way. It counts on the render
    /// thread and only hops to main to act, and it goes quiet once it has
    /// fired; the next clip takes it off.
    private func scheduleClipEnd(_ clip: AnimationClip, after duration: TimeInterval, completion: (() -> Void)?) {
        let pace = clipPace
        let progress = ClipProgress()
        let length: TimeInterval = max(0.01, duration)
        // Long enough for the clip at the slowest pace the fight runs at, and
        // a second more; a clip slowed further still (the speed control
        // stepped down in the middle of it as well) ends with the clock
        // rather than never.
        let span: TimeInterval = length / Self.slowestPace + 1
        let deadline: TimeInterval = span - 0.05
        let clock = SCNAction.customAction(duration: span) { [weak self] _, elapsed in
            // SceneKit runs this on its rendering thread, part-way through
            // the node's own action update, and everything the ending does
            // touches the scene graph. It counts here and hops to main to
            // act, exactly as `playProcedural` documents at the bottom of
            // this file.
            guard !progress.fired else { return }
            let now = Double(elapsed)
            progress.done += (now - progress.last) * pace.value
            progress.last = now
            guard progress.done >= length || now >= deadline else { return }
            progress.fired = true
            DispatchQueue.main.async {
                completion?()
                // A death holds its last frame for good.
                guard let self, clip != .death, !self.isDefeated, self.currentClip == clip else { return }
                self.play(self.idleAfterClip)
            }
        }
        modelContainer.runAction(clock, forKey: "clip_end")
    }

    /// The loop a one-shot hands back to: the combat crouch through the
    /// fight, and the family's standing idle once it has posed for the
    /// triumph (`celebrate(facing:turn:)`).
    private var idleAfterClip: AnimationClip {
        celebrating ? restingIdle : .idleCombat
    }

    /// Set by the triumph (W1.7): the unit has turned to the lens and posed.
    private var celebrating = false

    /// Plays a clip once the feet are down.
    ///
    /// A closing melee attack used to start its swing on the same frame as its
    /// dash, so the wind-up — the only part of an attack that carries
    /// anticipation — happened four metres away in mid-air and the figure
    /// arrived a quarter of the way through its own cut. The wait is a scene
    /// action so that it, the leap and the clip all stop together on a
    /// hit-stop.
    func play(_ clip: AnimationClip, after delay: TimeInterval) {
        guard delay > 0.01 else { play(clip); return }
        removeAction(forKey: "pending_clip")
        runAction(.sequence([
            .wait(duration: delay),
            SCNAction.run { [weak self] _ in
                DispatchQueue.main.async { self?.play(clip) }
            }
        ]), forKey: "pending_clip")
    }

    /// Drops a swing that has been scheduled but has not begun.
    ///
    /// The skip button flushes the queue and snaps the field to the end
    /// state, and a clip still waiting out its dash would otherwise land a
    /// lone attack over a battle that has already been decided.
    func cancelPendingClip() {
        removeAction(forKey: "pending_clip")
    }

    /// Stand-in motion built from SCNActions. Crude by design — it communicates
    /// timing and intent so combat pacing can be tuned before real animation.
    private func playProcedural(_ clip: AnimationClip, completion: (() -> Void)?) {
        modelContainer.removeAction(forKey: "clip")
        // This clip is about to rotate the container's pitch relatively, so it
        // takes that channel off the dash arc first. See `dashOwnsPitch`.
        if dashOwnsPitch {
            dashOwnsPitch = false
            modelContainer.eulerAngles.x = 0
        }
        // Forward, toward the enemy line. Every action below moves the model
        // container, whose parent is the unit node, and the unit node has
        // already been turned to face the enemy — `place` gives the near side
        // a half-turn because a model is authored facing +Z — so forward is
        // local +Z on BOTH sides. The `side == .player ? -1 : 1` this replaces
        // reasoned in WORLD space and then applied the answer in local space,
        // which sent every player unit's lunge and every player unit's gather
        // the wrong way: the near line wound up by stepping toward its victim
        // and then struck by retreating from it.
        let facing: Float = 1

        let action: SCNAction
        switch clip {
        case .idle, .idleCombat, .walk:
            // A `moveBy` that is interrupted half way leaves the container
            // where it stood, and over a battle of interruptions the bob
            // drifts, so the rest height is restored before it starts again.
            // The depth goes back too: the lunges below are relative and
            // `recoil` writes the same axis as an absolute value, so a unit
            // struck in the middle of its own swing ends it a few centimetres
            // off its mark. Every one-shot comes back through here, which
            // makes the idle the one place that residue can be swept up.
            modelContainer.position.y = containerRest.y
            modelContainer.position.z = containerRest.z
            // Same lockstep problem as the skeletal idle above, and worse: a
            // fixed 1.1 s bob started in the same frame for every unit on the
            // field. The period is jittered and the first idle waits a random
            // fraction of it, so nothing breathes in time with anything else.
            let period = beat(Double.random(in: 0.95...1.25))
            let up = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.012, z: 0, duration: period)
            up.timingMode = .easeInEaseOut
            let breathe = SCNAction.repeatForever(.sequence([up, up.reversed()]))
            let lead = hasIdled ? 0 : Double.random(in: 0...period)
            hasIdled = true
            action = lead > 0.01 ? SCNAction.sequence([.wait(duration: lead), breathe]) : breathe

        case .attackBasic:
            // Gather, strike, recover. The old version was a lunge and its
            // reverse with a flat wait between them, which is a slide with a
            // pause in it: there was nothing to anticipate the blow.
            let gather = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(-facing) * 0.12, duration: beat(0.14))
            gather.timingMode = .easeOut
            let lunge = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(facing) * 0.57, duration: beat(0.12))
            lunge.timingMode = .easeIn
            let recover = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(-facing) * 0.45, duration: beat(0.26))
            recover.timingMode = .easeInEaseOut
            action = .sequence([gather, lunge, .wait(duration: beat(0.10)), recover])

        case .attackHeavy, .castRelease:
            let wind = SCNAction.rotateBy(x: -0.22, y: 0, z: 0, duration: beat(0.28))
            wind.timingMode = .easeOut
            let strike = SCNAction.rotateBy(x: 0.34, y: 0, z: 0, duration: beat(0.1))
            strike.timingMode = .easeIn
            let lunge = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(facing) * 0.6, duration: beat(0.12))
            lunge.timingMode = .easeIn
            action = .sequence([
                wind, .group([strike, lunge]), .wait(duration: beat(0.2)),
                .group([.rotateBy(x: -0.12, y: 0, z: 0, duration: beat(0.2)), lunge.reversed()])
            ])

        case .ultimate:
            let rise = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.35, z: 0, duration: beat(0.6))
            rise.timingMode = .easeOut
            let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: beat(0.9))
            let slam = SCNAction.moveBy(x: 0, y: CGFloat(-spec.height) * 0.35, z: 0, duration: beat(0.22))
            slam.timingMode = .easeIn
            action = .sequence([rise, spin, slam, .wait(duration: beat(0.35))])

        case .castLoop:
            action = .repeatForever(.rotateBy(x: 0, y: 0.6, z: 0, duration: beat(1.5)))

        case .hitReact:
            // The shove away from the blow is `recoil`, which every hit fires
            // whether or not a real clip exists, so this is only the flinch on
            // top of it — a twist, not a translation, so the two never fight
            // over the same axis of the same node.
            let twist = SCNAction.rotateBy(x: -0.15, y: CGFloat(facing) * 0.12, z: 0, duration: beat(0.07))
            twist.timingMode = .easeOut
            let settle = twist.reversed()
            settle.timingMode = .easeInEaseOut
            action = .sequence([twist, .wait(duration: beat(0.06)), settle])

        case .death:
            let fall = SCNAction.rotateBy(x: -.pi / 2.2, y: 0, z: 0, duration: beat(0.55))
            fall.timingMode = .easeIn
            action = .group([fall, .fadeOpacity(to: 0.15, duration: beat(0.7))])

        case .victory:
            let jump = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.18, z: 0, duration: beat(0.3))
            jump.timingMode = .easeOut
            let land = jump.reversed()
            land.timingMode = .easeIn
            action = .repeat(.sequence([jump, land]), count: 3)

        case .summonReveal:
            action = .sequence([
                .fadeOpacity(to: 1, duration: beat(0.6)),
                .rotateBy(x: 0, y: .pi * 2, z: 0, duration: beat(1.6))
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
    /// Where a dash at `target` lands: a stride short of it, on the line
    /// between them. The camera asks before the leap begins
    /// (`CameraDirector.perform(_:on:target:focus:)`), so a push-in on a
    /// melee caster lands on the figure and not on the mark it just left.
    func dashDestination(toward target: UnitNode) -> SCNVector3 {
        let from = position
        let to = target.position
        let dx = to.x - from.x, dz = to.z - from.z
        let distance = max(0.001, (dx * dx + dz * dz).squareRoot())
        let stride = spec.height * 0.7
        let travel = max(0, distance - stride)
        return SCNVector3(from.x + dx / distance * travel, from.y, from.z + dz / distance * travel)
    }

    func dash(toward target: UnitNode, duration: TimeInterval) {
        if homePosition == nil {
            homePosition = position
            homeYaw = eulerAngles.y
        }
        let from = position
        let to = target.position
        let dx = to.x - from.x, dz = to.z - from.z
        let destination = dashDestination(toward: target)

        // Gather, fly, land — the three beats every convincing jump has, and
        // the reason this one now reads as a figure moving itself rather than
        // one being carried. The old dash was a single eased slide with a
        // symmetric up-and-down hop laid over it: nothing coiled before it
        // went and nothing absorbed the landing, which is exactly the pair of
        // frames the eye reads as weight.
        let gather = duration * Self.dashGather
        let flight = duration * Self.dashFlight

        removeAction(forKey: "dash")
        let move = SCNAction.move(to: destination, duration: flight)
        // Out of the crouch hard and into the victim soft. An ease at both
        // ends has no push-off, and a linear move reads as cheap at any speed.
        move.timingMode = .easeOut
        // The model is authored facing +Z, so this yaw faces the victim. (A
        // CAMERA looks along its own -Z and must use `look(at:)`; a character
        // does not.)
        let turn = SCNAction.rotateTo(
            x: 0, y: CGFloat(atan2(dx, dz)), z: 0,
            duration: gather + flight * 0.5, usesShortestUnitArc: true
        )
        turn.timingMode = .easeInEaseOut
        runAction(.group([.sequence([.wait(duration: gather), move]), turn]), forKey: "dash")

        // Height and lean are driven by one curve over the whole dash rather
        // than by a stack of `moveBy`s, so every frame is an absolute value:
        // an interrupted dash can leave no residue, and the arc is a real
        // parabola — fastest through the top — instead of up-then-down.
        let rest = containerRest.y
        let apex = spec.height * 0.18
        // The coil is a token dip only. A unit's feet sit ON the platform, so
        // a crouch built out of a downward translation drives the lower legs
        // through an opaque floor: at the 0.06 of its height this started at,
        // a 1.8 m figure sank eleven centimetres into the stage and a 3.2 m
        // boss nearly twenty. What sells the anticipation is the backward
        // lean below; a crouch that reads properly has to come out of the
        // skeleton, which is not something this file can author.
        let dip = spec.height * 0.02
        let span = max(0.01, duration)
        dashOwnsPitch = true
        modelContainer.removeAction(forKey: "hop")
        let arc = SCNAction.customAction(duration: span) { [weak self] node, elapsed in
            let t = Float(min(1, max(0, Double(elapsed) / span)))
            var height: Float = 0
            var lean: Float = 0
            if t < Float(Self.dashGather) {
                // Coil: down and back, the weight loading before the push.
                let g = t / Float(Self.dashGather)
                height = -dip * sin(g * .pi * 0.5)
                lean = -0.10 * g
            } else if t < Float(Self.dashGather + Self.dashFlight) {
                let f = (t - Float(Self.dashGather)) / Float(Self.dashFlight)
                height = -dip * (1 - f) + apex * 4 * f * (1 - f)
                lean = -0.10 * (1 - f) + 0.16 * f
            } else {
                // Absorb: the knees give on landing and come back up.
                let l = (t - Float(Self.dashGather + Self.dashFlight)) / Float(Self.dashLand)
                height = -dip * 0.85 * sin(min(1, l) * .pi)
                lean = 0.16 * (1 - min(1, l))
            }
            node.position.y = rest + height
            // The shadow stays on the floor and shrinks and fades as the
            // figure rises off it (`attachGroundShadow`).
            if let shadow = self?.groundShadow {
                let lift = max(0, height) / max(0.01, apex)
                let size = 1 - 0.3 * lift
                shadow.scale = SCNVector3(size, size, 1)
                shadow.opacity = CGFloat(1 - 0.45 * lift)
            }
            // The height is the arc's alone; the pitch is only its while no
            // procedural clip has taken it over. See `dashOwnsPitch`.
            if self?.dashOwnsPitch == true { node.eulerAngles.x = lean }
        }
        modelContainer.runAction(.sequence([arc, SCNAction.run { [weak self] node in
            node.position.y = rest
            // Scale and strength only: this runs on the render thread.
            if let self, let shadow = self.groundShadow {
                shadow.scale = SCNVector3(1, 1, 1)
                shadow.opacity = self.restingShadowOpacity
            }
            if self?.dashOwnsPitch == true { node.eulerAngles.x = 0 }
        }]), forKey: "hop")
    }

    /// Where the beats of a dash fall, as fractions of its duration. The clip
    /// is held until `dashGather + dashFlight` of the way through (see
    /// `BattleSceneController`), so the wind-up begins as the weight lands.
    static let dashGather = 0.22
    static let dashFlight = 0.70
    static let dashLand = 0.08

    /// Back to the spot it stood on, facing the way it did. Nothing happens
    /// for a unit that never dashed.
    func returnHome(duration: TimeInterval) {
        guard let home = homePosition else { return }
        removeAction(forKey: "dash")
        // The arc writes the container's height and lean every frame, so
        // cancelling it in mid-flight would leave the figure hanging tilted in
        // the air. Both are put back by hand.
        modelContainer.removeAction(forKey: "hop")
        modelContainer.position.y = containerRest.y
        // Only the arc's own lean is undone. A procedural clip that has taken
        // the pitch over is rotating it relatively toward its own zero, and
        // forcing it flat underneath that would leave the figure tilted for
        // the rest of the fight.
        if dashOwnsPitch { modelContainer.eulerAngles.x = 0 }
        settleGroundShadow()
        let move = SCNAction.move(to: home, duration: duration)
        move.timingMode = .easeInEaseOut
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(homeYaw), z: 0, duration: duration, usesShortestUnitArc: true)
        runAction(.group([move, turn]), forKey: "dash")
    }

    /// The shove a blow puts through a body: the whole figure is driven
    /// backwards off its stance and springs back onto it.
    ///
    /// A hit used to be a white flash and a number over a figure that never
    /// moved, which is most of why the fight read as "numbers changing" rather
    /// than as something being struck. It is deliberately NOT part of the hit
    /// react clip: most exports do not ship one, and a shove that only some
    /// families have is worse than none. Backwards is the container's own -Z,
    /// because a unit faces the line it is fighting, so this is away from the
    /// blow for a defender at its mark and for an attacker caught by a
    /// counter mid-dash alike.
    func recoil(strength: Float) {
        guard !isDefeated else { return }
        let push = spec.height * 0.055 * min(2.4, max(0.4, strength))
        let rest = containerRest.z
        let span = beat(0.26)
        modelContainer.removeAction(forKey: "recoil")
        modelContainer.runAction(.sequence([
            SCNAction.customAction(duration: span) { node, elapsed in
                let t = Float(min(1, max(0, Double(elapsed) / span)))
                // Driven out over the first quarter and returning over the
                // rest: a symmetric there-and-back reads as a slide, a fast
                // out and a decaying return reads as a body absorbing a blow.
                let out: Float
                if t < 0.25 {
                    out = sin(t / 0.25 * .pi * 0.5)
                } else {
                    let u = (t - 0.25) / 0.75
                    out = (1 - u) * (1 - u)
                }
                node.position.z = rest - push * out
            },
            SCNAction.run { node in node.position.z = rest }
        ]), forKey: "recoil")
    }

    /// A white flash over the whole model on the frame a hit lands, fading
    /// over a fifth of a second. The emission is what the tint left there,
    /// and it is put back.
    ///
    /// `strength` over 1 is the IMPACT FRAME's burn (Docs/FEEL.md W1.3, a
    /// crit or a kill): the figure goes fully white, its emission `strength`
    /// times as bright, for `burnHold` on the main queue, and then falls to
    /// the ordinary flash and fades as that does. The camera's grade is
    /// punched for two DRAWN frames on the renderer's thread
    /// (`BattleSceneController.impactFrames`), so a main thread stalled after
    /// the blow can hold the burn a little past the grade: a white figure for
    /// the length of a stall, never a grey world.
    ///
    /// The emission it puts back is the one the figure was BUILT with
    /// (`restEmission`), not whatever it holds when the flash lands: a
    /// second flash inside the first's burn read the burn's white as the
    /// colour to return to.
    func flashHit(strength: CGFloat = 1) {
        flashGeneration += 1
        let generation = flashGeneration
        let burns = strength > 1
        let rest = restEmission
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        for entry in rest {
            entry.material.emission.contents = UIColor(white: burns ? 1 : 0.8, alpha: 1)
            entry.material.emission.intensity = burns ? strength : entry.intensity
        }
        SCNTransaction.commit()
        let fade: () -> Void = { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            if burns {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0
                for entry in rest {
                    entry.material.emission.contents = UIColor(white: 0.8, alpha: 1)
                    entry.material.emission.intensity = entry.intensity
                }
                SCNTransaction.commit()
            }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.22
            for entry in rest {
                entry.material.emission.contents = entry.contents
            }
            SCNTransaction.commit()
        }
        if burns {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.burnHold) { fade() }
        } else {
            fade()
        }
    }

    /// How long the impact frame's burn holds: two frames at 60 Hz.
    static let burnHold: TimeInterval = 2.0 / 60.0

    /// Bumped by every flash, so a burn's fade that a newer flash overtook
    /// steps aside.
    private var flashGeneration = 0

    /// Every material of the model with the emission it was built with.
    private lazy var restEmission: [(material: SCNMaterial, contents: Any?, intensity: CGFloat)] = {
        var found: [(material: SCNMaterial, contents: Any?, intensity: CGFloat)] = []
        modelContainer.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                found.append((material: material, contents: material.emission.contents, intensity: material.emission.intensity))
            }
        }
        return found
    }()

    // MARK: - State

    func setHealth(fraction: Double, animated: Bool = true) {
        plate?.setHealth(fraction, animated: animated)
        let clamped = Float(min(1, max(0, fraction)))
        // Never below a sliver while there is health at all: a unit on its
        // last points still shows a mark of colour, not a bare plate.
        let shown = fraction > 0 ? max(0.04, clamped) : 0.0001
        let scale = SCNVector3(shown, 1, 1)
        if animated {
            let action = SCNAction.customAction(duration: 0.25) { node, elapsed in
                let t = Float(elapsed / 0.25)
                let current = node.scale.x
                node.scale = SCNVector3(current + (shown - current) * t, 1, 1)
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

    /// The acting unit's marks: its plate's gold rim, and the turn circle
    /// under it, popped in — from just over half its size to a touch past
    /// full and back, as it fades up — then breathing slowly between 72% and
    /// all of `turnDiscPeak` while the rune ring turns. Only a change does
    /// anything, so the others are not faded again on every turn.
    func setHighlighted(_ highlighted: Bool) {
        plate?.setActing(highlighted)
        guard highlighted != discLit else { return }
        discLit = highlighted
        turnDisc.removeAction(forKey: "turn")
        guard highlighted, !isDefeated else {
            turnDisc.runAction(.fadeOpacity(to: 0, duration: 0.2), forKey: "turn")
            return
        }
        let peak = turnDiscPeak
        turnDisc.opacity = 0
        // Under Reduce Motion the disc fades in at its size; it pops out of
        // a smaller one otherwise.
        let calm = MotionComfort.isReduced
        let start: Float = calm ? 1 : 0.55
        turnDisc.scale = SCNVector3(start, start, start)
        let grow = SCNAction.scale(to: calm ? 1.0 : 1.08, duration: 0.14)
        grow.timingMode = .easeOut
        let settle = SCNAction.scale(to: 1.0, duration: 0.12)
        settle.timingMode = .easeInEaseOut
        let pop = SCNAction.group([.fadeOpacity(to: peak, duration: calm ? 0.26 : 0.12), .sequence([grow, settle])])
        let dim = SCNAction.fadeOpacity(to: peak * 0.72, duration: 0.9)
        dim.timingMode = .easeInEaseOut
        let lift = SCNAction.fadeOpacity(to: peak, duration: 0.9)
        lift.timingMode = .easeInEaseOut
        turnDisc.runAction(.sequence([pop, .repeatForever(.sequence([dim, lift]))]), forKey: "turn")
    }

    /// The turn disc's diameter over the unit's height: 0.95 of a figure's
    /// width, which the ground shadow puts at about 0.625 of its height.
    static let turnDiscShare: Float = 0.6

    /// The turn circle: the rune ring the cast ring and the summon dais draw
    /// (`StageBuilder.runeRing`, additive, turning once in forty seconds,
    /// writing no depth) in the element's colour, over a soft pool of the
    /// same light half as wide again. It lies a few centimetres over the
    /// floor and is drawn after the ground shadow (`renderingOrder`), so the
    /// light lies on the darkened stone rather than under it. It throws no
    /// shadow, and starts hidden.
    private static func makeTurnDisc(diameter: CGFloat, tint: UIColor) -> SCNNode {
        let disc = SCNNode()
        disc.name = "turn_disc"
        disc.opacity = 0
        disc.position = SCNVector3(0, 0.012, 0)

        let pool = SCNPlane(width: diameter * 1.5, height: diameter * 1.5)
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = turnGlow
        glow.multiply.contents = tint
        glow.blendMode = .add
        // Adds light and writes no alpha, as every additive quad here must
        // (`StageBuilder.runeRing` says why).
        glow.colorBufferWriteMask = [.red, .green, .blue]
        glow.writesToDepthBuffer = false
        glow.isDoubleSided = true
        pool.firstMaterial = glow
        let poolNode = SCNNode(geometry: pool)
        poolNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        poolNode.position = SCNVector3(0, 0.016, 0)
        poolNode.opacity = 0.45
        disc.addChildNode(poolNode)

        disc.addChildNode(StageBuilder.runeRing(radius: diameter / 2, tint: tint))
        disc.enumerateHierarchy { node, _ in
            node.castsShadow = false
            node.renderingOrder = 5
        }
        return disc
    }

    /// The pool of light under the turn circle: white at the centre falling
    /// to black at the rim, opaque, so an additive quad adds only its middle.
    private static let turnGlow: UIImage = {
        let side: CGFloat = 128
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let colours = [
                UIColor(white: 0.85, alpha: 1).cgColor,
                UIColor(white: 0.35, alpha: 1).cgColor,
                UIColor(white: 0.0, alpha: 1).cgColor,
            ] as CFArray
            let stops: [CGFloat] = [0, 0.5, 1]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: stops) {
                let centre = CGPoint(x: side / 2, y: side / 2)
                cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                      endCenter: centre, endRadius: side / 2, options: [])
            }
        }
    }()

    /// Rebuilds the little status pips above the health bar.
    /// What the unit is under right now, drawn as icons over its bar.
    private var activeStatuses: [ActiveStatus] = []

    /// The buffs and debuffs on a unit, as the genre shows them: a row of
    /// icons over the health bar, a blue tile for a buff and a red one for a
    /// debuff, the effect's glyph on it and the turns left in the corner.
    /// The coloured dots of the first build told the player nothing.
    func setStatuses(_ statuses: [ActiveStatus], leaving: StatusTileExit = .expire) {
        activeStatuses = statuses
        plate?.setStatuses(statuses, leaving: leaving)
        // The mark round the head while it cannot act (W2.22).
        let mark = HeadMarkKind.of(statuses.map { $0.kind })
        if mark != headMarkShown, let markOverlay {
            headMarkShown = mark
            markOverlay.setHeadMark(mark, for: combatantID)
        }
        statusRow.childNodes.forEach { $0.removeFromParentNode() }
        // One tile per kind, the longest-lasting of each, six at most.
        var byKind: [StatusKind: Int] = [:]
        for status in statuses { byKind[status.kind] = max(byKind[status.kind] ?? 0, status.turnsRemaining) }
        let shown = byKind.sorted { $0.key.rawValue < $1.key.rawValue }.prefix(6)
        guard !shown.isEmpty else { return }

        // Constant, for the same reason the bar is: a status tile that
        // scales with the model makes the Colossus's poison four times the
        // size of a satyr's, and the player is reading them against each
        // other. Sized to sit on a 1.15 m bar — five fit across it.
        let pip: CGFloat = 0.22
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

    /// A status gone: run out, or — `cleansed` — taken off by a cleanse,
    /// whose red tiles are wiped rather than shrunk (W2.22).
    func removeStatus(_ kind: StatusKind, cleansed: Bool = false) {
        setStatuses(activeStatuses.filter { $0.kind != kind }, leaving: cleansed ? .cleanse : .expire)
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
        // The final blow starts the fall on the blow itself
        // (`beginFinalFall`); it is not played a second time.
        if currentClip != .death {
            let life = lifeSerial
            play(.death) { [weak self] in self?.deathClipEnded(life: life) }
        }
        isDefeated = true
        plate?.setDefeated(true)
        plate?.setMatchup(nil)
        matchupBadge.isHidden = true
        healthBarRoot.runAction(.fadeOut(duration: 0.4))
        groundShadow?.runAction(.fadeOpacity(to: 0.5, duration: 0.8))
        discLit = false
        turnDisc.runAction(.fadeOpacity(to: 0, duration: 0.3), forKey: "turn")
        // A fall that began on the final blow may have played out already.
        reportFallen()
    }

    /// The final blow's fall (Docs/FEEL.md W1.7) begins on the blow itself,
    /// not when the engine's `.defeated` is presented after the slow motion:
    /// the fall is what the slow motion slows.
    func beginFinalFall() {
        guard !isDefeated else { return }
        let life = lifeSerial
        play(.death) { [weak self] in self?.deathClipEnded(life: life) }
    }

    /// Main thread: the death clip has run its length (its counted clock, or
    /// the procedural fall's action) — the death of `life`, which a revive
    /// since has left behind.
    private func deathClipEnded(life: Int) {
        guard life == lifeSerial else { return }
        deathPlayedOut = true
        reportFallen()
    }

    /// `onFallen`, once a death is both played and marked.
    private func reportFallen() {
        guard isDefeated, deathPlayedOut, !fallReported else { return }
        fallReported = true
        onFallen?(self)
    }

    /// The body fades from the field (W2.8): the model to nothing over
    /// `duration` — its aura quieted first, so the motes already up die out
    /// on their own and no system is taken off a live node — and its ground
    /// shadow with it. The node stays, hidden in plain sight, with its plate
    /// and its mark: the engine may revive it.
    func dissolveBody(over duration: TimeInterval) {
        guard isDefeated, !hasLeftTheField else { return }
        hasLeftTheField = true
        quietAura()
        let span: TimeInterval = max(0.01, duration)
        let fade = SCNAction.fadeOpacity(to: 0, duration: span)
        fade.timingMode = .easeIn
        modelContainer.runAction(fade, forKey: "death_fade")
        groundShadow?.removeAllActions()
        groundShadow?.runAction(.fadeOpacity(to: 0, duration: span))
    }

    /// A boss's death (W2.8): it goes back under the rim it climbed over —
    /// `Dissolve.bossDepth` of its height, gathering speed — fading in the
    /// last part of the fall, its warm spot going out with it.
    func sinkBelowRim(over duration: TimeInterval) {
        guard isDefeated, !hasLeftTheField else { return }
        hasLeftTheField = true
        quietAura()
        sunkFrom = position
        let span: TimeInterval = max(0.01, duration)
        let depth = CGFloat(spec.height * Dissolve.bossDepth)
        let sink = SCNAction.moveBy(x: 0, y: -depth, z: 0, duration: span)
        sink.timingMode = .easeIn
        let fade = SCNAction.sequence([.wait(duration: span * 0.55), .fadeOut(duration: span * 0.45)])
        runAction(.group([sink, fade]), forKey: "sink")
        var lights: [(light: SCNLight, rest: CGFloat)] = []
        enumerateHierarchy { child, _ in
            if let light = child.light { lights.append((light: light, rest: light.intensity)) }
        }
        sunkLights = lights
        SCNTransaction.begin()
        SCNTransaction.animationDuration = span
        for entry in lights { entry.light.intensity = 0 }
        SCNTransaction.commit()
    }

    /// A faint glyph of the unit's element left on its mark (W2.8): a ring
    /// and the element's symbol, added over the stone at `opacity`, faded up
    /// over `fade`. A child of the unit, so a tap on it reaches the unit — a
    /// reviver's target is found where the body lay — and turned against
    /// the unit's resting facing so it reads upright from the camera on
    /// either side. A revive takes it up (`revive`).
    func leaveMark(opacity: CGFloat, fade: TimeInterval) {
        guard fallenMark == nil, !isBoss else { return }
        let side = CGFloat(spec.height) * 0.62
        let plane = SCNPlane(width: side, height: side)
        plane.firstMaterial = UnitNode.markMaterial(for: element)
        let glyph = SCNNode(geometry: plane)
        glyph.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        let mark = SCNNode()
        mark.name = "fallen_mark"
        mark.position = SCNVector3(0, 0.022, 0)
        mark.eulerAngles = SCNVector3(0, -restingYaw, 0)
        mark.addChildNode(glyph)
        mark.enumerateHierarchy { node, _ in
            node.castsShadow = false
            // Over the ground shadow, under the turn disc.
            node.renderingOrder = 4
        }
        mark.opacity = 0
        addChildNode(mark)
        mark.runAction(.fadeOpacity(to: opacity, duration: max(0.01, fade)))
        fallenMark = mark
    }

    /// The way this unit faces at its mark: its home yaw once it has dashed
    /// (`dash` records it), its yaw now otherwise.
    private var restingYaw: Float {
        homePosition != nil ? homeYaw : eulerAngles.y
    }

    /// Every looping system on the model (the awakened aura) stops being
    /// born, remembering its rate. Never taken off: a system's instance
    /// outliving its node was the crash of 2026-09-15.
    private func quietAura() {
        guard quietedSystems.isEmpty else { return }
        for system in modelContainer.particleSystems ?? [] {
            quietedSystems.append((system: system, rate: system.birthRate))
            system.birthRate = 0
        }
    }

    private func restoreAura() {
        for entry in quietedSystems { entry.system.birthRate = entry.rate }
        quietedSystems = []
    }

    /// Back from leaving the field, for a revive: the aura lit again, the
    /// mark taken up, a sunk boss put back where it sank from with its lights.
    private func comeBack() {
        hasLeftTheField = false
        restoreAura()
        removeAction(forKey: "sink")
        if let from = sunkFrom { position = from }
        sunkFrom = nil
        opacity = 1
        for entry in sunkLights { entry.light.intensity = entry.rest }
        sunkLights = []
    }

    /// The glyph a fallen unit leaves, per element: a double ring and the
    /// element's symbol in grey on black, for an additive quad whose
    /// multiply is the element's colour (`markMaterial`).
    private static var markImages: [String: UIImage] = [:]

    private static func markImage(for element: Element) -> UIImage {
        if let cached = markImages[element.rawValue] { return cached }
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            cg.setStrokeColor(UIColor(white: 0.6, alpha: 1).cgColor)
            cg.setLineWidth(6)
            cg.strokeEllipse(in: CGRect(x: 14, y: 14, width: side - 28, height: side - 28))
            cg.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: CGRect(x: 32, y: 32, width: side - 64, height: side - 64))
            let configuration = UIImage.SymbolConfiguration(pointSize: 92, weight: .semibold)
            if let symbol = UIImage(systemName: element.glyph, withConfiguration: configuration)?
                .withTintColor(UIColor(white: 0.9, alpha: 1), renderingMode: .alwaysOriginal) {
                let size = symbol.size
                let rect = CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height)
                symbol.draw(in: rect)
            }
        }
        markImages[element.rawValue] = image
        return image
    }

    private static func markMaterial(for element: Element) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = markImage(for: element)
        material.diffuse.mipFilter = .linear
        material.multiply.contents = (UIColor(hex: element.accentHex) ?? .white).mixed(with: .white, amount: 0.15)
        material.blendMode = .add
        // Adds light and writes no alpha (`StageBuilder.runeRing`).
        material.colorBufferWriteMask = [.red, .green, .blue]
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        return material
    }

    // MARK: - Walking on (Docs/FEEL.md W2.10)

    /// Whether this unit's rig shipped a walk (Meshy's Casual Walk, preset
    /// 30; the families rigged before 2026-09-17 have none). The briefing's
    /// warm pass has parsed it for every wave; a fight started without one
    /// parses it here, once.
    var hasWalkClip: Bool {
        ModelLibrary.shared.animation(.walk, for: clipAsset) != nil
    }

    /// A wave's arrival walks onto its mark: its walk clip at the fight's
    /// pace, the node carried at the stride the clip was made for
    /// (`WalkOn.speed`, the caller's `duration`), faded up as it comes out
    /// of the far set, and the combat idle once it stands there. Called
    /// once the unit is in the scene: a clip attached before that never
    /// starts (the Hall of Ka's Zeus, 2026-09-17).
    func walkOn(to mark: SCNVector3, over duration: TimeInterval, fadeIn: TimeInterval) {
        play(.walk)
        let move = SCNAction.move(to: mark, duration: max(0.01, duration))
        move.timingMode = .linear
        // SceneKit runs the block on its render thread: it only hops.
        let arrive = SCNAction.run { [weak self] _ in
            DispatchQueue.main.async { self?.settleFromWalk() }
        }
        runAction(.group([.sequence([move, arrive]), .fadeIn(duration: max(0.01, fadeIn))]), forKey: "walk_on")
    }

    /// On its mark: the walk gives way to the combat idle, unless something
    /// has already taken the figure over.
    private func settleFromWalk() {
        guard !isDefeated, currentClip == .walk else { return }
        play(.idleCombat)
    }

    /// Whether a status of this kind is on the unit now (a resisted status
    /// on a unit wearing Immunity reads IMMUNE, not RESIST).
    func hasStatus(_ kind: StatusKind) -> Bool {
        activeStatuses.contains { $0.kind == kind }
    }

    // MARK: - The triumph (Docs/FEEL.md W1.7)

    /// The survivor's pose on a won field: it steps the last of the way onto
    /// its mark (a melee unit may still be walking back from its last
    /// blow), turns to face the lens at `lens` — a turn about the vertical
    /// alone, the lens taken at the figure's own height, with
    /// `look(at:up:localFront:)` and the model's authored front (+Z) — and
    /// plays its own victory clip; after it, it stands in its resting idle
    /// rather than the combat crouch. The turn is one implicit animation
    /// over `duration`; nothing here runs inside an action.
    ///
    /// The pose runs at `pace`, never the fight's: the beat is not the
    /// fight, and at ×3 the clip's 2.0-s contract played in two thirds of a
    /// second, over before the turn to the lens had finished, and left the
    /// figure breathing at three times for the rest of the beat (review,
    /// 2026-09-24). Nothing re-paces a unit once the HUD has gone: the
    /// controller calls this after ending the slow motion, and the speed
    /// control is hidden with the HUD.
    func celebrate(facing lens: SCNVector3, turn duration: TimeInterval, pace: Double = 1) {
        guard !isDefeated else { return }
        celebrating = true
        cancelPendingClip()
        removeAction(forKey: "dash")
        modelContainer.removeAction(forKey: "hop")
        modelContainer.position.y = containerRest.y
        if dashOwnsPitch {
            dashOwnsPitch = false
            modelContainer.eulerAngles.x = 0
        }
        settleGroundShadow()
        let mark = homePosition ?? position
        let target = SCNVector3(lens.x, mark.y, lens.z)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = max(0, duration)
        SCNTransaction.animationTimingFunction = .init(name: .easeInEaseOut)
        position = mark
        look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        SCNTransaction.commit()
        playbackSpeed = pace
        play(.victory)
    }

    func revive(healthFraction: Double) {
        isDefeated = false
        // A new life: its next death is told again, and whatever the last
        // one left on the field is taken back (W2.8) — the aura, the glyph
        // on its mark, a sunk boss's place and light.
        lifeSerial += 1
        deathPlayedOut = false
        fallReported = false
        let wasGone = hasLeftTheField
        if wasGone { comeBack() }
        fallenMark?.removeFromParentNode()
        fallenMark = nil
        modelContainer.removeAllActions()
        modelContainer.removeAnimation(forKey: AnimationClip.death.rawValue)
        modelContainer.eulerAngles = SCNVector3Zero
        // A death, an interrupted leap or a recoil can all leave the container
        // off its rest transform, and a revived unit standing 20 cm to the
        // rear of its mark is the kind of thing nobody can name but everybody
        // sees.
        modelContainer.position = containerRest
        modelContainer.opacity = 1
        // A body that had left the field comes back out of the air rather
        // than popping in whole.
        if wasGone {
            modelContainer.opacity = 0
            modelContainer.runAction(.fadeIn(duration: beat(0.35)))
        }
        plate?.setDefeated(false)
        healthBarRoot.runAction(.fadeIn(duration: 0.3))
        settleGroundShadow()
        // Its shadow comes back with it, not ahead of it.
        if wasGone, let shadow = groundShadow {
            shadow.opacity = 0
            shadow.runAction(.fadeOpacity(to: 1, duration: beat(0.35)))
        }
        setHealth(fraction: healthFraction, animated: false)
        play(restingIdle)
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

    // MARK: - A boss's paint

    /// Where paint counts as pale, in linear light: the Jötunn's (0.13, pale
    /// ice over a dark hide) is under it and the sandstone Colossus's (0.24)
    /// well over. Measured off the shipped base colours
    /// the way `measurePaint` reads them (32 × 32, box-averaged): the
    /// serpent 0.03, the Hydra 0.06, the Jötunn 0.13, the Azure Dragon 0.19,
    /// the Colossus 0.24, the Dragon King 0.30, the Unwrapped King 0.50.
    static let paleAlbedo: Double = 0.14

    /// How much of a boss's warm spot its paint wants, 0.3…1 of the full
    /// light: all of it for a dark hide, which is what the spot is for (the
    /// owner, of the serpent against a night painting: "it's hard to see the
    /// boss"), and in proportion less as the paint is paler than
    /// `paleAlbedo`, so every boss gives back the same light from it. The
    /// Colossus takes 0.58 (about 1,390 of 2,400): at the full spot its
    /// chest and arms were paper white, 79% of the worst patch clipped
    /// (run 221). One for a unit that is not a boss or whose paint is
    /// unread, which is the light it had before.
    var bossLightScale: CGFloat {
        guard let paintAlbedo, paintAlbedo > 0.001 else { return 1 }
        return CGFloat(min(1, max(0.3, UnitNode.paleAlbedo / paintAlbedo)))
    }

    /// How much of every light a boss's paint answers, 0.5…1 — set as its
    /// materials' diffuse intensity, so the painted base colour is what is
    /// scaled and the rim that sets the figure off its painting, and the
    /// stone's sheen, keep their strength. All of it up to `paleAlbedo`;
    /// above it the square root of the ratio, which keeps HALF the paint's
    /// excess over the calibration in stops (the paint answers as the
    /// geometric mean of itself and `paleAlbedo`): the Colossus (0.24)
    /// 0.76, the Dragon King (0.30) 0.68, the Unwrapped King (0.50) 0.53,
    /// and the serpent, the Hydra and the Jötunn, under the line, all of
    /// it. Never under half, so a misread paint cannot put a boss in the
    /// dark (the owner: "it's hard to see the boss").
    ///
    /// Not the whole ratio, which `bossLightScale` takes for the spot: on
    /// every light it would paint every pale boss the one grey of the
    /// line, sandstone and linen wrappings alike. Not the Vault's grade:
    /// 0.2 of a stop off the whole set darkens its floor, its props and the
    /// team for one figure (18-dungeon_battle-d's painting band already
    /// sits at 34), and leaves a pale boss in any other place to blow. Not
    /// the aura: sixteen motes a second rising from feet sunk below the rim
    /// are not what clips a fist. Run 234's arm patches taken back through
    /// the camera's curve (Reinhard to the 1.85 white point) and forward
    /// again at 0.76: the plateau falls from 240–245 to about 220–225, its
    /// red channel off the clip (254 to about 234), no pixel of either
    /// worst patch over 240 before the bloom (which only falls with them),
    /// and the lit stone's median from about 220 to 200 — still nearly
    /// twice the set beside it (110), the brightest thing in the upper frame.
    static func paintResponse(albedo: Double?) -> CGFloat {
        guard let albedo, albedo > paleAlbedo else { return 1 }
        let halfTheExcess: Double = (paleAlbedo / albedo).squareRoot()
        return CGFloat(max(0.5, halfTheExcess))
    }

    private static var albedoCache: [String: Double] = [:]

    /// The mean brightness of a figure's paint in LINEAR light, 0…1 — what
    /// a light multiplies — from its diffuse textures (`ModelLibrary`
    /// leaves them decoded as images) or colours, each read off a 32 × 32
    /// reduction the way `PaintingPalette` reads a painting and taken to
    /// linear per pixel before the average. Cached by asset: every boss of a
    /// kind wears the same texture. Nil when nothing on the figure is a
    /// picture or a colour.
    static func measurePaint(of model: SCNNode, key: String) -> Double? {
        if let cached = albedoCache[key] { return cached }
        var total = 0.0
        var count = 0.0
        model.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                let contents = material.diffuse.contents
                if let image = contents as? UIImage, let cg = image.cgImage,
                   let mean = meanLinearLuminance(of: cg) {
                    total += mean
                    count += 1
                } else if let contents, let mean = ModelLibrary.paintMean(of: contents as AnyObject) {
                    // A texture the loader handed over (run 252's experiment),
                    // measured from its pixels when it was made.
                    total += mean
                    count += 1
                } else if let colour = contents as? UIColor {
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                    if colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                        total += 0.2126 * linearLight(Double(red)) + 0.7152 * linearLight(Double(green))
                            + 0.0722 * linearLight(Double(blue))
                        count += 1
                    }
                }
            }
        }
        guard count > 0 else { return nil }
        let mean = total / count
        albedoCache[key] = mean
        return mean
    }

    /// A picture's mean luminance in linear light, off a 32 × 32 reduction
    /// averaged here: the picture is drawn at 256 and every 8 × 8 block
    /// averaged by hand, because Core Graphics' filter at a sixty-fourfold
    /// reduction is not guaranteed to average — a sampled 32 read the
    /// Jötunn's dark hide and pale ice a third brighter — while any filter
    /// at eightfold then the blocks give the calibration's own numbers
    /// (`paleAlbedo`) to the third decimal.
    static func meanLinearLuminance(of image: CGImage) -> Double? {
        let side = 256
        let block = 8
        let cells = side / block
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        let perBlock = Double(block * block) * 255
        var sum = 0.0
        for cellY in 0..<cells {
            for cellX in 0..<cells {
                var red = 0
                var green = 0
                var blue = 0
                for row in (cellY * block)..<(cellY * block + block) {
                    for column in (cellX * block)..<(cellX * block + block) {
                        let at = (row * side + column) * 4
                        red += Int(data[at])
                        green += Int(data[at + 1])
                        blue += Int(data[at + 2])
                    }
                }
                sum += 0.2126 * linearLight(Double(red) / perBlock)
                    + 0.7152 * linearLight(Double(green) / perBlock)
                    + 0.0722 * linearLight(Double(blue) / perBlock)
            }
        }
        return sum / Double(cells * cells)
    }

    /// sRGB to linear light, one channel, 0…1.
    private static func linearLight(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    // MARK: - The cast ring and the swing's trail

    /// The node a blade hangs from: the rig's weapon attach point when it has
    /// one, else the right hand bone. Nil for a rig with neither, and the
    /// trail is simply not drawn.
    private lazy var weaponNode: SCNNode? = {
        if let attach = spec.weaponAttachNode,
           let named = modelContainer.childNode(withName: attach, recursively: true) { return named }
        var found: SCNNode?
        modelContainer.enumerateHierarchy { node, stop in
            let name = (node.name ?? "").lowercased()
            if name.contains("hand"), name.contains("r"), !name.contains("l_"), !name.hasPrefix("left") {
                found = node
                stop.pointee = true
            }
        }
        return found
    }()

    /// A rune ring under the caster for the length of a cast: the summon
    /// dais's own ring in the element's colour, faded in as the clip begins
    /// and out as it ends. A spell now has a floor to stand on.
    func castRing(tint: UIColor, duration: TimeInterval, after delay: TimeInterval = 0) {
        let ring = StageBuilder.runeRing(radius: CGFloat(max(1.1, spec.height * 0.62)), tint: tint)
        ring.name = "cast_ring"
        ring.opacity = 0
        ring.position = SCNVector3(0, 0.03, 0)
        // Light throws no shadow (2026-09-24): an additive ring left in the
        // key's shadow pass lays a dark disc under its own glow, and a
        // battle figure throws none now (`attachGroundShadow`).
        ring.enumerateHierarchy { child, _ in child.castsShadow = false }
        addChildNode(ring)
        ring.runAction(.sequence([
            .wait(duration: delay),
            .fadeOpacity(to: 0.9, duration: 0.15),
            .wait(duration: max(0.2, duration - 0.5)),
            .fadeOut(duration: 0.35),
            .removeFromParentNode(),
        ]))
    }

    /// The blur a weapon leaves through a swing: a ribbon of the last dozen
    /// frames' blade positions, additive in the strike's colour, rebuilt
    /// every frame for the length of the clip and gone a beat after. The
    /// blade is taken to run a metre out along the hand bone, which is where
    /// a blade is; a rig with no hand draws nothing. The ribbon lives in the
    /// stage, not in the figure, so the trail stays where the swing was.
    ///
    /// Rebuilt on the MAIN thread, on a timer, as the flipbooks step their
    /// frames (run 239). It was an `SCNAction.customAction` that set the
    /// node's geometry sixty times a second on SceneKit's render thread, in
    /// the middle of the render loop's update, with a fade and a removal
    /// action after it: the one scene-graph change in a fight still made
    /// there, against the rule the shockwave's crash left (2026-09-15). Run
    /// 239's arena died on that thread a tenth of a second after the
    /// pipeline asserted on an element it should have dropped, at the
    /// moment Set's ultimate's trail — 2.4 s of sampling, the 0.12 s fade,
    /// three hit-stops — was being taken off the stage. The timer keeps the
    /// action's clock: it counts only while `scene` runs, so a hit-stop
    /// holds the ribbon as it holds the clip, and it reads the hand exactly
    /// as the action did.
    func swingTrail(tint: UIColor, duration: TimeInterval, after delay: TimeInterval = 0, in scene: SCNScene) {
        guard let hand = weaponNode, let stage = parent else { return }
        let trail = SCNNode()
        trail.name = "swing_trail"
        // A ribbon of light casts nothing (the cast ring's reason, above).
        trail.castsShadow = false
        let material = UnitNode.trailMaterial(tint: tint)
        stage.addChildNode(trail)
        var samples: [(root: SCNVector3, tip: SCNVector3)] = []
        let keep = 12
        let reach: Float = min(1.1, spec.height * 0.5)
        let fade: TimeInterval = 0.12
        let owner = spec.assetName
        // Seconds of scene time since the trail was asked for.
        var clock: TimeInterval = 0
        var last = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak trail, weak hand, weak scene] timer in
            let now = CACurrentMediaTime()
            let step = now - last
            last = now
            guard let trail, trail.parent != nil else { timer.invalidate(); return }
            guard let hand, let scene else {
                timer.invalidate()
                trail.removeFromParentNode()
                return
            }
            // A hit-stop freezes the clip and, as the action did, the ribbon.
            guard !scene.isPaused else { return }
            clock += step
            guard clock >= delay else { return }
            let into = clock - delay
            if into < duration {
                let root = hand.worldPosition
                let tip = hand.convertPosition(SCNVector3(0, reach, 0), to: nil)
                samples.append((root, tip))
                if samples.count > keep { samples.removeFirst() }
                trail.geometry = UnitNode.ribbon(samples, material: material)
            } else if into < duration + fade {
                trail.opacity = CGFloat(max(0, 1 - (into - duration) / fade))
            } else {
                timer.invalidate()
                trail.removeFromParentNode()
                VFXLibrary.trace("swing trail of \(owner) taken off")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The ribbon's material: white under the strike's colour, added to the
    /// frame and written to neither the depth nor the alpha.
    private static func trailMaterial(tint: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.emission.contents = tint
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.isDoubleSided = true
        material.colorBufferWriteMask = [.red, .green, .blue]
        return material
    }

    /// The cast ring and a swing's ribbon, built as `castRing` and
    /// `swingTrail` build them, for the pre-draw under the stage card
    /// (Docs/FEEL.md W2.24, `VFXLibrary.predraw`): the ring's additive plane
    /// and the ribbon's vertex-coloured strip are pipelines of their own,
    /// compiled there rather than on the first ultimate's wind-up. The
    /// caller places them; neither casts a shadow.
    static func predrawPieces(tint: UIColor) -> [SCNNode] {
        let ring = StageBuilder.runeRing(radius: 1.2, tint: tint)
        ring.name = "predraw_cast_ring"
        ring.position = SCNVector3(0, 0.03, 0)
        ring.enumerateHierarchy { child, _ in child.castsShadow = false }
        let samples: [(root: SCNVector3, tip: SCNVector3)] = [
            (root: SCNVector3(-0.5, 1.0, 0), tip: SCNVector3(-0.4, 2.0, 0)),
            (root: SCNVector3(0, 1.1, 0), tip: SCNVector3(0.1, 2.1, 0)),
            (root: SCNVector3(0.5, 1.0, 0), tip: SCNVector3(0.6, 2.0, 0)),
        ]
        let trail = SCNNode(geometry: ribbon(samples, material: trailMaterial(tint: tint)))
        trail.name = "predraw_swing_trail"
        trail.castsShadow = false
        return [ring, trail]
    }

    /// A triangle strip through the samples, oldest first, darkening toward
    /// the tail so the additive ribbon fades along its length.
    private static func ribbon(_ samples: [(root: SCNVector3, tip: SCNVector3)], material: SCNMaterial) -> SCNGeometry? {
        guard samples.count >= 2 else { return nil }
        var vertices: [SCNVector3] = []
        var colors: [SCNVector4] = []
        var indices: [Int32] = []
        for (index, sample) in samples.enumerated() {
            let age = Float(index) / Float(samples.count - 1)   // 0 oldest, 1 newest
            let strength = age * age
            vertices.append(sample.root)
            vertices.append(sample.tip)
            colors.append(SCNVector4(strength * 0.35, strength * 0.35, strength * 0.35, 1))
            colors.append(SCNVector4(strength, strength, strength, 1))
            indices.append(Int32(index * 2))
            indices.append(Int32(index * 2 + 1))
        }
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<SCNVector4>.stride)
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count,
                                            usesFloatComponents: true, componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<SCNVector4>.stride)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangleStrip)
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        geometry.firstMaterial = material
        return geometry
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

    /// A tile for the unit plate over a fighter's head, drawn at the size it
    /// is shown (`UnitPlate.tile`, 16 points): the effect's glyph on its
    /// colour, and the turns left as an 11-point Manrope digit on a dark
    /// chip riding the tile's top-right corner. The 72-point picture above
    /// shrunk to 12 points put the turns at about 3 (run 221, under the
    /// 11-point floor), so the plate's tile is its own drawing. `anchor` is
    /// where the tile's centre sits in the picture, as SpriteKit counts it.
    struct PlateTile {
        let image: UIImage
        let anchor: CGPoint
    }

    private static var plateCache: [String: PlateTile] = [:]

    static func plateTile(kind: StatusKind, turns: Int) -> PlateTile? {
        let key = "\(kind.rawValue)|\(turns)"
        if let cached = plateCache[key] { return cached }

        let tile: CGFloat = 16
        let chipHeight: CGFloat = 12
        let font = UIFont(name: Theme.numberFace, size: Theme.bodyFloor)
            ?? UIFont.systemFont(ofSize: Theme.bodyFloor, weight: .bold)
        let digits = NSAttributedString(string: "\(turns)", attributes: [
            .font: font,
            .foregroundColor: UIColor.white,
        ])
        let chipWidth = turns > 0 ? max(chipHeight, ceil(digits.size().width) + 5) : 0
        // The chip is centred on the tile's top-right corner, so it hangs
        // half its height over the top and half its width past the side.
        let over = chipHeight / 2
        let size = CGSize(width: tile + chipWidth / 2, height: tile + over)
        let tileRect = CGRect(x: 0, y: over, width: tile, height: tile)
        let fill = kind.isBuff ? UIColor(hex: "#2E8FBF") ?? .systemBlue : UIColor(hex: "#B8403A") ?? .systemRed
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let square = UIBezierPath(roundedRect: tileRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3.5)
            fill.setFill()
            square.fill()
            UIColor.white.withAlphaComponent(0.85).setStroke()
            square.lineWidth = 1
            square.stroke()

            let configuration = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            if let symbol = UIImage(systemName: kind.glyph, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                // A shade down and left of centre, clear of the chip.
                let box: CGFloat = 9.5
                let scale = min(box / max(1, symbol.size.width), box / max(1, symbol.size.height))
                let drawn = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                symbol.draw(in: CGRect(
                    x: tileRect.midX - drawn.width / 2 - 1, y: tileRect.midY - drawn.height / 2 + 1,
                    width: drawn.width, height: drawn.height
                ))
            }

            if turns > 0 {
                let chip = CGRect(x: tile - chipWidth / 2, y: 0, width: chipWidth, height: chipHeight)
                let pill = UIBezierPath(roundedRect: chip.insetBy(dx: 0.25, dy: 0.25), cornerRadius: chipHeight / 2)
                (UIColor(hex: "#130E0A") ?? .black).withAlphaComponent(0.94).setFill()
                pill.fill()
                UIColor.white.withAlphaComponent(0.4).setStroke()
                pill.lineWidth = 0.75
                pill.stroke()
                // The digit's cap height centred in the chip.
                let width = digits.size().width
                let baseline = chip.midY + font.capHeight / 2
                digits.draw(at: CGPoint(x: chip.midX - width / 2, y: baseline - font.ascender))
            }
        }
        // SpriteKit counts from the bottom left.
        let result = PlateTile(
            image: image,
            anchor: CGPoint(x: tileRect.midX / size.width, y: 1 - tileRect.midY / size.height)
        )
        if plateCache.count > 200 { plateCache.removeAll() }
        plateCache[key] = result
        return result
    }
}

/// The advantage arrow's pictures, one per matchup, drawn once: a green
/// triangle pointing up, a yellow double chevron pointing both ways, a red
/// triangle pointing down, each with a dark edge and a soft shadow so it
/// reads over any floor. Even was a plain yellow disc until run 221, which
/// read as a coin rather than as "neither up nor down".
enum MatchupIconRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(for matchup: Element.Matchup) -> UIImage {
        let key = "\(matchup)"
        if let hit = cache[key] { return hit }
        let size = CGSize(width: 96, height: 96)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let canvas = context.cgContext
            let colour: UIColor
            let path = UIBezierPath()
            switch matchup {
            case .advantage:
                colour = UIColor(hex: "#4CD964") ?? .green
                path.move(to: CGPoint(x: 48, y: 12))
                path.addLine(to: CGPoint(x: 86, y: 72))
                path.addLine(to: CGPoint(x: 10, y: 72))
                path.close()
            case .disadvantage:
                colour = UIColor(hex: "#FF453A") ?? .red
                path.move(to: CGPoint(x: 48, y: 84))
                path.addLine(to: CGPoint(x: 86, y: 24))
                path.addLine(to: CGPoint(x: 10, y: 24))
                path.close()
            case .neutral:
                // A chevron each way on one shaft, as wide as the triangles
                // and a little shorter, so the three weigh the same.
                colour = UIColor(hex: "#F2C94C") ?? .yellow
                path.move(to: CGPoint(x: 8, y: 48))
                path.addLine(to: CGPoint(x: 38, y: 18))
                path.addLine(to: CGPoint(x: 38, y: 35))
                path.addLine(to: CGPoint(x: 58, y: 35))
                path.addLine(to: CGPoint(x: 58, y: 18))
                path.addLine(to: CGPoint(x: 88, y: 48))
                path.addLine(to: CGPoint(x: 58, y: 78))
                path.addLine(to: CGPoint(x: 58, y: 61))
                path.addLine(to: CGPoint(x: 38, y: 61))
                path.addLine(to: CGPoint(x: 38, y: 78))
                path.close()
            }
            canvas.setShadow(offset: .zero, blur: 7, color: UIColor.black.withAlphaComponent(0.85).cgColor)
            canvas.setFillColor(colour.cgColor)
            path.fill()
            canvas.setShadow(offset: .zero, blur: 0, color: nil)
            canvas.setStrokeColor(UIColor.black.withAlphaComponent(0.85).cgColor)
            path.lineWidth = 5
            path.stroke()
        }
        cache[key] = image
        return image
    }
}

/// The pace a running clip is kept to, as a share of the pace it began at
/// (`UnitNode.retimeRunningClip`): written on the main thread as the pace
/// changes, read by the clip's ending on SceneKit's render thread, so only
/// under the lock.
final class ClipPace {
    private let lock = NSLock()
    private var ratio: Double = 1

    func set(_ value: Double) {
        lock.lock()
        ratio = value
        lock.unlock()
    }

    var value: Double {
        lock.lock()
        defer { lock.unlock() }
        return ratio
    }
}

/// How far a one-shot's ending clock has counted (`UnitNode.scheduleClipEnd`).
/// The render thread's alone: the clock's block is its only reader and writer.
final class ClipProgress {
    var done: Double = 0
    var last: Double = 0
    var fired = false
}
