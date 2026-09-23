import SwiftUI
import UIKit

/// The app's tab shell.
struct RootView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var session: AppSession
    @State private var tab: Tab
    @State private var showTraining = false
    @State private var showSettings = false
    @State private var showLabyrinth = false
    @Environment(\.scenePhase) private var scenePhase

    /// The phone opens on the island; the CI tour's `-tour-root <tab>` opens
    /// the shell itself on another tab, so the real TabView-and-bar layout
    /// is photographed and not only the tour's copy of it.
    init(initialTab: Tab = .island) {
        _tab = State(initialValue: initialTab)
    }

    /// Five tabs, which is all an iPhone shows before it folds the rest
    /// into a "More" list of its own; the Hall of Ka and the settings open
    /// over the island instead.
    enum Tab: Hashable {
        case island, campaign, arena, summon, collection

        /// The tab a landmark leads to; nil for the two that open over the island.
        init?(_ destination: IslandDestination) {
            switch destination {
            case .campaign: self = .campaign
            case .arena: self = .arena
            case .summon: self = .summon
            case .collection: self = .collection
            case .training, .settings, .labyrinth: return nil
            }
        }
    }

    var body: some View {
        // The game's own bar (2026-09-22) is LAID OUT under the tabs since
        // run 216: the tabs' container ends where the bar begins, so every
        // tab screen is 58 points shorter than the window. It was the
        // TabView's `.safeAreaInset`, and that inset never reached the
        // content inside each tab's `NavigationStack` — the arena's offence,
        // the summon deck, the collection's Train and the chapter map's
        // lowest medallions were laid out to the window's foot and painted
        // over by the bar. The band's marble still runs under the home
        // indicator and out to both edges (`GameTabBar.band`); the TabView,
        // a UIKit container, still reaches both side edges and hands each
        // tab the side insets, so a place's painting can bleed to the glass.
        VStack(spacing: 0) {
            tabs
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            GameTabBar(selection: $tab)
        }
        .preferredColorScheme(.light)
        // Athena over the whole shell, the bar included — her caret points
        // at a door in it. A full-screen cover is presented ABOVE this, so
        // the two that matter to the opening carry her themselves — she has
        // to be able to talk inside the Hall of Ka.
        .guide(store)
        .fullScreenCover(isPresented: $showTraining) {
            TrainingView()
                .environmentObject(store)
                .guide(store)
        }
        .fullScreenCover(isPresented: $showLabyrinth) {
            LabyrinthView()
                .environmentObject(store)
                .guide(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .onAppear { AudioLibrary.shared.playMusic(.island) }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.refreshTimedResources()
                AudioLibrary.shared.resumeMusic()
                // Apple is asked whether the sign-in still stands; a revoked
                // one drops the account and the sign-in screen returns.
                session.sceneBecameActive()
            case .background:
                // The file, then the cloud copy: the one moment the upload
                // does not wait for its minute.
                Task {
                    await store.saveNow()
                    await store.flushCloud()
                }
            case .inactive:
                Task { await store.saveNow() }
            @unknown default:
                break
            }
        }
    }

    /// The five tabs, each with the system tab bar hidden from inside it.
    private var tabs: some View {
        TabView(selection: $tab) {
            // The hub. Every landmark on it is a tab below — except the Hall
            // of Ka, which opens over whatever is showing — so the island is a
            // way in rather than a fifth place things live.
            IslandView(isActive: tab == .island) { destination in
                switch destination {
                case .training:
                    showTraining = true
                case .settings:
                    showSettings = true
                case .labyrinth:
                    showLabyrinth = true
                default:
                    if let next = Tab(destination) {
                        withAnimation { tab = next }
                    }
                }
            }
            .tabItem { Label("Island", systemImage: "sun.haze.fill") }
            .tag(Tab.island)
            .toolbar(.hidden, for: .tabBar)

            CampaignView()
                .tabItem { Label("Campaign", systemImage: "map.fill") }
                .tag(Tab.campaign)
            .toolbar(.hidden, for: .tabBar)

            ArenaView()
                .tabItem { Label("Arena", systemImage: "trophy.fill") }
                .tag(Tab.arena)
            .toolbar(.hidden, for: .tabBar)

            SummonView()
                .tabItem { Label("Summon", systemImage: "sparkles") }
                .tag(Tab.summon)
            .toolbar(.hidden, for: .tabBar)

            CollectionView()
                .tabItem { Label("Collection", systemImage: "person.3.fill") }
                .tag(Tab.collection)
            .toolbar(.hidden, for: .tabBar)
        }
        // Dim gold on the cream bar, and light everywhere: the shell was
        // `.dark` over cream screens, which is what left the tab bar ink
        // under a cream header.
        .tint(Theme.goldDim)
    }
}

