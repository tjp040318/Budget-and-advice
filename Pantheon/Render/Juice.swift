import Foundation
import SceneKit
import UIKit

/// How hard a hit lands, for the purpose of feedback. Decided at presentation
/// time from the event and the clip that caused it; the engine knows nothing
/// about any of this.
enum HitWeight {
    /// A glancing blow.
    case light
    /// An ordinary hit.
    case normal
    /// A heavy attack or an ultimate's hit.
    case heavy
    /// A critical.
    case critical
    /// A killing blow.
    case lethal
}

/// Impact feedback — the freeze-frame, the shake, the haptic, the number pop —
/// scaled by how hard the hit was.
///
/// This is most of what separates "watching numbers change" from "hitting
/// something". Every magnitude lives in `profile(for:)` so the feel can be
/// tuned in one place, and everything divides by the playback speed so ×2 stays
/// snappy rather than mushy and skip mode gets none of it.
///
/// The freeze is `SCNScene.isPaused`, which stops every action and animation
/// in the scene for a few frames while the view keeps drawing the last one.
/// That is exactly the classic hit-stop and it costs nothing. The shake fires
/// on release, not on impact — a shake during a freeze is invisible.
enum Juice {

    struct Profile {
        /// Seconds the world freezes on impact.
        var pause: TimeInterval
        /// Camera shake amplitude in metres, and how long it decays.
        var shake: Float
        var shakeDuration: TimeInterval
        /// Haptic, if any.
        var haptic: UIImpactFeedbackGenerator.FeedbackStyle?
        /// Size multiplier for the damage number.
        var numberScale: CGFloat
    }

    static func profile(for weight: HitWeight) -> Profile {
        switch weight {
        case .light:    return Profile(pause: 0.00, shake: 0.00, shakeDuration: 0.00, haptic: nil,     numberScale: 0.85)
        case .normal:   return Profile(pause: 0.045, shake: 0.05, shakeDuration: 0.14, haptic: .light,  numberScale: 1.00)
        case .heavy:    return Profile(pause: 0.075, shake: 0.12, shakeDuration: 0.24, haptic: .medium, numberScale: 1.15)
        case .critical: return Profile(pause: 0.090, shake: 0.16, shakeDuration: 0.28, haptic: .medium, numberScale: 1.40)
        case .lethal:   return Profile(pause: 0.150, shake: 0.22, shakeDuration: 0.40, haptic: .heavy,  numberScale: 1.60)
        }
    }

    /// Above this playback speed the player has asked to skip, not to watch.
    static let skipThreshold: Double = 3.5

    /// Only the most recent freeze may release the scene. Multi-hit skills land
    /// their hits a few frames apart, and without this the first hit's release
    /// would cut the second hit's freeze short.
    private static var pauseGeneration = 0

    /// Plays the impact for a hit. Returns how long the world froze, so the
    /// caller can extend its hold by that much and keep the event cadence.
    @discardableResult
    /// The colour of a hit: what struck, as opposed to how hard.
    ///
    /// The tier alone made every blow the same event at five volumes. A cut,
    /// a mace and a spell are different sounds in any game that feels
    /// expensive, and the files exist for all three plus one per element, so
    /// a hit now plays its weight AND a quieter layer saying what it was.
    enum HitColour {
        case blade, blunt, magic, element(Element)

        var sound: AudioLibrary.Sound {
            switch self {
            case .blade: return .hitBlade
            case .blunt: return .hitBlunt
            case .magic: return .hitMagic
            case .element(let element):
                switch element {
                case .ember: return .impactEmber
                case .tide: return .impactTide
                case .gale: return .impactGale
                case .radiance: return .impactRadiance
                case .umbra: return .impactUmbra
                }
            }
        }
    }

    static func impact(
        _ weight: HitWeight,
        colour: HitColour? = nil,
        scene: SCNScene,
        director: CameraDirector?,
        speed: Double
    ) -> TimeInterval {
        guard speed < skipThreshold else { return 0 }
        let p = profile(for: weight)
        let divisor = max(1.0, speed)

        // The haptic and the sound go with the freeze, not the release: the
        // thumb and the ear should get the hit at the instant the eye sees the
        // world stop.
        if let style = p.haptic { haptic(style) }
        AudioLibrary.shared.play(sound(for: weight))
        // The colour sits under the weight, quieter and a touch later, so the
        // two read as one hit rather than two sounds.
        if let colour {
            AudioLibrary.shared.play(colour.sound, volume: 0.55, delay: 0.02)
        }

        guard p.pause > 0 else {
            if p.shake > 0 { director?.shake(intensity: p.shake, duration: p.shakeDuration / divisor) }
            return 0
        }

        pauseGeneration += 1
        let generation = pauseGeneration
        let pause = p.pause / divisor
        scene.isPaused = true

        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
            guard generation == pauseGeneration else { return }
            scene.isPaused = false
            if p.shake > 0 {
                director?.shake(intensity: p.shake, duration: p.shakeDuration / divisor)
            }
        }
        return pause
    }

    static func sound(for weight: HitWeight) -> AudioLibrary.Sound {
        switch weight {
        case .light: return .hitLight
        case .normal: return .hitNormal
        case .heavy: return .hitHeavy
        case .critical: return .hitCrit
        case .lethal: return .hitLethal
        }
    }

    /// Belt and braces: anything that tears the scene down while a freeze is
    /// pending must not leave it paused.
    static func release(_ scene: SCNScene) {
        pauseGeneration += 1
        scene.isPaused = false
    }

    // MARK: - Haptics

    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static let notifier = UINotificationFeedbackGenerator()

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator: UIImpactFeedbackGenerator
        if let existing = impactGenerators[style] {
            generator = existing
        } else {
            generator = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = generator
        }
        generator.impactOccurred()
    }

    /// Warms the Taptic Engine so the first hit of a cast is not late.
    static func prepareHaptics() {
        for style in [UIImpactFeedbackGenerator.FeedbackStyle.light, .medium, .heavy] {
            if impactGenerators[style] == nil {
                impactGenerators[style] = UIImpactFeedbackGenerator(style: style)
            }
            impactGenerators[style]?.prepare()
        }
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notifier.notificationOccurred(type)
    }

    // MARK: - Number pop

    /// The entrance for a floating number: snaps in oversized, settles, then
    /// the caller's rise-and-fade takes over. A number that simply appears at
    /// full size reads as a label; one that pops reads as a consequence.
    static func popAction(scale: CGFloat) -> SCNAction {
        let overshoot = SCNAction.scale(to: scale * 1.12, duration: 0.07)
        overshoot.timingMode = .easeOut
        let settle = SCNAction.scale(to: scale, duration: 0.06)
        settle.timingMode = .easeInEaseOut
        return .sequence([overshoot, settle])
    }
}
