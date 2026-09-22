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
    /// The caches' lock. `node(for:)` and `animation(_:for:)` run on the main
    /// thread as a stage is built; `warm(_:)` fills the same caches from a
    /// background queue while the briefing is up. Held around the dictionary
    /// reads and writes only, never around a load, so a mesh parsing in the
    /// background never blocks the stage being built in front.
    private let cacheLock = NSLock()

    private func cachedNode(_ name: String) -> SCNNode? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache[name]
    }

    private func store(_ node: SCNNode, as name: String) {
        cacheLock.lock(); cache[name] = node; cacheLock.unlock()
    }

    /// SceneKit's importer is driven from ONE thread at a time.
    ///
    /// The warm pass parses a rail's meshes on a background queue while the
    /// screen it is warming for parses the figure it is about to show — and
    /// that figure's clip — on the main thread, and on the Hall of Ka the two
    /// overlapped: the tour's step 3 logged the USD library's "TBB Global TLS
    /// count is not == 1, instead it is: 2" the instant the altar's idle clip
    /// was read while the rail's meshes were parsing on the other thread, and
    /// 'zeus' was parsed twice, once by each thread. Every parse in the app
    /// goes through `withImporter` — the loader's meshes and clips, the
    /// stage's props, the chest — so a background parse can never overlap a
    /// foreground one. The lock is held around a PARSE only, never around
    /// the caches: the warm pass still does its work, and the foreground
    /// waits for at most the one file being read.
    ///
    /// It was found while chasing the frozen figure on the dais (the owner,
    /// 2026-09-17: "Why are the characters stuck in this position") and is
    /// NOT what froze it: run 170 serialised every parse and Zeus stood in
    /// his bind pose all the same. That was the order of attach and animate
    /// — `SCNNode.startLoop`, at the end of this file.
    private static let importerLock = NSLock()

    /// Runs one use of SceneKit's importer with the importer to itself.
    static func withImporter<T>(_ body: () throws -> T) rethrows -> T {
        importerLock.lock(); defer { importerLock.unlock() }
        return try body()
    }

    /// Parses a model file, one parse at a time (see `importerLock`).
    static func parseScene(at url: URL, options: [SCNSceneSource.LoadingOption: Any]? = nil) throws -> SCNScene {
        try withImporter { try SCNScene(url: url, options: options) }
    }

    /// The cached prototype, or the file parsed and cached — parsed ONCE even
    /// when two threads ask at the same moment, which the warm pass and the
    /// screen it is warming for do: the second asker waits on the importer
    /// and then finds the first's result in the cache instead of parsing the
    /// same file again (the Hall of Ka's log showed Zeus built twice).
    private func loadOrCached(_ name: String) -> SCNNode? {
        if let cached = cachedNode(name) { return cached }
        return Self.withImporter { () -> SCNNode? in
            if let cached = cachedNode(name) { return cached }
            guard let loaded = loadFromBundle(name) else { return nil }
            store(loaded, as: name)
            return loaded
        }
    }

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

    /// A battle always renders the `_lod` file. A screen showing ONE character
    /// — the summon reveal, the unit sheet — asks for `.high` by name.
    ///
    /// This was "full detail below eight combatants", written when a shipped
    /// model was 5,000 triangles with a 1,024 texture. The detail pass made it
    /// 9,000 triangles with a **2,048** texture, and a 2,048-square RGBA
    /// texture is 16 MB decompressed: a 3v3 was decoding and uploading six of
    /// them, about 100 MB, on the main thread while the stage built. That is
    /// the multi-second hitch the owner hit entering a campaign fight in a
    /// release build.
    ///
    /// The LOD costs nothing visible here. The battle camera stands a figure a
    /// quarter of the screen tall — roughly 330 pixels on a 3× phone — and the
    /// LOD carries 3,500 triangles with a 1,024 texture, which is more texels
    /// than those pixels can show. The full model exists for the screens where
    /// one character fills the frame, and there it is worth every byte.
    static func detail(forCombatantCount count: Int) -> DetailLevel {
        count > 1 ? .low : .high
    }

    /// Returns a fresh copy of the model for a spec, ready to be added to a scene.
    /// Always returns a node — never nil — so the renderer has no missing-asset path.
    func node(
        for spec: ModelSpec,
        archetype: Archetype,
        element: Element,
        detail: DetailLevel = .high,
        awakened: Bool = false
    ) -> SCNNode {
        let container = SCNNode()
        container.name = "unit_\(spec.assetName)"

        // An awakened unit loads `<asset>_awakened` when that mesh has
        // shipped and otherwise the base mesh with the awakened look on it:
        // glowing costume accents, a stronger rim, an aura from the unit node.
        let baseName = awakened && bundleURL(for: spec.awakenedAssetName) != nil
            ? spec.awakenedAssetName
            : spec.assetName

        // Ask for the reduced mesh first when the stage is busy, but never fail
        // over it: a missing `_lod` file just means the full model is used.
        let assetName = detail == .low && bundleURL(for: baseName + DetailLevel.low.suffix) != nil
            ? baseName + DetailLevel.low.suffix
            : baseName

        let model: SCNNode
        var isStandIn = false
        /// A stand-in that is a portrait sprite rather than the primitive rig.
        var isPortraitSprite = false
        if let loaded = loadOrCached(assetName) {
            model = loaded.clone()
            MaterialTuner.applyElementTint(model, hex: spec.auraHex, sourceHue: CGFloat(spec.costumeHue))
        } else if let standIn = spec.standInAsset,
                  let loaded = loadOrCached(standIn) {
            // A named stand-in: a shipped mesh of the right kind, stood up
            // and scaled to this spec's height like a real export, so a boss
            // whose own mesh is still on the way fights as a giant of its
            // kind rather than as the primitive rig.
            model = loaded.clone()
            MaterialTuner.applyElementTint(model, hex: spec.auraHex, sourceHue: CGFloat(spec.costumeHue))
            if !orientationLogged.contains(assetName) {
                log("'\(assetName)': no mesh in the bundle; standing in with '\(standIn)' at \(spec.height) m")
            }
        } else {
            isStandIn = true
            isPortraitSprite = BundleArt.exists(spec.portraitName + "_cut")
                || BundleArt.exists(spec.portraitName)
            let key = spec.assetName + "|" + spec.auraHex
            let placeholder = placeholderCache[key]
                ?? PlaceholderRig.make(spec: spec, archetype: archetype, element: element)
            placeholderCache[key] = placeholder
            model = placeholder.clone()
        }

        if !isStandIn {
            repairSkinners(in: model, label: assetName)
            // A cape's chain of joints (the cape pass, tools/character.py)
            // is found here, before the model is scaled and placed, and
            // stepped by the simulation from every stage's render delegate.
            ClothChain.attach(to: model, label: assetName)
            if awakened { MaterialTuner.applyAwakenedLook(model) }
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
        // Multiplied onto what `normalise` set, never assigned over it: a
        // canonical export's factor is 1.0 either way, but a named stand-in
        // is scaled to its host's height by normalise, and assigning here
        // threw that away — the first Colossus fought at sentinel size.
        model.scale = SCNVector3(model.scale.x * scale, model.scale.y * scale, model.scale.z * scale)
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
        cacheLock.lock()
        let hit = animationCache[assetName]?[clip]
        cacheLock.unlock()
        if let hit { return hit }

        var found: CAAnimation?

        // Layout A: separate file per clip. Parsed with the importer to
        // itself (`importerLock`): read while a warm pass parsed meshes on
        // another thread, a clip came back as a group that moved nothing.
        if let url = bundleURL(for: "\(assetName)_\(clip.rawValue)"),
           let scene = try? Self.parseScene(at: url, options: [.animationImportPolicy: SCNSceneSource.AnimationImportPolicy.playRepeatedly]) {
            found = firstAnimation(in: scene.rootNode)
        }

        // Layout B: one file, many animation players.
        if found == nil, let url = bundleURL(for: assetName) {
            found = Self.withImporter { () -> CAAnimation? in
                guard let source = SCNSceneSource(url: url, options: nil) else { return nil }
                let identifiers = source.identifiersOfEntries(withClass: CAAnimation.self)
                let match = identifiers.first { $0.lowercased().contains(clip.rawValue) }
                guard let match else { return nil }
                return source.entryWithIdentifier(match, withClass: CAAnimation.self)
            }
        }

        if let found {
            found.repeatCount = clip.loops ? .greatestFiniteMagnitude : 1
            found.isRemovedOnCompletion = !clip.loops
            // A longer cross-fade between clips: the cut from idle to swing
            // and back was where the motion looked stiff.
            found.fadeInDuration = 0.22
            found.fadeOutDuration = 0.30
            cacheLock.lock()
            animationCache[assetName, default: [:]][clip] = found
            cacheLock.unlock()
        }
        return found
    }

    /// Whether a model file of this name is in the bundle. The unit node asks
    /// so an awakened mesh, when one has shipped, plays its own clips.
    func hasModel(_ name: String) -> Bool { bundleURL(for: name) != nil }

    /// The asset whose CLIPS a figure plays: the awakened export when it
    /// shipped and the unit is awakened, else the base one, else the
    /// stand-in's own — the same choice `node(for:)` makes for the MESH, so
    /// a clip is never played on another family's rig. Every stage that
    /// starts an idle goes through this. The reveal, the altar and the
    /// collection's Stage played the BASE mesh's idle on the awakened mesh
    /// until 2026-09-18: the two rigs share their joint names and nothing
    /// else, the base Ares's idle put the awakened Ares's pelvis 150° off
    /// its rest, and the cape simulation, which keeps the hem behind a plane
    /// through the pelvis, pushed his cape round to the front (run 189's
    /// console beside tools/cape_sim.py's numbers).
    func clipAsset(for spec: ModelSpec, awakened: Bool) -> String {
        if awakened && hasModel(spec.awakenedAssetName) { return spec.awakenedAssetName }
        if hasModel(spec.assetName) { return spec.assetName }
        return spec.standInAsset ?? spec.assetName
    }

    /// Loads a set of specs' meshes and their clips into the caches on a
    /// background queue, so a stage built afterwards clones from the cache
    /// instead of parsing USDZ on the main thread.
    ///
    /// The tour's watchdog timed that parse at 1.5 s for six figures on the
    /// simulator's Mac; on the phone it is the freeze between Begin and the
    /// first frame of a fight, and the same freeze again when a wave walks
    /// on. The briefing is up for seconds before Begin, which is the time to
    /// spend it in. `crowded` asks for the reduced meshes the stage will ask
    /// for (`detail(forCombatantCount:)`); the clips are keyed by the base
    /// name whatever the mesh, as `UnitNode.clipAsset` keys them.
    func warm(_ specs: [ModelSpec], crowded: Bool = false, clips: Bool = true) {
        var meshes: Set<String> = []
        var clipAssets: Set<String> = []
        for spec in specs {
            let shipped = bundleURL(for: spec.assetName) != nil
            let base = shipped ? spec.assetName : (spec.standInAsset ?? spec.assetName)
            let reduced = base + DetailLevel.low.suffix
            meshes.insert(crowded && bundleURL(for: reduced) != nil ? reduced : base)
            clipAssets.insert(base)
            if bundleURL(for: spec.awakenedAssetName) != nil {
                meshes.insert(spec.awakenedAssetName)
                clipAssets.insert(spec.awakenedAssetName)
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let started = Perf.begin()
            var loaded = 0
            for name in meshes where cachedNode(name) == nil {
                if loadOrCached(name) != nil { loaded += 1 }
            }
            if clips {
                for name in clipAssets {
                    for clip in AnimationClip.allCases { _ = animation(clip, for: name) }
                }
            }
            Perf.end(started, "warmed \(loaded) meshes, \(clips ? "clips of \(clipAssets.count)" : "no clips")", over: 1)
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

    /// Parses a mesh file. Called under `importerLock` by `loadOrCached`,
    /// which is the only caller: the lock is not re-entrant, so this must
    /// never take it itself.
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
        Self.predecodeTextures(in: wrapper, label: name)
        describe(wrapper, label: name)
        return wrapper
    }

    /// Decodes every texture on the model's materials on the thread that
    /// parsed it, so a stage built afterwards uploads pixels instead of
    /// decoding JPEGs on the main thread.
    ///
    /// A 2,048-square texture is 16 MB of pixels and the decode is what
    /// made a 3v3 hitch as it built (six of them, about 100 MB, on the main
    /// thread) — the reason the battle's `_lod` file carried a 1,024
    /// texture from 2026-09-09 to 2026-09-17. The warm pass parses on its
    /// own queue while the briefing is up, and `preparingForDisplay` decodes
    /// there too; a cold load on the main thread pays the same decode it
    /// would have paid at first render, no more.
    ///
    /// SceneKit's USDZ importer leaves a texture as a URL INTO the archive
    /// — `file:///…/zeus.usdz#textures/base_color.png` — and `URL.path`
    /// drops the fragment, so the first cut of this read the whole 5 MB
    /// zip as an image and logged twelve CoreGraphics errors per screen
    /// (run 174). The member is read out of the archive by name instead:
    /// a USDZ is a zip with every member stored uncompressed, so the bytes
    /// are a slice of the file (`USDZArchive`).
    private static func predecodeTextures(in root: SCNNode, label: String) {
        var decoded = 0
        var archives: [String: USDZArchive] = [:]
        root.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                for property in [material.diffuse, material.emission, material.normal, material.roughness, material.metalness] {
                    var image: UIImage?
                    if let existing = property.contents as? UIImage {
                        image = existing
                    } else if let url = property.contents as? URL, url.isFileURL, url.pathExtension.lowercased() == "usdz" {
                        // Run 175 showed the URL carries NO fragment: SceneKit
                        // keeps the member's name to itself. The writer
                        // (tools/character.py) names every texture by its
                        // role, so the member is looked up by the role this
                        // property plays; a file that lacks it is left to
                        // SceneKit, and the archive is never handed to UIImage.
                        let archive = archives[url.path] ?? USDZArchive(url: url)
                        archives[url.path] = archive
                        let role: String
                        switch property {
                        case material.diffuse: role = "base_color"
                        case material.normal: role = "normal"
                        case material.emission: role = "emissive"
                        default: role = "metallic_roughness"
                        }
                        let candidates = url.fragment.map { [$0] } ?? ["textures/\(role).png", "textures/\(role).jpg"]
                        for name in candidates {
                            if let data = archive?.member(named: name), let read = UIImage(data: data) {
                                image = read
                                break
                            }
                        }
                    } else if let path = property.contents as? String, !path.contains("#"),
                              !path.lowercased().hasSuffix(".usdz"), FileManager.default.fileExists(atPath: path) {
                        image = UIImage(contentsOfFile: path)
                    }
                    if let image, let ready = image.preparingForDisplay() {
                        property.contents = ready
                        decoded += 1
                    }
                }
            }
        }
        if decoded > 0 {
            shared.log("'\(label)': \(decoded) texture(s) decoded ahead of the first frame")
        }
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
        // The first two dozen, not all seven hundred: the tour keeps 120 KB
        // of console per step, and the full list filled it before a fight's
        // own lines — the wave that brought the Colossus on was cut off.
        for path in found.prefix(24) { log("    \(path)") }
        if found.count > 24 { log("    … and \(found.count - 24) more") }
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
        // The track count is in the line so a clip that parsed into an empty
        // group — the shape of the Hall of Ka's frozen figure — can be read
        // off the console rather than guessed from a screenshot.
        let shape = (best as? CAAnimationGroup).map { "a group of \($0.animations?.count ?? 0) tracks" } ?? "a single track"
        log(String(format: "clip animation taken from %@, %.2f s, %@", origin, best.duration, shape))
        return best
    }
}

