import Foundation
import SceneKit
import UIKit

// MARK: - What a cast draws (Docs/PLAN.md *Skills that look like themselves*, 2026-09-25)
//
// The owner, of the fight: "If a skill attacks 3 times, the character might
// hit once, but 3 hits occur. Theres no magic animations, only your generic
// sphere looking hits. I want more custom, high end, REAL GAME FEEL." A cast
// drew ONE burst on the frame of its first contact — two puffs of sprite on
// the victim, a slash arc for a melee blow, one sprite from a caster —
// whatever the skill was, and nothing on screen said its element or its
// shape. This is the grammar the plan chose instead, composed per cast from
// what the cast is:
//
// - the WIND-UP: the element's circle under a spell, a rite or an ultimate;
//   an ultimate's aura (its gathering motes until the aura is painted); a
//   blade's trail through a melee clip;
// - the DELIVERY, per hit: a slash in the element on each melee victim,
//   turned ±25° from one strike to the next; an orb, or an arrow for an
//   archer, thrown at each victim to ARRIVE on the hit's contact;
// - the IMPACT, per hit and per victim: the element's burst, its sparks and
//   one light under the key, and on a heavy blow's last hit a ring on the
//   ground; a flurry's early hits at 0.7 of the size and quieter;
// - the ROW, once, on an area cast's first hit (run 224's rule: one effect
//   over a line, never a full-strength sheet per victim): the element's
//   pillars rising under each victim, or its strikes falling on each, 60 ms
//   apart, and every victim its own quiet impact;
// - the RITE: a release lifting off its caster on its contact, and each
//   ally's own column on its own event (`BattleSceneController.present`);
// - the ULTIMATE: the family's SIGNATURE landing on its first hit.
//
// Every piece is a painted sheet once its painting has shipped
// (`tools/skills/fx_sheets.tsv`: painted by tools/skill_fx.py, keyed and
// shipped by tools/vfx_sheets.py) and the effect the fight always drew until
// then, so the build is right before a single sheet ships. A named effect
// the kits already carry for a blow (`thunderbolt`, `heart_weigh`,
// `wrath_of_the_eye`, …) keeps its look as the delivery and the impact —
// per hit now. Everything is timed as SCENE actions under one key on the
// scene's root (`actionKey`), so a hit's freeze holds it with the clip it is
// timed against, a new cast cancels whatever a stale one still had to draw,
// and a skip takes it all (`cancel`). Every block only hops to the main
// thread, where the pieces are made (run 239's rule for anything that
// carries particles).

/// A cast as `SkillFX` draws it, handed over by the battle's scene the
/// moment it draws the cast (`BattleSceneController.performCast`): who casts,
/// what the cast is, and when each of its hits lands on whom — the times
/// read off the clip that really plays (`ClipTimings`), the victims off the
/// engine's own events, read ahead in the queue.
struct CastFX {
    /// The unit casting.
    let caster: UnitNode
    /// Its element: every piece's colour, and the sheets it draws from.
    let element: Element
    /// The clip that really plays for the skill (`ModelLibrary.resolvedClip`).
    let clip: AnimationClip
    /// The skill's named effect; `impact_generic`, or an element's
    /// `impact_*`, names none.
    let vfx: String
    /// The family (`ModelSpec.assetName`): whose signature an ultimate plays.
    let family: String
    /// The third skill.
    let isUltimate: Bool
    /// No damage: a heal, a buff, a shield, a cleanse.
    let isRite: Bool
    /// It struck every enemy at once.
    let isArea: Bool
    /// The caster stands and throws (`!ModelSpec.melee`).
    let ranged: Bool
    /// The caster shoots arrows (`SkillFX.archers`).
    let archer: Bool
    /// Authored seconds from the cast's start to its clip's start: a melee
    /// caster's leap.
    let walkUp: TimeInterval
    /// Each hit, in order: when it lands, in authored seconds from the
    /// cast's start, and whom it strikes (a victim a random volley strikes
    /// twice is named twice). A rite's release is its one hit, on the cast's
    /// own targets.
    let hits: [(time: TimeInterval, victims: [UUID])]
    /// Authored seconds from the cast's start to the end of its clip.
    let clipEnd: TimeInterval
}

/// An ultimate's signature look (Docs/PLAN.md *Skills that look like
/// themselves*): one per family, chosen from its myth
/// (`SkillFX.signatures`), each built from a painted sheet of its own with
/// the fight's older sheets as its fallbacks. The raw values are the ones
/// the sentence lane's table spells (tools/skills/signature_fx.json).
enum SignatureFX: String {
    case meteor, lightning, tidal, tornado, holyBlade
    case maw, spikes, bladestorm, spirit, sunburst
    case script, claw, blood, volley, eruption

    /// The painted sheet the look is built from (`vfx_<sheet>_sheet.png`);
    /// nil for the eruption, which is the element's own pillars and ring.
    var sheet: String? {
        switch self {
        case .meteor: return "meteor"
        case .lightning: return "lightning"
        case .tidal: return "tidal"
        case .tornado: return "tornado"
        case .holyBlade: return "holyblade"
        case .maw: return "maw"
        case .spikes: return "spikes"
        case .bladestorm: return "bladestorm"
        case .spirit: return "spirit"
        case .sunburst: return "sunburst"
        case .script: return "script"
        case .claw: return "claw"
        case .blood: return "blood"
        case .volley: return "volley"
        case .eruption: return nil
        }
    }

    /// The element a look belongs to, when its painting is of one: a meteor
    /// is fire and a tidal wave is water, so only a form of that element
    /// plays it (`SkillFX.signature(for:element:)`). The rest are neutral,
    /// painted as they are or tinted by the caster's element.
    var affinity: Element? {
        switch self {
        case .meteor: return .ember
        case .tidal: return .tide
        case .tornado: return .gale
        case .holyBlade: return .radiance
        case .maw: return .umbra
        case .lightning, .spikes, .bladestorm, .spirit, .sunburst, .script, .claw, .blood, .volley, .eruption:
            return nil
        }
    }

    /// Whether, over a whole line, the look lands on EACH victim — a meteor
    /// on every one, 60 ms apart and each drawn quietly — or once over the
    /// line's middle, by the row's rules (a wave, a storm, a field of
    /// spikes).
    var fallsOnEach: Bool {
        switch self {
        case .meteor, .holyBlade, .maw, .spirit, .claw, .blood, .volley, .eruption:
            return true
        case .lightning, .sunburst, .script, .tidal, .tornado, .spikes, .bladestorm:
            return false
        }
    }

