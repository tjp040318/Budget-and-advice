import Foundation
import SceneKit
import simd

/// A cape's chain of spring bones, swung every frame.
///
/// A cape bound to the spine is a rigid board: it swung as one plate with
/// the back, and in a twisted stance it stood in front of Ares's legs on
/// every reveal frame (the owner, 2026-09-18: "ares is STILL broken"). The
/// genre's capes hang from a chain of their own joints that a spring
/// simulation moves — Summoners War's, Epic Seven's, VRM's spring bones —
/// and that is what this is. The cape pass (`tools/character.py`,
/// `reweight_cape`) gives a cape four joints of its own, `cape_0` at the
/// shoulder line down to `cape_3` above the hem, children of the spine
/// joint the sheet hangs from, and skins the free sheet to them; the clip
/// files never carry those joints, so no track ever pins them, and what
/// this class sets on their orientation each frame is what the skinner
/// draws.
///
/// The sum is VRM's, constant for constant with `tools/cape_sim.py`, which
/// renders the boards a change is judged on BEFORE it ships — change a
/// number in both files. Each joint keeps a TAIL particle in world space
/// that carries its velocity (Verlet), is drawn toward the bone's rest
/// direction in its parent's current frame (the cape follows the back it
/// hangs from), pulled down by gravity, held at the bone's length, kept out
/// of spheres on the pelvis, the chest and the legs and behind a plane
/// through the hips; the joint's rotation is whatever turns the rest
/// direction onto the tail. Nothing moves a joint's origin — that is the
/// parent's — so the chain never detaches. A sphere's push carries no
/// velocity into the next step: a thigh swinging through the hem would
/// otherwise fling the cape at ten times the speed of anything the figure
/// does. The step is fixed at 1/60 s (at most four a frame), so the phone
/// at 60 Hz, the island at 30 and the Python board agree.
///
/// Every joint of a Meshy rig carries a SCALE (0.009 on Ares, the armature's
/// own unit, cancelled by the bind), so `cape_0`'s rest transform under the
/// spine is that scale's inverse and the spine's inverse rotation. Only the
/// ORIENTATION is replaced; the rest position and scale stay, and the
/// chain's world transform is read back off the node after the set.
/// Lengths and forces are in the mesh's metres; `worldScale`, read off the
/// model node each step, maps them to the scene (1 in a battle, the island's
/// points per metre on the island).
final class ClothChain {

    /// The constants. Mirror: `tools/cape_sim.py` (STEP, DRAG, GRAVITY …).
    /// A pull is a velocity added each step and re-normalised to the bone,
    /// so it reads as an acceleration of pull / step: gravity 0.35 is
    /// 21 m/s², twice the real thing, which swings a 26 cm segment with a
    /// 0.7 s period — a heavy cloth.
    enum Cloth {
        static let step: Float = 1.0 / 60.0
        static let maxSubsteps = 4
        /// Of the tail's velocity lost per step: about half-critical
        /// damping at that period.
        static let drag: Float = 0.15
        /// Metres per step at 1.9 m; scaled by the figure's height.
        static let gravity: Float = 0.35
        /// Toward the rest direction in the parent's frame, at the shoulder
        /// line and at the hem; the joints between take a line between them.
        static let stiffnessRoot: Float = 0.25
        static let stiffnessHem: Float = 0.12
        static let referenceHeight: Float = 1.9
        /// A plane through the hips facing backward that no tail crosses,
        /// so the hem cannot swing forward between the legs when the figure
        /// stops (the spheres catch only what enters them). Its offset is
        /// the chain's rest clearance behind the pelvis, at most this share
        /// of the height.
        static let backPlaneJoint = "hips"
        static let backPlaneShare: Float = 0.06
        /// Spheres the tails stay out of: joint a, joint b, the fraction
        /// along a→b, the radius as a share of the height — the pelvis, the
        /// chest, two on each thigh, one on each shin. Every radius is
        /// capped at 0.97 of the sphere's rest distance to the chain, so
        /// nothing pushes at rest.
        static let colliders: [(a: String, b: String, fraction: Float, share: Float)] = [
            ("hips", "hips", 0.0, 0.085),
            ("spine01", "spine01", 0.0, 0.09),
            ("leftupleg", "leftleg", 0.40, 0.06), ("leftupleg", "leftleg", 0.80, 0.06),
            ("rightupleg", "rightleg", 0.40, 0.06), ("rightupleg", "rightleg", 0.80, 0.06),
            ("leftleg", "leftfoot", 0.50, 0.045), ("rightleg", "rightfoot", 0.50, 0.045)
        ]
        /// The prefix the cape pass names the joints with.
        static let jointPrefix = "cape_"
    }

