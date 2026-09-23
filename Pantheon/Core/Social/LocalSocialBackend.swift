import Foundation

/// The social layer with nobody on the other end: what the screens run on
/// when CloudKit cannot be used — an unsigned build (the CI tour and its
/// tests), a device with no iCloud account, a container that answered with
/// an error — so a screen is never empty and every flow can be exercised.
///
/// One number seeds a small world: twelve rival summoners with defence teams
/// rolled from the summon pool through the same resolve the arena's
/// challengers go through, four guilds with members and a board, one
/// welcome mail with a small gift, one waiting friend request, one friend
/// already made. A rival answers a friend request on the spot — the ones
/// whose names hash even accept, the rest decline — and returns a greeting
/// with a greeting, so the loops close without a second phone.
///
/// What the player does here (friends, mail claimed, the guild joined, the
/// attacks fought) is kept in `UserDefaults` under `storageKey` when
/// `persisting`; the rivals themselves are regenerated from the seed on
/// every launch, so a roster change can never leave a dangling family.
final class LocalSocialBackend: SocialBackend, @unchecked Sendable {
    static let storageKey = "social.local.v1"
    static let me = "local_me"
    static let systemSender = "system"

    let name = "Offline"

    private let lock = NSLock()
    /// Built on the first call, under the lock: the seeded world resolves
    /// forty-eight units through their relics, which is not a thing to do in
    /// an initialiser that may run on the main thread at launch.
    private var state = LocalSocialState()
    private var loaded = false
    private let seed: UInt64
    private let persisting: Bool
    private let notice: String
    private let clock: @Sendable () -> Date

    /// The tour's and the tests' seed is 7; the notice is what the screens
    /// print under the strip.
    init(
        seed: UInt64 = 7,
        persisting: Bool = true,
        notice: String = SocialAvailability.noAccount,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.seed = seed
        self.persisting = persisting
        self.notice = notice
        self.clock = now
    }

