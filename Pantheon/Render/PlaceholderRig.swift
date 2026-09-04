import Foundation
import SceneKit
import UIKit

/// Builds a stand-in character out of primitives.
///
/// This is not concept art — it is scaffolding. It exists so that combat,
/// cameras, VFX attachment and the whole UI can be finished and shipped to a
/// device before a single `.usdz` is exported, and so that a character with a
/// missing or broken asset degrades to something the size and colour it should
/// be rather than to an invisible node.
///
/// It builds the same node names a real rig must expose (`hand_r`, `spine_03`,
/// `weapon_r`, `head`), so VFX attachment code written against a placeholder
/// keeps working the day the real model arrives.
enum PlaceholderRig {

    static func make(spec: ModelSpec, archetype: Archetype, element: Element) -> SCNNode {
        let root = SCNNode()
        root.name = "placeholder_root"

        let tint = UIColor(hex: spec.auraHex) ?? UIColor(hex: element.accentHex) ?? .white
        let bodyColor = tint.mixed(with: .darkGray, amount: 0.55)
        let height = CGFloat(spec.height)

        // Proportions as fractions of total height, so a Titan and a Spirit are
        // the same figure at different scales.
        let legHeight = height * 0.46
        let torsoHeight = height * 0.32
        let headRadius = height * 0.075

        let hips = SCNNode()
        hips.name = "hips"
        hips.position = SCNVector3(0, Float(legHeight), 0)
        root.addChildNode(hips)

        // Legs
        for (offset, suffix) in [(-1.0, "l"), (1.0, "r")] {
            let leg = capsule(radius: height * 0.055, height: legHeight, color: bodyColor)
            leg.name = "leg_\(suffix)"
            leg.position = SCNVector3(Float(offset * Double(height) * 0.075), Float(-legHeight / 2), 0)
            hips.addChildNode(leg)
        }

        // Torso
        let spine = SCNNode()
        spine.name = "spine_01"
        hips.addChildNode(spine)

        let chest = capsule(radius: height * 0.105, height: torsoHeight, color: bodyColor)
        chest.name = "spine_03"
        chest.position = SCNVector3(0, Float(torsoHeight / 2), 0)
        spine.addChildNode(chest)

        // Head
        let head = SCNNode(geometry: SCNSphere(radius: headRadius))
        head.name = "head"
        head.position = SCNVector3(0, Float(torsoHeight / 2 + headRadius * 1.3), 0)
        head.geometry?.firstMaterial = material(color: bodyColor.mixed(with: tint, amount: 0.3))
        chest.addChildNode(head)

        // Arms, with attachment points at the hands.
        for (suffix, offset) in [("l", -1.0), ("r", 1.0)] {
            let shoulder = SCNNode()
            shoulder.name = "shoulder_\(suffix)"
            shoulder.position = SCNVector3(
                Float(offset * Double(height) * 0.135),
                Float(torsoHeight * 0.34),
                0
            )
            chest.addChildNode(shoulder)

            let arm = capsule(radius: height * 0.04, height: height * 0.34, color: bodyColor)
            arm.name = "arm_\(suffix)"
            arm.position = SCNVector3(0, Float(-height * 0.17), 0)
            shoulder.addChildNode(arm)

            let hand = SCNNode()
            hand.name = "hand_\(suffix)"
            hand.position = SCNVector3(0, Float(-height * 0.17), 0)
            arm.addChildNode(hand)

            if suffix == "r" {
                let weapon = SCNNode()
                weapon.name = "weapon_r"
                hand.addChildNode(weapon)
            }
        }

        // A silhouette cue so archetypes are distinguishable at a glance.
        addSilhouetteCue(to: chest, archetype: archetype, tint: tint, height: height)

        // A faint emissive core, so the aura colour reads even in shadow.
        let core = SCNNode(geometry: SCNSphere(radius: height * 0.055))
        core.name = "aura_core"
        let coreMaterial = SCNMaterial()
        coreMaterial.lightingModel = .constant
        coreMaterial.diffuse.contents = tint
        coreMaterial.emission.contents = tint
        coreMaterial.transparency = 0.55
        core.geometry?.firstMaterial = coreMaterial
        core.position = SCNVector3(0, Float(torsoHeight * 0.1), Float(height * 0.06))
        chest.addChildNode(core)

        return root
    }

    /// Reads at a glance: gods get a halo, titans get shoulder spurs, monsters
    /// get a crest, spirits get a trailing wisp.
    private static func addSilhouetteCue(
        to chest: SCNNode,
        archetype: Archetype,
        tint: UIColor,
        height: CGFloat
    ) {
        switch archetype {
        case .god, .primordial:
            let halo = SCNNode(geometry: SCNTorus(ringRadius: height * 0.12, pipeRadius: height * 0.009))
            halo.name = "cue_halo"
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = tint
            mat.emission.contents = tint
            halo.geometry?.firstMaterial = mat
            halo.position = SCNVector3(0, Float(height * 0.30), 0)
            halo.eulerAngles.x = .pi / 2.6
            chest.addChildNode(halo)
            halo.runAction(.repeatForever(.rotateBy(x: 0, y: 1.2, z: 0, duration: 4)))

        case .titan:
            for offset in [-1.0, 1.0] {
                let spur = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: height * 0.05, height: height * 0.16))
                spur.geometry?.firstMaterial = material(color: tint)
                spur.position = SCNVector3(Float(offset * Double(height) * 0.13), Float(height * 0.14), 0)
                spur.eulerAngles.z = Float(-offset * 0.5)
                chest.addChildNode(spur)
            }

        case .monster:
            let crest = SCNNode(geometry: SCNPyramid(width: height * 0.08, height: height * 0.13, length: height * 0.03))
            crest.geometry?.firstMaterial = material(color: tint)
            crest.position = SCNVector3(0, Float(height * 0.20), Float(-height * 0.03))
            chest.addChildNode(crest)

        case .spirit:
            let wisp = SCNNode(geometry: SCNSphere(radius: height * 0.035))
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = tint
            mat.emission.contents = tint
            mat.transparency = 0.4
            wisp.geometry?.firstMaterial = mat
            wisp.position = SCNVector3(0, Float(height * 0.24), Float(-height * 0.12))
            chest.addChildNode(wisp)
            wisp.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: CGFloat(height) * 0.04, z: 0, duration: 1.4),
                .moveBy(x: 0, y: CGFloat(-height) * 0.04, z: 0, duration: 1.4)
            ])))

        case .hero, .demigod:
            let mantle = SCNNode(geometry: SCNBox(
                width: height * 0.20, height: height * 0.22, length: height * 0.02, chamferRadius: height * 0.01
            ))
            mantle.geometry?.firstMaterial = material(color: tint.mixed(with: .black, amount: 0.2))
            mantle.position = SCNVector3(0, Float(height * 0.04), Float(-height * 0.09))
            chest.addChildNode(mantle)
        }
    }

    private static func capsule(radius: CGFloat, height: CGFloat, color: UIColor) -> SCNNode {
        let geometry = SCNCapsule(capRadius: radius, height: height)
        geometry.firstMaterial = material(color: color)
        return SCNNode(geometry: geometry)
    }

    private static func material(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = 0.62
        material.metalness.contents = 0.12
        return material
    }
}

extension UIColor {
    /// Parses `#RRGGBB` and `#RRGGBBAA`.
    convenience init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16) else { return nil }

        let hasAlpha = cleaned.count == 8
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(1, max(0, amount))
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
