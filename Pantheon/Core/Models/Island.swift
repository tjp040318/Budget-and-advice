import Foundation

/// Where a landmark on the island leads.
enum IslandDestination: String, CaseIterable, Sendable {
    case campaign
    case arena
    case summon
    case collection
    case settings
    /// The Hall of Ka: power-up, evolution and awakening (`TrainingView`).
    case training
    /// The Labyrinth: the relic dungeons and the Halls of Essence (`LabyrinthView`).
    case labyrinth
}

/// A tappable place on the island.
///
/// The island is a painting with hotspots, not a scene: `anchor` is the centre
/// of the landmark's footprint in `island_bg.png`, normalised to 0...1 in both
/// axes, so the same data works at any screen size once the painting's
/// on-screen frame is known (`IslandView.fill`). The positions are mirrored in
/// `tools/island.py`, which paints a stone footprint under each one; move them
/// together.
struct Landmark: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var destination: IslandDestination
    var anchor: CGPoint
    /// Player level at which the landmark opens.
    var unlockLevel: Int
    /// Player levels at which the building takes its next look. Tier I is the
    /// starting state; each threshold passed adds one.
    var upgradeLevels: [Int]
    var accentHex: String
    /// Where the painted building actually is — its tap target and the light
    /// under it since 2026-09-17, when the building itself became the button
    /// the way Summoners War's are. Measured off the painting, in fractions
    /// of it, like `anchor`.
    var footprint: Footprint

    func isUnlocked(atLevel level: Int) -> Bool { level >= unlockLevel }

    func tier(atLevel level: Int) -> Int { 1 + upgradeLevels.filter { level >= $0 }.count }
}

/// A painted building's extent: centre and size as fractions of the painting.
struct Footprint: Equatable, Sendable {
    var centre: CGPoint
    var size: CGSize
}

/// A piece the player can stand on the sand: a prop already in the bundle,
/// bought with drachma and kept for good, placed in one of the island's
/// `DecorSlot`s and moved between them for nothing. Summoners War's island
/// decorations, in the game's own stone (`Docs/PLAN.md`, *The home island as
/// Summoners War's*).
struct IslandDecoration: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var blurb: String
    /// The shipped prop, `prop_<name>`.
    var asset: String
    /// The piece's height as a fraction of the screen's; the figures stand
    /// at 0.11 (`IslandSceneView.figureHeight`).
    var height: CGFloat
    /// Drachma.
    var price: Int
    var unlockLevel: Int
    /// A brazier: it carries a flame and a light.
    var burns: Bool = false
    var flameHex: String = "#FFA040"
    /// The catalogue's glyph beside the render.
    var glyph: String = "building.columns.fill"
    /// The rendered thumbnail in the bundle, `decor_<id>` (`tools/decor_thumbs.py`).
    var thumbnail: String { "decor_\(id)" }
}

/// A patch of open sand a decoration can stand on, measured off the painting.
struct DecorSlot: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var point: CGPoint
}

enum IslandDatabase {
    static let landmarks: [Landmark] = [
        Landmark(
            id: "circle",
            title: "Summoning Circle",
            subtitle: "Call a god out of the Duat",
            systemImage: "sparkles",
            destination: .summon,
            anchor: CGPoint(x: 0.44, y: 0.48),
            unlockLevel: 1,
            upgradeLevels: [8, 20],
            accentHex: "#7FE0FF",
            footprint: Footprint(centre: CGPoint(x: 0.445, y: 0.47), size: CGSize(width: 0.17, height: 0.19))
        ),
        Landmark(
            id: "gate",
            title: "Gate of the Duat",
            subtitle: "The campaign",
            systemImage: "map.fill",
            destination: .campaign,
            anchor: CGPoint(x: 0.26, y: 0.64),
            unlockLevel: 1,
            upgradeLevels: [10, 25],
            accentHex: "#F2A03C",
            footprint: Footprint(centre: CGPoint(x: 0.255, y: 0.63), size: CGSize(width: 0.18, height: 0.26))
        ),
        Landmark(
            id: "arena",
            title: "Arena of Souls",
            subtitle: "Other demigods' defences",
            systemImage: "trophy.fill",
            destination: .arena,
            anchor: CGPoint(x: 0.74, y: 0.63),
            unlockLevel: 1,
            upgradeLevels: [12, 30],
            accentHex: "#FF5B57",
            footprint: Footprint(centre: CGPoint(x: 0.745, y: 0.63), size: CGSize(width: 0.22, height: 0.24))
        ),
        Landmark(
            id: "labyrinth",
            title: "Labyrinth",
            subtitle: "Relic dungeons and the Halls of Essence",
            systemImage: "shield.lefthalf.filled",
            destination: .labyrinth,
            anchor: CGPoint(x: 0.62, y: 0.42),
            unlockLevel: 1,
            upgradeLevels: [10, 25],
            accentHex: "#C97BFF",
            footprint: Footprint(centre: CGPoint(x: 0.64, y: 0.42), size: CGSize(width: 0.14, height: 0.14))
        ),
        Landmark(
            id: "hall",
            title: "Hall of Ka",
            subtitle: "Power up, evolve, awaken",
            systemImage: "person.3.fill",
            destination: .training,
            anchor: CGPoint(x: 0.16, y: 0.36),
            unlockLevel: 1,
            upgradeLevels: [6, 15],
            accentHex: "#F5D57A",
            footprint: Footprint(centre: CGPoint(x: 0.16, y: 0.35), size: CGSize(width: 0.12, height: 0.14))
        ),
        Landmark(
            id: "obelisk",
            title: "Obelisk",
            subtitle: "Account, sound, assets",
            systemImage: "gearshape.fill",
            destination: .settings,
            anchor: CGPoint(x: 0.89, y: 0.47),
            unlockLevel: 1,
            upgradeLevels: [],
            accentHex: "#9E97C4",
            footprint: Footprint(centre: CGPoint(x: 0.885, y: 0.34), size: CGSize(width: 0.07, height: 0.28))
        )
    ]
}