    private struct Link {
        let node: SCNNode
        /// Unit, toward the child in this joint's own frame.
        let axis: SIMD3<Float>
        /// Metres of the mesh.
        let length: Float
        let stiffness: Float
        var tail = SIMD3<Float>(repeating: 0)
        var previous = SIMD3<Float>(repeating: 0)
    }

    private struct Sphere {
        let a: SCNNode
        let b: SCNNode
        let fraction: Float
        /// Metres of the mesh.
        let radius: Float
    }

    private struct Plane {
        let hips: SCNNode
        /// The backward direction in the hips' own frame.
        let backLocal: SIMD3<Float>
        /// Metres of the mesh.
        let offset: Float
    }

    /// The joint `cape_0` hangs from.
    let anchor: SCNNode
    /// The asset's name, for the console.
    let label: String
    /// Steps taken, for the console's samples.
    private var steps = 0
    /// Where the last substep put each joint, to check against SceneKit's own placement.
    private var computed: [SIMD3<Float>] = []
    /// The node whose world scale maps the mesh's metres to the scene.
    private weak var model: SCNNode?
    private var links: [Link]
    private var spheres: [Sphere] = []
    private var plane: Plane?
    /// The figure's height over 1.9 m: gravity and stiffness scale with it.
    private let unit: Float
    private var carry: Float = 0
    private var lastTime: TimeInterval?
    private var primed = false

    /// Whether the figure this chain belongs to is still alive.
    var isAlive: Bool { model != nil }

    // MARK: - Attaching

    /// Finds a cape chain in a freshly cloned figure and, if there is one,
    /// registers it with the simulation. `model` is the node the mesh hangs
    /// under (the one `ModelOrientation.normalise` scales), NOT yet placed:
    /// the rest geometry is measured in its frame.
    @discardableResult
    static func attach(to model: SCNNode, label: String) -> ClothChain? {
        guard let root = model.childNode(withName: Cloth.jointPrefix + "0", recursively: true),
              let anchor = root.parent else { return nil }
        var nodes = [root]
        while let next = nodes.last?.childNodes.first(where: { $0.name?.hasPrefix(Cloth.jointPrefix) == true }) {
            nodes.append(next)
        }
        guard nodes.count >= 2 else { return nil }
        let chain = ClothChain(model: model, anchor: anchor, nodes: nodes, label: label)
        ClothSimulation.shared.register(chain)
        #if DEBUG
        print("[ClothChain] '\(label)': \(nodes.count) cape joints under \(anchor.name ?? "?"), "
              + "\(chain.spheres.count) spheres\(chain.plane == nil ? "" : " and the back plane")")
        chain.describeAttach(nodes: nodes)
        #endif
        return chain
    }

