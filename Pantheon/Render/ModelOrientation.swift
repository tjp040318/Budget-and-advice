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

    /// Rotates `model` so its longest axis is +Y and translates it so its
    /// lowest point sits on y = 0. `model` must already be a child of `parent`.
    /// Returns a one-line description of what it did, for the debug log.
    @discardableResult
    static func standUp(_ model: SCNNode, in parent: SCNNode) -> String {
        guard let box = bounds(of: model, in: model) else { return "no geometry" }
        let extent = SCNVector3(box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z)
        // Which end of the long axis the mesh mostly occupies. With the origin
        // at the feet the body extends toward the positive end; if it extends
        // negative, the head is on the far side and the rotation flips sign.
        let centreX = (box.min.x + box.max.x) * 0.5
        let centreZ = (box.min.z + box.max.z) * 0.5

        var note = "already Y-up"
        if extent.z > extent.y, extent.z > extent.x {
            // Z is height. Rotate about X so +Z → +Y (or −Z → +Y).
            let sign: Float = centreZ >= 0 ? -1 : 1
            model.eulerAngles.x += sign * .pi / 2
            note = "Z-up export (\(fmt(extent))) — pitched \(Int(sign * -90))°"
        } else if extent.x > extent.y, extent.x > extent.z {
            // X is height. Rotate about Z so +X → +Y (or −X → +Y).
            let sign: Float = centreX >= 0 ? 1 : -1
            model.eulerAngles.z += sign * .pi / 2
            note = "X-up export (\(fmt(extent))) — rolled \(Int(sign * 90))°"
        }

        // Ground it. Recomputed in the parent's space so the rotation above is
        // included; the model has unit scale at this point so the offset is in
        // metres.
        if let placed = bounds(of: model, in: parent) {
            let lift = -placed.min.y
            if abs(lift) > 0.001 {
                model.position.y += lift
                note += String(format: ", feet lifted %.2f m", lift)
            }
        }
        return note
    }

    private static func fmt(_ v: SCNVector3) -> String {
        String(format: "x%.1f y%.1f z%.1f", v.x, v.y, v.z)
    }
}