extension IslandDatabase {
    /// The catalogue: every piece is a prop already in the bundle, so the
    /// feature costs nothing to ship; prices climb with the piece's presence
    /// on the sand, and the statues wait for a summoner who has been around.
    static let decorations: [IslandDecoration] = [
        IslandDecoration(id: "brazier", title: "Brazier", blurb: "A bronze bowl of fire that never goes out.",
                         asset: "prop_brazier", height: 0.075, price: 4_000, unlockLevel: 1,
                         burns: true, flameHex: "#FFA040", glyph: "flame.fill"),
        IslandDecoration(id: "tripod_brazier", title: "Tripod brazier", blurb: "The Greek bowl on three legs, with a paler flame.",
                         asset: "prop_tripod_brazier", height: 0.07, price: 5_000, unlockLevel: 1,
                         burns: true, flameHex: "#FFD070", glyph: "flame.fill"),
        IslandDecoration(id: "broken_column", title: "Broken column", blurb: "A fallen drum and a stump, as the arena's outskirts have them.",
                         asset: "prop_broken_column", height: 0.09, price: 6_000, unlockLevel: 1,
                         glyph: "building.columns"),
        IslandDecoration(id: "doric_column", title: "Doric column", blurb: "One whole column of Olympus, fluted and white.",
                         asset: "prop_doric_column", height: 0.16, price: 9_000, unlockLevel: 3,
                         glyph: "building.columns.fill"),
        IslandDecoration(id: "lotus_column", title: "Lotus column", blurb: "A papyrus-bud column of the Duat, painted in its bands.",
                         asset: "prop_lotus_column", height: 0.16, price: 10_000, unlockLevel: 3,
                         glyph: "building.columns.fill"),
        IslandDecoration(id: "sphinx", title: "Sphinx", blurb: "A crouching sphinx to watch the shore.",
                         asset: "prop_sphinx", height: 0.09, price: 12_000, unlockLevel: 5,
                         glyph: "pawprint.fill"),
        IslandDecoration(id: "temple_ruin", title: "Temple ruin", blurb: "A corner of a fallen sanctuary, its lintel still up.",
                         asset: "prop_temple_ruin", height: 0.15, price: 20_000, unlockLevel: 8,
                         glyph: "building.2.fill"),
        IslandDecoration(id: "world_tree_root", title: "World-tree root", blurb: "A root of Yggdrasil, broken through the sand from very far away.",
                         asset: "prop_world_tree_root", height: 0.12, price: 25_000, unlockLevel: 8,
                         glyph: "leaf.fill"),
        IslandDecoration(id: "obelisk", title: "Obelisk", blurb: "A second needle of the sun, half the height of the first.",
                         asset: "prop_obelisk", height: 0.22, price: 30_000, unlockLevel: 10,
                         glyph: "triangle.fill"),
        IslandDecoration(id: "zeus_statue", title: "Statue of the Thunderer", blurb: "The king of Olympus in marble, bolt raised.",
                         asset: "prop_zeus_statue", height: 0.16, price: 40_000, unlockLevel: 12,
                         glyph: "figure.stand"),
        IslandDecoration(id: "anubis_colossus", title: "Seated colossus", blurb: "The jackal enthroned, as tall as the hall's columns.",
                         asset: "prop_anubis_colossus", height: 0.18, price: 60_000, unlockLevel: 15,
                         glyph: "figure.seated.side"),
    ]

