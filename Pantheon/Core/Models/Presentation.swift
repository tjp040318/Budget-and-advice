import Foundation
import UIKit

/// Is a painting in the bundle?
///
/// The paintings ship as JPEG (`tools/shrink_art.py`: a card is a 1024px
/// painting with no transparency, and the PNG of one is five times the size),
/// while the UI kit and the sprites that carry alpha stay PNG. `UIImage(named:)`
/// does not care, but the two places that ask whether a file exists by name did,
/// so they ask here instead and both extensions are tried.
enum BundleArt {
    static let extensions = ["jpg", "png"]

    static func url(_ name: String) -> URL? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }

    static func exists(_ name: String) -> Bool { url(name) != nil }

    /// The painting itself.
    ///
    /// `UIImage(named:)` is the reason this exists. For an image inside an
    /// asset catalogue it finds any format; for a **loose file in the bundle**
    /// — which is what every painting here is — it appends `.png` and nothing
    /// else. The moment the cards became JPEGs, `UIImage(named: "portrait_x")`
    /// returned nil for all 154 of them and every unit in the collection fell
    /// back to its letter placeholder. The CI tour photographed it.
    ///
    /// So: ask UIKit first (asset-catalogue images and any `.png` still work
    /// exactly as before), then load the file `url(_:)` found. The result is
    /// cached because a grid of sixty cards would otherwise decode sixty
    /// 1024-pixel JPEGs on every layout pass.
    private static var cache: [String: UIImage?] = [:]

    static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        var loaded = UIImage(named: name)
        if loaded == nil, let url = url(name) {
            loaded = UIImage(contentsOfFile: url.path)
        }
        cache[name] = loaded
        return loaded
    }
}

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
        case .attackHeavy, .castRelease: return 1.7
        case .attackBasic: return 1.3
        case .hitReact: return 0.5
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
    /// Degrees of X rotation needed for the model to stand up. USD exporters
    /// disagree about which axis is up, and a generator's rig can be authored
    /// lying down regardless; `convertToYUp` only fixes the declared case.
    var pitchCorrection: Float = 0
    /// Node names in the rig used as VFX attachment points.
    var weaponAttachNode: String? = nil
    var handAttachNode: String? = "hand_r"
    var chestAttachNode: String? = "spine_03"
    /// Emissive colour used by the rim light and the summon beam.
    var auraHex: String = "#FFFFFF"
    /// Portrait image name in the asset catalogue.
    var portraitName: String
    /// Whether the character closes to strike. A melee unit dashes to its
    /// target for a single-target attack clip and dashes back; a caster or an
    /// archer stays put and its effect crosses the field.
    var melee: Bool = true
    /// Hue, in degrees, of the design's primary costume accent — the colour the
    /// per-element recolour replaces. Gold on every character so far.
    var costumeHue: Float = 45
    /// A shipped model to fight in this one's place, scaled to its height,
    /// until its own mesh lands: a boss whose mesh is still on the way stands
    /// in as a giant of its kind rather than as the loader's primitive.
    var standInAsset: String? = nil

    init(
        assetName: String,
        scale: Float = 1.0,
        height: Float = 1.9,
        yOffset: Float = 0,
        yawCorrection: Float = 0,
        pitchCorrection: Float = 0,
        weaponAttachNode: String? = nil,
        handAttachNode: String? = "hand_r",
        chestAttachNode: String? = "spine_03",
        auraHex: String = "#FFFFFF",
        portraitName: String? = nil,
        melee: Bool = true,
        costumeHue: Float = 45,
        standInAsset: String? = nil
    ) {
        self.assetName = assetName
        self.scale = scale
        self.height = height
        self.yOffset = yOffset
        self.yawCorrection = yawCorrection
        self.pitchCorrection = pitchCorrection
        self.weaponAttachNode = weaponAttachNode
        self.handAttachNode = handAttachNode
        self.chestAttachNode = chestAttachNode
        self.auraHex = auraHex
        self.portraitName = portraitName ?? "portrait_\(assetName)"
        self.melee = melee
        self.costumeHue = costumeHue
        self.standInAsset = standInAsset
    }

    /// The card for a unit in a given state. An awakened unit shows its own
    /// card, `portrait_<id>_awakened.png`, once that file has shipped; until
    /// then it shows the base card, so awakening never blanks a portrait.
    func portraitName(awakened: Bool) -> String {
        guard awakened else { return portraitName }
        let name = portraitName + "_awakened"
        return BundleArt.exists(name) ? name : portraitName
    }

    /// The mesh an awakened unit loads when one has shipped: the base asset's
    /// name with `_awakened`, beside it in the bundle with its own clips. The
    /// loader falls back to the base mesh with the awakened look on it.
    var awakenedAssetName: String { assetName + "_awakened" }
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
    // Greece
    case olympusGate = "olympus_gate"
    case aegeanCliffs = "aegean_cliffs"
    case lernaMarsh = "lerna_marsh"
    // The Norse realms
    case midgardFjord = "midgard_fjord"
    case yggdrasilRoots = "yggdrasil_roots"
    case jotunheimHall = "jotunheim_hall"
    // The Labyrinth's relic dungeons: their own paintings, their pantheon's set
    case colossusVault = "colossus_vault"
    case hydraLair = "hydra_lair"
    case necropolis = "necropolis"

    var displayName: String {
        switch self {
        case .duatGate: return "The First Gate"
        case .reedFields: return "Field of Reeds"
        case .hallOfTwoTruths: return "Hall of Two Truths"
        case .serpentDeep: return "The Serpent Deep"
        case .arenaOfSouls: return "Arena of Souls"
        case .olympusGate: return "The Gate of Olympus"
        case .aegeanCliffs: return "The Aegean Cliffs"
        case .lernaMarsh: return "The Marsh of Lerna"
        case .midgardFjord: return "The Midgard Fjord"
        case .yggdrasilRoots: return "The Roots of Yggdrasil"
        case .jotunheimHall: return "The Hall of Jötunheim"
        case .colossusVault: return "The Vault of the Colossus"
        case .hydraLair: return "The Lair of the Hydra"
        case .necropolis: return "The Necropolis"
        }
    }

    /// The pantheon whose stages these are, for the music and the island.
    var pantheon: Pantheon {
        switch self {
        case .duatGate, .reedFields, .hallOfTwoTruths, .serpentDeep, .arenaOfSouls, .colossusVault, .necropolis: return .egyptian
        case .olympusGate, .aegeanCliffs, .lernaMarsh, .hydraLair: return .greek
        case .midgardFjord, .yggdrasilRoots, .jotunheimHall: return .norse
        }
    }

    /// Scene file to load from `Resources/Environments`, without extension.
    var sceneName: String { rawValue }

    /// The painting to show for this place: its own once it is in the bundle,
    /// and until then the painting of the place it was carved out of, so a
    /// dungeon never shows a grey banner while its own picture is on the way.
    var backdropName: String {
        let own = "\(rawValue)_bg"
        if BundleArt.exists(own) { return own }
        return "\(paintingFallback.rawValue)_bg"
    }

    private var paintingFallback: BattleEnvironment {
        switch self {
        case .colossusVault: return .duatGate
        case .hydraLair: return .lernaMarsh
        case .necropolis: return .hallOfTwoTruths
        default: return self
        }
    }

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
        case .olympusGate: return "#FFF4D6"
        case .aegeanCliffs: return "#FFEFD0"
        case .lernaMarsh: return "#C8D8A0"
        case .midgardFjord: return "#D8E4F0"
        case .yggdrasilRoots: return "#B8E0B0"
        case .jotunheimHall: return "#C8E0FF"
        case .colossusVault: return "#E0C89C"
        case .hydraLair: return "#B8D090"
        case .necropolis: return "#D8C8A8"
        }
    }

    var fogHex: String {
        switch self {
        case .duatGate: return "#4A3A28"
        case .reedFields: return "#3C4A38"
        case .hallOfTwoTruths: return "#5A4C33"
        case .serpentDeep: return "#2A1A38"
        case .arenaOfSouls: return "#6E5A3C"
        case .olympusGate: return "#6A7A9A"
        case .aegeanCliffs: return "#5A7A94"
        case .lernaMarsh: return "#2E3E2C"
        case .midgardFjord: return "#3A4858"
        case .yggdrasilRoots: return "#243A2A"
        case .jotunheimHall: return "#2C3A50"
        case .colossusVault: return "#2C2218"
        case .hydraLair: return "#243424"
        case .necropolis: return "#2A2230"
        }
    }
}