extension SCNNode {
    /// Starts a looping clip on a figure that is ALREADY in its scene, through
    /// a player told to play.
    ///
    /// The stage views used to `addAnimation` the idle to the figure and THEN
    /// add the figure to the scene. Built inside `makeUIView`, before the
    /// view's first frame, that played; built inside `updateUIView`, into a
    /// scene already rendering, the figure stood in its bind pose for good —
    /// the Hall of Ka opened from the island picks its unit a beat after it
    /// appears and photographed Zeus frozen on the dais in three runs of
    /// frames (168–170), while the Awaken step, which names its unit up
    /// front, animated on the same code (the owner, 2026-09-17: "Why are the
    /// characters stuck in this position"). A clip added to a detached node
    /// and carried into a live scene is the one order SceneKit did not start.
    /// So: into the scene first, then a player, then `play()` — the three
    /// things the paths that worked had and the frozen one lacked.
    func startLoop(_ clip: CAAnimation, key: String) {
        let animation = SCNAnimation(caAnimation: clip)
        animation.usesSceneTimeBase = false
        let player = SCNAnimationPlayer(animation: animation)
        addAnimationPlayer(player, forKey: key)
        player.play()
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
///    pixel of the base texture that is strongly coloured and close to the
///    design's primary accent (`ModelSpec.costumeHue`, gold so far) takes the
///    element's hue as it is sampled, so the water variant wears water, not a
///    faintly bluer red. Skin, fur, white linen, black and the design's other
///    colours stay as painted. It runs per fragment, so it costs no memory
///    and no load time.
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
    /// the PNG's own values) and back afterwards. Only the design's PRIMARY
    /// accent moves: a pixel that is strongly coloured (saturation over 0.5,
    /// which leaves every skin tone alone) and within `costumeBand` of the
    /// model's `costumeSourceHue` — gold, on every character so far — is
    /// rebuilt with the element's hue at its own brightness. The design's
    /// other colours (Sekhmet's lapis and crimson, Zeus's white) stay, so an
    /// ember Sekhmet is red-gold, blue and crimson rather than a monochrome.
    /// The first version recoloured everything saturated and the CI reveal
    /// showed a lioness in one shade of red. `costumeMix` is 0 until
    /// `applyElementTint` sets it, so an untinted model renders as painted.
    static let surfaceModifier = """
    #pragma arguments
    float costumeHue;
    float costumeSaturation;
    float costumeMix;
    float costumeSourceHue;
    float costumeBand;
    float costumeGlow;
    float paintSaturation;
    float hasMetalMap;
    float metalShine;
    #pragma body
    float3 c = pow(max(_surface.diffuse.rgb, float3(0.0)), float3(1.0 / 2.2));
    // THE PAINT'S SATURATION (2026-09-20). Meshy's texturing doubles the
    // concept's saturation (Sif's shipped base colour measures 118 of 255
    // against her concept's 60; the prompt asked for "rich saturated
    // colour"), and the owner read the result as a cartoon on every stage.
    // Pulled toward its own luminance here, one number for every family,
    // before the hue test so the recolour reads the tempered paint.
    float luma = dot(c, float3(0.299, 0.587, 0.114));
    c = mix(float3(luma), c, paintSaturation);
    _surface.diffuse.rgb = pow(c, float3(2.2));
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float delta = maxC - minC;
    float h = 0.0;
    float s = 0.0;
    if (delta > 0.001) {
        if (maxC == c.r) { h = (c.g - c.b) / delta; if (h < 0.0) { h += 6.0; } }
        else if (maxC == c.g) { h = (c.b - c.r) / delta + 2.0; }
        else { h = (c.r - c.g) / delta + 4.0; }
        h /= 6.0;
        s = delta / maxC;
    }
    // The metal, read off the painting (2026-09-17): the generator's
    // metal-vs-cloth map never reached the bundle (the animated exports
    // carry the base colour alone and the tasks are gone), so a pixel
    // painted as gold — bright, saturated, within a few degrees of gold's
    // hue, which no skin tone reaches — is marked metallic and smooth
    // here, and the lighting modifier gives it a tight bright pop where
    // linen gets a soft broad one. Read BEFORE the element recolour, so a
    // water unit's blue armour is still armour.
    // Only for a family with NO metalness map (2026-09-20): the serious
    // families ship the generator's own metallic and roughness maps, and
    // a painted-gold guess on top of a real map marked every warm cloth
    // as metal.
    float goldAway = abs(h - 0.125);
    goldAway = min(goldAway, 1.0 - goldAway);
    float metal = (hasMetalMap < 0.5 && delta > 0.001 && maxC > 0.35)
        ? smoothstep(0.45, 0.65, s) * (1.0 - smoothstep(0.035, 0.07, goldAway))
        : 0.0;
    _surface.metalness = max(_surface.metalness, 0.85 * metal);
    _surface.roughness = mix(_surface.roughness, 0.28, metal);
    // A real metalness map's metal takes a lower roughness (2026-09-22):
    // Meshy paints its gold at about 0.5, satin, and under the studio
    // map satin gold reads as tan paint beside a matte tunic.
    if (hasMetalMap > 0.5 && metalShine > 0.5) {
        _surface.roughness = mix(_surface.roughness, _surface.roughness * 0.55, saturate(_surface.metalness));
    }
    if (costumeMix > 0.0 && maxC > 0.12 && delta > 0.001 && s > 0.5) {
        float away = abs(h - costumeSourceHue);
        away = min(away, 1.0 - away);
        if (away < costumeBand) {
            // The accent keeps the paint's own saturation, lifted no higher
            // than 0.6 of the element's and never past 0.85 (2026-09-20): at
            // 0.8 of a fully saturated element colour every ember accent
            // was neon.
            float ns = min(max(s, costumeSaturation * 0.6), 0.85);
            float3 k = fract(float3(costumeHue) + float3(1.0, 2.0 / 3.0, 1.0 / 3.0));
            float3 p = abs(k * 6.0 - 3.0);
            float3 recoloured = maxC * mix(float3(1.0), saturate(p - 1.0), ns);
            float3 blended = mix(c, recoloured, costumeMix);
            float3 lit = pow(blended, float3(2.2));
            _surface.diffuse.rgb = lit;
            // Awakened: the costume accent glows in its own colour.
            _surface.emission.rgb += lit * costumeGlow;
        }
    }
    """

    /// Metal. `_surface.normal` and `_surface.view` are in view space;
    /// `_light.direction` points at the light.
    ///
    /// LAMBERT since 2026-09-18. Every ramp before it was a half-Lambert —
    /// `ndl * 0.5 + 0.5` through a band, over a floor of 0.30 — so a face
    /// turned fully away from a light still took 30% of it, and the four
    /// lights of the reveal, the altar and the collection's Stage summed to
    /// a figure with no shadow side at all: the owner's frames of the
    /// awakened Ares and of Sekhmet on the beam were "the renders all
    /// fucked up", and `preview.py`, which draws plain Lambert, drew the
    /// same meshes as sculpture. The half-Lambert was the cartoon; the
    /// 0.04–0.96 band of 2026-09-17 widened it but kept the wrap and the
    /// floor. This is `saturate((ndl + 0.15) / 1.15)`: a real terminator with
    /// a hair of wrap so a normal map's engraving shades through the turn,
    /// and the shadow side is what the fill, the ambient and the environment
    /// map give it — which is how the genre's real-time figures (Raid, the
    /// 3D reveals) are lit. The old ramp survives as `legacyLightingModifier`
    /// for the CI lab (`-tour-shading legacy`), so a frame can be judged
    /// against it; it is not for the game.
    ///
    /// NONE since 2026-09-20: the figures are lit by SceneKit's own
    /// physically based model — GGX speculars shaped by the shipped
    /// roughness map, Fresnel, and the environment map's reflections
    /// weighted by roughness and metalness — which is what the set's floors
    /// and props have had all along (`StageBuilder` never had a modifier),
    /// and what the genre's real-time figures are lit with. The Lambert
    /// ramp with its 16- to 70-power Blinn-Phong pop was the last of the
    /// cartoon: a hand-shaped highlight that ignored the maps' fine grain.
    /// The ramp (`-tour-shading ramp`) and the half-Lambert of 2026-09-17
    /// (`-tour-shading legacy`) survive for the CI lab, so a run photographs
    /// the same figure under all three.
    static var lightingModifier: String? {
        switch shadingLab {
        case .physical: return nil
        case .ramp: return lambertLightingModifier
        case .legacy: return legacyLightingModifier
        }
    }

    /// `-tour-shading ramp|legacy` (DEBUG, the CI lab) lights every figure
    /// with an older ramp, so one run photographs the physically based
    /// figure beside its two predecessors.
    enum ShadingLab { case physical, ramp, legacy }
    static var shadingLab: ShadingLab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-shading"), at + 1 < args.count else { return .physical }
        switch args[at + 1] {
        case "ramp": return .ramp
        case "legacy": return .legacy
        default: return .physical
        }
        #else
        return .physical
        #endif
    }

