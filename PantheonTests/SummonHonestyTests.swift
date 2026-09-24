import XCTest
@testable import Pantheon

/// The summon tells the truth (2026-09-24, Docs/FEEL.md W1.5). The reveal
/// said "one skill levelled up" of every duplicate, even of a kit already at
/// its cap, because the answer of `ProgressionService.applySkillUp` was
/// thrown away where it was made. Now a duplicate's `skillUp` is the step
/// the copy already owned really took, read off that unit; a capped kit says
/// `.maxed` and nothing moves; and a new form's `codexDivinity` is exactly
/// what claiming its page pays, the family's first counted once. Every
/// figure a test compares is hoisted into a typed `let` first (CLAUDE.md: an
/// assert's parentheses stay free of arithmetic).
final class SummonHonestyTests: XCTestCase {

    /// A save holding one of every form the Duat banner can draw, each
    /// recorded in the book, so every pull is a duplicate.
    private func fullRoster(scrolls: Int) -> Player {
        var player = Player()
        player.units = []
        player.codex = []
        player.wallet.scrolls = [ScrollType.pantheonic.rawValue: scrolls]
        for blueprint in SummonService.eligible(for: .duatOpens) {
            player.units.append(Unit(blueprint: blueprint))
            player.codex.insert(blueprint.id)
        }
        return player
    }

    /// The skill levels of the FIRST copy of each form: the one a
    /// duplicate's skill-up goes to.
    private func firstCopies(_ player: Player) -> [String: [Int]] {
        var levels: [String: [Int]] = [:]
        for unit in player.units where levels[unit.blueprintID] == nil {
            levels[unit.blueprintID] = unit.skillLevels
        }
        return levels
    }

    /// Forty duplicates, one at a time: each one's record is the step its
    /// first copy really took — that skill, from the level it held to the
    /// level it holds now — and no other form's first copy moved.
    func testADuplicateReportsTheSkillThatRose() throws {
        var player = fullRoster(scrolls: 40)
        var rng = SeededRandom(seed: 17)
        var levelled = 0
        for _ in 0..<40 {
            let before: [String: [Int]] = firstCopies(player)
            let results = try SummonService.summon(banner: .duatOpens, count: 1, player: &player, rng: &rng)
            let result = try XCTUnwrap(results.first)
            let id: String = result.blueprint.id
            XCTAssertFalse(result.isNew, id)
            XCTAssertNil(result.codexDivinity, "\(id): a form already recorded has no page to pay")
            let after: [String: [Int]] = firstCopies(player)
            let was: [Int] = before[id] ?? []
            let now: [Int] = after[id] ?? []
            let skillUp = try XCTUnwrap(result.skillUp, "\(id): a duplicate of an owned form says what it did")
            switch skillUp {
            case .levelled(let skill, let from, let to):
                levelled += 1
                let held: Int = was.indices.contains(skill) ? was[skill] : 1
                let holds: Int = now.indices.contains(skill) ? now[skill] : 0
                let step: Int = to - from
                XCTAssertEqual(from, held, "\(id): the level it rose from")
                XCTAssertEqual(to, holds, "\(id): the level the copy now holds")
                XCTAssertEqual(step, 1, id)
            case .maxed:
                XCTAssertEqual(now, was, "\(id): a capped kit changed")
            }
            for (other, levels) in before where other != id {
                let moved: [Int] = after[other] ?? []
                XCTAssertEqual(moved, levels, "\(other) moved on \(id)'s pull")
            }
        }
        XCTAssertGreaterThan(levelled, 0, "forty duplicates on fresh kits raise some skill")
    }

    /// Every kit at its cap: every duplicate says `.maxed` — the reveal's
    /// "Skills maxed — feed to the Regalia" — and no level moves.
    func testACappedKitSaysSoAndChangesNothing() throws {
        var player = fullRoster(scrolls: 10)
        for index in player.units.indices {
            guard let blueprint = UnitDatabase.blueprint(player.units[index].blueprintID) else { continue }
            player.units[index].skillLevels = blueprint.skills.map { $0.maxSkillLevel }
        }
        let before: [[Int]] = player.units.map { $0.skillLevels }
        let capped: SummonSkillUp? = .maxed
        var rng = SeededRandom(seed: 5)
        let results = try SummonService.summon(banner: .duatOpens, count: 10, player: &player, rng: &rng)
        for result in results {
            XCTAssertEqual(result.skillUp, capped, result.blueprint.id)
        }
        let kept: [[Int]] = player.units.prefix(before.count).map { $0.skillLevels }
        XCTAssertEqual(kept, before)
    }

