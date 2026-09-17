import XCTest
@testable import Pantheon

/// The island's data and the rules of decorating it (2026-09-17): the
/// landmarks and their footprints lie on the painting, the catalogue and the
/// slots are well formed, buying and placing follow the rules, and the two
/// save fields survive a round trip and a save written before they existed.
final class IslandTests: XCTestCase {

    func testLandmarksAndFootprintsLieOnThePainting() {
        let ids = IslandDatabase.landmarks.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "landmark ids must be unique")
        for landmark in IslandDatabase.landmarks {
            XCTAssert((0.0...1.0).contains(landmark.anchor.x) && (0.0...1.0).contains(landmark.anchor.y), landmark.id)
            let footprint = landmark.footprint
            XCTAssert((0.0...1.0).contains(footprint.centre.x) && (0.0...1.0).contains(footprint.centre.y), landmark.id)
            // A tap target smaller than 3% of the painting is not a building.
            XCTAssertGreaterThan(footprint.size.width, 0.03, landmark.id)
            XCTAssertGreaterThan(footprint.size.height, 0.03, landmark.id)
            // And one wider than a third of it would cover its neighbours.
            XCTAssertLessThan(footprint.size.width, 0.34, landmark.id)
        }
    }

    func testTheCatalogueAndTheSlotsAreWellFormed() {
        let pieces = IslandDatabase.decorations
        XCTAssertEqual(Set(pieces.map(\.id)).count, pieces.count, "decoration ids must be unique")
        for piece in pieces {
            XCTAssertGreaterThan(piece.price, 0, piece.id)
            XCTAssertGreaterThanOrEqual(piece.unlockLevel, 1, piece.id)
            XCTAssert(piece.asset.hasPrefix("prop_"), "\(piece.id) must be a shipped prop")
            // Between a knee-high bowl and the obelisk: the figures are 0.11.
            XCTAssert((0.05...0.25).contains(piece.height), piece.id)
        }
        // The cheapest piece is affordable on the first day; the dearest is a
        // purchase, so decorating has a ladder to climb.
        let prices = pieces.map(\.price).sorted()
        XCTAssertLessThanOrEqual(prices.first ?? 0, 5_000)
        XCTAssertGreaterThanOrEqual(prices.last ?? 0, 50_000)

        let slots = IslandDatabase.decorSlots
        XCTAssertEqual(Set(slots.map(\.id)).count, slots.count, "slot ids must be unique")
        XCTAssertGreaterThanOrEqual(slots.count, 6)
        for slot in slots {
            XCTAssert((0.05...0.95).contains(slot.point.x) && (0.2...0.8).contains(slot.point.y), slot.id)
            // Not where the team stands.
            for stand in IslandView.stands {
                XCTAssertGreaterThan(hypot(stand.x - slot.point.x, stand.y - slot.point.y), 0.04,
                                     "\(slot.id) stands on a figure's mark")
            }
        }
    }

    func testBuyingPlacingAndMovingADecoration() throws {
        var player = NewGame.create().player
        player.wallet.drachma = 10_000
        let brazier = try XCTUnwrap(IslandDatabase.decoration("brazier"))
        XCTAssertEqual(brazier.unlockLevel, 1, "the brazier is the day-one piece")

        try IslandDecorService.buy("brazier", player: &player)
        XCTAssertEqual(player.wallet.drachma, 10_000 - brazier.price)
        XCTAssertTrue(IslandDecorService.owns("brazier", player: player))
        XCTAssertThrowsError(try IslandDecorService.buy("brazier", player: &player)) { error in
            XCTAssertEqual(error as? IslandDecorService.DecorError, .alreadyOwned)
        }
        // A piece never bought cannot be placed.
        XCTAssertThrowsError(try IslandDecorService.place("sphinx", in: "west", player: &player)) { error in
            XCTAssertEqual(error as? IslandDecorService.DecorError, .notOwned)
        }
        XCTAssertThrowsError(try IslandDecorService.place("brazier", in: "nowhere", player: &player)) { error in
            XCTAssertEqual(error as? IslandDecorService.DecorError, .unknownSlot)
        }

        try IslandDecorService.place("brazier", in: "west", player: &player)
        XCTAssertEqual(player.islandDecor?["west"], "brazier")
        XCTAssertEqual(IslandDecorService.placements(for: player).map(\.slot.id), ["west"])

        // Placing it again elsewhere MOVES it: one brazier, one place.
        try IslandDecorService.place("brazier", in: "east", player: &player)
        XCTAssertNil(player.islandDecor?["west"])
        XCTAssertEqual(player.islandDecor?["east"], "brazier")

        IslandDecorService.clear(slot: "east", player: &player)
        XCTAssertNil(player.islandDecor?["east"])
        XCTAssertTrue(IslandDecorService.owns("brazier", player: player), "clearing a slot never sells the piece")
    }

    func testAPoorOrNewSummonerCannotBuy() throws {
        var player = NewGame.create().player
        player.wallet.drachma = 0
        XCTAssertThrowsError(try IslandDecorService.buy("brazier", player: &player)) { error in
            XCTAssertEqual(error as? IslandDecorService.DecorError, .notEnoughDrachma(needed: 4_000))
        }
        player.wallet.drachma = 1_000_000
        let colossus = try XCTUnwrap(IslandDatabase.decoration("anubis_colossus"))
        XCTAssertGreaterThan(colossus.unlockLevel, player.level, "the colossus waits for a veteran")
        XCTAssertThrowsError(try IslandDecorService.buy("anubis_colossus", player: &player)) { error in
            XCTAssertEqual(error as? IslandDecorService.DecorError, .locked(level: colossus.unlockLevel))
        }
        XCTAssertEqual(player.wallet.drachma, 1_000_000, "a refused purchase costs nothing")
    }

    func testDecorFieldsRoundTripAndTolerateAbsence() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var save = NewGame.create()
        save.player.decorationsOwned = ["brazier", "sphinx"]
        save.player.islandDecor = ["west": "brazier"]
        let restored = try decoder.decode(SaveGame.self, from: try encoder.encode(save))
        XCTAssertEqual(restored.player.decorationsOwned, ["brazier", "sphinx"])
        XCTAssertEqual(restored.player.islandDecor?["west"], "brazier")

        // A save from before the island could be decorated has neither key.
        let bare = NewGame.create()
        let json = String(data: try encoder.encode(bare), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"islandDecor\""), "an undecorated island writes no key")
        let old = try decoder.decode(SaveGame.self, from: try encoder.encode(bare))
        XCTAssertNil(old.player.decorationsOwned)
        XCTAssertNil(old.player.islandDecor)
        XCTAssertTrue(IslandDecorService.placements(for: old.player).isEmpty)
    }
}
