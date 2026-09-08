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

    /// Below this many combatants, everything renders at full detail. The
    /// shipped models are 5,000 triangles with a 1,024 texture, so a 4v4 at
    /// full detail is 40,000 triangles — nothing to a phone. The `_lod` file
    /// (2,500 triangles, a 512 texture) is for the ten-character stage.
    static let crowdedStageThreshold = 8

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

        if !isStandIn {
            repairSkinners(in: model, label: assetName)
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
        describe(wrapper, label: name)
        return wrapper
    }

    /// Points every skinner in a cloned hierarchy at the clone's own bones.
    ///
    /// `SCNNode.clone()` copies the node tree, but a skinner's `bones` and
    /// `skeleton` can keep referring to the tree it was cloned FROM. Here that
    /// tree is the cached original, which is never in a scene and never
    /// animated, so a clone that kept those references would be skinned at the
    /// original's scale and position and would ignore every clip played on it.
    /// Rebuilding the skinner against nodes found by name inside the clone is
    /// harmless when SceneKit has already done this and decisive when it has
    /// not. Joint names are unique in every export this loader has seen.
    private func repairSkinners(in root: SCNNode, label: String) {
        var repaired = 0
        root.enumerateHierarchy { node, _ in
            guard let skinner = node.skinner, let geometry = node.geometry else { return }
            var bones: [SCNNode] = []
            for bone in skinner.bones {
                guard let name = bone.name, let mine = root.childNode(withName: name, recursively: true) else {
                    self.log("'\(label)': bone '\(bone.name ?? "(unnamed)")' has no counterpart in the clone; skinner left alone")
                    return
                }
                bones.append(mine)
            }
            let rebuilt = SCNSkinner(
                baseGeometry: geometry,
                bones: bones,
                boneInverseBindTransforms: skinner.boneInverseBindTransforms,
                boneWeights: skinner.boneWeights,
                boneIndices: skinner.boneIndices
            )
            rebuilt.baseGeometryBindTransform = skinner.baseGeometryBindTransform
            if let skeletonName = skinner.skeleton?.name {
                rebuilt.skeleton = root.childNode(withName: skeletonName, recursively: true)
            }
            node.skinner = rebuilt
            repaired += 1
        }
        if repaired > 0 {
            log("'\(label)': \(repaired) skinner(s) rebound to this instance's own bones")
        }
    }

    /// One line per node that carries geometry, a skinner or an animation, so
    /// the console shows what SceneKit actually built from the file rather
    /// than what the file was meant to contain. Bounds are the node's own, in
    /// its local space; for a skinned mesh that is the bind pose.
    private func describe(_ root: SCNNode, label: String) {
        #if DEBUG
        var lines: [String] = []
        root.enumerateHierarchy { node, _ in
            var bits: [String] = []
            if let geometry = node.geometry {
                let box = node.boundingBox
                bits.append(String(
                    format: "geometry %d sources, %d elements, bbox x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f",
                    geometry.sources.count, geometry.elements.count,
                    box.min.x, box.max.x, box.min.y, box.max.y, box.min.z, box.max.z
                ))
            }
            if let skinner = node.skinner {
                bits.append("skinner with \(skinner.bones.count) bones")
            }
            if !node.animationKeys.isEmpty {
                bits.append("animation keys \(node.animationKeys)")
            }
            if !bits.isEmpty {
                lines.append("      \(node.name ?? "(unnamed)"): " + bits.joined(separator: "; "))
            }
        }
        log("'\(label)' built \(lines.count) node(s) of interest:")
        for line in lines.prefix(16) { print(line); DiagnosticsLog.shared.record(line) }
        if lines.count > 16 {
            print("      … \(lines.count - 16) more")
            DiagnosticsLog.shared.record("      … \(lines.count - 16) more")
        }
        #endif
    }

    /// Every line goes to the console and to `DiagnosticsLog`, which is what
    /// More → Diagnostics shows and shares, so a phone without Xcode attached
    /// can still hand over the block.
    private func log(_ message: String) {
        #if DEBUG
        print("[ModelLibrary] \(message)")
        DiagnosticsLog.shared.record("[ModelLibrary] \(message)")
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
        DiagnosticsLog.shared.recordDeviceHeader()

        for name in assetNames.sorted() {
            if let url = bundleURL(for: name) {
                log("  OK       \(name) -> \(url.lastPathComponent)")
            } else {
                log("  MISSING  \(name) — will render as a placeholder")
            }
        }
        #endif
    }

    /// The clip in a per-clip file. SceneKit may hang the imported skeletal
    /// animation on the skeleton root as one group, or a track on every joint;
    /// the longest animation in the file is the whole clip in either case,
    /// where a depth-first "first one found" could be a single joint's track.
    private func firstAnimation(in node: SCNNode) -> CAAnimation? {
        var best: CAAnimation?
        var origin = ""
        var tracks: [(node: String, animation: CAAnimation)] = []
        node.enumerateHierarchy { child, _ in
            for key in child.animationKeys {
                // `SCNAnimationPlayer.animation` is an `SCNAnimation`, not a
                // `CAAnimation`; the bridging initialiser is the way across.
                guard let player = child.animationPlayer(forKey: key) else { continue }
                let animation = CAAnimation(scnAnimation: player.animation)
                tracks.append((child.name ?? "", animation))
                if best == nil || animation.duration > (best?.duration ?? 0) {
                    best = animation
                    origin = "\(child.name ?? "(unnamed)") / \(key)"
                }
            }
        }
        guard let best else { return nil }
        // The importer may hang a clip on the skeleton root as one group,
        // which is the whole clip, or as one track per joint. The longest
        // single track is one joint's motion, and playing it alone leaves
        // the rest of the body in its bind pose — the A-pose seen in battle.
        // Per-joint tracks are gathered into one group whose key paths name
        // their joints, which is how SceneKit addresses a child node.
        if !(best is CAAnimationGroup), tracks.count > 1 {
            let group = CAAnimationGroup()
            var duration: TimeInterval = 0
            group.animations = tracks.compactMap { track in
                guard let copy = track.animation.copy() as? CAAnimation else { return nil }
                if let property = copy as? CAPropertyAnimation, let keyPath = property.keyPath,
                   !keyPath.hasPrefix("/"), !track.node.isEmpty {
                    property.keyPath = "/\(track.node).\(keyPath)"
                }
                duration = max(duration, copy.duration)
                return copy
            }
            group.duration = duration
            log(String(format: "clip animation assembled from %d joint tracks, %.2f s (longest single track was %@)",
                       tracks.count, duration, origin))
            return group
        }
        log(String(format: "clip animation taken from %@, %.2f s, %@",
                   origin, best.duration, best is CAAnimationGroup ? "a group" : "a single track"))
        return best
    }
}

