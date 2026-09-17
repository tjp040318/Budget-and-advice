import XCTest
@testable import Pantheon

/// Accounts (`Docs/PLAN.md`, *Accounts — Sign in with Apple*): one save per
/// identity, the legacy save carried to the first account, a guest's hour
/// carried to his Apple ID, and a sign-out that keeps the file. Every test
/// points `SaveStore` at its own temporary folder; nothing here touches
/// Apple's servers or CloudKit.
final class AccountTests: XCTestCase {
    private var folder: URL!
    private var previousBase: URL?

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        previousBase = SaveStore.baseURL
        SaveStore.baseURL = folder
    }

    override func tearDown() {
        SaveStore.baseURL = previousBase
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private static let hexDigits = Set("0123456789abcdef")

    /// A credential as Apple sends it the first time: with the name.
    private static let firstCredential = AppleCredential(
        user: "001234.owner.5678",
        givenName: "Tyler",
        familyName: "Pratt",
        email: "owner@example.com"
    )

    /// The same Apple ID on any later sign-in: the id alone.
    private static let laterCredential = AppleCredential(
        user: "001234.owner.5678",
        givenName: nil,
        familyName: nil,
        email: nil
    )

    // MARK: - The key

    func testStorageKeyIsStableFilesystemSafeAndSHA256() {
        // SHA-256("hello") begins 2cf24dba5fb0a30e…: the key IS that digest,
        // so a support script in any language can compute it from the id.
        XCTAssertEqual(Account.key(for: "hello"), "2cf24dba5fb0a30e")

        let apple = Account(id: "001234.abcdef.5678", provider: .apple, displayName: nil, email: nil, createdAt: Date())
        let key = apple.storageKey
        XCTAssertEqual(key.count, 16)
        XCTAssertTrue(key.allSatisfy { AccountTests.hexDigits.contains($0) }, "the key is hex, never the id's dots")
        XCTAssertEqual(key, apple.storageKey, "stable across calls")
        XCTAssertNotEqual(key, Account.guest().storageKey)
        XCTAssertEqual(apple.playerCode.count, 6)
        XCTAssertEqual(apple.playerCode, apple.playerCode.uppercased())
        XCTAssertTrue(key.hasSuffix(apple.playerCode.lowercased()), "the Player ID is the key's tail")
    }

    func testAGuestIsAGuestAndAppleGivesTheDemigodItsName() {
        let guest = Account.guest()
        XCTAssertTrue(guest.isGuest)
        XCTAssertTrue(guest.id.hasPrefix(Account.guestPrefix))
        XCTAssertEqual(guest.demigodName, "Demigod")

        var apple = Account(id: "001.x", provider: .apple, displayName: "Tyler Pratt", email: nil, createdAt: Date())
        XCTAssertEqual(apple.demigodName, "Tyler")
        apple.displayName = nil
        XCTAssertEqual(apple.demigodName, "Demigod")
    }

    // MARK: - The files

    func testLegacySaveMigratesOnceToTheFirstAccount() throws {
        var game = NewGame.create()
        game.player.wallet.divinity = 4_242
        let legacy = try XCTUnwrap(SaveStore.legacySaveURL)
        try SaveStore.encode(game).write(to: legacy)

        let first = Account.guest()
        let second = Account.guest()
        XCTAssertTrue(SaveStore.migrateLegacySave(to: first.storageKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "renamed, not copied")

        let carried = try SaveStore.load(key: first.storageKey)
        XCTAssertEqual(carried?.player.wallet.divinity, 4_242)

        // Once: the second account finds nothing to take.
        XCTAssertFalse(SaveStore.migrateLegacySave(to: second.storageKey))
        let nothing = try SaveStore.load(key: second.storageKey)
        XCTAssertNil(nothing)
        XCTAssertTrue(SaveStore.hasSave(key: first.storageKey))
    }

    func testTwoAccountsOnOneDeviceLoadTwoDifferentSaves() throws {
        let alpha = Account(id: "001.alpha", provider: .apple, displayName: nil, email: nil, createdAt: Date())
        let beta = Account(id: "001.beta", provider: .apple, displayName: nil, email: nil, createdAt: Date())
        XCTAssertNotEqual(alpha.storageKey, beta.storageKey)

        var alphaGame = NewGame.create()
        alphaGame.player.wallet.divinity = 111
        var betaGame = NewGame.create()
        betaGame.player.wallet.divinity = 222
        try SaveStore.save(alphaGame, key: alpha.storageKey)
        try SaveStore.save(betaGame, key: beta.storageKey)

        let alphaBack = try SaveStore.load(key: alpha.storageKey)
        let betaBack = try SaveStore.load(key: beta.storageKey)
        XCTAssertEqual(alphaBack?.player.wallet.divinity, 111)
        XCTAssertEqual(betaBack?.player.wallet.divinity, 222)

        SaveStore.deleteSave(key: alpha.storageKey)
        XCTAssertFalse(SaveStore.hasSave(key: alpha.storageKey))
        XCTAssertTrue(SaveStore.hasSave(key: beta.storageKey), "deleting one account's save leaves the other's")
    }

    func testImportKeepsTheOlderFileAsideAndRefusesBadBytes() throws {
        let account = Account.guest()
        var older = NewGame.create()
        older.player.wallet.divinity = 1
        try SaveStore.save(older, key: account.storageKey)

        var newer = NewGame.create()
        newer.player.wallet.divinity = 2
        try SaveStore.importData(SaveStore.encode(newer), key: account.storageKey)
        let restored = try SaveStore.load(key: account.storageKey)
        XCTAssertEqual(restored?.player.wallet.divinity, 2)

        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Pantheon").path)
        XCTAssertTrue(kept.contains { $0.hasPrefix("replaced_") }, "the replaced save is moved aside, never deleted")

        XCTAssertThrowsError(try SaveStore.importData(Data("not a save".utf8), key: account.storageKey))
        let unchanged = try SaveStore.load(key: account.storageKey)
        XCTAssertEqual(unchanged?.player.wallet.divinity, 2, "bad bytes replace nothing")
    }

    // MARK: - The service

    @MainActor
    func testGuestBindingCarriesTheSaveToTheAppleKey() async throws {
        let accounts = AccountService(directory: folder)
        XCTAssertNil(accounts.account)
        let guest = accounts.continueAsGuest()
        XCTAssertTrue(guest.isGuest)

        var game = NewGame.create()
        game.player.wallet.divinity = 777
        try SaveStore.save(game, key: guest.storageKey)

        let outcome = accounts.bindGuestToApple(AccountTests.firstCredential)
        XCTAssertEqual(outcome, .bound)
        let apple = try XCTUnwrap(accounts.account)
        XCTAssertEqual(apple.provider, .apple)
        XCTAssertEqual(apple.id, "001234.owner.5678")
        XCTAssertEqual(apple.displayName, "Tyler Pratt")
        XCTAssertEqual(apple.email, "owner@example.com")

        let carried = try SaveStore.load(key: apple.storageKey)
        XCTAssertEqual(carried?.player.wallet.divinity, 777)
        XCTAssertFalse(SaveStore.hasSave(key: guest.storageKey), "renamed, not copied")

        // Binding into an Apple ID that already has a save keeps that save.
        let secondGuest = AccountService(directory: folder.appendingPathComponent("other"))
        _ = secondGuest.continueAsGuest()
        XCTAssertEqual(secondGuest.bindGuestToApple(AccountTests.firstCredential), .keptAppleSave)
        let stillApple = try SaveStore.load(key: apple.storageKey)
        XCTAssertEqual(stillApple?.player.wallet.divinity, 777)
    }

    @MainActor
    func testSigningOutKeepsTheFileAndTheNameComesBack() async throws {
        let accounts = AccountService(directory: folder)
        let apple = accounts.signInWithApple(AccountTests.firstCredential)
        var game = NewGame.create()
        game.player.wallet.divinity = 5_555
        try SaveStore.save(game, key: apple.storageKey)

        accounts.signOut()
        XCTAssertNil(accounts.account)
        XCTAssertTrue(SaveStore.hasSave(key: apple.storageKey), "signing out never touches the save")

        // A later sign-in carries no name or email; the ledger gives the
        // first one's back, and the same key opens the same save.
        let again = accounts.signInWithApple(AccountTests.laterCredential)
        XCTAssertEqual(again.id, apple.id)
        XCTAssertEqual(again.displayName, "Tyler Pratt")
        XCTAssertEqual(again.email, "owner@example.com")
        XCTAssertEqual(again.storageKey, apple.storageKey)
        let back = try SaveStore.load(key: again.storageKey)
        XCTAssertEqual(back?.player.wallet.divinity, 5_555)

        // The ledger is a file: a fresh service reads the sign-in back.
        let reopened = AccountService(directory: folder)
        XCTAssertEqual(reopened.account?.id, apple.id)
        XCTAssertEqual(reopened.account?.displayName, "Tyler Pratt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(AccountService.filename).path))
    }

    @MainActor
    func testTourAccountIsAFixedGuestHeldInMemory() async {
        let accounts = AccountService(directory: folder, preset: AccountService.tourAccount)
        XCTAssertEqual(accounts.account?.id, "guest-tour-000000")
        XCTAssertEqual(accounts.account?.provider, .guest)
        XCTAssertEqual(AccountService.tourAccount.storageKey, Account.key(for: "guest-tour-000000"), "the same key on every launch of the tour")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(AccountService.filename).path), "never written")
    }

    // MARK: - The store

    @MainActor
    func testAStoreSavesUnderItsOwnKeyAndARetiredStoreWritesNothing() async throws {
        let account = Account.guest()
        let store = GameStore.bootstrap(account: account, cloudSave: nil)
        XCTAssertEqual(store.account.id, account.id)
        store.update { $0.wallet.divinity = 99 }
        await store.saveNow()
        let saved = try SaveStore.load(key: account.storageKey)
        XCTAssertEqual(saved?.player.wallet.divinity, 99)

        store.retire()
        store.update { $0.wallet.divinity = 1 }
        await store.saveNow()
        let afterRetire = try SaveStore.load(key: account.storageKey)
        XCTAssertEqual(afterRetire?.player.wallet.divinity, 99, "a retired store cannot write into the file")
    }
}
