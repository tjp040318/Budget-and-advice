import Foundation

/// The engine's output. Battles are simulated to completion (or to the next
/// point where the player must choose) and hand back an ordered list of these.
/// The renderer walks the list, plays the matching animation and updates the
/// HUD; it never asks the engine what the state "is" mid-animation.
enum BattleEvent: Identifiable, Sendable {
    case battleStart(playerTeam: [UUID], opponentTeam: [UUID])
    case turnBegan(actor: UUID, turnNumber: Int)
    /// The actor is stunned, frozen or asleep and loses the turn.
    case turnSkipped(actor: UUID, reason: StatusKind)
    case skillCast(actor: UUID, skillID: String, skillName: String, targets: [UUID], shot: CameraShot, animation: AnimationClip, vfx: String)
    case damage(source: UUID, target: UUID, amount: Double, isCritical: Bool, isGlancing: Bool, matchup: Element.Matchup, remainingHealth: Double, hitIndex: Int, hitCount: Int)
    case healed(source: UUID, target: UUID, amount: Double, remainingHealth: Double)
    case shieldAbsorbed(target: UUID, amount: Double, shieldRemaining: Double)
    case statusApplied(source: UUID, target: UUID, kind: StatusKind, turns: Int)
    case statusResisted(source: UUID, target: UUID, kind: StatusKind)
    case statusExpired(target: UUID, kind: StatusKind)
    case statusRemoved(target: UUID, kind: StatusKind, byStrip: Bool)
    case attackBarChanged(target: UUID, delta: Double, newValue: Double)
    case counterattack(actor: UUID, target: UUID)
    case extraTurnGranted(actor: UUID, source: String)
    case revived(target: UUID, health: Double)
    case defeated(target: UUID)
    case cooldownStarted(actor: UUID, skillSlot: Int, turns: Int)
    case passiveTriggered(actor: UUID, name: String)
    case battleEnded(result: BattleResult)

    var id: String {
        switch self {
        case .battleStart: return "start"
        case .turnBegan(let a, let n): return "turn-\(a)-\(n)"
        case .turnSkipped(let a, let r): return "skip-\(a)-\(r.rawValue)"
        case .skillCast(let a, let s, _, _, _, _, _): return "cast-\(a)-\(s)"
        case .damage(let s, let t, _, _, _, _, _, let i, _): return "dmg-\(s)-\(t)-\(i)"
        case .healed(let s, let t, let amount, _): return "heal-\(s)-\(t)-\(amount)"
        case .shieldAbsorbed(let t, let a, _): return "shield-\(t)-\(a)"
        case .statusApplied(_, let t, let k, _): return "status-\(t)-\(k.rawValue)"
        case .statusResisted(_, let t, let k): return "resist-\(t)-\(k.rawValue)"
        case .statusExpired(let t, let k): return "expire-\(t)-\(k.rawValue)"
        case .statusRemoved(let t, let k, _): return "remove-\(t)-\(k.rawValue)"
        case .attackBarChanged(let t, let d, _): return "atb-\(t)-\(d)"
        case .counterattack(let a, let t): return "counter-\(a)-\(t)"
        case .extraTurnGranted(let a, let s): return "extra-\(a)-\(s)"
        case .revived(let t, _): return "revive-\(t)"
        case .defeated(let t): return "dead-\(t)"
        case .cooldownStarted(let a, let s, _): return "cd-\(a)-\(s)"
        case .passiveTriggered(let a, let n): return "passive-\(a)-\(n)"
        case .battleEnded: return "end"
        }
    }

    /// How long the renderer should hold before playing the next event.
    /// Damage numbers within one multi-hit skill land fast; casts breathe.
    var presentationDuration: TimeInterval {
        switch self {
        case .battleStart: return 1.2
        case .turnBegan: return 0.25
        case .turnSkipped: return 0.9
        case .skillCast(_, _, _, _, let shot, let animation, _):
            return max(shot.duration, animation.fallbackDuration)
        case .damage(_, _, _, let crit, _, _, _, _, _): return crit ? 0.42 : 0.3
        case .healed: return 0.5
        case .shieldAbsorbed: return 0.25
        case .statusApplied: return 0.3
        case .statusResisted: return 0.35
        case .statusExpired, .statusRemoved: return 0.2
        case .attackBarChanged: return 0.3
        case .counterattack: return 0.9
        case .extraTurnGranted: return 0.6
        case .revived: return 1.4
        case .defeated: return 1.1
        case .cooldownStarted: return 0
        case .passiveTriggered: return 0.6
        case .battleEnded: return 1.6
        }
    }
}

enum BattleOutcome: String, Codable, Sendable {
    case victory
    case defeat
    case draw
}

/// The summary the rest of the game reads once a battle finishes.
struct BattleResult: Codable, Equatable, Sendable {
    var outcome: BattleOutcome
    var turnsTaken: Int
    /// Fraction of the player team still standing, 0...1. Drives star ratings.
    var survivorFraction: Double
    var totalDamageDealt: Double
    var totalDamageTaken: Double
    /// Seed the battle ran on, stored with replays.
    var seed: UInt64
}
