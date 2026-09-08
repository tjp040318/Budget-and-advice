import Foundation
import SceneKit
import simd
import UIKit

/// Loads and caches character models.
///
/// The lookup order is deliberate: a real exported model wins, a `.scn`
/// conversion is next, and a procedural stand-in is last. That last step is what
/// lets the whole game be playable today with zero art in the bundle — a missing
/// `anubis.usdz` produces a correctly-sized, correctly-tinted placeholder that
/// animates, takes hits and dies, so combat, cameras and UI can all be built and
/// tested before the first model lands.
///
/// See `Docs/ART_PIPELINE.md` for the export contract.
final class ModelLibrary {

    static let shared = ModelLibrary()

    /// Subdirectory inside the bundle where character models live.
    static let modelDirectory = "Models"
    /// Extensions tried in order.
    static let searchExtensions = ["usdz", "usdc", "scn", "dae"]

    /// Untinted source nodes, keyed by asset name. A real export is one shared
    /// mesh for a whole elemental family, so the source is kept neutral and the
    /// element colour is applied per instance below.
    private var cache: [String: SCNNode] = [:]
    /// Assets whose auto-orientation has already been reported, so the log
    /// says it once rather than once per instance.
    private var orientationLogged: Set<String> = []
    /// Placeholders build themselves in their element's colour, so they are
    /// cached per colour — otherwise the first variant to be created would set
    /// the colour for all five.
    private var placeholderCache: [String: SCNNode] = [:]
    private var animationCache: [String: [AnimationClip: CAAnimation]] = [:]
    private let queue = DispatchQueue(label: "com.pantheon.modellibrary", attributes: .concurrent)

    private init() {}

    // MARK: - Public API

    /// How much geometry to ask for.
    ///
    /// A raw conversion is heavy — the first Anubis landed near 200k triangles,
    /// which is fine for one character on a summon screen and far too much for
    /// ten of them behind a bloom and ambient-occlusion pass. Rather than force
    /// the art down to the worst case, the loader will use `<asset>_lod.usdz`
    /// when one exists and the stage is crowded, and silently fall back to the
    /// full model when it does not. Shipping the low-detail export is therefore
    /// optional and can happen long after the character does.
    enum DetailLevel: String {
        case high
        case low

        /// Suffix appended to the asset name when looking for the file.
        var suffix: String { self == .low ? "_lod" : "" }
    }

    /// Below this many combatants, everything renders at full detail.
    static let crowdedStageThreshold = 4

    static func detail(forCombatantCount count: Int) -> DetailLevel {
        count > crowdedStageThreshold ? .low : .high
    }

