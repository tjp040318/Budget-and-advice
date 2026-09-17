import XCTest
@testable import Pantheon

/// The social layer on the offline backend (`LocalSocialBackend`), which is
/// the world CI and a device without iCloud run on, and the war's rules,
/// which both backends share (`WarRules`). Nothing here touches CloudKit.
final class SocialTests: XCTestCase {

    /// Thursday 2026-09-17, noon UTC: ISO week 38 of 2026, the fourth
    /// battle day of the week. Pinned so a run across midnight cannot move
    /// the week under the assertions.
    private static let noon = Date(timeIntervalSince1970: 1_789_646_400)

    private func makeBackend() -> LocalSocialBackend {
        LocalSocialBackend(seed: 7, persisting: false, now: { SocialTests.noon })
    }

    /// A fresh account, published so the backend knows the player's name
    /// and power.
    private func publish(_ backend: LocalSocialBackend) async throws -> SocialProfile {
        let player = NewGame.create().player
        let draft = SocialService.profile(from: player, id: "", guild: nil)
        return try await backend.publish(profile: draft)
    }

    private func rival(named name: String, in backend: LocalSocialBackend) async throws -> SocialProfile {
        let found = try await backend.search(name: name)
        return try XCTUnwrap(found.first(where: { $0.name == name }), "the seed has a rival called \(name)")
    }

    // MARK: - The clock

    func testWeekDayAndSeasonKeysAreISOInUTC() {
        let week = WarRules.weekKey(for: SocialTests.noon)
        let day = WarRules.dayKey(for: SocialTests.noon)
        let season = WarRules.seasonKey(for: SocialTests.noon)
        let battleDay = LocalSocialBackend.daysIntoWeek(SocialTests.noon)
        XCTAssertEqual(week, "2026-W38")
        XCTAssertEqual(day, "2026-09-17")
        XCTAssertEqual(season, "2026-09")
        XCTAssertEqual(battleDay, 4)
        // The week closes after the date, within seven days.
        let end = WarRules.weekEnd(for: SocialTests.noon)
        let left = end.timeIntervalSince(SocialTests.noon)
        let sevenDays: Double = 7 * 86_400
        XCTAssertGreaterThan(left, 0)
        XCTAssertLessThanOrEqual(left, sevenDays)
    }

    // MARK: - The profile

    func testProfileIsBuiltFromThePlayerAndItsDefence() throws {
        var player = NewGame.create().player
        player.displayName = "Testarion"
        player.arenaDefenseTeam.unitIDs = [player.units[0].id]
        let profile = SocialService.profile(from: player, id: "me", guild: nil)
        XCTAssertEqual(profile.name, "Testarion")
        XCTAssertEqual(profile.defence.count, 1)
        XCTAssertGreaterThan(profile.power, 0)
        let leader = try XCTUnwrap(profile.leader)
        XCTAssertEqual(leader.family, player.units[0].blueprintID)
        // The snapshot fights on this build with the stats it was taken with.
        let resolved = try XCTUnwrap(leader.resolved())
        XCTAssertEqual(resolved.stats, leader.stats)
        XCTAssertEqual(resolved.activeRelicSets.count, leader.sets.count)
    }

    func testSnapshotAndGrantsRoundTripThroughJSON() async throws {
        let backend = makeBackend()
        let kallias = try await rival(named: "Kallias", in: backend)
        XCTAssertEqual(kallias.defence.count, ArenaService.teamSize)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profileData = try encoder.encode(kallias)
        let restoredProfile = try decoder.decode(SocialProfile.self, from: profileData)
        XCTAssertEqual(restoredProfile.defence, kallias.defence)
        // Every unit of the defence fights on this build.
        let fightable = kallias.defence.compactMap { $0.resolved() }
        XCTAssertEqual(fightable.count, kallias.defence.count)

        let grants: [ShopService.Grant] = [
            .scrolls(.mystical, 3), .drachma(5_000), .relic(grade: 5), .essences("essence_ember_mid", 2),
            .bundle([.energyRefill, .unit("anubis_ember"), .boonCache(grade: 4), .stones("whetstone_hero", 1)]),
        ]
        let grantData = try encoder.encode(grants)
        let restoredGrants = try decoder.decode([ShopService.Grant].self, from: grantData)
        XCTAssertEqual(restoredGrants, grants)
    }