    /// Seconds of its painting before the look LANDS — the meteor falling,
    /// the sword descending, the pillar climbing out of the ground — so it
    /// is started that far ahead of its hit and lands on the number. The
    /// fight's older looks (the bolt, the sunburst, the script, the claw,
    /// the crimson X) land as they begin.
    var landsAhead: TimeInterval {
        switch self {
        case .meteor, .tidal: return 0.35
        case .holyBlade, .volley: return 0.3
        case .maw, .spirit, .eruption: return 0.25
        case .spikes: return 0.2
        case .tornado, .bladestorm: return 0.15
        case .lightning, .sunburst, .script, .claw, .blood: return 0
        }
    }
}

/// Draws a cast (`play`) and takes back what a cast still had to draw
/// (`cancel`). Main thread, as every drawing in the fight is; not bound to
/// the main actor, as nothing in the render layer is, so the battle's scene
/// calls it as it calls `VFXLibrary`.
enum SkillFX {

    /// The key every piece of a cast's script runs under on the scene's root.
    static let actionKey = "cast_fx"

    /// The families that shoot arrows: an arrow per hit where any other
    /// ranged caster throws its element's orb. (Ra and the Azure Dragon share
    /// the marksman's kit and cast light and lightning instead.)
    static let archers: Set<String> = [
        "artemis", "atalanta", "diana", "medjay", "ullr", "skadi",
        "artemis_awakened", "atalanta_awakened", "diana_awakened", "medjay_awakened", "ullr_awakened",
        "skadi_awakened",
    ]

    /// Each family's signature, from its myth: the sentence lane's table
    /// (tools/skills/signature_fx.json, forty-eight families), mirrored here
    /// by hand — change a row in both. A family missing from it erupts in
    /// its element (`.eruption`); the healers and oracles are missing on
    /// purpose, since a rite has no signature (its look is its release and
    /// each ally's own column). The five gods' are their own named effects
    /// of 2026-09-15 (Zeus's lightning, Anubis's and Thoth's script,
    /// Sekhmet's sunburst, Ares's crimson X), which is why `play` leaves a
    /// signature out when the skill's named effect already paints it.
    static let signatures: [String: SignatureFX] = [
        // Egypt
        "horus": .holyBlade, "set": .tornado, "bastet": .claw, "sobek": .tidal, "ra": .sunburst,
        "khnum": .spikes, "nephthys": .maw, "serqet": .claw, "taweret": .tidal, "anhur": .spirit,
        "sekhmet": .sunburst, "thoth": .script, "anubis": .script,
        // Greece
        "zeus": .lightning, "ares": .blood, "athena": .holyBlade, "poseidon": .tidal, "hades": .maw,
        "artemis": .volley, "hephaestus": .meteor, "dionysus": .spikes, "nike": .holyBlade,
        "achilles": .bladestorm, "heracles": .spikes, "perseus": .holyBlade,
        // The Norse realms
        "thor": .lightning, "loki": .bladestorm, "tyr": .spirit, "heimdall": .holyBlade, "hel": .maw,
        "skadi": .volley, "surtr": .meteor, "njord": .tidal, "sif": .bladestorm, "ullr": .volley,
        "vidar": .spikes, "fenrir": .spirit,
        // Rome
        "mars": .bladestorm, "neptune": .tidal, "pluto": .maw, "diana": .volley, "mercury": .tornado,
        "bellona": .meteor,
        // The Jade Court
        "sun_wukong": .spikes, "nezha": .meteor, "guan_yu": .bladestorm, "azure_dragon": .lightning,
        "dragon_king": .tidal,
    ]

    /// The look an ultimate of `family` plays in `element`: its signature,
    /// and a look with an element of its own only by a form of that element
    /// (the table's note: "a tide Surtr is never a fire meteor") — any other
    /// form, and a family with no signature, erupts in its own element
    /// (`.eruption`: the element's strike from the sky for ember and
    /// radiance, its pillar out of the ground for the rest, and its ring).
    static func signature(for family: String, element: Element) -> SignatureFX {
        guard let look = signatures[family] else { return .eruption }
        if let own = look.affinity, own != element { return .eruption }
        return look
    }

    // MARK: - The timing

    /// How far ahead of a blow its swing is heard, in seconds of the wall
    /// clock: a sound plays at its own speed whatever the fight's, and the
    /// whoosh peaks about 85 ms into its file, so started this long before
    /// the blow it peaks a breath ahead of it at every speed. Beaten with the
    /// fight's, it began 47 ms before the blow at ×3 and peaked after it.
    /// `tools/sfx.py` `SWING_LEAD`, which sums the cast at it.
    static let swingLead: TimeInterval = 0.14
    /// How far ahead of the queue's number a hit's impact is drawn, in
    /// authored seconds: two frames, so the burst is already on the frame
    /// the hit's freeze holds, whichever of the two reaches the main thread
    /// first.
    static let impactLead: TimeInterval = 0.03
    /// Seconds of a pillar's or a strike's painting before it lands: started
    /// that far ahead, it erupts on the number.
    static let risesAhead: TimeInterval = 0.25
    /// Authored seconds an arrow and an orb take to cross the field, and
    /// the shortest either flies on the wall clock, so ×3 still shows them.
    /// Short on purpose: a caster's contact is its RELEASE, and the battle
    /// presents the hit this long after it (`flight`), so the shot leaves
    /// the hand as the hand opens and lands on the number.
    static let arrowFlight: TimeInterval = 0.2
    static let orbFlight: TimeInterval = 0.28

    /// The authored seconds a cast's shot is in the air, or 0 when it throws
    /// none (a melee blow, a boss, an area cast, an ultimate): the battle
    /// presents each hit this long after the clip's contact, which is the
    /// RELEASE, and `play` launches the shot on the release so it lands on
    /// the hit. One function for both, so the two cannot drift.
    static func flight(family: String, ranged: Bool, isBoss: Bool, isArea: Bool, isUltimate: Bool) -> TimeInterval {
        guard ranged, !isBoss, !isArea, !isUltimate else { return 0 }
        return archers.contains(family) ? arrowFlight : orbFlight
    }
    static let shortestFlight: TimeInterval = 0.12
    /// The shortest wind-up worth an ultimate's gathering swell.
    static let chargeWorth: TimeInterval = 0.5
    /// Seconds the first of a volley's arrows drawn in code (the signature
    /// until `vfx_volley_sheet` ships) takes to fall from the sky; each one
    /// after it falls 50 ms longer. The volley is started this far ahead of
    /// its hit, so its first arrow lands on the number (`lead(of:element:)`).
    static let volleyFlight: TimeInterval = 0.28