/// Applies the project's look to imported materials.
///
/// A generator's export arrives as photoreal PBR with one flat texture, and
/// on a phone that reads as clay. The genre's characters read as *drawn*:
/// lifted shadows, a painted highlight, an edge of light in the element's
/// colour, and a costume in the element's palette. Three shader modifiers do
/// that here, all on the GPU, and none of them touches the art files:
///
/// 1. A **surface shader modifier** recolours the costume per element: every
///    pixel of the base texture that is clearly coloured and is not skin or
///    fur takes the element's hue as it is sampled, so the water variant wears
///    water, not a faintly bluer red. Skin, fur, white linen and black stay as
///    painted. It runs per fragment, so it costs no memory and no load time.
///    (The first version did this on the CPU, once per texture and element.
///    It stalled the main thread for the whole recolour — the summon reveal
///    stayed dark through a CI tour — and would have kept five copies of every
///    texture alive.)
/// 2. A **lighting-model shader modifier**: half-Lambert diffuse (shadows
///    lift instead of going black) through a soft two-band ramp, plus a tight
///    specular pop, so form reads at a glance the way a painted texture does.
/// 3. A **fragment shader modifier**: a Fresnel rim in the element's colour,
///    the edge light every gacha character has.
///
/// The PBR clamps stay as they were: roughness in a sane band and metalness
/// capped, because a fully metallic surface under a flat environment is a
/// mirror of nothing.
enum MaterialTuner {

    /// Metal. `_surface.diffuse` is the sampled base colour in linear space,
    /// so it is taken to sRGB for the hue test (the thresholds were tuned on
    /// the PNG's own values) and back afterwards. Skin and fur are a warm hue
    /// between 11° and 38° at moderate saturation; everything else that is
    /// clearly coloured is rebuilt with the element's hue, its own brightness
    /// and no less saturation than the element colour carries. `costumeMix`
    /// is 0 until `applyElementTint` sets it, so an untinted model renders as
    /// painted.
    static let surfaceModifier = """
    #pragma arguments
    float costumeHue;
    float costumeSaturation;
    float costumeMix;
    #pragma body
    float3 c = pow(max(_surface.diffuse.rgb, float3(0.0)), float3(1.0 / 2.2));
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float delta = maxC - minC;
    if (costumeMix > 0.0 && maxC > 0.12 && delta > 0.001 && delta / maxC > 0.28) {
        float h;
        if (maxC == c.r) { h = (c.g - c.b) / delta; if (h < 0.0) { h += 6.0; } }
        else if (maxC == c.g) { h = (c.b - c.r) / delta + 2.0; }
        else { h = (c.r - c.g) / delta + 4.0; }
        h /= 6.0;
        float s = delta / maxC;
        bool skinOrFur = (h > 0.03 && h < 0.105 && s < 0.62);
        if (!skinOrFur) {
            float ns = max(s, costumeSaturation * 0.8);
            float3 k = fract(float3(costumeHue) + float3(1.0, 2.0 / 3.0, 1.0 / 3.0));
            float3 p = abs(k * 6.0 - 3.0);
            float3 recoloured = maxC * mix(float3(1.0), saturate(p - 1.0), ns);
            float3 blended = mix(c, recoloured, costumeMix);
            _surface.diffuse.rgb = pow(blended, float3(2.2));
        }
    }
    """