    /// Thirty pulls on an empty book: each new form's page promises exactly
    /// what claiming it pays, claimed in the order pulled, so the family's
    /// first goes to the page that promised it; a form with no page in the
    /// book promises nothing.
    func testANewPagePromisesWhatItsClaimPays() throws {
        var player = Player()
        player.units = []
        player.codex = []
        player.codexClaims = nil
        player.wallet.divinity = 0
        player.wallet.scrolls = [ScrollType.pantheonic.rawValue: 30]
        var rng = SeededRandom(seed: 23)
        let results = try SummonService.summon(banner: .duatOpens, count: 30, player: &player, rng: &rng)
        var promised = 0
        var paid = 0
        var pages = 0
        for result in results where result.isNew {
            let pageID: String = CodexService.claimID(for: result.blueprint.id, kind: .base)
            guard CodexService.entry(id: pageID) != nil else {
                XCTAssertNil(result.codexDivinity, "\(result.blueprint.id) has no page")
                continue
            }
            pages += 1
            let pay: Int = try XCTUnwrap(result.codexDivinity, "\(result.blueprint.id): a new form's page")
            let before: Int = player.wallet.divinity
            try CodexService.claim(pageID, player: &player, rng: &rng)
            let gained: Int = player.wallet.divinity - before
            XCTAssertEqual(gained, pay, result.blueprint.id)
            promised += pay
            paid += gained
        }
        XCTAssertEqual(paid, promised)
        XCTAssertGreaterThan(pages, 1, "thirty pulls on an empty book record more than one page")
    }

    /// Sixty SEPARATE single summons on an empty book, nothing claimed
    /// between them, then every page claimed in the REVERSE order: what the
    /// pages promised adds up to what claiming them pays (review,
    /// 2026-09-24). `promised` lives for one summon, so a family's second
    /// form in a later summon promised the family's first again — paid once.
    func testPagesPromisedAcrossSummonsAddUpToTheirClaims() throws {
        var player = Player()
        player.units = []
        player.codex = []
        player.codexClaims = nil
        player.wallet.divinity = 0
        player.wallet.scrolls = [ScrollType.pantheonic.rawValue: 60]
        var rng = SeededRandom(seed: 29)
        var pages: [(id: String, pay: Int, family: String)] = []
        for _ in 0..<60 {
            let results = try SummonService.summon(banner: .duatOpens, count: 1, player: &player, rng: &rng)
            let result = try XCTUnwrap(results.first)
            guard result.isNew else { continue }
            let pageID: String = CodexService.claimID(for: result.blueprint.id, kind: .base)
            guard let page = CodexService.entry(id: pageID) else { continue }
            let pay: Int = try XCTUnwrap(result.codexDivinity, "\(result.blueprint.id): a new form's page")
            pages.append((id: pageID, pay: pay, family: page.familyKey))
        }
        let families: Set<String> = Set(pages.map { $0.family })
        let twice: Int = pages.count - families.count
        XCTAssertGreaterThan(twice, 0, "sixty singles record two forms of some family in separate summons")
        let promised: Int = pages.reduce(0) { $0 + $1.pay }
        let before: Int = player.wallet.divinity
        for page in pages.reversed() {
            try CodexService.claim(page.id, player: &player, rng: &rng)
        }
        let paid: Int = player.wallet.divinity - before
        XCTAssertEqual(paid, promised)
    }

    /// A page already in the book and unclaimed — a unit owned from before
    /// the Codex — keeps its family's first: a new form of that family
    /// promises its own divinity alone.
    func testAnUnclaimedSiblingKeepsTheFamilysFirst() throws {
        let owned = try XCTUnwrap(UnitDatabase.blueprint("anubis_ember"))
        let pulled = try XCTUnwrap(UnitDatabase.blueprint("anubis_tide"))
        let page = try XCTUnwrap(CodexService.entry(id: CodexService.claimID(for: pulled.id, kind: .base)))
        var player = Player()
        player.units = [Unit(blueprint: owned)]
        player.codex = []
        player.codexClaims = nil
        var promised: Set<String> = []
        let pay: Int? = SummonService.codexPay(for: pulled.id, player: player, promised: &promised)
        let own: Int? = CodexService.entryDivinity(page)
        XCTAssertEqual(pay, own)
    }

    /// A shrine's duplicate tells the same truth as a scroll's: the skill its
    /// copy took and the levels either side.
    func testAShrineDuplicateReportsItsSkillUp() throws {
        let form = try XCTUnwrap(UnitDatabase.blueprint("anubis_tide"))
        var player = NewGame.create().player
        player.units.append(Unit(blueprint: form))
        player.codex.insert(form.id)
        let firstCopy: Int? = player.units.firstIndex(where: { $0.blueprintID == form.id })
        let owned: Int = try XCTUnwrap(firstCopy)
        let before: [Int] = player.units[owned].skillLevels
        player.shrinePieces = [form.id: 40]
        var rng = SeededRandom(seed: 11)
        let result = try ShrineService.summon(form.id, player: &player, rng: &rng)
        let after: [Int] = player.units[owned].skillLevels
        let skillUp = try XCTUnwrap(result.skillUp)
        switch skillUp {
        case .levelled(let skill, let from, let to):
            let held: Int = before.indices.contains(skill) ? before[skill] : 1
            let holds: Int = after.indices.contains(skill) ? after[skill] : 0
            XCTAssertEqual(from, held)
            XCTAssertEqual(to, holds)
        case .maxed:
            XCTAssertEqual(after, before, "a capped kit changed")
        }
    }
}
