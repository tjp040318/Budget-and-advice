import XCTest
@testable import Pantheon

/// The Codex (Docs/CODEX.md): a page pays once, and only for a form the save
/// has held; the family's first pays once per family; Radiance and Umbra
/// pages pay double; a pantheon's tier pays at its share of pages recorded,
/// once; Claim all pays exactly what the claims one by one would. Every
/// figure a test sums is hoisted into a typed `let` first (CLAUDE.md: an
/// assert's parentheses stay free of arithmetic).
final class CodexTests: XCTestCase {

    /// A save with nothing in it, no divinity and no scrolls, so the wallet
    /// after a claim is exactly what the claim paid.
    private func emptySave() -> Player {
        var player = Player()
        player.wallet.divinity = 0
        player.wallet.scrolls = [:]
        return player
    }

    private func page(_ blueprintID: String, _ kind: CodexFormKind = .base) throws -> CodexEntry {
        try XCTUnwrap(CodexService.entry(id: CodexService.claimID(for: blueprintID, kind: kind)), blueprintID)
    }

    private func give(_ blueprintID: String, awakened: Bool = false, to player: inout Player) throws {
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint(blueprintID), blueprintID)
        player.units.append(Unit(blueprint: blueprint, awakened: awakened))
    }

    // MARK: - The table

    func testTheRewardTableIsPinned() {
        // Docs/CODEX.md, *The reward table*: measured against a first month
        // (about 6% of its income) and a first year (about 2%). Change a
        // number in CodexService, the doc and here together.
        XCTAssertEqual(CodexService.formDivinity, [3: 5, 4: 10, 5: 25])
        XCTAssertEqual(CodexService.awakenedDivinity, [4: 20, 5: 40])
        XCTAssertEqual(CodexService.familyFirstDivinity, [3: 5, 4: 20, 5: 50])
        XCTAssertEqual(CodexService.premiumMultiple, 2)
        XCTAssertEqual(CodexService.prize(for: .quarter), [.scrolls(.pantheonic, 1), .divinity(100)])
        XCTAssertEqual(CodexService.prize(for: .half), [.scrolls(.divine, 1)])
        XCTAssertEqual(CodexService.prize(for: .threeQuarters), [.scrolls(.lightDark, 1), .divinity(300)])
        XCTAssertEqual(CodexService.prize(for: .whole), [.scrolls(.lightDark, 3), .divinity(1_000)])

        // The intent beside the numbers. No page's own reward reaches the
        // price of a Pantheon Scroll: the book is a small return on the
        // summons, never a second income.
        let dearestFace: Int = (CodexService.awakenedDivinity[5] ?? 0) * CodexService.premiumMultiple
        let pantheonScroll: Int = ScrollType.pantheonic.divinityPrice ?? 0
        XCTAssertLessThan(dearestFace, pantheonScroll)
        // An awakening is work and a summon is luck: every awakened face
        // pays more than its form.
        for stars in [4, 5] {
            let face: Int = CodexService.awakenedDivinity[stars] ?? 0
            let form: Int = CodexService.formDivinity[stars] ?? 0
            XCTAssertGreaterThan(face, form, "\(stars)★")
        }
    }

    func testTheWholeBookIsWhatTheDocMeasured() {
        // The roster of 2026-09-23: 99 families, 495 forms, 335 awakened
        // faces. The pages' divinity is 8,225 for the forms, 12,600 for the
        // faces and 2,190 for the families' firsts (Docs/CODEX.md, *What the
        // whole book pays*). A family added moves these: measure the book's
        // share of the economy again there, and move the doc and this with
        // it.
        let forms = CodexService.entries.filter { $0.kind == .base }
        let faces = CodexService.entries.filter { $0.kind == .awakened }
        let formDivinity: Int = forms.reduce(0) { $0 + CodexService.entryDivinity($1) }
        let faceDivinity: Int = faces.reduce(0) { $0 + CodexService.entryDivinity($1) }
        let firsts: Int = CodexService.families.reduce(0) { $0 + CodexService.familyFirstBonus(stars: $1.stars) }
        XCTAssertEqual(CodexService.families.count, 99)
        XCTAssertEqual(forms.count, 495)
        XCTAssertEqual(faces.count, 335)
        XCTAssertEqual(formDivinity, 8_225)
        XCTAssertEqual(faceDivinity, 12_600)
        XCTAssertEqual(firsts, 2_190)
    }

    // MARK: - The book

    func testTheBookHoldsEveryCollectibleFormOnce() {
        let pool = UnitDatabase.collectiblePool
        let forms = CodexService.entries.filter { $0.kind == .base }.map(\.blueprintID)
        XCTAssertEqual(forms.count, pool.count, "one page per collectible form")
        XCTAssertEqual(Set(forms), Set(pool))
        // An awakened face for exactly the forms with an awakening.
        let faces = Set(CodexService.entries.filter { $0.kind == .awakened }.map(\.blueprintID))
        let awakenable = Set(pool.filter { UnitDatabase.blueprint($0)?.awakening != nil })
        XCTAssertEqual(faces, awakenable)
        // Every page claims under its own id.
        let ids = CodexService.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        // The fusion prizes are in the book: no scroll gives them, and the
        // hexagram's owner must still be able to finish a pantheon.
        for recipe in FusionService.recipes {
            XCTAssertTrue(forms.contains(recipe.resultID), recipe.resultID)
        }
        // A family's forms share its pantheon and its grade.
        for family in CodexService.families {
            for id in family.forms.values {
                XCTAssertEqual(UnitDatabase.blueprint(id)?.pantheon, family.pantheon, id)
                XCTAssertEqual(UnitDatabase.blueprint(id)?.naturalStars, family.stars, id)
            }
        }
        // The rarest first, as the genre's book files them.
        let grades = CodexService.families.map(\.stars)
        XCTAssertEqual(grades, grades.sorted(by: >))
    }

    func testAFormHeldNowOrEverIsRecorded() throws {
        var player = emptySave()
        let tide = try page("anubis_tide")
        XCTAssertEqual(CodexService.ledger(for: player).standing(tide), .unrecorded)

        // Held now: a unit in the roster, which the tour's seed adds without
        // writing the codex.
        try give("anubis_tide", to: &player)
        XCTAssertEqual(CodexService.ledger(for: player).standing(tide), .ready)

        // Held once: fed away since, but the codex remembers every form ever
        // owned (`Player.codex`, written by every way a unit arrives).
        player.units.removeAll()
        player.codex.insert("anubis_tide")
        XCTAssertEqual(CodexService.ledger(for: player).standing(tide), .ready)
    }

    // MARK: - Claims

    func testAPagePaysOnceAndTheFamilysFirstOnlyOnce() throws {
        var player = emptySave()
        var rng = SeededRandom(seed: 1)
        try give("anubis_tide", to: &player)
        try give("anubis_gale", to: &player)
        let tide = try page("anubis_tide")
        let gale = try page("anubis_gale")

        try CodexService.claim(tide.id, player: &player, rng: &rng)
        let firstPay: Int = 10 + 20   // a 4★ form, and the family's first
        XCTAssertEqual(player.wallet.divinity, firstPay)

        try CodexService.claim(gale.id, player: &player, rng: &rng)
        let secondPay: Int = firstPay + 10   // the family's first is spent
        XCTAssertEqual(player.wallet.divinity, secondPay)

        XCTAssertThrowsError(try CodexService.claim(tide.id, player: &player, rng: &rng)) { error in
            XCTAssertEqual(error as? CodexError, .alreadyClaimed)
        }
        XCTAssertEqual(player.wallet.divinity, secondPay)
        XCTAssertEqual(CodexService.ledger(for: player).standing(tide), .claimed)
    }

    func testNothingPaysForAFormNeverHeld() {
        var player = emptySave()
        var rng = SeededRandom(seed: 2)
        XCTAssertThrowsError(try CodexService.claim("form:anubis_tide", player: &player, rng: &rng)) { error in
            XCTAssertEqual(error as? CodexError, .notRecorded)
        }
        XCTAssertThrowsError(try CodexService.claim("form:no_such_god", player: &player, rng: &rng)) { error in
            XCTAssertEqual(error as? CodexError, .unknownEntry)
        }
        XCTAssertEqual(player.wallet.divinity, 0)
        XCTAssertNil(player.codexClaims, "a refused claim writes nothing")
    }

    func testRadianceAndUmbraPagesPayDouble() throws {
        var player = emptySave()
        var rng = SeededRandom(seed: 3)
        try give("anubis_umbra", to: &player)
        let umbra = try page("anubis_umbra")
        try CodexService.claim(umbra.id, player: &player, rng: &rng)
        let premiumForm: Int = 10 * CodexService.premiumMultiple
        let paid: Int = premiumForm + 20   // the family's first is never doubled
        XCTAssertEqual(player.wallet.divinity, paid)
    }

    func testTheAwakenedFaceNeedsAnAwakening() throws {
        var player = emptySave()
        var rng = SeededRandom(seed: 4)
        try give("anubis_tide", to: &player)
        let face = try page("anubis_tide", .awakened)
        XCTAssertEqual(CodexService.ledger(for: player).standing(face), .unrecorded)
        XCTAssertThrowsError(try CodexService.claim(face.id, player: &player, rng: &rng)) { error in
            XCTAssertEqual(error as? CodexError, .notRecorded)
        }

        player.units[0].isAwakened = true
        XCTAssertEqual(CodexService.ledger(for: player).standing(face), .ready)
        try CodexService.claim(face.id, player: &player, rng: &rng)
        let paid: Int = 20 + 20   // a 4★'s awakened face, and the family's first
        XCTAssertEqual(player.wallet.divinity, paid)

        // Claimed, the page stays lit after the unit that earned it is gone,
        // and so does its form.
        player.units.removeAll()
        let book = CodexService.ledger(for: player)
        XCTAssertEqual(book.standing(face), .claimed)
        XCTAssertEqual(book.standing(try page("anubis_tide")), .ready)

        // A 3★ family has no awakened face at all.
        XCTAssertNil(CodexService.entry(id: CodexService.claimID(for: "shabti_tide", kind: .awakened)))
    }

    func testATierPaysAtItsShareOfThePantheonAndOnce() throws {
        var player = emptySave()
        var rng = SeededRandom(seed: 5)
        let total = CodexService.pages(of: .roman).count
        let target = CodexService.target(for: .quarter, total: total)
        // The share rounds UP: a quarter is never reached a page short.
        let reached: Int = target * 4
        let shortOf: Int = (target - 1) * 4
        XCTAssertGreaterThanOrEqual(reached, total)
        XCTAssertLessThan(shortOf, total)

        let forms = CodexService.pages(of: .roman).filter { $0.kind == .base }
        for form in forms.prefix(target - 1) { player.codex.insert(form.blueprintID) }
        let oneShort = CodexService.ledger(for: player)
        XCTAssertEqual(CodexService.recordsNeeded(for: .quarter, of: .roman, ledger: oneShort), 1)
        XCTAssertEqual(CodexService.tierStanding(.quarter, of: .roman, ledger: oneShort), .unrecorded)
        XCTAssertThrowsError(try CodexService.claimTier(.quarter, of: .roman, player: &player, rng: &rng)) { error in
            XCTAssertEqual(error as? CodexError, .tierNotReached(needed: 1))
        }

        // The last page: reached on the pages RECORDED, none of them claimed.
        for form in forms.dropFirst(target - 1).prefix(1) { player.codex.insert(form.blueprintID) }
        XCTAssertEqual(CodexService.tierStanding(.quarter, of: .roman, ledger: CodexService.ledger(for: player)), .ready)
        try CodexService.claimTier(.quarter, of: .roman, player: &player, rng: &rng)
        XCTAssertEqual(player.wallet.divinity, 100)
        XCTAssertEqual(player.wallet.count(of: .pantheonic), 1)
        XCTAssertThrowsError(try CodexService.claimTier(.quarter, of: .roman, player: &player, rng: &rng)) { error in
            XCTAssertEqual(error as? CodexError, .alreadyClaimed)
        }
        // The next tier is still far off.
        XCTAssertEqual(CodexService.tierStanding(.half, of: .roman, ledger: CodexService.ledger(for: player)), .unrecorded)
    }

    func testClaimAllPaysWhatTheClaimsOneByOneWould() throws {
        var player = emptySave()
        for id in ["anubis_tide", "anubis_umbra", "zeus_ember", "shabti_gale", "mars_ember", "odin_tide"] {
            try give(id, to: &player)
        }
        player.units[0].isAwakened = true
        // And a quarter of Rome, for a tier among the pages.
        let romanForms = CodexService.pages(of: .roman).filter { $0.kind == .base }
        let target = CodexService.target(for: .quarter, total: CodexService.pages(of: .roman).count)
        for form in romanForms.prefix(target) { player.codex.insert(form.blueprintID) }

        var together = player
        var rngTogether = SeededRandom(seed: 6)
        let receipt = CodexService.claimAll(player: &together, rng: &rngTogether)

        var oneByOne = player
        var rngOneByOne = SeededRandom(seed: 6)
        let book = CodexService.ledger(for: oneByOne)
        for entry in CodexService.entries where book.standing(entry) == .ready {
            try CodexService.claim(entry.id, player: &oneByOne, rng: &rngOneByOne)
        }
        for pantheon in CodexService.pantheons {
            for tier in CodexTier.allCases where CodexService.tierStanding(tier, of: pantheon, ledger: book) == .ready {
                try CodexService.claimTier(tier, of: pantheon, player: &oneByOne, rng: &rngOneByOne)
            }
        }

        XCTAssertEqual(together.wallet.divinity, oneByOne.wallet.divinity)
        XCTAssertEqual(together.wallet.scrolls, oneByOne.wallet.scrolls)
        XCTAssertEqual(together.codexClaims, oneByOne.codexClaims)
        XCTAssertEqual(CodexService.readyCount(player: together), 0)
        let again = CodexService.claimAll(player: &together, rng: &rngTogether)
        XCTAssertTrue(again.isEmpty, "nothing pays twice")
        // One tile per currency on the receipt: all the divinity, then Rome's
        // Pantheon Scroll.
        let firstTile = try XCTUnwrap(receipt.first)
        XCTAssertEqual(firstTile, ShopService.Grant.divinity(together.wallet.divinity))
        XCTAssertEqual(receipt.count, 2)
    }

    func testANewAccountOwesTheStartersPage() {
        var player = NewGame.create().player
        let before = player.wallet.divinity
        XCTAssertEqual(CodexService.readyCount(player: player), 1, "the starter's form and nothing else")
        var rng = SeededRandom(seed: 7)
        let receipt = CodexService.claimAll(player: &player, rng: &rng)
        let starterPage: Int = 10 + 20   // a 4★ form, and the family's first
        let after: Int = before + starterPage
        XCTAssertEqual(player.wallet.divinity, after)
        XCTAssertEqual(receipt, [.divinity(starterPage)])
    }

    // MARK: - Roads and words

    func testTheRoadsKeepTheLightAndDarkRule() throws {
        let player = emptySave()
        let umbra = try page("anubis_umbra")
        let umbraRoads = CodexService.sources(for: umbra, player: player).map(\.id)
        XCTAssertEqual(umbraRoads, ["banner_\(Banner.lightAndDark.id)"],
                       "a Radiance or Umbra form comes from the Light & Dark scroll alone")

        let fire = try page("anubis_ember")
        let fireRoads = CodexService.sources(for: fire, player: player).map(\.id)
        XCTAssertTrue(fireRoads.contains("banner_\(Banner.duatOpens.id)"))
        XCTAssertFalse(fireRoads.contains("banner_\(Banner.lightAndDark.id)"))

        for recipe in FusionService.recipes {
            let prize = try page(recipe.resultID)
            let roads = CodexService.sources(for: prize, player: player).map(\.id)
            XCTAssertEqual(roads, ["fusion_\(recipe.id)"], "\(recipe.resultID) is the hexagram's alone")
        }

        // An awakened page leads with the awakening.
        let face = try page("anubis_tide", .awakened)
        XCTAssertEqual(CodexService.sources(for: face, player: player).first?.id, "awakening")
    }

    func testFormsAreNamedAsTheirCardsAre() throws {
        XCTAssertEqual(CodexService.formName(for: try page("anubis_ember")), "Anubis of the Burning Sands")
        XCTAssertEqual(CodexService.formName(for: try page("anubis_umbra")), "Anubis, Guardian of the Scales")
        XCTAssertEqual(CodexService.formName(for: try page("anubis_ember", .awakened)), "Anubis, Keeper of the Ash Road")
    }

    func testTheReceiptFoldsItsGrants() {
        let folded = CodexService.merged([.divinity(10), .scrolls(.pantheonic, 1), .divinity(20),
                                          .scrolls(.pantheonic, 2), .energy(5)])
        XCTAssertEqual(folded, [.divinity(30), .scrolls(.pantheonic, 3), .energy(5)])
    }

    func testRatesReadAsTheRateTablePrintsThem() {
        XCTAssertEqual(CodexService.percentText(0.03), "3%")
        XCTAssertEqual(CodexService.percentText(0.015), "1.5%")
        XCTAssertEqual(CodexService.percentText(0.008), "0.8%")
        XCTAssertEqual(CodexService.percentText(0.885), "88.5%")
    }
}