    // MARK: - Playing a cast

    /// Schedules everything `cast` draws as SCENE actions under `actionKey`
    /// on the scene's root, so a freeze holds them with the clip and a new
    /// cast cancels a stale one; the wind-up's pieces, which keep their own
    /// clocks, start at once. `node` finds a victim when its hit fires, so
    /// no piece lands where a victim used to stand; `beat` turns authored
    /// seconds into the scene's at the pace of the moment.
    static func play(_ cast: CastFX, in scene: SCNScene, node: @escaping (UUID) -> UnitNode?,
                     beat: @escaping (TimeInterval) -> TimeInterval) {
        cancel(in: scene)
        let caster = cast.caster
        // ×3 draws a flurry's early hits silent (Docs/FEEL.md W1.1).
        let pace: Double = 1 / max(0.001, beat(1))
        let fast = Juice.isFast(pace)
        let colours = CastColours(cast)
        windUp(cast, colours: colours, in: scene, beat: beat)

        var steps: [SCNAction] = []
        func at(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
            steps.append(step(after: seconds, work))
        }
        let clipStart: TimeInterval = beat(cast.walkUp)

        // An ultimate's gathering swell, a rite's as well as a blow's,
        // started so that it crests a breath before the first blow and has
        // let go as the blow lands (`SkillSound.chargeLead`, the file's own
        // shape, at which `tools/sfx.py` sums the cast). A sound plays at its
        // own speed, so the lead is the wall clock's and never beaten.
        // Started with the wind-up, as it was, the swell had died a second
        // before the blow of a 3.4 s ultimate at ×1. A wind-up too short for
        // the swell to mean anything (`chargeWorth`) has none.
        if cast.isUltimate, let first = cast.hits.first {
            let blow: TimeInterval = beat(first.time)
            if blow >= chargeWorth {
                at(max(0, blow - SkillSound.chargeLead)) {
                    AudioLibrary.shared.play(.charge, volume: 0.7)
                }
            }
        }

        // A RITE: a release lifting off its caster on its contact, and a
        // named look of its own over its targets (the golden script of a
        // decree, Ma'at's shield); its heals, buffs and shields are drawn on
        // each ally by their own events.
        if cast.isRite {
            guard let release = cast.hits.first else { return }
            let targets = release.victims
            let named = riteLook(cast.vfx)
            at(beat(release.time)) { [weak scene] in
                guard let scene else { return }
                SkillFX.release(from: cast.caster, element: cast.element, colours: colours, in: scene)
                if let named {
                    let reached: [UnitNode] = targets.compactMap(node)
                    if !reached.isEmpty {
                        let scale = SkillFX.meanScale(of: reached)
                        VFXLibrary.spawnArea(named, over: reached.map { $0.chestWorldPosition }, in: scene,
                                             tint: colours.aura, scale: scale)
                    }
                }
                AudioLibrary.shared.play(.rite, volume: 0.8)
            }
            scene.rootNode.runAction(.group(steps), forKey: actionKey)
            return
        }

        let count = cast.hits.count
        let named = blowLook(cast.vfx)
        // The signature, unless the named effect already paints it (the five
        // gods': Zeus's Keraunos IS his lightning).
        var signed: SignatureFX?
        if cast.isUltimate {
            let look = signature(for: cast.family, element: cast.element)
            let painted: String? = named.flatMap { namedSheet($0) }
            if look.sheet == nil || look.sheet != painted { signed = look }
        }
        // Shots fly for a caster's own blows; an ultimate lands through its
        // signature and an area cast through its row, and a boss has no
        // floor to throw across (it strikes from where it towers).
        let shoots = flight(family: cast.family, ranged: cast.ranged, isBoss: caster.isBoss, isArea: cast.isArea,
                            isUltimate: cast.isUltimate) > 0

        for (index, hit) in cast.hits.enumerated() {
            let early = count > 1 && index < count - 1
            let hushed = early && fast
            let contact: TimeInterval = beat(hit.time)
            let ids: [UUID] = hit.victims

            // The swing, heard as each blow comes (its lead the wall
            // clock's: `swingLead`).
            if !cast.ranged, !hushed {
                let heavy = !early && (cast.isUltimate || cast.isArea || count > 1 || cast.clip == .attackHeavy)
                at(max(clipStart, contact - swingLead)) {
                    AudioLibrary.shared.play(.swing(heavy: heavy), volume: early ? 0.5 : 0.8)
                }
            }

            // The shots, thrown to land on the contact.
            if shoots {
                let flight: TimeInterval = max(shortestFlight, beat(cast.archer ? arrowFlight : orbFlight))
                let launch: TimeInterval = max(clipStart, contact - flight)
                let airborne: TimeInterval = max(0.05, contact - launch)
                for victimID in ids {
                    at(launch) { [weak scene] in
                        guard let scene, let victim = node(victimID) else { return }
                        SkillFX.shoot(cast, at: victim, flight: airborne, early: early, sounded: !hushed,
                                      colours: colours, in: scene)
                    }
                }
            }

            // The row's own effect, once, on an area cast's first hit: the
            // element's pillars or strikes, one victim after the next. Not
            // under a named effect, which is the row's look, nor under a
            // signature, which is the ultimate's.
            if cast.isArea, index == 0, named == nil, signed == nil {
                let ahead: TimeInterval = VFXLibrary.hasSheet(risingSheet(cast.element)) ? risesAhead : 0
                let start: TimeInterval = max(clipStart, contact - ahead)
                // Each victim's piece `victimStep` after the last, as its
                // number is (`CastTimeline`), beaten to the fight's speed.
                let stagger: TimeInterval = beat(CastTimeline.victimStep)
                for (order, victimID) in ids.enumerated() {
                    at(start + stagger * Double(order)) { [weak scene] in
                        guard let scene, let victim = node(victimID) else { return }
                        SkillFX.rise(cast.element, under: victim, colours: colours, in: scene)
                    }
                }
            }

            // The signature, landing on the first hit.
            if index == 0, let look = signed {
                let ahead: TimeInterval = lead(of: look, element: cast.element)
                let start: TimeInterval = max(clipStart, contact - ahead)
                let line = cast.isArea && ids.count > 1
                if line, look.fallsOnEach {
                    let stagger: TimeInterval = beat(CastTimeline.victimStep)
                    for (order, victimID) in ids.enumerated() {
                        at(start + stagger * Double(order)) { [weak scene] in
                            guard let scene, let victim = node(victimID) else { return }
                            SkillFX.sign(look, on: [victim], reach: .member, cast: cast, colours: colours, in: scene)
                        }
                    }
                    // One light for the line, as a line's own effects bring.
                    at(contact) { [weak scene] in
                        guard let scene else { return }
                        let reached: [UnitNode] = ids.compactMap(node)
                        SkillFX.rowLight(over: reached, tint: colours.aura, in: scene)
                    }
                } else {
                    at(start) { [weak scene] in
                        guard let scene else { return }
                        let reached: [UnitNode] = ids.compactMap(node)
                        guard let first = reached.first else { return }
                        if line {
                            SkillFX.sign(look, on: reached, reach: .row(span: SkillFX.span(of: reached)), cast: cast,
                                         colours: colours, in: scene)
                        } else {
                            SkillFX.sign(look, on: [first], reach: .single, cast: cast, colours: colours, in: scene)
                        }
                    }
                }
            }

            // The impact, on the contact.
            let signedHere: Bool = index == 0 && signed != nil
            at(max(0, contact - beat(impactLead))) { [weak scene] in
                guard let scene else { return }
                let reached: [UnitNode] = ids.compactMap(node)
                SkillFX.land(cast, hit: index, on: reached, named: named, signedHere: signedHere, hushed: hushed,
                             colours: colours, in: scene)
            }
        }
        guard !steps.isEmpty else { return }
        scene.rootNode.runAction(.group(steps), forKey: actionKey)
    }

