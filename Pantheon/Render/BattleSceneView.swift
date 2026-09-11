import SwiftUI
import SceneKit
import SpriteKit
import UIKit

/// Bridges the SceneKit battle stage into SwiftUI, and lays the unit plates
/// over it.
///
/// The controller is created once and owned by the battle view model, not by
/// this struct — SwiftUI rebuilds `View` values constantly, and rebuilding a
/// scene graph on every layout pass would drop the battle.
///
/// The plates — every unit's health bar and attack bar — are a SpriteKit
/// scene drawn over the 3D view (`overlaySKScene`), the mechanism Apple's
/// own SceneKit samples use for a HUD, so a bar is drawn in points, as crisp
/// as the rest of the HUD and the same size in both rows. The coordinator is
/// the renderer's delegate and places them under the units' feet on every
/// frame, from the camera about to draw.
struct BattleSceneView: UIViewRepresentable {

    let controller: BattleSceneController
    /// Called with the combatant a tap landed on, for target selection.
    var onTapUnit: ((UUID) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        // The camera is directed by CameraDirector; free orbit would fight it.
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.overlaySKScene = controller.plates
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTapUnit = onTapUnit
        context.coordinator.controller = controller
        if view.scene !== controller.scene { view.scene = controller.scene }
        if view.overlaySKScene !== controller.plates { view.overlaySKScene = controller.plates }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, onTapUnit: onTapUnit)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var onTapUnit: ((UUID) -> Void)?
        weak var view: SCNView?
        weak var controller: BattleSceneController?

        init(controller: BattleSceneController, onTapUnit: ((UUID) -> Void)?) {
            self.controller = controller
            self.onTapUnit = onTapUnit
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view, let onTapUnit else { return }
            let point = recognizer.location(in: view)
            let hits = view.hitTest(point, options: [
                .boundingBoxOnly: true,
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            // Walk up from whatever geometry was hit to the owning UnitNode.
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let unitNode = current as? UnitNode {
                        onTapUnit(unitNode.combatantID)
                        return
                    }
                    node = current.parent
                }
            }
        }

        /// The frame is about to be drawn with the camera where it now
        /// stands: put every plate under its unit's feet for it.
        func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
            controller?.layoutPlates(in: renderer)
        }
    }
}

// MARK: - The unit plates

/// The screen-space layer of unit plates over the battle: one `UnitPlate`
/// per fighter, in points. Transparent, never touched by the player (taps go
/// through to the 3D view), sized to the view by `resizeFill`.
final class UnitPlateOverlay: SKScene {

    private var plates: [UUID: UnitPlate] = [:]

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("UnitPlateOverlay is created in code") }

    func plate(for id: UUID) -> UnitPlate? { plates[id] }

    @discardableResult
    func addPlate(for id: UUID, elementHex: String) -> UnitPlate {
        plates[id]?.removeFromParent()
        let plate = UnitPlate(elementHex: elementHex)
        plates[id] = plate
        addChild(plate)
        return plate
    }

    func removePlate(for id: UUID) {
        plates[id]?.removeFromParent()
        plates[id] = nil
    }

    func removeAllPlates() {
        for plate in plates.values { plate.removeFromParent() }
        plates.removeAll()
    }
}

/// One fighter's bars, the genre's way: a slim green health bar under the
/// feet with a dark rounded track, a gradient fill and a cream trail that
/// lingers a beat after a hit, the thinner light-blue attack bar under it
/// that fills toward the unit's turn and turns gold when it is ready, the
/// element pip at the left end, the status tiles above, the matchup arrow at
/// the right, and a gold rim while the unit is acting. Every size here is in
/// points and the same in both rows, which is what makes health comparable
/// across the field and the bars as crisp as the HUD.
final class UnitPlate: SKNode {

    static let barWidth: CGFloat = 76
    static let hpHeight: CGFloat = 8
    static let atbHeight: CGFloat = 3.5
    /// The health bar's centre sits this far under the projected feet.
    static let dropBelowFeet: CGFloat = 12
    static let tile: CGFloat = 13

