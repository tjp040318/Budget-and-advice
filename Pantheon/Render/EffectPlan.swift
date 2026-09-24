import Foundation

// MARK: - What a fight can draw (Docs/FEEL.md W2.24)
//
// A shader compiles the first time something is DRAWN with it (run 221: the
// reveal's 21 shaders compiled at its flash and stalled the main thread a
// second). The battle parsed its meshes in advance and drew nothing in
// advance, so the first ultimate of every fight, the first fireburst and the
// first standing sheet each paid their compile in the middle of the fight.
// While the stage card holds, `VFXLibrary.predraw` draws once, out of sight,
// everything this plan names, and the controller steps the lights a fight
// adds through the counts it reaches (`PredrawStep`).

/// One named effect as it will first be drawn: its name (`Skill.vfx`, an
/// element's `impact_<element>`) and the tint of the first caster to use it.
struct PlannedEffect: Equatable, Hashable {
    var name: String
    var tintHex: String
}

/// One fighter as the plan reads it: its element, whether it closes to
/// strike, whether it is a boss and whether it arrives with a later wave,
/// its aura, and the effect each of its skills names.
struct PlannedFighter: Equatable {
    var element: Element
    var melee: Bool
    var boss: Bool
    var laterWave: Bool = false
    var auraHex: String
    var effects: [String]
}

/// Everything one fight can draw: every named effect once, the elements
/// whose projectiles fly, whether anyone closes to strike (the slash, the
/// shockwave under a heavy blow, the swing's ribbon) and whether a boss
/// rises over the rim (its dust) — and whether one arrives with a later
/// wave, whose warm spot is a light the figures' shaders have not met.
struct EffectPlan: Equatable {
    var effects: [PlannedEffect] = []
    var projectiles: [Element] = []
    var closes = false
    var boss = false
    var laterBoss = false

    /// The effects every fight can draw whoever fights it: a crit's sparks,
    /// a buff's and a debuff's motes and a heal's lotus, in the tints the
    /// controller spawns them in.
    static let always: [PlannedEffect] = [
        PlannedEffect(name: "crit", tintHex: "#FFD24F"),
        PlannedEffect(name: "buff", tintHex: "#FFFFFF"),
        PlannedEffect(name: "debuff", tintHex: "#FFFFFF"),
        PlannedEffect(name: "heal", tintHex: "#7FE8A0"),
    ]

    /// The plan for a fight's fighters, every wave's. A skill with no effect
    /// of its own (`impact_generic`) lands in its caster's element, as
    /// `BattleSceneController.performCast` draws it, and every caster's
    /// element hit is in the plan whatever its skills name, because a
    /// passive or a counter lands in it too. Each effect is listed once, in
    /// the order it is first met, with its first caster's aura; the
    /// projectiles are the ranged casters' elements (a boss throws none).
    static func of(_ fighters: [PlannedFighter]) -> EffectPlan {
        var plan = EffectPlan()
        var seen: Set<String> = []
        func add(_ name: String, tint: String) {
            guard !name.isEmpty, seen.insert(name).inserted else { return }
            plan.effects.append(PlannedEffect(name: name, tintHex: tint))
        }
        var thrown: Set<Element> = []
        for fighter in fighters {
            let own = "impact_\(fighter.element.rawValue)"
            add(own, tint: fighter.auraHex)
            for effect in fighter.effects {
                add(effect == "impact_generic" ? own : effect, tint: fighter.auraHex)
            }
            if fighter.melee {
                plan.closes = true
            } else if !fighter.boss, thrown.insert(fighter.element).inserted {
                plan.projectiles.append(fighter.element)
            }
            if fighter.boss {
                plan.boss = true
                if fighter.laterWave { plan.laterBoss = true }
            }
        }
        if plan.closes {
            add("slash", tint: "#D9E4F2")
            add("shockwave", tint: "#D8C0A0")
        }
        for effect in always { add(effect.name, tint: effect.tintHex) }
        return plan
    }
}

/// The pre-draw's steps under the stage card, one every `framesEach` drawn
/// frames: the effects with no light of their own first, then one, two and
/// three of `flash`'s lights at once (a hit's, a multi-hit's overlapping
/// pair, a strike with its sky flash and the next hit's), then a later
/// boss's warm spot alone and beside a flash, then the holder retired.
/// SceneKit keys a material's shader by the lights that reach it, so each
/// count a fight reaches is a compile, and each is paid here.
enum PredrawStep: Equatable {
    case lights(Int)
    case spot(withFlash: Bool)
    case retire

    /// Drawn frames each step stands for: the first compiles, the second
    /// makes sure a light added in the middle of a frame was drawn whole.
    static let framesEach = 2

    /// The most `flash` lights the pre-draw stands up at once.
    static let mostLights = 3

    /// The steps for a plan, in order.
    static func steps(laterBoss: Bool) -> [PredrawStep] {
        var steps: [PredrawStep] = (1...mostLights).map { PredrawStep.lights($0) }
        if laterBoss {
            steps.append(.spot(withFlash: false))
            steps.append(.spot(withFlash: true))
        }
        steps.append(.retire)
        return steps
    }

    /// The step due once `frame` frames have been drawn since the build:
    /// step k after frame `framesEach × (k + 1)`; nil between steps.
    static func step(afterFrame frame: Int, laterBoss: Bool) -> PredrawStep? {
        guard frame > 0, frame % framesEach == 0 else { return nil }
        let index = frame / framesEach - 1
        let all = steps(laterBoss: laterBoss)
        guard index >= 0, index < all.count else { return nil }
        return all[index]
    }

    /// Drawn frames the whole pre-draw takes, its retirement included.
    static func frames(laterBoss: Bool) -> Int {
        framesEach * (steps(laterBoss: laterBoss).count + 1)
    }
}