    private init(model: SCNNode, anchor: SCNNode, nodes: [SCNNode], label: String) {
        self.model = model
        self.anchor = anchor
        self.label = label
        let height = Self.height(of: model)
        unit = height / Cloth.referenceHeight
        // The bone axis: toward the child in this joint's own frame, which is
        // world-aligned at rest (the chain's bind transforms are translations);
        // the last joint repeats the segment above it.
        var links: [Link] = []
        for (k, node) in nodes.enumerated() {
            let offset: SIMD3<Float>
            if k + 1 < nodes.count {
                offset = nodes[k + 1].simdPosition
            } else if k > 0 {
                offset = node.simdPosition
            } else {
                offset = SIMD3<Float>(0, -0.1, 0)
            }
            let length = max(simd_length(offset), 1e-6)
            let t = Float(k) / Float(max(nodes.count - 1, 1))
            let stiffness = Cloth.stiffnessRoot + (Cloth.stiffnessHem - Cloth.stiffnessRoot) * t
            links.append(Link(node: node, axis: offset / length, length: length, stiffness: stiffness))
        }
        self.links = links
        // The chain's particles at rest, in the model's frame: each joint's
        // origin plus its bone; the last one repeats the segment above it.
        var particles: [SIMD3<Float>] = []
        let origins = nodes.map { Self.vector($0.convertPosition(SCNVector3Zero, to: model)) }
        for k in origins.indices {
            if k + 1 < origins.count {
                particles.append(origins[k + 1])
            } else if k > 0 {
                particles.append(origins[k] + (origins[k] - origins[k - 1]))
            } else {
                particles.append(origins[k] + SIMD3<Float>(0, -0.1, 0))
            }
        }
        // The colliders in the bind pose, each radius capped at its rest clearance.
        for spec in Cloth.colliders {
            guard let a = Self.joint(named: spec.a, in: model), let b = Self.joint(named: spec.b, in: model) else { continue }
            let pa = Self.vector(a.convertPosition(SCNVector3Zero, to: model))
            let pb = Self.vector(b.convertPosition(SCNVector3Zero, to: model))
            let centre = pa * (1 - spec.fraction) + pb * spec.fraction
            let clearance = particles.map { simd_length($0 - centre) }.min() ?? 0
            spheres.append(Sphere(a: a, b: b, fraction: spec.fraction, radius: min(spec.share * height, 0.97 * clearance)))
        }
        // The back plane: the hips' backward direction in the hips' own
        // frame, so it turns with the pelvis, and its offset from the hips.
        if let hips = Self.joint(named: Cloth.backPlaneJoint, in: model) {
            let back = SIMD3<Float>(0, 0, -1)                       // a canonical figure faces +Z
            let hipsAt = Self.vector(hips.convertPosition(SCNVector3Zero, to: model))
            let depth = particles.map { simd_dot($0 - hipsAt, back) }.min() ?? 0
            let hipsRotation = Self.rotation(of: hips.simdWorldTransform)
            plane = Plane(hips: hips, backLocal: hipsRotation.inverse.act(back),
                          offset: min(Cloth.backPlaneShare * height, 0.97 * depth))
        }
    }

    // MARK: - Stepping

    /// Advances the chain to `time` and writes the joints' orientations.
    /// Called from a render delegate after the animations have been applied,
    /// so the anchor's presentation transform is this frame's pose.
    func step(at time: TimeInterval) {
        guard let model else { return }
        var dt = Cloth.step
        if let lastTime {
            dt = min(max(Float(time - lastTime), 0), 0.1)
        }
        lastTime = time
        let anchorWorld = anchor.presentation.simdWorldTransform
        let worldScale = max(simd_length(model.presentation.simdWorldTransform.columns.0.xyz), 1e-6)
        if !primed {
            prime(anchorWorld: anchorWorld, scale: worldScale)
            primed = true
        }
        carry += dt
        var substeps = Int(carry / Cloth.step)
        substeps = min(substeps, Cloth.maxSubsteps)
        carry -= Float(substeps) * Cloth.step
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        if substeps == 0 {
            pose(anchorWorld: anchorWorld, scale: worldScale)
        } else {
            for _ in 0..<substeps {
                substep(h: Cloth.step, anchorWorld: anchorWorld, scale: worldScale)
            }
        }
        SCNTransaction.commit()
        steps += 1
        #if DEBUG
        if steps <= 3 || steps == 60 || steps == 180 || steps == 300 {
            describeStep(anchorWorld: anchorWorld, scale: worldScale, time: time)
        }
        #endif
    }

    // MARK: - The console