    private let hpFill: SKSpriteNode
    private let hpMask: SKSpriteNode
    private let trailMask: SKSpriteNode
    private let atbFill: SKSpriteNode
    private let atbMask: SKSpriteNode
    private let statusRow = SKNode()
    private let badge: SKSpriteNode
    private let rim: SKSpriteNode
    private let fullTexture: SKTexture
    private let lowTexture: SKTexture
    private let atbTexture: SKTexture
    private let readyTexture: SKTexture
    private var shownFraction: CGFloat = 1

    init(elementHex: String) {
        let w = UnitPlate.barWidth
        let h = UnitPlate.hpHeight
        let a = UnitPlate.atbHeight
        let full = PlateArt.fill("hp", width: w, height: h, radius: 2.5, top: "#9CF2B0", bottom: "#3DB868")
        let low = PlateArt.fill("hp_low", width: w, height: h, radius: 2.5, top: "#FFD27A", bottom: "#E0762E")
        let trail = PlateArt.fill("hp_trail", width: w, height: h, radius: 2.5, top: "#FFF6E6", bottom: "#E8CBA8")
        let atb = PlateArt.fill("atb", width: w, height: a, radius: 1.5, top: "#B4EEFF", bottom: "#3AA6DE")
        let ready = PlateArt.fill("atb_ready", width: w, height: a, radius: 1.5, top: "#FFF3C4", bottom: "#E8B44A")
        fullTexture = full
        lowTexture = low
        atbTexture = atb
        readyTexture = ready

        let hpFillNode = SKSpriteNode(texture: full)
        hpFillNode.size = CGSize(width: w, height: h)
        let trailFillNode = SKSpriteNode(texture: trail)
        trailFillNode.size = CGSize(width: w, height: h)
        let atbFillNode = SKSpriteNode(texture: atb)
        atbFillNode.size = CGSize(width: w, height: a)
        let badgeNode = SKSpriteNode(color: .clear, size: CGSize(width: 14, height: 14))
        badgeNode.isHidden = true
        let rimNode = SKSpriteNode(texture: PlateArt.rim("rim_acting", width: w + 12, height: h + a + 12, radius: 6, hex: "#F2C75C"))
        rimNode.size = CGSize(width: w + 12, height: h + a + 12)
        rimNode.isHidden = true

        hpFill = hpFillNode
        hpMask = UnitPlate.mask(width: w, height: h)
        trailMask = UnitPlate.mask(width: w, height: h)
        atbFill = atbFillNode
        atbMask = UnitPlate.mask(width: w, height: a)
        badge = badgeNode
        rim = rimNode
        super.init()

        let hpY: CGFloat = 0
        let atbY: CGFloat = -(h / 2 + 2 + a / 2)

        rim.position = CGPoint(x: 0, y: (hpY + atbY) / 2)
        rim.zPosition = 0
        addChild(rim)

        let hpTrack = SKSpriteNode(texture: PlateArt.track("hp_track", width: w + 2, height: h + 2, radius: 3.5))
        hpTrack.size = CGSize(width: w + 2, height: h + 2)
        hpTrack.position = CGPoint(x: 0, y: hpY)
        hpTrack.zPosition = 1
        addChild(hpTrack)

        let trailCrop = SKCropNode()
        trailCrop.maskNode = trailMask
        trailCrop.addChild(trailFillNode)
        trailCrop.position = CGPoint(x: 0, y: hpY)
        trailCrop.zPosition = 2
        addChild(trailCrop)

        let hpCrop = SKCropNode()
        hpCrop.maskNode = hpMask
        hpCrop.addChild(hpFill)
        hpCrop.position = CGPoint(x: 0, y: hpY)
        hpCrop.zPosition = 3
        addChild(hpCrop)

        let atbTrack = SKSpriteNode(texture: PlateArt.track("atb_track", width: w + 2, height: a + 2, radius: 2.5))
        atbTrack.size = CGSize(width: w + 2, height: a + 2)
        atbTrack.position = CGPoint(x: 0, y: atbY)
        atbTrack.zPosition = 1
        addChild(atbTrack)

        let atbCrop = SKCropNode()
        atbCrop.maskNode = atbMask
        atbCrop.addChild(atbFill)
        atbCrop.position = CGPoint(x: 0, y: atbY)
        atbCrop.zPosition = 3
        addChild(atbCrop)

        let pip = SKSpriteNode(texture: PlateArt.pip(elementHex))
        pip.size = CGSize(width: 10, height: 10)
        pip.position = CGPoint(x: -w / 2 - 8, y: hpY)
        pip.zPosition = 4
        addChild(pip)

        statusRow.position = CGPoint(x: 0, y: hpY + h / 2 + 2 + UnitPlate.tile / 2)
        statusRow.zPosition = 4
        addChild(statusRow)

        badge.position = CGPoint(x: w / 2 + 11, y: hpY)
        badge.zPosition = 4
        addChild(badge)
    }