    /// Takes back everything a cast still had to draw: a new cast's, a
    /// skip's, a forfeit's and a new run's. What is already on the field
    /// plays out and retires itself.
    static func cancel(in scene: SCNScene) {
        scriptSerial &+= 1
        scene.rootNode.removeAction(forKey: actionKey)
    }

    /// Which script the pieces waiting on the main thread belong to: moved
    /// on by every `cancel` (and so by every `play`, which cancels first).
    /// Taking the action off stops every wait still running, but a piece
    /// whose block SceneKit had just run on its render thread has its hop
    /// to the main thread already queued — behind a skip that is running
    /// there, say — and would draw its burst over the field the skip had
    /// jumped to, or into the next run's stage. Such a piece finds the
    /// serial moved on and draws nothing. Main thread.
    private static var scriptSerial = 0

    /// One piece of a cast's script: `work` on the main thread `seconds` of
    /// scene time from now, unless the script has been taken back by then.
    /// SceneKit runs an action's block on its render thread, so the block
    /// only hops.
    private static func step(after seconds: TimeInterval, _ work: @escaping () -> Void) -> SCNAction {
        let serial = scriptSerial
        return .sequence([
            .wait(duration: max(0, seconds)),
            SCNAction.run { _ in
                DispatchQueue.main.async {
                    guard SkillFX.scriptSerial == serial else { return }
                    work()
                }
            },
        ])
    }

    // MARK: - The wind-up

    /// What a cast stands on and gathers before it lands, started at once:
    /// the element's painted circle (the dais's rune ring until it ships)
    /// under a spell, a rite or an ultimate for the length of its clip; an
    /// ultimate's aura round its caster until the first contact (its
    /// gathering motes until the aura ships); and a blade's trail through a
    /// melee clip — in steel, in the element for an ultimate. The swell of
    /// an ultimate's charge is timed to its blow instead (`play`).
    private static func windUp(_ cast: CastFX, colours: CastColours, in scene: SCNScene,
                               beat: (TimeInterval) -> TimeInterval) {
        let caster = cast.caster
        let clipStart: TimeInterval = beat(cast.walkUp)
        let clipLength: TimeInterval = beat(max(0.3, cast.clipEnd - cast.walkUp))
        let firstHit: TimeInterval = beat(cast.hits.first?.time ?? cast.clipEnd)
        let spell = cast.isRite || cast.isUltimate || (cast.ranged && !cast.archer && cast.clip != .attackBasic)
        if spell {
            let radius = CGFloat(max(1.1, caster.spec.height * 0.62))
            if !VFXLibrary.castCircle(under: caster, element: cast.element, tint: colours.element, radius: radius,
                                      duration: clipLength, after: clipStart) {
                caster.castRing(tint: colours.element, duration: clipLength, after: clipStart)
            }
        }
        if cast.isUltimate {
            let gather: TimeInterval = max(0.2, firstHit)
            let tall = CGFloat(min(caster.spec.height, 2.6)) * 1.6
            if !VFXLibrary.loopingSheet("\(cast.element.rawValue)_aura", feet: caster.position, behind: 0.45, in: scene,
                                        tint: colours.paint, size: tall, duration: gather + 0.15, cycle: 0.9) {
                VFXLibrary.charge(on: caster, tint: colours.element, duration: gather,
                                  scale: BattleSceneController.effectScale(for: caster))
            }
        }
        if !cast.ranged, !cast.isRite, !caster.isBoss {
            let steel = UIColor(hex: "#D9E4F2") ?? .white
            caster.swingTrail(tint: cast.isUltimate ? colours.element : steel, duration: clipLength,
                              after: clipStart, in: scene)
        }
    }

    // MARK: - A hit

