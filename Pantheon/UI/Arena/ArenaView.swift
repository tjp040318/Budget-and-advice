import SwiftUI

/// PvP: your standing, your defence, and the list of people to attack.
///
/// Landscape shape. The page used to be one `ScrollView` under a navigation
/// bar: the rank panel, the two team panels, then the challengers, so a phone
/// showed the rank and about one opponent. It is now two columns under the
/// strip — your side on the left (the rank card, then both teams), the
/// challenger list on the right with the full height of the frame — and
/// nothing but that list scrolls.
struct ArenaView: View {
    @EnvironmentObject private var store: GameStore
    @State private var opponents: [ArenaOpponent] = []
    @State private var pendingEngines: [String: BattleEngine] = [:]
    @State private var battle: BattleContext?
    @State private var showDefensePicker = false
    @State private var showOffensePicker = false
    @State private var defenseRating: Double?
    /// True while the challengers are being built off the main thread, so a
    /// second appearance does not start a second build over the top of the
    /// first.
    @State private var isRefreshing = false
    /// True while the defence rating is being simulated. Five whole battles
    /// run to a conclusion, so this one is emphatically not a main-thread job
    /// either — the Simulate button used to freeze the screen for as long as
    /// it took.
    @State private var isRating = false

    private var record: ArenaRecord { store.player.arena }

    /// The challenger rows' cards. They cross half a landscape frame beside
    /// the name block and the attack capsule, which is what sets the number.
    /// Your own two team panels are a quarter of the frame each and size their
    /// cards to fit — see `teamRow`.
    private let cardSize: CGFloat = 38

    var body: some View {
        NavigationStack {
            GameScreen("Arena", subtitle: "\(record.tier.displayName) · \(record.points) pts") {
                BarCount(
                    value: "\(record.attacksRemaining)/\(record.maxAttacks)",
                    systemImage: "flame.fill",
                    tint: record.attacksRemaining > 0 ? Theme.gold : Theme.textSecondary
                )
                BarButton(
                    title: isRating ? "Simulating" : "Simulate",
                    systemImage: "waveform.path.ecg",
                    tint: isRating ? Theme.textSecondary : Theme.info
                ) {
                    rateDefence()
                }
                BarButton(title: "Refresh", systemImage: "arrow.clockwise") {
                    refresh()
                }
                BarWallet(
                    wallet: store.player.wallet,
                    shows: [.energy, .divinity, .drachma, .laurels]
                )
            } content: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        standingPanel
                        HStack(alignment: .top, spacing: 8) {
                            defensePanel
                            offensePanel
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    opponentList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
            }
            .onAppear(perform: refresh)
            .sheet(isPresented: $showDefensePicker) {
                TeamPickerView(slot: .arenaDefense, maxSize: ArenaService.teamSize)
                    .environmentObject(store)
                    .onDisappear { defenseRating = nil }
            }
            .sheet(isPresented: $showOffensePicker) {
                TeamPickerView(slot: .arenaOffense, maxSize: ArenaService.teamSize)
                    .environmentObject(store)
            }
            .fullScreenCover(item: $battle) { context in
                battleScreen(for: context)
            }
        }
    }

    /// Building the challengers is not free: five opponents, each a team of
    /// five units rolled out of the summon pool with six generated relics
    /// apiece and every one of them resolved through `ProgressionService`. It
    /// ran on the main thread inside `onAppear`, so the Arena could not draw
    /// its first frame until it finished — the owner felt it as "it did get
    /// really laggy after I clicked on Arena" on 2026-09-10, and the CI tour
    /// photographed the screen as pure black, with even the tour's own overlay
    /// missing, which is what a view looks like before its first frame.
    ///
    /// It now runs off the main thread and lands when it lands. The screen
    /// draws immediately with whatever it already had, which after the first
    /// visit is the previous list, and the challengers appear a moment later.
    /// The pool is deterministic in the day and the player's points, so the
    /// list that arrives is the same one that would have blocked the frame.
    private func refresh() {
        let entered = Perf.begin()
        store.refreshTimedResources()
        Perf.end(entered, "arena: refreshTimedResources", over: 8)
        // The player's own four fight in every arena bout, so their meshes
        // and clips go into the model cache while the challengers are
        // still being built; the chosen opponent's follow at Fight.
        ModelLibrary.shared.warm(store.team(store.player.arenaOffenseTeam).map { $0.blueprint.model }, crowded: true)
        guard !isRefreshing else { return }
        isRefreshing = true
        // The record and the day are read HERE, on the main actor, and handed
        // to the task by value. `ArenaRecord` and `ArenaOpponent` are both
        // Sendable and `ArenaService.pool` is a pure function of them, so the
        // build genuinely happens off the main thread. Reaching back into the
        // store from inside the task would have put the work straight back
        // where it came from.
        let record = store.player.arena
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        // The card size in pixels, read here because `UIScreen` is the main
        // thread's; the task decodes every challenger's portrait at it before
        // the list is handed over, so the list draws from the cache.
        let cardPixels = Int((cardSize * UIScreen.main.scale).rounded(.up))
        Task.detached(priority: .userInitiated) {
            let started = Perf.begin()
            let built = ArenaService.pool(for: record, day: day)
                .filter { !record.defeatedOpponentIDs.contains($0.id) }
            Perf.end(started, "arena: challenger pool", over: 1)
            BundleArt.warmThumbnails(
                built.flatMap { opponent in
                    opponent.team.map { $0.blueprint.model.portraitName(awakened: $0.unit.isAwakened) }
                },
                maxPixel: cardPixels
            )
            await MainActor.run {
                let landed = Perf.begin()
                opponents = built
                isRefreshing = false
                Perf.end(landed, "arena: challengers handed to the view", over: 1)
            }
        }
    }

