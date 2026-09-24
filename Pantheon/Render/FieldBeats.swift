import Foundation
import SceneKit
import UIKit

// The beats drawn over the fight (Docs/FEEL.md Wave 2, the battle's lane):
// the ultimate's splash (W2.1), the spotlight round its caster (W2.9), a
// death leaving the field (W2.8), a wave walking on under its stamp (W2.10)
// and a boss's entrance (W2.11). Their numbers live here, in one place for
// the scene (`BattleSceneController`), the view (`BattleView`,
// FieldBeatViews.swift) and the tests (`FieldBeatsTests`); every timing is
// written for ×1 and scaled by the scene's `beat` like every other.

// MARK: - The ultimate's splash (W2.1)

/// When an ultimate owns the screen before it is cast — Settings →
/// Graphics & comfort → Ultimate splash: every time (the default), each
/// unit's first in a fight, or never, for a player farming on auto. Stored
/// under `UltimateSplash.key` as its raw value, beside the cinematic
/// camera's switch.
enum SplashChoice: String, CaseIterable, Sendable {
    case always
    case first
    case off
}

/// How much of the splash plays at the player's speed (W1.1's rule: ×2 is
/// every length halved, ×3 keeps the beat's essence).
enum SplashForm: Equatable, Sendable {
    /// ×1: the band, the card, the name.
    case full
    /// ×2: the same at half its length.
    case brisk
    /// ×3: the name alone, flashed.
    case flash
}

/// The splash's numbers.
enum UltimateSplash {
    /// The `UserDefaults` key of the player's `SplashChoice`.
    static let key = "ultimateSplash"

    /// Its length at each speed: 0.9 s, 0.45 s, and a 0.3-s name flash.
    static let fullLength: TimeInterval = 0.9
    static let briskLength: TimeInterval = 0.45
    static let flashLength: TimeInterval = 0.3

    /// Where the name lands, as a share of the splash — the sting and the
    /// heavy haptic with it. A flash's name is there almost at once.
    static let nameLandsAt: Double = 0.34
    static let flashLandsAt: Double = 0.15
    /// How far the field darkens under the band, and under a flash.
    static let fieldShade: Double = 0.55
    static let flashShade: Double = 0.35
    /// The band: its height over the screen's, how far it leans, and the
    /// skill's name carved on it.
    static let bandShare: CGFloat = 0.6
    static let bandLeanDegrees: Double = 12
    static let nameSize: CGFloat = 34
    /// The pixels the caster's card is decoded at ahead of its splash
    /// (`BundleArt`'s largest bucket: a band 60% of a landscape phone's
    /// height, at three pixels a point, asks for it).
    static let cardPixels = 1_024

    /// The player's choice. Always under the CI tour, so every run's frames
    /// are drawn the same way whatever the simulator last remembered.
    static func choice(in defaults: UserDefaults = .standard) -> SplashChoice {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-tour") { return .always }
        #endif
        guard let raw = defaults.string(forKey: key), let chosen = SplashChoice(rawValue: raw) else { return .always }
        return chosen
    }

    /// Whether an ultimate owns the screen: `castBefore` is whether its
    /// caster's ultimate already has in this fight.
    static func plays(_ choice: SplashChoice, castBefore: Bool) -> Bool {
        switch choice {
        case .always: return true
        case .first: return !castBefore
        case .off: return false
        }
    }

    static func form(speed: Double) -> SplashForm {
        if Juice.isFast(speed) { return .flash }
        if speed > 1.5 { return .brisk }
        return .full
    }

    static func duration(of form: SplashForm) -> TimeInterval {
        switch form {
        case .full: return fullLength
        case .brisk: return briskLength
        case .flash: return flashLength
        }
    }

    /// Seconds from the splash's start to its name landing.
    static func landing(of form: SplashForm) -> TimeInterval {
        switch form {
        case .full, .brisk: return duration(of: form) * nameLandsAt
        case .flash: return duration(of: form) * flashLandsAt
        }
    }

    // The band's curves, each a share of the splash from 0 to 1.

    /// How far the band has wiped across: 0 gone at the left, 1 whole, 2
    /// gone to the right. In over the first 22%, out over the last 20%.
    static func sweep(at progress: Double) -> Double {
        if progress < 0.22 { return FieldClock.ease(progress / 0.22) }
        if progress < 0.8 { return 1 }
        return 1 + FieldClock.ease((progress - 0.8) / 0.2)
    }

    /// The dark over the field: up over the first 12%, down over the last.
    static func shade(at progress: Double, form: SplashForm) -> Double {
        let depth: Double = form == .flash ? flashShade : fieldShade
        return depth * envelope(at: progress, rise: 0.12, fall: 0.12)
    }

