import SwiftUI

/// Missions, feats and the login gift: what the day asks for and what it
/// pays. Opens from the scroll beside the wallet on the island and from More.
///
/// Landscape shape: the strip carries the tab (Daily / Feats), the tally and
/// the wallet; the day's gift is one band across the top, and the list below
/// runs in as many columns as the width holds, so a dozen rows sit in the
/// frame at once where the navigation bar and the stacked panels used to leave
/// room for five.
struct MissionsView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var receipt: String?
    @State private var tab: Tab = .missions

    enum Tab: Hashable {
        case missions
        case feats
    }

    /// One row of a list, whichever list it came from.
    private struct Entry: Identifiable {
        let id: String
        let icon: String
        let title: String
        let reward: String
        let progress: Int
        let goal: Int
        let complete: Bool
        let claimed: Bool
        /// Feats claim through `claimFeat`, missions (and the all-missions
        /// bonus) through `claimMission`.
        let isFeat: Bool
    }

    /// Two columns of rows on a landscape phone, one on anything narrower.
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 8)]

    var body: some View {
        NavigationStack {
            GameScreen("Missions", subtitle: subtitle, dismiss: { dismiss() }) {
                BarSegments(
                    options: [(value: Tab.missions, title: "Daily"), (value: Tab.feats, title: "Feats")],
                    selection: $tab
                )
                BarCount(value: tally, systemImage: "checkmark.seal.fill", tint: Theme.gold)
                BarWallet(wallet: store.player.wallet)
            } content: {
                VStack(spacing: 8) {
                    loginBand
                    if let receipt {
                        receiptBanner(receipt)
                    }
                    list
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Strip

    private var subtitle: String {
        switch tab {
        case .missions: return "Missions reset at midnight"
        case .feats: return "Feats of a lifetime"
        }
    }

    private var tally: String {
        let player = store.player
        switch tab {
        case .missions:
            let claimed = QuestService.missions.filter { QuestService.isMissionClaimed($0.id, player: player) }.count
            return "\(claimed)/\(QuestService.missions.count)"
        case .feats:
            let claimed = QuestService.feats.filter { QuestService.isFeatClaimed($0.id, player: player) }.count
            return "\(claimed)/\(QuestService.feats.count)"
        }
    }

    // MARK: - The login gift

    /// Seven day tiles, the day's reward and the claim, in one band rather than
    /// the tall panel the portrait layout used.
    private var loginBand: some View {
        let player = store.player
        let day = max(1, player.loginStreak?.day ?? 1)
        let claimed = QuestService.isLoginGiftClaimed(player: player)
        let gifts = QuestService.loginGifts
        let today = gifts[max(0, min(gifts.count - 1, day - 1))]
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TODAY'S GIFT")
                    .font(Theme.body(10).weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(Theme.goldDim)
                Text("Day \(day) of \(gifts.count)")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 4) {
                ForEach(gifts.indices, id: \.self) { index in
                    dayTile(index: index, day: day, claimed: claimed, gifts: gifts)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(ShopService.describe(today))
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("Come back every day; a missed day starts the seven over.")
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            claimButton(title: claimed ? "Claimed" : "Claim", enabled: !claimed) {
                if let grants = store.claimLoginGift() { paid(grants) }
            }
        }
        .padding(8)
        .panelBackground()
    }

    private func dayTile(index: Int, day: Int, claimed: Bool, gifts: [ShopService.Grant]) -> some View {
        let number = index + 1
        let taken = number < day || (number == day && claimed)
        let isToday = number == day
        return VStack(spacing: 2) {
            Image(systemName: icon(for: gifts[index]))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(taken ? Theme.ink : (isToday ? Theme.gold : Theme.textSecondary))
            Text("\(number)")
                .font(Theme.numeric(9))
                .foregroundStyle(taken ? Theme.ink : Theme.textSecondary)
        }
        .frame(width: 34, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(taken ? Theme.gold : (isToday ? Theme.surfaceHigh : Theme.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isToday ? Theme.gold : Theme.stroke, lineWidth: 1)
        )
    }

    // MARK: - The list

    private var list: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entries: [Entry] {
        switch tab {
        case .missions: return missionEntries
        case .feats: return featEntries
        }
    }

    private var missionEntries: [Entry] {
        let player = store.player
        let claimedCount = QuestService.missions.filter { QuestService.isMissionClaimed($0.id, player: player) }.count
        let bonusClaimed = QuestService.isMissionClaimed(QuestService.allMissionsID, player: player)
        var rows = QuestService.missions.map { mission in
            Entry(
                id: mission.id,
                icon: mission.icon,
                title: mission.title,
                reward: ShopService.describe(mission.reward),
                progress: QuestService.progress(of: mission, player: player),
                goal: mission.goal,
                complete: QuestService.isMissionComplete(mission, player: player),
                claimed: QuestService.isMissionClaimed(mission.id, player: player),
                isFeat: false
            )
        }
        rows.append(
            Entry(
                id: QuestService.allMissionsID,
                icon: "checkmark.seal.fill",
                title: "Finish every mission",
                reward: ShopService.describe(QuestService.allMissionsBonus),
                progress: claimedCount,
                goal: QuestService.missions.count,
                complete: QuestService.allMissionsClaimable(player) || bonusClaimed,
                claimed: bonusClaimed,
                isFeat: false
            )
        )
        return rows
    }

    /// Claimable first, then in progress, then done.
    private var featEntries: [Entry] {
        let player = store.player
        let ordered = QuestService.feats.sorted { rank($0, player) < rank($1, player) }
        return ordered.map { feat in
            Entry(
                id: feat.id,
                icon: feat.icon,
                title: feat.title,
                reward: ShopService.describe(feat.reward),
                progress: QuestService.progress(of: feat, player: player),
                goal: feat.goal,
                complete: QuestService.isFeatComplete(feat, player: player),
                claimed: QuestService.isFeatClaimed(feat.id, player: player),
                isFeat: true
            )
        }
    }

    private func rank(_ feat: QuestService.Feat, _ player: Player) -> Int {
        if QuestService.isFeatClaimed(feat.id, player: player) { return 2 }
        return QuestService.isFeatComplete(feat, player: player) ? 0 : 1
    }

    // MARK: - Parts

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(entry.claimed ? Theme.textSecondary : Theme.gold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(entry.claimed ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatBar(
                        value: Double(entry.progress),
                        maximum: Double(max(1, entry.goal)),
                        tint: entry.complete ? Theme.success : Theme.gold,
                        height: 4
                    )
                    .frame(width: 70)
                    Text("\(entry.progress)/\(entry.goal)")
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                    Text(entry.reward)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.goldDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            claimButton(title: entry.claimed ? "Done" : "Claim", enabled: entry.complete && !entry.claimed) {
                claim(entry)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(entry.complete && !entry.claimed ? Theme.surfaceHigh : Theme.surface)
        )
    }

    private func claim(_ entry: Entry) {
        let grants = entry.isFeat ? store.claimFeat(entry.id) : store.claimMission(entry.id)
        if let grants { paid(grants) }
    }

    private func receiptBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.success)
            Text(text)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.success.opacity(0.12))
        )
    }

    private func claimButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(11).weight(.bold))
                .foregroundStyle(enabled ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
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