    /// Everything one hit draws on its victims as it lands: a named effect
    /// in its own look, or the element's grammar — a melee victim's slash
    /// and every victim's burst, drawn quietly (off white, no light each)
    /// when the hit strikes several and one light for the line — then a
    /// ring under a heavy blow's last hit, and the hit's sounds. `signedHere`
    /// is the ultimate's first hit, whose signature brings the light.
    private static func land(_ cast: CastFX, hit index: Int, on victims: [UnitNode], named: String?,
                             signedHere: Bool, hushed: Bool, colours: CastColours, in scene: SCNScene) {
        let count = cast.hits.count
        let early = count > 1 && index < count - 1
        let last = index == count - 1
        let size: Float = early ? 0.7 : 1.0
        let melee = !cast.ranged
        if !victims.isEmpty {
            let crowd = victims.count > 1
            let reach: VFXLibrary.Reach = crowd ? .member : .single
            // The ground breaks under a heavy blow's last hit: the heavy blow
            // itself, a melee flurry's finisher, an ultimate's, a line's.
            let ringed = last && (cast.isUltimate || cast.isArea || (melee && count > 1)
                                  || (count == 1 && cast.clip == .attackHeavy))
            if let named {
                // A named effect keeps its look, per hit now: once over a line
                // by the row's rules (`spawnArea`), and a melee blow's slash
                // across a single victim.
                if crowd {
                    VFXLibrary.spawnArea(named, over: victims.map { $0.chestWorldPosition }, in: scene,
                                         tint: colours.aura, scale: meanScale(of: victims) * size)
                } else if let victim = victims.first {
                    let scale = BattleSceneController.effectScale(for: victim) * size
                    VFXLibrary.spawn(named, at: victim.chestWorldPosition, in: scene, tint: colours.aura, scale: scale)
                    if melee {
                        slash(on: victim, turn: index, heavy: ringed, reach: .single, scale: scale, element: cast.element,
                              colours: colours, in: scene)
                    }
                }
            } else {
                for victim in victims {
                    let scale = BattleSceneController.effectScale(for: victim) * size
                    if melee {
                        slash(on: victim, turn: index, heavy: ringed, reach: reach, scale: scale, element: cast.element,
                              colours: colours, in: scene)
                    }
                    burst(on: victim, element: cast.element, reach: reach, lit: !crowd && !signedHere, scale: scale,
                          colours: colours, in: scene)
                }
                if crowd, !signedHere { rowLight(over: victims, tint: colours.aura, in: scene) }
            }
            if ringed {
                if crowd {
                    ring(under: middle(of: victims), element: cast.element, reach: .row(span: span(of: victims)),
                         scale: meanScale(of: victims), colours: colours, in: scene)
                } else if let victim = victims.first {
                    ring(under: victim.position, element: cast.element, reach: .single,
                         scale: BattleSceneController.effectScale(for: victim), colours: colours, in: scene)
                }
            }
        }
        // The ultimate's boom lands on its first hit, whatever it struck.
        if cast.isUltimate, index == 0 { AudioLibrary.shared.play(.boom(cast.element), volume: 0.9) }
        guard !hushed else { return }
        let loud: Float = early ? 0.55 : 0.9
        if cast.archer, cast.ranged {
            AudioLibrary.shared.play(.arrowHit, volume: loud * 0.8)
        } else if melee {
            // The element under the blade: `Juice` sounds the blade itself.
            AudioLibrary.shared.play(.hit(cast.element), volume: loud * 0.6)
        }
        if let named, thunders(named) {
            let full: Float = named == "keraunos" ? 1.0 : 0.7
            AudioLibrary.shared.play(.thunder, volume: full * (early ? 0.6 : 1))
        }
    }

    /// A melee blow's slash across its victim: the element's painted
    /// crescent turned 25° one way on one strike and the other way on the
    /// next, a fifth larger on a heavy blow; the code-drawn arc until the
    /// crescent ships.
    private static func slash(on victim: UnitNode, turn index: Int, heavy: Bool, reach: VFXLibrary.Reach, scale: Float,
                              element: Element, colours: CastColours, in scene: SCNScene) {
        let chest = victim.chestWorldPosition
        let angle: CGFloat = index % 2 == 0 ? 25 : -25
        let grown: CGFloat = heavy ? 1.2 : 1
        if VFXLibrary.playSheet("\(element.rawValue)_slash", at: chest, in: scene, tint: colours.paint,
                                casterTint: colours.aura, size: 2.1 * CGFloat(scale) * grown, life: 0.45,
                                angle: angle, reach: reach) {
            return
        }
        VFXLibrary.spawn("slash", at: chest, in: scene, tint: colours.aura, scale: scale * (heavy ? 1.3 : 1.0), reach: reach)
    }

    /// A hit's burst on its victim: the element's painted burst with its
    /// sparks and, when `lit`, one light under the key; the element's hit
    /// of 2026-09-10 until the burst ships (lighting itself only when `lit`).
    private static func burst(on victim: UnitNode, element: Element, reach: VFXLibrary.Reach, lit: Bool, scale: Float,
                              colours: CastColours, in scene: SCNScene) {
        let chest = victim.chestWorldPosition
        if VFXLibrary.playSheet("\(element.rawValue)_burst", at: chest, in: scene, tint: colours.paint,
                                casterTint: colours.aura, size: 2.3 * CGFloat(scale), life: 0.6, reach: reach) {
            let quiet: Bool
            if case .single = reach { quiet = false } else { quiet = true }
            VFXLibrary.sparkBurst(at: chest, in: scene, tint: colours.aura, count: quiet ? 18 : 40, speed: 5, scale: scale)
            if lit { VFXLibrary.flash(at: chest, in: scene, color: colours.aura, radius: 1.4 * scale, duration: 0.2) }
            return
        }
        let drawn: VFXLibrary.Reach = lit ? reach : .member
        VFXLibrary.spawn("impact_\(element.rawValue)", at: chest, in: scene, tint: colours.aura, scale: scale, reach: drawn)
    }

    /// A ring spreading on the floor under a heavy blow: the element's
    /// painted ring, the dust shockwave until it ships.
    private static func ring(under feet: SCNVector3, element: Element, reach: VFXLibrary.Reach, scale: Float,
                             colours: CastColours, in scene: SCNScene) {
        let floor = SCNVector3(feet.x, 0, feet.z)
        let side = VFXLibrary.reachSide(3.2 * CGFloat(scale), reach: reach)
        let tint = VFXLibrary.reachTint(colours.paint, casterTint: colours.aura, reach: reach)
        if VFXLibrary.groundFlipbook("\(element.rawValue)_ring", at: floor, in: scene, tint: tint, size: side, life: 0.7) {
            return
        }
        VFXLibrary.spawn("shockwave", at: floor, in: scene, tint: colours.aura, scale: scale, reach: reach)
    }