    required init?(coder: NSCoder) { fatalError("UnitPlate is created in code") }

    /// A crop mask anchored on the bar's left edge, so a scale in x is a fill
    /// that empties toward the left with its round ends intact.
    private static func mask(width: CGFloat, height: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(color: .white, size: CGSize(width: width, height: height + 2))
        node.anchorPoint = CGPoint(x: 0, y: 0.5)
        node.position = CGPoint(x: -width / 2, y: 0)
        return node
    }

    // MARK: State

    /// The health bar. A hit drops the fill at once and the cream trail
    /// follows after a beat, so the size of the blow is read off the bar;
    /// a heal lifts both together.
    func setHealth(_ fraction: Double, animated: Bool) {
        let clamped = CGFloat(min(1, max(0, fraction)))
        // Never below a sliver while there is health at all.
        let target = fraction > 0 ? max(0.03, clamped) : 0.001
        hpMask.removeAction(forKey: "hp")
        trailMask.removeAction(forKey: "trail")
        if animated {
            let drop = SKAction.scaleX(to: target, duration: 0.18)
            drop.timingMode = .easeOut
            hpMask.run(drop, withKey: "hp")
            if target < shownFraction {
                let follow = SKAction.scaleX(to: target, duration: 0.32)
                follow.timingMode = .easeIn
                trailMask.run(.sequence([.wait(forDuration: 0.35), follow]), withKey: "trail")
            } else {
                let lift = SKAction.scaleX(to: target, duration: 0.18)
                lift.timingMode = .easeOut
                trailMask.run(lift, withKey: "trail")
            }
        } else {
            hpMask.xScale = target
            trailMask.xScale = target
        }
        hpFill.texture = clamped < 0.3 ? lowTexture : fullTexture
        shownFraction = target
    }

    /// The attack bar: the fraction of the way to the unit's next turn, gold
    /// and pulsing once it is full.
    func setAttackBar(_ value: Double, animated: Bool) {
        let target = CGFloat(min(1, max(0, value)))
        let shown = max(0.001, target)
        atbMask.removeAction(forKey: "atb")
        if animated {
            let move = SKAction.scaleX(to: shown, duration: 0.45)
            move.timingMode = .easeInEaseOut
            atbMask.run(move, withKey: "atb")
        } else {
            atbMask.xScale = shown
        }
        let ready = target >= 0.999
        atbFill.texture = ready ? readyTexture : atbTexture
        atbFill.removeAction(forKey: "pulse")
        if ready {
            atbFill.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.65, duration: 0.45),
                .fadeAlpha(to: 1.0, duration: 0.45)
            ])), withKey: "pulse")
        } else {
            atbFill.alpha = 1
        }
    }

    /// The buffs and debuffs as a row of tiles over the health bar: one per
    /// kind, the longest-lasting of each, six at most.
    func setStatuses(_ statuses: [ActiveStatus]) {
        statusRow.removeAllChildren()
        var byKind: [StatusKind: Int] = [:]
        for status in statuses { byKind[status.kind] = max(byKind[status.kind] ?? 0, status.turnsRemaining) }
        let shown = byKind.sorted { $0.key.rawValue < $1.key.rawValue }.prefix(6)
        guard !shown.isEmpty else { return }
        let spacing = UnitPlate.tile + 1
        let totalWidth = spacing * CGFloat(shown.count - 1)
        for (index, entry) in shown.enumerated() {
            guard let image = StatusIconRenderer.image(kind: entry.key, turns: entry.value) else { continue }
            let tile = SKSpriteNode(texture: SKTexture(image: image))
            tile.size = CGSize(width: UnitPlate.tile, height: UnitPlate.tile)
            tile.position = CGPoint(x: -totalWidth / 2 + spacing * CGFloat(index), y: 0)
            statusRow.addChild(tile)
        }
    }

    /// The advantage arrow at the bar's right end on a player's turn.
    func setMatchup(_ matchup: Element.Matchup?) {
        guard let matchup else {
            badge.isHidden = true
            return
        }
        badge.texture = SKTexture(image: MatchupIconRenderer.image(for: matchup))
        badge.isHidden = false
    }

    /// The gold rim while this unit acts.
    func setActing(_ acting: Bool) {
        rim.removeAction(forKey: "pulse")
        rim.isHidden = !acting
        if acting {
            rim.alpha = 1
            rim.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 0.6),
                .fadeAlpha(to: 1.0, duration: 0.6)
            ])), withKey: "pulse")
        }
    }

    /// The plate goes with its unit: out with a death, back with a revival.
    func setDefeated(_ defeated: Bool) {
        removeAction(forKey: "fade")
        run(defeated ? .fadeOut(withDuration: 0.4) : .fadeIn(withDuration: 0.3), withKey: "fade")
    }
}