    /// The seeded people and places come back fresh every launch; what the
    /// player did with them is what the save keeps.
    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        let world = LocalSocialBackend.seededWorld(seed: seed, now: clock())
        guard persisting, let saved = LocalSocialBackend.load() else {
            state = world
            return
        }
        var merged = saved
        merged.rivals = world.rivals
        for index in merged.friendships.indices {
            if let fresh = world.rivals.first(where: { $0.id == merged.friendships[index].friend.id }) {
                merged.friendships[index].friend = fresh
            }
        }
        for guild in world.guilds where !merged.guilds.contains(where: { $0.id == guild.id }) {
            merged.guilds.append(guild)
        }
        for member in world.members where !merged.members.contains(where: { $0.id == member.id }) {
            merged.members.append(member)
        }
        for post in world.posts where !merged.posts.contains(where: { $0.id == post.id }) {
            merged.posts.append(post)
        }
        state = merged
    }

    // MARK: - SocialBackend

    func availability() async -> SocialAvailability { .offline(notice) }

    func myProfile() async throws -> SocialProfile? {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return state.profile
    }

    func publish(profile: SocialProfile) async throws -> SocialProfile {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        var stamped = profile
        stamped.id = LocalSocialBackend.me
        if let membership = state.members.first(where: { $0.userID == LocalSocialBackend.me }),
           let guild = state.guilds.first(where: { $0.id == membership.guildID }) {
            stamped.guildID = guild.id
            stamped.guildName = guild.name
        } else {
            stamped.guildID = nil
            stamped.guildName = nil
        }
        state.profile = stamped
        // The member row wears the profile's numbers, as the roster shows them.
        if let index = state.members.firstIndex(where: { $0.userID == LocalSocialBackend.me }) {
            state.members[index].name = stamped.name
            state.members[index].level = stamped.level
            state.members[index].power = stamped.power
        }
        save()
        return stamped
    }

    func search(name: String) async throws -> [SocialProfile] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        let key = SocialProfile.key(name)
        guard !key.isEmpty else { return [] }
        return state.rivals
            .filter { $0.nameKey.hasPrefix(key) }
            .sorted { $0.arenaPoints > $1.arenaPoints }
    }

    func friends() async throws -> [Friendship] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return state.friendships.sorted { $0.since > $1.since }
    }

    func friendRequests() async throws -> [FriendRequest] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return state.incoming.filter { $0.status == .pending }.sorted { $0.sentAt > $1.sentAt }
    }

    func sendFriendRequest(to profileID: String) async throws -> FriendRequest {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        guard let rival = state.rivals.first(where: { $0.id == profileID }) else {
            throw SocialError.notFound("That demigod")
        }
        if state.friendships.contains(where: { $0.friend.id == profileID }) {
            throw SocialError.conflict("\(rival.name) is already a friend.")
        }
        if state.outgoing.contains(where: { $0.toID == profileID && $0.status == .pending }) {
            throw SocialError.conflict("A request to \(rival.name) is already waiting.")
        }
        let now = clock()
        let me = state.profile?.name ?? "Demigod"
        var request = FriendRequest(
            id: FriendRequest.id(from: LocalSocialBackend.me, to: profileID),
            fromID: LocalSocialBackend.me,
            fromName: me,
            toID: profileID,
            status: .pending,
            sentAt: now
        )
        // The rival answers at once: even hashes accept, odd ones decline.
        let accepts = WarRules.hash(rival.name) % 2 == 0
        request.status = accepts ? .accepted : .declined
        state.outgoing.removeAll { $0.id == request.id }
        state.outgoing.append(request)
        if accepts {
            befriend(rival, now: now)
        }
        save()
        return request
    }

    func respond(request: FriendRequest, accept: Bool) async throws {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        guard let index = state.incoming.firstIndex(where: { $0.id == request.id }) else {
            throw SocialError.notFound("That request")
        }
        state.incoming[index].status = accept ? .accepted : .declined
        if accept, let rival = state.rivals.first(where: { $0.id == request.fromID }) {
            befriend(rival, now: clock())
        }
        save()
    }

    func mail() async throws -> [Mail] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return state.mail.sorted { $0.sentAt > $1.sentAt }
    }

    func send(mail: Mail) async throws {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        guard let rival = state.rivals.first(where: { $0.id == mail.toID }) else {
            throw SocialError.notFound("That demigod")
        }
        // Nobody reads a rival's inbox here, so the greeting comes straight
        // back: the genre's friendship points, both ways.
        let reply = Mail(
            id: "mail_\(UUID().uuidString.lowercased())",
            toID: LocalSocialBackend.me,
            fromID: rival.id,
            fromName: rival.name,
            subject: "\(rival.name) returns your greeting",
            body: "\"Well met, \(mail.fromName). The island keeps you in mind.\"",
            grants: [.scrolls(.mystical, 2)],
            claimed: false,
            sentAt: clock()
        )
        state.mail.append(reply)
        save()
    }

    func claim(mail: Mail) async throws -> [ShopService.Grant] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        guard let index = state.mail.firstIndex(where: { $0.id == mail.id }) else {
            throw SocialError.notFound("That mail")
        }
        guard !state.mail[index].claimed else {
            throw SocialError.conflict("That mail was already claimed.")
        }
        state.mail[index].claimed = true
        save()
        return state.mail[index].grants
    }

    func guild() async throws -> Guild? {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return currentGuild()
    }

    func findGuilds(name: String) async throws -> [Guild] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        let key = SocialProfile.key(name)
        return state.guilds
            .filter { key.isEmpty || $0.nameKey.hasPrefix(key) }
            .sorted { $0.warPoints > $1.warPoints }
    }

    func createGuild(name: String, crest: String) async throws -> Guild {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 24 else {
            throw SocialError.invalid("A guild's name is two to twenty-four characters.")
        }
        guard currentGuild() == nil else { throw SocialError.conflict("Leave your guild before founding another.") }
        let key = SocialProfile.key(trimmed)
        guard !state.guilds.contains(where: { $0.nameKey == key }) else {
            throw SocialError.conflict("A guild called \(trimmed) already exists.")
        }
        let now = clock()
        let guild = Guild(
            id: "guild_\(UUID().uuidString.lowercased())",
            name: trimmed,
            crest: Guild.crests.contains(crest) ? crest : Guild.crests[0],
            leaderID: LocalSocialBackend.me,
            memberCount: 1,
            warPoints: 0,
            season: WarRules.seasonKey(for: now),
            weekKey: WarRules.weekKey(for: now),
            weekPoints: 0,
            createdAt: now
        )
        state.guilds.append(guild)
        state.members.append(membership(in: guild, role: .leader, now: now))
        refreshProfileGuild()
        save()
        return guild
    }

    func joinGuild(id: String) async throws -> Guild {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        guard currentGuild() == nil else { throw SocialError.conflict("Leave your guild before joining another.") }
        guard let index = state.guilds.firstIndex(where: { $0.id == id }) else {
            throw SocialError.notFound("That guild")
        }
        guard !state.guilds[index].isFull else {
            throw SocialError.conflict("\(state.guilds[index].name) is full.")
        }
        state.guilds[index].memberCount += 1
        state.members.append(membership(in: state.guilds[index], role: .member, now: clock()))
        refreshProfileGuild()
        save()
        return state.guilds[index]
    }

    func leaveGuild() async throws {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        guard let guild = currentGuild(), let index = state.guilds.firstIndex(where: { $0.id == guild.id }) else {
            throw SocialError.conflict("You are not in a guild.")
        }
        state.members.removeAll { $0.userID == LocalSocialBackend.me }
        let remaining = state.members
            .filter { $0.guildID == guild.id }
            .sorted { $0.joinedAt < $1.joinedAt }
        if remaining.isEmpty {
            state.guilds.remove(at: index)
            state.posts.removeAll { $0.guildID == guild.id }
        } else {
            state.guilds[index].memberCount = remaining.count
            if guild.leaderID == LocalSocialBackend.me, let heir = remaining.first {
                state.guilds[index].leaderID = heir.userID
                if let heirIndex = state.members.firstIndex(where: { $0.id == heir.id }) {
                    state.members[heirIndex].role = .leader
                }
            }
        }
        refreshProfileGuild()
        save()
    }

    func guildMembers() async throws -> [GuildMember] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        guard let guild = currentGuild() else { return [] }
        return members(of: guild.id, now: clock())
    }

    func postToBoard(text: String) async throws -> BoardPost {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SocialError.invalid("Write something first.") }
        guard trimmed.count <= 200 else { throw SocialError.invalid("A post is two hundred characters at most.") }
        guard let guild = currentGuild() else { throw SocialError.conflict("Join a guild to use its board.") }
        let post = BoardPost(
            id: "post_\(UUID().uuidString.lowercased())",
            guildID: guild.id,
            authorID: LocalSocialBackend.me,
            authorName: state.profile?.name ?? "Demigod",
            text: trimmed,
            postedAt: clock()
        )
        state.posts.append(post)
        save()
        return post
    }

    func board() async throws -> [BoardPost] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        guard let guild = currentGuild() else { return [] }
        return state.posts
            .filter { $0.guildID == guild.id }
            .sorted { $0.postedAt > $1.postedAt }
    }

    func war() async throws -> GuildWar? {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        return currentWar(now: clock())
    }

    func reportWarAttack(result: WarAttackResult) async throws -> WarStanding {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        let now = clock()
        guard let guild = currentGuild(), let index = state.guilds.firstIndex(where: { $0.id == guild.id }) else {
            throw SocialError.conflict("Join a guild to fight its war.")
        }
        guard let war = currentWar(now: now) else {
            throw SocialError.conflict("There is no war this week.")
        }
        guard result.targetGuildID == war.opponent.id,
              war.targets.contains(where: { $0.id == result.targetID }) else {
            throw SocialError.invalid("That demigod is not in the opposing guild.")
        }
        guard war.attacksLeftToday > 0 else {
            throw SocialError.conflict("No war attacks left today. They return at midnight UTC.")
        }
        let week = WarRules.weekKey(for: now)
        // A second win over a target already beaten this week scores nothing;
        // the attack is still spent and recorded.
        let alreadyBeaten = state.attacks.contains {
            $0.week == week && $0.attackerID == LocalSocialBackend.me && $0.targetID == result.targetID && $0.won
        }
        let points = alreadyBeaten ? 0 : WarRules.points(
            won: result.won,
            attackerPower: state.profile?.power ?? 0,
            targetPower: result.targetPower
        )
        state.attacks.append(
            LocalWarAttack(
                week: week,
                day: WarRules.dayKey(for: now),
                attackerID: LocalSocialBackend.me,
                guildID: guild.id,
                targetID: result.targetID,
                targetGuildID: result.targetGuildID,
                won: result.won,
                points: points,
                foughtAt: now
            )
        )
        // The guild's points: this week's, and the season's, which start
        // over with the first report of a new week or month.
        var updated = state.guilds[index]
        let season = WarRules.seasonKey(for: now)
        if updated.season != season {
            updated.season = season
            updated.warPoints = 0
        }
        if updated.weekKey != week {
            updated.weekKey = week
            updated.weekPoints = 0
        }
        updated.weekPoints += points
        updated.warPoints += points
        state.guilds[index] = updated
        save()
        guard let mineNow = currentWar(now: now)?.mine else {
            throw SocialError.unknown("The standings could not be read back.")
        }
        return mineNow
    }

    func leaderboard(kind: LeaderboardKind) async throws -> [LeaderboardEntry] {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded()
        switch kind {
        case .arena:
            var everyone = state.rivals
            if let profile = state.profile { everyone.append(profile) }
            let ordered = everyone.sorted {
                $0.arenaPoints == $1.arenaPoints ? $0.name < $1.name : $0.arenaPoints > $1.arenaPoints
            }
            return ordered.enumerated().map { offset, profile in
                LeaderboardEntry(
                    id: profile.id,
                    rank: offset + 1,
                    name: profile.name,
                    detail: "Lv.\(profile.level) · \(profile.tier.displayName) · power \(profile.power.formatted())",
                    score: profile.arenaPoints,
                    crest: nil,
                    isMine: profile.id == LocalSocialBackend.me
                )
            }
        case .guild:
            let mine = currentGuild()?.id
            let ordered = state.guilds.sorted {
                $0.warPoints == $1.warPoints ? $0.name < $1.name : $0.warPoints > $1.warPoints
            }
            return ordered.enumerated().map { offset, guild in
                LeaderboardEntry(
                    id: guild.id,
                    rank: offset + 1,
                    name: guild.name,
                    detail: "\(guild.memberCount) member\(guild.memberCount == 1 ? "" : "s")",
                    score: guild.warPoints,
                    crest: guild.crest,
                    isMine: guild.id == mine
                )
            }
        }
    }

    // MARK: - The world behind the lock

    private func currentGuild() -> Guild? {
        guard let membership = state.members.first(where: { $0.userID == LocalSocialBackend.me }) else { return nil }
        return state.guilds.first(where: { $0.id == membership.guildID })
    }

    private func membership(in guild: Guild, role: GuildRole, now: Date) -> GuildMember {
        GuildMember(
            id: GuildMember.id(userID: LocalSocialBackend.me),
            userID: LocalSocialBackend.me,
            guildID: guild.id,
            name: state.profile?.name ?? "Demigod",
            level: state.profile?.level ?? 1,
            power: state.profile?.power ?? 0,
            role: role,
            joinedAt: now
        )
    }

    private func refreshProfileGuild() {
        guard var profile = state.profile else { return }
        if let guild = currentGuild() {
            profile.guildID = guild.id
            profile.guildName = guild.name
        } else {
            profile.guildID = nil
            profile.guildName = nil
        }
        state.profile = profile
    }

    private func befriend(_ rival: SocialProfile, now: Date) {
        guard !state.friendships.contains(where: { $0.friend.id == rival.id }) else { return }
        state.friendships.append(
            Friendship(
                id: Friendship.id(LocalSocialBackend.me, rival.id),
                members: [LocalSocialBackend.me, rival.id],
                since: now,
                friend: rival
            )
        )
    }

    /// A guild's members with this week's points: the player's from the
    /// attacks recorded, a rival's seeded from the week and the day so the
    /// numbers move as the week goes on and never change under a screen.
    private func members(of guildID: String, now: Date) -> [GuildMember] {
        let week = WarRules.weekKey(for: now)
        let days = LocalSocialBackend.daysIntoWeek(now)
        return state.members
            .filter { $0.guildID == guildID }
            .map { member in
                var scored = member
                if member.userID == LocalSocialBackend.me {
                    scored.weekPoints = state.attacks
                        .filter { $0.week == week && $0.attackerID == member.userID }
                        .reduce(0) { $0 + $1.points }
                } else {
                    scored.weekPoints = LocalSocialBackend.seededWeekPoints(member: member, week: week, days: days)
                }
                return scored
            }
            .sorted { $0.weekPoints == $1.weekPoints ? $0.joinedAt < $1.joinedAt : $0.weekPoints > $1.weekPoints }
    }

    private func currentWar(now: Date) -> GuildWar? {
        guard let guild = currentGuild(),
              let opponent = WarRules.opponent(for: guild, among: state.guilds, week: WarRules.weekKey(for: now)) else {
            return nil
        }
        let week = WarRules.weekKey(for: now)
        let day = WarRules.dayKey(for: now)
        let myAttacks = state.attacks.filter { $0.week == week && $0.attackerID == LocalSocialBackend.me }
        let today = myAttacks.filter { $0.day == day }.count
        let myPower = state.profile?.power ?? 0
        let targets: [WarTarget] = state.members
            .filter { $0.guildID == opponent.id }
            .compactMap { member -> WarTarget? in
                guard let profile = state.rivals.first(where: { $0.id == member.userID }) else { return nil }
                return WarTarget(
                    id: profile.id,
                    profile: profile,
                    guildID: opponent.id,
                    beaten: myAttacks.contains { $0.targetID == profile.id && $0.won },
                    pointsForWin: WarRules.points(won: true, attackerPower: myPower, targetPower: profile.power)
                )
            }
            .sorted { $0.profile.power < $1.profile.power }
        return GuildWar(
            week: week,
            opponent: opponent,
            targets: targets,
            standings: [standing(of: guild, mine: true, now: now), standing(of: opponent, mine: false, now: now)],
            attacksLeftToday: max(0, WarRules.attacksPerDay - today),
            endsAt: WarRules.weekEnd(for: now)
        )
    }

    private func standing(of guild: Guild, mine: Bool, now: Date) -> WarStanding {
        let week = WarRules.weekKey(for: now)
        let days = LocalSocialBackend.daysIntoWeek(now)
        var points = 0
        var wins = 0
        var attacks = 0
        for member in state.members where member.guildID == guild.id {
            if member.userID == LocalSocialBackend.me {
                let fought = state.attacks.filter { $0.week == week && $0.attackerID == member.userID }
                points += fought.reduce(0) { $0 + $1.points }
                wins += fought.filter(\.won).count
                attacks += fought.count
            } else {
                let scored = LocalSocialBackend.seededWeekPoints(member: member, week: week, days: days)
                points += scored
                wins += scored / WarRules.winPoints
                attacks += min(WarRules.attacksPerDay * days, scored / WarRules.winPoints + days)
            }
        }
        return WarStanding(
            id: guild.id,
            guildName: guild.name,
            crest: guild.crest,
            points: points,
            wins: wins,
            attacks: attacks,
            isMine: mine
        )
    }

    /// Monday is 1, Sunday 7: how many battle days of the week have opened.
    static func daysIntoWeek(_ date: Date) -> Int {
        let weekday = WarRules.calendar.component(.weekday, from: date)
        return ((weekday + 5) % 7) + 1
    }

    /// A rival's points so far this week: between five and twenty-five a
    /// day, from the hash of the week and the rival.
    static func seededWeekPoints(member: GuildMember, week: String, days: Int) -> Int {
        let perDay = Int(WarRules.hash(week + member.userID) % 21) + 5
        return perDay * max(0, days)
    }

    // MARK: - Persistence

    private func save() {
        guard persisting else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            UserDefaults.standard.set(data, forKey: LocalSocialBackend.storageKey)
        }
    }

    private static func load() -> LocalSocialState? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocalSocialState.self, from: data)
    }

    /// Forgets everything the player did offline. The settings screen's
    /// account reset should call it.
    static func wipe() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - The seed

    private static let rivalNames = [
        "Amunet", "Kallias", "Sigrun", "Ptahmose", "Hypatia", "Eirik",
        "Nefertari", "Straton", "Ragnhild", "Zenon", "Meryt", "Lysander",
    ]

    private static let guildSeeds: [(name: String, crest: String, points: Int)] = [
        (name: "The Ennead", crest: "sun.max.fill", points: 640),
        (name: "Wolves of the Tiber", crest: "shield.lefthalf.filled", points: 410),
        (name: "Ravens of Asgard", crest: "bolt.fill", points: 880),
        (name: "Jade Lanterns", crest: "moon.stars.fill", points: 230),
    ]

    private static let boardLines = [
        "Good hunting this week. Hit the lowest power first and leave the wardens to the six-stars.",
        "Three attacks a day each, every day. The bar only moves if we all show up.",
        "Welcome to the newcomers. Set a defence you would not want to fight yourself.",
        "The Ennead's leader runs a Vigil set on everything; bring a stripper.",
        "Rank rewards land Monday. Do not spend your laurels before then.",
    ]

    /// Families to draw a rival's team from when the summon pool is empty —
    /// a build with no cards in the bundle. Every one is hand-written and
    /// always in the database.
    private static let fallbackFamilies = [
        "anubis_ember", "sekhmet_ember", "zeus_ember", "ares_ember", "thoth_tide",
        "heracles_ember", "perseus_radiance", "hoplite_tide", "satyr_gale", "harpy_tide",
        "anubis_umbra", "sekhmet_tide", "zeus_gale", "ares_radiance", "thoth_umbra",
    ]

    static func seededWorld(seed: UInt64, now: Date) -> LocalSocialState {
        var rng = SeededRandom(seed: seed &+ 0x50C1_A1)
        var world = LocalSocialState()

        // Twelve rivals, spread from a fresh account to a built one.
        for (index, rivalName) in rivalNames.enumerated() {
            let rating = 950 + index * 230 + rng.int(in: -60...60)
            let defence = rivalDefence(rating: rating, rng: &rng)
            let power = defence.reduce(0) { $0 + $1.power }
            let level = min(60, 8 + Int(Double(rating - 900) / 3_000 * 50) + rng.int(in: 0...4))
            world.rivals.append(
                SocialProfile(
                    id: "rival_\(index)",
                    name: rivalName,
                    level: level,
                    power: power,
                    arenaPoints: rating,
                    defence: defence,
                    updatedAt: now.addingTimeInterval(-Double(rng.int(in: 600...86_400)))
                )
            )
        }

        // Four guilds of three, the strongest rivals in the strongest guild.
        let byStrength = world.rivals.sorted { $0.arenaPoints > $1.arenaPoints }
        for (index, seedGuild) in guildSeeds.enumerated() {
            let guildID = "guild_seed_\(index)"
            let founded = now.addingTimeInterval(-Double(30 + index * 9) * 86_400)
            let crew = Array(byStrength.dropFirst(index * 3).prefix(3))
            for (slot, rival) in crew.enumerated() {
                world.members.append(
                    GuildMember(
                        id: GuildMember.id(userID: rival.id),
                        userID: rival.id,
                        guildID: guildID,
                        name: rival.name,
                        level: rival.level,
                        power: rival.power,
                        role: slot == 0 ? .leader : .member,
                        joinedAt: founded.addingTimeInterval(Double(slot) * 3_600)
                    )
                )
            }
            world.guilds.append(
                Guild(
                    id: guildID,
                    name: seedGuild.name,
                    crest: seedGuild.crest,
                    leaderID: crew.first?.id ?? "",
                    memberCount: crew.count,
                    warPoints: seedGuild.points,
                    season: WarRules.seasonKey(for: now),
                    weekKey: "",
                    weekPoints: 0,
                    createdAt: founded
                )
            )
            for line in 0..<2 {
                let author = crew[min(crew.count - 1, line)]
                world.posts.append(
                    BoardPost(
                        id: "post_seed_\(index)_\(line)",
                        guildID: guildID,
                        authorID: author.id,
                        authorName: author.name,
                        text: boardLines[(index * 2 + line) % boardLines.count],
                        postedAt: now.addingTimeInterval(-Double(3 + line * 20) * 3_600)
                    )
                )
            }
        }

        // The welcome, a friend already made and a request waiting.
        world.mail.append(
            Mail(
                id: "mail_welcome",
                toID: me,
                fromID: systemSender,
                fromName: "The Island",
                subject: "Welcome, Demigod",
                body: "The other demigods will find you once you sign in to iCloud. Until then, a gift for the road.",
                grants: [.scrolls(.mystical, 3), .drachma(5_000)],
                claimed: false,
                sentAt: now.addingTimeInterval(-7_200)
            )
        )
        if let first = world.rivals.first {
            world.friendships.append(
                Friendship(
                    id: Friendship.id(me, first.id),
                    members: [me, first.id],
                    since: now.addingTimeInterval(-3 * 86_400),
                    friend: first
                )
            )
        }
        if world.rivals.count > 3 {
            let asker = world.rivals[3]
            world.incoming.append(
                FriendRequest(
                    id: FriendRequest.id(from: asker.id, to: me),
                    fromID: asker.id,
                    fromName: asker.name,
                    toID: me,
                    status: .pending,
                    sentAt: now.addingTimeInterval(-5_400)
                )
            )
        }
        return world
    }

    /// A rival's defence at a rating: the arena challenger's own recipe —
    /// level, grade and relics climb with the points — snapshotted.
    private static func rivalDefence(rating: Int, rng: inout SeededRandom) -> [TeamSnapshotUnit] {
        let normalized = min(1.0, max(0.0, Double(rating - 900) / 3_000))
        let level = Int(15 + normalized * 45)
        let stars = min(6, 3 + Int(normalized * 3))
        let relicGrade = min(6, 3 + Int(normalized * 3))
        let relicLevel = Int(normalized * 15)
        var pool = UnitDatabase.summonPool
        if pool.isEmpty { pool = fallbackFamilies }
        let picks = Array(rng.shuffled(pool).prefix(ArenaService.teamSize))
        var team: [TeamSnapshotUnit] = []
        for blueprintID in picks {
            guard let blueprint = UnitDatabase.blueprint(blueprintID) else { continue }
            let unitStars = min(6, max(blueprint.naturalStars, stars))
            var unit = Unit(
                blueprint: blueprint,
                level: min(ProgressionService.maxLevel(stars: unitStars), level),
                stars: unitStars,
                awakened: normalized > 0.4 && blueprint.awakening != nil
            )
            unit.skillLevels = blueprint.skills.map { _ in max(1, Int(normalized * 5)) }
            let primary: RelicSet = blueprint.role == .attacker ? .fury : .bulwark
            let secondary: RelicSet = blueprint.role == .attacker ? .ruin : .vigil
            let relics = RelicService.generateLoadout(
                grade: relicGrade,
                primarySet: primary,
                secondarySet: secondary,
                upgradeLevel: relicLevel,
                rng: &rng
            )
            let resolved = ProgressionService.resolve(unit, blueprint: blueprint, equipped: relics)
            team.append(TeamSnapshotUnit.snapshot(of: resolved))
        }
        return team
    }
}

/// Everything the offline world holds, as one JSON value in `UserDefaults`.
struct LocalSocialState: Codable, Equatable, Sendable {
    var profile: SocialProfile? = nil
    var rivals: [SocialProfile] = []
    var friendships: [Friendship] = []
    var incoming: [FriendRequest] = []
    var outgoing: [FriendRequest] = []
    var mail: [Mail] = []
    var guilds: [Guild] = []
    var members: [GuildMember] = []
    var posts: [BoardPost] = []
    var attacks: [LocalWarAttack] = []
}

/// One fought war attack, as the offline world records it.
struct LocalWarAttack: Codable, Equatable, Sendable {
    var week: String
    var day: String
    var attackerID: String
    var guildID: String
    var targetID: String
    var targetGuildID: String
    var won: Bool
    var points: Int
    var foughtAt: Date
}