    /// A shot at one victim, `flight` seconds from now to its contact: an
    /// archer's arrow and the loose of the string; any other caster's orb
    /// (`projectile`'s sprite until the orb ships) and the spell's release.
    private static func shoot(_ cast: CastFX, at victim: UnitNode, flight: TimeInterval, early: Bool, sounded: Bool,
                              colours: CastColours, in scene: SCNScene) {
        let from = cast.caster.chestWorldPosition
        let to = victim.chestWorldPosition
        let scale: Float = cast.caster.spec.height / 1.9
        if cast.archer {
            VFXLibrary.arrow(from: from, to: to, in: scene, element: cast.element, tint: colours.aura, duration: flight,
                             scale: scale)
            if sounded { AudioLibrary.shared.play(.loose, volume: early ? 0.5 : 0.8) }
            return
        }
        if !VFXLibrary.orb(cast.element, from: from, to: to, in: scene, tint: colours.aura, duration: flight, scale: scale) {
            VFXLibrary.projectile(cast.element, from: from, to: to, in: scene, tint: colours.aura, duration: flight,
                                  scale: scale)
        }
        if sounded { AudioLibrary.shared.play(.cast(cast.element), volume: early ? 0.45 : 0.7) }
    }

    /// An area cast's piece on one victim of its line: the element's strike
    /// falling from the sky (ember, radiance) or its pillar rising out of
    /// the ground (tide, gale, umbra), drawn as one of several. Nothing
    /// until the sheet ships: every victim's own impact carries the hit.
    private static func rise(_ element: Element, under victim: UnitNode, colours: CastColours, in scene: SCNScene) {
        let scale = BattleSceneController.effectScale(for: victim)
        let tint = VFXLibrary.reachTint(colours.paint, casterTint: colours.aura, reach: .member)
        let side = VFXLibrary.reachSide(3.2 * CGFloat(scale), reach: .member)
        VFXLibrary.anchoredSheet(risingSheet(element), feet: victim.position, in: scene, tint: tint, size: side, life: 0.9)
    }

    /// The sheet an element's line is struck with: a strike from the sky
    /// for fire and light, a pillar out of the ground for the rest.
    private static func risingSheet(_ element: Element) -> String {
        let kind: String
        switch element {
        case .ember, .radiance: kind = "strike"
        case .tide, .gale, .umbra: kind = "pillar"
        }
        return "\(element.rawValue)_\(kind)"
    }

    /// A rite's release lifting off its caster: the element's burst at 0.8
    /// of a hit's, a little over the chest, with its light, and motes of the
    /// element rising — the element's hit of 2026-09-10 until the burst
    /// ships.
    private static func release(from caster: UnitNode, element: Element, colours: CastColours, in scene: SCNScene) {
        let scale = BattleSceneController.effectScale(for: caster)
        let chest = caster.chestWorldPosition
        let above = SCNVector3(chest.x, chest.y + 0.3 * scale, chest.z)
        if VFXLibrary.playSheet("\(element.rawValue)_burst", at: above, in: scene, tint: colours.paint,
                                casterTint: colours.aura, size: 2.3 * 0.8 * CGFloat(scale), life: 0.7) {
            VFXLibrary.flash(at: chest, in: scene, color: colours.aura, radius: 1.2 * scale, duration: 0.25)
        } else {
            VFXLibrary.spawn("impact_\(element.rawValue)", at: above, in: scene, tint: colours.aura, scale: scale * 0.8)
        }
        VFXLibrary.risingMotes(at: caster.position, in: scene, tint: colours.element, count: 50, scale: scale)
    }

    // MARK: - The signature

    /// How far ahead of its hit a look is started so that it LANDS on the
    /// number: its painting's own lead (`landsAhead`) when the painting, or
    /// the first painted sheet it falls back to, has shipped; the first
    /// arrow's fall for a volley drawn in code (`volleyFlight`), whose
    /// arrows are thrown from the sky and would otherwise land a third of a
    /// second after the numbers; nothing for a look that lands as it begins.
    private static func lead(of look: SignatureFX, element: Element) -> TimeInterval {
        if hasPainting(look, element: element) { return look.landsAhead }
        return look == .volley ? volleyFlight : 0
    }

    /// Whether a look's own painting, or the first painted sheet it falls
    /// back to, has shipped — so it is worth starting ahead of its hit.
    private static func hasPainting(_ look: SignatureFX, element: Element) -> Bool {
        if let sheet = look.sheet, VFXLibrary.hasSheet(sheet) { return true }
        switch look {
        case .meteor, .holyBlade: return VFXLibrary.hasSheet("\(element.rawValue)_strike")
        case .maw, .tidal, .tornado: return VFXLibrary.hasSheet("\(element.rawValue)_pillar")
        case .eruption: return VFXLibrary.hasSheet(risingSheet(element))
        case .lightning, .spikes, .bladestorm, .spirit, .sunburst, .script, .claw, .blood, .volley: return false
        }
    }

