import SwiftUI

/// The app's tab shell.
struct RootView: View {
    @EnvironmentObject private var store: GameStore
    @State private var tab: Tab = .island
    @State private var showTraining = false
    @Environment(\.scenePhase) private var scenePhase

    enum Tab: Hashable {
        case island, campaign, arena, summon, collection, settings

        init(_ destination: IslandDestination) {
            switch destination {
            case .campaign: self = .campaign
            case .arena: self = .arena
            case .summon: self = .summon
            case .collection, .training: self = .collection
            case .settings: self = .settings
            }
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            // The hub. Every landmark on it is a tab below — except the Hall
            // of Ka, which opens over whatever is showing — so the island is a
            // way in rather than a fifth place things live.
            IslandView { destination in
                if destination == .training {
                    showTraining = true
                } else {
                    withAnimation { tab = Tab(destination) }
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

            SettingsView()
                .tabItem { Label("More", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showTraining) {
            TrainingView()
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

/// Account, diagnostics and the asset-pipeline status board.
struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showResetConfirm = false
    @State private var soundOn = !AudioLibrary.shared.isMuted
    @State private var musicOn = !AudioLibrary.shared.isMusicMuted

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    accountPanel
                    soundPanel
                    diagnosticsPanel
                    assetStatusPanel
                    dangerPanel
                }
                .padding(16)
            }
            .screen("More")
        }
    }

    private var accountPanel: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "Account")
            row("Summoner", store.player.displayName)
            row("Level", "\(store.player.level)")
            row("Units", "\(store.player.units.count)")
            row("Relics", "\(store.player.relics.count)")
            row("Total summons", "\(store.player.totalSummons)")
            row("Codex", "\(store.player.codex.count) / \(UnitDatabase.summonPool.count)")
        }
        .padding(14)
        .panelBackground()
    }

    private var soundPanel: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "Sound")
            Toggle(isOn: $soundOn) {
                Text("Sound effects")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.gold)
            .onChange(of: soundOn) { _, on in
                AudioLibrary.shared.isMuted = !on
                if on { AudioLibrary.shared.play(.uiConfirm) }
            }
            Toggle(isOn: $musicOn) {
                Text("Music")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.gold)
            .onChange(of: musicOn) { _, on in
                AudioLibrary.shared.isMusicMuted = !on
            }
            Text("Effects mix with your own music and respect the silent switch.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .panelBackground()
    }

    /// Shows which characters still render as placeholders. This is the board
    /// the art pipeline works against — a unit turns green the moment its
    /// `.usdz` is in the bundle, with no code change.
    private var assetStatusPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: "3D assets")
            Text("Green means a real model is in the bundle. Grey means the portrait is standing in as a sprite.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)

            ForEach(UnitDatabase.all) { blueprint in
                let hasModel = ModelLibrary.shared.hasRealModel(blueprint.model.assetName)
                HStack {
                    Circle()
                        .fill(hasModel ? Theme.success : Theme.stroke)
                        .frame(width: 8, height: 8)
                    Text(blueprint.name)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(blueprint.model.assetName).usdz")
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(14)
        .panelBackground()
    }

    /// The console, for a phone with no Xcode attached: the `[ModelLibrary]`
    /// block and everything else the app printed, with Copy and Share.
    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: "Diagnostics")
            NavigationLink {
                DiagnosticsView()
            } label: {
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(Theme.gold)
                    Text("Console log")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(DiagnosticsLog.shared.count) lines")
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text("What the app printed since launch, ready to copy or share into a chat.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .panelBackground()
    }

    private var dangerPanel: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Danger zone")
            PrimaryButton(title: "Reset account", systemImage: "trash.fill", tint: Theme.danger) {
                showResetConfirm = true
            }
        }
        .padding(14)
        .panelBackground()
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

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.numeric(13)).foregroundStyle(Theme.textPrimary)
        }
    }
}
