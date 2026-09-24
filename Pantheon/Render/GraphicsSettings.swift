import Foundation
import SceneKit
import UIKit

/// The three stages whose views the Settings screen's graphics choices reach
/// (`Docs/SETTINGS.md` §2): the fight, the island's living layer and the
/// summon reveal. Every other SceneKit view (the altar, the collection's
/// Stage, the reward chest) keeps its own configuration.
enum RenderStage {
    case battle, island, reveal

    /// The rate each stage drew at before the setting existed, which the
    /// default choice reproduces exactly: the fight and the reveal at 60
    /// (SceneKit's own default, which the reveal never set), the island at a
    /// deliberate 30 — four idling figures over a painting, which a hidden
    /// island once drew as a tax on whatever screen was showing.
    var nativeFramesPerSecond: Int {
        switch self {
        case .battle, .reveal: return 60
        case .island: return 30
        }
    }
}

/// The frame-rate choice: a cap for the battery, the stages' own rates, or
/// ProMotion's 120 where the screen and the app can draw it.
enum FrameRateChoice: Int, CaseIterable {
    case battery = 30
    case standard = 60
    case promotion = 120

    var title: String {
        switch self {
        case .battery: return "30"
        case .standard: return "60"
        case .promotion: return "120"
        }
    }
}

/// Full is the game as designed. Reduced drops the bloom and halves every
/// particle burst or loop of a dozen particles or more; a painted flipbook
/// sheet or a sprite of a few — the effect itself — is never touched.
enum EffectsQuality: String, CaseIterable {
    case full
    case reduced
}

/// The two choices the render thread applies to a live scene.
struct GraphicsChoice: Equatable {
    var effects: EffectsQuality
    var shadows: Bool

    /// The scene exactly as it is built.
    static let asBuilt = GraphicsChoice(effects: .full, shadows: true)

    /// Read off `UserDefaults`, which is safe from any thread.
    static var current: GraphicsChoice {
        GraphicsChoice(effects: GraphicsSettings.effects, shadows: GraphicsSettings.shadows)
    }
}

/// The graphics choices on the Settings screen (`Docs/SETTINGS.md` §2),
/// stored per phone in `UserDefaults` — the Settings pages bind the same keys
/// through `@AppStorage` — and applied through ONE helper, `configure(_:for:)`,
/// where each stage's view is set up. Every default reproduces the look the
/// stages had before the settings existed.
enum GraphicsSettings {
    static let frameRateKey = "graphics.frameRate"
    static let effectsKey = "graphics.effects"
    static let shadowsKey = "graphics.shadows"

    /// The player's frame-rate choice; 120 falls back to 60 where it cannot
    /// be drawn.
    static var frameRate: FrameRateChoice {
        let stored = FrameRateChoice(rawValue: UserDefaults.standard.integer(forKey: frameRateKey)) ?? .standard
        if stored == .promotion && !supportsPromotion { return .standard }
        return stored
    }

    static var effects: EffectsQuality {
        EffectsQuality(rawValue: UserDefaults.standard.string(forKey: effectsKey) ?? "") ?? .full
    }

    /// On unless the player turned them off: the fight's key light and the
    /// reveal's figure throw deferred shadows.
    static var shadows: Bool {
        UserDefaults.standard.object(forKey: shadowsKey) as? Bool ?? true
    }

    /// The Info.plist key without which an iPhone never draws faster than
    /// 60 Hz, whatever a view asks for (Apple, *Optimizing iPhone and iPad
    /// apps to support ProMotion displays*). An iPad Pro needs nothing.
    static let highRateKey = "CADisableMinimumFrameDurationOnPhone"

    /// Whether 120 is worth offering: a ProMotion screen, and on an iPhone
    /// the Info.plist key as well — an option that silently drew at 60 would
    /// be a lie on the Settings screen.
    static var supportsPromotion: Bool {
        guard UIScreen.main.maximumFramesPerSecond > 60 else { return false }
        if UIScreen.main.traitCollection.userInterfaceIdiom == .pad { return true }
        return Bundle.main.object(forInfoDictionaryKey: highRateKey) as? Bool ?? false
    }

    /// The choices a player is offered here.
    static var offeredFrameRates: [FrameRateChoice] {
        supportsPromotion ? FrameRateChoice.allCases : [.battery, .standard]
    }

    /// A stage's rate under a choice: 30 caps every stage, 60 is each
    /// stage's own rate, and 120 raises the fight and the reveal while the
    /// island stays at its ambient 30.
    static func framesPerSecond(for stage: RenderStage, choice: FrameRateChoice) -> Int {
        switch choice {
        case .battery: return FrameRateChoice.battery.rawValue
        case .standard: return stage.nativeFramesPerSecond
        case .promotion: return stage == .island ? stage.nativeFramesPerSecond : FrameRateChoice.promotion.rawValue
        }
    }