    /// Rating the defence runs five complete battles. On the main thread that
    /// is a freeze with no spinner and no explanation, so it runs off it and
    /// the button says so while it works.
    private func rateDefence() {
        guard !isRating else { return }
        isRating = true
        let player = store.player
        Task.detached(priority: .userInitiated) {
            let rating = ArenaService.rateDefense(player: player)
            await MainActor.run {
                defenseRating = rating
                isRating = false
            }
        }
    }

    @ViewBuilder
    private func battleScreen(for context: BattleContext) -> some View {
        if case .arena(let opponent) = context, let engine = pendingEngines[opponent.id] {
            BattleView(model: BattleViewModel(engine: engine, context: context, store: store))
                .environmentObject(store)
                .onDisappear { refresh() }
        } else {
            Color.black.ignoresSafeArea().onAppear { battle = nil }
        }
    }

    // MARK: - Standing

    /// The rank card. It takes whatever height the two team panels leave, so
    /// the tier, the climb to the next one and the day's laurels sit spread
    /// down the column instead of stacked at the top of a scroll.
    private var standingPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.tier.displayName.uppercased())
                .font(Theme.display(28))
                .foregroundStyle(record.tier.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(record.points) rank points")
                .font(Theme.numeric(12))
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 2)

            if let next = nextTier {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Next: \(next.displayName)")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(next.threshold - record.points) to go")
                            .font(Theme.numeric(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    StatBar(
                        value: Double(record.points - record.tier.threshold),
                        maximum: Double(max(1, next.threshold - record.tier.threshold)),
                        tint: record.tier.color,
                        height: 5
                    )
                }
            }

            Spacer(minLength: 2)

            HStack {
                Text("\(record.wins)W / \(record.losses)L")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Best \(record.highestPoints)")
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("+\(record.tier.dailyLaurels) laurels daily")
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.success)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .frame(maxHeight: .infinity)
        .panelBackground()
    }

    private var nextTier: ArenaTier? {
        ArenaTier.allCases.first { $0.threshold > record.points }
    }

    /// The power of the team that actually attacks. `store.totalPower` is the
    /// sum of the player's best *five* units, and an arena team is four, so
    /// comparing a challenger against it biased every row toward green — an
    /// offence team that is not your top four was reported as an easy fight.
    ///
    /// Reading it resolves four units out of their relics, so it is read once
    /// in `opponentList` and handed down to the rows: a computed property has
    /// no cache, and five challengers asking one each would resolve twenty.
    private var offensePower: Int {
        store.team(store.player.arenaOffenseTeam).reduce(0) { $0 + $1.power }
    }

    // MARK: - Teams

    private var defensePanel: some View {
        SectionPanel(title: "Defence", accessory: ratingText) {
            teamRow(store.team(store.player.arenaDefenseTeam)) { showDefensePicker = true }
        }
        .frame(maxWidth: .infinity)
    }

    private var ratingText: String? {
        guard let defenseRating else { return nil }
        return "holds \(Int(defenseRating * 100))%"
    }

    private var offensePanel: some View {
        SectionPanel(
            title: "Offence",
            accessory: "Power \(offensePower)"
        ) {
            teamRow(store.team(store.player.arenaOffenseTeam)) { showOffensePicker = true }
        }
        .frame(maxWidth: .infinity)
    }

    /// Four cards have to cross a quarter of the frame: half the screen for
    /// this column, halved again for the two team panels, less whatever the
    /// device's safe area takes. The row measures the width it is given and
    /// sizes the cards to it — one layout.
    ///
    /// It used to offer four sizes to `ViewThatFits`, which lays out EVERY
    /// candidate to pick one: eight rows of five cards measured on every
    /// pass of a screen that renders three times on the way in. The phone's
    /// watchdog put the Arena's entry at two seconds of main thread with the
    /// challengers, the cards and the models all already off it; this row
    /// is the one thing on the screen no other screen has.
    private func teamRow(_ team: [ResolvedUnit], onTap: @escaping () -> Void) -> some View {
        let slots = max(1, min(ArenaService.teamSize, team.count + (team.count < ArenaService.teamSize ? 1 : 0)))
        return Button(action: onTap) {
            GeometryReader { geo in
                let size = max(30, min(44, floor((geo.size.width - CGFloat(slots - 1) * 5) / CGFloat(slots))))
                teamCards(team, size: size)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 44 * 1.62)
        }
        .buttonStyle(.plain)
    }

    private func teamCards(_ team: [ResolvedUnit], size: CGFloat) -> some View {
        HStack(spacing: 5) {
            ForEach(team) { unit in
                UnitCard(unit: unit, showPower: false, size: size)
            }
            if team.count < ArenaService.teamSize {
                EmptyTeamSlot(size: size, label: "Add")
            }
        }
    }

    // MARK: - Opponents

    private var opponentList: some View {
        let offense = offensePower
        return SectionPanel(title: "Challengers", accessory: "\(opponents.count)") {
            if opponents.isEmpty {
                // An empty list means two completely different things now that
                // the pool is built off the main thread, and saying the wrong
                // one is worse than saying nothing: the CI tour photographed
                // this panel announcing "You have cleared the current pool" on
                // a fresh account that had not fought anybody, because the
                // challengers were still a few milliseconds away.
                EmptyState(
                    icon: isRefreshing ? "hourglass" : "person.2.slash",
                    title: isRefreshing ? "Finding challengers" : "No challengers",
                    message: isRefreshing
                        ? "Building five defence teams to fight."
                        : "You have cleared the current pool. It refreshes as your rating moves."
                )
            } else {
                // The one thing on this screen that scrolls, and it now has the
                // whole height of the frame to do it in.
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(opponents) { opponent in
                            opponentRow(opponent, offense: offense)
                        }
                    }
                }
            }
        }
    }

    /// One challenger, laid out across rather than down: who they are, the team
    /// you would meet, what the fight costs if you lose and what it pays if you
    /// win, and the plate that starts it.
    ///
    /// `offense` is `offensePower`, resolved once by the list.
    private func opponentRow(_ opponent: ArenaOpponent, offense: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(opponent.name)
                    .font(Theme.body(13).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(opponent.tier.displayName)
                    .font(Theme.body(10).weight(.bold))
                    .foregroundStyle(opponent.tier.color)
                    .lineLimit(1)
                Text("\(opponent.points) pts")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text("Power \(opponent.power)")
                    .font(Theme.numeric(10))
                    .foregroundStyle(
                        opponent.power > offense ? Theme.danger : Theme.success
                    )
                    .lineLimit(1)
                // What the attack costs and pays: the points a loss takes off
                // your rating, and the laurels a win is worth at your tier.
                // Kept to one short line so it lives inside the name column
                // rather than widening the row.
                HStack(spacing: 3) {
                    Text("−\(ArenaService.pointsForLoss(playerPoints: record.points, opponentPoints: opponent.points))")
                        .foregroundStyle(Theme.danger.opacity(0.9))
                    Text("·")
                        .foregroundStyle(Theme.textSecondary)
                    Label("\(ArenaService.laurelsForWin(tier: record.tier))", systemImage: "laurel.leading")
                        .foregroundStyle(Theme.success)
                }
                .font(Theme.numeric(10))
                .lineLimit(1)
            }
            // Flexible, not fixed at 100: the name block is the one thing in
            // the row that can give, so a narrow column truncates a long name
            // instead of pushing the attack capsule off the panel.
            .frame(maxWidth: 104, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(opponent.team) { unit in
                    UnitCard(unit: unit, showPower: false, size: cardSize)
                }
            }

            Spacer(minLength: 4)

            // The verb goes above the number: a bare "+27" in a gold capsule
            // did not read as the button that starts the fight, and the number
            // could have been laurels, power or points. Two lines rather than
            // two words, because the row has no width to spare.
            Button {
                attack(opponent)
            } label: {
                VStack(spacing: 0) {
                    Text("FIGHT")
                        .font(Theme.body(9).weight(.black))
                        .tracking(0.8)
                    Text("+\(ArenaService.pointsForWin(playerPoints: record.points, opponentPoints: opponent.points))")
                        .font(Theme.numeric(12).weight(.bold))
                }
                .foregroundStyle(record.attacksRemaining > 0 ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        record.attacksRemaining > 0
                            ? Theme.goldPlate
                            : LinearGradient(colors: [Theme.stroke, Theme.stroke],
                                             startPoint: .top, endPoint: .bottom)
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(record.attacksRemaining == 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func attack(_ opponent: ArenaOpponent) {
        ModelLibrary.shared.warm(opponent.team.map { $0.blueprint.model }, crowded: true)
        guard let engine = store.startArenaBattle(against: opponent) else { return }
        pendingEngines[opponent.id] = engine
        battle = .arena(opponent)
    }
}