    /// The card sliding in behind the wipe.
    static func cardIn(at progress: Double) -> Double {
        FieldClock.ease((progress - 0.06) / 0.26)
    }

    /// The name: nothing until it lands, then in over 8% of the splash.
    static func nameIn(at progress: Double) -> Double {
        guard progress >= nameLandsAt else { return 0 }
        return FieldClock.ease((progress - nameLandsAt) / 0.08)
    }

    /// Up over `rise` and down over the last `fall` of the splash: the
    /// flash's whole life, and the band's under Reduce Motion, which fades
    /// where the wipe would travel.
    static func envelope(at progress: Double, rise: Double, fall: Double) -> Double {
        let coming: Double = FieldClock.ease(progress / max(0.001, rise))
        let going: Double = FieldClock.ease((1 - progress) / max(0.001, fall))
        return min(coming, going)
    }
}

/// The clock a beat drawn over the field keeps: its own seconds since it
/// appeared, held at `holdAt` for `frozenFor` more under a CI frame's hold
/// (0 everywhere else), then running on.
enum FieldClock {
    static func time(elapsed: TimeInterval, holdAt: TimeInterval, frozenFor: TimeInterval) -> TimeInterval {
        guard frozenFor > 0, elapsed > holdAt else { return elapsed }
        return elapsed < holdAt + frozenFor ? holdAt : elapsed - frozenFor
    }

    /// Smoothstep, clamped.
    static func ease(_ value: Double) -> Double {
        let clamped: Double = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }
}

// MARK: - The cues (scene → view)

/// An ultimate's splash for the battle view to draw, told the moment the
/// scene holds the world for it (`BattleSceneController.onFieldCue`).
struct UltimateSplashCue: Equatable {
    /// Counts up through a fight: an end that arrives for an older splash
    /// never takes down a newer one.
    let serial: Int
    let portrait: String
    let unitName: String
    let skillName: String
    let accentHex: String
    let form: SplashForm
    /// Its length, and how long it stands at its middle for a CI frame (0
    /// but under the tour's `-tour-cutin`).
    let duration: TimeInterval
    let frozenFor: TimeInterval
}

/// A wave's stamp (W2.10): WAVE 2, or FINAL WAVE.
struct WaveStampCue: Equatable {
    let serial: Int
    let wave: Int
    let count: Int
    let duration: TimeInterval
    let frozenFor: TimeInterval

    var isFinal: Bool { wave >= count }
    var word: String { isFinal ? "FINAL WAVE" : "WAVE \(wave)" }
}

/// A boss's entrance (W2.11); the view asks the model for its ribbon's
/// words (`BattleViewModel.entranceCard(for:)`).
struct BossEntranceCue: Equatable {
    let serial: Int
    let bossID: UUID
}

/// What the scene tells the battle view about the beats drawn over the
/// field, in order, on the main thread.
enum FieldCue {
    /// The world is held for an ultimate's splash.
    case splash(UltimateSplashCue)
    /// That splash has let go (its serial).
    case splashEnded(Int)
    /// A new wave's stamp.
    case waveStamp(WaveStampCue)
    /// A boss begins its entrance: the HUD goes.
    case bossEntrance(BossEntranceCue)
    /// It roars: its ribbon lands and its bar fills from empty.
    case bossRibbon(Int)
    /// The entrance is over: the HUD comes back.
    case entranceEnded(Int)
    /// Everything down at once: a skip, a forfeit, a new run.
    case clear
}

// MARK: - A wave walking on (W2.10)

enum WaveStamp {
    /// The stamp's length at ×1; at ×2 and ×3 half of it (at ×3 it is the
    /// only part of a wave's arrival that plays).
    static let fullLength: TimeInterval = 1.3
    /// Where the word lands, with its drum, as a share of its length.
    static let landsAt: Double = 0.22

    static func length(speed: Double) -> TimeInterval {
        speed > 1.5 ? fullLength / 2 : fullLength
    }

    /// Whether a `.waveStarted` wears the stamp: only a NEW wave — later
    /// than `onField`, the one the field is already on — and only one with no
    /// boss, whose entrance announces it instead. A raid's guard coming back
    /// is reported under the wave the fight is on (`BattleEngine.summonGuard`)
    /// and was stamped FINAL WAVE, with its drum, every time (review,
    /// 2026-09-24).
    static func stamps(wave: Int, onField: Int, bossArrives: Bool) -> Bool {
        wave > onField && !bossArrives
    }

    /// Where the word stands across the screen, in widths: in from the
    /// right until it lands, a slow drift, then away to the left.
    static func travel(at progress: Double) -> Double {
        if progress < landsAt { return 0.6 * (1 - FieldClock.ease(progress / landsAt)) }
        if progress < 0.75 { return -0.03 * (progress - landsAt) / (0.75 - landsAt) }
        return -0.03 - 0.7 * FieldClock.ease((progress - 0.75) / 0.25)
    }