    /// Draws an ultimate's signature on its target, on one victim of a line
    /// (`.member`, quiet: the caller lights the line once) or once over a
    /// whole line's middle (`.row`), each look from its own painting and,
    /// until that ships, from the sheets and the named effects the fight
    /// already has — so every signature reads before a single new sheet is
    /// painted. A painting of the look's own element is multiplied by near
    /// white, its paint showing; a neutral one (stone, steel, a wolf of
    /// light, a rain of arrows) is tinted toward the caster's element.
    private static func sign(_ look: SignatureFX, on victims: [UnitNode], reach: VFXLibrary.Reach, cast: CastFX,
                             colours: CastColours, in scene: SCNScene) {
        guard !victims.isEmpty else { return }
        let element = cast.element
        let feet = middle(of: victims)
        let chestHeight: Float = victims.reduce(Float(0)) { $0 + $1.chestWorldPosition.y } / Float(victims.count)
        let chest = SCNVector3(feet.x, chestHeight, feet.z)
        let scale = meanScale(of: victims)
        let own = VFXLibrary.reachTint(colours.paint, casterTint: colours.aura, reach: reach)
        let neutral = VFXLibrary.reachTint(colours.element.mixed(with: .white, amount: 0.45), casterTint: colours.aura,
                                           reach: reach)
        let big = VFXLibrary.reachSide(4.4 * CGFloat(scale), reach: reach)
        let row: Bool
        if case .row = reach { row = true } else { row = false }
        let chests = victims.map { $0.chestWorldPosition }
        // Whether what was drawn brought its own light (the named effects
        // light themselves; a painting is lit once below).
        var lit = false
        switch look {
        case .meteor, .holyBlade:
            let painted = look.sheet ?? ""
            if !VFXLibrary.anchoredSheet(painted, feet: feet, in: scene, tint: own, size: big, life: 1.0),
               !VFXLibrary.anchoredSheet("\(element.rawValue)_strike", feet: feet, in: scene, tint: own, size: big * 0.85,
                                         life: 0.9) {
                if look == .meteor {
                    VFXLibrary.spawn("impact_ember", at: chest, in: scene, tint: colours.aura, scale: scale * 1.4, reach: reach)
                    VFXLibrary.spawn("shockwave", at: feet, in: scene, tint: colours.aura, scale: scale, reach: reach)
                } else {
                    VFXLibrary.spawn("eye_of_ra", at: chest, in: scene, tint: colours.aura, scale: scale, reach: reach)
                }
                lit = true
            }
        case .maw:
            if !VFXLibrary.anchoredSheet("maw", feet: feet, in: scene, tint: own, size: big * 0.9, life: 1.0),
               !VFXLibrary.anchoredSheet("\(element.rawValue)_pillar", feet: feet, in: scene, tint: own, size: big * 0.8,
                                         life: 0.9),
               !VFXLibrary.playSheet("shadow", at: chest, in: scene, tint: .white, casterTint: colours.aura,
                                     size: 3.0 * CGFloat(scale), life: 0.7, reach: reach) {
                VFXLibrary.spawn("scale_strike", at: chest, in: scene, tint: colours.aura, scale: scale, reach: reach)
                lit = true
            }
        case .spirit:
            if !VFXLibrary.playSheet("spirit", at: chest, in: scene, tint: neutral, casterTint: colours.aura,
                                     size: 3.6 * CGFloat(scale), life: 0.8, reach: reach),
               !VFXLibrary.playSheet("claw", at: chest, in: scene, tint: neutral, casterTint: colours.aura,
                                     size: 2.8 * CGFloat(scale), life: 0.6, reach: reach) {
                VFXLibrary.spawn("lioness_rake", at: chest, in: scene, tint: colours.aura, scale: scale, reach: reach)
                lit = true
            }
        case .claw:
            VFXLibrary.spawn("lioness_rake", at: chest, in: scene, tint: colours.aura, scale: scale, reach: reach)
            lit = true
        case .blood:
            VFXLibrary.spawn("blood_slash", at: chest, in: scene, tint: colours.aura, scale: scale, reach: reach)
            lit = true
        case .lightning:
            if row {
                VFXLibrary.spawnArea("thunderclap", over: chests, in: scene, tint: colours.aura, scale: scale)
            } else {
                VFXLibrary.spawn("keraunos", at: chest, in: scene, tint: colours.aura, scale: scale, reach: reach)
            }
            lit = true
        case .sunburst:
            if row {
                VFXLibrary.spawnArea("wrath_of_the_eye", over: chests, in: scene, tint: colours.aura, scale: scale)
            } else {
                VFXLibrary.spawn("eye_of_ra", at: chest, in: scene, tint: colours.aura, scale: scale, reach: reach)
            }
            lit = true
        case .script:
            if row {
                VFXLibrary.spawnArea("duat_rite", over: chests, in: scene, tint: colours.aura, scale: scale)
            } else {
                VFXLibrary.spawn("duat_rite", at: chest, in: scene, tint: colours.aura, scale: scale, reach: reach)
            }
            lit = true
        case .tidal, .tornado:
            let painted = look.sheet ?? ""
            if !VFXLibrary.anchoredSheet(painted, feet: feet, in: scene, tint: own, size: big, life: 1.0) {
                var risen = false
                for victim in victims {
                    let side = VFXLibrary.reachSide(3.2 * CGFloat(BattleSceneController.effectScale(for: victim)),
                                                    reach: .member)
                    if VFXLibrary.anchoredSheet("\(element.rawValue)_pillar", feet: victim.position, in: scene,
                                                tint: VFXLibrary.reachTint(colours.paint, casterTint: colours.aura, reach: .member),
                                                size: side, life: 0.9) {
                        risen = true
                    }
                }
                if !risen {
                    VFXLibrary.spawn("impact_\(element.rawValue)", at: chest, in: scene, tint: colours.aura,
                                     scale: scale * 1.4, reach: reach)
                    VFXLibrary.spawn("shockwave", at: feet, in: scene, tint: colours.aura, scale: scale, reach: reach)
                    lit = true
                }
            }
        case .spikes:
            if !VFXLibrary.anchoredSheet("spikes", feet: feet, in: scene, tint: neutral, size: big * 0.9, life: 1.0) {
                ring(under: feet, element: element, reach: reach, scale: scale * 1.3, colours: colours, in: scene)
                let stone = UIColor(hex: "#D8C0A0") ?? .white
                VFXLibrary.sparkBurst(at: SCNVector3(feet.x, 0.3, feet.z), in: scene, tint: stone, count: 70, speed: 6,
                                      scale: scale)
            }
        case .bladestorm:
            if !VFXLibrary.playSheet("bladestorm", at: chest, in: scene, tint: neutral, casterTint: colours.aura,
                                     size: 3.8 * CGFloat(scale), life: 0.8, reach: reach) {
                // Three cuts across the target at three angles: the element's
                // crescents, or the code-drawn arcs.
                for angle in [CGFloat(-40), CGFloat(15), CGFloat(70)] {
                    if !VFXLibrary.playSheet("\(element.rawValue)_slash", at: chest, in: scene, tint: colours.paint,
                                             casterTint: colours.aura, size: 2.4 * CGFloat(scale), life: 0.5,
                                             angle: angle, reach: reach) {
                        VFXLibrary.spawn("slash", at: chest, in: scene, tint: colours.aura, scale: scale * 1.2, reach: reach)
                    }
                }
            }
        case .volley:
            if !VFXLibrary.anchoredSheet("volley", feet: feet, in: scene, tint: neutral, size: big * 0.9, life: 1.0) {
                // A rain of arrows out of the sky on each victim, landing one
                // after another: launched together, each flying a little
                // longer than the last — started `volleyFlight` ahead of the
                // hit (`lead(of:element:)`), so the first lands on it.
                for victim in victims {
                    let ground = victim.position
                    let height = BattleSceneController.effectScale(for: victim)
                    for arrow in 0..<5 {
                        let spread = Float(arrow - 2) * 0.22
                        let landing = SCNVector3(ground.x + spread, 0.35 * height, ground.z + spread * 0.5)
                        let sky = SCNVector3(landing.x - 2.4, landing.y + 7.5, landing.z - 0.8)
                        let flight: TimeInterval = volleyFlight + 0.05 * Double(arrow)
                        VFXLibrary.arrow(from: sky, to: landing, in: scene, element: element, tint: colours.aura,
                                         duration: flight, scale: height, arc: 0)
                    }
                }
            }
        case .eruption:
            var risen = false
            for victim in victims {
                let side = VFXLibrary.reachSide(3.4 * CGFloat(BattleSceneController.effectScale(for: victim)), reach: reach)
                if VFXLibrary.anchoredSheet(risingSheet(element), feet: victim.position, in: scene, tint: own, size: side,
                                            life: 0.9) {
                    risen = true
                }
            }
            ring(under: feet, element: element, reach: reach, scale: scale * 1.2, colours: colours, in: scene)
            if !risen {
                VFXLibrary.spawn("impact_\(element.rawValue)", at: chest, in: scene, tint: colours.aura,
                                 scale: scale * 1.3, reach: reach)
                lit = true
            }
        }
        guard !lit else { return }
        switch reach {
        case .single:
            VFXLibrary.flash(at: chest, in: scene, color: colours.aura, radius: 2.4 * scale, duration: 0.3)
        case .member:
            break
        case .row:
            rowLight(over: victims, tint: colours.aura, in: scene)
        }
    }