    /// Metal. `_surface.normal` and `_surface.view` are in view space;
    /// `_light.direction` points at the light.
    static let lightingModifier = """
    #pragma body
    float ndl = dot(_surface.normal, _light.direction);
    float wrap = ndl * 0.5 + 0.5;
    float band = smoothstep(0.28, 0.72, wrap);
    _lightingContribution.diffuse += _light.intensity.rgb * (0.34 + 0.66 * band);
    float3 h = normalize(_light.direction + _surface.view);
    float spec = pow(saturate(dot(_surface.normal, h)), 26.0) * 0.32;
    _lightingContribution.specular += _light.intensity.rgb * spec;
    """

    static let fragmentModifier = """
    #pragma arguments
    float3 rimColor;
    float rimPower;
    float rimStrength;
    #pragma body
    float facing = saturate(dot(normalize(_surface.normal), normalize(_surface.view)));
    float rim = pow(1.0 - facing, rimPower) * rimStrength;
    _output.color.rgb += rimColor * rim;
    """

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

                material.shaderModifiers = [
                    .surface: surfaceModifier,
                    .lightingModel: lightingModifier,
                    .fragment: fragmentModifier,
                ]
                material.setValue(NSNumber(value: 0.0), forKey: "costumeHue")
                material.setValue(NSNumber(value: 0.0), forKey: "costumeSaturation")
                material.setValue(NSNumber(value: 0.0), forKey: "costumeMix")
                material.setValue(NSValue(scnVector3: SCNVector3(1, 1, 1)), forKey: "rimColor")
                material.setValue(NSNumber(value: 2.6), forKey: "rimPower")
                material.setValue(NSNumber(value: 0.55), forKey: "rimStrength")
            }
        }
    }

    private static var reportedTints: Set<String> = []

    /// Turns one export into five characters.
    ///
    /// The costume takes the element's hue in the surface shader (see
    /// `surfaceModifier`), the rim light takes the element's colour, and a
    /// small additive lift in the element colour tints the near-black parts
    /// that no recolour can reach. `SCNNode.clone()` shares geometry and
    /// materials with the original, so each instance gets its own copies
    /// first; otherwise tinting one Anubis would repaint every Anubis on the
    /// board.
    static func applyElementTint(
        _ node: SCNNode,
        hex: String,
        strength: CGFloat = 0.12,
        glow: CGFloat = 0.10,
        costume: CGFloat = 1.0
    ) {
        guard let tint = UIColor(hex: hex) else { return }
        let wash = UIColor.white.mixed(with: tint, amount: strength)
        let lift = UIColor.black.mixed(with: tint, amount: glow)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        tint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        var textured = 0
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry,
                  let unique = geometry.copy() as? SCNGeometry else { return }
            unique.materials = geometry.materials.map { source in
                guard let material = source.copy() as? SCNMaterial else { return source }
                if material.diffuse.contents != nil && !(material.diffuse.contents is UIColor) {
                    textured += 1
                }
                material.setValue(NSNumber(value: Float(hue)), forKey: "costumeHue")
                material.setValue(NSNumber(value: Float(saturation)), forKey: "costumeSaturation")
                material.setValue(NSNumber(value: Float(costume)), forKey: "costumeMix")
                material.setValue(NSValue(scnVector3: SCNVector3(Float(red), Float(green), Float(blue))), forKey: "rimColor")
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
        report(node, "\(textured) textured material(s); costume hue \(Int(hue * 360))° for \(hex), recoloured in the surface shader")
    }

    private static func report(_ node: SCNNode, _ message: String) {
        #if DEBUG
        let key = (node.name ?? "?") + message
        guard !reportedTints.contains(key) else { return }
        reportedTints.insert(key)
        print("[ModelLibrary] \(node.name ?? "model"): \(message)")
        DiagnosticsLog.shared.record("[ModelLibrary] \(node.name ?? "model"): \(message)")
        #endif
    }
}
