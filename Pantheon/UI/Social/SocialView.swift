import SwiftUI
import UIKit

/// Allies: friends, the inbox, the guild and its war, the rankings — the
/// social layer (`Docs/SOCIAL.md`) in the shape of the app's other screens:
/// one strip with the four tabs as its segmented switch, the content to the
/// edges, two columns on a landscape phone.
///
/// The screen reads `SocialService` and the store's `Player`; it never pays
/// anything itself. A claimed mail's grants go out through `onClaim` and a
/// war attack goes out through `onAttack`, both the lead's wiring.
struct SocialView: View {
    @EnvironmentObject private var store: GameStore
    @ObservedObject var social: SocialService
    @Environment(\.dismiss) private var dismiss

    let onAttack: (WarTarget) -> Void
    let onClaim: ([ShopService.Grant]) -> Void

    @State private var tab: SocialTab
    @State private var friendQuery = ""
    @State private var guildQuery = ""
    @State private var newGuildName = ""
    @State private var newGuildCrest = Guild.crests[0]
    @State private var draftPost = ""
    @State private var receiptLine: String?

    init(
        social: SocialService,
        opening: SocialTab = .friends,
        onAttack: @escaping (WarTarget) -> Void,
        onClaim: @escaping ([ShopService.Grant]) -> Void
    ) {
        self.social = social
        self.onAttack = onAttack
        self.onClaim = onClaim
        _tab = State(initialValue: opening)
    }

    private var tabs: [(value: SocialTab, title: String)] {
        SocialTab.allCases.map { candidate in
            (value: candidate, title: candidate.title(requests: social.requests.count, mail: social.unclaimedMail))
        }
    }

    var body: some View {
        NavigationStack {
            // Three controls (run 217: "ALL…", "Demig…" and "Refres|h" out of
            // its capsule with seven): the switch, Refresh as a glyph well,
            // and the two currencies this screen can change — the inbox pays
            // drachma. The Online/Offline chip is gone: the notice line under
            // the strip says Offline in words, and online is the normal case.
            GameScreen("Allies", subtitle: subtitle, dismiss: { dismiss() }) {
                BarSegments(options: tabs, selection: $tab)
                BarButton(
                    title: social.isRefreshing ? "Refreshing" : "Refresh",
                    systemImage: "arrow.clockwise",
                    tint: social.isRefreshing ? Theme.textSecondary : Theme.gold,
                    showsTitle: false
                ) {
                    refresh()
                }
                BarWallet(wallet: store.player.wallet, shows: [.energy, .drachma])
            } content: {
                VStack(spacing: 8) {
                    if let notice = social.availability.notice {
                        SocialNoticeLine(text: notice, icon: "icloud.slash", tint: Theme.textSecondary)
                    }
                    if let receiptLine {
                        SocialNoticeLine(text: receiptLine, icon: "checkmark.seal.fill", tint: Theme.success)
                            .onTapGesture { self.receiptLine = nil }
                    } else if let line = social.notice {
                        SocialNoticeLine(text: line, icon: "info.circle.fill", tint: Theme.goldDim)
                            .onTapGesture { social.notice = nil }
                    }
                    content
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
            }
            .onAppear { refresh() }
        }
    }

    private var subtitle: String {
        if let profile = social.profile {
            return "\(profile.name) · \(profile.tier.displayName) · \(social.backendName)"
        }
        return social.backendName
    }

    /// The player is read here, on the main actor, and handed to the task
    /// by value; the service never reaches into the store.
    private func refresh() {
        let player = store.player
        Task { await social.refresh(player: player) }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .friends: friendsTab
        case .inbox: inboxTab
        case .guild: guildTab
        case .ranks: ranksTab
        }
    }

    // MARK: - Friends

