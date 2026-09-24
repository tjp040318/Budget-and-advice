import CoreImage
import SceneKit
import UIKit

/// THE ARENA FLOOR AS A DESIGNED PIECE (2026-09-24). The owner, with two
/// Summoners War battles beside ours: "Look how clean the game looks … I
/// want THIS level." What his frames stand on is not a tiled slab with a
/// groove scratched in it: it is a round arena laid in stone — radial
/// courses with crisp grout, a broad inlaid band of gold running round
/// both teams, a gold emblem at the centre, enamel plaques on the inner
/// ring — and it is sharp at every depth. Ours was painted sandstone at
/// 77% saturation under a 1024-pixel multiply quad of thin dark rings.
///
/// Three ways were weighed (Docs/PLAN.md, *The arena medallion*): a painted
/// top-down arena per realm through Meshy's picture endpoint (6 credits a
/// picture, seven at most over the owner's floor, and a single 2048-pixel
/// picture over 15 m is soft at the team's feet and cannot be re-cut per
/// realm); one large procedural image of the whole medallion (the same
/// resolution ceiling — a 4096 texture is 85 MB with its mips); and what
/// is built here: the medallion as GEOMETRY, one mesh per course, each
/// course a ring of stones whose texture is ONE stone repeated round it.
/// A stone is 512 pixels across about a metre and the gold band's
/// ornament 256 pixels across 0.9 m, so the floor holds 270–500 texels a
/// metre wherever the camera looks — more than the screen can show at the
/// team's row — for about 8 MB of textures with their mips. Each stone's shade is a vertex
/// colour, so no two neighbours match; every stone, the band and the
/// emblem carry a relief map derived from their own drawing, so the key
/// light catches every grout line and every edge of the ornament; the band
/// stands 2 cm proud of the stone with real walls. Everything is drawn
/// here at runtime, per pantheon: a lotus-and-bud band and a lotus rosette
/// for Egypt, the meander and a sixteen-rayed sun for Greece, a two-strand
/// braid and three interlaced triangles for the Norse, a laurel band and
/// wreath for Rome, the square fret and a taiji in its eight trigrams for
/// the Jade Court.
extension StageBuilder {

    /// How far each row stands from the arena's centre, in metres — the
    /// medallion is sized off it so the broad band runs round both teams
    /// (the genre's frame: the enemies on the band's far arc, the team
    /// just inside its near one). KEEP IN STEP with the `depth` of
    /// `BattleSceneController.position(for:teamSize:)`: 5.2 is the row
    /// depth the Summoners War frames measured (rows 10.4 m apart).
    static let arenaRowDepth: Float = 5.2

    /// Where the medallion's centre stands: midway between the rows.
    /// z 1.8 (2026-09-24, the camera's pass): `BattleSceneController.
    /// position(for:teamSize:)` stands its rows at `arenaCentre.z ±
    /// arenaRowDepth` — the team at +7.0, the enemies at −3.4 — because at
    /// ±5.2 about the origin the enemy row stood in the sets' back row (the
    /// columns at z −7, the braziers at −5.6, the temple ruin at −7.6) and
    /// two metres from the far rim. The whole field moved toward the camera
    /// instead, and the medallion with it.
    static let arenaCentre = SCNVector3(0, 0, 1.8)

    /// How much of its colour the slab's painted tile keeps, and its tint.
    /// Summoners War's arena stone is 3–6% saturated and ours was 77%: the
    /// tiles are desaturated when a stage is built (`calmedFloorImage`)
    /// rather than repainted, so the realm's hue survives as a hint.
    static let arenaFloorSaturation: CGFloat = 0.5

    enum ArenaFloorMotif {
        case lotus, meander, braid, laurel, fret
    }

    struct ArenaFloorStyle {
        var key: String
        var motif: ArenaFloorMotif
        var stone: UIColor
        var grout: UIColor
        var gold: UIColor
        var goldLight: UIColor
        var goldDark: UIColor
        var accent: UIColor
    }

    struct ArenaFloorArt {
        var stone: UIImage
        var stoneRelief: UIImage?
        var band: UIImage
        var bandRelief: UIImage?
        var bead: UIImage
        var beadRelief: UIImage?
        var emblem: UIImage
        var emblemRelief: UIImage?
        var plaque: UIImage
        var gem: UIImage
    }

    /// The realm's palette: its pantheon's motif and enamel, and a pale
    /// stone taken from the floor's own tint with most of its colour
    /// taken out (the tint keeps the realm's hue; the stone is what SW's
    /// is, near-grey and light).
    static func arenaStyle(for environment: BattleEnvironment, floorTint: String?) -> ArenaFloorStyle {
        let motif: ArenaFloorMotif
        let accentHex: String
        switch environment.pantheon {
        case .egyptian:
            motif = .lotus
            accentHex = "#2F5E9E"      // lapis
        case .norse:
            motif = .braid
            accentHex = "#4C7BA6"      // steel blue
        case .roman:
            motif = .laurel
            accentHex = "#9A302A"      // Roman red
        case .chinese:
            motif = .fret
            accentHex = "#2E8A66"      // jade
        default:
            motif = .meander
            accentHex = "#2A8C9C"      // the genre's teal
        }
        let tint = UIColor(hex: floorTint ?? "#A89C8C") ?? .gray
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        tint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let light = min(0.78, max(0.6, brightness + 0.14))
        let stone = UIColor(hue: hue, saturation: min(0.14, saturation * 0.4), brightness: light, alpha: 1)
        let grout = UIColor(hue: hue, saturation: min(0.22, saturation * 0.5), brightness: 0.26, alpha: 1)
        return ArenaFloorStyle(key: environment.rawValue, motif: motif, stone: stone, grout: grout,
                               gold: UIColor(hex: "#D2A844") ?? .yellow,
                               goldLight: UIColor(hex: "#F4DC8C") ?? .yellow,
                               goldDark: UIColor(hex: "#5A4212") ?? .brown,
                               accent: UIColor(hex: accentHex) ?? .blue)
    }

