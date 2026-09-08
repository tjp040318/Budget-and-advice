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
        // A character with a portrait but no mesh stands in as its portrait —
        // a card in the world, billboarded, with a shadow and its element's
        // glow. It reads as a deliberate style rather than as missing art, and
        // every enemy in the roster has a portrait today while none has a
        // model. The primitive rig below remains for the case with neither.
        if let cut = UIImage(named: spec.portraitName + "_cut") {
            return sprite(portrait: cut, spec: spec, element: element, isCutout: true)
        }
        if let portrait = UIImage(named: spec.portraitName) {
            return sprite(portrait: portrait, spec: spec, element: element, isCutout: false)
        }

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

    // MARK: - Portrait sprite

    /// A billboarded portrait card: the art at ~80% of the unit's height, a
    /// soft element glow behind it, a contact shadow on the ground, and the
    /// same attachment node names the primitive rig and a real export expose.
    /// A character with art but no mesh, standing in the world.
    ///
    /// With a cut-out (`<portrait>_cut`, background keyed to transparent by
    /// `tools/cutouts.py`) this is the creature itself standing on the ground,
    /// which reads as a deliberate 2D-in-3D style. Without one it falls back to
    /// a framed card, which reads as missing art — hence the cut-outs.
    private static func sprite(
        portrait: UIImage,
        spec: ModelSpec,
        element: Element,
        isCutout: Bool
    ) -> SCNNode {
        let root = SCNNode()
        root.name = "placeholder_root"

        let tint = UIColor(hex: spec.auraHex) ?? UIColor(hex: element.accentHex) ?? .white
        let height = CGFloat(spec.height)

        // Size to the unit's real height and keep the art's aspect ratio. A
        // square plane stretched a portrait and, worse, made every creature the
        // same width regardless of shape.
        let aspect = portrait.size.height > 0 ? portrait.size.width / portrait.size.height : 1
        let artHeight = height * (isCutout ? 0.94 : 0.78)
        let artWidth = artHeight * aspect

        let plane = SCNPlane(width: artWidth, height: artHeight)
        if !isCutout { plane.cornerRadius = artHeight * 0.07 }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = portrait
        material.isDoubleSided = true
        material.blendMode = .alpha
        // A cut-out has soft edges; writing depth would cut a hard hole in
        // anything drawn behind it along that fringe.
        material.writesToDepthBuffer = !isCutout
        material.readsFromDepthBuffer = true
        plane.firstMaterial = material

        let card = SCNNode(geometry: plane)
        card.name = "portrait_card"
        card.position = SCNVector3(0, Float(artHeight / 2), 0)
        card.renderingOrder = 10
        root.addChildNode(card)

        // A soft element glow behind the figure. Kept well behind and faint so
        // it reads as light in the air rather than as the coin the figure is
        // printed on — at 0.16 alpha over the whole height it read as a token.
        let glowSize = artHeight * (isCutout ? 0.62 : 1.35)
        let glowPlane = SCNPlane(width: glowSize, height: glowSize)
        glowPlane.cornerRadius = glowSize / 2
        let glowMaterial = SCNMaterial()
        glowMaterial.lightingModel = .constant
        glowMaterial.diffuse.contents = tint.withAlphaComponent(isCutout ? 0.09 : 0.28)
        glowMaterial.blendMode = .add
        glowMaterial.writesToDepthBuffer = false
        glowMaterial.isDoubleSided = true
        glowPlane.firstMaterial = glowMaterial
        let glow = SCNNode(geometry: glowPlane)
        glow.name = "portrait_glow"
        glow.position = SCNVector3(0, Float(artHeight * (isCutout ? 0.38 : 0.45)), -0.05)
        glow.renderingOrder = 9
        root.addChildNode(glow)

        // Only a card gets a rim; a cut-out outlined in gold would look pasted.
        if !isCutout {
            let rimPlane = SCNPlane(width: artWidth * 1.04, height: artHeight * 1.04)
            rimPlane.cornerRadius = artHeight * 0.075
            let rimMaterial = SCNMaterial()
            rimMaterial.lightingModel = .constant
            rimMaterial.diffuse.contents = tint.mixed(with: .white, amount: 0.35).withAlphaComponent(0.9)
            rimMaterial.writesToDepthBuffer = false
            rimMaterial.isDoubleSided = true
            rimPlane.firstMaterial = rimMaterial
            let rim = SCNNode(geometry: rimPlane)
            rim.name = "portrait_rim"
            rim.position = SCNVector3(0, Float(artHeight / 2), -0.02)
            rim.renderingOrder = 8
            root.addChildNode(rim)
        }

        // Contact shadow on the ground, so the figure is standing on the stage
        // rather than hovering in front of it.
        let shadowPlane = SCNPlane(width: artWidth * 0.62, height: artWidth * 0.34)
        shadowPlane.cornerRadius = artWidth * 0.17
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.5)
        shadowMaterial.writesToDepthBuffer = false
        shadowPlane.firstMaterial = shadowMaterial
        let shadow = SCNNode(geometry: shadowPlane)
        shadow.name = "portrait_shadow"
        shadow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, 0.02, 0)
        shadow.renderingOrder = 7
        root.addChildNode(shadow)

        // Y-only billboard: the figure turns to face the camera but never tips,
        // so a low-angle shot does not lay it on its back.
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.Y]
        card.constraints = [billboard]
        glow.constraints = [billboard]

        // The names a real rig exposes, so VFX attachment is identical.
        for (name, fraction) in [("head", 0.86), ("spine_03", 0.55), ("hand_r", 0.42), ("weapon_r", 0.42)] {
            let anchor = SCNNode()
            anchor.name = name
            anchor.position = SCNVector3(0, Float(artHeight * CGFloat(fraction)), 0)
            root.addChildNode(anchor)
        }

        return root
    }

    // MARK: - Portrait sprite

    /// A billboarded portrait card: the art at ~80% of the unit's height, a
    /// soft element glow behind it, a contact shadow on the ground, and the
    /// same attachment node names the primitive rig and a real export expose.
    private static func sprite(portrait: UIImage, spec: ModelSpec, element: Element) -> SCNNode {
        let root = SCNNode()
        root.name = "placeholder_root"

        let tint = UIColor(hex: spec.auraHex) ?? UIColor(hex: element.accentHex) ?? .white
        let height = CGFloat(spec.height)
        let cardSize = height * 0.82
        let cardBottom = height * 0.06

        // The card itself. Constant lighting: it is a picture, and stage lights
        // raking across it would only expose that.
        let plane = SCNPlane(width: cardSize, height: cardSize)
        plane.cornerRadius = cardSize * 0.07
        let cardMaterial = SCNMaterial()
        cardMaterial.lightingModel = .constant
        cardMaterial.diffuse.contents = portrait
        cardMaterial.isDoubleSided = true
        cardMaterial.blendMode = .alpha
        cardMaterial.writesToDepthBuffer = true
        plane.firstMaterial = cardMaterial
        let card = SCNNode(geometry: plane)
        card.name = "portrait_card"
        card.position = SCNVector3(0, Float(cardBottom + cardSize / 2), 0)
        card.renderingOrder = 10

        // Element glow behind the card: an additive disc, slightly larger.
        let glowPlane = SCNPlane(width: cardSize * 1.35, height: cardSize * 1.35)
        glowPlane.cornerRadius = cardSize * 0.675
        let glowMaterial = SCNMaterial()
        glowMaterial.lightingModel = .constant
        glowMaterial.diffuse.contents = tint.withAlphaComponent(0.28)
        glowMaterial.blendMode = .add
        glowMaterial.writesToDepthBuffer = false
        glowMaterial.isDoubleSided = true
        glowPlane.firstMaterial = glowMaterial
        let glow = SCNNode(geometry: glowPlane)
        glow.name = "portrait_glow"
        glow.position = SCNVector3(0, 0, -0.03)
        glow.renderingOrder = 9
        card.addChildNode(glow)

        // Thin gold rim so the card has an edge against a bright backdrop.
        let rimPlane = SCNPlane(width: cardSize * 1.03, height: cardSize * 1.03)
        rimPlane.cornerRadius = cardSize * 0.075
        let rimMaterial = SCNMaterial()
        rimMaterial.lightingModel = .constant
        rimMaterial.diffuse.contents = tint.mixed(with: .white, amount: 0.35).withAlphaComponent(0.9)
        rimMaterial.writesToDepthBuffer = false
        rimMaterial.isDoubleSided = true
        rimPlane.firstMaterial = rimMaterial
        let rim = SCNNode(geometry: rimPlane)
        rim.name = "portrait_rim"
        rim.position = SCNVector3(0, 0, -0.015)
        rim.renderingOrder = 9
        card.addChildNode(rim)

        // Face the camera, but stay upright — a card that tilts to follow a
        // low-angle shot looks like a fridge magnet.
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        card.constraints = [billboard]
        root.addChildNode(card)

        // Contact shadow: a dark disc flat on the ground.
        let shadowPlane = SCNPlane(width: cardSize * 0.7, height: cardSize * 0.32)
        shadowPlane.cornerRadius = cardSize * 0.16
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.55)
        shadowMaterial.writesToDepthBuffer = false
        shadowPlane.firstMaterial = shadowMaterial
        let shadow = SCNNode(geometry: shadowPlane)
        shadow.name = "portrait_shadow"
        shadow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, 0.012, 0)
        shadow.renderingOrder = 8
        root.addChildNode(shadow)

        // Attachment points at the heights a humanoid would have them.
        for (name, y) in [("head", 0.92), ("spine_03", 0.62), ("hand_r", 0.5), ("weapon_r", 0.5)] {
            let anchor = SCNNode()
            anchor.name = name
            anchor.position = SCNVector3(name == "hand_r" || name == "weapon_r" ? Float(cardSize * 0.35) : 0,
                                         Float(height * y), 0)
            root.addChildNode(anchor)
        }
        return root
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