    static let lambertLightingModifier = """
    #pragma body
    float ndl = dot(_surface.normal, _light.direction);
    // A real terminator with a hair of wrap (0.15): the shadow side is the
    // fill's, the ambient's and the environment's, not this light's.
    float lam = saturate((ndl + 0.15) / 1.15);
    // A metal's colour is in its highlight, not its diffuse: the surface
    // modifier marks the painted gold metallic and smooth, and here that
    // dims the flat fill a little and turns the specular from one 36-power
    // pop for everything into one that follows roughness — 70-power and
    // bright on smooth metal, 16-power and faint on rough linen (the
    // owner, 2026-09-17: "not detailed enough"; the engraving was lit like
    // the cloth beside it).
    float rough = saturate(_surface.roughness);
    float metal = saturate(_surface.metalness);
    _lightingContribution.diffuse += _light.intensity.rgb * lam * (1.0 - 0.30 * metal);
    float3 h = normalize(_light.direction + _surface.view);
    float specPower = mix(70.0, 16.0, rough);
    float specStrength = mix(0.90, 0.22, rough) * (0.55 + 0.75 * metal);
    float spec = pow(saturate(dot(_surface.normal, h)), specPower) * specStrength * saturate(ndl * 4.0);
    _lightingContribution.specular += _light.intensity.rgb * spec;
    """