/// The "More" menu: the places this screen leads to, and the three boards a
/// player reads — the account, sound and camera, and support.
///
/// Landscape shape: the strip carries the title, the demigod and the wallet;
/// the five places are one row of painted doors across the top; the three
/// boards fill the rest of the frame as columns, each scrolling under a fade.
///
/// Phase B (2026-09-22, evening; PLAN.md, *Phase B of the premium pass*).
/// Run 211's frame showed a player's screen carrying the developer's: a
/// "3D ASSETS 521/523" board of `anubis.usdz` rows and a CONSOLE tile with a
/// 554 badge, and the Sound & camera words cut off at the panel's foot with
/// nothing to say there was more. Now the doors are `MedallionIcon`s (the
/// island header's painted missions, events and allies; the bazaar and the
/// lessons by glyph in the same socket); the console and the model board sit
/// behind ONE Diagnostics row on the Support board, and the model board is
/// compiled into a debug build only; Reset account is a quiet row at the
/// foot of the Account board — where the genre keeps it, and where Apple's
/// account-deletion rule expects it — rather than a door beside Missions;
/// and every board scrolls and fades at its foot.
///
/// Height, on an iPhone 16 Pro in landscape: this is a sheet, so no tab bar
/// — 402 less the 52-point strip and the 21-point home indicator is 329, 16
/// of it padding. The doors take 74 since run 216 (their captions went) and
/// a gap of 8, and the boards the 231 left; the Account board's buttons are
/// a pinned foot of 85 under its scrolling rows.
struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var showSignOutConfirm = false
    @State private var showRestoreConfirm = false
    @State private var showBind = false
    @State private var showShop = false
    @State private var showMissions = false
    @State private var showEvents = false
    @State private var showSocial = false
    @State private var warBattle: BattleContext?
    @State private var soundOn = !AudioLibrary.shared.isMuted
    @State private var musicOn = !AudioLibrary.shared.isMusicMuted
    @AppStorage(CameraDirector.cinematicKey) private var cinematicCamera = false

    var body: some View {
        NavigationStack {
            GameScreen("More", subtitle: subtitle, dismiss: { dismiss() }) {
                BarCount(
                    value: "\(store.player.codex.count)/\(UnitDatabase.collectiblePool.count)",
                    systemImage: "book.closed.fill",
                    tint: Theme.gold
                )
                BarWallet(wallet: store.player.wallet)
            } content: {
                VStack(spacing: 8) {
                    destinations
                    HStack(alignment: .top, spacing: 8) {
                        accountPanel
                        soundPanel
                        supportPanel
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $showMissions) {
                MissionsView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showEvents) {
                EventsView(onClaim: { _ in store.claimEventGift() })
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSocial) {
                SocialView(
                    social: store.social,
                    onAttack: { target in
                        showSocial = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { warBattle = .guildWar(target) }
                    },
                    onClaim: { grants in _ = store.receive(grants) }
                )
                .environmentObject(store)
            }
            .fullScreenCover(item: $warBattle) { context in
                if case .guildWar(let target) = context, let engine = store.startWarAttack(target) {
                    BattleView(model: BattleViewModel(engine: engine, context: context, store: store))
                        .environmentObject(store)
                } else {
                    EmptyState(icon: "person.3", title: "No team", message: "Set an offence team in the Arena first.")
                        .onTapGesture { warBattle = nil }
                }
            }
            .sheet(isPresented: $showShop) {
                ShopView()
                    .environmentObject(store)
            }
            .confirmationDialog(
                "Delete this account?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    // The sheet goes first, then the store: the new game's
                    // shell replaces the whole screen under it.
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        Task { await session.startOver() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every unit, relic and clear is erased on this phone and in \(cloudName), and the game starts over from the first summon. The old save is kept aside on this phone, not deleted.")
            }
            .confirmationDialog(
                "Sign out of Pantheon?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    // The sheet goes first, then the store: the sign-in
                    // screen replaces the whole shell under it.
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        Task { await session.signOut() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your progress stays on this phone and in \(cloudName). Sign in again with the same Apple ID to pick up where you left off.")
            }
            .confirmationDialog(
                "Restore the \(cloudName) save?",
                isPresented: $showRestoreConfirm,
                titleVisibility: .visible
            ) {
                Button("Restore from \(cloudName)", role: .destructive) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        Task { await session.restoreFromCloud() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This phone's save is replaced by the one in \(cloudName). The replaced save is kept aside on this phone, not deleted.")
            }
            .sheet(isPresented: $showBind) {
                BindAppleSheet { credential in
                    Task { await session.bindGuestToApple(credential) }
                }
            }
        }
    }

    private var subtitle: String {
        "\(store.player.displayName) · Level \(store.player.level)"
    }

    // MARK: - Where this screen leads

    /// The five places as one row of doors. Two rows of four horizontal tiles
    /// were a glyph plate, a name and a caption squeezed side by side, and
    /// eight across one row left 45 points for a name (run 204: "D", "C",
    /// "EVE…"); a door with the medallion ABOVE its name needs only its
    /// widest line — "Weekly boosts", 74 points — so five fit one row at 139
    /// apiece on a 16 Pro and 122 on an SE, which is also the genre's menu:
    /// an object over its word.
    private var destinations: some View {
        HStack(spacing: 8) {
            Button {
                press { showMissions = true }
            } label: {
                door(title: "Missions", icon: "scroll.fill", art: "missions", badge: store.claimableRewards)
            }
            .buttonStyle(PlateButtonStyle())

            Button {
                press { showEvents = true }
            } label: {
                door(title: "Events", icon: "calendar", art: "events",
                     badge: EventCalendar.claimableCount(player: store.player))
            }
            .buttonStyle(PlateButtonStyle())

            Button {
                press { showSocial = true }
            } label: {
                door(title: "Allies", icon: "person.2.fill", art: "allies", badge: store.social.pendingCount)
            }
            .buttonStyle(PlateButtonStyle())

            Button {
                press { showShop = true }
            } label: {
                // The drachma's painted coin stack, the bazaar's own coin,
                // where a flat SF shopping bag stood beside three painted
                // objects (run 216).
                door(title: "Bazaar", icon: "bag.fill", itemKey: "drachma")
            }
            .buttonStyle(PlateButtonStyle())

            // Everything Athena has ever said, kept and replayable. The
            // owner, on the opening being skippable: "that would be a good
            // idea, let's expand on that" — so the tutorial is the manual.
            // Its old badge was the count of lessons read, which is not a
            // thing waiting to be taken; the count is the Lessons screen's
            // own subtitle.
            NavigationLink {
                LessonsView()
                    .environmentObject(store)
            } label: {
                door(title: "Lessons", icon: "book.fill", itemKey: ItemArt.key(scroll: .unknown))
            }
            .buttonStyle(PlateButtonStyle())
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The tap every door on this screen makes: a light haptic and the tap
    /// sound, then the door.
    private func press(_ open: () -> Void) {
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap)
        open()
    }

    /// One door: the painted object in its dark socket (`MedallionIcon` at
    /// 38 — its own painting, or the closest painted item, or its glyph in
    /// pale gold) over its name in Cinzel at 13, at its own width so
    /// nothing is cut, on the Missions rows' marble. A count waiting to be
    /// taken is the island header's red badge on the medallion's shoulder,
    /// so the same thing reads the same on both screens. No caption since
    /// run 216: the object and the name carry the door, and the 20 points
    /// the caption line took are what the boards below needed to show the
    /// Bind button whole.
    private func door(
        title: String,
        icon: String,
        art: String? = nil,
        itemKey: String? = nil,
        badge: Int = 0
    ) -> some View {
        VStack(spacing: 4) {
            MedallionIcon(key: art ?? "", glyph: icon, size: 38, glyphTint: Theme.onGlassGold, itemKey: itemKey)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        waitingBadge(badge)
                            .offset(x: 8, y: -3)
                    }
                }
            Text(title.uppercased())
                .font(Theme.title(13))
                .tracking(0.8)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(MarbleRowPlate(radius: Theme.tightCorner))
        .contentShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Red, not another gold pill beside a gold object: the one thing on the
    /// screen that must not be missed, drawn as the island header draws it.
    private func waitingBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(Theme.numeric(11.5).weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(Capsule().fill(Theme.danger))
            .overlay(Capsule().strokeBorder(Theme.surfaceHigh, lineWidth: 1))
    }

    // MARK: - The boards

    /// The account's rows scroll under a fade; its ACTIONS are a pinned foot
    /// below them (run 216): inside the fading board, Bind to Apple ID — the
    /// guest's one action — sat bisected at the board's foot and washed to a
    /// pale ghost that read as disabled. The rows keep only what the screen
    /// does not already say: the name and the level are the strip's
    /// subtitle, the codex its count.
    private var accountPanel: some View {
        SectionPanel(title: "Account", accessory: nil) {
            VStack(spacing: 6) {
                FadingBoard {
                    VStack(spacing: 5) {
                        row("Account", accountLine)
                        // The key's tail, in capitals: what a support request
                        // quotes, and the tail of the save's record name in
                        // CloudKit.
                        row("Player ID", session.accounts.account?.playerCode ?? "—")
                        row("Total summons", "\(store.player.totalSummons)")
                        accountCaptions
                    }
                }
                VStack(spacing: 5) {
                    accountActions
                    resetRow
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The Apple name, "Apple ID" when Apple sent none, or the guest's line.
    private var accountLine: String {
        guard let account = session.accounts.account else { return "—" }
        switch account.provider {
        case .apple: return account.displayName ?? "Apple ID"
        case .guest: return "Guest — this phone only"
        }
    }

    /// What the account's buttons need said first: the foreign save's date,
    /// the guest's warning. They scroll with the rows; the buttons are the
    /// pinned foot.
    @ViewBuilder
    private var accountCaptions: some View {
        if let foreign = store.cloudSave?.foreign {
            caption("\(cloudName) holds a different save, from \(SettingsView.dayFormatter.string(from: foreign.modifiedAt)).")
        }
        if session.accounts.account?.isGuest ?? true {
            caption("A guest cannot sign back in; bind this phone's progress to your Apple ID.")
        }
    }

    /// Sign out for an Apple account; Bind to Apple ID for a guest, who could
    /// not sign back in; Restore from iCloud when the cloud holds a save of
    /// another lineage that this store will never overwrite.
    @ViewBuilder
    private var accountActions: some View {
        if store.cloudSave?.foreign != nil {
            PrimaryButton(title: "Restore from \(cloudName)", systemImage: "icloud.and.arrow.down", tint: Theme.info) {
                showRestoreConfirm = true
            }
        }
        if session.accounts.account?.isGuest ?? true {
            PrimaryButton(title: "Bind to Apple ID", systemImage: "person.crop.circle.badge.checkmark") {
                showBind = true
            }
        } else {
            PrimaryButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.goldDim) {
                showSignOutConfirm = true
            }
        }
    }

    /// Reset account (`AppSession.startOver`, behind its confirmation) as a
    /// quiet outlined row at the foot of the Account board (2026-09-22,
    /// phase B). It was a red-glyph door beside Missions and Bazaar in run
    /// 211 — the one irreversible thing on the screen, as loud as the daily
    /// ones. The genre keeps it inside the account's settings, and Apple asks
    /// for an account's deletion to be found in the account's place.
    private var resetRow: some View {
        Button {
            press { showResetConfirm = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 12, weight: .black))
                Text("Reset account")
                    .font(Theme.body(12).weight(.bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Theme.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.danger.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlateButtonStyle())
    }

    /// "iCloud" or "Pantheon Cloud": whichever keeps this account's copy.
    private var cloudName: String { store.cloudSave?.serviceName ?? "iCloud" }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var soundPanel: some View {
        SectionPanel(title: "Sound & camera", accessory: nil) {
            // Four points between the rows, not seven, and the camera's two
            // captions as one pair: the 18 points that buys are what keeps
            // the last caption off the bottom-left acanthus with the board
            // still whole at rest (run 217).
            FadingBoard(foot: boardAcanthus) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $soundOn) {
                        Text("Sound effects")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.gold)
                    .onChange(of: soundOn) { _, on in
                        AudioLibrary.shared.isMuted = !on
                        if on { AudioLibrary.shared.play(.uiConfirm) }
                    }
                    Toggle(isOn: $musicOn) {
                        Text("Music")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.gold)
                    .onChange(of: musicOn) { _, on in
                        AudioLibrary.shared.isMusicMuted = !on
                    }
                    caption("Effects mix with your own music and respect the silent switch.")
                    Toggle(isOn: $cinematicCamera) {
                        Text("Cinematic battle camera")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.gold)
                    // One line each (run 216 cut the old paragraph mid-word
                    // at the board's foot).
                    VStack(alignment: .leading, spacing: 1) {
                        caption("Off: one fixed view, the genre's way.")
                        caption("On: cuts, leans and orbits on skills.")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What a player needs when something goes wrong: the build they are on
    /// and ONE row to the diagnostics — which is also the owner's way to the
    /// `[ModelLibrary]` block (More → Diagnostics, CLAUDE.md). The Player ID
    /// a support request quotes is on the Account board. This column was the
    /// art pipeline's model board until phase B (2026-09-22); that board is
    /// behind the row now, in a debug build only (`DiagnosticsDesk`).
    private var supportPanel: some View {
        SectionPanel(title: "Support", accessory: nil) {
            FadingBoard(foot: boardAcanthus) {
                VStack(alignment: .leading, spacing: 8) {
                    row("Version", LaunchView.version)
                    NavigationLink {
                        diagnosticsDestination
                    } label: {
                        diagnosticsRow
                    }
                    .buttonStyle(PlateButtonStyle())
                    caption("Something wrong? Diagnostics copies or shares the log; send it with your Player ID.")
                    caption("Set in Cinzel and Manrope, under the SIL Open Font License.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The row to the diagnostics, a door in miniature: the glyph in the
    /// doors' dark socket, the name and what it does, a chevron.
    private var diagnosticsRow: some View {
        HStack(spacing: 8) {
            MedallionIcon(key: "", glyph: "waveform.path.ecg", size: 30, glyphTint: Theme.onGlassGold)
            VStack(alignment: .leading, spacing: 1) {
                Text("DIAGNOSTICS")
                    .font(Theme.title(13))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                Text("Copy or share the log")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Theme.goldDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(MarbleRowPlate(radius: Theme.tightCorner))
        .contentShape(Rectangle())
    }

    /// The console itself in a release build; in a debug build the desk that
    /// holds the console and the art pipeline's model board, which no player
    /// ever sees.
    @ViewBuilder
    private var diagnosticsDestination: some View {
        #if DEBUG
        DiagnosticsDesk()
        #else
        DiagnosticsView()
        #endif
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(11))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A label and its value. The value wraps to a second line rather than
    /// shrinking: it shrank to 0.7 before, which put an Apple name at eight
    /// points, under the numeric floor.
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            Text(value)
                .font(Theme.numeric(11.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The fade at the foot of a More board that scrolls, and the room its last
/// line keeps under it so it can scroll clear.
private let boardFade: CGFloat = 22

/// How far the painted panel's acanthus corner reaches up past the panel's
/// own padding: the room a board whose foot is its panel's foot keeps under
/// its last line. Run 217's Sound & camera caption stood on the bottom-left
/// scroll ("On: cuts, …" with its "O" in the leaves).
private let boardAcanthus: CGFloat = 16

/// The coordinate space a `FadingBoard` measures its content in.
private let fadingBoardSpace = "fadingBoard"

/// A board's body on More: it scrolls when it is taller than its board — and
/// says so only when it has to.
///
/// Run 211 stopped the Sound & camera paragraph mid-sentence at the panel's
/// edge with nothing to say it went on, so the body got a 22-point fade at
/// its foot and 22 empty points under its last line (2026-09-22, phase B).
/// Those 22 points were what overflowed: run 217's Sound & camera board and
/// the guest's note on the Account board both FIT their boards, and their
/// last lines stood ghosted in the fade, reading as disabled. So the body is
/// measured, as the unit sheet's `SheetPanelScroll` is: content that fits is
/// drawn whole with no fade at all; content that does not fades at the foot,
/// wears a small chevron there until its last line has been scrolled into
/// view, and keeps the fade's height under that line so it can scroll clear.
/// `foot` is room kept under the last line either way (`boardAcanthus` where
/// the board's foot is its panel's foot).
private struct FadingBoard<Content: View>: View {
    let foot: CGFloat
    let content: () -> Content
    /// The content's frame in the scroll's own space: its height against the
    /// viewport's says whether it overflows, its foot whether there is more
    /// below.
    @State private var contentFrame: CGRect = .zero
    @State private var viewportHeight: CGFloat = 0

    init(foot: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.foot = foot
        self.content = content
    }

    private var overflows: Bool { contentFrame.height > viewportHeight + 1 }
    private var moreBelow: Bool { overflows && contentFrame.maxY > viewportHeight + 2 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.trailing, 2)
            .padding(.bottom, foot)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(fadingBoardSpace))
                    Color.clear
                        .onAppear { contentFrame = frame }
                        .onChange(of: frame) { _, now in contentFrame = now }
                }
            )
            // Room for the last line to scroll clear of the fade — only when
            // there is a fade.
            .padding(.bottom, overflows ? max(0, boardFade - foot) : 0)
        }
        .coordinateSpace(name: fadingBoardSpace)
        .scrollBounceBehavior(.basedOnSize)
        .background(
            GeometryReader { proxy in
                let height = proxy.size.height
                Color.clear
                    .onAppear { viewportHeight = height }
                    .onChange(of: height) { _, now in viewportHeight = now }
            }
        )
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [Color.black, moreBelow ? Color.clear : Color.black], startPoint: .top, endPoint: .bottom)
                    .frame(height: boardFade)
            }
        )
        .overlay(alignment: .bottom) {
            if moreBelow {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.goldDim)
                    .frame(width: 30, height: 12)
                    .background(Capsule().fill(Theme.surfaceHigh.opacity(0.92)))
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 0.8))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

#if DEBUG
/// The debug build's diagnostics, behind More's one Diagnostics row
/// (2026-09-22, phase B): the console and the art pipeline's model board side
/// by side. The board — which characters still stand in as sprites — was a
/// third of More in run 211, a list of `anubis.usdz` rows on a player's
/// screen. It is the pipeline's, not the player's, so a release build does
/// not compile it and its Diagnostics row opens the console straight away.
/// Copy is here as well as in the console so the owner's one errand —
/// the `[ModelLibrary]` block into a chat — is still one tap past the row.
///
/// Pushed in More's navigation stack, which is a sheet: 329 points under the
/// strip on a 16 Pro, no tab bar. Internal rather than private only so the
/// CI tour can photograph where the model board went.
struct DiagnosticsDesk: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        GameScreen(
            "Diagnostics",
            subtitle: "Debug build: the log and the model board",
            dismiss: { dismiss() }
        ) {
            // The count is the Console panel's accessory; twice on one
            // screen was once too many (run 216).
            EmptyView()
        } content: {
            HStack(alignment: .top, spacing: 8) {
                consolePanel
                    .frame(width: 250)
                assetPanel
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
        }
    }

    private var consolePanel: some View {
        SectionPanel(title: "Console", accessory: "\(DiagnosticsLog.shared.count) lines") {
            VStack(alignment: .leading, spacing: 8) {
                note("Everything the app has printed since launch. The [ModelLibrary] block says what each model loaded as.")
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    deskRow(title: "Read the log", glyph: "text.alignleft", trailing: "chevron.right")
                }
                .buttonStyle(PlateButtonStyle())
                Button {
                    Juice.haptic(.light)
                    AudioLibrary.shared.play(.uiTap)
                    UIPasteboard.general.string = DiagnosticsLog.shared.text
                    copied = true
                } label: {
                    deskRow(
                        title: copied ? "Copied" : "Copy the log",
                        glyph: copied ? "checkmark" : "doc.on.doc.fill",
                        trailing: nil
                    )
                }
                .buttonStyle(PlateButtonStyle())
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Shows which characters still render as placeholders. This is the
    /// board the art pipeline works against — a unit turns green the moment
    /// its `.usdz` is in the bundle, with no code change.
    private var assetPanel: some View {
        SectionPanel(title: "3D assets", accessory: "\(shippedModels)/\(UnitDatabase.all.count)") {
            VStack(alignment: .leading, spacing: 6) {
                note("Green means a real model is in the bundle. Grey means the portrait is standing in as a sprite.")
                FadingBoard {
                    VStack(spacing: 4) {
                        ForEach(UnitDatabase.all) { blueprint in
                            let hasModel = ModelLibrary.shared.hasRealModel(blueprint.model.assetName)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(hasModel ? Theme.success : Theme.stroke)
                                    .frame(width: 7, height: 7)
                                Text(blueprint.name)
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(blueprint.model.assetName).usdz")
                                    .font(Theme.numeric(11.5))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shippedModels: Int {
        UnitDatabase.all.filter { ModelLibrary.shared.hasRealModel($0.model.assetName) }.count
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(11))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deskRow(title: String, glyph: String, trailing: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Theme.goldDim)
                .frame(width: 22)
            Text(title)
                .font(Theme.body(12).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.goldDim)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(MarbleRowPlate(radius: Theme.tightCorner))
        .contentShape(Rectangle())
    }
}
#endif

// MARK: - The launch

/// What the launch has warmed, for the bar, and whether the door is open.
///
/// The genre opens on a piece of key art with the game's name and a bar
/// that fills as the game loads. Ours is the same, with the bar tied to
/// real work — the unit and stage databases, the Labyrinth, the bundle's
/// index — and held no shorter than `minimum` seconds so the painting is
/// seen. Offline, so no "touch to start": that tap is for a server
/// handshake this game does not have.
@MainActor
final class LaunchProgress: ObservableObject {
    @Published private(set) var fraction: Double = 0
    @Published private(set) var step: String = "Registering the faces"
    @Published private(set) var finished = false

    /// The painting and the tip for this launch: the key art, painted for
    /// this screen (2026-09-12, the one image the owner authorised), or,
    /// in a bundle without it, one of the five banners in turn.
    let artName: String
    let tip: String

    /// The five pantheons' gods on a summit over a sea of cloud at dawn,
    /// 16:9, its lower third dark for the name and the bar.
    static let keyArt = "launch_key_art"

    static let paintings = [
        "banner_olympus_stirs", "banner_duat_opens", "banner_ravens_gather",
        "banner_eagle_rises", "banner_jade_court",
    ]

    static let tips = [
        "A Legend relic drops with four sub stats; a Normal has none until +3.",
        "Fire beats wind, wind beats water, water beats fire. Light and dark beat each other.",
        "Slots 1, 3 and 5 always carry flat ATK, DEF and HP. The even slots are the decision.",
        "Two pieces complete a stat set, four an effect set.",
        "A whetstone hones a sub stat; a gem replaces one. The raids drop both.",
        "Hard opens when Normal's boss falls, and Hell when Hard's.",
        "The same god burns as fire, freezes as water and strikes twice as wind.",
        "Power-up is sure to +3. After that a failed attempt keeps the level and spends the drachma.",
        "A relic can be sold from the chest's shelf before it ever reaches the bag.",
        "Every enemy wears a matchup arrow on your turn: green up, red down.",
    ]

    private var started = false

    init() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: "launchCount")
        defaults.set(count + 1, forKey: "launchCount")
        artName = BundleArt.exists(Self.keyArt) ? Self.keyArt : Self.paintings[count % Self.paintings.count]
        tip = Self.tips[count % Self.tips.count]
    }

    /// A frozen state, for the CI tour's frame.
    init(preview fraction: Double, step: String, art: String) {
        self.fraction = fraction
        self.step = step
        self.artName = art
        self.tip = Self.tips[0]
        self.started = true
    }

    /// Warms the game on a background task, one named step at a time, and
    /// opens the door no sooner than `minimum` seconds after the call.
    func run(minimum: TimeInterval = 2.6) {
        guard !started else { return }
        started = true
        let began = Date()
        Task.detached(priority: .userInitiated) { [weak self] in
            let steps: [(name: String, work: @Sendable () -> Void)] = [
                ("Waking the pantheon", { _ = UnitDatabase.summonPool.count }),
                ("Raising the stages", { _ = StageDatabase.allStages.count }),
                ("Opening the Labyrinth", { _ = DungeonDatabase.allLevels.count + DungeonDatabase.allFloors.count }),
                ("Reading the island", { _ = BundleArt.exists("island_bg") }),
            ]
            for (index, entry) in steps.enumerated() {
                await self?.advance(to: Double(index) / Double(steps.count), step: entry.name)
                entry.work()
            }
            let wait = max(0, minimum - Date().timeIntervalSince(began))
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            await self?.finish()
        }
    }

    private func advance(to fraction: Double, step: String) {
        withAnimation(.easeInOut(duration: 0.5)) { self.fraction = fraction }
        self.step = step
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.4)) { fraction = 1 }
        step = "Enter"
        withAnimation(.easeInOut(duration: 0.9)) { finished = true }
    }
}

/// The loading screen: one of the five banner paintings full-bleed and
/// anchored to its top so the faces stay, pushed in slowly, ink at the top
/// and the bottom, embers rising, the name in Cinzel on the clouds, the
/// five pantheons under it, the bar and a tip. Sits over `RootView` until
/// `LaunchProgress.finished` and dissolves.
struct LaunchView: View {
    @ObservedObject var progress: LaunchProgress
    @State private var revealed = false
    @State private var zoom: CGFloat = 1.0

    private let cream = Color(hex: "#EBE2CF")

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.ink
                BundleImage(name: progress.artName)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .clipped()
                    .scaleEffect(zoom, anchor: .top)
                    .opacity(revealed ? 1 : 0)
                LinearGradient(
                    stops: [
                        .init(color: Theme.ink.opacity(0.25), location: 0),
                        .init(color: .clear, location: 0.2),
                        .init(color: .clear, location: 0.42),
                        .init(color: Theme.ink.opacity(0.9), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                LaunchEmbers()
                VStack(spacing: 0) {
                    // 0.58 of the height: on the key art the five figures fill
                    // the top half and the summit's dark base is here; the
                    // mock at 0.50 put the name across the thunder god's
                    // waist and 0.64 crowded the bar.
                    Spacer()
                        .frame(height: geo.size.height * 0.58)
                    wordmark
                    Spacer(minLength: 8)
                    footer
                        .padding(.bottom, 14)
                }
                .padding(.horizontal, 24)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { revealed = true }
            withAnimation(.easeInOut(duration: 9)) { zoom = 1.07 }
        }
    }

    private var wordmark: some View {
        VStack(spacing: 8) {
            Text("PANTHEON")
                .font(Theme.display(44))
                .tracking(9)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#FFF0C2"), Color(hex: "#F3D27A"), Color(hex: "#B08A2E")],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.7), radius: 6, y: 3)
            HStack(spacing: 10) {
                LinearGradient(colors: [.clear, Theme.gold], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 110, height: 1)
                RelicSetEmblem(set: .fates, size: 14, tint: Theme.gold, lineSeal: true)
                LinearGradient(colors: [Theme.gold, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 110, height: 1)
            }
            Text("EGYPT  ·  GREECE  ·  NORSE  ·  ROME  ·  THE JADE COURT")
                .font(Theme.body(10).weight(.bold))
                .tracking(2.2)
                .foregroundStyle(cream.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 12)
        .animation(.easeOut(duration: 1.0).delay(0.5), value: revealed)
    }

    private var footer: some View {
        VStack(spacing: 7) {
            Text(progress.step.uppercased())
                .font(Theme.body(10).weight(.bold))
                .tracking(2)
                .foregroundStyle(Theme.gold)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 280, height: 3)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.goldDim, Color(hex: "#FFE49B")], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, 280 * progress.fraction), height: 3)
            }
            .frame(width: 280)
            Text(progress.tip)
                .font(Theme.body(11))
                .foregroundStyle(cream.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomTrailing) {
            Text(Self.version)
                .font(Theme.body(9))
                .foregroundStyle(cream.opacity(0.5))
        }
    }

    /// "v1.0 (211)": the loading screen's corner, and More's Support board
    /// (2026-09-22, phase B), where a support request reads it.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (\(build))"
    }
}

/// Two dozen gold motes rising through the frame, each on a path of its
/// own from a seeded draw, redrawn every frame so the painting breathes.
private struct LaunchEmbers: View {
    private struct Mote {
        let x: Double
        let speed: Double
        let phase: Double
        let size: Double
        let sway: Double
    }

    private static let motes: [Mote] = (0..<26).map { index in
        var rng = SeededRandom(seed: 700 + UInt64(index))
        return Mote(
            x: rng.double(in: 0.02...0.98),
            speed: rng.double(in: 0.05...0.11),
            phase: rng.double(in: 0...1),
            size: rng.double(in: 1.5...3.2),
            sway: rng.double(in: 8...26)
        )
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for (index, mote) in Self.motes.enumerated() {
                    let travel = (t * mote.speed + mote.phase).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1.05 - travel * 1.1)
                    let x = size.width * mote.x + sin(t * 0.7 + Double(index)) * mote.sway
                    let pulse = 0.25 + 0.55 * (0.5 + 0.5 * sin(t * 2.1 + Double(index) * 1.3))
                    let fade = travel < 0.1 ? travel / 0.1 : (travel > 0.85 ? (1 - travel) / 0.15 : 1)
                    let rect = CGRect(x: x - mote.size, y: y - mote.size, width: mote.size * 2, height: mote.size * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(hex: "#FFD678").opacity(pulse * fade)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The tab bar

/// The game's own tab bar (2026-09-22): five painted doors on a marble band,
/// the chosen one lifted, gold-rimmed and lit — the iOS tab bar with its
/// grey symbols was the loudest "app, not game" note on every screen
/// (PLAN.md, *The premium pass*).
///
/// The doors are PAINTED since phase B (2026-09-22, evening; PLAN.md, *The
/// painted doors*): each is `MedallionIcon`, the tab's object (`tab_<art>`,
/// painted on one sheet with the island header's four) in a dark bronze
/// socket. The socket is dark on purpose, on a cream band: every painted
/// icon in the game was painted on black and keyed off it, and on the cream
/// discs the mock left a dark halo round a glow; the old gold selected disc
/// swallowed a gold object whole. So the art is full colour in both states
/// and the selection is the rim, the light, the glow and a 1.1 lift from
/// the bottom edge, never a dimmed picture. Run 211's frame had the five
/// SF symbols in cream discs that all but dissolved into the band.
struct GameTabBar: View {
    @Binding var selection: RootView.Tab
    /// Read for `tabBarDimmed` alone: a modal card over a tab screen
    /// (`View.dimsTabBar(_:)`) dims the band and takes its taps.
    @EnvironmentObject private var store: GameStore

    static let height: CGFloat = 58

    /// One door: its tab, its label, its glyph (drawn in the same socket
    /// until the painting ships) and its painting's key in `ChromeArt`.
    private struct TabItem: Identifiable {
        let tab: RootView.Tab
        let title: String
        let glyph: String
        let art: String
        var id: String { title }
    }

    private static let items: [TabItem] = [
        TabItem(tab: .island, title: "Island", glyph: "sun.haze.fill", art: "island"),
        TabItem(tab: .campaign, title: "Campaign", glyph: "map.fill", art: "campaign"),
        TabItem(tab: .arena, title: "Arena", glyph: "trophy.fill", art: "arena"),
        TabItem(tab: .summon, title: "Summon", glyph: "sparkles", art: "summon"),
        TabItem(tab: .collection, title: "Collection", glyph: "person.3.fill", art: "collection"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.items) { item in
                button(item)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(band)
        // Under a card (the stage popup, the sweep receipt) the bar recedes
        // with the screen: the card's own 0.55 black, over the whole band,
        // and no door takes a tap while it stands (run 216: a bright, live
        // bar under a dimmed map read as a card pasted between two screens,
        // and a tap on a door switched screens with the card still up).
        .overlay {
            if store.tabBarDimmed {
                Color.black.opacity(0.55)
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(!store.tabBarDimmed)
        .animation(.easeOut(duration: 0.2), value: store.tabBarDimmed)
    }

    /// The door: the medallion at 38 over its name in Cinzel at 13 — 38, one
    /// point and a 17.6-point line are 56.6 of the band's 58. The label is
    /// written at 13 because that is what it drew: the old `title(10)` was
    /// floored to 13 and only read as if it were smaller.
    private func button(_ item: TabItem) -> some View {
        let isOn = selection == item.tab
        return Button {
            guard !isOn else { return }
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { selection = item.tab }
        } label: {
            VStack(spacing: 1) {
                // Anchored at the bottom, so the chosen door rises about
                // four points over the band's gold rule instead of growing
                // down into its own name.
                MedallionIcon(key: item.art, glyph: item.glyph, size: 38, isOn: isOn)
                    .scaleEffect(isOn ? 1.12 : 1, anchor: .bottom)
                // The chosen door's name in ink, the rest in a quieter brown
                // (run 216: goldDeep against textSecondary measured as two
                // near-identical dark inks, so the label never changed).
                Text(item.title.uppercased())
                    .font(Theme.title(13))
                    .tracking(0.8)
                    .foregroundStyle(isOn ? Theme.ink : Theme.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Athena's caret finds a tab by this name: lesson `first_relic`
        // points at "tab_collection", which no view had registered, so the
        // caret fell back to a line at the foot with nothing under it.
        .guideAnchor("tab_\(item.art)")
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var band: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: "#FBF5E8"), Theme.surface, Color(hex: "#DCCFB4")],
                startPoint: .top,
                endPoint: .bottom
            )
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.goldDeep.opacity(0.0), Theme.gold, Theme.goldDeep.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, y: -3)
        // Edge to edge: with the bottom alone, run 211's island frame showed
        // the painting down to the band's midline in both bottom corners and
        // a white strip under it, beside a band that stopped 62 points short
        // of each edge. The doors stay inside the safe area; only the marble
        // runs out to the glass.
        .ignoresSafeArea(edges: [.horizontal, .bottom])
    }
}
