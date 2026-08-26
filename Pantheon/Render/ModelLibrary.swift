import Foundation
import SceneKit
import UIKit

/// Loads and caches character models.
///
/// The lookup order is deliberate: a real exported model wins, a `.scn`
/// conversion is next, and a procedural stand-in is last. That last step is what
/// lets the whole game be playable today with zero art in the bundle — a missing
/// `zeus.usdz` produces a correctly-sized, correctly-tinted placeholder that
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

    private var cache: [String: SCNNode] = [:]
    private var animationCache: [String: [AnimationClip: CAAnimation]] = [:]
    private let queue = DispatchQueue(label: "com.pantheon.modellibrary", attributes: .concurrent)

    private init() {}

    // MARK: - Public API

    /// Returns a fresh copy of the model for a spec, ready to be added to a scene.
    /// Always returns a node — never nil — so the renderer has no missing-asset path.
    func node(for spec: ModelSpec, archetype: Archetype, element: Element) -> SCNNode {
        let container = SCNNode()
        container.name = "unit_\(spec.assetName)"

        let model: SCNNode
        if let cached = cache[spec.assetName] {
            model = cached.clone()
        } else if let loaded = loadFromBundle(spec.assetName) {
            cache[spec.assetName] = loaded
            model = loaded.clone()
        } else {
            let placeholder = PlaceholderRig.make(spec: spec, archetype: archetype, element: element)
            cache[spec.assetName] = placeholder
            model = placeholder.clone()
        }

        model.name = "model"
        // Normalise the export: correct the facing, lift it to stand on the
        // ground plane, and scale it so a Titan reads as a Titan.
        model.eulerAngles.y += spec.yawCorrection * .pi / 180
        model.position.y += spec.yOffset
        let scale = spec.scale * archetype.modelScale
        model.scale = SCNVector3(scale, scale, scale)

        container.addChildNode(model)
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
        guard let url = bundleURL(for: name) else { return nil }
        guard let scene = try? SCNScene(url: url, options: [
            .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.doNotPlay,
            .convertToYUp: true,
            .createNormalsIfAbsent: true
        ]) else { return nil }

        let wrapper = SCNNode()
        for child in scene.rootNode.childNodes {
            wrapper.addChildNode(child)
        }
        MaterialTuner.tune(wrapper)
        return wrapper
    }

    private func firstAnimation(in node: SCNNode) -> CAAnimation? {
        for key in node.animationKeys {
            if let player = node.animationPlayer(forKey: key) { return player.animation }
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
                    material.roughness.contents = min(0.92, max(0.18, value.doubleValue))
                }
                if material.metalness.contents == nil {
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
}
