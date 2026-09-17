import Foundation
import Combine

/// The social layer as the screens see it: one backend (`CloudKitSocialBackend`
/// when the build is signed for iCloud and an account is present, the
/// seeded `LocalSocialBackend` otherwise), its state published, and every
/// action a screen can take as one async call that reports its failure in
/// plain words (`notice`).
///
/// It builds the player's profile FROM a `Player` it is handed — the name,
/// level, arena points, the total power the store shows and the arena
/// DEFENCE team as the snapshot — and never touches `GameStore`. Claiming a
/// mail hands the grants back to the caller, who pays them through the
/// store; a war attack's engine is built here exactly as an arena attack's
/// is, and the result is reported back through `reportWarAttack`.
@MainActor
final class SocialService: ObservableObject {
    @Published private(set) var availability: SocialAvailability = .checking
    @Published private(set) var profile: SocialProfile?
    @Published private(set) var friends: [Friendship] = []
    @Published private(set) var requests: [FriendRequest] = []
    @Published private(set) var searchResults: [SocialProfile] = []
    @Published private(set) var mail: [Mail] = []
    @Published private(set) var guild: Guild?
    @Published private(set) var members: [GuildMember] = []
    @Published private(set) var board: [BoardPost] = []
    @Published private(set) var war: GuildWar?
    @Published private(set) var guildsFound: [Guild] = []
    @Published private(set) var arenaLeaderboard: [LeaderboardEntry] = []
    @Published private(set) var guildLeaderboard: [LeaderboardEntry] = []
    @Published private(set) var isRefreshing = false
    /// Summoners a request went to this session, so their row says "Sent".
    @Published private(set) var sentRequestIDs: Set<String> = []
    /// Friends greeted this session: one greeting a friend a sitting.
    @Published private(set) var greetedIDs: Set<String> = []
    /// The last thing worth a line on the screen: an error, or a receipt.
    @Published var notice: String?

    private(set) var backend: SocialBackend
    private let cloud: CloudKitSocialBackend?
    private let fallback: LocalSocialBackend

    var backendName: String { backend.name }
    var unclaimedMail: Int { mail.filter { !$0.claimed && $0.hasGrants }.count }
    /// What the island's badge counts: requests waiting and mail unclaimed.
    var pendingCount: Int { requests.count + unclaimedMail }

    /// `nil` chooses: CloudKit when the binary is signed for it, the
    /// offline world otherwise. The tour and the tests pass a
    /// `LocalSocialBackend` of their own.
    init(backend: SocialBackend? = nil) {
        if let backend {
            self.backend = backend
            self.cloud = backend as? CloudKitSocialBackend
            self.fallback = (backend as? LocalSocialBackend) ?? LocalSocialBackend()
        } else if CloudKitSocialBackend.isEntitled {
            let cloud = CloudKitSocialBackend()
            self.backend = cloud
            self.cloud = cloud
            self.fallback = LocalSocialBackend()
        } else {
            let local = LocalSocialBackend(notice: SocialAvailability.notEntitled)
            self.backend = local
            self.cloud = nil
            self.fallback = local
        }
    }

    // MARK: - The player's profile

    /// The profile the backends store, from the save: the power is the
    /// store's own `totalPower` (the best five units), the defence is the
    /// arena defence team resolved through its relics and snapshotted.
    nonisolated static func profile(from player: Player, id: String, guild: Guild?) -> SocialProfile {
        let defence = CampaignService.resolveTeam(player.arenaDefenseTeam, player: player)
        let powers = player.units
            .compactMap { ProgressionService.resolve($0, relics: player.relics, boons: player.boons ?? []) }
            .map { $0.power }
            .sorted(by: >)
        let power = powers.prefix(5).reduce(0, +)
        return SocialProfile(
            id: id,
            name: player.displayName,
            level: player.level,
            power: power,
            arenaPoints: player.arena.points,
            guildID: guild?.id,
            guildName: guild?.name,
            defence: defence.map { TeamSnapshotUnit.snapshot(of: $0) },
            updatedAt: Date()
        )
    }

    // MARK: - Refresh

