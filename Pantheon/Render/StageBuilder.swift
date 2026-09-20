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
        // The +x obelisk (and the Greek column and Norse stone on the same
        // mark) stands at the back of its wing, not beside the line: from
        // the camera's side of the field a wing prop at z = −2.4 is a
        // foreground pillar.
        let obelisks = [
            Placement(asset: "prop_obelisk", position: SCNVector3(-6.9, 0, -2.4), standIn: .obelisk),
            Placement(asset: "prop_obelisk", position: SCNVector3(7.0, 0, -5.0), standIn: .obelisk),
        ]
        let columns = [
            Placement(asset: "prop_lotus_column", position: SCNVector3(-2.4, 0, -7.0)),
            Placement(asset: "prop_lotus_column", position: SCNVector3(2.4, 0, -7.0)),
        ]
        // Both sphinxes on the LEFT, an avenue. The camera stands 58° round
        // to the right now (`CameraDirector.homeYaw`), which makes the +x
        // wing the foreground: a sphinx at (6, −0.4) filled the lower right
        // of the first frames and hid the enemy column's front mark behind
        // its head. The left wing is the far side, where a prop adds depth
        // behind the player's column and stands in front of nothing.
        let sphinxes = [
            Placement(asset: "prop_sphinx", position: SCNVector3(-6.0, 0, -0.4), yaw: 90, standIn: .block),
            Placement(asset: "prop_sphinx", position: SCNVector3(-6.4, 0, -4.2), yaw: 90, standIn: .block),
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
            Placement(asset: "prop_doric_column", position: SCNVector3(7.0, 0, -5.0)),
        ]
        let ruin = [
            Placement(asset: "prop_temple_ruin", position: SCNVector3(0, 0, -7.6), scale: 0.8, standIn: .block),
        ]
        let broken = [
            Placement(asset: "prop_broken_column", position: SCNVector3(-6.0, 0, -0.4), standIn: .block),
            Placement(asset: "prop_broken_column", position: SCNVector3(-6.4, 0, -4.2), standIn: .block),
        ]
        // The Labyrinth's own pieces (Meshy image-to-3D from Gemini concepts,
        // 2026-09-17, 30 credits each): the Vault's bronze door stands at the
        // back-left corner turned to the field, with a fallen pharaoh's head
        // in the right wing and the canopic altar low in the near-left; the
        // Lair grows dead trees at the back corners and one in the right
        // wing over a bone pile; the Necropolis stands two sarcophagi at
        // the back corners, the head behind the left column, the altar and
        // the bones in the wings. Every mark is one the sets already use
        // (wings at z −1.4 and beyond, nothing tall nearer than the rows).
        let vaultSet = [
            Placement(asset: "prop_vault_door", position: SCNVector3(-5.0, 0, -7.8), yaw: 20, scale: 0.9, standIn: .block),
            Placement(asset: "prop_pharaoh_head", position: SCNVector3(6.4, 0, -3.8), yaw: -30, scale: 0.9, standIn: .block),
            Placement(asset: "prop_canopic_jars", position: SCNVector3(-6.8, 0, 1.2), scale: 0.8, standIn: .block),
        ]
        let lairSet = [
            Placement(asset: "prop_dead_tree", position: SCNVector3(-5.3, 0, -6.3), scale: 0.9, standIn: .block),
            Placement(asset: "prop_dead_tree", position: SCNVector3(5.3, 0, -6.3), yaw: 140, scale: 0.9, standIn: .block),
            Placement(asset: "prop_dead_tree", position: SCNVector3(6.6, 0, -1.4), yaw: 60, scale: 0.7, standIn: .block),
            Placement(asset: "prop_bone_pile", position: SCNVector3(-6.6, 0, 1.0), scale: 0.9, standIn: .block),
        ]
        let necropolisSet = [
            Placement(asset: "prop_sarcophagus", position: SCNVector3(-5.3, 0, -6.3), yaw: 15, standIn: .block),
            Placement(asset: "prop_sarcophagus", position: SCNVector3(5.3, 0, -6.3), yaw: -15, standIn: .block),
            Placement(asset: "prop_pharaoh_head", position: SCNVector3(-4.0, 0, -7.4), yaw: 40, scale: 0.9, standIn: .block),
            Placement(asset: "prop_canopic_jars", position: SCNVector3(6.6, 0, -1.4), scale: 0.9, standIn: .block),
            Placement(asset: "prop_bone_pile", position: SCNVector3(-6.6, 0, 1.0), scale: 0.8, standIn: .block),
        ]
        // The Norse set: rune stones at the sides, a longship prow and the
        // world tree's roots at the back corners, hall pillars closing the
        // back, braziers on dragon-headed posts.
        let runeStones = [
            Placement(asset: "prop_rune_stone", position: SCNVector3(-6.9, 0, -2.4), standIn: .obelisk),
            Placement(asset: "prop_rune_stone", position: SCNVector3(7.0, 0, -5.0), standIn: .obelisk),
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
            // Three columns, not four: the one at (6.6, 0.8) stood between
            // the camera and the enemy line once the camera moved to the
            // +x side, and the owner photographed the Hall of Sentinels with
            // a pillar down the middle of the fight. The +x wing is the
            // foreground now; nothing tall stands in it.
            let hall = [
                Placement(asset: "prop_lotus_column", position: SCNVector3(-5.6, 0, -5.2)),
                Placement(asset: "prop_lotus_column", position: SCNVector3(5.6, 0, -5.2)),
                Placement(asset: "prop_lotus_column", position: SCNVector3(-6.6, 0, 0.8)),
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
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#8A7A64", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: colossi + columns + sphinxes + vaultSet,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#FFB050",
                          mistHex: "#B0A088", mistCount: 5, dustHex: "#E0C898")
        case .hydraLair:
            return Recipe(floor: "floor_moss", floorRepeats: 5, floorTint: "#7E9068", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: broken + [doric[2], doric[3]] + lairSet,
                          braziers: [braziers[0], braziers[1]], brazierAsset: "prop_tripod_brazier", flameHex: "#90FF90",
                          mistHex: "#98B088", mistCount: 14, dustHex: "#B8E0A0")
        case .necropolis:
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#8A7A80", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: obelisks + columns + sphinxes + necropolisSet,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#9C80FF",
                          mistHex: "#9C8CB0", mistCount: 9, dustHex: "#C8B0FF")
        // Rome: the Greek marble and props under Roman paintings until Rome's
        // own are made — the Forum by moonlight with its columns and the
        // temple ruin, the arena in sun with the statues and the broken
        // columns. `backdropName` borrows an older painting until
        // tools/batch/realms_batch4.sh paints theirs.
        case .forumRome:
            return Recipe(floor: "floor_marble", floorRepeats: 5, floorTint: "#9C9CB0", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: doric + ruin + [broken[0]],
                          braziers: braziers, brazierAsset: "prop_tripod_brazier", flameHex: "#FFC070",
                          mistHex: "#B8B8D8", mistCount: 9, dustHex: "#D8D8F0")
        case .colosseumSands:
            return Recipe(floor: "floor_sandstone", floorRepeats: 6, floorTint: "#C8A878", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: statues + [doric[0], doric[1]] + broken,
                          braziers: braziers, brazierAsset: "prop_tripod_brazier", flameHex: "#FFB050",
                          mistHex: "#E8D8B0", mistCount: 4, dustHex: "#FFE0A0")
        // The Jade Court: the sandstone floor under a red tint, lotus columns
        // standing in for the palace's, and two props that do not exist yet
        // — stone lions in the far wing, pagoda lanterns at the back corners
        // — each placed with a stand-in so the set has no hole until they
        // ship (`propHeights` has no entry for them: the stand-in is the 3 m
        // default, scaled here). Nothing tall in the +x wing at z > -5.
        case .peachGarden:
            let lions = [
                Placement(asset: "prop_stone_lion", position: SCNVector3(-6.0, 0, -0.4), yaw: 90, scale: 0.6, standIn: .block),
                Placement(asset: "prop_stone_lion", position: SCNVector3(-6.4, 0, -4.2), yaw: 90, scale: 0.6, standIn: .block),
            ]
            let lanterns = [
                Placement(asset: "prop_pagoda_lantern", position: SCNVector3(-5.3, 0, -6.3), scale: 0.8, standIn: .obelisk),
                Placement(asset: "prop_pagoda_lantern", position: SCNVector3(5.3, 0, -6.3), scale: 0.8, standIn: .obelisk),
            ]
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#B07860", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: columns + lanterns + lions,
                          braziers: [braziers[2], braziers[3]], brazierAsset: "prop_brazier", flameHex: "#FF9060",
                          mistHex: "#F0C8C8", mistCount: 8, dustHex: "#FFD0D8")
        case .dragonGate:
            let lions = [
                Placement(asset: "prop_stone_lion", position: SCNVector3(-3.8, 0, -7.2), scale: 0.7, standIn: .block),
                Placement(asset: "prop_stone_lion", position: SCNVector3(3.8, 0, -7.2), yaw: 180, scale: 0.7, standIn: .block),
            ]
            let lanterns = [
                Placement(asset: "prop_pagoda_lantern", position: SCNVector3(-6.9, 0, -2.4), scale: 0.8, standIn: .obelisk),
                Placement(asset: "prop_pagoda_lantern", position: SCNVector3(7.0, 0, -5.0), scale: 0.8, standIn: .obelisk),
            ]
            return Recipe(floor: "floor_sandstone", floorRepeats: 5, floorTint: "#9A5A58", rock: "rock_cliff",
                          backdrop: environment.backdropName, props: columns + lions + lanterns,
                          braziers: braziers, brazierAsset: "prop_brazier", flameHex: "#60C0FF",
                          mistHex: "#A0C8E0", mistCount: 11, dustHex: "#B8E0FF")
        }
    }

    // MARK: - The battle stage

    /// The battle platform's radius. 7.6 showed its near rim in every frame.

    /// The whole set for a battle, added to `scene`. The camera is at +Z
    /// looking toward -Z; units stand between z = +2.2 and z = -5.4.
    /// Returns the painting's palette so the lights can be built to match it.
    @discardableResult
    static func buildBattleStage(_ environment: BattleEnvironment, into scene: SCNScene) -> PaintingPalette {
        let recipe = recipe(for: environment)
        let stage = SCNNode()
        stage.name = "stage"
        scene.rootNode.addChildNode(stage)

        // AN ARENA FLOOR, NOT A DISC (2026-09-11). The owner, twice, with a
        // fight on his phone: "the battle ground should look flat, not
        // slanted" and then "when the heck are you fixing the camera view?
        // Take a look at Summoners War. DO THAT." What the genre shows is a
        // floor: a wide flat ground whose side edges are outside the frame,
        // whose one visible edge — the far one — runs STRAIGHT across the
        // upper third under the painting, with the world's axes square to
        // the screen so tiles, pillars and statues all stand upright. What
        // we showed was a floating disc: its curved rim in three corners,
        // a boulder ring, rocks hanging in a void, and the whole world
        // turned 58° so the grid ran diagonally. So the ground is a 44 m
        // square slab whose far face is at `battleFloorFarEdge`, where the
        // boss stands a stride beyond it (`BattleSceneController.bossMark`),
        // and the camera looks straight up the field (`CameraDirector.homeYaw`
        // is 0). Nothing under or beside the slab is drawn; the painting is
        // hung beyond the far edge.
        stage.addChildNode(slab(size: Self.battleFloorSize, thickness: 1.8, farEdge: Self.battleFloorFarEdge,
                                floor: recipe.floor, repeats: recipe.floorRepeats * 2.86,
                                tint: recipe.floorTint, rock: recipe.rock))
        // THE ARENA DRESSED (2026-09-15, part 4 of "I want THAT level of
        // detail"): its sides walled, its floor inlaid, its air moving —
        // the free half of the pass; the painted tiles and the Meshy set
        // pieces are the half that costs (Docs/PLAN.md).
        stage.addChildNode(sideWalls(rock: recipe.rock, farEdge: Self.battleFloorFarEdge, nearEnd: 9.0))
        let groove = (UIColor(hex: recipe.floorTint ?? "#9C8468") ?? .brown).mixed(with: .black, amount: 0.55)
        stage.addChildNode(arenaInlay(radius: 6.6, groove: groove, at: SCNVector3(0.3, 0, 0)))

        // The sets were dressed for two lines abreast at z = ±3.4, with the
        // statues, obelisks and braziers standing 5–7 m out to the sides at
        // z −0.4 to −5. The wings stand THERE now — the first arena frames
        // had Zeus inside a sphinx and three enemies behind a brazier — so
        // every side piece in the wings' band is moved out to the edge of
        // the frame, where the genre keeps its decoration: the arena is
        // open in the middle and framed at the sides and the back. The back
        // row (the two columns, the ruin, the statues at z −6.3, the
        // braziers at ±3.8) is beyond the deepest mark and stays.
        for placement in recipe.props {
            var placed = placement
            placed.position = Self.clearOfTheWings(placement.position)
            stage.addChildNode(prop(placed))
        }
        let flame = UIColor(hex: recipe.flameHex) ?? .orange
        for position in recipe.braziers {
            stage.addChildNode(brazier(asset: recipe.brazierAsset, at: Self.clearOfTheWings(position), flame: flame))
        }

        let mist = UIColor(hex: recipe.mistHex) ?? .white
        // Mist along the far edge only: a ring round the old disc put a
        // plane a metre in front of the lens now that the near side of the
        // ground is behind the camera.
        for plane in mistPlanes(count: recipe.mistCount * 2, radius: -Self.battleFloorFarEdge + 1.2, tint: mist, seed: environment.rawValue.hashValue)
        where plane.position.z < Self.battleFloorFarEdge * 0.45 {
            stage.addChildNode(plane)
        }
        stage.addChildNode(dust(tint: UIColor(hex: recipe.dustHex) ?? .white,
                                volume: SCNVector3(18, 6, 16), at: SCNVector3(0, 3, -1)))

        if let weather = weather(for: environment) {
            let air = SCNNode()
            let rises = weather.kind == .embers || weather.kind == .wisps || weather.kind == .motes
            air.position = SCNVector3(0, rises ? 0.4 : 6.5, -1)
            air.addParticleSystem(VFXLibrary.weather(weather.kind, tint: weather.tint,
                                                     volume: SCNVector3(22, rises ? 1.5 : 1, 18)))
            stage.addChildNode(air)
        }

        let painting = recipe.backdrop.flatMap { BundleArt.image($0) }
        if let painting {
            stage.addChildNode(farBackdrop(painting, yaw: CameraDirector.backdropYaw))
        }

        // ONE LIGHT FOR THE SET AND THE PAINTING (2026-09-15). The fog and
        // the sky beyond the painting are the painting's own horizon and
        // sky, mixed with the hand-picked fog so a night painting's intent
        // (the Serpent Deep's violet) survives its measured near-black;
        // `BattleSceneController` lights the set from the same palette. The
        // haze is light and starts beyond the far parapet: the floor is
        // never fogged, the painting takes about a tenth of the horizon
        // colour at 70 m, enough to sit in the same air.
        var palette = painting.flatMap { PaintingPalette(image: $0) } ?? .neutral
        if let painting {
            palette.environment = environmentMap(from: painting, palette: palette)
        }
        let hand = UIColor(hex: environment.fogHex) ?? .darkGray
        let fog = palette.horizon.mixed(with: hand, amount: 0.35)
        scene.background.contents = palette.sky.mixed(with: fog, amount: 0.3)
        scene.fogStartDistance = 45
        scene.fogEndDistance = 170
        scene.fogColor = fog
        scene.fogDensityExponent = 1.4
        return palette
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

    // MARK: - The arena's edges, its inlay, its light and its air (2026-09-15)

    /// The arena's sides: a low balustrade down each flank of the field from
    /// the far parapet to behind the team, so the ground is a bounded PLACE
    /// — the genre's arena has an edge on every side — and not a slab
    /// running off into the wings. At ±9.8 m the walls stand a stride
    /// outside the side pieces (`clearOfTheWings` puts them at 8.5) and
    /// outside a five-a-side's outer marks (±5.4). Projected in the Python
    /// port of the camera solve before it was built: from the home camera
    /// the far-side wall runs diagonally down the upper left of the frame
    /// between the floor and the painting, the near-side one lies along the
    /// frame's right edge (inside it only for a five-a-side), and from the
    /// boss camera both flank the boss.
    static let arenaHalfWidth: Float = 9.8

    static func sideWalls(rock: String, farEdge: Float, nearEnd: Float) -> SCNNode {
        let node = SCNNode()
        node.name = "walls"
        let length = CGFloat(nearEnd - farEdge)
        let centreZ = (nearEnd + farEdge) / 2
        for sign in [Float(-1), Float(1)] {
            let x = sign * arenaHalfWidth
            let wall = SCNBox(width: 0.6, height: 0.9, length: length, chamferRadius: 0.05)
            wall.materials = [rockMaterial(rock, repeats: SCNVector3(Float(length) * 0.5, 1, 1))]
            let wallNode = SCNNode(geometry: wall)
            wallNode.position = SCNVector3(x, 0.45, centreZ)
            node.addChildNode(wallNode)
            // A coping along the top, a hand wider than the wall.
            let coping = SCNBox(width: 0.8, height: 0.14, length: length + 0.2, chamferRadius: 0.03)
            coping.materials = [rockMaterial(rock, repeats: SCNVector3(Float(length) * 0.5, 0.3, 1))]
            let copingNode = SCNNode(geometry: coping)
            copingNode.position = SCNVector3(x, 0.97, centreZ)
            node.addChildNode(copingNode)
            // Posts every four metres break the line.
            var z = farEdge + 1.0
            while z < nearEnd - 0.5 {
                let post = SCNBox(width: 0.72, height: 1.25, length: 0.72, chamferRadius: 0.04)
                post.materials = [rockMaterial(rock, repeats: SCNVector3(1, 1, 1))]
                let postNode = SCNNode(geometry: post)
                postNode.position = SCNVector3(x, 0.625, z)
                node.addChildNode(postNode)
                z += 4.0
            }
        }
        return node
    }

    /// The arena's floor inlay: rings and a compass star cut into the stone
    /// under the fight, the genre's circular battleground (every Summoners
    /// War scenario floor has one). A quad a finger above the slab whose
    /// grooves are MULTIPLIED over the tiles, so they darken the stone the
    /// way a cut does and the relief still shows through them; the image is
    /// white everywhere else and changes nothing there. 6.6 m round, so the
    /// outer band passes just outside both rows (marks at r ≈ 3–3.9) and
    /// the near arc leaves the frame under the HUD.
    static func arenaInlay(radius: CGFloat, groove: UIColor, at centre: SCNVector3) -> SCNNode {
        let plane = SCNPlane(width: radius * 2, height: radius * 2)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = inlayImage(groove: groove)
        material.blendMode = .multiply
        // Writes colour only: a quad that darkens what is under it has no
        // business changing the frame buffer's alpha (see `runeRing`).
        material.colorBufferWriteMask = [.red, .green, .blue]
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = false
        plane.firstMaterial = material
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.position = SCNVector3(centre.x, 0.02, centre.z)
        node.castsShadow = false
        node.name = "inlay"
        return node
    }

    private static var inlayCache: [String: UIImage] = [:]

    /// The inlay's drawing: an outer band, a ring of ticks inside it, a
    /// thin ring, an inner ring just inside the rows, and an eight-point
    /// star of thin spokes at the centre. Geometry only — a device drawn
    /// here would be the thing the owner called clip art; the stone's own
    /// carving is the tiles' relief.
    private static func inlayImage(groove: UIColor) -> UIImage {
        let key = groove.description
        if let cached = inlayCache[key] { return cached }
        let size: CGFloat = 1024
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let cg = context.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let centre = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2
            func ring(_ r: CGFloat, width: CGFloat, alpha: CGFloat) {
                cg.setStrokeColor(groove.withAlphaComponent(alpha).cgColor)
                cg.setLineWidth(width)
                cg.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            }
            func spoke(angle: CGFloat, from inner: CGFloat, to outer: CGFloat, width: CGFloat, alpha: CGFloat) {
                cg.setStrokeColor(groove.withAlphaComponent(alpha).cgColor)
                cg.setLineWidth(width)
                cg.setLineCap(.round)
                cg.move(to: CGPoint(x: centre.x + cos(angle) * inner, y: centre.y + sin(angle) * inner))
                cg.addLine(to: CGPoint(x: centre.x + cos(angle) * outer, y: centre.y + sin(angle) * outer))
                cg.strokePath()
            }
            ring(radius * 0.93, width: radius * 0.06, alpha: 0.5)
            ring(radius * 0.885, width: radius * 0.012, alpha: 0.45)
            for index in 0..<36 {
                let angle = CGFloat(index) / 36 * .pi * 2
                spoke(angle: angle, from: radius * 0.845, to: radius * 0.87, width: radius * 0.012, alpha: 0.45)
            }
            ring(radius * 0.83, width: radius * 0.012, alpha: 0.45)
            ring(radius * 0.42, width: radius * 0.02, alpha: 0.45)
            ring(radius * 0.09, width: radius * 0.012, alpha: 0.45)
            for index in 0..<8 {
                let angle = CGFloat(index) / 8 * .pi * 2 + .pi / 8
                spoke(angle: angle, from: radius * 0.1, to: radius * 0.40, width: radius * 0.009, alpha: 0.42)
            }
        }
        inlayCache[key] = image
        return image
    }

    /// What the painting says the light is: the average colour of its sky
    /// (the top eighth), its horizon (the band the floor's far edge meets,
    /// 37–56% down) and its ground (the bottom fifth), read off a 32 × 32
    /// reduction. The fog, the sky beyond the painting, the ambient and the
    /// fill light take theirs from here, so the set and the painting are lit
    /// as one place — a marsh's floor sits in the marsh's green, a vault's
    /// in the vault's brown — where every stage used to sit under the same
    /// blue fill.
    struct PaintingPalette {
        var sky: UIColor
        var horizon: UIColor
        var ground: UIColor
        /// The whole painting's mean luminance, 0…1. A pale painting is a
        /// set whose lights are about to double it (2026-09-15: a quarter
        /// of Olympus's marble floor came out as white with no stone in
        /// it), so the camera takes its exposure off this — see
        /// `PaintingPalette.exposureCompensation`.
        var luminance: Double = 0.45
        /// A lighting environment made from the painting itself
        /// (2026-09-20; `StageBuilder.environmentMap`): nil for the
        /// procedural fallback, which has no painting.
        var environment: UIImage? = nil

        static let neutral = PaintingPalette(sky: UIColor(white: 0.5, alpha: 1),
                                             horizon: UIColor(white: 0.35, alpha: 1),
                                             ground: UIColor(white: 0.2, alpha: 1))

        init(sky: UIColor, horizon: UIColor, ground: UIColor, luminance: Double = 0.45) {
            self.sky = sky
            self.horizon = horizon
            self.ground = ground
            self.luminance = luminance
        }

        /// Stops to add to the grade's own exposure: nothing for a painting
        /// at mid grey, down to −0.55 for a sunlit marble one and up to
        /// +0.25 for a night. The hand-picked grade is still added on top,
        /// so a set that is meant to be dark stays dark.
        var exposureCompensation: CGFloat {
            CGFloat(min(0.25, max(-0.55, (0.45 - luminance) * 1.3)))
        }

        init?(image: UIImage) {
            guard let cg = image.cgImage else { return nil }
            let side = 32
            var data = [UInt8](repeating: 0, count: side * side * 4)
            let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
                guard let base = buffer.baseAddress,
                      let context = CGContext(data: base, width: side, height: side, bitsPerComponent: 8,
                                              bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .medium
                context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
                return true
            }
            guard drawn else { return nil }
            // Core Graphics draws with its origin at the bottom left, so the
            // buffer's first row is the painting's bottom.
            func band(fromTop lower: Double, _ upper: Double) -> UIColor {
                var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
                for row in 0..<side {
                    let fromTop = 1 - (Double(row) + 0.5) / Double(side)
                    guard fromTop >= lower, fromTop < upper else { continue }
                    for column in 0..<side {
                        let at = (row * side + column) * 4
                        red += Double(data[at])
                        green += Double(data[at + 1])
                        blue += Double(data[at + 2])
                        count += 1
                    }
                }
                guard count > 0 else { return .gray }
                return UIColor(red: CGFloat(red / count / 255), green: CGFloat(green / count / 255),
                               blue: CGFloat(blue / count / 255), alpha: 1)
            }
            sky = band(fromTop: 0, 0.125)
            horizon = band(fromTop: 0.37, 0.56)
            ground = band(fromTop: 0.8, 1.0)
            var light = 0.0
            for at in stride(from: 0, to: side * side * 4, by: 4) {
                light += 0.2126 * Double(data[at]) + 0.7152 * Double(data[at + 1]) + 0.0722 * Double(data[at + 2])
            }
            luminance = light / Double(side * side) / 255
        }
    }

    /// A lighting environment made from the painting (2026-09-20): a 256 ×
    /// 128 equirectangular map with the painting's own sky above, the
    /// painting wrapped twice round the horizon band (mirrored, so the seam
    /// is a fold and not a cut), and its ground colour below, drawn at
    /// 32 × 16 and stretched, which blurs it into the soft reflection a
    /// lighting environment wants. No battle set ever shipped an .hdr, so
    /// every figure had reflected ONE FLAT COLOUR (the key's hex at 0.35),
    /// which is why a metal could not be let go metallic and the ramp had
    /// to fake its highlight; with the set's own colours to reflect, the
    /// physically based model lights a figure and its floor as one place.
    /// `BattleSceneController` hands it to `scene.lightingEnvironment` at
    /// `environmentIntensity`.
    static let environmentIntensity: CGFloat = 0.7

    static func environmentMap(from painting: UIImage, palette: PaintingPalette) -> UIImage? {
        let coarseSize = CGSize(width: 32, height: 16)
        let fineSize = CGSize(width: 256, height: 128)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let coarse = UIGraphicsImageRenderer(size: coarseSize, format: format).image { context in
            let cg = context.cgContext
            // Sky at the top, blending to the horizon by the band's edge.
            let skyBand = CGRect(x: 0, y: 0, width: coarseSize.width, height: 5)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [palette.sky.cgColor, palette.horizon.cgColor] as CFArray,
                                         locations: [0, 1]) {
                cg.saveGState()
                cg.clip(to: skyBand)
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 5), options: [])
                cg.restoreGState()
            } else {
                cg.setFillColor(palette.sky.cgColor)
                cg.fill(skyBand)
            }
            // Ground below the band.
            cg.setFillColor(palette.ground.cgColor)
            cg.fill(CGRect(x: 0, y: 11, width: coarseSize.width, height: 5))
            // The painting twice across the horizon band, the second mirrored.
            let band = CGRect(x: 0, y: 5, width: 16, height: 6)
            painting.draw(in: band)
            cg.saveGState()
            cg.translateBy(x: 32, y: 0)
            cg.scaleBy(x: -1, y: 1)
            painting.draw(in: band)
            cg.restoreGState()
        }
        return UIGraphicsImageRenderer(size: fineSize, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            coarse.draw(in: CGRect(origin: .zero, size: fineSize))
        }
    }

    /// The camera's grade for a place: the genre's sets are each ONE hue,
    /// pushed — warm stone in the sun, cold blue in the ice, a violet dark
    /// in the deep. Saturation and contrast on the camera, an exposure
    /// nudge, and how far the corners fall off.
    ///
    /// EASED (2026-09-20). `SCNCamera.contrast` is an ADDITION to the
    /// default of 0 — the reveal's camera grades at 0.16 — and these sat
    /// at 1.03–1.12 from 2026-09-15, a doubling of the contrast on every
    /// battle set, which crushed the floor's shade and pushed every colour
    /// on it; the saturation pushes of 1.04–1.08 came on top. The Duat's
    /// battle frame measured a mean saturation of 202 of 255 against 115
    /// on the reveal. Contrast is on the reveal's scale now (0.06–0.14)
    /// and saturation at or under 1.0: a set keeps its one hue from its
    /// painting and its lights, not from the grade.
    struct Grade {
        var saturation: CGFloat
        var contrast: CGFloat
        var exposure: CGFloat
        var vignette: CGFloat
    }

    static func grade(for environment: BattleEnvironment) -> Grade {
        switch environment {
        // The warm sets began at 1.12 and 1.15: with the braziers' orange
        // light on a mottled sandstone floor the first frames were a sheet
        // of orange, so the push is gentler there.
        case .duatGate, .hallOfTwoTruths, .arenaOfSouls, .colosseumSands:
            return Grade(saturation: 1.0, contrast: 0.10, exposure: 0.0, vignette: 0.32)
        case .reedFields, .peachGarden:
            return Grade(saturation: 1.0, contrast: 0.06, exposure: 0.05, vignette: 0.26)
        case .serpentDeep, .necropolis:
            return Grade(saturation: 0.98, contrast: 0.14, exposure: -0.1, vignette: 0.42)
        case .colossusVault:
            return Grade(saturation: 0.98, contrast: 0.12, exposure: -0.05, vignette: 0.4)
        case .olympusGate, .aegeanCliffs:
            return Grade(saturation: 0.98, contrast: 0.08, exposure: 0.05, vignette: 0.24)
        case .lernaMarsh, .hydraLair, .yggdrasilRoots:
            return Grade(saturation: 0.94, contrast: 0.12, exposure: -0.05, vignette: 0.38)
        case .midgardFjord:
            // A night fjord under a grey sky: lifted a little, or the floor
            // is only what the braziers reach.
            return Grade(saturation: 0.96, contrast: 0.10, exposure: 0.08, vignette: 0.32)
        case .jotunheimHall, .dragonGate:
            return Grade(saturation: 0.96, contrast: 0.10, exposure: 0.0, vignette: 0.32)
        case .forumRome:
            return Grade(saturation: 0.92, contrast: 0.12, exposure: -0.08, vignette: 0.4)
        }
    }

    /// The air of each realm: the genre's stages are never still — leaves
    /// fall in its forests, embers rise in its ruins, snow drifts across its
    /// passes. One system over the field per place, on the sprites the
    /// effects already ship (`VFXLibrary.weather`); the dust motes stay
    /// underneath.
    static func weather(for environment: BattleEnvironment) -> (kind: VFXLibrary.Weather, tint: UIColor)? {
        func colour(_ hex: String) -> UIColor { UIColor(hex: hex) ?? .white }
        switch environment {
        case .duatGate, .arenaOfSouls, .colosseumSands, .colossusVault, .hallOfTwoTruths:
            return (.embers, colour("#FFB050"))
        case .lernaMarsh:
            return (.leaves, colour("#B8C8A0"))
        case .yggdrasilRoots:
            return (.leaves, colour("#E0B060"))
        case .reedFields:
            return (.leaves, colour("#E8E0B8"))
        case .midgardFjord, .jotunheimHall:
            return (.snow, colour("#F0F6FF"))
        case .peachGarden:
            return (.petals, colour("#FFB8C8"))
        case .serpentDeep, .necropolis:
            return (.wisps, colour("#B08CFF"))
        case .hydraLair:
            return (.wisps, colour("#90E0A0"))
        case .dragonGate:
            return (.wisps, colour("#70D0FF"))
        case .forumRome:
            return (.motes, colour("#C8D0FF"))
        case .olympusGate:
            return (.motes, colour("#FFE8B0"))
        case .aegeanCliffs:
            return (.motes, colour("#FFFFFF"))
        }
    }

    /// Where a set piece may stand beside the rows: anything in the rows'
    /// band (z above −6, between 4.5 and 8 m out) goes to 8.5 m out on its
    /// own side, the edge of the frame. A five-a-side's outermost mark is
    /// at ±5.4 (`BattleSceneController.position(for:teamSize:)`); the back
    /// row of every set is deeper than the enemy row and the centre pieces
    /// are inside 4.5 m.
    static func clearOfTheWings(_ position: SCNVector3) -> SCNVector3 {
        let out = abs(position.x)
        guard position.z > -6.0, out > 4.5, out < 8.0 else { return position }
        return SCNVector3(position.x < 0 ? -8.5 : 8.5, position.y, position.z)
    }

    /// The battle ground: a square slab this wide, its far face at
    /// `battleFloorFarEdge`. 44 m puts the side faces well outside a frame
    /// that is 13 m across at the figures, and the near face behind the
    /// camera. The far edge is where the old disc's far rim was, so the boss
    /// mark (0, −9.8) is still a stride beyond it and the breach still reads
    /// as a cliff it has climbed to.
    static let battleFloorSize: CGFloat = 44
    static let battleFloorFarEdge: Float = -8.4

    /// The ground as a slab: the painted floor on top, cliff rock on the
    /// faces, a row of boulders along the far edge. Square, so the tiles
    /// repeat the same in both directions whatever way the box's top face
    /// runs its texture coordinates.
    static func slab(size: CGFloat, thickness: CGFloat, farEdge: Float, floor: String, repeats: Float,
                     tint: String?, rock: String) -> SCNNode {
        let node = SCNNode()
        node.name = "platform"
        let body = SCNBox(width: size, height: thickness, length: size, chamferRadius: 0)
        // The tint as clouds of shade (`mottle`), 1.6 repeats across the
        // slab, so fourteen identical tiles each way stop reading as
        // wallpaper.
        let top = floorMaterial(floor, repeats: repeats, tint: tint, mottleRepeats: 1.6)
        let side = rockMaterial(rock, repeats: SCNVector3(Float(size) * 0.35, 1, 1))
        // SCNBox: front (+z), right (+x), back (−z), left (−x), top, bottom.
        body.materials = [side, side, side, side, top, rockMaterial(rock, repeats: SCNVector3(4, 4, 1))]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.name = "platform_floor"
        bodyNode.position = SCNVector3(0, -Float(thickness) / 2, farEdge + Float(size) / 2)
        node.addChildNode(bodyNode)

        // A low parapet along the far edge, so the ground ends at a wall the
        // way an arena does rather than at a cliff: the owner read the bare
        // edge, with the painting hung beyond it, as the floor tilting away.
        // The boss's breach breaks through it in the middle.
        let parapet = SCNBox(width: size, height: 0.9, length: 0.7, chamferRadius: 0.06)
        parapet.materials = [rockMaterial(rock, repeats: SCNVector3(Float(size) * 0.5, 1, 1))]
        let parapetNode = SCNNode(geometry: parapet)
        parapetNode.position = SCNVector3(0, 0.45, farEdge - 0.35)
        node.addChildNode(parapetNode)

        // Boulders along it break its line. None across the middle six
        // metres, where the boss's breach puts its own.
        var rng = SeededRandom(seed: UInt64(size * 100) &+ 0x5EED)
        let count = Int(size / 3.2)
        for index in 0..<count {
            let x = -Float(size) / 2 + (Float(index) + 0.5) * Float(size) / Float(count) + Float(rng.unit() - 0.5) * 1.2
            if abs(x) < 3 { continue }
            let boulderSize = CGFloat(0.5 + rng.unit() * 0.9) * thickness * 0.55
            let boulder = SCNSphere(radius: boulderSize)
            boulder.segmentCount = 10
            boulder.firstMaterial = rockMaterial(rock, repeats: SCNVector3(2, 1, 1))
            let boulderNode = SCNNode(geometry: boulder)
            boulderNode.position = SCNVector3(x, -Float(boulderSize) * 0.55 - Float(rng.unit()) * 0.3,
                                              farEdge - Float(rng.unit()) * 0.8 + 0.3)
            boulderNode.scale = SCNVector3(1 + Float(rng.unit()) * 0.6, 0.7 + Float(rng.unit()) * 0.4, 1 + Float(rng.unit()) * 0.5)
            boulderNode.eulerAngles = SCNVector3(Float(rng.unit()), Float(rng.unit()) * 6, Float(rng.unit()))
            node.addChildNode(boulderNode)
        }
        return node
    }

    // MARK: - Parts

    /// The stone the set stands on: a painted floor on top, a cliff face round
    /// the side, boulders at the rim.
    static func platform(radius: CGFloat, thickness: CGFloat, floor: String, repeats: Float,
                         tint: String?, rock: String, centre: SCNVector3, floorYaw: Float = 0) -> SCNNode {
        let node = SCNNode()
        node.name = "platform"
        let body = SCNCylinder(radius: radius, height: thickness)
        body.radialSegmentCount = 64
        let top = floorMaterial(floor, repeats: repeats, tint: tint)
        body.materials = [
            rockMaterial(rock, repeats: SCNVector3(Float(radius) * 0.7, 1, 1)),
            top,
            rockMaterial(rock, repeats: SCNVector3(2, 2, 1)),
        ]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.name = "platform_floor"
        bodyNode.position = SCNVector3(centre.x, centre.y - Float(thickness) / 2, centre.z)
        bodyNode.eulerAngles.y = floorYaw
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

    /// The rim broken open where a boss climbed through. A knot of boulders
    /// under its mark with their tops a hand above the platform — the cliff
    /// the owner described, and what hides the body a boss keeps below the
    /// rim (the camera, ten metres up, otherwise looked over the edge and
    /// saw the sunk half hanging in the air) — then a dark rent in the floor
    /// in front of it, and the floor's own tiles thrown round the rent,
    /// tipped and turned. The owner: "fix the battle map to look more like
    /// its been broken and opened where the boss is."
    static func breach(rock: String, floor: String, floorRepeats: Float, floorTint: String?,
                       at mark: SCNVector3) -> SCNNode {
        let node = SCNNode()
        node.name = "breach"
        let boulders: [(offset: SCNVector3, size: CGFloat, scale: SCNVector3)] = [
            (SCNVector3(0.0, -1.2, 0.9), 2.6, SCNVector3(1.5, 0.6, 1.1)),
            (SCNVector3(-2.1, -1.9, 0.3), 1.9, SCNVector3(1.3, 0.7, 1.2)),
            (SCNVector3(2.0, -2.1, -0.2), 1.7, SCNVector3(1.4, 0.6, 1.0)),
        ]
        for boulder in boulders {
            let geometry = SCNSphere(radius: boulder.size)
            geometry.segmentCount = 9
            geometry.firstMaterial = rockMaterial(rock, repeats: SCNVector3(3, 2, 1))
            let chunk = SCNNode(geometry: geometry)
            chunk.position = SCNVector3(mark.x + boulder.offset.x, boulder.offset.y, mark.z + boulder.offset.z)
            chunk.scale = boulder.scale
            chunk.eulerAngles = SCNVector3(0.2, Float(boulder.size), 0.1)
            node.addChildNode(chunk)
        }

        // The rent: a dark disc of the rock a hair above the floor, its far
        // half over the rim, so the platform reads as torn open at the edge.
        let rent = SCNCylinder(radius: 2.6, height: 0.06)
        rent.firstMaterial = rockMaterial(rock, repeats: SCNVector3(2, 2, 1))
        rent.firstMaterial?.multiply.contents = UIColor(white: 0.22, alpha: 1)
        let rentNode = SCNNode(geometry: rent)
        rentNode.position = SCNVector3(mark.x, 0.03, mark.z + 2.6)
        rentNode.scale = SCNVector3(1.35, 1, 0.75)
        node.addChildNode(rentNode)

        // The tiles thrown out of it, on the platform's own floor texture.
        var rng = SeededRandom(seed: 0xB0551)
        for index in 0..<10 {
            let angle = Float(index) / 10 * .pi * 2 + Float(rng.unit()) * 0.4
            let radius = 2.2 + Float(rng.unit()) * 1.3
            let tile = SCNBox(width: 0.55, height: 0.14, length: 0.55, chamferRadius: 0.02)
            tile.firstMaterial = floorMaterial(floor, repeats: max(0.2, floorRepeats * 0.08), tint: floorTint)
            let chunk = SCNNode(geometry: tile)
            chunk.position = SCNVector3(
                mark.x + sin(angle) * radius,
                0.05 + Float(rng.unit()) * 0.14,
                mark.z + 2.9 + cos(angle) * radius * 0.55
            )
            chunk.eulerAngles = SCNVector3(
                Float(rng.unit()) * 0.7 - 0.35,
                Float(rng.unit()) * 6.28,
                Float(rng.unit()) * 0.7 - 0.35
            )
            node.addChildNode(chunk)
        }
        return node
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
        // Through the loader's importer lock: a prop parsed on the main thread
        // while a warm pass parsed a figure on another came out wrong once
        // (the Hall of Ka's frozen idle, 2026-09-17).
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: ModelLibrary.modelDirectory)
                ?? Bundle.main.url(forResource: name, withExtension: "usdz"),
              let scene = try? ModelLibrary.parseScene(at: url, options: [.createNormalsIfAbsent: true]) else {
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
        let runes = UIImage(named: "rune_ring")
        material.lightingModel = .constant
        material.diffuse.contents = runes ?? tint
        material.multiply.contents = tint.mixed(with: .white, amount: 0.35)
        material.emission.contents = runes
        material.blendMode = .add
        // rune_ring.png is a 1024 px RGB painting with no alpha channel, so every
        // fragment of this square quad carries alpha 1 — including the black
        // corners outside the ring. Additive blending hides that in colour, but
        // not in alpha, so this 3.9 x 3.9 m square would print its own rectangle
        // over anything transparent behind it, exactly as the mist planes did in
        // the summon reveal (see mistPlanes below). It never showed only because
        // the ring lies flat on an opaque dais, which is how that bug stayed
        // hidden for a whole build. An additive quad adds light and has no
        // business changing what is behind it, so it writes colour and no alpha
        // at all; every additive material in this file should carry this line.
        //
        // Deriving the alpha from the painting instead is a trap worth naming,
        // because it looks like the obvious fix: `transparencyMode = .rgbZero`
        // takes transparency from luminance with 0.0 OPAQUE (Apple's wording),
        // so on art painted bright-on-black it is exactly inverted — it would
        // hold the black corners solid and dissolve the rune strokes, which are
        // the only thing this quad exists to draw.
        material.colorBufferWriteMask = [.red, .green, .blue]
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
            // mist.png is a 1024 px RGB painting with no alpha channel, so every
            // fragment of this quad carries alpha 1 even where the painting is
            // black. Additive blending hides that in colour — adding zero changes
            // nothing — but SceneKit still wrote the node's opacity into the
            // frame buffer's alpha across the whole 7 x 3.2 m rectangle, corners
            // included. Behind the battle stage's opaque black view and its
            // farBackdrop painting that alpha never composites against anything.
            // The summon reveal is the one place it does: that view is clear on
            // purpose so the SwiftUI rays and glow show between the pillars, so
            // these corners laid a black rectangle over the backdrop with
            // dead-straight edges — the translucent pane hanging behind Shabti's
            // head in the playtest. Measured off that frame, the step across the
            // edge is (38.9, 48.9, 82.3) -> (32.2, 41.0, 68.1): a ratio of
            // 0.828/0.839/0.827, i.e. a pure multiply by 1 - 0.172, which is the
            // top of the opacity range rolled below — the frame buffer's alpha
            // composited source-over by UIKit, and not a colour add at all.
            //
            // So the cure is to write no alpha: this quad adds light and must
            // leave what is behind it exactly as it found it. A real transparency
            // map would be the other half of the answer if the art carried one,
            // but do not reach for `transparencyMode = .rgbZero` to fake one out
            // of the painting: that mode reads transparency from luminance with
            // 0.0 OPAQUE, so on puffs painted bright on black it is inverted —
            // it would hold the corners solid and dissolve the mist itself.
            material.colorBufferWriteMask = [.red, .green, .blue]
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            material.isDoubleSided = true
            plane.firstMaterial = material
            let node = SCNNode(geometry: plane)
            // Left at the value the haze was tuned to. Masking the alpha write
            // above changes nothing about the light this quad adds — node
            // opacity still scales the premultiplied colour — so there is no
            // luminance loss here to compensate for, and raising it would only
            // push the reveal further towards the blown-out upper left the
            // playtest already complained about.
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
    ///
    /// `yaw` is the battle camera's (`CameraDirector.homeYaw`): the painting
    /// is hung 70 m out along the camera's own line of sight and turned to
    /// face it, so it fills the frame whichever way the camera looks. Hung
    /// square to the world, as it was, a camera 55° round to the side saw
    /// its edge a third of the way across the frame and the bare sky colour
    /// beyond.
    static func farBackdrop(_ image: UIImage, yaw: Float = 0) -> SCNNode {
        let plane = SCNPlane(width: 170, height: 170)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = false
        plane.firstMaterial = material
        let node = SCNNode(geometry: plane)
        // Centred well below the platform, so the painting's horizon sits a
        // little under the platform's far edge on screen: sky above the edge,
        // the painted land far below it. The camera's horizontal forward is
        // (sin yaw, −cos yaw); a plane faces +Z, so turning it by −yaw points
        // it back up that line.
        node.position = SCNVector3(sin(yaw) * 70, -16, -cos(yaw) * 70)
        node.eulerAngles.y = -yaw
        node.name = "backdrop"
        return node
    }

    // MARK: - Materials

    /// How polished each floor is: marble takes a sheen the key light draws
    /// across it, slate a little, sandstone almost none, moss none at all.
    /// Marble was 0.52 and threw the key straight back as a sheet of white
    /// across the whole floor (2026-09-15); the relief map does the reading
    /// now and the sheen is a hint.
    private static let floorRoughness: [String: CGFloat] = [
        "floor_marble": 0.62, "floor_slate": 0.72, "floor_sandstone": 0.86, "floor_moss": 0.95,
    ]

    /// `mottleRepeats`: the slab's macro variation (`mottle`) in place of a
    /// flat tint, repeated that many times across the surface; nil keeps the
    /// flat tint, which is what the dais, a stand-in column and a thrown
    /// tile want.
    static func floorMaterial(_ texture: String, repeats: Float, tint: String?, mottleRepeats: Float? = nil) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIImage(named: texture) ?? UIColor(hex: "#B08A5A")
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(repeats, repeats, 1)
        material.diffuse.mipFilter = .linear
        material.roughness.contents = floorRoughness[texture] ?? 0.8
        material.metalness.contents = 0.0
        applyRelief(texture, to: material, repeats: SCNVector3(repeats, repeats, 1))
        if let tint, let colour = UIColor(hex: tint) {
            if let mottleRepeats {
                material.multiply.contents = mottle(tint: colour)
                material.multiply.wrapS = .repeat
                material.multiply.wrapT = .repeat
                material.multiply.contentsTransform = SCNMatrix4MakeScale(mottleRepeats, mottleRepeats, 1)
            } else {
                material.multiply.contents = colour
            }
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
        material.diffuse.mipFilter = .linear
        material.roughness.contents = 0.9
        material.metalness.contents = 0.0
        applyRelief(texture, to: material, repeats: repeats)
        return material
    }

    /// RELIEF (2026-09-15). Summoners War's floors are carved patterns with
    /// bevelled edges, and what makes them read is the light catching the
    /// edge of every tile; ours were paintings with the shading baked flat,
    /// so the key light slid over them as over a photograph. Each tile now
    /// ships with a normal map derived from its own painting by
    /// `tools/floor_relief.py` (`<texture>_n.png`: the grout low, the stone
    /// high, the cracks cut in), aligned with the diffuse by the same
    /// repeat, so the 36° key light bevels every grout line and every
    /// crack. A tile without a map (a stand-in colour) shades flat as
    /// before.
    private static func applyRelief(_ texture: String, to material: SCNMaterial, repeats: SCNVector3) {
        guard let relief = UIImage(named: "\(texture)_n") else { return }
        material.normal.contents = relief
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.contentsTransform = SCNMatrix4MakeScale(repeats.x, repeats.y, 1)
        material.normal.mipFilter = .linear
        material.normal.intensity = 0.9
    }

    private static var mottleCache: [String: UIImage] = [:]

    /// The slab's macro variation: the floor's tint with soft lighter and
    /// darker clouds through it, drawn wrapped so it tiles, multiplied over
    /// the tiles at about 1.6 repeats across the 44 m slab so the clouds
    /// are eight to twenty metres wide. Fourteen identical tiles each way
    /// read as wallpaper; the same tiles under clouds of shade read as a
    /// floor that has been walked on.
    static func mottle(tint: UIColor) -> UIImage {
        let key = tint.description
        if let cached = mottleCache[key] { return cached }
        let size: CGFloat = 256
        var rng = SeededRandom(seed: 0x5EED7)
        let space = CGColorSpaceCreateDeviceRGB()
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let cg = context.cgContext
            tint.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<9 {
                let cloud: UIColor = rng.unit() < 0.5 ? .white : .black
                let alpha = CGFloat(0.06 + rng.unit() * 0.08)
                let colors = [cloud.withAlphaComponent(alpha).cgColor, cloud.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { continue }
                let radius = CGFloat(50 + rng.unit() * 80)
                let centre = CGPoint(x: CGFloat(rng.unit()) * size, y: CGFloat(rng.unit()) * size)
                // Nine copies, so a cloud that crosses the edge continues
                // on the other side and the tile has no seam.
                for dx in [-size, 0, size] {
                    for dy in [-size, 0, size] {
                        let at = CGPoint(x: centre.x + dx, y: centre.y + dy)
                        cg.drawRadialGradient(gradient, startCenter: at, startRadius: 0, endCenter: at, endRadius: radius, options: [])
                    }
                }
            }
        }
        mottleCache[key] = image
        return image
    }
}