    /// Finding a demigod and the requests waiting are ONE painted panel down
    /// the left, two sections of it: as two panels each stood under the
    /// painted panel's 118-point floor and drew the plain gold-rimmed plate,
    /// beside the acanthus-cornered Friends (runs 220 and 221). It hangs from
    /// the top at its own height, as Found a guild does on the Guild tab, and
    /// scrolls under its field only when a search fills it. The friends
    /// hang from the top of theirs and end in a line that says where the
    /// next one comes from — one friend's row stood over two thirds of
    /// empty marble.
    private var friendsTab: some View {
        HStack(alignment: .top, spacing: 8) {
            SectionPanel(title: "Find demigods") {
                VStack(alignment: .leading, spacing: 6) {
                    SocialField(placeholder: "A demigod's name", draft: $friendQuery, submitLabel: "Search") {
                        Task { await social.search(name: friendQuery) }
                    }
                    // The field stays out of the choice, so a search that
                    // fills the panel never takes the keyboard away.
                    ViewThatFits(in: .vertical) {
                        findings
                        ScrollView {
                            findings
                                .padding(.bottom, SocialScrollFoot.fade)
                        }
                        .mask { SocialScrollFoot.footMask }
                    }
                }
                .modifier(SocialPanelInset())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            SectionPanel(title: "Friends", accessory: "\(social.friends.count)") {
                if social.friends.isEmpty {
                    EmptyState(
                        icon: "person.2",
                        title: "No friends yet",
                        message: "Find a demigod by name and send a request; a friend's row greets them with a gift."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(social.friends) { friendship in
                                SocialFriendRow(friendship: friendship, greeted: social.greetedIDs.contains(friendship.friend.id)) {
                                    Task { await social.sendGreeting(to: friendship) }
                                }
                            }
                            SocialInviteLine(text: "Find more demigods by name on the left.")
                        }
                        .padding(.bottom, SocialScrollFoot.fade)
                    }
                    .mask { SocialScrollFoot.footMask }
                    .modifier(SocialPanelInset())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Under the find field: what the search found (or how to search), then
    /// the requests waiting, headed like the panel's own first section.
    private var findings: some View {
        VStack(alignment: .leading, spacing: 6) {
            if social.searchResults.isEmpty {
                Text(friendQuery.isEmpty ? "Search by name. A friend's row sends a greeting a day." : "Nobody by that name yet.")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(social.searchResults.prefix(6)) { found in
                    SocialProfileRow(profile: found, state: requestState(for: found)) {
                        Task { await social.sendFriendRequest(to: found) }
                    }
                }
            }
            SocialSubheader(title: "Requests", accessory: "\(social.requests.count)")
                .padding(.top, 6)
            if social.requests.isEmpty {
                Text("Nobody is waiting on you.")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(social.requests) { request in
                    SocialRequestRow(request: request) { accept in
                        Task { await social.respond(request, accept: accept) }
                    }
                }
            }
        }
    }

    private func requestState(for found: SocialProfile) -> SocialRequestState {
        if social.isFriend(found.id) { return .friends }
        if social.sentRequestIDs.contains(found.id) { return .sent }
        return .open
    }

    // MARK: - Inbox

    private var inboxTab: some View {
        SectionPanel(title: "Inbox", accessory: "\(social.unclaimedMail) to claim") {
            if social.mail.isEmpty {
                EmptyState(
                    icon: "envelope",
                    title: "Nothing in the inbox",
                    message: "Greetings from friends and the game's own gifts land here, each with its reward."
                )
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(social.mail) { item in
                            SocialMailRow(item: item) {
                                claim(item)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func claim(_ item: Mail) {
        Task {
            let grants = await social.claim(item)
            guard !grants.isEmpty else { return }
            onClaim(grants)
            AudioLibrary.shared.play(.uiConfirm)
            Juice.haptic(.light)
            receiptLine = "Received " + grants.map(ShopService.describe).joined(separator: ", ") + "."
        }
    }

    // MARK: - Guild

    @ViewBuilder
    private var guildTab: some View {
        if let guild = social.guild {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    SocialGuildCard(guild: guild, memberCount: max(guild.memberCount, social.members.count)) {
                        Task { await social.leaveGuild() }
                    }
                    SectionPanel(title: "Roster", accessory: "\(social.members.count)/\(Guild.capacity)") {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(social.members) { member in
                                    SocialMemberRow(member: member, isMe: member.userID == social.profile?.id)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                    }
                    SectionPanel(title: "Board") {
                        VStack(spacing: 6) {
                            SocialField(placeholder: "A line for the guild", draft: $draftPost, submitLabel: "Post") {
                                let line = draftPost
                                draftPost = ""
                                Task { await social.post(line) }
                            }
                            ScrollView {
                                VStack(spacing: 4) {
                                    ForEach(social.board) { post in
                                        SocialPostRow(post: post)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                warPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                // One way to found it: the field's own "Found" pill did what
                // FOUND THE GUILD under the crests does (run 217). The return
                // key still submits. Both panels hang from the top, so their
                // headers stand on one line; the short one was centred. Both
                // keep their contents inside the painted corners
                // (`SocialPanelInset`): the bottom scrolls painted over
                // FOUND THE GUILD's two lower corners and the last guild
                // row's (run 221).
                SectionPanel(title: "Found a guild") {
                    VStack(spacing: 8) {
                        SocialField(placeholder: "The guild's name", draft: $newGuildName, submitLabel: nil) {
                            Task { await social.createGuild(name: newGuildName, crest: newGuildCrest) }
                        }
                        SocialCrestPicker(chosen: newGuildCrest) { newGuildCrest = $0 }
                        Text("Up to \(Guild.capacity) demigods. The guild is paired against a rival every week; each member fights \(WarRules.attacksPerDay) times a day.")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryButton(title: "Found the guild", systemImage: "flag.fill", isEnabled: newGuildName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2) {
                            Task { await social.createGuild(name: newGuildName, crest: newGuildCrest) }
                        }
                    }
                    .modifier(SocialPanelInset())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                SectionPanel(title: "Find a guild", accessory: "\(social.guildsFound.count)") {
                    VStack(spacing: 6) {
                        SocialField(placeholder: "A guild's name, or nothing for the strongest", draft: $guildQuery, submitLabel: "Search") {
                            Task { await social.findGuilds(name: guildQuery) }
                        }
                        if social.guildsFound.isEmpty {
                            Text("Search, or press Search with nothing typed for the strongest guilds.")
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // Whole rows while they fit — the four strongest
                            // do, on the CI phone — and a list that scrolls
                            // and fades at its foot once they do not.
                            ViewThatFits(in: .vertical) {
                                guildRows
                                ScrollView {
                                    guildRows
                                        .padding(.bottom, SocialScrollFoot.fade)
                                }
                                .mask { SocialScrollFoot.footMask }
                            }
                        }
                    }
                    .modifier(SocialPanelInset())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onAppear { Task { await social.findGuilds(name: "") } }
            }
        }
    }

    /// The guilds a search found, strongest first, each with its Join.
    private var guildRows: some View {
        VStack(spacing: 3) {
            ForEach(social.guildsFound) { candidate in
                SocialGuildRow(guild: candidate) {
                    Task { await social.joinGuild(candidate) }
                }
            }
        }
    }

    @ViewBuilder
    private var warPanel: some View {
        if let war = social.war {
            SectionPanel(title: "Guild war · \(war.week)", accessory: "ends in \(SocialClock.remaining(until: war.endsAt))") {
                VStack(spacing: 8) {
                    SocialStandingsBar(standings: war.standings)
                    HStack {
                        Text("\(war.attacksLeftToday) of \(WarRules.attacksPerDay) attacks left today")
                            .font(Theme.numeric(11))
                            .foregroundStyle(war.attacksLeftToday > 0 ? Theme.textPrimary : Theme.textSecondary)
                        Spacer()
                        Text("vs \(war.opponent.name)")
                            .font(Theme.body(11).weight(.bold))
                            .foregroundStyle(Theme.goldDim)
                    }
                    if war.targets.isEmpty {
                        Text("The rival guild has nobody to fight yet.")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(war.targets) { target in
                                    SocialTargetRow(target: target, canAttack: war.attacksLeftToday > 0 && !target.beaten) {
                                        onAttack(target)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            SectionPanel(title: "Guild war") {
                EmptyState(
                    icon: "flag.slash",
                    title: "No rival this week",
                    message: "A war needs a second guild. The pairing is drawn every week from the guilds nearest yours in points."
                )
            }
        }
    }

    // MARK: - Ranks

    /// Each table ends in the player's own standing when the list's window
    /// does not show it; the guilds' table, for a demigod in none, in a line
    /// that says where one is found.
    private var ranksTab: some View {
        HStack(alignment: .top, spacing: 8) {
            SocialRankTable(title: "Arena", entries: social.arenaLeaderboard, unit: "pts")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SocialRankTable(
                title: "Guilds",
                entries: social.guildLeaderboard,
                unit: "war pts",
                ownOutsideList: ownGuildEntry,
                withoutOwnRow: social.guild == nil ? "No guild yet · found or join one on the Guild tab" : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The player's guild as a row of the table, unranked, for a guild the
    /// table does not reach (the strongest fifty in the cloud); nil when he
    /// has none.
    private var ownGuildEntry: LeaderboardEntry? {
        guard let guild = social.guild else { return nil }
        return LeaderboardEntry(
            id: guild.id,
            rank: 0,
            name: guild.name,
            detail: "\(guild.memberCount) member\(guild.memberCount == 1 ? "" : "s")",
            score: guild.warPoints,
            crest: guild.crest,
            isMine: true
        )
    }
}

/// The four tabs, and the launch argument the tour picks one with
/// (`-tour-social-tab friends|inbox|guild|ranks`).
enum SocialTab: String, Hashable, CaseIterable {
    case friends
    case inbox
    case guild
    case ranks

    func title(requests: Int, mail: Int) -> String {
        switch self {
        case .friends: return requests > 0 ? "Friends (\(requests))" : "Friends"
        case .inbox: return mail > 0 ? "Inbox (\(mail))" : "Inbox"
        case .guild: return "Guild"
        case .ranks: return "Ranks"
        }
    }

    static var pinnedFromArguments: SocialTab? {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-social-tab"), at + 1 < args.count else { return nil }
        return SocialTab(rawValue: args[at + 1])
    }
}

/// Where a search result stands with the player.
enum SocialRequestState {
    case open
    case sent
    case friends
}

// MARK: - Parts

/// One line under the strip: the offline notice, a receipt, an error.
private struct SocialNoticeLine: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.plate.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
        )
    }
}

/// A text field in the app's cream, with its action on the return key and
/// as a small button beside it — or on the return key alone when the panel
/// has its own button for it (`submitLabel` nil: Found a guild).
private struct SocialField: View {
    let placeholder: String
    @Binding var draft: String
    let submitLabel: String?
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $draft)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(submit)
                .padding(.horizontal, 8)
                .frame(height: ScreenChrome.control)
                .background(ScreenChrome.controlShape.fill(Theme.surfaceHigh))
                .overlay(ScreenChrome.controlShape.strokeBorder(Theme.stroke, lineWidth: 0.5))
            if let submitLabel {
                SocialPillButton(title: submitLabel, enabled: true, tint: Theme.gold, action: submit)
            }
        }
    }
}

/// The row action: a capsule, gold when it can be pressed.
private struct SocialPillButton: View {
    let title: String
    let enabled: Bool
    var tint: Color = Theme.gold
    let action: () -> Void

    var body: some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            action()
        } label: {
            Text(title)
                .font(Theme.body(11).weight(.bold))
                .foregroundStyle(enabled ? Theme.ink : Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(enabled ? tint : Theme.surface))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A defence's leader as a face, or an empty square when the family is
/// unknown to this build.
///
/// A face, not a `UnitCard` (run 217): at 44 points the card's caption
/// strip read "Azure D…", its element badge was cut by the card's left
/// edge and its stars ran to the rim — and the row beside it already
/// names the demigod. `UnitPortraitTile` has no name to cut.
private struct SocialLeaderCard: View {
    let unit: TeamSnapshotUnit?
    var size: CGFloat = 44

    var body: some View {
        if let resolved = unit?.resolved() {
            UnitPortraitTile(unit: resolved, size: size)
        } else {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(Theme.goldDim)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .fill(Theme.plate.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .accessibilityLabel("No leader")
        }
    }
}

private struct SocialProfileRow: View {
    let profile: SocialProfile
    let state: SocialRequestState
    let send: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SocialLeaderCard(unit: profile.leader, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("Lv.\(profile.level) · \(profile.tier.displayName) · power \(profile.power)")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            switch state {
            case .open:
                SocialPillButton(title: "Add", enabled: true, action: send)
            case .sent:
                Chip(text: "SENT", tint: Theme.goldDim)
            case .friends:
                Chip(text: "FRIENDS", tint: Theme.success, filled: true)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

private struct SocialRequestRow: View {
    let request: FriendRequest
    let respond: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.fromName)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("asked \(SocialClock.ago(request.sentAt))")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            SocialPillButton(title: "Accept", enabled: true) { respond(true) }
            SocialPillButton(title: "Decline", enabled: true, tint: Theme.surfaceHigh) { respond(false) }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surfaceHigh)
        )
    }
}

private struct SocialFriendRow: View {
    let friendship: Friendship
    let greeted: Bool
    let greet: () -> Void

    /// How long the two have been friends, short enough to sit under the
    /// greeting pill: "friends 3 d", "friends 5 h", "new friend".
    private var friendsFor: String {
        let seconds = max(0, Date().timeIntervalSince(friendship.since))
        if seconds >= 86_400 { return "friends \(Int(seconds / 86_400)) d" }
        if seconds >= 3_600 { return "friends \(Int(seconds / 3_600)) h" }
        return "new friend"
    }

    // The power line is the power alone and the friendship's age sits under
    // the pill, as a war target's points do under Attack: "Power 6,955 ·
    // friends 3 d a…" was cut in run 217. The tier's word is taken 60% to
    // ink — the Initiate's blue-grey was 2.7:1 on the cream row.
    var body: some View {
        HStack(spacing: 8) {
            SocialLeaderCard(unit: friendship.friend.leader, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(friendship.friend.name)
                    .font(Theme.body(13).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("Lv.\(friendship.friend.level) · \(friendship.friend.tier.displayName)")
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(SocialInk.inked(friendship.friend.tier.color))
                    .lineLimit(1)
                    .fixedSize()
                Text("Power \(friendship.friend.power)")
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                if let guildName = friendship.friend.guildName {
                    Chip(text: guildName.uppercased(), systemImage: "flag.fill", tint: Theme.goldDim)
                }
            }
            Spacer(minLength: 4)
            VStack(spacing: 3) {
                SocialPillButton(title: greeted ? "Greeted" : "Send greeting", enabled: !greeted, action: greet)
                Text(friendsFor)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

private struct SocialMailRow: View {
    let item: Mail
    let claim: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.claimed ? "envelope.open" : "envelope.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(item.claimed ? Theme.textSecondary : Theme.gold)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.subject)
                        .font(Theme.body(12).weight(.semibold))
                        .foregroundStyle(item.claimed ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(SocialClock.ago(item.sentAt))
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("From \(item.fromName)")
                    .font(Theme.body(10).weight(.bold))
                    .foregroundStyle(Theme.goldDim)
                Text(item.body)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if item.hasGrants {
                    HStack(spacing: 6) {
                        ForEach(Array(item.grants.enumerated()), id: \.offset) { _, grant in
                            RewardTile(grant: grant, size: 40, showsTitle: false)
                                .opacity(item.claimed ? 0.45 : 1)
                        }
                    }
                }
            }
            Spacer(minLength: 4)
            if item.hasGrants {
                SocialPillButton(title: item.claimed ? "Claimed" : "Claim", enabled: !item.claimed, action: claim)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(item.claimed ? Theme.surface : Theme.surfaceHigh)
        )
    }
}

private struct SocialGuildCard: View {
    let guild: Guild
    let memberCount: Int
    let leave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: guild.crest)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surfaceHigh))
                .overlay(Circle().strokeBorder(Theme.goldDim.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(guild.name.uppercased())
                    .font(Theme.title(14))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(memberCount) member\(memberCount == 1 ? "" : "s") · \(guild.warPoints) season points")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text("Season \(guild.season)")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            SocialPillButton(title: "Leave", enabled: true, tint: Theme.surfaceHigh, action: leave)
        }
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
    }
}

private struct SocialMemberRow: View {
    let member: GuildMember
    let isMe: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: member.role == .leader ? "crown.fill" : "person.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(member.role == .leader ? Theme.gold : Theme.textSecondary)
                .frame(width: 14)
            Text(member.name)
                .font(Theme.body(11).weight(isMe ? .bold : .semibold))
                .foregroundStyle(isMe ? Theme.goldDim : Theme.textPrimary)
                .lineLimit(1)
            Text("Lv.\(member.level)")
                .font(Theme.numeric(10))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 4)
            Text("power \(member.power)")
                .font(Theme.numeric(10))
                .foregroundStyle(Theme.textSecondary)
            Text("\(member.weekPoints) pts")
                .font(Theme.numeric(10.5).weight(.bold))
                .foregroundStyle(member.weekPoints > 0 ? Theme.success : Theme.textSecondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(isMe ? Theme.surfaceHigh : Theme.surface)
        )
    }
}

private struct SocialPostRow: View {
    let post: BoardPost

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(post.authorName)
                    .font(Theme.body(10).weight(.bold))
                    .foregroundStyle(Theme.goldDim)
                Spacer(minLength: 4)
                Text(SocialClock.ago(post.postedAt))
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(post.text)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

private struct SocialGuildRow: View {
    let guild: Guild
    let join: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: guild.crest)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(guild.name)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(guild.memberCount)/\(Guild.capacity) members · \(guild.warPoints) pts")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            SocialPillButton(title: guild.isFull ? "Full" : "Join", enabled: !guild.isFull, action: join)
        }
        // Four points top and bottom (the Join pill is 25 in a 34-point
        // pair of lines): the four strongest guilds stand whole above the
        // panel's painted corners, 42 points a row.
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

private struct SocialCrestPicker: View {
    let chosen: String
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Guild.crests, id: \.self) { glyph in
                Button {
                    Juice.haptic(.light)
                    pick(glyph)
                } label: {
                    Image(systemName: glyph)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(glyph == chosen ? Theme.ink : Theme.goldDim)
                        .frame(width: ScreenChrome.control + 4, height: ScreenChrome.control + 4)
                        .background(ScreenChrome.controlShape.fill(glyph == chosen ? Theme.gold : Theme.surfaceHigh))
                        .overlay(ScreenChrome.controlShape.strokeBorder(Theme.goldDim.opacity(0.4), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The two guilds' week points as one bar against the other, the genre's
/// war meter, with wins and attempts under it.
private struct SocialStandingsBar: View {
    let standings: [WarStanding]

    var body: some View {
        let top = max(1, standings.map(\.points).max() ?? 1)
        VStack(spacing: 5) {
            ForEach(standings) { standing in
                HStack(spacing: 6) {
                    Image(systemName: standing.crest)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(standing.isMine ? Theme.gold : Theme.textSecondary)
                        .frame(width: 14)
                    Text(standing.guildName)
                        .font(Theme.body(11).weight(standing.isMine ? .bold : .semibold))
                        .foregroundStyle(standing.isMine ? Theme.goldDim : Theme.textPrimary)
                        .lineLimit(1)
                        .frame(width: 96, alignment: .leading)
                    StatBar(
                        value: Double(standing.points),
                        maximum: Double(top),
                        tint: standing.isMine ? Theme.gold : Theme.danger,
                        height: 6
                    )
                    Text("\(standing.points)")
                        .font(Theme.numeric(12).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 40, alignment: .trailing)
                    Text("\(standing.wins)W/\(standing.attacks)")
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
    }
}

private struct SocialTargetRow: View {
    let target: WarTarget
    let canAttack: Bool
    let attack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SocialLeaderCard(unit: target.profile.leader, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.profile.name)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("Lv.\(target.profile.level) · power \(target.profile.power)")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    ForEach(target.profile.defence.prefix(4)) { unit in
                        Circle()
                            .fill(unit.element.color)
                            .frame(width: 7, height: 7)
                    }
                    Text("\(target.profile.defence.count) on defence")
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 4)
            if target.beaten {
                Chip(text: "BEATEN", systemImage: "checkmark", tint: Theme.success, filled: true)
            } else {
                VStack(spacing: 2) {
                    SocialPillButton(title: "Attack", enabled: canAttack, action: attack)
                    Text("+\(target.pointsForWin)")
                        .font(Theme.numeric(10).weight(.bold))
                        .foregroundStyle(Theme.success)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(target.beaten ? Theme.surface : Theme.surfaceHigh)
        )
    }
}

/// A ranking table with the player's own row lit — and pinned under the
/// list, after a rule, while the list's window does not show it whole: the
/// genre's "your rank" line. Run 221's arena said "top 13" and never showed
/// the thirteenth, the player's own. A table with no row of his (a demigod
/// in no guild) ends in a line that says where one is found, where the
/// guilds' four rows stood over 65 points of empty marble.
private struct SocialRankTable: View {
    let title: String
    let entries: [LeaderboardEntry]
    let unit: String
    /// The player's own row for a table that does not list it: his guild
    /// outside the strongest the table holds.
    var ownOutsideList: LeaderboardEntry? = nil
    /// What the foot says when the player has no row here at all.
    var withoutOwnRow: String? = nil

    /// Whether the player's own row stands whole in the list's window, above
    /// its fade — read as the list scrolls, written only when it flips — and
    /// how tall the window is.
    @State private var ownRowShown = false
    @State private var window: CGFloat = 0

    private static let space = "socialRankWindow"

    /// The player's row, in the list or from outside it.
    private var mine: LeaderboardEntry? { entries.first(where: \.isMine) ?? ownOutsideList }

    /// A row at `frame` in the list's window stands whole above the fade.
    private func inWindow(_ frame: CGRect) -> Bool {
        window > 0 && frame.minY >= -1 && frame.maxY <= window - SocialScrollFoot.fade + 1
    }

    var body: some View {
        SectionPanel(title: title, accessory: "top \(entries.filter { $0.rank > 0 }.count)") {
            if entries.isEmpty {
                EmptyState(
                    icon: "list.number",
                    title: "No ranks yet",
                    message: "The table fills as demigods publish their standing."
                )
            } else {
                VStack(spacing: 6) {
                    // The list fades at its foot and ends in as much clear
                    // space, so a row under the fold reads as a scroll: the
                    // arena's sixth row was cut hard at the panel's inner rule
                    // with nothing to say there were seven more (run 220).
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(entries) { entry in
                                SocialRankRow(entry: entry, unit: unit)
                                    .background {
                                        if entry.isMine {
                                            GeometryReader { row in
                                                let shown = inWindow(row.frame(in: .named(Self.space)))
                                                Color.clear
                                                    .onAppear { ownRowShown = shown }
                                                    .onChange(of: shown) { _, now in ownRowShown = now }
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.bottom, SocialScrollFoot.fade)
                    }
                    .coordinateSpace(name: Self.space)
                    .background {
                        GeometryReader { box in
                            Color.clear
                                .onAppear { window = box.size.height }
                                .onChange(of: box.size.height) { _, now in window = now }
                        }
                    }
                    .mask { SocialScrollFoot.footMask }
                    foot
                }
                .modifier(SocialPanelInset())
            }
        }
    }

    /// Under the list: a rule and the player's own row while the window
    /// does not show it, or the dashed line for a table with no row of his —
    /// 37 points, so the guilds' four rows still stand whole above the
    /// list's fade on the CI phone (165 of the 185 left them).
    @ViewBuilder
    private var foot: some View {
        if let mine, !(ownRowShown && entries.contains(where: \.isMine)) {
            SocialSubheader(title: "Your standing")
            SocialRankRow(entry: mine, unit: unit)
        } else if mine == nil, let withoutOwnRow {
            SocialInviteLine(text: withoutOwnRow, systemImage: "flag")
        }
    }
}

/// What a painted panel's contents keep clear of: its acanthus corners
/// reach about 18 points in, and the panel pads only 8 — the header takes 12
/// more across for the same reason. So the contents take 4 more across and
/// 10 more at the foot, and a last row or a button ends inside the corners
/// (run 221: FOUND THE GUILD's lower corners and the last guild row's were
/// painted over).
private struct SocialPanelInset: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.bottom, 10)
    }
}

/// A second section inside one panel, headed the way `SectionPanel` heads
/// its first: the name in small black capitals, a rule, the count — at the
/// header's own 20 points from the plate's edge.
private struct SocialSubheader: View {
    let title: String
    var accessory: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(Theme.body(10).weight(.black))
                .tracking(1.0)
                .foregroundStyle(Theme.goldDim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(Theme.stroke.opacity(0.7))
                .frame(height: 1)
            if let accessory {
                Text(accessory)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
    }
}

/// A line at the end of a list that says what goes there: where the next
/// friend comes from, why a table has no row of the player's. Drawn in the
/// list's own row shape, dashed, so it reads as the next row's place.
private struct SocialInviteLine: View {
    let text: String
    var systemImage: String = "person.badge.plus"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.goldDim)
                .frame(width: 26)
            Text(text)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .accessibilityElement(children: .combine)
    }
}

/// The foot of a scrolling list on the Allies screen: opaque down to its
/// last `fade` points, then clear — the relic columns' and the bazaar's
/// foot (`BazaarLayout.footFade`).
private enum SocialScrollFoot {
    static let fade: CGFloat = 18

    static var footMask: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
        }
    }
}

private struct SocialRankRow: View {
    let entry: LeaderboardEntry
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.rank > 0 ? "\(entry.rank)" : "—")
                .font(Theme.numeric(11).weight(.bold))
                .foregroundStyle(entry.rank <= 3 && entry.rank > 0 ? Theme.gold : Theme.textSecondary)
                .frame(width: 26, alignment: .trailing)
            if let crest = entry.crest {
                Image(systemName: crest)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.goldDim)
                    .frame(width: 14)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(Theme.body(11).weight(entry.isMine ? .bold : .semibold))
                    .foregroundStyle(entry.isMine ? Theme.goldDim : Theme.textPrimary)
                    .lineLimit(1)
                Text(entry.detail)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(entry.score) \(unit)")
                .font(Theme.numeric(11).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(entry.isMine ? Theme.surfaceHigh : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(entry.isMine ? Theme.gold : Color.clear, lineWidth: 1)
        )
    }
}

/// A colour taken 60% of the way to `Theme.ink`, so a tier's word reads on
/// the cream rows and still says which tier it is (the unit sheet's tags
/// do the same, `UnitDetailView.inked`).
private enum SocialInk {
    static func inked(_ color: Color) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return Theme.textPrimary }
        var inkRed: CGFloat = 0, inkGreen: CGFloat = 0, inkBlue: CGFloat = 0, inkAlpha: CGFloat = 0
        _ = UIColor(Theme.ink).getRed(&inkRed, green: &inkGreen, blue: &inkBlue, alpha: &inkAlpha)
        let keep: CGFloat = 0.4
        let mixedRed: Double = Double(red * keep + inkRed * (1 - keep))
        let mixedGreen: Double = Double(green * keep + inkGreen * (1 - keep))
        let mixedBlue: Double = Double(blue * keep + inkBlue * (1 - keep))
        return Color(red: mixedRed, green: mixedGreen, blue: mixedBlue)
    }
}

/// "just now", "5 min ago", "3 h ago", "2 d ago", and the war's "2 d 4 h".
enum SocialClock {
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) h ago" }
        return "\(Int(seconds / 86_400)) d ago"
    }

    static func remaining(until date: Date, now: Date = Date()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let days = Int(seconds / 86_400)
        let hours = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3_600)
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h" }
        return "\(max(1, Int(seconds / 60))) min"
    }
}