    /// Availability, then the profile published, then everything read.
    func refresh(player: Player) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await checkAvailability()
        await publish(player: player)
        await load()
    }

    /// The cloud whenever it answers; the offline world when it does not.
    private func checkAvailability() async {
        guard let cloud else {
            availability = await backend.availability()
            return
        }
        let status = await cloud.availability()
        switch status {
        case .online:
            backend = cloud
            availability = .online
        case .offline:
            backend = fallback
            availability = status
        case .checking:
            availability = .checking
        }
    }

    func publish(player: Player) async {
        let draft = SocialService.profile(from: player, id: profile?.id ?? "", guild: guild)
        do {
            profile = try await backend.publish(profile: draft)
        } catch {
            report(error)
        }
    }

    private func load() async {
        let source = backend
        async let friendsRead = try source.friends()
        async let requestsRead = try source.friendRequests()
        async let mailRead = try source.mail()
        async let guildRead = try source.guild()
        async let arenaRead = try source.leaderboard(kind: .arena)
        async let guildsRead = try source.leaderboard(kind: .guild)
        friends = (try? await friendsRead) ?? friends
        requests = (try? await requestsRead) ?? requests
        mail = (try? await mailRead) ?? mail
        arenaLeaderboard = (try? await arenaRead) ?? arenaLeaderboard
        guildLeaderboard = (try? await guildsRead) ?? guildLeaderboard
        do {
            guild = try await guildRead
        } catch {
            report(error)
        }
        await loadGuildDetails()
    }

    private func loadGuildDetails() async {
        guard guild != nil else {
            members = []
            board = []
            war = nil
            return
        }
        let source = backend
        async let membersRead = try source.guildMembers()
        async let boardRead = try source.board()
        async let warRead = try source.war()
        members = (try? await membersRead) ?? []
        board = (try? await boardRead) ?? []
        do {
            war = try await warRead
        } catch {
            report(error)
        }
    }

    func loadLeaderboards() async {
        let source = backend
        async let arenaRead = try source.leaderboard(kind: .arena)
        async let guildsRead = try source.leaderboard(kind: .guild)
        arenaLeaderboard = (try? await arenaRead) ?? arenaLeaderboard
        guildLeaderboard = (try? await guildsRead) ?? guildLeaderboard
    }

    // MARK: - Friends

    func search(name: String) async {
        do {
            searchResults = try await backend.search(name: name)
        } catch {
            report(error)
        }
    }

    func sendFriendRequest(to target: SocialProfile) async {
        do {
            let request = try await backend.sendFriendRequest(to: target.id)
            sentRequestIDs.insert(target.id)
            switch request.status {
            case .accepted:
                notice = "\(target.name) accepted your request."
                friends = (try? await backend.friends()) ?? friends
            case .declined:
                notice = "\(target.name) declined."
            case .pending:
                notice = "Request sent to \(target.name)."
            }
        } catch {
            report(error)
        }
    }

    func respond(_ request: FriendRequest, accept: Bool) async {
        do {
            try await backend.respond(request: request, accept: accept)
            requests.removeAll { $0.id == request.id }
            if accept {
                friends = (try? await backend.friends()) ?? friends
                notice = "\(request.fromName) is now a friend."
            }
        } catch {
            report(error)
        }
    }

    func isFriend(_ profileID: String) -> Bool {
        friends.contains { $0.friend.id == profileID }
    }

    func sendGreeting(to friendship: Friendship) async {
        guard let profile else {
            notice = "Your profile is not published yet. Refresh and try again."
            return
        }
        guard !greetedIDs.contains(friendship.friend.id) else {
            notice = "\(friendship.friend.name) has had your greeting today."
            return
        }
        do {
            try await backend.send(mail: Mail.greeting(from: profile, to: friendship.friend))
            greetedIDs.insert(friendship.friend.id)
            notice = "Greeting sent to \(friendship.friend.name)."
            mail = (try? await backend.mail()) ?? mail
        } catch {
            report(error)
        }
    }

    // MARK: - Mail

    /// Marks the mail claimed and returns what it carried, for the caller
    /// to pay through the store. Empty when it was already claimed.
    func claim(_ item: Mail) async -> [ShopService.Grant] {
        do {
            let grants = try await backend.claim(mail: item)
            if let index = mail.firstIndex(where: { $0.id == item.id }) {
                mail[index].claimed = true
            }
            return grants
        } catch {
            report(error)
            return []
        }
    }

    // MARK: - Guild

    func findGuilds(name: String) async {
        do {
            guildsFound = try await backend.findGuilds(name: name)
        } catch {
            report(error)
        }
    }

    func createGuild(name: String, crest: String) async {
        do {
            guild = try await backend.createGuild(name: name, crest: crest)
            notice = "\(name.trimmingCharacters(in: .whitespacesAndNewlines)) is founded."
            await afterGuildChange()
        } catch {
            report(error)
        }
    }

    func joinGuild(_ candidate: Guild) async {
        do {
            guild = try await backend.joinGuild(id: candidate.id)
            notice = "You joined \(candidate.name)."
            await afterGuildChange()
        } catch {
            report(error)
        }
    }

    func leaveGuild() async {
        do {
            try await backend.leaveGuild()
            guild = nil
            notice = "You left the guild."
            await afterGuildChange()
        } catch {
            report(error)
        }
    }

    private func afterGuildChange() async {
        profile = (try? await backend.myProfile()) ?? profile
        await loadGuildDetails()
        await loadLeaderboards()
    }

    func post(_ text: String) async {
        do {
            let posted = try await backend.postToBoard(text: text)
            board.insert(posted, at: 0)
        } catch {
            report(error)
        }
    }

    // MARK: - The war

    /// The fight, exactly as an arena attack: the player's arena OFFENCE
    /// team against the target's defence snapshot, in the arena mode. Nil,
    /// with the reason in `notice`, when either side has nobody.
    func warBattle(against target: WarTarget, player: Player, seed: UInt64) -> BattleEngine? {
        let offence = CampaignService.resolveTeam(player.arenaOffenseTeam, player: player)
        guard !offence.isEmpty else {
            notice = "Set an arena offence team before you attack."
            return nil
        }
        let defence = target.opponentTeam
        guard !defence.isEmpty else {
            notice = "\(target.profile.name)'s defence has no unit this build knows."
            return nil
        }
        return BattleEngine(
            playerTeam: Array(offence.prefix(ArenaService.teamSize)),
            opponentTeam: defence,
            mode: .arenaOffense,
            seed: seed
        )
    }

    /// Reports a fought attack and returns the points it earned.
    @discardableResult
    func reportWarAttack(against target: WarTarget, result: BattleResult) async -> Int {
        let outcome = WarAttackResult(target: target, result: result)
        let points = target.beaten ? 0 : WarRules.points(
            won: outcome.won,
            attackerPower: profile?.power ?? 0,
            targetPower: target.profile.power
        )
        do {
            _ = try await backend.reportWarAttack(result: outcome)
            notice = outcome.won
                ? "Victory over \(target.profile.name): +\(points) war points."
                : "\(target.profile.name)'s defence held."
            await loadGuildDetails()
            return points
        } catch {
            report(error)
            return 0
        }
    }

    // MARK: - Errors

    private func report(_ error: Error) {
        let message = (error as? SocialError)?.message ?? error.localizedDescription
        notice = message
        DiagnosticsLog.shared.record("[Social] \(backend.name): \(message)")
    }
}