    /// Returns a fresh copy of the model for a spec, ready to be added to a scene.
    /// Always returns a node — never nil — so the renderer has no missing-asset path.
    func node(
        for spec: ModelSpec,
        archetype: Archetype,
        element: Element,
        detail: DetailLevel = .high
    ) -> SCNNode {
        let container = SCNNode()
        container.name = "unit_\(spec.assetName)"

        // Ask for the reduced mesh first when the stage is busy, but never fail
        // over it: a missing `_lod` file just means the full model is used.
        let assetName = detail == .low && bundleURL(for: spec.assetName + DetailLevel.low.suffix) != nil
            ? spec.assetName + DetailLevel.low.suffix
            : spec.assetName

        let model: SCNNode
        var isStandIn = false
        /// A stand-in that is a portrait sprite rather than the primitive rig.
        var isPortraitSprite = false
        if let cached = cache[assetName] {
            model = cached.clone()
            MaterialTuner.applyElementTint(model, hex: spec.auraHex)
        } else if let loaded = loadFromBundle(assetName) {
            cache[assetName] = loaded
            model = loaded.clone()
            MaterialTuner.applyElementTint(model, hex: spec.auraHex)
        } else {
            isStandIn = true
            isPortraitSprite = UIImage(named: spec.portraitName + "_cut") != nil
                || UIImage(named: spec.portraitName) != nil
            let key = spec.assetName + "|" + spec.auraHex
            let placeholder = placeholderCache[key]
                ?? PlaceholderRig.make(spec: spec, archetype: archetype, element: element)
            placeholderCache[key] = placeholder
            model = placeholder.clone()
        }

        model.name = "model"
        container.addChildNode(model)

        // A real export gets stood up from its bounding box — whichever axis
        // the exporter used for height becomes +Y, feet on the ground — before
        // the hand-tuned corrections are applied on top. Placeholders are
        // built upright and skip it.
        if !isStandIn {
            let note = ModelOrientation.normalise(model, in: container, targetHeight: spec.height)
            if !orientationLogged.contains(assetName) {
                orientationLogged.insert(assetName)
                log("'\(assetName)': \(note)")
            }
        }
        // Overrides are rotations about the CONTAINER's axes, applied on top of
        // whatever standUp set. Adding to eulerAngles would not do that once
        // the node already carries a rotation — Euler components do not
        // compose — so they are pre-multiplied as quaternions instead.
        if spec.yawCorrection != 0 || spec.pitchCorrection != 0 {
            let yaw = simd_quatf(angle: spec.yawCorrection * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
            let pitch = simd_quatf(angle: spec.pitchCorrection * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
            model.simdOrientation = yaw * pitch * model.simdOrientation
        }
        model.position.y += spec.yOffset

        // The archetype scale applies to the STAND-IN ONLY. Placeholders are all
        // built to one size and lean on it to tell a Titan from a Spirit. A real
        // export is authored at its true height — the table in
        // Docs/ART_PIPELINE.md — so scaling it again would make every god 15%
        // too tall and every primordial 60%.
        // The archetype scale is a property of the PRIMITIVE rig, which is
        // built at one size and leans on it to tell a Titan from a Spirit. A
        // real export and a portrait sprite are both already authored at the
        // unit's true height, so scaling either again is simply wrong.
        let scale = spec.scale * (isStandIn && !isPortraitSprite ? archetype.modelScale : 1.0)
        model.scale = SCNVector3(scale, scale, scale)
        return container
    }

    /// Whether a real model exists for a spec. The debug overlay shows this so
    /// it is obvious which characters are still placeholders.
    func hasRealModel(_ assetName: String) -> Bool {
        bundleURL(for: assetName) != nil
    }

    /// Animation for a clip, if the export provided one.
    ///
    /// Two layouts are supported: all clips inside one file (animation players
    /// keyed by clip name), or one file per clip named `<unit>_<clip>.usdz`.
    func animation(_ clip: AnimationClip, for assetName: String) -> CAAnimation? {
        if let cached = animationCache[assetName]?[clip] { return cached }

        var found: CAAnimation?

        // Layout A: separate file per clip.
        if let url = bundleURL(for: "\(assetName)_\(clip.rawValue)"),
           let scene = try? SCNScene(url: url, options: [.animationImportPolicy: SCNSceneSource.AnimationImportPolicy.playRepeatedly]) {
            found = firstAnimation(in: scene.rootNode)
        }

        // Layout B: one file, many animation players.
        if found == nil, let url = bundleURL(for: assetName),
           let source = SCNSceneSource(url: url, options: nil) {
            let identifiers = source.identifiersOfEntries(withClass: CAAnimation.self)
            let match = identifiers.first { $0.lowercased().contains(clip.rawValue) }
            if let match, let animation = source.entryWithIdentifier(match, withClass: CAAnimation.self) {
                found = animation
            }
        }

        if let found {
            found.repeatCount = clip.loops ? .greatestFiniteMagnitude : 1
            found.isRemovedOnCompletion = !clip.loops
            found.fadeInDuration = 0.15
            found.fadeOutDuration = 0.25
            animationCache[assetName, default: [:]][clip] = found
        }
        return found
    }

    /// Warms the cache off the main thread before a battle starts.
    func preload(_ specs: [ModelSpec], completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            for spec in specs {
                _ = self.bundleURL(for: spec.assetName)
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: - Loading

    private func bundleURL(for name: String) -> URL? {
        for ext in Self.searchExtensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: Self.modelDirectory) {
                return url
            }
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private func loadFromBundle(_ name: String) -> SCNNode? {
        guard let url = bundleURL(for: name) else {
            log("no file in the bundle for '\(name)' — falling back to a placeholder")
            return nil
        }
        let scene: SCNScene
        do {
            // Never `try?` here. A model that is present but unreadable and a
            // model that was never copied into the bundle produce the same grey
            // stand-in on screen, and only the error tells them apart.
            scene = try SCNScene(url: url, options: [
                .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.doNotPlay,
                .convertToYUp: true,
                .createNormalsIfAbsent: true
            ])
        } catch {
            log("'\(name)' is in the bundle at \(url.lastPathComponent) but SceneKit "
                + "could not open it: \(error.localizedDescription)")
            return nil
        }

        let wrapper = SCNNode()
        for child in scene.rootNode.childNodes {
            wrapper.addChildNode(child)
        }
        MaterialTuner.tune(wrapper)
        return wrapper
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[ModelLibrary] \(message)")
        #endif
    }

    /// Prints what the bundle actually contains against what the roster asks
    /// for. Called once at launch in debug builds, because "the character is
    /// grey" has two very different causes — the file was never copied into the
    /// app, or it was copied and will not load — and they are indistinguishable
    /// on screen.
    func diagnose(expecting assetNames: [String]) {
        #if DEBUG
        let root = Bundle.main.bundleURL
        let found = (try? FileManager.default.subpathsOfDirectory(atPath: root.path))?
            .filter { path in Self.searchExtensions.contains((path as NSString).pathExtension) }
            .sorted() ?? []

        log("bundle: \(root.path)")
        log("3D files actually inside the app: \(found.isEmpty ? "NONE" : "\(found.count)")")
        for path in found { log("    \(path)") }

        for name in assetNames.sorted() {
            if let url = bundleURL(for: name) {
                log("  OK       \(name) -> \(url.lastPathComponent)")
            } else {
                log("  MISSING  \(name) — will render as a placeholder")
            }
        }
        #endif
    }

    private func firstAnimation(in node: SCNNode) -> CAAnimation? {
        for key in node.animationKeys {
            // `SCNAnimationPlayer.animation` is an `SCNAnimation`, not a
            // `CAAnimation`; the bridging initialiser is the way across.
            if let player = node.animationPlayer(forKey: key) {
                return CAAnimation(scnAnimation: player.animation)
            }
        }
        for child in node.childNodes {
            if let found = firstAnimation(in: child) { return found }
        }
        return nil
    }
}

/// Applies the project's look to imported materials.
///
/// Imported PBR from a generator arrives with wildly varying roughness and no
/// consistent response to the environment map. Rather than asking the art side
/// to hand-tune every export, the renderer clamps the range that reads badly
/// under the stage lighting and forces physically-based shading on everything.
enum MaterialTuner {
    static func tune(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry else { return }
            for material in geometry.materials {
                material.lightingModel = .physicallyBased
                material.isDoubleSided = false

                // Fully rough or fully smooth both look wrong under IBL.
                if material.roughness.contents == nil {
                    material.roughness.contents = 0.55
                } else if let value = material.roughness.contents as? NSNumber {
                    material.roughness.contents = min(0.95, max(0.35, value.doubleValue))
                }
                // A fully metallic surface lit by a flat-colour environment
                // becomes a mirror of that colour: the figure goes chrome and
                // the midtones blow out to white. Meshy ships metalness 1.0 on
                // plenty of materials, so clamp rather than only defaulting.
                if let value = material.metalness.contents as? NSNumber {
                    material.metalness.contents = min(0.25, value.doubleValue)
                } else if material.metalness.contents == nil {
                    material.metalness.contents = 0.0
                }
                material.normal.wrapS = .repeat
                material.normal.wrapT = .repeat
                material.diffuse.wrapS = .repeat
                material.diffuse.wrapT = .repeat
                material.diffuse.mipFilter = .linear
            }
        }
    }

    /// Tints one instance of a shared model toward its element colour.
    ///
    /// This is the thing that turns one export into five characters, and it
    /// takes two passes because one is not enough on a dark character.
    ///
    /// **Multiply** handles the light areas. The wash is mostly white — a
    /// full-strength multiply would flatten the gold, the lapis and the white
    /// linen into a single colour, whereas about a third keeps the material
    /// identity and still reads, across a board, as "the fire one".
    ///
    /// **Emission** handles the dark areas, and it is the reason both exist.
    /// Multiplying cannot lift a near-black surface: black times anything is
    /// black, so Anubis's jackal head would come out identical in all five
    /// elements. A little additive light in the element colour tints exactly
    /// the parts multiply cannot reach. Kept low, because emission applies
    /// flatly and too much of it makes the whole figure look like a decal.
    ///
    /// One structural detail: `SCNNode.clone()` shares geometry — and therefore
    /// materials — with the original, so tinting in place would repaint every
    /// Anubis on the board including the opponent's. Each instance gets its own
    /// copy of the materials first.
    static func applyElementTint(
        _ node: SCNNode,
        hex: String,
        strength: CGFloat = 0.35,
        glow: CGFloat = 0.13
    ) {
        guard let tint = UIColor(hex: hex) else { return }
        let wash = UIColor.white.mixed(with: tint, amount: strength)
        let lift = UIColor.black.mixed(with: tint, amount: glow)

        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry,
                  let unique = geometry.copy() as? SCNGeometry else { return }
            unique.materials = geometry.materials.map { source in
                guard let material = source.copy() as? SCNMaterial else { return source }
                material.multiply.contents = wash
                // Never overwrite a real emissive map the export shipped with —
                // glowing eyes and runes are authored, not incidental.
                if material.emission.contents == nil {
                    material.emission.contents = lift
                }
                return material
            }
            child.geometry = unique
        }
    }
}
