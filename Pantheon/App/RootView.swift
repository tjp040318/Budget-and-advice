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
        // Dim gold on the cream bar, and light everywhere: the shell was
        // `.dark` over cream screens, which is what left the tab bar ink
        // under a cream header.
        .tint(Theme.goldDim)
        .preferredColorScheme(.light)
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
                    caption: "Dailies, feats, the gift · also on the island",
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
                    caption: "Scrolls, energy, relics · also on the island",
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
                row("Codex", "\(store.player.codex.count) / \(UnitDatabase.collectiblePool.count)")
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

    /// The painting and the tip for this launch. The five banners take
    /// turns, so the screen is not the same twice running.
    let artName: String
    let tip: String

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
        artName = Self.paintings[count % Self.paintings.count]
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
                    Spacer()
                        .frame(height: geo.size.height * 0.5)
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
                RelicSetEmblem(set: .fates, size: 14, tint: Theme.gold)
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

    private static var version: String {
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
