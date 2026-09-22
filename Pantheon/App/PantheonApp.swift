import SwiftUI
import Combine
import UIKit

/// Who is playing, and the store that plays as them.
///
/// The store is REBUILT per account, never reloaded in place: a `GameStore`
/// holds its `Account` and saves under that key and no other, so a store
/// retired at sign-out cannot write the old player into the next account's
/// file — which a "current account" global and a reload in place would have
/// allowed the moment a pending 400 ms save fired across the swap. When there
/// is no store the root is the sign-in screen; when one exists it is the game
/// (`Docs/PLAN.md`, *Accounts — Sign in with Apple*).
@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var store: GameStore?
    /// True from a sign-in until its store exists: the credential is being
    /// verified and the cloud copy fetched.
    @Published private(set) var isOpening = false

    let accounts: AccountService
    private var forwarding: AnyCancellable?
    private var opening: Task<Void, Never>?

    init(accounts: AccountService) {
        self.accounts = accounts
        // The service's changes (a dropped sign-in, a notice) re-render
        // through this object, which is the one the views hold.
        forwarding = accounts.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        accounts.onDropped = { [weak self] in self?.dropStore() }
        if let account = accounts.account { open(account) }
    }

    /// Builds the store for an account: through the backend when one is
    /// configured (`Docs/BACKEND.md`; a guest and an Apple ID alike, the
    /// guest as an anonymous user), otherwise synchronously when nothing has
    /// to be fetched (a guest, an unentitled build, the tour — so the first
    /// frame has its store) and through Apple and iCloud for an Apple ID.
    /// `appleIdentityToken` is the token of a sign-in this launch, for the
    /// backend; `freshStart` skips every restore, for a player starting over.
    func open(_ account: Account, appleIdentityToken: String? = nil, freshStart: Bool = false) {
        opening?.cancel()
        store?.retire()
        store = nil
        // Every save that exists today is `pantheon_save.json`: the first
        // account to sign in on the phone takes it, before the cloud is asked
        // anything.
        if !freshStart {
            SaveStore.migrateLegacySave(to: account.storageKey)
        }
        if BackendConfig.isConfigured, let config = BackendConfig.shared {
            openThroughBackend(account, config: config, appleIdentityToken: appleIdentityToken, freshStart: freshStart)
            return
        }
        guard account.provider == .apple, let cloud = CloudSaveStore(key: account.storageKey) else {
            install(GameStore.bootstrap(account: account, cloudSave: nil))
            isOpening = false
            if account.provider == .apple {
                Task { [weak self] in
                    await self?.accounts.verifyCredentialState()
                }
            }
            return
        }
        isOpening = true
        opening = Task { [weak self] in
            guard let self else { return }
            // Apple first: a revoked sign-in never opens a store.
            let valid = await self.accounts.verifyCredentialState()
            guard valid, !Task.isCancelled else {
                self.isOpening = false
                return
            }
            // Then iCloud: ten seconds for a phone with no save of this
            // account (the restore is the point), four under the loading
            // screen when there is one. A corrupt local file is quarantined
            // by the load, which leaves no local save and lets the cloud copy
            // stand in for it.
            if !freshStart {
                let local = try? SaveStore.load(key: account.storageKey)
                _ = await cloud.restoreIfNewer(than: local, within: local == nil ? 10 : 4)
            }
            guard !Task.isCancelled else { return }
            self.install(GameStore.bootstrap(account: account, cloudSave: cloud))
            self.isOpening = false
        }
    }

    /// The backend's path (2026-09-22): Apple verified first for an Apple
    /// ID, then the Supabase session (saved, Apple's token, or an anonymous
    /// user for a guest), then the cloud row pulled when it is newer — ten
    /// seconds for a phone with no save of this account, four under the
    /// loading screen when there is one. A backend out of reach opens the
    /// local save as it is; the uploads retry at the next flush.
    private func openThroughBackend(_ account: Account, config: BackendConfig, appleIdentityToken: String?, freshStart: Bool) {
        isOpening = true
        opening = Task { [weak self] in
            guard let self else { return }
            if account.provider == .apple {
                let valid = await self.accounts.verifyCredentialState()
                guard valid, !Task.isCancelled else {
                    self.isOpening = false
                    return
                }
            }
            let client = SupabaseClient(config: config, storageKey: account.storageKey)
            let cloud = SupabaseSaveStore(client: client, account: account, appleIdentityToken: appleIdentityToken)
            let reached = await cloud.prepare()
            if reached, !freshStart {
                let local = try? SaveStore.load(key: account.storageKey)
                _ = await cloud.restoreIfNewer(than: local, within: local == nil ? 10 : 4)
            }
            guard !Task.isCancelled else { return }
            self.install(GameStore.bootstrap(account: account, cloudSave: cloud))
            self.isOpening = false
        }
    }

    /// "Reset account" on the Settings screen (2026-09-22): the store is
    /// retired, this phone's save kept aside as `reset_<stamp>_…`, the
    /// offline world wiped, the cloud copy erased, and a new game opened for
    /// the same account with no restore. When the cloud could not be
    /// reached, its old copy stays and comes back as a foreign save the
    /// Account panel offers — never silently over the new game.
    func startOver() async {
        guard let current = store, let account = accounts.account else { return }
        opening?.cancel()
        current.retire()
        let cloud = current.cloudSave
        store = nil
        isOpening = true
        SaveStore.archive(key: account.storageKey)
        LocalSocialBackend.wipe()
        if let cloud {
            _ = await cloud.erase()
        }
        open(account, freshStart: true)
    }

    private func install(_ newStore: GameStore) {
        newStore.onSignedOut = { [weak self] in
            guard let self else { return }
            self.store = nil
            self.accounts.signOut()
        }
        store = newStore
    }

    /// Apple said the sign-in is gone while the game was open: the store is
    /// saved, retired and dropped, and the sign-in screen returns.
    private func dropStore() {
        guard let current = store else { return }
        Task { await current.signOut() }
    }

    func signInWithApple(_ credential: AppleCredential) {
        accounts.notice = nil
        open(accounts.signInWithApple(credential), appleIdentityToken: credential.identityToken)
    }

    func continueAsGuest() {
        accounts.notice = nil
        open(accounts.continueAsGuest())
    }

    /// A guest binding this phone's progress to his Apple ID: the store is
    /// saved and retired, the file renamed, and a store for the Apple account
    /// opened over it.
    func bindGuestToApple(_ credential: AppleCredential) async {
        if let current = store {
            await current.saveNow()
            current.retire()
        }
        accounts.bindGuestToApple(credential)
        if let account = accounts.account { open(account, appleIdentityToken: credential.identityToken) }
    }

    func signOut() async {
        await store?.signOut()
    }

    /// "Restore from iCloud" on the Account panel: the other lineage's copy
    /// written over this phone's save (kept aside by the import), and the
    /// store reopened on it.
    func restoreFromCloud() async {
        guard let current = store, let cloud = current.cloudSave else { return }
        current.retire()
        _ = cloud.restoreForeign()
        open(current.account)
    }

    /// On every return to the foreground: Apple is asked whether the sign-in
    /// still stands (`onDropped` retires the store when it does not).
    func sceneBecameActive() {
        Task { [weak self] in
            await self?.accounts.verifyCredentialState()
        }
    }
}

