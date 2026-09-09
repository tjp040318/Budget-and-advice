import Foundation
import SceneKit
import UIKit

/// Builds the 3D sets the characters fight and appear in.
///
/// The genre's stage is not a picture behind the fighters; it is a small set
/// the camera can move around: a broken stone platform hanging in the air,
/// ruins and statues on it, fire and dust in the air, the sky and the land far
/// behind so everything shifts as the camera leans. This assembles one from
/// four kinds of part, none of which needs a scene file:
///
/// - **the platform**: a cylinder with a painted floor on top and a cliff face
///   round the side, a ring of boulders at its rim, and rock chunks hanging
///   below it;
/// - **props**: Meshy models shipped by `tools/prop.py` as `prop_<name>.usdz`
///   in the bundle, placed by a recipe per environment — with a built
///   stand-in (a column, an obelisk, a block) for any prop that has not
///   shipped, so the set never has a hole in it;
/// - **fire and air**: braziers with a flame and a flickering light, drifting
///   mist planes, slow dust;
/// - **the distance**: the environment's painting on a huge plane far behind
///   the platform, so the camera's lean puts real parallax between the set and
///   the world beyond it.
///
/// The summoning circle is the same parts in a ring around a rune dais.
enum StageBuilder {

    // MARK: - Recipes

    struct Placement {
        var asset: String
        var position: SCNVector3
        var yaw: Float = 0
        var scale: Float = 1
        var standIn: StandIn = .column
    }

    enum StandIn {
        case column, obelisk, block, none
    }

    struct Recipe {
        var floor: String
        var floorRepeats: Float
        var floorTint: String?
        var rock: String
        var backdrop: String?
        var props: [Placement]
        var braziers: [SCNVector3]
        var brazierAsset: String
        var flameHex: String
        var mistHex: String
        var mistCount: Int
        var dustHex: String
    }

    /// Heights the props were shipped at, in metres, so a stand-in matches.
    static let propHeights: [String: Float] = [
        "prop_anubis_colossus": 6.5, "prop_obelisk": 7.5, "prop_lotus_column": 4.6,
        "prop_brazier": 1.4, "prop_sphinx": 2.2, "prop_doric_column": 4.6,
        "prop_broken_column": 2.2, "prop_zeus_statue": 5.0, "prop_tripod_brazier": 1.3,
        "prop_temple_ruin": 6.0,
        "prop_rune_stone": 3.2, "prop_longship_prow": 3.6, "prop_world_tree_root": 5.0,
        "prop_norse_brazier": 1.3, "prop_hall_pillar": 4.8,
    ]

    /// A generator's idea of the front is not always the game's (+Z, toward
    /// the camera). Degrees about Y, applied after the shipped yaw.
    static let propYaw: [String: Float] = [:]