    static func framesPerSecond(for stage: RenderStage) -> Int {
        framesPerSecond(for: stage, choice: frameRate)
    }

    /// THE helper. Called once where a stage's view is set up, after its own
    /// render delegate is assigned: sets the frame rate and puts a
    /// `StageRenderGovernor` in front of that delegate, which forwards every
    /// callback to it and applies the effects and shadow choices on the
    /// render thread — and takes them off again when the player turns them
    /// back, so a change reaches the island too, whose view is never rebuilt.
    /// The governor is kept alive by the view (the delegate is weak).
    static func configure(_ view: SCNView, for stage: RenderStage) {
        view.preferredFramesPerSecond = framesPerSecond(for: stage)
        let governor = StageRenderGovernor(stage: stage, inner: view.delegate)
        view.delegate = governor
        objc_setAssociatedObject(view, &governorKey, governor, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static var governorKey: UInt8 = 0
}

/// Comfort: iOS's Reduce Motion, or the game's own switch on the Settings
/// screen. With either on, the fight's camera never shakes, an ultimate's
/// cut-in never flashes the screen white, the skill zoom travels
/// `zoomReach` of its way at a gentler ease, and the cinematic camera's cuts
/// and orbits are held off (`CameraDirector`, `BattleView`).
enum MotionComfort {
    static let key = "comfort.reduceMotion"

    static var isReduced: Bool {
        UIAccessibility.isReduceMotionEnabled || UserDefaults.standard.bool(forKey: key)
    }

    /// The share of its travel the skill zoom keeps under Reduce Motion.
    static let zoomReach: Float = 0.4
    /// How much longer its ease in and out take.
    static let zoomEase: Double = 1.6
}

/// The render delegate a stage view wears once `GraphicsSettings.configure`
/// has seen it. It forwards all six callbacks to the stage's own delegate —
/// the battle's plate layout, every stage's cloth step, the reveal's
/// warm-up — and then, on the render thread, keeps the scene in the
/// player's choice: the bloom of the camera being drawn at zero, every
/// particle system of a dozen or more thinned to half as it appears, every
/// shadow-casting light quiet. What it changes it remembers, and puts back
/// the moment the player returns to Full or turns shadows on. At the
/// defaults it changes nothing and only forwards.
///
/// A new effect is caught in the frame it arrives: VFX hosts are the root's
/// children and their carriers one level down, which a shallow pass reads
/// every frame; anything deeper (a brazier's flame on a prop, a light on a
/// rig) is caught by a full pass twice a second. Everything here runs on
/// the render thread, where SceneKit lets a delegate change the scene.
final class StageRenderGovernor: NSObject, SCNSceneRendererDelegate {
    let stage: RenderStage
    private weak var inner: SCNSceneRendererDelegate?

    /// A system emitting this many particles or more (per burst, or per
    /// second for a loop) is thinned; fewer is a sheet or a few sprites.
    static let thinFrom: CGFloat = 12
    /// The share of its birth rate a thinned system keeps.
    static let thinning: CGFloat = 0.5
    /// Frames between reads of the stored choice, and between full passes.
    private static let readEvery = 10
    private static let deepEvery = 30

    // Render thread only.
    private var applied = GraphicsChoice.asBuilt
    private var wanted = GraphicsChoice.asBuilt
    private var frame = 0
    private let thinnedSystems = NSMapTable<SCNParticleSystem, NSNumber>.weakToStrongObjects()
    private let dimmedCameras = NSMapTable<SCNCamera, NSNumber>.weakToStrongObjects()
    private let quietLights = NSMapTable<SCNLight, NSNumber>.weakToStrongObjects()

    init(stage: RenderStage, inner: SCNSceneRendererDelegate?) {
        self.stage = stage
        self.inner = inner
        super.init()
        Self.adjustLive(stage, by: 1)
    }

    deinit {
        Self.adjustLive(stage, by: -1)
    }

    // MARK: Live views (2026-09-24)
    //
    // A governor is its view's own associated object, so it lives exactly as
    // long as the view: this counts the live battle, island and reveal
    // views. Run 243's summon stress still climbed about 18 MB a reveal
    // with every reveal's stage released ("[Mem] reveal stage released"),
    // and a view SwiftUI let go of that something else kept would hold its
    // render targets and its uploaded textures; `MemoryProbe` prints this
    // on every line, so the next run says whether the views pile up.

    private static let liveLock = NSLock()
    private static var liveCounts: [String: Int] = [:]

    private static func liveName(_ stage: RenderStage) -> String {
        switch stage {
        case .battle: return "battle"
        case .island: return "island"
        case .reveal: return "reveal"
        }
    }

    private static func adjustLive(_ stage: RenderStage, by step: Int) {
        liveLock.lock()
        liveCounts[liveName(stage), default: 0] += step
        liveLock.unlock()
    }

    /// "views battle 0, island 1, reveal 1".
    static func liveViewSummary() -> String {
        liveLock.lock()
        defer { liveLock.unlock() }
        let parts = [RenderStage.battle, .island, .reveal].map { "\(liveName($0)) \(liveCounts[liveName($0), default: 0])" }
        return "views " + parts.joined(separator: ", ")
    }

    // MARK: - Forwarding

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        inner?.renderer?(renderer, updateAtTime: time)
        govern(renderer)
    }

    func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        inner?.renderer?(renderer, didApplyAnimationsAtTime: time)
    }