    // MARK: - The medallion

    /// The whole medallion, centred on `arenaCentre`, a few millimetres
    /// above the slab (the band 2 cm): from the centre out, the emblem
    /// disc, a gold line, sixteen stones, a band of gold beads on enamel,
    /// twenty-four stones with four plaques on the diagonals, thirty-two
    /// stones, a gold line, the broad ornamented band with four gems, and
    /// a kerb of forty-eight darker stones inside a gold rim. At a row
    /// depth of 5.2 m the band's middle is 6.1 m out and the rim 7.6 m.
    static func arenaMedallion(for environment: BattleEnvironment, floorTint: String?) -> SCNNode {
        let style = arenaStyle(for: environment, floorTint: floorTint)
        let art = arenaArt(for: style)
        let scale = arenaRowDepth / 5.2
        let node = SCNNode()
        node.name = "arena_medallion"
        node.position = SCNVector3(arenaCentre.x, 0, arenaCentre.z)

        let stone = arenaMaterial(art.stone, relief: art.stoneRelief, roughness: 0.64, metalness: 0)
        let band = arenaMaterial(art.band, relief: art.bandRelief, roughness: 0.42, metalness: 0.35)
        let beads = arenaMaterial(art.bead, relief: art.beadRelief, roughness: 0.5, metalness: 0.2)
        let emblem = arenaMaterial(art.emblem, relief: art.emblemRelief, roughness: 0.55, metalness: 0.15)
        let plaque = arenaMaterial(art.plaque, relief: nil, roughness: 0.45, metalness: 0.2)
        let gem = arenaMaterial(art.gem, relief: nil, roughness: 0.3, metalness: 0.1)
        let gold = arenaMaterial(style.gold, relief: nil, roughness: 0.4, metalness: 0.35)
        let goldWall = arenaMaterial(style.gold.mixed(with: style.goldDark, amount: 0.35), relief: nil,
                                     roughness: 0.45, metalness: 0.35)

        func place(_ geometry: SCNGeometry, _ material: SCNMaterial, height: Float, x: Float = 0, z: Float = 0) {
            geometry.materials = [material]
            let child = SCNNode(geometry: geometry)
            child.position = SCNVector3(x, height, z)
            child.castsShadow = false
            node.addChildNode(child)
        }
        func tones(_ count: Int, seed: UInt64, from low: CGFloat, to high: CGFloat) -> [CGFloat] {
            var rng = SeededRandom(seed: seed)
            return (0..<count).map { _ in low + CGFloat(rng.unit()) * (high - low) }
        }
        let flush: Float = 0.006
        let r = { (metres: Float) -> Float in metres * scale }

        place(arenaRing(inner: 0, outer: r(1.5), pieces: 8, planar: true), emblem, height: flush)
        place(arenaRing(inner: r(1.5), outer: r(1.58), pieces: 16), gold, height: flush + 0.001)
        place(arenaRing(inner: r(1.58), outer: r(2.9), pieces: 16,
                        tones: tones(16, seed: 0xA1, from: 0.82, to: 1.0)), stone, height: flush)
        place(arenaRing(inner: r(2.9), outer: r(3.2), pieces: 64), beads, height: flush + 0.001)
        place(arenaRing(inner: r(3.2), outer: r(4.6), pieces: 24,
                        tones: tones(24, seed: 0xB2, from: 0.82, to: 1.0)), stone, height: flush)
        place(arenaRing(inner: r(4.6), outer: r(5.55), pieces: 32,
                        tones: tones(32, seed: 0xC3, from: 0.82, to: 1.0)), stone, height: flush)
        place(arenaRing(inner: r(5.55), outer: r(5.62), pieces: 32), gold, height: flush + 0.001)

        // The broad band, raised: its top 2 cm up, a gold tube under it
        // for the walls the light catches at its two edges.
        let bandInner = r(5.62), bandOuter = r(6.52)
        let bandTop: Float = 0.022
        place(arenaRing(inner: bandInner, outer: bandOuter, pieces: 12), band, height: bandTop)
        let walls = SCNTube(innerRadius: CGFloat(bandInner), outerRadius: CGFloat(bandOuter), height: CGFloat(bandTop - 0.002))
        walls.radialSegmentCount = 192
        place(walls, goldWall, height: (bandTop - 0.002) / 2)

        place(arenaRing(inner: r(6.52), outer: r(7.55), pieces: 48,
                        tones: tones(48, seed: 0xD4, from: 0.68, to: 0.8)), stone, height: flush)
        place(arenaRing(inner: r(7.55), outer: r(7.64), pieces: 48), gold, height: flush + 0.001)

        // Four enamel plaques on the diagonals of the inner ring (the
        // genre's glyph discs), four gems on the band at the cardinals.
        for index in 0..<4 {
            let diagonal = (Float(index) + 0.5) * Float.pi / 2
            let plaqueAt = r(3.9)
            place(arenaRing(inner: 0, outer: r(0.36), pieces: 4, planar: true), plaque,
                  height: flush + 0.003, x: cos(diagonal) * plaqueAt, z: sin(diagonal) * plaqueAt)
            let cardinal = Float(index) * Float.pi / 2
            let gemAt = (bandInner + bandOuter) / 2
            place(arenaRing(inner: 0, outer: r(0.22), pieces: 4, planar: true), gem,
                  height: bandTop + 0.003, x: cos(cardinal) * gemAt, z: sin(cardinal) * gemAt)
        }
        return node
    }

