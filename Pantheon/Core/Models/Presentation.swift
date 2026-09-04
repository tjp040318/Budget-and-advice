import Foundation

/// Animation clips every character rig must export. `ModelLibrary` looks for a
/// SceneKit animation player with exactly these keys inside the unit's `.usdz`
/// (or a sibling `<unit>_<clip>.usdz`), so the names here are a contract with
/// the art pipeline. See `Docs/ART_PIPELINE.md`.
enum AnimationClip: String, Codable, CaseIterable, Sendable {
    case idle
    case idleCombat = "idle_combat"
    case attackBasic = "attack_basic"
    case attackHeavy = "attack_heavy"
    case castLoop = "cast_loop"
    case castRelease = "cast_release"
    case ultimate
    case hitReact = "hit_react"
    case death
    case victory
    case summonReveal = "summon_reveal"

    /// Clips that must loop rather than play once.
    var loops: Bool {
        switch self {
        case .idle, .idleCombat, .castLoop: return true
        default: return false
        }
    }

    /// Seconds the engine holds the battle before resuming, when a real clip is
    /// missing. Keeps pacing sane with placeholder art.
    var fallbackDuration: TimeInterval {
        switch self {
        case .ultimate: return 2.4
        case .attackHeavy, .castRelease: return 1.4
        case .attackBasic: return 1.0
        case .hitReact: return 0.45
        case .death: return 1.2
        case .victory: return 2.0
        case .summonReveal: return 3.0
        default: return 1.0
        }
    }
}

/// How the camera covers a skill.
enum CameraShot: String, Codable, Sendable {
    /// Wide battlefield framing, no cut.
    case standard
    /// Quick push toward the attacker on cast, then back out.
    case pushIn = "push_in"
    /// Orbit around the caster during a channel — for ultimates.
    case cinematicOrbit = "cinematic_orbit"
    /// Low hero angle looking up at the caster. Reserved for gods.
    case heroLowAngle = "hero_low_angle"
    /// Tight over-the-shoulder on the victim as the hit lands.
    case impactClose = "impact_close"

    var duration: TimeInterval {
        switch self {
        case .standard: return 0
        case .pushIn: return 0.8
        case .cinematicOrbit: return 2.2
        case .heroLowAngle: return 1.6
        case .impactClose: return 0.7
        }
    }
}

/// Everything the renderer needs to put a unit on screen. Kept in Core (not
/// Render) so blueprints stay a single source of truth and the engine can be
/// unit-tested without SceneKit.
struct ModelSpec: Codable, Equatable, Sendable {
    /// Base filename without extension, e.g. `anubis`. The loader tries
    /// `anubis.usdz`, then `anubis.scn`, then falls back to a procedural stand-in.
    ///
    /// Elemental variants of one character deliberately SHARE this: all five
    /// Anubis point at `anubis` and differ only by `auraHex`, so a whole family
    /// costs one export.
    var assetName: String
    /// Uniform scale applied on top of the archetype scale.
    var scale: Float = 1.0
    /// Metres from the model origin to the top of the head. Used to place the
    /// health bar and to aim the camera, so it must be filled in per model.
    var height: Float = 1.9
    /// Vertical offset if the export's origin is not at the feet.
    var yOffset: Float = 0
    /// Degrees of Y rotation needed for the model to face +Z.
    var yawCorrection: Float = 0
    /// Node names in the rig used as VFX attachment points.
    var weaponAttachNode: String? = nil
    var handAttachNode: String? = "hand_r"
    var chestAttachNode: String? = "spine_03"
    /// Emissive colour used by the rim light and the summon beam.
    var auraHex: String = "#FFFFFF"
    /// Portrait image name in the asset catalogue.
    var portraitName: String

    init(
        assetName: String,
        scale: Float = 1.0,
        height: Float = 1.9,
        yOffset: Float = 0,
        yawCorrection: Float = 0,
        weaponAttachNode: String? = nil,
        handAttachNode: String? = "hand_r",
        chestAttachNode: String? = "spine_03",
        auraHex: String = "#FFFFFF",
        portraitName: String? = nil
    ) {
        self.assetName = assetName
        self.scale = scale
        self.height = height
        self.yOffset = yOffset
        self.yawCorrection = yawCorrection
        self.weaponAttachNode = weaponAttachNode
        self.handAttachNode = handAttachNode
        self.chestAttachNode = chestAttachNode
        self.auraHex = auraHex
        self.portraitName = portraitName ?? "portrait_\(assetName)"
    }
}

/// A battle stage's visual setting. Each case names a scene file and a lighting
/// preset; `BattleSceneController` falls back to a procedural stage if the file
/// is missing, so environments can ship one at a time.
enum BattleEnvironment: String, Codable, CaseIterable, Sendable {
    case duatGate = "duat_gate"
    case reedFields = "reed_fields"
    case hallOfTwoTruths = "hall_of_two_truths"
    case serpentDeep = "serpent_deep"
    case arenaOfSouls = "arena_of_souls"

    var displayName: String {
        switch self {
        case .duatGate: return "The First Gate"
        case .reedFields: return "Field of Reeds"
        case .hallOfTwoTruths: return "Hall of Two Truths"
        case .serpentDeep: return "The Serpent Deep"
        case .arenaOfSouls: return "Arena of Souls"
        }
    }

    /// Scene file to load from `Resources/Environments`, without extension.
    var sceneName: String { rawValue }

    /// Image-based lighting file (`.hdr` or `.exr`) driving reflections.
    var environmentMap: String { "\(rawValue)_ibl" }

    /// Key light colour and the fog the stage sits in — used by the procedural
    /// fallback and to tint the real scene consistently.
    var keyLightHex: String {
        switch self {
        case .duatGate: return "#F2D9A8"
        case .reedFields: return "#D8E0B0"
        case .hallOfTwoTruths: return "#FFF0CC"
        case .serpentDeep: return "#C08CFF"
        case .arenaOfSouls: return "#FFE3B0"
        }
    }

    var fogHex: String {
        switch self {
        case .duatGate: return "#4A3A28"
        case .reedFields: return "#3C4A38"
        case .hallOfTwoTruths: return "#5A4C33"
        case .serpentDeep: return "#2A1A38"
        case .arenaOfSouls: return "#6E5A3C"
        }
    }
}