    #if DEBUG
    private static func f3(_ v: SIMD3<Float>) -> String { String(format: "(%.3f, %.3f, %.3f)", v.x, v.y, v.z) }
    private static func f4(_ q: simd_quatf) -> String {
        String(format: "q(%.3f, %.3f, %.3f, %.3f)", q.vector.x, q.vector.y, q.vector.z, q.vector.w)
    }

    /// What SceneKit handed the chain at attach: the joints' own rest data,
    /// the anchor's and the hips' frames, the particles, the colliders. Read
    /// beside `tools/cape_sim.py`'s numbers for the same file.
    func describeAttach(nodes: [SCNNode]) {
        guard let model else { return }
        var lines: [String] = []
        for (k, node) in nodes.enumerated() {
            lines.append("    \(node.name ?? "?"): pos \(Self.f3(node.simdPosition)) scale \(Self.f3(node.simdScale)) "
                         + "orientation \(Self.f4(node.simdOrientation)) fromTransform \(Self.f4(Self.rotation(of: node.simdTransform))) "
                         + "axis \(Self.f3(links[k].axis)) length \(String(format: "%.3f", links[k].length))")
        }
        let anchorWorld = anchor.simdWorldTransform
        lines.append("    anchor \(anchor.name ?? "?"): world pos \(Self.f3(anchorWorld.columns.3.xyz)) rot \(Self.f4(Self.rotation(of: anchorWorld))) "
                     + "scale \(String(format: "%.4f", simd_length(anchorWorld.columns.0.xyz)))")
        if let plane {
            let hipsWorld = plane.hips.simdWorldTransform
            lines.append("    hips: world pos \(Self.f3(hipsWorld.columns.3.xyz)) rot \(Self.f4(Self.rotation(of: hipsWorld))) "
                         + "backLocal \(Self.f3(plane.backLocal)) offset \(String(format: "%.3f", plane.offset))")
        }
        lines.append("    model transform pos \(Self.f3(model.simdWorldTransform.columns.3.xyz)) rot \(Self.f4(Self.rotation(of: model.simdWorldTransform))) "
                     + "unit \(String(format: "%.3f", unit)); spheres \(spheres.map { String(format: "%.3f", $0.radius) })")
        print("[ClothChain] '\(label)' at attach:\n" + lines.joined(separator: "\n"))
    }

    /// One sample of the running chain: the anchor as presented, the rest
    /// direction, the plane, every tail's direction, and where the chain put
    /// each joint against where SceneKit presents it a frame later.
    private func describeStep(anchorWorld: simd_float4x4, scale: Float, time: TimeInterval) {
        var line = "[ClothChain] '\(label)' step \(steps) t=\(String(format: "%.2f", time)): anchor pos \(Self.f3(anchorWorld.columns.3.xyz)) "
            + "rot \(Self.f4(Self.rotation(of: anchorWorld))) worldScale \(String(format: "%.3f", scale))"
        if !links.isEmpty {
            let (position, _, restRotation) = joint(0, under: anchorWorld)
            line += "; cape_0 at \(Self.f3(position)) rest dir \(Self.f3(restRotation.act(links[0].axis)))"
        }
        if let plane {
            let hipsWorld = plane.hips.presentation.simdWorldTransform
            line += "; plane back \(Self.f3(Self.rotation(of: hipsWorld).act(plane.backLocal))) at hips \(Self.f3(hipsWorld.columns.3.xyz))"
        }
        for k in links.indices {
            let presented = links[k].node.presentation.simdWorldPosition
            let mine = k < computed.count ? computed[k] : SIMD3<Float>(repeating: 0)
            let direction = simd_length(links[k].tail - mine) > 1e-6 ? Self.normalised(links[k].tail - mine) : SIMD3<Float>(repeating: 0)
            line += "; \(links[k].node.name ?? "?") mine \(Self.f3(mine)) presented \(Self.f3(presented)) tail dir \(Self.f3(direction))"
        }
        print(line)
    }
    #endif