    /// A flat ring (or, from radius 0, a disc) lying in the XZ plane with
    /// its face up, made of `pieces` equal sectors that share no vertices,
    /// so each sector can take its own `tones` (a grey vertex colour that
    /// multiplies the texture: one stone lighter, its neighbour darker).
    /// Each sector's texture runs u 0…1 round the ring (left to right as
    /// the camera sees the near arc) and v 0…1 from the inner edge out, so
    /// one stone's image is one stone; `planar` maps the image flat over
    /// the whole disc instead (top of the image to the far side).
    static func arenaRing(inner: Float, outer: Float, pieces: Int, tones: [CGFloat] = [],
                          planar: Bool = false) -> SCNGeometry {
        let arcSteps = max(1, Int((outer * 32 / Float(pieces)).rounded(.up)))
        let sector = 2 * Float.pi / Float(pieces)
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        var colours: [Float] = []
        var indices: [UInt32] = []
        for piece in 0..<pieces {
            let shade = Float(piece < tones.count ? tones[piece] : 1)
            let base = UInt32(positions.count)
            for step in 0...arcSteps {
                let share = Float(step) / Float(arcSteps)
                let angle = (Float(piece) + share) * sector
                for edge in 0...1 {
                    let radius = edge == 0 ? inner : outer
                    let x = cos(angle) * radius
                    let z = sin(angle) * radius
                    positions.append(SCNVector3(x, 0, z))
                    normals.append(SCNVector3(0, 1, 0))
                    if planar {
                        let extent = max(outer, 0.001) * 2
                        coordinates.append(CGPoint(x: CGFloat(0.5 + x / extent), y: CGFloat(0.5 + z / extent)))
                    } else {
                        coordinates.append(CGPoint(x: CGFloat(1 - share), y: CGFloat(edge)))
                    }
                    colours.append(contentsOf: [shade, shade, shade])
                }
            }
            for step in 0..<UInt32(arcSteps) {
                let innerHere = base + step * 2
                let outerHere = innerHere + 1
                let innerNext = innerHere + 2
                let outerNext = innerHere + 3
                // Counter-clockwise seen from above, so the face is up.
                indices += [innerHere, innerNext, outerHere, outerHere, innerNext, outerNext]
            }
        }
        let colourData = colours.withUnsafeBufferPointer { Data(buffer: $0) }
        let colourSource = SCNGeometrySource(data: colourData, semantic: .color, vectorCount: colours.count / 3,
                                             usesFloatComponents: true, componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                             dataStride: MemoryLayout<Float>.size * 3)
        let sources = [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                       SCNGeometrySource(textureCoordinates: coordinates), colourSource]
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: sources, elements: [element])
    }

    /// A floor material that stays sharp at a grazing angle: trilinear
    /// mips and 16× anisotropic filtering on the paint and the relief.
    private static func arenaMaterial(_ contents: Any, relief: UIImage?, roughness: CGFloat,
                                      metalness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = contents
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        sharpenFloor(material.diffuse)
        if let relief {
            material.normal.contents = relief
            material.normal.intensity = 1.0
            sharpenFloor(material.normal)
        }
        return material
    }

    /// Trilinear, 16× anisotropic, repeating: what every floor texture
    /// wants seen at 19–36° from the ground.
    static func sharpenFloor(_ property: SCNMaterialProperty) {
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.minificationFilter = .linear
        property.magnificationFilter = .linear
        property.mipFilter = .linear
        property.maxAnisotropy = 16
    }

    // MARK: - The drawings

    /// The last realm's drawings (about 6 MB with their relief maps): a
    /// second fight in the same place builds nothing, and a change of
    /// realm lets the old set go.
    private static var arenaArtCache: (key: String, art: ArenaFloorArt)?

    static func arenaArt(for style: ArenaFloorStyle) -> ArenaFloorArt {
        if let cached = arenaArtCache, cached.key == style.key { return cached.art }
        let stone = stoneImage(style)
        let band = bandImage(style)
        let bead = beadImage(style)
        let emblem = emblemImage(style)
        let art = ArenaFloorArt(stone: stone, stoneRelief: reliefMap(from: stone, width: 256, height: 256, strength: 2.6),
                                band: band, bandRelief: reliefMap(from: band, width: 512, height: 128, strength: 2.4),
                                bead: bead, beadRelief: reliefMap(from: bead, width: 64, height: 64, strength: 2.0),
                                emblem: emblem, emblemRelief: reliefMap(from: emblem, width: 512, height: 512, strength: 2.2),
                                plaque: plaqueImage(style), gem: gemImage(style))
        arenaArtCache = (key: style.key, art: art)
        return art
    }

    /// Draws at one pixel a point, opaque, in UIKit's coordinates (origin
    /// top left, y down). The default format is the screen's scale, which
    /// would make a 1024-point drawing 3072 pixels.
    private static func paintArena(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in draw(context.cgContext) }
    }

    /// One stone of a course, 512 pixels square: the stone's colour with a
    /// fine grain and a few soft clouds through it, and half a grout line
    /// on every edge (its neighbour draws the other half).
    private static func stoneImage(_ style: ArenaFloorStyle) -> UIImage {
        let side = 512
        return paintArena(side, side) { cg in
            let size = CGFloat(side)
            style.stone.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var rng = SeededRandom(seed: 0x57011E)
            let space = CGColorSpaceCreateDeviceRGB()
            for _ in 0..<9 {
                let cloud: UIColor = rng.unit() < 0.5 ? .white : .black
                let alpha = CGFloat(0.05 + rng.unit() * 0.07)
                let colors = [cloud.withAlphaComponent(alpha).cgColor, cloud.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { continue }
                let at = CGPoint(x: CGFloat(rng.unit()) * size, y: CGFloat(rng.unit()) * size)
                cg.drawRadialGradient(gradient, startCenter: at, startRadius: 0, endCenter: at,
                                      endRadius: CGFloat(80 + rng.unit() * 140), options: [])
            }
            for _ in 0..<700 {
                let light = rng.unit() < 0.5
                let colour: UIColor = light ? .white : .black
                cg.setFillColor(colour.withAlphaComponent(CGFloat(0.02 + rng.unit() * 0.04)).cgColor)
                let radius = CGFloat(0.6 + rng.unit() * 2.2)
                let at = CGPoint(x: CGFloat(rng.unit()) * size, y: CGFloat(rng.unit()) * size)
                cg.fillEllipse(in: CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 1.6))
            }
            // The bevel: a lit lip inside the top and left grout, a shaded
            // one inside the bottom and right, then the grout itself.
            let groutHalf: CGFloat = 5
            let lip: CGFloat = 5
            cg.setFillColor(UIColor.white.withAlphaComponent(0.16).cgColor)
            cg.fill(CGRect(x: groutHalf, y: groutHalf, width: size - groutHalf * 2, height: lip))
            cg.fill(CGRect(x: groutHalf, y: groutHalf, width: lip, height: size - groutHalf * 2))
            cg.setFillColor(UIColor.black.withAlphaComponent(0.14).cgColor)
            cg.fill(CGRect(x: groutHalf, y: size - groutHalf - lip, width: size - groutHalf * 2, height: lip))
            cg.fill(CGRect(x: size - groutHalf - lip, y: groutHalf, width: lip, height: size - groutHalf * 2))
            style.grout.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: groutHalf))
            cg.fill(CGRect(x: 0, y: size - groutHalf, width: size, height: groutHalf))
            cg.fill(CGRect(x: 0, y: 0, width: groutHalf, height: size))
            cg.fill(CGRect(x: size - groutHalf, y: 0, width: groutHalf, height: size))
        }
    }

    /// Strokes every path twice — dark and wide, then light and narrow —
    /// so an ornament reads as a raised gold line with a cut edge, and
    /// where two lines meet they merge instead of crossing.
    private static func inlay(_ cg: CGContext, _ paths: [CGPath], width: CGFloat, style: ArenaFloorStyle,
                              cap: CGLineCap = .square) {
        cg.setLineCap(cap)
        cg.setLineJoin(.miter)
        cg.setStrokeColor(style.goldDark.cgColor)
        cg.setLineWidth(width + 8)
        for path in paths {
            cg.addPath(path)
            cg.strokePath()
        }
        cg.setStrokeColor(style.goldLight.cgColor)
        cg.setLineWidth(width)
        for path in paths {
            cg.addPath(path)
            cg.strokePath()
        }
    }

    /// A pointed petal or leaf from `base` to `tip`, `width` to each side.
    private static func petal(from base: CGPoint, to tip: CGPoint, width: CGFloat) -> CGPath {
        let dx = tip.x - base.x, dy = tip.y - base.y
        let length = max(0.001, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / length * width * 2, ny = dx / length * width * 2
        let mid = CGPoint(x: base.x + dx * 0.45, y: base.y + dy * 0.45)
        let path = CGMutablePath()
        path.move(to: base)
        path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
        path.addQuadCurve(to: base, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
        path.closeSubpath()
        return path
    }

    /// Fills shapes in light gold with a dark cut edge.
    private static func raised(_ cg: CGContext, _ paths: [CGPath], style: ArenaFloorStyle, edge: CGFloat = 4,
                               fill: UIColor? = nil) {
        for path in paths {
            cg.addPath(path)
            cg.setFillColor((fill ?? style.goldLight).cgColor)
            cg.fillPath()
            cg.addPath(path)
            cg.setStrokeColor(style.goldDark.cgColor)
            cg.setLineWidth(edge)
            cg.setLineJoin(.round)
            cg.strokePath()
        }
    }

    /// The broad band's tile, 1024 × 256 (0.9 m deep, about 3.2 m of arc):
    /// a gold field between two lipped borders, the realm's running
    /// ornament raised in the middle. It repeats twelve times round the
    /// ring, so every motif is drawn to wrap at the tile's sides.
    private static func bandImage(_ style: ArenaFloorStyle) -> UIImage {
        let width = 1024, height = 256
        return paintArena(width, height) { cg in
            let w = CGFloat(width), h = CGFloat(height)
            style.gold.mixed(with: style.goldDark, amount: 0.18).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // The borders: a dark cut at the stone, a light lip, a line.
            for upper in [true, false] {
                func band(_ from: CGFloat, _ to: CGFloat, _ colour: UIColor) {
                    colour.setFill()
                    let y = upper ? from : h - to
                    cg.fill(CGRect(x: 0, y: y, width: w, height: to - from))
                }
                band(0, 7, style.goldDark)
                band(7, 22, style.goldLight)
                band(22, 26, style.goldDark)
            }
            let top: CGFloat = 38, bottom: CGFloat = 218
            let mid = (top + bottom) / 2
            switch style.motif {
            case .meander, .fret:
                // The key: a square spiral per period off a base line, on a
                // grid of 5 × 4 units. The fret (the Jade Court's huiwen)
                // hangs every other spiral from a top line instead.
                let inset: CGFloat = 12
                let unitY = (bottom - top - inset * 2) / 4
                let periods = max(1, Int((w / (unitY * 5)).rounded()))
                let unitX = w / CGFloat(periods * 5)
                let spiral: [(CGFloat, CGFloat)] = [(0, 0), (0, 4), (4, 4), (4, 1), (1, 1), (1, 3), (3, 3), (3, 2), (2, 2)]
                func point(_ gx: CGFloat, _ gy: CGFloat) -> CGPoint {
                    CGPoint(x: gx * unitX, y: bottom - inset - gy * unitY)
                }
                var paths: [CGPath] = []
                let base = CGMutablePath()
                base.move(to: point(-1, 0))
                base.addLine(to: point(CGFloat(periods * 5) + 1, 0))
                paths.append(base)
                if style.motif == .fret {
                    let roof = CGMutablePath()
                    roof.move(to: point(-1, 4))
                    roof.addLine(to: point(CGFloat(periods * 5) + 1, 4))
                    paths.append(roof)
                }
                for period in 0..<periods {
                    let flipped = style.motif == .fret && period % 2 == 1
                    let path = CGMutablePath()
                    for (index, grid) in spiral.enumerated() {
                        let gx = CGFloat(period * 5) + grid.0
                        let gy = flipped ? 4 - grid.1 : grid.1
                        if index == 0 { path.move(to: point(gx, gy)) } else { path.addLine(to: point(gx, gy)) }
                    }
                    paths.append(path)
                }
                inlay(cg, paths, width: unitY * 0.42, style: style)
            case .lotus:
                // Lotus and bud, linked by swags along the base.
                let periods = 4
                let span = w / CGFloat(periods)
                let ground = bottom - 10
                var swags: [CGPath] = []
                for period in -1...periods {
                    let flower = (CGFloat(period) + 0.25) * span
                    let bud = (CGFloat(period) + 0.75) * span
                    let swag = CGMutablePath()
                    swag.move(to: CGPoint(x: flower, y: ground))
                    swag.addQuadCurve(to: CGPoint(x: bud, y: ground), control: CGPoint(x: (flower + bud) / 2, y: ground + 16))
                    swag.addQuadCurve(to: CGPoint(x: flower + span, y: ground), control: CGPoint(x: bud + span / 4, y: ground + 16))
                    swags.append(swag)
                }
                inlay(cg, swags, width: 7, style: style, cap: .round)
                for period in -1...periods {
                    let flower = (CGFloat(period) + 0.25) * span
                    let bud = (CGFloat(period) + 0.75) * span
                    let foot = CGPoint(x: flower, y: ground)
                    raised(cg, [
                        petal(from: foot, to: CGPoint(x: flower - 88, y: top + 78), width: 12),
                        petal(from: foot, to: CGPoint(x: flower + 88, y: top + 78), width: 12),
                        petal(from: foot, to: CGPoint(x: flower - 52, y: top + 18), width: 17),
                        petal(from: foot, to: CGPoint(x: flower + 52, y: top + 18), width: 17),
                        petal(from: foot, to: CGPoint(x: flower, y: top), width: 22),
                    ], style: style)
                    let budFoot = CGPoint(x: bud, y: ground)
                    raised(cg, [
                        petal(from: budFoot, to: CGPoint(x: bud - 26, y: mid + 18), width: 8),
                        petal(from: budFoot, to: CGPoint(x: bud + 26, y: mid + 18), width: 8),
                        petal(from: budFoot, to: CGPoint(x: bud, y: top + 50), width: 16),
                    ], style: style)
                }
            case .braid:
                // Two strands crossing every eighth of the tile, over and
                // under in turn, an eye in every loop.
                let period = w / 4
                let amplitude = (bottom - top) / 2 - 22
                func wave(_ x: CGFloat, _ sign: CGFloat) -> CGPoint {
                    let phase: CGFloat = 2 * CGFloat.pi * x / period
                    let lift: CGFloat = sign * amplitude * sin(phase)
                    return CGPoint(x: x, y: mid + lift)
                }
                func strand(_ sign: CGFloat, from start: CGFloat, to end: CGFloat) -> CGPath {
                    let path = CGMutablePath()
                    var x = start
                    path.move(to: wave(x, sign))
                    while x < end {
                        x = min(end, x + 4)
                        path.addLine(to: wave(x, sign))
                    }
                    return path
                }
                inlay(cg, [strand(1, from: -8, to: w + 8), strand(-1, from: -8, to: w + 8)], width: 22,
                      style: style, cap: .butt)
                for crossing in 0...8 {
                    let x = CGFloat(crossing) * period / 2
                    let over: CGFloat = crossing % 2 == 0 ? 1 : -1
                    inlay(cg, [strand(over, from: x - 34, to: x + 34)], width: 22, style: style, cap: .butt)
                }
                var eyes: [CGPath] = []
                for loop in 0..<8 {
                    let x = (CGFloat(loop) + 0.5) * period / 2
                    eyes.append(CGPath(ellipseIn: CGRect(x: x - 17, y: mid - 17, width: 34, height: 34), transform: nil))
                }
                raised(cg, eyes, style: style, edge: 4)
            case .laurel:
                // A running laurel: a stem, a pair of leaves every 64 px,
                // a berry between.
                let stem = CGMutablePath()
                stem.move(to: CGPoint(x: -8, y: mid))
                stem.addLine(to: CGPoint(x: w + 8, y: mid))
                inlay(cg, [stem], width: 6, style: style, cap: .butt)
                var leaves: [CGPath] = []
                var berries: [CGPath] = []
                var x: CGFloat = -128
                while x < w + 64 {
                    leaves.append(petal(from: CGPoint(x: x, y: mid), to: CGPoint(x: x + 62, y: mid - 66), width: 13))
                    leaves.append(petal(from: CGPoint(x: x + 32, y: mid), to: CGPoint(x: x + 94, y: mid + 66), width: 13))
                    berries.append(CGPath(ellipseIn: CGRect(x: x + 22, y: mid - 30, width: 14, height: 14), transform: nil))
                    x += 64
                }
                raised(cg, leaves, style: style)
                raised(cg, berries, style: style, edge: 3)
            }
        }
    }

    /// The bead band's tile: a gold bead on the realm's enamel between two
    /// gold threads, 128 pixels square, sixty-four round the ring.
    private static func beadImage(_ style: ArenaFloorStyle) -> UIImage {
        paintArena(128, 128) { cg in
            style.accent.mixed(with: .black, amount: 0.3).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            style.gold.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 128, height: 12))
            cg.fill(CGRect(x: 0, y: 116, width: 128, height: 12))
            style.goldDark.setFill()
            cg.fill(CGRect(x: 0, y: 12, width: 128, height: 3))
            cg.fill(CGRect(x: 0, y: 113, width: 128, height: 3))
            let bead = CGRect(x: 30, y: 30, width: 68, height: 68)
            let space = CGColorSpaceCreateDeviceRGB()
            cg.saveGState()
            cg.addEllipse(in: bead)
            cg.clip()
            let colors = [style.goldLight.cgColor, style.gold.cgColor, style.gold.mixed(with: style.goldDark, amount: 0.45).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) {
                cg.drawRadialGradient(gradient, startCenter: CGPoint(x: 54, y: 52), startRadius: 0,
                                      endCenter: CGPoint(x: 64, y: 64), endRadius: 36, options: [])
            }
            cg.restoreGState()
            cg.setStrokeColor(style.goldDark.cgColor)
            cg.setLineWidth(4)
            cg.strokeEllipse(in: bead)
        }
    }

    /// The centre: 1024 pixels over the emblem disc's 3 m — eight stones
    /// round an inner disc, and the realm's emblem raised in gold over them.
    private static func emblemImage(_ style: ArenaFloorStyle) -> UIImage {
        paintArena(1024, 1024) { cg in
            let size: CGFloat = 1024
            let centre = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2
            style.stone.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            // Grain, as the stones have it.
            var rng = SeededRandom(seed: 0xE3B1E3)
            for _ in 0..<1300 {
                let colour: UIColor = rng.unit() < 0.5 ? .white : .black
                cg.setFillColor(colour.withAlphaComponent(CGFloat(0.02 + rng.unit() * 0.04)).cgColor)
                let dot = CGFloat(0.6 + rng.unit() * 2.2)
                cg.fillEllipse(in: CGRect(x: CGFloat(rng.unit()) * size, y: CGFloat(rng.unit()) * size, width: dot * 2, height: dot * 1.6))
            }
            // The stones' joints: a ring and eight radial lines.
            cg.setStrokeColor(style.grout.cgColor)
            cg.setLineWidth(8)
            cg.strokeEllipse(in: CGRect(x: centre.x - radius * 0.5, y: centre.y - radius * 0.5, width: radius, height: radius))
            for index in 0..<8 {
                let angle = (CGFloat(index) + 0.5) * .pi / 4
                cg.move(to: CGPoint(x: centre.x + cos(angle) * radius * 0.5, y: centre.y + sin(angle) * radius * 0.5))
                cg.addLine(to: CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius))
                cg.strokePath()
            }
            // A thin gold ring inside the edge, then the emblem.
            cg.setStrokeColor(style.goldDark.cgColor)
            cg.setLineWidth(16)
            cg.strokeEllipse(in: CGRect(x: centre.x - radius * 0.93, y: centre.y - radius * 0.93, width: radius * 1.86, height: radius * 1.86))
            cg.setStrokeColor(style.gold.cgColor)
            cg.setLineWidth(9)
            cg.strokeEllipse(in: CGRect(x: centre.x - radius * 0.93, y: centre.y - radius * 0.93, width: radius * 1.86, height: radius * 1.86))
            drawEmblem(cg, centre: centre, radius: radius * 0.86, style: style)
        }
    }

    /// The realm's emblem, raised gold with enamel, in a circle of
    /// `radius` (y down).
    private static func drawEmblem(_ cg: CGContext, centre c: CGPoint, radius r: CGFloat, style: ArenaFloorStyle) {
        func at(_ angle: CGFloat, _ distance: CGFloat) -> CGPoint {
            CGPoint(x: c.x + cos(angle) * distance, y: c.y + sin(angle) * distance)
        }
        func disc(_ radius: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        }
        switch style.motif {
        case .meander:
            // A sixteen-rayed sun, long and short rays in turn.
            var rays: [CGPath] = []
            for index in 0..<16 {
                let angle = CGFloat(index) * .pi / 8 - .pi / 2
                let reach = index % 2 == 0 ? r * 0.98 : r * 0.72
                let half = CGFloat.pi / 16 * 0.85
                let ray = CGMutablePath()
                ray.move(to: at(angle - half, r * 0.3))
                ray.addLine(to: at(angle, reach))
                ray.addLine(to: at(angle + half, r * 0.3))
                ray.closeSubpath()
                rays.append(ray)
            }
            raised(cg, rays, style: style, edge: 5)
            raised(cg, [disc(r * 0.28)], style: style, edge: 6)
            raised(cg, [disc(r * 0.14)], style: style, edge: 5, fill: style.accent)
        case .lotus:
            // A rosette: twelve short petals behind twelve long ones.
            var short: [CGPath] = []
            var long: [CGPath] = []
            for index in 0..<12 {
                let angle = CGFloat(index) * .pi / 6 - .pi / 2
                short.append(petal(from: at(angle + .pi / 12, r * 0.16), to: at(angle + .pi / 12, r * 0.68), width: r * 0.075))
                long.append(petal(from: at(angle, r * 0.16), to: at(angle, r * 0.98), width: r * 0.1))
            }
            raised(cg, short, style: style, edge: 5, fill: style.gold)
            raised(cg, long, style: style, edge: 5)
            raised(cg, [disc(r * 0.24)], style: style, edge: 6)
            raised(cg, [disc(r * 0.15)], style: style, edge: 5, fill: style.accent)
        case .braid:
            // Three interlaced triangles inside a ring.
            cg.setLineJoin(.miter)
            var triangles: [CGPath] = []
            for index in 0..<3 {
                let turn = CGFloat(index) * 2 * .pi / 3
                let offset = at(turn - .pi / 2, r * 0.16)
                let path = CGMutablePath()
                for corner in 0..<3 {
                    // Two typed steps, not one chain of bare `.pi`s: the
                    // checker's time on one grows with every operator (2026-09-24).
                    let step: CGFloat = CGFloat(corner) * 2 * CGFloat.pi / 3
                    let angle: CGFloat = turn + step - CGFloat.pi / 2 + CGFloat.pi / 9
                    let point = CGPoint(x: offset.x + cos(angle) * r * 0.64,
                                        y: offset.y + sin(angle) * r * 0.64)
                    if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                triangles.append(path)
            }
            inlay(cg, triangles, width: r * 0.075, style: style, cap: .butt)
            inlay(cg, [disc(r * 0.95)], width: r * 0.05, style: style)
            raised(cg, [disc(r * 0.1)], style: style, edge: 5, fill: style.accent)
        case .laurel:
            // A wreath round an eight-pointed star.
            var leaves: [CGPath] = []
            for side in [CGFloat(-1), 1] {
                var step: CGFloat = 0
                while step < 9 {
                    // From the bottom (90°) round each side toward the top.
                    let sweep: CGFloat = 0.22 + step * 0.27
                    let angle: CGFloat = CGFloat.pi / 2 + side * sweep
                    let base = at(angle, r * 0.76)
                    let tangent = CGPoint(x: -sin(angle) * side, y: cos(angle) * side)
                    let outward = CGPoint(x: cos(angle), y: sin(angle))
                    for lean in [CGFloat(-1), 1] {
                        let tip = CGPoint(x: base.x + tangent.x * r * 0.2 + outward.x * lean * r * 0.1,
                                          y: base.y + tangent.y * r * 0.2 + outward.y * lean * r * 0.1)
                        leaves.append(petal(from: base, to: tip, width: r * 0.04))
                    }
                    step += 1
                }
            }
            raised(cg, leaves, style: style, edge: 4)
            let star = CGMutablePath()
            for index in 0..<16 {
                let angle = CGFloat(index) * .pi / 8 - .pi / 2
                let point = at(angle, index % 2 == 0 ? r * 0.5 : r * 0.2)
                if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            raised(cg, [star], style: style, edge: 6)
            raised(cg, [disc(r * 0.1)], style: style, edge: 5, fill: style.accent)
        case .fret:
            // A taiji in jade and gold inside the eight trigrams.
            let t = r * 0.34
            raised(cg, [disc(t)], style: style, edge: 6)
            let dark = CGMutablePath()
            var first = true
            func trace(_ centre: CGPoint, _ radius: CGFloat, from start: CGFloat, to end: CGFloat) {
                let steps = 40
                for index in 0...steps {
                    let angle = start + (end - start) * CGFloat(index) / CGFloat(steps)
                    let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
                    if first { dark.move(to: point); first = false } else { dark.addLine(to: point) }
                }
            }
            trace(c, t, from: -.pi / 2, to: .pi / 2)
            trace(CGPoint(x: c.x, y: c.y + t / 2), t / 2, from: .pi / 2, to: 3 * .pi / 2)
            trace(CGPoint(x: c.x, y: c.y - t / 2), t / 2, from: .pi / 2, to: -.pi / 2)
            dark.closeSubpath()
            cg.addPath(dark)
            cg.setFillColor(style.accent.cgColor)
            cg.fillPath()
            let dot = t / 7
            style.goldLight.setFill()
            cg.fillEllipse(in: CGRect(x: c.x - dot, y: c.y + t / 2 - dot, width: dot * 2, height: dot * 2))
            style.accent.setFill()
            cg.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - t / 2 - dot, width: dot * 2, height: dot * 2))
            cg.setStrokeColor(style.goldDark.cgColor)
            cg.setLineWidth(6)
            cg.strokeEllipse(in: CGRect(x: c.x - t, y: c.y - t, width: t * 2, height: t * 2))
            // The trigrams, top first: heaven, lake, fire, thunder, wind,
            // water, mountain, earth (a broken line is false).
            let trigrams: [[Bool]] = [[true, true, true], [false, true, true], [true, false, true], [false, false, true],
                                      [true, true, false], [false, true, false], [true, false, false], [false, false, false]]
            var bars: [CGPath] = []
            for (index, lines) in trigrams.enumerated() {
                let angle = CGFloat(index) * .pi / 4 - .pi / 2
                let across = CGPoint(x: -sin(angle), y: cos(angle))
                for (row, whole) in lines.enumerated() {
                    let centre = at(angle, r * (0.58 + CGFloat(row) * 0.13))
                    let half = r * 0.16
                    let spans: [(CGFloat, CGFloat)] = whole ? [(-half, half)] : [(-half, -half * 0.22), (half * 0.22, half)]
                    for span in spans {
                        let bar = CGMutablePath()
                        bar.move(to: CGPoint(x: centre.x + across.x * span.0, y: centre.y + across.y * span.0))
                        bar.addLine(to: CGPoint(x: centre.x + across.x * span.1, y: centre.y + across.y * span.1))
                        bars.append(bar)
                    }
                }
            }
            inlay(cg, bars, width: r * 0.055, style: style, cap: .butt)
        }
    }

    /// An enamel plaque: a gold rim, the realm's enamel, an eight-pointed
    /// gold star.
    private static func plaqueImage(_ style: ArenaFloorStyle) -> UIImage {
        paintArena(256, 256) { cg in
            let c = CGPoint(x: 128, y: 128)
            style.gold.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            style.goldDark.setFill()
            cg.fillEllipse(in: CGRect(x: 14, y: 14, width: 228, height: 228))
            style.accent.setFill()
            cg.fillEllipse(in: CGRect(x: 22, y: 22, width: 212, height: 212))
            let star = CGMutablePath()
            for index in 0..<16 {
                let angle = CGFloat(index) * .pi / 8 - .pi / 2
                let reach: CGFloat = index % 2 == 0 ? 88 : 34
                let point = CGPoint(x: c.x + cos(angle) * reach, y: c.y + sin(angle) * reach)
                if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            raised(cg, [star], style: style, edge: 4)
        }
    }

    /// A cabochon of the realm's enamel in a gold setting, lit from the
    /// upper left.
    private static func gemImage(_ style: ArenaFloorStyle) -> UIImage {
        paintArena(128, 128) { cg in
            style.gold.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            style.goldDark.setFill()
            cg.fillEllipse(in: CGRect(x: 10, y: 10, width: 108, height: 108))
            cg.saveGState()
            cg.addEllipse(in: CGRect(x: 16, y: 16, width: 96, height: 96))
            cg.clip()
            let colors = [style.accent.mixed(with: .white, amount: 0.55).cgColor, style.accent.cgColor,
                          style.accent.mixed(with: .black, amount: 0.45).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
                cg.drawRadialGradient(gradient, startCenter: CGPoint(x: 50, y: 46), startRadius: 0,
                                      endCenter: CGPoint(x: 64, y: 64), endRadius: 50, options: [])
            }
            cg.restoreGState()
        }
    }

    // MARK: - Relief

    /// A tangent-space normal map from a drawing's own light and dark (the
    /// light parts high, the grout and the cut edges low), at `width` ×
    /// `height`, wrapping at the sides as the textures do. The convention
    /// is `tools/floor_relief.py`'s: red to the right, green to the top.
    static func reliefMap(from image: UIImage, width: Int, height: Int, strength: Float) -> UIImage? {
        guard let source = image.cgImage else { return nil }
        var grey = [UInt8](repeating: 0, count: width * height)
        let read = grey.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard read else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let scale = strength / 255
        grey.withUnsafeBufferPointer { heights in
            pixels.withUnsafeMutableBufferPointer { out in
                for y in 0..<height {
                    let up = (y + height - 1) % height, down = (y + 1) % height
                    for x in 0..<width {
                        let left = (x + width - 1) % width, right = (x + 1) % width
                        let dx = Float(heights[y * width + right]) - Float(heights[y * width + left])
                        let dyDown = Float(heights[down * width + x]) - Float(heights[up * width + x])
                        let nx = -dx * scale
                        let ny = dyDown * scale
                        let length = (nx * nx + ny * ny + 1).squareRoot()
                        let at = (y * width + x) * 4
                        // Typed lets: written as one expression each, these
                        // three lines took 1.1-4.6 s apiece to type-check
                        // (runs 243 and 244's slowest-to-compile list).
                        let red: Float = (nx / length * 0.5 + 0.5) * 255
                        let green: Float = (ny / length * 0.5 + 0.5) * 255
                        let blue: Float = (1 / length * 0.5 + 0.5) * 255
                        out[at] = UInt8(max(Float(0), min(Float(255), red)))
                        out[at + 1] = UInt8(max(Float(0), min(Float(255), green)))
                        out[at + 2] = UInt8(max(Float(0), min(Float(255), blue)))
                    }
                }
            }
        }
        let made: CGImage? = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            return context.makeImage()
        }
        return made.map { UIImage(cgImage: $0) }
    }

    // MARK: - The slab's tiles, calmed

    private static var calmedFloorCache: [String: UIImage] = [:]
    private static let calmingContext = CIContext(options: nil)

    /// The painted floor tile with `saturation` of its colour kept, cached
    /// for the two most recent (a 1024-pixel tile is 4 MB). Nil when the
    /// tile is missing or Core Image cannot draw it; the caller keeps the
    /// original then.
    static func calmedFloorImage(_ name: String, saturation: CGFloat) -> UIImage? {
        let key = "\(name)@\(saturation)"
        if let cached = calmedFloorCache[key] { return cached }
        guard let original = UIImage(named: name), let input = CIImage(image: original),
              let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let drawn = calmingContext.createCGImage(output, from: input.extent) else { return nil }
        let image = UIImage(cgImage: drawn)
        if calmedFloorCache.count >= 2 { calmedFloorCache.removeAll() }
        calmedFloorCache[key] = image
        return image
    }

    /// A tint with only `keep` of its saturation.
    static func calmedTint(_ colour: UIColor, keep: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard colour.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return colour }
        return UIColor(hue: hue, saturation: saturation * keep, brightness: brightness, alpha: alpha)
    }
}
