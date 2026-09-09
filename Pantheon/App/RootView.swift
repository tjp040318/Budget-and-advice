import SwiftUI

/// The app's tab shell.
struct RootView: View {
    @EnvironmentObject private var store: GameStore
    @State private var tab: Tab = .island
    @State private var showTraining = false
    @State private var showSettings = false
    @State private var showLabyrinth = false
    @Environment(\.scenePhase) private var scenePhase

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
        TabView(selection: $tab) {
            // The hub. Every landmark on it is a tab below — except the Hall
            // of Ka, which opens over whatever is showing — so the island is a
            // way in rather than a fifth place things live.
            IslandView { destination in
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

            CampaignView()
                .tabItem { Label("Campaign", systemImage: "map.fill") }
                .tag(Tab.campaign)

            ArenaView()
                .tabItem { Label("Arena", systemImage: "trophy.fill") }
                .tag(Tab.arena)

            SummonView()
                .tabItem { Label("Summon", systemImage: "sparkles") }
                .tag(Tab.summon)

            CollectionView()
                .tabItem { Label("Collection", systemImage: "person.3.fill") }
                .tag(Tab.collection)
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showTraining) {
            TrainingView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showLabyrinth) {
            LabyrinthView()
                .environmentObject(store)
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
            case .background, .inactive:
                Task { await store.saveNow() }
            @unknown default:
                break
            }
        }
    }
}

/// Account, diagnostics and the asset-pipeline status board: the "More" menu.
///
/// Landscape shape: the strip carries the title, the summoner and the wallet;
/// the four places this screen leads to are a band of tiles across the top,
/// each one the size of a thumb; and the three boards that only report —
/// account, sound and camera, and the model pipeline — fill the rest of the
/// frame as three columns. The old layout stacked seven panels under a
/// navigation bar and scrolled the lot.
struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var showShop = false
    @State private var showMissions = false
    @State private var soundOn = !AudioLibrary.shared.isMuted
    @State private var musicOn = !AudioLibrary.shared.isMusicMuted
    @AppStorage(CameraDirector.cinematicKey) private var cinematicCamera = false

    var body: some View {
        NavigationStack {
            GameScreen("More", subtitle: subtitle, dismiss: { dismiss() }) {
                BarCount(
                    value: "\(store.player.codex.count)/\(UnitDatabase.summonPool.count)",
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
                        assetStatusPanel
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
            .sheet(isPresented: $showShop) {
                ShopView()
                    .environmentObject(store)
            }
            .confirmationDialog(
                "Delete this account?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { store.resetAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every unit, relic and clear is erased. There is no undo and no cloud backup yet.")
            }
        }
    }

    private var subtitle: String {
        "\(store.player.displayName) · Level \(store.player.level)"
    }

    // MARK: - Where this screen leads

    /// The four destinations as tiles rather than as three panels each holding
    /// one button and a paragraph. Four across a landscape phone.
    private var destinations: some View {
        HStack(spacing: 8) {
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showMissions = true
            } label: {
                tileFace(
                    title: "Missions",
                    caption: "Dailies, feats, the gift",
                    icon: "scroll.fill",
                    tint: Theme.gold,
                    badge: store.claimableRewards > 0 ? "\(store.claimableRewards)" : nil
                )
            }
            .buttonStyle(PlateButtonStyle())

            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showShop = true
            } label: {
                tileFace(
                    title: "Bazaar",
                    caption: "Scrolls, energy, relics",
                    icon: "bag.fill",
                    tint: Theme.info,
                    badge: nil
                )
            }
            .buttonStyle(PlateButtonStyle())

            NavigationLink {
                DiagnosticsView()
            } label: {
                tileFace(
                    title: "Console log",
                    caption: "Copy or share the log",
                    icon: "terminal.fill",
                    tint: Theme.success,
                    badge: "\(DiagnosticsLog.shared.count)"
                )
            }
            .buttonStyle(PlateButtonStyle())

            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showResetConfirm = true
            } label: {
                tileFace(
                    title: "Reset account",
                    caption: "Erase every unit and clear",
                    icon: "trash.fill",
                    tint: Theme.danger,
                    badge: nil
                )
            }
            .buttonStyle(PlateButtonStyle())
        }
        .frame(height: 64)
    }

    /// One destination tile: a tinted glyph plate, the name, what it holds,
    /// and a count when there is one to show.
    private func tileFace(
        title: String,
        caption: String,
        icon: String,
        tint: Color,
        badge: String?
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.16))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 0.5)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(Theme.title(12))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let badge {
                Text(badge)
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint))
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(
                    LinearGradient(colors: [Theme.surfaceRaised, Theme.surface],
                                   startPoint: .top, endPoint: .bottom)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }

    // MARK: - The boards

    private var accountPanel: some View {
        SectionPanel(title: "Account", accessory: "Lv.\(store.player.level)") {
            VStack(spacing: 5) {
                row("Summoner", store.player.displayName)
                row("Level", "\(store.player.level)")
                row("Units", "\(store.player.units.count)")
                row("Relics", "\(store.player.relics.count)")
                row("Total summons", "\(store.player.totalSummons)")
                row("Codex", "\(store.player.codex.count) / \(UnitDatabase.summonPool.count)")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var soundPanel: some View {
        SectionPanel(title: "Sound & camera", accessory: nil) {
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
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
                    caption("Off keeps one fixed view of the whole field, the way the genre does it; only an ultimate pushes in for a moment, and hits shake. On lets the camera cut, lean and orbit on skills.")
                }
                .padding(.trailing, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shows which characters still render as placeholders. This is the board
    /// the art pipeline works against — a unit turns green the moment its
    /// `.usdz` is in the bundle, with no code change.
    private var assetStatusPanel: some View {
        SectionPanel(title: "3D assets", accessory: "\(shippedModels)/\(UnitDatabase.all.count)") {
            VStack(alignment: .leading, spacing: 6) {
                caption("Green means a real model is in the bundle. Grey means the portrait is standing in as a sprite.")
                ScrollView {
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
                                    .font(Theme.numeric(9))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shippedModels: Int {
        UnitDatabase.all.filter { ModelLibrary.shared.hasRealModel($0.model.assetName) }.count
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(10))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
