import SwiftUI

/// Missions, feats and the login gift: what the day asks for and what it
/// pays. Opens from the scroll beside the wallet on the island and from More.
struct MissionsView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var receipt: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let receipt {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Theme.success)
                            Text(receipt)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                .fill(Theme.success.opacity(0.12))
                        )
                    }
                    loginPanel
                    missionsPanel
                    featsPanel
                }
                .padding(16)
            }
            .screen("Missions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    WalletBar(wallet: store.player.wallet)
                }
            }
        }
    }

    // MARK: - The login gift

    private var loginPanel: some View {
        let player = store.player
        let day = max(1, player.loginStreak?.day ?? 1)
        let claimed = QuestService.isLoginGiftClaimed(player: player)
        let gifts = QuestService.loginGifts
        let today = gifts[max(0, min(gifts.count - 1, day - 1))]
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today's gift", accessory: "Day \(day) of \(gifts.count)")
            HStack(spacing: 6) {
                ForEach(gifts.indices, id: \.self) { index in
                    let number = index + 1
                    let taken = number < day || (number == day && claimed)
                    let isToday = number == day
                    VStack(spacing: 4) {
                        Image(systemName: icon(for: gifts[index]))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(taken ? Theme.ink : (isToday ? Theme.gold : Theme.textSecondary))
                        Text("\(number)")
                            .font(Theme.numeric(9))
                            .foregroundStyle(taken ? Theme.ink : Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(taken ? Theme.gold : (isToday ? Theme.surfaceHigh : Theme.surface))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isToday ? Theme.gold : Theme.stroke, lineWidth: 1)
                    )
                }
            }
            HStack {
                Text(ShopService.describe(today))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                claimButton(title: claimed ? "Claimed" : "Claim", enabled: !claimed) {
                    if let grants = store.claimLoginGift() { paid(grants) }
                }
            }
            Text("Come back every day; a missed day starts the seven over.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .panelBackground()
    }

    // MARK: - Daily missions

    private var missionsPanel: some View {
        let player = store.player
        let claimedCount = QuestService.missions.filter { QuestService.isMissionClaimed($0.id, player: player) }.count
        let bonusClaimed = QuestService.isMissionClaimed(QuestService.allMissionsID, player: player)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Daily missions", accessory: "\(claimedCount)/\(QuestService.missions.count)")
            ForEach(QuestService.missions) { mission in
                row(
                    icon: mission.icon,
                    title: mission.title,
                    reward: ShopService.describe(mission.reward),
                    progress: QuestService.progress(of: mission, player: player),
                    goal: mission.goal,
                    complete: QuestService.isMissionComplete(mission, player: player),
                    claimed: QuestService.isMissionClaimed(mission.id, player: player)
                ) {
                    if let grants = store.claimMission(mission.id) { paid(grants) }
                }
            }
            row(
                icon: "checkmark.seal.fill",
                title: "Finish every mission",
                reward: ShopService.describe(QuestService.allMissionsBonus),
                progress: claimedCount,
                goal: QuestService.missions.count,
                complete: QuestService.allMissionsClaimable(player) || bonusClaimed,
                claimed: bonusClaimed
            ) {
                if let grants = store.claimMission(QuestService.allMissionsID) { paid(grants) }
            }
            Text("Missions reset at midnight.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .panelBackground()
    }

    // MARK: - Feats

    private var featsPanel: some View {
        let player = store.player
        let ordered = QuestService.feats.sorted { rank($0, player) < rank($1, player) }
        let claimedCount = QuestService.feats.filter { QuestService.isFeatClaimed($0.id, player: player) }.count
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Feats", accessory: "\(claimedCount)/\(QuestService.feats.count)")
            ForEach(ordered) { feat in
                row(
                    icon: feat.icon,
                    title: feat.title,
                    reward: ShopService.describe(feat.reward),
                    progress: QuestService.progress(of: feat, player: player),
                    goal: feat.goal,
                    complete: QuestService.isFeatComplete(feat, player: player),
                    claimed: QuestService.isFeatClaimed(feat.id, player: player)
                ) {
                    if let grants = store.claimFeat(feat.id) { paid(grants) }
                }
            }
        }
        .padding(12)
        .panelBackground()
    }

    /// Claimable first, then in progress, then done.
    private func rank(_ feat: QuestService.Feat, _ player: Player) -> Int {
        if QuestService.isFeatClaimed(feat.id, player: player) { return 2 }
        return QuestService.isFeatComplete(feat, player: player) ? 0 : 1
    }

    // MARK: - Parts

    private func row(
        icon: String, title: String, reward: String, progress: Int, goal: Int,
        complete: Bool, claimed: Bool, claim: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(claimed ? Theme.textSecondary : Theme.gold)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.body(13).weight(.semibold))
                    .foregroundStyle(claimed ? Theme.textSecondary : Theme.textPrimary)
                HStack(spacing: 8) {
                    StatBar(
                        value: Double(progress),
                        maximum: Double(max(1, goal)),
                        tint: complete ? Theme.success : Theme.gold,
                        height: 4
                    )
                    .frame(width: 90)
                    Text("\(progress)/\(goal)")
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                    Text(reward)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.goldDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            claimButton(title: claimed ? "Done" : "Claim", enabled: complete && !claimed, action: claim)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(complete && !claimed ? Theme.surfaceHigh : Theme.surface)
        )
    }

    private func claimButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(12).weight(.bold))
                .foregroundStyle(enabled ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(enabled ? Theme.gold : Theme.surface))
        }
        .disabled(!enabled)
    }

    private func paid(_ grants: [ShopService.Grant]) {
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.light)
        receipt = "Received " + grants.map(ShopService.describe).joined(separator: ", ") + "."
    }

    private func icon(for grant: ShopService.Grant) -> String {
        switch grant {
        case .scrolls: return "scroll.fill"
        case .energy, .energyRefill: return "bolt.fill"
        case .drachma: return "circle.hexagongrid.fill"
        case .divinity: return "sparkles"
        case .relic: return "shield.lefthalf.filled"
        case .essences: return "drop.triangle.fill"
        case .bundle: return "gift.fill"
        }
    }
}