    /// The band under it: up quickly, down over the last fifth.
    static func opacity(at progress: Double) -> Double {
        UltimateSplash.envelope(at: progress, rise: 0.12, fall: 0.2)
    }
}

enum WalkOn {
    /// Metres behind its mark an arrival starts (`place`'s two since
    /// 2026-09-24, measured clear of every set's pieces).
    static let distance: Float = 2.0
    /// Meshy's Casual Walk, in metres a second for a figure of a hero's
    /// 1.9 m — the island's own stroll (`IslandSceneView.wanderSpeed`) —
    /// and in proportion to height, since a taller figure's stride is longer
    /// at the same cadence; a slide past this reads as skating.
    static let stroll: Double = 1.05
    static let heroHeight: Float = 1.9
    /// The fade up out of the far set, and the breath after the arrival
    /// before the next turn.
    static let fadeIn: TimeInterval = 0.35
    static let settle: TimeInterval = 0.2

    static func speed(height: Float) -> Double {
        let tall: Double = Double(max(0.8, height))
        let scaled: Double = stroll * tall / Double(heroHeight)
        return min(2.2, scaled)
    }

    /// Seconds at ×1 to walk `distance` metres.
    static func duration(distance: Float, height: Float) -> TimeInterval {
        Double(distance) / speed(height: height)
    }

    /// An arrival walks when its rig shipped a walk and the fight is not at
    /// ×3; otherwise it slides on as it always did (no clip), or fades up
    /// on its mark (×3).
    static func walks(hasClip: Bool, speed: Double) -> Bool {
        hasClip && !Juice.isFast(speed)
    }
}

// MARK: - A death leaving the field (W2.8)

enum Dissolve {
    /// The body's fade once its death clip has played.
    static let fade: TimeInterval = 0.7
    /// The soul light: how far it lifts and how long it takes.
    static let soulRise: Float = 2.0
    static let soulFlight: TimeInterval = 1.0
    /// The glyph left on the mark: faint, and fainter on the pale marble
    /// (`StageBuilder.isPaleSet`), where anything added to the floor blows.
    static let markOpacity: CGFloat = 0.38
    static let paleMarkShare: CGFloat = 0.6
    static let markFade: TimeInterval = 0.6
    /// A boss sinking back below the rim: how long, and how far (a share of
    /// its height).
    static let bossSink: TimeInterval = 1.6
    static let bossDepth: Float = 0.9

    /// The soul light rises only where motion is welcome and time allows:
    /// never under Reduce Motion, never at ×3.
    static func showsSoulLight(speed: Double, calm: Bool) -> Bool {
        !calm && !Juice.isFast(speed)
    }
}

// MARK: - A boss's entrance (W2.11)

enum BossEntrance {
    /// The whole entrance at ×1, and when in it the boss ROARS: the rise is
    /// everything before.
    static let length: TimeInterval = 2.4
    static let roarAt: TimeInterval = 1.2
    /// How far under the rim it starts.
    static let depth: Float = 4.5
    /// The ground under the team as it climbs, and the roar's shake.
    static let rumble: Float = 0.05
    static let roarShake: Float = 0.3
    static let roarShakeLength: TimeInterval = 0.6
    /// The breath after it before the first turn.
    static let settle: TimeInterval = 0.15
}

// MARK: - The spotlight (W2.9, and the entrance's dim)

/// What the set is dimmed to.
enum SpotlightLook: Equatable, Sendable {
    /// An ultimate's wind-up: the set's lights at 35%, the painting at 0.45
    /// of itself, the colour 0.35 down; the figures keep their light.
    case ultimate
    /// A boss's entrance: the key light down 40%, nothing else.
    case bossEntrance
}

/// The lights' shares of their rest at one moment.
struct SpotlightShares: Equatable {
    /// The shared key, and the figures' own key making up what it lost.
    var key: CGFloat
    var figureKey: CGFloat
    /// The set's fill, ambient and braziers.
    var setLights: CGFloat
    /// The painting's diffuse intensity (`Spotlight.backdropRest` at rest).
    var backdrop: CGFloat
    /// How far the camera's saturation is taken down.
    var desaturation: CGFloat
}

