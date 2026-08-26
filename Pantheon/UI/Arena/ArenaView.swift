import SwiftUI

/// PvP: your standing, your defence, and the list of people to attack.
struct ArenaView: View {
    @EnvironmentObject private var store: GameStore
    @State private var opponents: [ArenaOpponent] = []
    @State private var pendingEngines: [String: BattleEngine] = [:]
    @State private var battle: BattleContext?
    @State private var showDefensePicker = false
    @State private var showOffensePicker = false
    @State private var defenseRating: Double?

    private var record: ArenaRecord { store.player.arena }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    standingPanel
                    defensePanel
                    offensePanel
                    opponentList
                }
                .padding(16)
            }
            .screen("Arena")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WalletBar(wallet: store.player.wallet)
                }
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

    private var standingPanel: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.tier.displayName.uppercased())
                        .font(Theme.display(26))
                        .foregroundStyle(record.tier.color)
                    Text("\(record.points) rank points")
                        .font(Theme.numeric(13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(record.wins)W / \(record.losses)L")
                        .font(Theme.numeric(13))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Best \(record.highestPoints)")
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

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

            HStack {
                Label("\(record.attacksRemaining)/\(record.maxAttacks) attacks", systemImage: "flame.fill")
                    .font(Theme.numeric(12))
                    .foregroundStyle(record.attacksRemaining > 0 ? Theme.gold : Theme.textSecondary)
                Spacer()
                Text("+\(record.tier.dailyLaurels) laurels daily")
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .panelBackground()
    }

    private var nextTier: ArenaTier? {
        ArenaTier.allCases.first { $0.threshold > record.points }
    }

    // MARK: - Teams

    private var defensePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Defence", accessory: ratingText)

            Text("This is the team other summoners fight when they attack you. It is played by the AI.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)

            teamRow(store.team(store.player.arenaDefenseTeam)) { showDefensePicker = true }

            Button {
                defenseRating = ArenaService.rateDefense(player: store.player)
            } label: {
                Label("Simulate defence", systemImage: "waveform.path.ecg")
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.info)
            }
        }
        .padding(14)
        .panelBackground()
    }

    private var ratingText: String? {
        guard let defenseRating else { return nil }
        return "holds \(Int(defenseRating * 100))%"
    }

    private var offensePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Offence",
                accessory: "Power \(store.team(store.player.arenaOffenseTeam).reduce(0) { $0 + $1.power })"
            )
            teamRow(store.team(store.player.arenaOffenseTeam)) { showOffensePicker = true }
        }
        .padding(14)
        .panelBackground()
    }

    private func teamRow(_ team: [ResolvedUnit], onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ForEach(team) { unit in
                    UnitCard(unit: unit, size: 64)
                }
                if team.count < ArenaService.teamSize {
                    EmptyTeamSlot(size: 64, label: "Add")
                }
                Spacer()
            }
        }
    }

    // MARK: - Opponents

    private var opponentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Challengers")
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
            }

            if opponents.isEmpty {
                EmptyState(
                    icon: "person.2.slash",
                    title: "No challengers",
                    message: "You have cleared the current pool. It refreshes as your rating moves."
                )
            } else {
                ForEach(opponents) { opponent in
                    opponentRow(opponent)
                }
            }
        }
        .padding(14)
        .panelBackground()
    }

    private func opponentRow(_ opponent: ArenaOpponent) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(opponent.name)
                        .font(Theme.body(15).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        Text(opponent.tier.displayName)
                            .font(Theme.body(10).weight(.bold))
                            .foregroundStyle(opponent.tier.color)
                        Text("\(opponent.points) pts")
                            .font(Theme.numeric(10))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Power \(opponent.power)")
                            .font(Theme.numeric(10))
                            .foregroundStyle(
                                opponent.power > store.totalPower ? Theme.danger : Theme.success
                            )
                    }
                }
                Spacer()
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

            HStack(spacing: 6) {
                ForEach(opponent.team) { unit in
                    UnitCard(unit: unit, showPower: false, size: 52)
                }
                Spacer()
            }
        }
        .padding(10)
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
