import Foundation
import SceneKit

/// The light the figure stages share (2026-09-18): the summon reveal, the
/// Hall of Ka's altar and the collection's Stage.
///
/// Until this, each of the three lit its figure with four lights and nothing
/// else — no environment, so a metal the surface shader marks had nothing to
/// reflect and the shadow side of a figure was whatever the ambient gave it,
/// and no shadow, so a helmet did not shade a face nor an arm a torso — on a
/// half-Lambert ramp that gave a face turned fully away from a light 30% of
/// it. The owner's frames of the awakened Ares and of Sekhmet on the beam
/// were "the renders all fucked up", and `tools/preview.py`, plain Lambert on
/// the same meshes, drew sculpture. Three things put it right, and they go
/// together: the Lambert ramp in `MaterialTuner` (ModelLibrary.swift), the
/// studio environment map here (`tools/studio_ibl.py`: a cool sky, a cream
/// horizon, warm dark ground, two softboxes), and a shadow-casting key with
/// only the FIGURE casting — the beam, the mist, the rune ring and the
/// contact shadow are additive or painted quads and would throw solid black
/// shapes of their own across the dais, which is why the reveal never had a
/// shadow before.
enum FigureStageLighting {
    /// The studio map's strength: enough to lift the shadow side and give
    /// gold a reflection, not enough to flatten the key.
    static var environmentIntensity: CGFloat { lab == .previous ? 0.5 : 1.0 }

    /// The rig's numbers, shared so the three stages light a figure the same.
    /// The Lambert ramp gives away the half-Lambert's free 30%, so the key is
    /// a little stronger than the 780–820 it was; the ambient is lower because
    /// the environment now does its job.
    ///
    /// Raised on 2026-09-22 (PLAN.md, *The figure on the phone*): under the
    /// 1.85 white point the rig of 2026-09-18 (key 900, environment 0.5)
    /// lit a figure to about six tenths of white, and the owner's phone
    /// frame of Anhur was a grey-brown man beside gold pillars while his
    /// texture is a red tunic and white sleeves. The `previous` lab variant
    /// is that rig, photographed beside this one every run.
    static var keyIntensity: CGFloat { lab == .previous ? 900 : 1150 }
    static var fillIntensity: CGFloat { lab == .previous ? 240 : 320 }
    static var rimIntensity: CGFloat { lab == .previous ? 400 : 420 }
    static var ambientIntensity: CGFloat { lab == .previous ? 100 : 140 }

    /// How far the key light's colour is pulled from the element's tint
    /// toward white: 0.82 left an ember unit's key peach, and Anhur's white
    /// sleeves tan; the rim keeps the element's colour whole.
    static var keyTintMix: CGFloat { lab == .previous ? 0.82 : 0.92 }

    /// The paint's saturation in the surface shader: 0.85 tempered every
    /// texture on 2026-09-20 and the owner read grey; the physically based
    /// shading is what tempers a cartoon now, and the boards he judged the
    /// roster on draw the textures as painted.
    static var paintSaturation: Double { lab == .previous ? 0.85 : 1.0 }

    /// Whether a real metalness map's metal takes a lower roughness
    /// (`MaterialTuner.surfaceModifier`): Meshy paints gold at 0.5, which
    /// is satin, and satin gold beside a matte tunic is tan paint.
    static var metalShine: Bool { lab != .previous }

    /// `scene.lightingEnvironment` from the studio map, unless the lab asks
    /// for the bare rig.
    static func applyEnvironment(to scene: SCNScene) {
        // The map of 2026-09-18 is kept as `studio_ibl_v1` for the lab's
        // `previous` variant; `studio_ibl` has brighter softboxes and sky
        // since 2026-09-22, so gold has something to reflect.
        let name = lab == .previous ? "studio_ibl_v1" : "studio_ibl"
        guard lab != .bare,
              let url = Bundle.main.url(forResource: name, withExtension: "png")
                ?? Bundle.main.url(forResource: "studio_ibl", withExtension: "png") else { return }
        scene.lightingEnvironment.contents = url
        scene.lightingEnvironment.intensity = environmentIntensity
    }

    /// Makes a key light cast a soft deferred shadow (the battle's settings),
    /// unless the lab asks for the bare rig.
    static func castShadows(from key: SCNLight) {
        guard lab != .bare else { return }
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        key.shadowColor = UIColor.black.withAlphaComponent(0.55)
        key.maximumShadowDistance = 30
        key.automaticallyAdjustsShadowProjection = true
    }

    /// Only the figure casts a shadow: every other node in the scene is a
    /// set piece, a painted quad or an effect. Call it after anything is
    /// added to the scene — the beam and the contact shadow arrive at the
    /// reveal, after the figure.
    static func restrictShadows(in scene: SCNScene, to figure: SCNNode?) {
        scene.rootNode.enumerateHierarchy { node, _ in node.castsShadow = false }
        figure?.enumerateHierarchy { node, _ in node.castsShadow = true }
    }

    /// The camera's exposure for the lab's darker variant; zero otherwise.
    static var exposureOffset: CGFloat { lab == .dark ? -0.4 : 0 }

    /// The CI lab (DEBUG only): `-tour-reveal-lab dark` photographs the rig
    /// two thirds of a stop under, `-tour-reveal-lab bare` photographs the
    /// Lambert ramp with no environment and no shadow; with `-tour-shading
    /// legacy` beside it, `bare` is the render of 2026-09-17, the control.
    enum Lab { case none, dark, bare, previous }
    static var lab: Lab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-reveal-lab"), at + 1 < args.count else { return .none }
        switch args[at + 1] {
        case "dark": return .dark
        case "previous": return .previous
        case "bare": return .bare
        default: return .none
        }
        #else
        return .none
        #endif
    }
}