    /// The tails at rest under the anchor as it stands: where the chain
    /// starts, and where it returns to when a figure is rebuilt into a scene.
    private func prime(anchorWorld: simd_float4x4, scale: Float) {
        var parentWorld = anchorWorld
        for k in links.indices {
            let (position, _, restRotation) = joint(k, under: parentWorld)
            let tail = position + restRotation.act(links[k].axis) * (links[k].length * scale)
            links[k].tail = tail
            links[k].previous = tail
            links[k].node.simdOrientation = restLocalRotation(k)
            parentWorld = parentWorld * links[k].node.simdTransform
        }
    }

    /// A link's world position, its parent's world rotation and its own REST
    /// world rotation under a parent world transform.
    private func joint(_ k: Int, under parentWorld: simd_float4x4) -> (SIMD3<Float>, simd_quatf, simd_quatf) {
        let parentRotation = Self.rotation(of: parentWorld)
        let local = links[k].node.simdPosition
        let position = (parentWorld * SIMD4<Float>(local.x, local.y, local.z, 1)).xyz
        return (position, parentRotation, parentRotation * restLocalRotation(k))
    }

    /// The joint's rest orientation in its parent's frame: the spine's
    /// inverse for `cape_0`, identity below it. Read once, kept.
    private func restLocalRotation(_ k: Int) -> simd_quatf {
        if k < restLocal.count { return restLocal[k] }
        return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    }
    private lazy var restLocal: [simd_quatf] = self.links.map { Self.rotation(of: $0.node.simdTransform) }

    private func substep(h: Float, anchorWorld: simd_float4x4, scale: Float) {
        let centres: [(SIMD3<Float>, Float)] = spheres.map { sphere in
            let pa = sphere.a.presentation.simdWorldPosition
            let pb = sphere.b.presentation.simdWorldPosition
            return (pa * (1 - sphere.fraction) + pb * sphere.fraction, sphere.radius * scale)
        }
        var planeNow: (point: SIMD3<Float>, back: SIMD3<Float>, offset: Float)?
        if let plane {
            let hipsWorld = plane.hips.presentation.simdWorldTransform
            planeNow = (hipsWorld.columns.3.xyz, Self.rotation(of: hipsWorld).act(plane.backLocal), plane.offset * scale)
        }
        var parentWorld = anchorWorld
        for k in links.indices {
            let (position, parentRotation, restRotation) = joint(k, under: parentWorld)
            let restDirection = restRotation.act(links[k].axis)
            let length = links[k].length * scale
            let tail = links[k].tail
            var next = tail + (tail - links[k].previous) * (1 - Cloth.drag)
                + restDirection * (links[k].stiffness * unit * scale * h)
                + SIMD3<Float>(0, -Cloth.gravity * unit * scale * h, 0)
            next = position + Self.normalised(next - position) * length
            let free = next
            for (centre, radius) in centres {
                let away = next - centre
                let distance = simd_length(away)
                if distance < radius {
                    next = centre + Self.normalised(away) * radius
                    next = position + Self.normalised(next - position) * length
                }
            }
            if let planeNow {
                let depth = simd_dot(next - planeNow.point, planeNow.back)
                if depth < planeNow.offset {
                    next += planeNow.back * (planeNow.offset - depth)
                    next = position + Self.normalised(next - position) * length
                }
            }
            links[k].previous = tail + (next - free)
            links[k].tail = next
            let worldRotation = Self.swing(from: restDirection, to: Self.normalised(next - position)) * restRotation
            links[k].node.simdOrientation = simd_normalize(parentRotation.inverse * worldRotation)
            parentWorld = parentWorld * links[k].node.simdTransform
            if computed.count <= k { computed.append(position) } else { computed[k] = position }
        }
    }

    /// No substep this frame: re-derive the pose from the tails as they stand.
    private func pose(anchorWorld: simd_float4x4, scale: Float) {
        var parentWorld = anchorWorld
        for k in links.indices {
            let (position, parentRotation, restRotation) = joint(k, under: parentWorld)
            let restDirection = restRotation.act(links[k].axis)
            let worldRotation = Self.swing(from: restDirection, to: Self.normalised(links[k].tail - position)) * restRotation
            links[k].node.simdOrientation = simd_normalize(parentRotation.inverse * worldRotation)
            parentWorld = parentWorld * links[k].node.simdTransform
        }
    }