    // MARK: - Friends

    func testFriendRequestRoundTrip() async throws {
        let backend = makeBackend()
        _ = try await publish(backend)

        // Kallias accepts (an even hash), Sigrun declines (an odd one).
        let kallias = try await rival(named: "Kallias", in: backend)
        let sent = try await backend.sendFriendRequest(to: kallias.id)
        XCTAssertEqual(sent.status, .accepted)
        let friendsAfterKallias = try await backend.friends()
        XCTAssertTrue(friendsAfterKallias.contains { $0.friend.id == kallias.id })

        let sigrun = try await rival(named: "Sigrun", in: backend)
        let declined = try await backend.sendFriendRequest(to: sigrun.id)
        XCTAssertEqual(declined.status, .declined)
        let friendsAfterSigrun = try await backend.friends()
        XCTAssertFalse(friendsAfterSigrun.contains { $0.friend.id == sigrun.id })

        // A request already waiting on the player, accepted.
        let waiting = try await backend.friendRequests()
        let request = try XCTUnwrap(waiting.first)
        try await backend.respond(request: request, accept: true)
        let afterAccept = try await backend.friends()
        XCTAssertTrue(afterAccept.contains { $0.friend.id == request.fromID })
        let stillWaiting = try await backend.friendRequests()
        XCTAssertFalse(stillWaiting.contains { $0.id == request.id })

        // Asking a friend again is refused, not duplicated.
        do {
            _ = try await backend.sendFriendRequest(to: kallias.id)
            XCTFail("a second request to a friend must throw")
        } catch let error as SocialError {
            guard case .conflict = error else { return XCTFail("expected a conflict, got \(error)") }
        }
    }

    // MARK: - Mail

    func testMailIsClaimedExactlyOnce() async throws {
        let backend = makeBackend()
        let inbox = try await backend.mail()
        let welcome = try XCTUnwrap(inbox.first(where: { $0.id == "mail_welcome" }))
        XCTAssertFalse(welcome.claimed)
        XCTAssertTrue(welcome.hasGrants)

        let paid = try await backend.claim(mail: welcome)
        let expected: [ShopService.Grant] = [.scrolls(.mystical, 3), .drachma(5_000)]
        XCTAssertEqual(paid, expected)

        do {
            _ = try await backend.claim(mail: welcome)
            XCTFail("a second claim must throw")
        } catch let error as SocialError {
            guard case .conflict = error else { return XCTFail("expected a conflict, got \(error)") }
        }
        let after = try await backend.mail()
        let claimed = try XCTUnwrap(after.first(where: { $0.id == "mail_welcome" })).claimed
        XCTAssertTrue(claimed)
    }

    func testGreetingComesBackWithAGift() async throws {
        let backend = makeBackend()
        let me = try await publish(backend)
        let friendships = try await backend.friends()
        let friend = try XCTUnwrap(friendships.first)
        let before = try await backend.mail().count
        try await backend.send(mail: Mail.greeting(from: me, to: friend.friend))
        let after = try await backend.mail()
        let expectedCount = before + 1
        XCTAssertEqual(after.count, expectedCount)
        let reply = try XCTUnwrap(after.first(where: { $0.fromID == friend.friend.id }))
        XCTAssertTrue(reply.hasGrants)
    }

    // MARK: - Guilds