    // MARK: - The named looks

    /// The named effects that are BLOWS, kept as a hit's delivery and
    /// impact (2026-09-15's painted looks and the gods' bolts); any other
    /// name on a damaging skill — a heal's lotus, a buff's motes, Ma'at's
    /// shield, the blood-thirst — is a support look that has no business on
    /// an enemy being struck, and that skill's hits speak the element's
    /// grammar instead.
    private static func blowLook(_ vfx: String) -> String? {
        switch vfx {
        case "scale_strike", "heart_weigh", "duat_rite", "olympian_decree", "lioness_rake", "eye_of_ra",
             "wrath_of_the_eye", "blood_slash", "thunderbolt", "thunderclap", "keraunos":
            return vfx
        default:
            return nil
        }
    }

    /// The named look a rite draws over its targets as it is released: its
    /// own (a decree's script, Ma'at's shield, the blood-thirst), never the
    /// heal, the buff, the debuff or the shield, which each ally's own event
    /// draws (drawn by the cast as well, a heal was drawn twice).
    private static func riteLook(_ vfx: String) -> String? {
        if vfx.isEmpty || vfx.hasPrefix("impact_") { return nil }
        switch vfx {
        case "heal", "buff", "debuff", "shield":
            return nil
        default:
            return vfx
        }
    }

    /// The painted sheet a named blow already draws, so an ultimate's
    /// signature is not drawn over its own painting twice.
    private static func namedSheet(_ vfx: String) -> String? {
        switch vfx {
        case "thunderbolt", "thunderclap", "keraunos": return "lightning"
        case "duat_rite", "olympian_decree": return "script"
        case "scale_strike", "heart_weigh": return "shadow"
        case "lioness_rake": return "claw"
        case "eye_of_ra", "wrath_of_the_eye": return "sunburst"
        case "blood_slash": return "blood"
        default: return nil
        }
    }

    /// Whether a named blow sounds the thunder with it.
    private static func thunders(_ vfx: String) -> Bool {
        vfx == "thunderbolt" || vfx == "thunderclap" || vfx == "keraunos"
    }

    // MARK: - Lines

    /// One light for a whole line struck at once, at its middle and under
    /// the key, as `spawnArea` lights a line whose members draw their own.
    private static func rowLight(over victims: [UnitNode], tint: UIColor, in scene: SCNScene) {
        guard victims.count > 1 else { return }
        let centre = middle(of: victims)
        let chestHeight: Float = victims.reduce(Float(0)) { $0 + $1.chestWorldPosition.y } / Float(victims.count)
        let reach: Float = min(4, span(of: victims) * 0.5 + 1)
        VFXLibrary.flash(at: SCNVector3(centre.x, chestHeight, centre.z), in: scene, color: tint, radius: reach,
                         duration: 0.3, strength: VFXLibrary.rowLightStrength)
    }

    /// The middle of a line on the floor.
    private static func middle(of victims: [UnitNode]) -> SCNVector3 {
        guard !victims.isEmpty else { return SCNVector3(0, 0, 0) }
        let count = Float(victims.count)
        let x: Float = victims.reduce(Float(0)) { $0 + $1.position.x } / count
        let z: Float = victims.reduce(Float(0)) { $0 + $1.position.z } / count
        return SCNVector3(x, 0, z)
    }

    /// How far a line runs across the floor, end to end.
    private static func span(of victims: [UnitNode]) -> Float {
        var widest: Float = 0
        for first in victims {
            for second in victims {
                widest = max(widest, hypotf(first.position.x - second.position.x, first.position.z - second.position.z))
            }
        }
        return widest
    }

    /// The size an effect is drawn at over several victims: their mean.
    private static func meanScale(of victims: [UnitNode]) -> Float {
        guard !victims.isEmpty else { return 1 }
        let total: Float = victims.reduce(Float(0)) { $0 + BattleSceneController.effectScale(for: $1) }
        return total / Float(victims.count)
    }

    // MARK: - Colours

    /// A cast's colours: its element's accent (circles, auras, motes); the
    /// family's aura in that element, which the fight's impacts were always
    /// tinted with ("a fire Anubis and a fire Zeus burn in their own
    /// oranges"); and the near white a painted element sheet is multiplied
    /// by, so the painting's own colour shows.
    private struct CastColours {
        let element: UIColor
        let aura: UIColor
        let paint: UIColor

        init(_ cast: CastFX) {
            let accent = UIColor(hex: cast.element.accentHex) ?? .white
            element = accent
            let family = UIColor(hex: cast.caster.spec.auraHex) ?? accent
            aura = family
            paint = family.mixed(with: .white, amount: 0.6)
        }
    }
}