enum Spotlight {
    static let setShare: CGFloat = 0.35
    static let backdropShare: CGFloat = 0.45
    static let desaturation: CGFloat = 0.35
    static let entranceKeyShare: CGFloat = 0.6
    /// The painting's intensity at rest: a hair under 1, set when the stage
    /// is built. SceneKit draws a property at exactly 1 without the
    /// multiply, so the first dim away from 1 would build a new shader in
    /// the middle of an ultimate; from 0.999 it only changes a number.
    static let backdropRest: CGFloat = 0.999
    /// The figures' key at rest, a share of the key's: never nothing, for
    /// the same reason — a light lit from nothing mid-fight changes every
    /// figure material's light list.
    static let figureKeyIdle: CGFloat = 0.001
    /// The dim's way in, and its way out after the blow.
    static let attack: TimeInterval = 0.18
    static let releaseAfterBlow: TimeInterval = 0.4
    /// The longest a dim holds unreleased (a lost release never leaves the
    /// set dark).
    static let longest: TimeInterval = 6

    static let rest = SpotlightShares(key: 1, figureKey: 0, setLights: 1, backdrop: Spotlight.backdropRest, desaturation: 0)

    static func shares(for look: SpotlightLook, level: Double) -> SpotlightShares {
        let amount = CGFloat(min(1, max(0, level)))
        switch look {
        case .ultimate:
            let lost: CGFloat = (1 - setShare) * amount
            let painting: CGFloat = backdropRest - (backdropRest - backdropShare) * amount
            return SpotlightShares(key: 1 - lost, figureKey: lost, setLights: 1 - lost, backdrop: painting,
                                   desaturation: desaturation * amount)
        case .bossEntrance:
            let key: CGFloat = 1 - (1 - entranceKeyShare) * amount
            return SpotlightShares(key: key, figureKey: 0, setLights: 1, backdrop: backdropRest, desaturation: 0)
        }
    }
}

/// One dim of the set on the wall clock: in over `attack`, held until it is
/// released (or `longest` after it began), out over `release`. Read on the
/// renderer's thread (`BattleSceneController.renderUpdate`), so it runs
/// through a hit's freeze as light does.
struct SpotlightTimeline {
    let look: SpotlightLook
    let began: CFTimeInterval
    let attack: TimeInterval
    let longest: TimeInterval
    var release: TimeInterval
    var releasedAt: CFTimeInterval? = nil

    /// When it starts to come back up.
    var letGo: CFTimeInterval { releasedAt ?? (began + longest) }

    func level(at now: CFTimeInterval) -> Double {
        let upTo: CFTimeInterval = min(now, letGo)
        let rise: Double = FieldClock.ease((upTo - began) / max(0.001, attack))
        guard now > letGo else { return rise }
        let fall: Double = FieldClock.ease((now - letGo) / max(0.001, release))
        return rise * (1 - fall)
    }

    func isOver(at now: CFTimeInterval) -> Bool {
        now >= letGo + release
    }
}

/// A multiplier the set's flickering lights read on every frame
/// (`StageBuilder.brazier`), so a dim of the set is not undone by a flicker
/// writing its own level. Locked: the flicker reads it on the renderer's
/// thread.
final class SetLightDimmer {
    private let lock = NSLock()
    private var stored: Double = 1

    var level: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}

/// The lights a spotlight turns down, and where each stands at rest,
/// gathered when the stage is built (`BattleSceneController`). Written on
/// the renderer's thread only, in `renderer(_:updateAtTime:)`.
final class SpotlightRig {
    private weak var key: SCNLight?
    private weak var figureKey: SCNLight?
    private weak var fill: SCNLight?
    private weak var ambient: SCNLight?
    private weak var backdrop: SCNMaterial?
    private weak var camera: SCNCamera?
    private let dimmer: SetLightDimmer
    private let keyRest: CGFloat
    private let fillRest: CGFloat
    private let ambientRest: CGFloat
    private let saturationRest: CGFloat

    init(key: SCNLight, figureKey: SCNLight, fill: SCNLight, ambient: SCNLight, backdrop: SCNMaterial?,
         camera: SCNCamera?, dimmer: SetLightDimmer) {
        self.key = key
        self.figureKey = figureKey
        self.fill = fill
        self.ambient = ambient
        self.backdrop = backdrop
        self.camera = camera
        self.dimmer = dimmer
        keyRest = key.intensity
        fillRest = fill.intensity
        ambientRest = ambient.intensity
        saturationRest = camera?.saturation ?? 1
    }

    /// The lights at `shares` of their rest; the camera's colour too when
    /// it is the spotlight's to write (`grade`).
    func apply(_ shares: SpotlightShares, grade: Bool) {
        key?.intensity = keyRest * shares.key
        figureKey?.intensity = keyRest * max(Spotlight.figureKeyIdle, shares.figureKey)
        fill?.intensity = fillRest * shares.setLights
        ambient?.intensity = ambientRest * shares.setLights
        backdrop?.diffuse.intensity = shares.backdrop
        dimmer.level = Double(shares.setLights)
        if grade { camera?.saturation = max(0, saturationRest - shares.desaturation) }
    }
}