    /// Open sand, measured off the painting (`tools/mapgrid.py`-style, a
    /// grid drawn over it and every dot looked at): nothing painted stands
    /// on any of them and none is where the team stands (`IslandView.stands`).
    /// The first west and north dots sat on the palms by the circle.
    static let decorSlots: [DecorSlot] = [
        DecorSlot(id: "west", title: "West sand", point: CGPoint(x: 0.375, y: 0.545)),
        DecorSlot(id: "north", title: "North shore", point: CGPoint(x: 0.35, y: 0.335)),
        DecorSlot(id: "east", title: "East sand", point: CGPoint(x: 0.56, y: 0.56)),
        DecorSlot(id: "south", title: "South sand", point: CGPoint(x: 0.53, y: 0.64)),
        DecorSlot(id: "shore", title: "Eastern shore", point: CGPoint(x: 0.88, y: 0.58)),
        DecorSlot(id: "grove", title: "By the grove", point: CGPoint(x: 0.79, y: 0.44)),
    ]

    static func decoration(_ id: String) -> IslandDecoration? {
        decorations.first { $0.id == id }
    }

    static func slot(_ id: String) -> DecorSlot? {
        decorSlots.first { $0.id == id }
    }
}

/// The rules of buying and placing a decoration, on the save alone, so the
/// tests can run them without a store. `GameStore` wraps each with its own
/// error reporting.
enum IslandDecorService {
    enum DecorError: Error, LocalizedError, Equatable {
        case unknown
        case alreadyOwned
        case locked(level: Int)
        case notEnoughDrachma(needed: Int)
        case notOwned
        case unknownSlot

        var errorDescription: String? {
            switch self {
            case .unknown: return "No such decoration."
            case .alreadyOwned: return "You already own that piece."
            case .locked(let level): return "Reach demigod level \(level) first."
            case .notEnoughDrachma(let needed): return "Needs \(needed) drachma."
            case .notOwned: return "Buy the piece before placing it."
            case .unknownSlot: return "No such place on the island."
            }
        }
    }

    static func owns(_ id: String, player: Player) -> Bool {
        player.decorationsOwned?.contains(id) ?? false
    }

    /// Where everything stands: each occupied slot with its piece, in the
    /// slots' own order.
    static func placements(for player: Player) -> [(slot: DecorSlot, decoration: IslandDecoration)] {
        IslandDatabase.decorSlots.compactMap { slot in
            guard let id = player.islandDecor?[slot.id], let piece = IslandDatabase.decoration(id) else { return nil }
            return (slot, piece)
        }
    }

    /// Buys a piece for good. Owned once, never twice.
    static func buy(_ id: String, player: inout Player) throws {
        guard let piece = IslandDatabase.decoration(id) else { throw DecorError.unknown }
        guard !owns(id, player: player) else { throw DecorError.alreadyOwned }
        guard player.level >= piece.unlockLevel else { throw DecorError.locked(level: piece.unlockLevel) }
        guard player.wallet.drachma >= piece.price else { throw DecorError.notEnoughDrachma(needed: piece.price) }
        player.wallet.drachma -= piece.price
        var owned = player.decorationsOwned ?? []
        owned.append(id)
        player.decorationsOwned = owned
    }

    /// Stands an owned piece in a slot. A piece standing elsewhere moves;
    /// whatever stood in the slot goes back to storage.
    static func place(_ id: String, in slotID: String, player: inout Player) throws {
        guard IslandDatabase.decoration(id) != nil else { throw DecorError.unknown }
        guard IslandDatabase.slot(slotID) != nil else { throw DecorError.unknownSlot }
        guard owns(id, player: player) else { throw DecorError.notOwned }
        var decor = player.islandDecor ?? [:]
        for (slot, standing) in decor where standing == id { decor[slot] = nil }
        decor[slotID] = id
        player.islandDecor = decor
    }

    /// Empties a slot; the piece stays owned.
    static func clear(slot slotID: String, player: inout Player) {
        var decor = player.islandDecor ?? [:]
        decor[slotID] = nil
        player.islandDecor = decor
    }
}