    func testGuildCreateJoinAndLeave() async throws {
        let backend = makeBackend()
        _ = try await publish(backend)
        let none = try await backend.guild()
        XCTAssertNil(none)

        let founded = try await backend.createGuild(name: "Order of the Ibis", crest: "eye.fill")
        XCTAssertEqual(founded.name, "Order of the Ibis")
        XCTAssertEqual(founded.memberCount, 1)
        let mine = try await backend.guild()
        XCTAssertEqual(mine?.id, founded.id)
        let roster = try await backend.guildMembers()
        XCTAssertEqual(roster.count, 1)
        XCTAssertEqual(roster.first?.role, .leader)
        let published = try await backend.myProfile()
        let profileInGuild = try XCTUnwrap(published)
        XCTAssertEqual(profileInGuild.guildID, founded.id)

        // A second guild while in one is refused.
        do {
            _ = try await backend.createGuild(name: "Another", crest: "bolt.fill")
            XCTFail("founding while in a guild must throw")
        } catch let error as SocialError {
            guard case .conflict = error else { return XCTFail("expected a conflict, got \(error)") }
        }

        try await backend.leaveGuild()
        let afterLeaving = try await backend.guild()
        XCTAssertNil(afterLeaving)
        // The last member out deletes the guild.
        let listed = try await backend.findGuilds(name: "Order")
        XCTAssertTrue(listed.isEmpty)

        let seeded = try await backend.findGuilds(name: "")
        let target = try XCTUnwrap(seeded.first)
        let membersBefore = target.memberCount
        let joined = try await backend.joinGuild(id: target.id)
        let membersAfter = membersBefore + 1
        XCTAssertEqual(joined.memberCount, membersAfter)
        let rosterAfterJoin = try await backend.guildMembers()
        XCTAssertEqual(rosterAfterJoin.count, membersAfter)
        XCTAssertTrue(rosterAfterJoin.contains { $0.userID == LocalSocialBackend.me && $0.role == .member })

        let posted = try await backend.postToBoard(text: "Hail, all.")
        let board = try await backend.board()
        XCTAssertEqual(board.first?.id, posted.id)

        try await backend.leaveGuild()
        let listedAgain = try await backend.findGuilds(name: "")
        let restored = try XCTUnwrap(listedAgain.first(where: { $0.id == target.id }))
        XCTAssertEqual(restored.memberCount, membersBefore)
    }

    // MARK: - The war

    func testWarPairingIsDeterministicPerWeekAndNeverTheGuildItself() async throws {
        let backend = makeBackend()
        let guilds = try await backend.findGuilds(name: "")
        XCTAssertGreaterThanOrEqual(guilds.count, 4)
        var picks: Set<String> = []
        for guild in guilds {
            for week in 30...41 {
                let key = String(format: "2026-W%02d", week)
                let first = try XCTUnwrap(WarRules.opponent(for: guild, among: guilds, week: key))
                let again = try XCTUnwrap(WarRules.opponent(for: guild, among: guilds, week: key))
                XCTAssertEqual(first.id, again.id)
                XCTAssertNotEqual(first.id, guild.id)
                picks.insert(first.id)
            }
        }
        // The hash spreads the pairings over the nearest three, not one.
        XCTAssertGreaterThan(picks.count, 1)
        // Alone, there is no war.
        let alone = try XCTUnwrap(guilds.first)
        XCTAssertNil(WarRules.opponent(for: alone, among: [alone], week: "2026-W38"))
    }

    func testWarPointsAndThePairingPointsIgnoreThisWeek() throws {
        let plain = WarRules.points(won: true, attackerPower: 5_000, targetPower: 4_000)
        let upset = WarRules.points(won: true, attackerPower: 4_000, targetPower: 5_000)
        let loss = WarRules.points(won: false, attackerPower: 1, targetPower: 9_999)
        let expectedUpset = WarRules.winPoints + WarRules.upsetBonus
        XCTAssertEqual(plain, WarRules.winPoints)
        XCTAssertEqual(upset, expectedUpset)
        XCTAssertEqual(loss, 0)

        var guild = Guild(
            id: "g", name: "G", crest: "bolt.fill", leaderID: "x", memberCount: 1,
            warPoints: 300, season: "2026-09", weekKey: "2026-W38", weekPoints: 45, createdAt: SocialTests.noon
        )
        let thisWeek = WarRules.pairingPoints(guild, week: "2026-W38")
        XCTAssertEqual(thisWeek, 255)
        guild.weekKey = "2026-W37"
        let staleWeek = WarRules.pairingPoints(guild, week: "2026-W38")
        XCTAssertEqual(staleWeek, 300)
    }

