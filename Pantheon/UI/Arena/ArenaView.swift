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
                BarButton(title: "Simulate", systemImage: "waveform.path.ecg", tint: Theme.info) {
                    defenseRating = ArenaService.rateDefense(player: store.player)
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

    private func refresh() {
        opponents = store.arenaPool
        store.refreshTimedResources()
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
            accessory: "Power \(store.team(store.player.arenaOffenseTeam).reduce(0) { $0 + $1.power })"
        ) {
            teamRow(store.team(store.player.arenaOffenseTeam)) { showOffensePicker = true }
        }
        .frame(maxWidth: .infinity)
    }

    /// Four cards have to cross a quarter of the frame: half the screen for
    /// this column, halved again for the two team panels. What is left of that
    /// inside the panel depends on the device's safe area — 162 points on the
    /// iPhone 16 Pro the CI tour photographs, where four 38s and their gaps
    /// come to 170 and spill over the panel edge — and there is no compiler
    /// here to measure it, so the row offers four sizes and takes the widest
    /// that fits rather than trusting one hand-computed number.
    private func teamRow(_ team: [ResolvedUnit], onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            ViewThatFits(in: .horizontal) {
                teamCards(team, size: 44)
                teamCards(team, size: 40)
                teamCards(team, size: 36)
                teamCards(team, size: 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// One candidate width for `teamRow`. No `Spacer` in here: a greedy row
    /// has no ideal width, and `ViewThatFits` chooses on the ideal width.
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
        SectionPanel(title: "Challengers", accessory: "\(opponents.count)") {
            if opponents.isEmpty {
                EmptyState(
                    icon: "person.2.slash",
                    title: "No challengers",
                    message: "You have cleared the current pool. It refreshes as your rating moves."
                )
            } else {
                // The one thing on this screen that scrolls, and it now has the
                // whole height of the frame to do it in.
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(opponents) { opponent in
                            opponentRow(opponent)
                        }
                    }
                }
            }
        }
    }

    /// One challenger, laid out across rather than down: who they are, the team
    /// you would meet, and what beating them is worth.
    private func opponentRow(_ opponent: ArenaOpponent) -> some View {
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
                        opponent.power > store.totalPower ? Theme.danger : Theme.success
                    )
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

            Button {
                attack(opponent)
            } label: {
                Text("+\(ArenaService.pointsForWin(playerPoints: record.points, opponentPoints: opponent.points))")
                    .font(Theme.numeric(13).weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(record.attacksRemaining > 0 ? Theme.gold : Theme.stroke))
            }
            .disabled(record.attacksRemaining == 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func attack(_ opponent: ArenaOpponent) {
        guard let engine = store.startArenaBattle(against: opponent) else { return }
        pendingEngines[opponent.id] = engine
        battle = .arena(opponent)
    }
}