/// The plates' pictures, drawn once each with Core Graphics at 3× and kept:
/// a track, a fill, a pip and a rim.
enum PlateArt {

    private static var cache: [String: SKTexture] = [:]

    private static func texture(_ key: String, size: CGSize, draw: (CGContext, CGRect) -> Void) -> SKTexture {
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext, CGRect(origin: .zero, size: size))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    private static func color(_ hex: String) -> UIColor {
        UIColor(hex: hex) ?? .white
    }

    private static func paintGradient(_ context: CGContext, in rect: CGRect, path: CGPath, top: UIColor, bottom: UIColor) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
        }
        context.restoreGState()
    }

    /// The dark rounded track a bar sits in, with a hairline of shadow round
    /// it so it reads over a bright floor.
    static func track(_ key: String, width: CGFloat, height: CGFloat, radius: CGFloat) -> SKTexture {
        texture(key, size: CGSize(width: width, height: height)) { context, rect in
            let inner = rect.insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: inner, cornerRadius: radius).cgPath
            paintGradient(context, in: inner, path: path, top: color("#2A211A").withAlphaComponent(0.92), bottom: color("#120D09").withAlphaComponent(0.92))
            context.addPath(path)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
    }

    /// A bar's fill: a vertical gradient with a light edge along the top.
    static func fill(_ key: String, width: CGFloat, height: CGFloat, radius: CGFloat, top: String, bottom: String) -> SKTexture {
        texture(key, size: CGSize(width: width, height: height)) { context, rect in
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
            paintGradient(context, in: rect, path: path, top: color(top), bottom: color(bottom))
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            context.fill(CGRect(x: rect.minX + 1, y: rect.minY + 0.5, width: rect.width - 2, height: max(0.8, rect.height * 0.14)))
            context.restoreGState()
        }
    }

    /// The element pip at the bar's left end: a small sphere in the element's
    /// colour with a dark rim and a glint.
    static func pip(_ hex: String) -> SKTexture {
        texture("pip_\(hex)", size: CGSize(width: 10, height: 10)) { context, rect in
            let circle = rect.insetBy(dx: 0.75, dy: 0.75)
            let path = UIBezierPath(ovalIn: circle).cgPath
            let base = color(hex)
            paintGradient(context, in: circle, path: path, top: base, bottom: base.withAlphaComponent(0.6))
            context.addPath(path)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1)
            context.strokePath()
            context.setFillColor(UIColor.white.withAlphaComponent(0.55).cgColor)
            context.fillEllipse(in: CGRect(x: circle.minX + 2, y: circle.minY + 1.5, width: 2.6, height: 1.8))
        }
    }

    /// A soft gold rim round the acting unit's plate.
    static func rim(_ key: String, width: CGFloat, height: CGFloat, radius: CGFloat, hex: String) -> SKTexture {
        texture(key, size: CGSize(width: width, height: height)) { context, rect in
            let base = color(hex)
            for (inset, lineWidth, alpha) in [(2.0, 4.0, 0.16), (2.5, 2.5, 0.35), (3.0, 1.2, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
                let path = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: radius).cgPath
                context.addPath(path)
                context.setStrokeColor(base.withAlphaComponent(alpha).cgColor)
                context.setLineWidth(lineWidth)
                context.strokePath()
            }
        }
    }
}