@main
struct PantheonApp: App {
    @StateObject private var session: AppSession
    @StateObject private var launch: LaunchProgress

    /// Explicitly main-actor isolated: `GameStore` is `@MainActor`, and building
    /// it in a default property value would leave that isolation implicit.
    @MainActor
    init() {
        // The two bundled faces, before any view asks `Theme` for a font.
        FontLibrary.registerBundledFonts()

        // The CI tour never signs in: it plays as a fixed guest, held in
        // memory, so every launch of the tour opens the same save and no
        // dialog, no Apple and no CloudKit stand between it and its screen.
        var touring = false
        #if DEBUG
        touring = ProcessInfo.processInfo.arguments.contains("-tour")
        #endif
        let accounts = AccountService(preset: touring ? AccountService.tourAccount : nil)
        _session = StateObject(wrappedValue: AppSession(accounts: accounts))
        _launch = StateObject(wrappedValue: LaunchProgress())

        // The whole app is cream and gold, the tab bar included; setting it
        // here stops a dark flash on launch before the first SwiftUI frame
        // applies the preference. The selected tab is the DIM gold — the
        // bright one reads on ink, not on cream — and the rest are the
        // caption colour, so the bar is the header strip's own material.
        UITabBar.appearance().backgroundColor = UIColor(Theme.surfaceRaised)
        UITabBar.appearance().tintColor = UIColor(Theme.goldDim)
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.textSecondary)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: UIColor(Theme.textPrimary)
        ]

        // Decode the sound set now so the first hit of the first battle does
        // not stutter. Off the main thread; a missing file is a silent event.
        AudioLibrary.shared.preload()

        // The main-thread watchdog: any stall over a quarter second is
        // written to More → Diagnostics with its length and the time.
        Perf.startWatchdog()

        #if DEBUG
        // Line-buffered stdout. The CI tour writes the app's stdout to a
        // file and kills the app at the end of each step; a block-buffered
        // stdout took the last kilobytes with it — every run's wave-three
        // loads and the watchdog's lines were in the buffer, not the file.
        setvbuf(stdout, nil, _IOLBF, 0)
        #endif

        // Build the unit database and the bundle's resource index before a
        // screen asks for them. `UnitDatabase.all` is three hundred and
        // ninety-five blueprints and `summonPool` filters every one of them on
        // whether its card shipped; whichever screen touched it first paid for
        // all of it on the main thread, which is why the arena took seconds to
        // open. Swift's lazy static initialisation is thread-safe, so warming
        // it here is only a matter of who waits.
        DispatchQueue.global(qos: .userInitiated).async {
            _ = UnitDatabase.summonPool
            _ = StageDatabase.allStages.count
        }

        #if DEBUG
        // Reports, once, which models are really in the app and which are
        // standing in. A placeholder and a model that failed to load look
        // identical on screen; this is the only place the difference shows.
        ModelLibrary.shared.diagnose(
            expecting: UnitDatabase.all.map { $0.model.assetName }
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // `-tour` is the CI screenshot job: the app drives itself through
            // its screens while the runner photographs the simulator. The
            // tour's guest has no cloud, so its store is built in `init`.
            if ProcessInfo.processInfo.arguments.contains("-tour") {
                if let store = session.store {
                    TourView()
                        .environmentObject(store)
                        .environmentObject(session)
                }
            } else {
                gate
            }
            #else
            gate
            #endif
        }
    }

    /// The sign-in screen while no account is signed in, the game once its
    /// store exists — the shell keyed by the account, so a sign-in rebuilds
    /// every screen under it — and the loading screen over whichever is
    /// under it until the launch has warmed what it warms and the painting
    /// has had its moment; then it dissolves.
    private var gate: some View {
        ZStack {
            if let store = session.store {
                RootView()
                    .environmentObject(store)
                    .environmentObject(session)
                    .id(store.account.id)
            } else {
                SignInView(
                    isOpening: session.isOpening,
                    notice: session.accounts.notice,
                    onApple: { credential in session.signInWithApple(credential) },
                    onGuest: { session.continueAsGuest() }
                )
            }
            if !launch.finished {
                LaunchView(progress: launch)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear { launch.run() }
    }
}
