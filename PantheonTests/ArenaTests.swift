import XCTest
@testable import Pantheon

/// PvP scoring and matchmaking.
final class ArenaTests: XCTestCase {

    func testTierBoundaries() {
        XCTAssertEqual(ArenaTier.tier(forPoints: 0), .initiate)
        XCTAssertEqual(ArenaTier.tier(forPoints: 1_199), .initiate)
        XCTAssertEqual(ArenaTier.tier(forPoints: 1_200), .acolyte)
        XCTAssertEqual(ArenaTier.tier(forPoints: 99_999), .olympian)
    }

    func testBeatingAStrongerOpponentIsWorthMore() {
        let easy = ArenaService.pointsForWin(playerPoints: 2_000, opponentPoints: 1_500)
        let hard = ArenaService.pointsForWin(playerPoints: 2_000, opponentPoints: 2_500)
        XCTAssertGreaterThan(hard, easy)
    }

    func testLosingToAWeakerOpponentCostsMore() {
        let expected = ArenaService.pointsForLoss(playerPoints: 2_000, opponentPoints: 1_400)
        let upset = ArenaService.pointsForLoss(playerPoints: 2_000, opponentPoints: 2_600)
        XCTAssertGreaterThan(expected, upset)
    }

    func testPointsNeverFallBelowTheTierFloor() {
        var player = Player()
        player.arena.points = ArenaTier.champion.threshold
        let opponent = ArenaService.pool(for: player.arena, day: 1).first!

        let loss = BattleResult(
            outcome: .defeat, turnsTaken: 10, survivorFraction: 0,
            totalDamageDealt: 0, totalDamageTaken: 0, seed: 1
        )
        for _ in 0..<20 {
            _ = ArenaService.applyResult(loss, against: opponent, player: &player)
        }
        XCTAssertGreaterThanOrEqual(player.arena.points, ArenaTier.champion.threshold)
    }

    func testOpponentPoolIsDeterministicForADay() {
        let record = ArenaRecord()
        let first = ArenaService.pool(for: record, day: 100).map(\.id)
        let second = ArenaService.pool(for: record, day: 100).map(\.id)
        XCTAssertEqual(first, second)

        let otherDay = ArenaService.pool(for: record, day: 101).map(\.id)
        XCTAssertNotEqual(first, otherDay)
    }

    func testOpponentTeamsAreFullyGeared() {
        let record = ArenaRecord()
        for opponent in ArenaService.pool(for: record, day: 5) {
            XCTAssertEqual(opponent.team.count, ArenaService.teamSize)
            XCTAssertGreaterThan(opponent.power, 0)
            for unit in opponent.team {
                XCTAssertEqual(unit.relics.count, 6, "\(unit.name) should have a full relic loadout")
            }
        }
    }

    func testAttackConsumesAnAttemptAndFailsWhenExhausted() {
        var player = NewGame.create().player
        player.arena.attacksRemaining = 1
        let opponent = ArenaService.pool(for: player.arena, day: 3).first!

        XCTAssertNoThrow(try ArenaService.startAttack(against: opponent, player: &player, seed: 1))
        XCTAssertEqual(player.arena.attacksRemaining, 0)
        XCTAssertThrowsError(try ArenaService.startAttack(against: opponent, player: &player, seed: 2))
    }
}