    // MARK: - Small sums

    private static func vector(_ v: SCNVector3) -> SIMD3<Float> {
        SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
    }

    private static func normalised(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let n = simd_length(v)
        return n > 1e-9 ? v / n : SIMD3<Float>(0, -1, 0)
    }

    /// The rotation taking unit vector `a` onto unit vector `b`; a half turn
    /// about any perpendicular when they are opposed.
    private static func swing(from a: SIMD3<Float>, to b: SIMD3<Float>) -> simd_quatf {
        let c = simd_dot(a, b)
        if c < -0.9999 {
            var helper = SIMD3<Float>(1, 0, 0)
            if abs(a.x) > 0.9 { helper = SIMD3<Float>(0, 1, 0) }
            return simd_quatf(angle: .pi, axis: normalised(simd_cross(a, helper)))
        }
        return simd_normalize(simd_quatf(from: a, to: b))
    }

    /// The rotation of a world transform, its scale stripped.
    private static func rotation(of m: simd_float4x4) -> simd_quatf {
        let c0 = normalised(m.columns.0.xyz)
        let c1 = normalised(m.columns.1.xyz)
        let c2 = normalised(m.columns.2.xyz)
        return simd_normalize(simd_quatf(simd_float3x3(columns: (c0, c1, c2))))
    }

    /// The figure's bind-pose height in the model's frame: every geometry's
    /// box, its corners carried into that frame.
    private static func height(of model: SCNNode) -> Float {
        var low = Float.greatestFiniteMagnitude
        var high = -Float.greatestFiniteMagnitude
        model.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let box = node.boundingBox
            for corner in [box.min, box.max] {
                let y = node.convertPosition(corner, to: model).y
                low = min(low, y)
                high = max(high, y)
            }
        }
        return high > low ? high - low : Cloth.referenceHeight
    }

    /// A joint by its lowercased name (Meshy's rigs mix cases: `neck`, `Spine01`).
    private static func joint(named key: String, in model: SCNNode) -> SCNNode? {
        let matches = model.childNodes { node, stop in
            if node.name?.lowercased() == key { stop.pointee = true; return true }
            return false
        }
        return matches.first
    }
}

/// Every live chain, stepped from whichever render delegate is drawing the
/// scene its figure stands in. Chains are dropped as their figures go.
final class ClothSimulation {
    static let shared = ClothSimulation()
    private let lock = NSLock()
    private var chains: [ClothChain] = []

    private init() {}

    func register(_ chain: ClothChain) {
        lock.lock()
        chains.removeAll { !$0.isAlive }
        chains.append(chain)
        lock.unlock()
    }

    /// Steps the chains whose figures stand in `scene`. Call from
    /// `renderer(_:didApplyAnimationsAtTime:)`: the anchors' presentation
    /// transforms carry this frame's pose there, and what the chains set on
    /// the model tree is drawn in the same frame.
    func step(in scene: SCNScene?, at time: TimeInterval) {
        guard let root = scene?.rootNode else { return }
        lock.lock()
        chains.removeAll { !$0.isAlive }
        let live = chains
        lock.unlock()
        for chain in live where chain.stands(under: root) {
            chain.step(at: time)
        }
    }
}

extension ClothChain {
    /// Whether the chain's anchor hangs somewhere under `root`.
    func stands(under root: SCNNode) -> Bool {
        var node: SCNNode? = anchor
        while let current = node {
            if current === root { return true }
            node = current.parent
        }
        return false
    }
}

/// A render delegate for a stage that has none of its own — the reveal and
/// the island — whose one job is to step the cloth each frame. The view's
/// `delegate` is weak, so the coordinator holds this.
final class ClothStepper: NSObject, SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        ClothSimulation.shared.step(in: renderer.scene, at: time)
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}