    func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        inner?.renderer?(renderer, didSimulatePhysicsAtTime: time)
    }

    func renderer(_ renderer: SCNSceneRenderer, didApplyConstraintsAtTime time: TimeInterval) {
        inner?.renderer?(renderer, didApplyConstraintsAtTime: time)
    }

    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        inner?.renderer?(renderer, willRenderScene: scene, atTime: time)
        if applied.effects == .reduced { quietBloom(renderer) }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        inner?.renderer?(renderer, didRenderScene: scene, atTime: time)
    }

    // MARK: - The player's choice

    private func govern(_ renderer: SCNSceneRenderer) {
        frame &+= 1
        if frame % StageRenderGovernor.readEvery == 1 { wanted = GraphicsChoice.current }
        guard let root = renderer.scene?.rootNode else { return }
        if wanted != applied {
            if wanted.effects == .full && applied.effects == .reduced { restoreEffects() }
            if wanted.shadows && !applied.shadows { restoreShadows() }
            applied = wanted
            if applied != GraphicsChoice.asBuilt { sweep(root, deep: true) }
            return
        }
        guard applied != GraphicsChoice.asBuilt else { return }
        sweep(root, deep: frame % StageRenderGovernor.deepEvery == 1)
    }

    private func sweep(_ root: SCNNode, deep: Bool) {
        if deep {
            root.enumerateHierarchy { node, _ in
                self.adjust(node)
            }
            return
        }
        adjust(root)
        for child in root.childNodes {
            adjust(child)
            for grandchild in child.childNodes {
                adjust(grandchild)
            }
        }
    }

    private func adjust(_ node: SCNNode) {
        if applied.effects == .reduced, let systems = node.particleSystems {
            for system in systems {
                thin(system)
            }
        }
        if !applied.shadows, let light = node.light, light.castsShadow {
            light.castsShadow = false
            quietLights.setObject(NSNumber(value: true), forKey: light)
        }
    }

    /// Half the particles of a system of a dozen or more, once.
    private func thin(_ system: SCNParticleSystem) {
        guard thinnedSystems.object(forKey: system) == nil else { return }
        let span: CGFloat = system.emissionDuration > 0 ? system.emissionDuration : 1
        guard system.birthRate * span >= StageRenderGovernor.thinFrom else { return }
        thinnedSystems.setObject(NSNumber(value: Double(system.birthRate)), forKey: system)
        system.birthRate *= StageRenderGovernor.thinning
    }

    private func quietBloom(_ renderer: SCNSceneRenderer) {
        guard let camera = renderer.pointOfView?.camera, camera.bloomIntensity > 0 else { return }
        if dimmedCameras.object(forKey: camera) == nil {
            dimmedCameras.setObject(NSNumber(value: Double(camera.bloomIntensity)), forKey: camera)
        }
        camera.bloomIntensity = 0
    }

    private func restoreEffects() {
        for case let system as SCNParticleSystem in thinnedSystems.keyEnumerator().allObjects {
            if let rate = thinnedSystems.object(forKey: system) {
                system.birthRate = CGFloat(rate.doubleValue)
            }
        }
        thinnedSystems.removeAllObjects()
        for case let camera as SCNCamera in dimmedCameras.keyEnumerator().allObjects {
            if let bloom = dimmedCameras.object(forKey: camera) {
                camera.bloomIntensity = CGFloat(bloom.doubleValue)
            }
        }
        dimmedCameras.removeAllObjects()
    }

    private func restoreShadows() {
        for case let light as SCNLight in quietLights.keyEnumerator().allObjects {
            light.castsShadow = true
        }
        quietLights.removeAllObjects()
    }
}