    static func recipe(for environment: BattleEnvironment) -> Recipe {
        // The Egyptian set. Colossi flank the far edge, obelisks stand at the
        // sides, lotus columns close the back, sphinxes watch from the wings,
        // braziers burn at the corners — behind the enemy line and just off
        // the frame beside the player's, so their fire shows at the edges.
        // Everything sits inside a platform of radius 7.6 centred at z = -0.8,
        // whose far edge (z = -8.4) the camera sees about a third of the way
        // down the frame with the painted distance beyond it. The first set
        // was a metre and a half wider and its edge never came into frame,
        // so the platform read as a floor, not as a thing in the air.
        let colossi = [
            Placement(asset: "prop_anubis_colossus", position: SCNVector3(-5.3, 0, -6.3), scale: 0.85, standIn: .block),
            Placement(asset: "prop_anubis_colossus", position: SCNVector3(5.3, 0, -6.3), scale: 0.85, standIn: .block),
        ]
        let obelisks = [
            Placement(asset: "prop_obelisk", position: SCNVector3(-6.9, 0, -2.4), standIn: .obelisk),
            Placement(asset: "prop_obelisk", position: SCNVector3(6.9, 0, -2.4), standIn: .obelisk),
        ]
        let columns = [
            Placement(asset: "prop_lotus_column", position: SCNVector3(-2.4, 0, -7.0)),
            Placement(asset: "prop_lotus_column", position: SCNVector3(2.4, 0, -7.0)),
        ]
        let sphinxes = [
            Placement(asset: "prop_sphinx", position: SCNVector3(-6.0, 0, -0.4), yaw: 90, standIn: .block),
            Placement(asset: "prop_sphinx", position: SCNVector3(6.0, 0, -0.4), yaw: -90, standIn: .block),
        ]
        // All behind the enemy line: the two beside the player's line were
        // where the impact shot's camera lands, and one arena frame was the
        // inside of a bowl.
        let braziers = [
            SCNVector3(-6.2, 0, -4.4), SCNVector3(6.2, 0, -4.4),
            SCNVector3(-3.8, 0, -5.6), SCNVector3(3.8, 0, -5.6),
        ]
        // The Greek set on the same marks: the Zeus statues where the colossi
        // stood, Doric columns for the lotus ones and at the obelisks' marks,
        // the temple ruin closing the back, broken columns in the wings and
        // tripod braziers at the corners.
        let statues = [
            Placement(asset: "prop_zeus_statue", position: SCNVector3(-5.3, 0, -6.3), scale: 0.9, standIn: .block),
            Placement(asset: "prop_zeus_statue", position: SCNVector3(5.3, 0, -6.3), scale: 0.9, standIn: .block),
        ]
        let doric = [
            Placement(asset: "prop_doric_column", position: SCNVector3(-2.4, 0, -7.0)),
            Placement(asset: "prop_doric_column", position: SCNVector3(2.4, 0, -7.0)),
            Placement(asset: "prop_doric_column", position: SCNVector3(-6.9, 0, -2.4)),
            Placement(asset: "prop_doric_column", position: SCNVector3(6.9, 0, -2.4)),
        ]
        let ruin = [
            Placement(asset: "prop_temple_ruin", position: SCNVector3(0, 0, -7.6), scale: 0.8, standIn: .block),
        ]
        let broken = [
            Placement(asset: "prop_broken_column", position: SCNVector3(-6.0, 0, -0.4), standIn: .block),
            Placement(asset: "prop_broken_column", position: SCNVector3(6.0, 0, -0.4), standIn: .block),
        ]
        // The Norse set: rune stones at the sides, a longship prow and the
        // world tree's roots at the back corners, hall pillars closing the
        // back, braziers on dragon-headed posts.
        let runeStones = [
            Placement(asset: "prop_rune_stone", position: SCNVector3(-6.9, 0, -2.4), standIn: .obelisk),
            Placement(asset: "prop_rune_stone", position: SCNVector3(6.9, 0, -2.4), standIn: .obelisk),
        ]
        let prow = [
            Placement(asset: "prop_longship_prow", position: SCNVector3(-5.3, 0, -6.3), yaw: 30, standIn: .block),
        ]
        let roots = [
            Placement(asset: "prop_world_tree_root", position: SCNVector3(-5.0, 0, -6.6), scale: 0.9, standIn: .block),
            Placement(asset: "prop_world_tree_root", position: SCNVector3(5.0, 0, -6.6), yaw: 180, scale: 0.9, standIn: .block),
        ]
        let pillars = [
            Placement(asset: "prop_hall_pillar", position: SCNVector3(-2.4, 0, -7.0)),
            Placement(asset: "prop_hall_pillar", position: SCNVector3(2.4, 0, -7.0)),
            Placement(asset: "prop_hall_pillar", position: SCNVector3(-5.6, 0, -5.2)),
            Placement(asset: "prop_hall_pillar", position: SCNVector3(5.6, 0, -5.2)),
        ]
        switch environment {
        case .olympusGate:
            return Recipe(floor: "floor_marble", floorRepeats: 5, floorTint: "#C8C0B4", rock: "rock_cliff",
                          backdrop: "olympus_gate_bg", props: statues + doric + ruin,
                          braziers: braziers, brazierAsset: "prop_tripod_brazier", flameHex: "#FFC870",
                          mistHex: "#E0E8F8", mistCount: 7, dustHex: "#FFF0C0")
        case .aegeanCliffs:
            return Recipe(floor: "floor_marble", floorRepeats: 5, floorTint: "#B8B4A8", rock: "rock_cliff",
                          backdrop: "aegean_cliffs_bg", props: [doric[0], doric[1], statues[1]] + broken,
                          braziers: [braziers[2], braziers[3]], brazierAsset: "prop_tripod_brazier", flameHex: "#FFD080",
                          mistHex: "#D8E8F0", mistCount: 8, dustHex: "#F0F8FF")
        case .lernaMarsh:
            return Recipe(floor: "floor_moss", floorRepeats: 5, floorTint: "#8A9A74", rock: "rock_cliff",
                          backdrop: "lerna_marsh_bg", props: broken + [doric[2], doric[3]],
                          braziers: [braziers[0], braziers[1]], brazierAsset: "prop_tripod_brazier", flameHex: "#A0FF90",
                          mistHex: "#A8C090", mistCount: 12, dustHex: "#C0E0A0")
        case .midgardFjord:
            return Recipe(floor: "floor_slate", floorRepeats: 5, floorTint: "#8A9AA8", rock: "rock_ice",
                          backdrop: "midgard_fjord_bg", props: prow + runeStones + [pillars[1]],
                          braziers: braziers, brazierAsset: "prop_norse_brazier", flameHex: "#FFB060",
                          mistHex: "#C8D8E8", mistCount: 8, dustHex: "#E8F0FF")
        case .yggdrasilRoots:
            return Recipe(floor: "floor_slate", floorRepeats: 5, floorTint: "#6E8A6A", rock: "rock_cliff",
                          backdrop: "yggdrasil_roots_bg", props: roots + runeStones,
                          braziers: [braziers[2], braziers[3]], brazierAsset: "prop_norse_brazier", flameHex: "#90FFB0",
                          mistHex: "#B0D0A0", mistCount: 9, dustHex: "#C8FFC0")
        case .jotunheimHall:
            return Recipe(floor: "floor_slate", floorRepeats: 5, floorTint: "#9AB0C8", rock: "rock_ice",
                          backdrop: "jotunheim_hall_bg", props: pillars + runeStones,
                          braziers: braziers, brazierAsset: "prop_norse_brazier", flameHex: "#80C0FF",
                          mistHex: "#D0E4FF", mistCount: 6, dustHex: "#E0F0FF")
        case .duatGate:
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#9C8468", rock: "rock_cliff",
                          backdrop: "duat_gate_bg", props: colossi + obelisks + columns + sphinxes,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#FFA040",
                          mistHex: "#C8B890", mistCount: 6, dustHex: "#FFD98A")
        case .reedFields:
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#94A07C", rock: "rock_cliff",
                          backdrop: "reed_fields_bg", props: [obelisks[1], sphinxes[0], columns[0]],
                          braziers: [braziers[2], braziers[3]], brazierAsset: "prop_brazier", flameHex: "#FFD070",
                          mistHex: "#D8E6C8", mistCount: 9, dustHex: "#E8F0C0")
        case .hallOfTwoTruths:
            let hall = [
                Placement(asset: "prop_lotus_column", position: SCNVector3(-5.6, 0, -5.2)),
                Placement(asset: "prop_lotus_column", position: SCNVector3(5.6, 0, -5.2)),
                Placement(asset: "prop_lotus_column", position: SCNVector3(-6.6, 0, 0.8)),
                Placement(asset: "prop_lotus_column", position: SCNVector3(6.6, 0, 0.8)),
            ]
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#B8A088", rock: "rock_cliff",
                          backdrop: "hall_of_two_truths_bg", props: colossi + columns + hall,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#FFC060",
                          mistHex: "#E0D0A8", mistCount: 4, dustHex: "#FFE8B0")
        case .serpentDeep:
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#5E4878", rock: "rock_cliff",
                          backdrop: "serpent_deep_bg", props: obelisks + sphinxes + columns,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#B07CFF",
                          mistHex: "#8A6AC0", mistCount: 8, dustHex: "#C8A0FF")
        case .arenaOfSouls:
            return Recipe(floor: "floor_sandstone", floorRepeats: 6, floorTint: "#A88C70", rock: "rock_cliff",
                          backdrop: "arena_of_souls_bg", props: colossi + obelisks + columns,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#FFB050",
                          mistHex: "#D8C8A0", mistCount: 5, dustHex: "#FFE0A0")
        // The Labyrinth's dungeons: their pantheon's set under their own
        // painting (or the painting of the place they were carved from,
        // until theirs lands — `backdropName`).
        case .colossusVault:
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#A08C6C", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: colossi + columns + sphinxes,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#FFC060",
                          mistHex: "#D0C098", mistCount: 5, dustHex: "#FFE0A0")
        case .hydraLair:
            return Recipe(floor: "floor_moss", floorRepeats: 5, floorTint: "#7E9068", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: broken + [doric[2], doric[3]],
                          braziers: [braziers[0], braziers[1]], brazierAsset: "prop_tripod_brazier", flameHex: "#90FF90",
                          mistHex: "#98B088", mistCount: 14, dustHex: "#B8E0A0")
        case .necropolis:
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#8A7A80", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: obelisks + columns + sphinxes,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#9C80FF",
                          mistHex: "#9C8CB0", mistCount: 9, dustHex: "#C8B0FF")
        }
    }

    // MARK: - The battle stage

    /// The whole set for a battle, added to `scene`. The camera is at +Z
    /// looking toward -Z; units stand between z = +2.2 and z = -5.4.
    static func buildBattleStage(_ environment: BattleEnvironment, into scene: SCNScene) {
        let recipe = recipe(for: environment)
        let stage = SCNNode()
        stage.name = "stage"
        scene.rootNode.addChildNode(stage)

        stage.addChildNode(platform(radius: 7.6, thickness: 1.8, floor: recipe.floor,
                                    repeats: recipe.floorRepeats, tint: recipe.floorTint, rock: recipe.rock,
                                    centre: SCNVector3(0, 0, -0.8)))
        for chunk in hangingRocks(rock: recipe.rock, seed: environment.rawValue.hashValue) {
            stage.addChildNode(chunk)
        }

        for placement in recipe.props {
            stage.addChildNode(prop(placement))
        }
        let flame = UIColor(hex: recipe.flameHex) ?? .orange
        for position in recipe.braziers {
            stage.addChildNode(brazier(asset: recipe.brazierAsset, at: position, flame: flame))
        }

        let mist = UIColor(hex: recipe.mistHex) ?? .white
        for plane in mistPlanes(count: recipe.mistCount, radius: 7.0, tint: mist, seed: environment.rawValue.hashValue) {
            stage.addChildNode(plane)
        }
        stage.addChildNode(dust(tint: UIColor(hex: recipe.dustHex) ?? .white,
                                volume: SCNVector3(18, 6, 16), at: SCNVector3(0, 3, -1)))

        if let backdrop = recipe.backdrop, let image = UIImage(named: backdrop) {
            stage.addChildNode(farBackdrop(image))
        }

        // The sky beyond the painting, and a light haze on the distance.
        let fog = UIColor(hex: environment.fogHex) ?? .darkGray
        scene.background.contents = fog.mixed(with: .white, amount: 0.15)
        scene.fogStartDistance = 55
        scene.fogEndDistance = 170
        scene.fogColor = fog.mixed(with: .white, amount: 0.25)
        scene.fogDensityExponent = 1.2
    }

    // MARK: - The summoning circle

    /// A rune dais on a floating rock, a half-ring of pillars and two braziers
    /// behind it, mist and dust. The view's SwiftUI backdrop (the glow and the
    /// rays) shows through between the pillars, so there is no sky here.
    static func buildSummoningCircle(pantheon: Pantheon, tint: UIColor, into scene: SCNScene) {
        let greek = pantheon == .greek
        let stage = SCNNode()
        stage.name = "stage"
        scene.rootNode.addChildNode(stage)

        let floor = greek ? "floor_marble" : "floor_sandstone"
        stage.addChildNode(platform(radius: 5.6, thickness: 1.4, floor: floor, repeats: 3,
                                    tint: "#A08A6E", rock: "rock_cliff", centre: SCNVector3(0, -0.3, -0.6)))
        // The dais the figure stands on, a step up from the platform.
        let dais = SCNCylinder(radius: 2.4, height: 0.3)
        dais.radialSegmentCount = 48
        dais.materials = [rockMaterial("rock_cliff", repeats: SCNVector3(4, 1, 1)),
                          floorMaterial(floor, repeats: 2.2, tint: "#A08A6E"),
                          rockMaterial("rock_cliff", repeats: SCNVector3(1, 1, 1))]
        let daisNode = SCNNode(geometry: dais)
        daisNode.position = SCNVector3(0, -0.15, 0)
        stage.addChildNode(daisNode)

        stage.addChildNode(runeRing(radius: 1.95, tint: tint))

        // Everything stands behind the figure and to its left: the camera
        // is offset so the figure lands on the left of the screen and the
        // words on the right, and a pillar under the words was noise.
        let pillarAsset = greek ? "prop_doric_column" : "prop_lotus_column"
        for angle in [165, 190, 215, 240] as [Float] {
            let radians = angle * .pi / 180
            let position = SCNVector3(sin(radians) * 4.4, 0, cos(radians) * 4.4)
            stage.addChildNode(prop(Placement(asset: pillarAsset, position: position, yaw: 0, scale: 0.78)))
        }
        let brazierAsset = greek ? "prop_tripod_brazier" : "prop_brazier"
        for angle in [200.0, 235.0] as [Float] {
            let radians = angle * .pi / 180
            stage.addChildNode(brazier(asset: brazierAsset, at: SCNVector3(sin(radians) * 3.6, 0, cos(radians) * 3.6),
                                       flame: tint.mixed(with: .orange, amount: 0.4)))
        }
        if greek {
            stage.addChildNode(prop(Placement(asset: "prop_temple_ruin", position: SCNVector3(-1.4, 0, -6.4), scale: 0.9, standIn: .none)))
        } else {
            stage.addChildNode(prop(Placement(asset: "prop_anubis_colossus", position: SCNVector3(-1.6, 0, -6.6), scale: 0.75, standIn: .none)))
        }

        for plane in mistPlanes(count: 5, radius: 4.6, tint: tint.mixed(with: .white, amount: 0.6), seed: 7) {
            // Behind the figure only: a plane between the figure and a camera
            // four metres away would fill the frame with haze.
            plane.position.z = -abs(plane.position.z) - 1.0
            plane.position.y = 0.2
            stage.addChildNode(plane)
        }
        stage.addChildNode(dust(tint: tint.mixed(with: .white, amount: 0.5), volume: SCNVector3(9, 5, 9), at: SCNVector3(0, 2.5, -1)))
    }

    // MARK: - Parts

    /// The stone the set stands on: a painted floor on top, a cliff face round
    /// the side, boulders at the rim.
    static func platform(radius: CGFloat, thickness: CGFloat, floor: String, repeats: Float,
                         tint: String?, rock: String, centre: SCNVector3) -> SCNNode {
        let node = SCNNode()
        node.name = "platform"
        let body = SCNCylinder(radius: radius, height: thickness)
        body.radialSegmentCount = 64
        body.materials = [
            rockMaterial(rock, repeats: SCNVector3(Float(radius) * 0.7, 1, 1)),
            floorMaterial(floor, repeats: repeats, tint: tint),
            rockMaterial(rock, repeats: SCNVector3(2, 2, 1)),
        ]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(centre.x, centre.y - Float(thickness) / 2, centre.z)
        node.addChildNode(bodyNode)

        // Boulders round the rim break the perfect circle. Deterministic, so
        // the stage is the same every battle.
        var rng = SeededRandom(seed: UInt64(radius * 1000) &+ 0x5EED)
        let count = Int(radius * 2.6)
        for index in 0..<count {
            let angle = Float(index) / Float(count) * 2 * .pi + Float(rng.unit()) * 0.15
            // None on the front arc: the camera sits outside the rim there
            // and a close shot that swings low would land inside a boulder.
            if cos(angle) > 0.72 { continue }
            let size = CGFloat(0.5 + rng.unit() * 0.9) * thickness * 0.55
            let boulder = SCNSphere(radius: size)
            boulder.segmentCount = 10
            boulder.firstMaterial = rockMaterial(rock, repeats: SCNVector3(2, 1, 1))
            let boulderNode = SCNNode(geometry: boulder)
            let r = Float(radius) * (0.96 + Float(rng.unit()) * 0.08)
            boulderNode.position = SCNVector3(centre.x + sin(angle) * r,
                                              centre.y - Float(size) * 0.55 - Float(rng.unit()) * 0.3,
                                              centre.z + cos(angle) * r)
            boulderNode.scale = SCNVector3(1 + Float(rng.unit()) * 0.6, 0.7 + Float(rng.unit()) * 0.4, 1 + Float(rng.unit()) * 0.5)
            boulderNode.eulerAngles = SCNVector3(Float(rng.unit()), Float(rng.unit()) * 6, Float(rng.unit()))
            node.addChildNode(boulderNode)
        }
        return node
    }

    /// Rock chunks hanging under and beyond the platform, bobbing slowly, the
    /// sign that the whole thing is in the air.
    static func hangingRocks(rock: String, seed: Int) -> [SCNNode] {
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(seed)) &+ 0xC4A5)
        var chunks: [SCNNode] = []
        let spots: [SCNVector3] = [
            SCNVector3(-14, -6, -14), SCNVector3(15, -4, -18), SCNVector3(-19, -9, -4),
            SCNVector3(18, -11, -2), SCNVector3(-8, -12, -24), SCNVector3(9, -8, -26),
        ]
        for spot in spots {
            let size = CGFloat(1.6 + rng.unit() * 2.2)
            let geometry = SCNSphere(radius: size)
            geometry.segmentCount = 9
            geometry.firstMaterial = rockMaterial(rock, repeats: SCNVector3(3, 2, 1))
            let chunk = SCNNode(geometry: geometry)
            chunk.position = spot
            chunk.scale = SCNVector3(1.3 + Float(rng.unit()) * 0.5, 0.6 + Float(rng.unit()) * 0.3, 1.1 + Float(rng.unit()) * 0.5)
            chunk.eulerAngles = SCNVector3(Float(rng.unit()) * 0.4, Float(rng.unit()) * 6, Float(rng.unit()) * 0.4)
            let bob = SCNAction.moveBy(x: 0, y: CGFloat(0.25 + rng.unit() * 0.3), z: 0, duration: 5 + rng.unit() * 4)
            bob.timingMode = .easeInEaseOut
            chunk.runAction(.repeatForever(.sequence([bob, bob.reversed()])))
            chunks.append(chunk)
        }
        return chunks
    }

    /// A shipped prop, or its stand-in.
    static func prop(_ placement: Placement) -> SCNNode {
        let node: SCNNode
        if let loaded = loadProp(placement.asset) {
            node = loaded
        } else {
            node = standIn(placement.standIn, height: CGFloat(propHeights[placement.asset] ?? 3))
        }
        node.name = placement.asset
        node.position = placement.position
        let yaw = (placement.yaw + (propYaw[placement.asset] ?? 0)) * .pi / 180
        node.eulerAngles = SCNVector3(0, yaw, 0)
        node.scale = SCNVector3(placement.scale, placement.scale, placement.scale)
        return node
    }

    private static var propCache: [String: SCNNode] = [:]

    /// `prop_<name>.usdz` from the bundle, tuned like a character but without
    /// the rim, cached and cloned. Nil when it has not shipped.
    static func loadProp(_ name: String) -> SCNNode? {
        if let cached = propCache[name] { return cached.clone() }
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: ModelLibrary.modelDirectory)
                ?? Bundle.main.url(forResource: name, withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: [.createNormalsIfAbsent: true]) else {
            return nil
        }
        let wrapper = SCNNode()
        for child in scene.rootNode.childNodes { wrapper.addChildNode(child) }
        MaterialTuner.tune(wrapper)
        wrapper.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                material.setValue(NSNumber(value: Float(0.18)), forKey: "rimStrength")
            }
        }
        propCache[name] = wrapper
        return wrapper.clone()
    }

    /// Geometry that stands where a prop would, at its height, in the stage's
    /// own stone, so a missing file is a plainer set rather than a hole.
    static func standIn(_ kind: StandIn, height: CGFloat) -> SCNNode {
        let node = SCNNode()
        switch kind {
        case .none:
            break
        case .column:
            let shaft = SCNCylinder(radius: height * 0.09, height: height * 0.86)
            shaft.firstMaterial = floorMaterial("floor_sandstone", repeats: 1.5, tint: nil)
            let shaftNode = SCNNode(geometry: shaft)
            shaftNode.position = SCNVector3(0, Float(height) * 0.43, 0)
            node.addChildNode(shaftNode)
            let capital = SCNCylinder(radius: height * 0.15, height: height * 0.1)
            capital.firstMaterial = floorMaterial("floor_sandstone", repeats: 1, tint: nil)
            let capitalNode = SCNNode(geometry: capital)
            capitalNode.position = SCNVector3(0, Float(height) * 0.91, 0)
            node.addChildNode(capitalNode)
            let base = SCNBox(width: height * 0.3, height: height * 0.06, length: height * 0.3, chamferRadius: 0.02)
            base.firstMaterial = rockMaterial("rock_cliff", repeats: SCNVector3(1, 1, 1))
            let baseNode = SCNNode(geometry: base)
            baseNode.position = SCNVector3(0, Float(height) * 0.03, 0)
            node.addChildNode(baseNode)
        case .obelisk:
            let shaft = SCNBox(width: height * 0.13, height: height * 0.86, length: height * 0.13, chamferRadius: 0)
            shaft.firstMaterial = floorMaterial("floor_sandstone", repeats: 1, tint: nil)
            let shaftNode = SCNNode(geometry: shaft)
            shaftNode.position = SCNVector3(0, Float(height) * 0.43, 0)
            node.addChildNode(shaftNode)
            let tip = SCNPyramid(width: height * 0.13, height: height * 0.14, length: height * 0.13)
            tip.firstMaterial = floorMaterial("floor_sandstone", repeats: 1, tint: "#FFD98A")
            let tipNode = SCNNode(geometry: tip)
            tipNode.position = SCNVector3(0, Float(height) * 0.86, 0)
            node.addChildNode(tipNode)
        case .block:
            let block = SCNBox(width: height * 0.5, height: height, length: height * 0.4, chamferRadius: height * 0.03)
            block.firstMaterial = rockMaterial("rock_cliff", repeats: SCNVector3(1, 2, 1))
            let blockNode = SCNNode(geometry: block)
            blockNode.position = SCNVector3(0, Float(height) / 2, 0)
            node.addChildNode(blockNode)
        }
        return node
    }

    /// A brazier prop (or a stone bowl) with a flame and a flickering light.
    static func brazier(asset: String, at position: SCNVector3, flame: UIColor) -> SCNNode {
        let height = propHeights[asset] ?? 1.4
        let node = prop(Placement(asset: asset, position: position, standIn: .none))
        if node.childNodes.isEmpty {
            let bowl = SCNCylinder(radius: CGFloat(height) * 0.36, height: CGFloat(height) * 0.18)
            bowl.firstMaterial = rockMaterial("rock_cliff", repeats: SCNVector3(2, 1, 1))
            let bowlNode = SCNNode(geometry: bowl)
            bowlNode.position = SCNVector3(0, height * 0.91, 0)
            node.addChildNode(bowlNode)
            let stem = SCNCylinder(radius: CGFloat(height) * 0.12, height: CGFloat(height) * 0.82)
            stem.firstMaterial = floorMaterial("floor_sandstone", repeats: 1, tint: nil)
            let stemNode = SCNNode(geometry: stem)
            stemNode.position = SCNVector3(0, height * 0.41, 0)
            node.addChildNode(stemNode)
        }
        let fire = SCNNode()
        fire.position = SCNVector3(0, height * 1.02, 0)
        fire.addParticleSystem(VFXLibrary.flame(tint: flame, scale: height))
        let light = SCNLight()
        light.type = .omni
        light.color = flame
        light.intensity = 300
        light.attenuationStartDistance = 0.5
        light.attenuationEndDistance = 6
        fire.light = light
        let flicker = SCNAction.customAction(duration: 2.3) { node, elapsed in
            let t = Float(elapsed)
            node.light?.intensity = CGFloat(300 + 70 * sin(t * 11.3) + 40 * sin(t * 4.7 + 1.3))
        }
        fire.runAction(.repeatForever(flicker))
        node.addChildNode(fire)
        return node
    }

    /// The glowing ring on the summon dais: the painted rune texture, additive,
    /// in the element's colour, turning slowly.
    static func runeRing(radius: CGFloat, tint: UIColor) -> SCNNode {
        let plane = SCNPlane(width: radius * 2, height: radius * 2)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIImage(named: "rune_ring") ?? tint
        material.multiply.contents = tint.mixed(with: .white, amount: 0.35)
        material.emission.contents = UIImage(named: "rune_ring")
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        plane.firstMaterial = material
        let ring = SCNNode(geometry: plane)
        ring.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        let spinner = SCNNode()
        spinner.position = SCNVector3(0, 0.02, 0)
        spinner.addChildNode(ring)
        spinner.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 40)))
        return spinner
    }

    /// Drifting mist: painted puffs on planes that face the camera, additive
    /// and faint, sliding slowly round the platform's edge.
    static func mistPlanes(count: Int, radius: Float, tint: UIColor, seed: Int) -> [SCNNode] {
        guard let image = UIImage(named: "mist") else { return [] }
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(seed)) &+ 0x3157)
        var planes: [SCNNode] = []
        for index in 0..<count {
            let plane = SCNPlane(width: 7, height: 3.2)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.multiply.contents = tint
            material.blendMode = .add
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            material.isDoubleSided = true
            plane.firstMaterial = material
            let node = SCNNode(geometry: plane)
            node.opacity = 0.09 + CGFloat(rng.unit()) * 0.08
            let angle = Float(index) / Float(count) * 2 * .pi + Float(rng.unit()) * 0.5
            node.position = SCNVector3(sin(angle) * radius, 0.4 + Float(rng.unit()) * 0.6, cos(angle) * radius - 1.2)
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = [.Y]
            node.constraints = [billboard]
            let drift = SCNAction.moveBy(x: CGFloat(1.2 + rng.unit() * 1.4) * (index % 2 == 0 ? 1 : -1), y: 0, z: 0,
                                         duration: 9 + rng.unit() * 6)
            drift.timingMode = .easeInEaseOut
            node.runAction(.repeatForever(.sequence([drift, drift.reversed()])))
            planes.append(node)
        }
        return planes
    }

    /// Slow motes of light in the air over the stage.
    static func dust(tint: UIColor, volume: SCNVector3, at position: SCNVector3) -> SCNNode {
        let node = SCNNode()
        node.position = position
        node.addParticleSystem(VFXLibrary.dust(tint: tint, volume: volume))
        return node
    }

    /// The environment's painting far behind the set, big enough to fill the
    /// frame below the platform's far edge as well as above it: the land in
    /// the painting reads as a world far below, which is what makes the
    /// platform float.
    static func farBackdrop(_ image: UIImage) -> SCNNode {
        let plane = SCNPlane(width: 170, height: 170)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = false
        plane.firstMaterial = material
        let node = SCNNode(geometry: plane)
        // Centred well below the platform, so the painting's horizon sits a
        // little under the platform's far edge on screen: sky above the edge,
        // the painted land far below it.
        node.position = SCNVector3(0, -16, -70)
        node.name = "backdrop"
        return node
    }

    // MARK: - Materials

    static func floorMaterial(_ texture: String, repeats: Float, tint: String?) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIImage(named: texture) ?? UIColor(hex: "#B08A5A")
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(repeats, repeats, 1)
        material.roughness.contents = 0.8
        material.metalness.contents = 0.0
        if let tint, let colour = UIColor(hex: tint) {
            material.multiply.contents = colour
        }
        return material
    }

    static func rockMaterial(_ texture: String, repeats: SCNVector3) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIImage(named: texture) ?? UIColor(hex: "#6A5A48")
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(repeats.x, repeats.y, 1)
        material.roughness.contents = 0.9
        material.metalness.contents = 0.0
        return material
    }
}