    func testWarStandingsSumTheWinsAndTheAttacksRunOutAtThree() async throws {
        let backend = makeBackend()
        _ = try await publish(backend)
        let seeded = try await backend.findGuilds(name: "")
        _ = try await backend.joinGuild(id: try XCTUnwrap(seeded.first).id)

        let warBefore = try await backend.war()
        let war = try XCTUnwrap(warBefore)
        XCTAssertEqual(war.week, "2026-W38")
        XCTAssertEqual(war.attacksLeftToday, WarRules.attacksPerDay)
        XCTAssertGreaterThanOrEqual(war.targets.count, 2)
        // The seeded guildmates already have this week's points, so every
        // assertion below is on the change the player's three attacks made.
        let mineBefore = try XCTUnwrap(war.mine)

        let victory = BattleResult(
            outcome: .victory, turnsTaken: 12, survivorFraction: 1,
            totalDamageDealt: 0, totalDamageTaken: 0, seed: 1
        )
        let defeat = BattleResult(
            outcome: .defeat, turnsTaken: 20, survivorFraction: 0,
            totalDamageDealt: 0, totalDamageTaken: 0, seed: 2
        )
        let first = war.targets[0]
        let second = war.targets[1]
        _ = try await backend.reportWarAttack(result: WarAttackResult(target: first, result: victory, foughtAt: SocialTests.noon))
        _ = try await backend.reportWarAttack(result: WarAttackResult(target: second, result: victory, foughtAt: SocialTests.noon))
        let standing = try await backend.reportWarAttack(result: WarAttackResult(target: first, result: defeat, foughtAt: SocialTests.noon))

        let expectedPoints = first.pointsForWin + second.pointsForWin
        let pointsGained = standing.points - mineBefore.points
        let winsGained = standing.wins - mineBefore.wins
        let attacksMade = standing.attacks - mineBefore.attacks
        XCTAssertEqual(pointsGained, expectedPoints)
        XCTAssertEqual(winsGained, 2)
        XCTAssertEqual(attacksMade, 3)
        XCTAssertTrue(standing.isMine)

        let warAfter = try await backend.war()
        let after = try XCTUnwrap(warAfter)
        XCTAssertEqual(after.attacksLeftToday, 0)
        let firstAgain = try XCTUnwrap(after.targets.first(where: { $0.id == first.id }))
        XCTAssertTrue(firstAgain.beaten)
        let myGuild = try await backend.guild()
        let guild = try XCTUnwrap(myGuild)
        XCTAssertEqual(guild.weekPoints, expectedPoints)

        do {
            _ = try await backend.reportWarAttack(result: WarAttackResult(target: second, result: victory, foughtAt: SocialTests.noon))
            XCTFail("a fourth attack in a day must throw")
        } catch let error as SocialError {
            guard case .conflict = error else { return XCTFail("expected a conflict, got \(error)") }
        }
    }

    // MARK: - Ranks

    func testLeaderboardsAreSortedWithThePlayersOwnRow() async throws {
        let backend = makeBackend()
        _ = try await publish(backend)
        let arena = try await backend.leaderboard(kind: .arena)
        XCTAssertFalse(arena.isEmpty)
        for (offset, entry) in arena.enumerated() {
            let expectedRank = offset + 1
            XCTAssertEqual(entry.rank, expectedRank)
            if offset > 0 {
                XCTAssertGreaterThanOrEqual(arena[offset - 1].score, entry.score)
            }
        }
        XCTAssertEqual(arena.filter(\.isMine).count, 1)

        let guilds = try await backend.leaderboard(kind: .guild)
        XCTAssertGreaterThanOrEqual(guilds.count, 4)
        for (offset, entry) in guilds.enumerated() where offset > 0 {
            XCTAssertGreaterThanOrEqual(guilds[offset - 1].score, entry.score)
        }
        XCTAssertTrue(guilds.allSatisfy { $0.crest != nil })
    }
}
