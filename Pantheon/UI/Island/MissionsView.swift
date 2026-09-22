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
            prizeRow(QuestService.allMissionsBonus, status: claimStatus(claimed: done, ready: ready)) {
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
        return VStack(alignment: .leading, spacing: 6) {
            cardHeader("Athena's counsel", tally: nil)
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(Theme.socketFill)
                    BundleImage(name: face.imageName, renderedAt: 64)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                }
                .frame(width: 64, height: 64)
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
            prizeRow(tier.prize, status: claimStatus(claimed: done, ready: ready)) {
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
    /// inside a card.
    private func prizeRow(_ grant: ShopService.Grant, status: ClaimStatus, action: @escaping () -> Void) -> some View {
        let parts = Self.parts(of: grant)
        return HStack(spacing: 5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                RewardTile(grant: part, size: parts.count > 2 ? 34 : 38, showsTitle: false)
            }
            Spacer(minLength: 6)
            ClaimPlate(status: status, action: action)
                .frame(width: 88)
        }
    }

    // MARK: - The list

    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 6) {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
            // Room for a lit row's glow, which the scroll view would clip.
            .padding(.horizontal, 3)
            .padding(.top, 3)
            .padding(.bottom, 16)
        }
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
            }
        )
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

    /// The tier the player is on, its steps in the order Athena set them.
    /// The tier's prize is its own card. Showing all thirty at once would be
    /// the feats list again, which is the thing this exists to replace.
    private var counselEntries: [Entry] {
        let player = store.player
        let tier = CounselService.currentTier(for: player)
        return CounselService.steps(in: tier).map { step in
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
    }

    /// 0 waiting to be claimed, 1 in progress, 2 claimed. A stable sort on
    /// it keeps each group in the order the game wrote it.
    private static func rank(complete: Bool, claimed: Bool) -> Int {
        if claimed { return 2 }
        return complete ? 0 : 1
    }

    // MARK: - A row

    /// One row of the board: the bronze medallion (gold and glowing when
    /// there is something to take), the title at 14 on up to two lines — the
    /// longest counsel is "Claim a tribute chest on a chapter's road", 268
    /// points against the row's 248 — the bar, the painted reward and the
    /// claim plate.
    private func row(_ entry: Entry) -> some View {
        let lit = entry.complete && !entry.claimed
        return HStack(spacing: 12) {
            MedallionIcon(key: "", glyph: entry.claimed ? "checkmark" : entry.icon, size: 38, isOn: lit)
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
                    .frame(maxWidth: 150)
                    Text("\(min(entry.progress, entry.goal)) / \(entry.goal)")
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Spacer(minLength: 8)
            rewardTiles(entry.grant)
            ClaimPlate(status: claimStatus(claimed: entry.claimed, ready: entry.complete)) {
                claim(entry)
            }
            .frame(width: 92)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 62)
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
            HStack(spacing: 4) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    RewardTile(grant: part, size: 40, showsTitle: false)
                }
            }
        } else {
            RewardTile(grant: grant, size: 46, showsTitle: false)
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
