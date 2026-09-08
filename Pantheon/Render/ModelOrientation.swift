import Foundation
import SceneKit

/// Stands an imported model up and puts its feet on the ground, whatever axis
/// the exporter thought was "up".
///
/// USD, glTF and every generator disagree about up-axis and origin, and
/// `SCNScene`'s `convertToYUp` only honours what the file *declares* — a rig
/// that was authored lying down is declared upright and arrives lying down.
/// Rather than a per-model rotation someone has to discover by rebuilding,
/// this reads the mesh: a humanoid's longest bounding-box axis is its height,
/// so whichever axis that is gets rotated to +Y, and the lowest point is then
/// moved to y = 0.
///
/// `ModelSpec.pitchCorrection`, `yawCorrection` and `yOffset` are applied
/// *after* this, so they remain available as overrides for the cases a
/// bounding box cannot decide — chiefly which way the model faces, which no
/// box can tell you.
enum ModelOrientation {

    /// Bounding box of every piece of geometry under `root`, expressed in
    /// `space`'s coordinates. `SCNNode.boundingBox` on a parent is not
    /// reliably hierarchical, so this walks the tree and accumulates corners.
    static func bounds(of root: SCNNode, in space: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var lo = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var hi = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var found = false

        root.enumerateHierarchy { child, _ in
            guard child.geometry != nil else { return }
            let box = child.boundingBox
            let xs = [box.min.x, box.max.x], ys = [box.min.y, box.max.y], zs = [box.min.z, box.max.z]
            for x in xs { for y in ys { for z in zs {
                let p = child.convertPosition(SCNVector3(x, y, z), to: space)
                lo = SCNVector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = SCNVector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
                found = true
            } } }
        }
        return found ? (lo, hi) : nil
    }

    /// Stands a model up, scales it to its declared height, and puts it on
    /// the ground at the origin. `model` must already be a child of `parent`.
    /// Returns a one-line description for the debug log.
    ///
    /// Scale is the part that cannot be skipped. A generator exports in
    /// whatever units its own pipeline used — the Anubis export measures 320
    /// units tall with `metersPerUnit = 1`, so taken at face value he is a
    /// 320-metre statue standing 100 metres off the origin. Nothing downstream
    /// can recover from that: the camera frames two metres of world, so the
    /// figure fills the screen with an arbitrary slice of its own shin.
    @discardableResult
    static func normalise(_ model: SCNNode, in parent: SCNNode, targetHeight: Float) -> String {
        guard let box = bounds(of: model, in: model) else { return "no geometry" }
        let extent = SCNVector3(box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z)
        let centreX = (box.min.x + box.max.x) * 0.5
        let centreZ = (box.min.z + box.max.z) * 0.5

        var note = "Y-up"
        if extent.z > extent.y, extent.z > extent.x {
            let sign: Float = centreZ >= 0 ? -1 : 1
            model.eulerAngles.x += sign * .pi / 2
            note = "Z-up, pitched \(Int(sign * -90))°"
        } else if extent.x > extent.y, extent.x > extent.z {
            let sign: Float = centreX >= 0 ? 1 : -1
            model.eulerAngles.z += sign * .pi / 2
            note = "X-up, rolled \(Int(sign * 90))°"
        }

        // Measure again in the parent's frame so the rotation above is included,
        // then scale the standing height to what the roster says the unit is.
        guard let stood = bounds(of: model, in: parent) else { return note + ", no bounds" }
        let standingHeight = stood.max.y - stood.min.y
        guard standingHeight > 0.0001, targetHeight > 0 else { return note + ", zero height" }

        let factor = targetHeight / standingHeight
        model.scale = SCNVector3(model.scale.x * factor, model.scale.y * factor, model.scale.z * factor)
        note += String(format: ", %.1f units → %.2f m (×%.4f)", standingHeight, targetHeight, factor)

        // Finally centre it over the origin and stand it on the ground. A
        // generator puts the origin wherever its own bind pose happened to sit,
        // which for this export is about a third of the way up the torso and a
        // hundred units to one side.
        if let placed = bounds(of: model, in: parent) {
            model.position.x -= (placed.min.x + placed.max.x) * 0.5
            model.position.z -= (placed.min.z + placed.max.z) * 0.5
            model.position.y -= placed.min.y
        }
        return note
    }

    private static func fmt(_ v: SCNVector3) -> String {
        String(format: "x%.1f y%.1f z%.1f", v.x, v.y, v.z)
    }
}
