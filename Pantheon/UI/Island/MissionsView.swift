import SwiftUI

/// Missions, Athena's counsel, feats and the login gift: what the day asks
/// for and what it pays. Opens from the scroll beside the wallet on the
/// island and from More.
///
/// A DATA screen, so it stays cream (PLAN.md, *Phase B of the premium pass*:
/// a checklist of eight to thirty rows is a list, and lists are marble). What
/// made run 211's frame read as a settings list was not the cream but the
/// material: flat rows with 14-point glyphs and a 70 × 4 hairline, rewards
/// as gold text although every reward has a painting, a Claim that was bare
/// text on an invisible capsule, and the day's biggest prize ("Finish every
/// mission") as the ninth row, under the fold. So, the marble board
/// (2026-09-22, option E):
///
/// - a left column of CARDS that keep the prizes in view — today's gift with
///   its seven days; the Daily Tribute, the chest for every mission of the
///   day (Honkai Star Rail's and AFK Journey's daily track is the header of
///   the list, never its last row); on the Counsel tab Athena herself, with
///   the tier's blurb that used to truncate the strip ("Wake a g…"), and the
///   tier's prize; on the Feats tab the tally;
/// - one column of raised marble rows (`MarbleRowPlate`): a bronze medallion,
///   the title at 14, a 7-point bar, the painted reward (`RewardTile`) and a
///   real claim plate (`ClaimPlate`), lit gold when there is something to take;
/// - the receipt as painted tiles (`GrantReceipt`) over the foot, where the
///   green sentence it replaces pushed the whole list down.
struct MissionsView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    /// What the last claim paid, as tiles, and which claim showed them.
    @State private var receipt: [ShopService.Grant] = []
    @State private var receiptID = UUID()

    /// Which list the screen opens on. The island's scroll and More both want
    /// Daily; the CI tour wants the Counsel, which is the only way to
    /// photograph a tab nothing taps its way to.
    init(opening: Tab = .missions) {
        _tab = State(initialValue: opening)
    }

    enum Tab: Hashable {
        case missions
        case counsel
        case feats
    }

    /// Which list a row came from, and so which claim it takes. A Bool told
    /// two lists apart; three need a name.
    private enum Source {
        case mission
        case counsel
        case feat
    }

    /// One row of a list, whichever list it came from.
    private struct Entry: Identifiable {
        let id: String
        let icon: String
        let title: String
        /// What it pays, drawn as its painting — it was a string of gold text.
        let grant: ShopService.Grant
        let progress: Int
        let goal: Int
        let complete: Bool
        let claimed: Bool
        /// Feats claim through `claimFeat`, missions through `claimMission`,
        /// the Counsel through `claimCounsel`.
        let source: Source
    }

    /// The three lists, as the strip's segmented switch.
    private let tabs: [(value: Tab, title: String)] = [
        (value: .missions, title: "Daily"),
        (value: .counsel, title: "Counsel"),
        (value: .feats, title: "Feats"),
    ]

    /// The cards' column. 236 holds "HIEROPHANT PRIZE" and its "10 / 10" on
    /// one line (197 of the 212 inside), seven 24-point day pips (192), and
    /// Athena's blurb in three lines beside her bust; it leaves the rows 478
    /// on an iPhone 16 Pro, 248 of it for a title.
    private static let cardColumn: CGFloat = 236

    /// A row's measures, which its bar's room is read off (`row`): the gap
    /// between its parts, the claim plate's column, and the reward at its
    /// end — one tile at 46, a two-part bundle's pair at 40 with 4 between.
    private static let rowSpacing: CGFloat = 12
    private static let claimColumn: CGFloat = 92
    private static let rewardTile: CGFloat = 46
    private static let pairTile: CGFloat = 40
    private static let pairGap: CGFloat = 4
    /// The longest a row's bar grows, which a wide phone reaches.
    private static let barCeiling: CGFloat = 190

    var body: some View {
        NavigationStack {
            GameScreen("Missions", subtitle: subtitle, dismiss: { dismiss() }) {
                // The tally that sat here is on the cards now, where it says
                // what it counts.
                BarSegments(options: tabs, selection: $tab)
                BarWallet(wallet: store.player.wallet)
            } content: {
                HStack(alignment: .top, spacing: 12) {
                    cards
                        .frame(width: Self.cardColumn)
                    list
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.top, 10)
                .overlay(alignment: .bottom) {
                    receiptOverlay
                }
            }
        }
    }

    // MARK: - Strip

    /// Short, so it never truncates: the counsel's 57-character blurb moved
    /// onto Athena's card.
    private var subtitle: String {
        switch tab {
        case .missions: return "Resets at midnight"
        case .counsel: return "Athena's counsel · " + CounselService.currentTier(for: store.player).title
        case .feats: return "Feats of a lifetime"
        }
    }

    // MARK: - The cards

    /// Two cards per tab, the day's prizes always in view. The column scrolls
    /// only if a short phone cannot hold it (it measures 297 of the 311
    /// points an iPhone 16 Pro gives it on the Daily tab).
    private var cards: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                switch tab {
                case .missions:
                    giftCard
                    tributeCard
                case .counsel:
                    athenaCard
                    prizeCard
                case .feats:
                    giftCard
                    featsCard
                }
            }
            .padding(.bottom, 12)
        }
    }

    /// Today's login gift: the thing, what it is, the seven days as pips, and
    /// the claim. The band it replaces had 34 × 36 day tiles with 16-point
    /// icons, the gift as plain text, and day seven looking like day two.
    private var giftCard: some View {
        let player = store.player
        let gifts = QuestService.loginGifts
        let day = max(1, min(gifts.count, player.loginStreak?.day ?? 1))
        let claimed = QuestService.isLoginGiftClaimed(player: player)
        let today = gifts[day - 1]
        return VStack(alignment: .leading, spacing: 6) {
            cardHeader("Today's gift", tally: "Day \(day) / \(gifts.count)")
            HStack(spacing: 10) {
                RewardTile(grant: today, size: 44, showsTitle: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ItemArt.title(for: today))
                        .font(Theme.body(13).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A missed day starts the seven over.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 4) {
                ForEach(gifts.indices, id: \.self) { index in
                    let number = index + 1
                    GiftDayPip(
                        key: ItemArt.key(for: gifts[index]),
                        taken: number < day || (number == day && claimed),
                        isToday: number == day,
                        isLast: index == gifts.count - 1
                    )
                }
            }
            ClaimPlate(status: claimed ? .done : .ready) {
                if let grants = store.claimLoginGift() { paid(grants) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MarbleRowPlate(isLit: !claimed, radius: Theme.cornerRadius))
    }

    /// The day's biggest prize, the chest for every mission claimed, with
    /// its track of eight — it was the ninth row of the list.
    private var tributeCard: some View {
        let player = store.player
        let total = QuestService.missions.count
        let claimed = QuestService.missions.filter { QuestService.isMissionClaimed($0.id, player: player) }.count
        let done = QuestService.isMissionClaimed(QuestService.allMissionsID, player: player)
        let ready = QuestService.allMissionsClaimable(player)
        return VStack(alignment: .leading, spacing: 6) {
            cardHeader("Daily tribute", tally: "\(claimed) / \(total)")
            HStack(spacing: 10) {
                ItemIcon(key: "chest_gold", size: 44, glow: ready)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Every mission of the day")
                        .font(Theme.body(12).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    segmentTrack(filled: claimed, total: total)
                }
            }
            prizeRow(QuestService.allMissionsBonus, status: claimStatus(claimed: done, ready: ready),
                     remaining: total - claimed) {
                if let grants = store.claimMission(QuestService.allMissionsID) { paid(grants) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MarbleRowPlate(isLit: ready, radius: Theme.cornerRadius))
    }

    /// Athena presents her own counsel: her bust (the four faces ship with
    /// alpha and the tab never showed one), the tier carved, and the tier's
    /// line in full. Pleased when something of hers is waiting to be taken.
    private var athenaCard: some View {
        let player = store.player
        let tier = CounselService.currentTier(for: player)
        let waiting = CounselService.steps(in: tier).contains {
            CounselService.isComplete($0, player: player) && !CounselService.isClaimed($0.id, player: player)
        } || CounselService.isPrizeReady(tier, player: player)
        let face: GuideFace = waiting ? .pleased : .calm
        // How many of her steps wait to be taken: the list sorts them first,
        // and her card says how many there are (run 216: a third ready step
        // sat under the fold with nothing to say it was there).
        let ready = CounselService.steps(in: tier).filter {
            CounselService.isComplete($0, player: player) && !CounselService.isClaimed($0.id, player: player)
        }.count
        let tally: String? = ready > 0 ? "\(ready) ready" : nil
        return VStack(alignment: .leading, spacing: 6) {
            cardHeader("Athena's counsel", tally: tally)
            HStack(alignment: .top, spacing: 10) {
                // 84, as designed: at 64 the card ended half way down the
                // column. The blurb then has 118 points, four lines at most
                // ("Hierophant" is 116 at 15; measured 2026-09-23).
                ZStack {
                    Circle().fill(Theme.socketFill)
                    BundleImage(name: face.imageName, renderedAt: 84)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84, height: 84)
                }
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.goldPlate, lineWidth: 1.5))
                .shadow(color: Color.black.opacity(0.2), radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.title.uppercased())
                        .font(Theme.title(15))
                        .tracking(0.8)
                        .carved(glow: false)
                        .lineLimit(1)
                        .fixedSize()
                    Text(tier.blurb)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MarbleRowPlate(isLit: waiting, radius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    /// The tier's own prize, for every step of it claimed — the Counsel list's
    /// last row before, below the fold.
    private var prizeCard: some View {
        let player = store.player
        let tier = CounselService.currentTier(for: player)
        let steps = CounselService.steps(in: tier)
        let claimed = steps.filter { CounselService.isClaimed($0.id, player: player) }.count
        let done = CounselService.isClaimed(tier.prizeID, player: player)
        let ready = CounselService.isPrizeReady(tier, player: player)
        return VStack(alignment: .leading, spacing: 6) {
            cardHeader("\(tier.title) prize", tally: "\(claimed) / \(steps.count)")
            HStack(spacing: 10) {
                ItemIcon(key: "chest_gold", size: 44, glow: ready)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Every counsel of the tier")
                        .font(Theme.body(12).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    segmentTrack(filled: claimed, total: steps.count)
                }
            }
            prizeRow(tier.prize, status: claimStatus(claimed: done, ready: ready),
                     remaining: steps.count - claimed) {
                claimCounsel(tier.prizeID)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MarbleRowPlate(isLit: ready, radius: Theme.cornerRadius))
    }

    /// The feats' tally, and how many are waiting. Feats have no prize of
    /// their own; each row is its own.
    private var featsCard: some View {
        let player = store.player
        let total = QuestService.feats.count
        let claimed = QuestService.feats.filter { QuestService.isFeatClaimed($0.id, player: player) }.count
        let waiting = QuestService.feats.filter {
            QuestService.isFeatComplete($0, player: player) && !QuestService.isFeatClaimed($0.id, player: player)
        }.count
        return VStack(alignment: .leading, spacing: 8) {
            cardHeader("Feats", tally: "\(claimed) / \(total)")
            StatBar(value: Double(claimed), maximum: Double(max(1, total)), tint: Theme.gold, height: 7)
            Text(waiting == 0 ? "Nothing waiting to claim" : "\(waiting) ready to claim")
                .font(Theme.body(12).weight(waiting == 0 ? .regular : .semibold))
                .foregroundStyle(waiting == 0 ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MarbleRowPlate(isLit: waiting > 0, radius: Theme.cornerRadius))
    }

    // MARK: - The cards' parts

    /// A card's name in carved-ink capitals and its tally at the right, both
    /// at their own width.
    private func cardHeader(_ title: String, tally: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.title(13))
                .tracking(1.2)
                .foregroundStyle(Theme.goldDim)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            if let tally {
                Text(tally)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// One segment per step, gold when claimed.
    private func segmentTrack(filled: Int, total: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<max(1, total), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? Theme.gold : Theme.stroke.opacity(0.7))
                    .frame(height: 6)
            }
        }
    }

    /// A prize's tiles and its claim, on one line: two parts at 38, three at
    /// 34, so the Hierophant's three and an 88-point claim fit the 212
    /// inside a card. Not yet earned, the slot says how many steps are left
    /// ("8 to go") instead of a dead Claim.
    private func prizeRow(_ grant: ShopService.Grant, status: ClaimStatus, remaining: Int,
                          action: @escaping () -> Void) -> some View {
        let parts = Self.parts(of: grant)
        return HStack(spacing: 5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                RewardTile(grant: part, size: parts.count > 2 ? 34 : 38, showsTitle: false)
            }
            Spacer(minLength: 6)
            claimSlot(status: status, waitingNote: "\(max(0, remaining)) to go", action: action)
                .frame(width: 88)
        }
    }

    /// The claim slot of a card or a row: the gold claim when there is
    /// something to take, DONE once taken, and — not yet earned — only a
    /// quiet note of what is left, right-aligned. Run 216's board ended every
    /// unfinished row in a cream CLAIM slab at 75%, a column of dead buttons
    /// that read as a disabled form; the genre puts a button on a finished
    /// mission only.
    @ViewBuilder
    private func claimSlot(status: ClaimStatus, waitingNote: String, action: @escaping () -> Void) -> some View {
        switch status {
        case .waiting:
            Text(waitingNote)
                .font(Theme.numeric(13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 6)
        case .ready, .done:
            ClaimPlate(status: status, action: action)
        }
    }

    // MARK: - The list

    /// The rows, resting on whole ones (`RestingList`): run 221 ended the
    /// Daily list on a ten-point sliver of its sixth row under the fade, and
    /// the Counsel on five. A row that would show as a sliver is not drawn,
    /// and the chevron at the foot says the list goes on.
    private var list: some View {
        let rows = entries
        // What the list's tightest row carries — its widest reward — and its
        // longest count, which every row's bar is measured against (`row`).
        let widestReward: CGFloat = rows.map { Self.rewardWidth($0.grant) }.max() ?? Self.rewardTile
        let longestGoal: Int = rows.map(\.goal).max() ?? 1
        let widestCount: String = "\(longestGoal) / \(longestGoal)"
        return RestingList {
            LazyVStack(spacing: 5) {
                ForEach(rows) { entry in
                    row(entry, widestReward: widestReward, widestCount: widestCount)
                        .restingRow()
                }
            }
            // Room for a lit row's glow, which the scroll view would clip,
            // and for the last row to scroll clear of the fade.
            .padding(.horizontal, 3)
            .padding(.top, 3)
            .padding(.bottom, RowRest.footFade)
        }
    }

    private var entries: [Entry] {
        switch tab {
        case .missions: return missionEntries
        case .counsel: return counselEntries
        case .feats: return featEntries
        }
    }

    /// The day's eight, claimable first, then in progress, then done. The
    /// all-missions bonus is the tribute card, not a row.
    private var missionEntries: [Entry] {
        let player = store.player
        let rows = QuestService.missions.map { mission in
            Entry(
                id: mission.id,
                icon: mission.icon,
                title: mission.title,
                grant: mission.reward,
                progress: QuestService.progress(of: mission, player: player),
                goal: mission.goal,
                complete: QuestService.isMissionComplete(mission, player: player),
                claimed: QuestService.isMissionClaimed(mission.id, player: player),
                source: .mission
            )
        }
        return rows.enumerated()
            .sorted { lhs, rhs in
                let left = Self.rank(complete: lhs.element.complete, claimed: lhs.element.claimed)
                let right = Self.rank(complete: rhs.element.complete, claimed: rhs.element.claimed)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// Claimable first, then in progress, then done.
    private var featEntries: [Entry] {
        let player = store.player
        let rows = QuestService.feats.map { feat in
            Entry(
                id: feat.id,
                icon: feat.icon,
                title: feat.title,
                grant: feat.reward,
                progress: QuestService.progress(of: feat, player: player),
                goal: feat.goal,
                complete: QuestService.isFeatComplete(feat, player: player),
                claimed: QuestService.isFeatClaimed(feat.id, player: player),
                source: .feat
            )
        }
        return rows.enumerated()
            .sorted { lhs, rhs in
                let left = Self.rank(complete: lhs.element.complete, claimed: lhs.element.claimed)
                let right = Self.rank(complete: rhs.element.complete, claimed: rhs.element.claimed)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// The tier the player is on: claimable first, then in progress, then
    /// done, each group in the order Athena set it — the other two lists'
    /// sort. Kept in her order, a ready step sat under the fold below an
    /// unfinished one (run 216). The tier's prize is its own card. Showing
    /// all thirty at once would be the feats list again, which is the thing
    /// this exists to replace.
    private var counselEntries: [Entry] {
        let player = store.player
        let tier = CounselService.currentTier(for: player)
        let rows = CounselService.steps(in: tier).map { step in
            Entry(
                id: step.id,
                icon: step.icon,
                title: step.title,
                grant: step.reward,
                progress: CounselService.progress(of: step, player: player),
                goal: step.goal,
                complete: CounselService.isComplete(step, player: player),
                claimed: CounselService.isClaimed(step.id, player: player),
                source: .counsel
            )
        }
        return rows.enumerated()
            .sorted { lhs, rhs in
                let left = Self.rank(complete: lhs.element.complete, claimed: lhs.element.claimed)
                let right = Self.rank(complete: rhs.element.complete, claimed: rhs.element.claimed)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// 0 waiting to be claimed, 1 in progress, 2 claimed. A stable sort on
    /// it keeps each group in the order the game wrote it.
    private static func rank(complete: Bool, claimed: Bool) -> Int {
        if claimed { return 2 }
        return complete ? 0 : 1
    }

    // MARK: - A row

    /// One row of the board: the painted door of the place the row is about
    /// in a bronze socket (gold-rimmed and glowing when there is something to
    /// take; its glyph where no painting fits), the title at 14 on up to two
    /// lines — the longest counsel is "Claim a tribute chest on a chapter's
    /// road", 268 points against the row's 248 — the bar with its count at
    /// its end ("0 / 3"), the painted reward, and the gold claim once there
    /// is something to take (DONE once taken). Rows are 54 at least, so
    /// about six show beside the cards.
    ///
    /// The count reads off the bar's own end. It stood in the claim slot at
    /// the row's far end until run 221, 180 points from the bar with the
    /// reward between them, and a row not yet earned carried an empty slot
    /// ninety points wide; the slot is only there now when it holds a plate,
    /// and the genre puts a button on a finished mission only.
    ///
    /// The bar is ONE length on every row of a list, so the counts stand in
    /// one column whether a row waits or is ready: run 234's Counsel had the
    /// counts of its three ready rows 7 points left of the waiting rows',
    /// because a ready row's claim plate took its bar's room. A fixed 190
    /// does not fit — a ready row on an iPhone 16 Pro has 216 points for the
    /// bar, its gap and its count, 178 with a two-part reward — so every
    /// row's bar line is given the room of the list's tightest row (a ready
    /// one with its widest reward: `barInset` is the claim column a waiting
    /// row lacks and what its reward is narrower than that one), and the
    /// count a slot as wide as the list's longest ("30 / 30"). On that phone
    /// the Daily bars are 168, the first Counsel's 145, the Feats' 115; a
    /// wide phone reaches `barCeiling`.
    private func row(_ entry: Entry, widestReward: CGFloat, widestCount: String) -> some View {
        let lit = entry.complete && !entry.claimed
        let status = claimStatus(claimed: entry.claimed, ready: entry.complete)
        let fraction = "\(min(entry.progress, entry.goal)) / \(entry.goal)"
        let art = Self.rowArt(for: entry.icon, id: entry.id)
        let claimRoom: CGFloat = status == .waiting ? Self.claimColumn + Self.rowSpacing : 0
        let rewardRoom: CGFloat = widestReward - Self.rewardWidth(entry.grant)
        let barInset: CGFloat = claimRoom + rewardRoom
        return HStack(spacing: Self.rowSpacing) {
            if entry.claimed {
                MedallionIcon(key: "", glyph: "checkmark", size: 38)
            } else {
                MedallionIcon(key: art.door, glyph: entry.icon, size: 38, isOn: lit, itemKey: art.item)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(Theme.body(14).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    StatBar(
                        value: Double(entry.progress),
                        maximum: Double(max(1, entry.goal)),
                        tint: entry.complete ? Theme.success : Theme.gold,
                        height: 7
                    )
                    .frame(maxWidth: Self.barCeiling)
                    // The list's longest count, unseen, holds the slot open,
                    // so a short count never lengthens its bar.
                    ZStack(alignment: .leading) {
                        Text(widestCount)
                            .hidden()
                            .accessibilityHidden(true)
                        Text(fraction)
                    }
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                }
                // Only the bar line: the title keeps the row's whole width.
                .padding(.trailing, barInset)
            }
            Spacer(minLength: 8)
            // The reward is the row's LAST thing on every row, so it stands
            // in one column whether or not a claim plate is up: drawn before
            // the plate, it jumped a plate's width between a ready row and a
            // waiting one (run 224, 33-counsel). A row that comes ready gains
            // its plate without its reward moving.
            if status != .waiting {
                claimSlot(status: status, waitingNote: fraction) {
                    claim(entry)
                }
                .frame(width: Self.claimColumn)
            }
            rewardTiles(entry.grant)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(minHeight: 54)
        .background(MarbleRowPlate(isLit: lit))
        .opacity(entry.claimed ? 0.62 : 1)
    }

    /// A reward as its painting: one tile, or a two-part bundle (a chapter's
    /// feat pays divinity and a scroll) as its two, so neither reads as a
    /// gift box marked "×2".
    @ViewBuilder
    private func rewardTiles(_ grant: ShopService.Grant) -> some View {
        let parts = Self.parts(of: grant)
        if parts.count == 2 {
            HStack(spacing: Self.pairGap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    RewardTile(grant: part, size: Self.pairTile, showsTitle: false)
                }
            }
        } else {
            RewardTile(grant: grant, size: Self.rewardTile, showsTitle: false)
        }
    }

    /// The width `rewardTiles` takes at a row's end.
    private static func rewardWidth(_ grant: ShopService.Grant) -> CGFloat {
        let pair: CGFloat = pairTile * 2 + pairGap
        return parts(of: grant).count == 2 ? pair : rewardTile
    }

    /// The painting a row's socket wears, read off the row's own glyph: the
    /// DOOR of the place it sends the player (`ChromeArt`: the campaign, the
    /// arena, the summoning circle, the collection) or the ITEM it is about
    /// (energy, the daily gift, a relic, an essence, the demigod's medal).
    /// A glyph with neither — the Labyrinth, the Tower, the codex, fusion —
    /// keeps its glyph, drawn legibly on the dark socket. Run 216's list was
    /// a column of flat SF glyphs, "a settings screen".
    ///
    /// `hexagon.fill` is two things, told apart by the row's id: the
    /// Counsel's relic power-ups ("Feed a relic to +3", +9, +15), which were
    /// the one flat gold hexagon among the paintings (run 221), and fusion,
    /// which has no painting and keeps it. A power-up wears the painted
    /// level-up mark: in the relic chest it read as "Put a relic on a god"
    /// again, one row under it (run 224).
    private static func rowArt(for glyph: String, id: String) -> (door: String, item: String?) {
        switch glyph {
        case "map.fill", "flag.fill", "checkmark.seal.fill", "bolt.shield.fill", "flame.circle.fill", "shippingbox.fill":
            return ("campaign", nil)
        case "trophy.fill":
            return ("arena", nil)
        case "sparkles", "star.fill":
            return ("summon", nil)
        case "arrow.up.circle.fill", "star.circle.fill", "sun.max.fill", "person.3.fill":
            return ("collection", nil)
        case "gift.fill":
            return ("", "bundle")
        case "bolt.fill":
            return ("", "energy")
        case "shield.lefthalf.filled", "circle.hexagongrid.fill", "diamond.fill":
            return ("", "relic_cache")
        case "hexagon.fill":
            return ("", id.contains("relic") ? "level_up" : nil)
        case "flame.fill":
            return ("", "essence_magic_mid")
        case "crown.fill":
            return ("", "player_exp")
        default:
            return ("", nil)
        }
    }

    /// A bundle flattened into its grants; anything else is itself.
    private static func parts(of grant: ShopService.Grant) -> [ShopService.Grant] {
        if case .bundle(let parts) = grant { return parts }
        return [grant]
    }

    private func claimStatus(claimed: Bool, ready: Bool) -> ClaimStatus {
        if claimed { return .done }
        return ready ? .ready : .waiting
    }

    // MARK: - Claiming

    private func claim(_ entry: Entry) {
        switch entry.source {
        case .mission:
            if let grants = store.claimMission(entry.id) { paid(grants) }
        case .counsel:
            claimCounsel(entry.id)
        case .feat:
            if let grants = store.claimFeat(entry.id) { paid(grants) }
        }
    }

    private func claimCounsel(_ id: String) {
        if let grants = store.claimCounsel(id) { paid(grants) }
    }

    @ViewBuilder
    private var receiptOverlay: some View {
        if !receipt.isEmpty {
            GrantReceipt(title: "Received", grants: receipt, onGlass: false)
                .padding(.bottom, 10)
        }
    }

    /// `ClaimPlate` has already played the confirm and the haptic; this shows
    /// what the claim paid for 2.8 seconds, unless a later claim replaced it.
    private func paid(_ grants: [ShopService.Grant]) {
        let id = UUID()
        withAnimation(.easeOut(duration: 0.2)) {
            receipt = grants
            receiptID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard receiptID == id else { return }
            withAnimation(.easeIn(duration: 0.25)) { receipt = [] }
        }
    }
}

/// One day of a seven-day gift, as a pip: the day's painted gift in a cream
/// disc, gold with a check once taken, ringed gold today, the seventh ringed
/// deeper so the week's last gift reads as its prize. The Missions' login
/// gift and the Events' Festival draw the same pip (2026-09-22; the critic's
/// note on run 211: the Festival's 30-point day tiles were the login band's).
/// `faded` dims a day that can no longer be claimed — a Festival day missed.
struct GiftDayPip: View {
    let key: String
    let taken: Bool
    let isToday: Bool
    var isLast: Bool = false
    var faded: Bool = false
    var size: CGFloat = 24

    private var rim: Color {
        if isToday { return Theme.gold }
        return isLast ? Theme.goldDeep : Theme.stroke
    }

    var body: some View {
        ZStack {
            Group {
                if taken {
                    Circle().fill(Theme.goldPlate)
                } else if isToday {
                    Circle().fill(Theme.surfaceHigh)
                } else {
                    Circle().fill(Theme.surface)
                }
            }
            Circle().strokeBorder(rim, lineWidth: isToday || isLast ? 1.5 : 1)
            if taken {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .black))
                    .foregroundStyle(Theme.ink)
            } else {
                ItemIcon(key: key, size: size * 0.7, glow: false)
                    .opacity(faded ? 0.3 : (isToday ? 1 : 0.6))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: isToday && !taken ? Theme.gold.opacity(0.45) : Color.clear, radius: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - A list that rests on whole rows

/// `RestingList`'s scroll space, for its content's frame.
private let restingListSpace = "restingList"

/// A cream list's scroll that comes to rest on whole rows (2026-09-23): run
/// 221's Missions board ended on a sliver of its next row under the foot's
/// fade, and the Lessons grid on the top half of a section's name. Each row
/// that wears `restingRow()` is drawn only while enough of it is in view, so
/// a sliver at either edge is not drawn at all; the foot still fades, so a
/// row scrolling out goes softly; and while anything is below the fold a
/// small chevron stands at the foot to say so — the unit sheet's and the
/// settings board's cue (`SheetPanelScroll`, `FadingBoard`), because a list
/// resting on whole rows no longer shows that it goes on.
///
/// The content brings its own padding, and under its last row at least
/// `RowRest.footFade`, so that row scrolls clear of the fade.
///
/// `onGlass` is for a list on dark glass over a painting — the bazaar's
/// shelves, the mileage board (run 234) — whose chevron is the glass's own
/// (`RestingChevron`).
struct RestingList<Content: View>: View {
    let onGlass: Bool
    let content: () -> Content

    /// The content's frame in the scroll's own space and the scroll's
    /// height: whether there is more below.
    @State private var contentFrame: CGRect = .zero
    @State private var viewportHeight: CGFloat = 0

    init(onGlass: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.onGlass = onGlass
        self.content = content
    }

    private var moreBelow: Bool {
        contentFrame.height > viewportHeight + 1 && contentFrame.maxY > viewportHeight + 2
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(restingListSpace))
                        Color.clear
                            .onAppear { contentFrame = frame }
                            .onChange(of: frame) { _, now in contentFrame = now }
                    }
                )
        }
        .coordinateSpace(name: restingListSpace)
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
                LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: RowRest.footFade)
            }
        )
        .overlay(alignment: .bottom) {
            if moreBelow {
                RestingChevron(onGlass: onGlass)
            }
        }
    }
}

/// The cue at a resting list's foot while rows wait below it: a small
/// chevron on a capsule — cream on marble; on glass, gold on a dark capsule
/// with the glass's rim, the summon rail's and the Hall of Ka ledger's.
struct RestingChevron: View {
    var onGlass: Bool = false

    var body: some View {
        Image(systemName: "chevron.compact.down")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(onGlass ? Theme.onGlassGold : Theme.goldDim)
            .frame(width: 30, height: 12)
            .background(Capsule().fill(onGlass ? Color.black.opacity(0.6) : Theme.surfaceHigh.opacity(0.92)))
            .overlay(Capsule().strokeBorder(onGlass ? Theme.glassRim : Theme.gold.opacity(0.35), lineWidth: 0.8))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The arithmetic of `restingRow()`, outside any view so the visual effect's
/// closure, which runs off the main actor, can call it.
enum RowRest {
    /// A resting list's foot fade, and the least padding under its last row.
    static let footFade: CGFloat = 16

    /// A row's opacity from how much of it is inside its scroll: none while
    /// `goneBelow` of its height or less shows, whole from `wholeFrom`, and
    /// a straight ramp between. A row with no scroll above it is whole.
    static func opacity(frame: CGRect, viewport: CGFloat?, goneBelow: CGFloat, wholeFrom: CGFloat) -> Double {
        guard let viewport, viewport > 0, frame.height > 0, wholeFrom > goneBelow else { return 1 }
        let shown = (min(frame.maxY, viewport) - max(frame.minY, 0)) / frame.height
        return Double(min(1, max(0, (shown - goneBelow) / (wholeFrom - goneBelow))))
    }
}

extension View {
    /// A row of a `RestingList`: not drawn while a third of it or less is in
    /// view at the scroll's top or foot, whole from three quarters in. A
    /// section's name passes a higher `goneBelow`, so it is never shown cut
    /// through its letters.
    func restingRow(goneBelow: CGFloat = 0.35, wholeFrom: CGFloat = 0.75) -> some View {
        visualEffect { content, place in
            content.opacity(RowRest.opacity(
                frame: place.frame(in: .scrollView),
                viewport: place.bounds(of: .scrollView)?.height,
                goneBelow: goneBelow,
                wholeFrom: wholeFrom
            ))
        }
    }
}