    /// The half-Lambert ramp the game shipped with until 2026-09-18, kept
    /// only so the CI lab can photograph it beside the Lambert (see
    /// `lightingModifier`).
    static let legacyLightingModifier = """
    #pragma body
    float ndl = dot(_surface.normal, _light.direction);
    float wrap = ndl * 0.5 + 0.5;
    float band = smoothstep(0.04, 0.96, wrap);
    float rough = saturate(_surface.roughness);
    float metal = saturate(_surface.metalness);
    _lightingContribution.diffuse += _light.intensity.rgb * (0.30 + 0.70 * band) * (1.0 - 0.30 * metal);
    float3 h = normalize(_light.direction + _surface.view);
    float specPower = mix(70.0, 16.0, rough);
    float specStrength = mix(0.90, 0.22, rough) * (0.55 + 0.75 * metal);
    float spec = pow(saturate(dot(_surface.normal, h)), specPower) * specStrength;
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
                    .fragment: fragmentModifier,
                ]
                if let lighting = lightingModifier {
                    material.shaderModifiers?[.lightingModel] = lighting
                }
                // A real metalness map (the serious families) switches the
                // surface shader's painted-gold guess off.
                let hasMetalMap = material.metalness.contents != nil && !(material.metalness.contents is NSNumber)
                material.setValue(NSNumber(value: Float(hasMetalMap ? 1 : 0)), forKey: "hasMetalMap")
                material.setValue(NSNumber(value: Float(paintSaturation)), forKey: "paintSaturation")
                material.setValue(NSNumber(value: Float(FigureStageLighting.metalShine ? 1 : 0)), forKey: "metalShine")
                // Float, and Float again when `applyElementTint` sets them:
                // SceneKit logs an error and animates wrongly when a key
                // switches between Double and Float.
                material.setValue(NSNumber(value: Float(0)), forKey: "costumeHue")
                material.setValue(NSNumber(value: Float(0)), forKey: "costumeSaturation")
                material.setValue(NSNumber(value: Float(0)), forKey: "costumeMix")
                material.setValue(NSNumber(value: Float(45.0 / 360.0)), forKey: "costumeSourceHue")
                material.setValue(NSNumber(value: Float(32.0 / 360.0)), forKey: "costumeBand")
                material.setValue(NSNumber(value: Float(0)), forKey: "costumeGlow")
                material.setValue(NSValue(scnVector3: SCNVector3(1, 1, 1)), forKey: "rimColor")
                // A narrower, quieter rim than the first build's 2.6 / 0.55:
                // that one drew a white outline round every figure.
                // Narrower and quieter again on 2026-09-17 (3.2 / 0.42): a
                // bright rim is a cartoon's outline in light. And again on
                // 2026-09-20 (4.2 / 0.12): with the physically based model's
                // own Fresnel on every edge, the rim is a hint, never a line.
                material.setValue(NSNumber(value: Float(rimPower)), forKey: "rimPower")
                material.setValue(NSNumber(value: Float(rimStrength)), forKey: "rimStrength")
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
        sourceHue: CGFloat = 45,
        strength: CGFloat = 0.06,
        glow: CGFloat = 0.04,
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
                material.setValue(NSNumber(value: Float(sourceHue / 360)), forKey: "costumeSourceHue")
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
        report(node, "\(textured) textured material(s); the \(Int(sourceHue))° costume accent becomes \(Int(hue * 360))° for \(hex) in the surface shader")
    }

    /// The awakened form on a base mesh: the costume accent glows in its
    /// element colour and the rim widens and brightens. Runs after
    /// `applyElementTint`, on the instance's own materials. When a family
    /// ships an `_awakened` mesh, this runs on that mesh instead, so the
    /// glow is the constant and the costume is the upgrade.
    ///
    /// Quiet since 2026-09-17 (evening). It was a 2.0-power rim at 0.95 and
    /// a costume glow of 0.55: at mid-facing that rim is nine times the base
    /// rim (3.6 / 0.30), in the element's colour, over every pixel of the
    /// figure, and the glow pushed lit gold past the bloom threshold — on the
    /// reveal's four lights the owner's Ares Aureate photographed as a pale
    /// smear over the temple ("If awakened characters look like this we have
    /// a HUGE problem"), while `preview.py` drew the same mesh as a bronze
    /// hoplite with a crimson cape. The aura rising from the feet and the
    /// glow on the accents say "awakened"; the silhouette does not need to.
    static func applyAwakenedLook(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            guard let materials = child.geometry?.materials else { return }
            for material in materials {
                material.setValue(NSNumber(value: Float(awakenedCostumeGlow)), forKey: "costumeGlow")
                material.setValue(NSNumber(value: Float(awakenedRimPower)), forKey: "rimPower")
                material.setValue(NSNumber(value: Float(awakenedRimStrength)), forKey: "rimStrength")
            }
        }
        report(node, "awakened look: costume glow \(awakenedCostumeGlow), rim \(awakenedRimStrength) at power \(awakenedRimPower)")
    }

    /// The awakened look's three numbers, beside each other so the next
    /// frame that reads wrong changes them together (the base rim is 3.6 at
    /// 0.30 in `tune`; an awakened figure's is a little wider and a little
    /// brighter, never an outline).
    static let awakenedCostumeGlow: Double = 0.12
    static let awakenedRimPower: Double = 4.0
    static let awakenedRimStrength: Double = 0.18

    /// The base rim (`tune`) and the paint's saturation, beside the awakened
    /// look's numbers so the next frame that reads as a cartoon changes them
    /// together (2026-09-20; Docs/PLAN.md, *The serious look in the light*).
    static let rimPower: Double = 4.2
    static let rimStrength: Double = 0.12
    static var paintSaturation: Double { FigureStageLighting.paintSaturation }

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

/// A renderer delegate that reports, in the tour's console, whether a stage
/// renders at all, whether its idle player advances, and whether the
/// figure's joints move — one line a second for six seconds, under `-tour`
/// only. The Hall of Ka's figure stood in its bind pose through four runs
/// of frames while the collection's Stage animated the same figure on the
/// same code, and nothing in the logs said WHICH link of the chain broke:
/// the view not rendering, the player not advancing, or the skinner not
/// following its bones. This says which.
final class StageDoctor: NSObject, SCNSceneRendererDelegate {
    let label: String
    weak var figure: SCNNode?
    weak var view: SCNView?
    private var frames = 0
    private var firstTime: TimeInterval = 0
    private var lastReport: TimeInterval = 0
    private var reports = 0
    private let enabled = ProcessInfo.processInfo.arguments.contains("-tour")

    init(label: String) {
        self.label = label
        super.init()
    }

    /// The cloth chains are stepped here on every stage this doctor watches
    /// (the Hall of Ka's altar, the collection's Stage), tour or not.
    func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        ClothSimulation.shared.step(in: renderer.scene, at: time)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard enabled else { return }
        frames += 1
        if firstTime == 0 { firstTime = time; lastReport = time }
        guard reports < 6, time - lastReport >= 1.0 else { return }
        lastReport = time
        reports += 1
        // The scene graph is read here, on the render thread, where the
        // presentation nodes are; the view's own properties are UIKit's
        // and are read on the main thread below.
        var line = String(format: "[StageDoctor] %@ t=%.1f frames=%d", label, time - firstTime, frames)
        if let figure {
            let keys = figure.animationKeys
            line += " keys=\(keys)"
            if let key = keys.first, let player = figure.animationPlayer(forKey: key) {
                line += String(format: " player(paused=%@ speed=%.2f blend=%.2f duration=%.2f)",
                               player.paused ? "yes" : "no", player.speed, player.blendFactor, player.animation.duration)
            }
            for name in ["Hips", "Hand"] {
                let matches = figure.childNodes { node, _ in node.name?.localizedCaseInsensitiveContains(name) == true }
                if let joint = matches.first {
                    let p = joint.presentation.worldPosition
                    line += String(format: " %@=(%.3f,%.3f,%.3f)", joint.name ?? name, p.x, p.y, p.z)
                }
            }
        } else {
            line += " figure=nil"
        }
        DispatchQueue.main.async { [weak self] in
            var full = line
            if let view = self?.view {
                full += " playing=\(view.isPlaying) continuous=\(view.rendersContinuously)"
                full += " scenePaused=\(view.scene?.isPaused ?? false) inWindow=\(view.window != nil)"
                full += " size=\(Int(view.bounds.width))x\(Int(view.bounds.height))"
            }
            print(full)
        }
    }
}


// MARK: - Reading a texture out of a USDZ

/// A USDZ is a zip whose members are stored uncompressed and aligned, so a
/// texture inside it is a contiguous slice of the file: this reads the
/// central directory once and hands the slice back by name. Nothing here
/// inflates — a member that is not stored (method 0) is refused, and the
/// caller leaves that texture to SceneKit.
final class USDZArchive {
    private let data: Data
    /// Member name → (offset of the local header, size).
    private var entries: [String: (offset: Int, size: Int)] = [:]

    init?(url: URL) {
        guard let mapped = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        data = mapped
        guard readCentralDirectory() else { return nil }
    }

    /// The bytes of a stored member, or nil.
    func member(named name: String) -> Data? {
        guard let entry = entries[name] else { return nil }
        // Local file header: signature (4), version (2), flags (2), method
        // (2), time (2), date (2), crc (4), compressed (4), uncompressed
        // (4), name length (2), extra length (2), then the name, the extra
        // field and the bytes.
        let base = entry.offset
        guard base + 30 <= data.count, u32(base) == 0x0403_4B50 else { return nil }
        let method = u16(base + 8)
        guard method == 0 else { return nil }
        let nameLength = u16(base + 26)
        let extraLength = u16(base + 28)
        let start = base + 30 + nameLength + extraLength
        let end = start + entry.size
        guard end <= data.count else { return nil }
        return data.subdata(in: start..<end)
    }

    /// Finds the end-of-central-directory record from the tail and walks
    /// the directory's entries.
    private func readCentralDirectory() -> Bool {
        let count = data.count
        guard count >= 22 else { return false }
        var eocd = -1
        var probe = count - 22
        let floor = max(0, count - 22 - 65_535)
        while probe >= floor {
            if u32(probe) == 0x0605_4B50 { eocd = probe; break }
            probe -= 1
        }
        guard eocd >= 0 else { return false }
        let total = u16(eocd + 10)
        var cursor = Int(u32(eocd + 16))
        for _ in 0..<total {
            // Central directory entry: signature (4) … method at 10,
            // compressed size at 20, uncompressed at 24, name length at 28,
            // extra length at 30, comment length at 32, local header offset
            // at 42, then the name.
            guard cursor + 46 <= count, u32(cursor) == 0x0201_4B50 else { return false }
            let compressed = Int(u32(cursor + 20))
            let nameLength = u16(cursor + 28)
            let extraLength = u16(cursor + 30)
            let commentLength = u16(cursor + 32)
            let offset = Int(u32(cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLength <= count else { return false }
            if let name = String(data: data.subdata(in: nameStart..<nameStart + nameLength), encoding: .utf8) {
                entries[name] = (offset, compressed)
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return true
    }

    private func u16(_ at: Int) -> Int {
        Int(data[at]) | (Int(data[at + 1]) << 8)
    }

    private func u32(_ at: Int) -> UInt32 {
        UInt32(data[at]) | (UInt32(data[at + 1]) << 8) | (UInt32(data[at + 2]) << 16) | (UInt32(data[at + 3]) << 24)
    }
}
