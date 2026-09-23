import Foundation
import CloudKit

/// The social layer on CloudKit's PUBLIC database (`Docs/SOCIAL.md`): record
/// types named as the value types, the iCloud user record's name as the
/// player's identity, deterministic record ids wherever a thing must be
/// unique (one profile per account, one guild per player, one request per
/// pair, three war attacks a day), and every failure mapped to a
/// `SocialError` with a plain sentence.
///
/// Nothing here may run without the entitlement: a process that touches
/// `CKContainer` without `com.apple.developer.icloud-services` is killed
/// with an uncaught exception, not handed an error, and the CI job builds
/// the app unsigned. `isEntitled` reads the running binary's signature
/// first, and `SocialService` never constructs this class when it is false.
final class CloudKitSocialBackend: SocialBackend, @unchecked Sendable {
    /// The bundle id with the `iCloud.` prefix; it must equal the container
    /// in `Pantheon.entitlements` and the one the owner creates in Xcode.
    static let containerID = "iCloud.com.pantheon.game"

    let name = "CloudKit"

    private let container: CKContainer
    private let database: CKDatabase
    private let lock = NSLock()
    private var cachedUserID: String?
    private var cachedProfile: SocialProfile?

    /// Whether the running executable's code signature carries the iCloud
    /// entitlement. The signature embeds the entitlements as a plist blob
    /// (magic `0xFADE7171`, a big-endian length, the XML), so this reads the
    /// binary once and looks inside that blob and nowhere else — the key is
    /// assembled from two halves so the string in THIS file's constants
    /// cannot answer for it. An unsigned build has no blob and no
    /// entitlement, which is exactly the CI job's app. The container id must
    /// be in the blob too: a container named in code but not in the
    /// entitlements is the same uncatchable exception.
    static let isEntitled: Bool = {
        guard let url = Bundle.main.executableURL,
              let binary = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        let magic = Data([0xFA, 0xDE, 0x71, 0x71])
        let key = ["com.apple.developer", "icloud-services"].joined(separator: ".")
        var cursor = binary.startIndex
        while cursor < binary.endIndex,
              let found = binary.range(of: magic, options: [], in: cursor..<binary.endIndex) {
            let lengthStart = found.upperBound
            guard lengthStart + 4 <= binary.endIndex else { break }
            var length = 0
            for byte in binary[lengthStart..<(lengthStart + 4)] {
                length = (length << 8) | Int(byte)
            }
            let bodyStart = lengthStart + 4
            let bodyEnd = min(binary.endIndex, found.lowerBound + max(8, length))
            if bodyEnd > bodyStart,
               let plist = String(data: binary[bodyStart..<bodyEnd], encoding: .utf8),
               plist.contains(key), plist.contains("CloudKit"), plist.contains(containerID) {
                return true
            }
            cursor = found.upperBound
        }
        return false
    }()

    init(containerID: String = CloudKitSocialBackend.containerID) {
        let container = CKContainer(identifier: containerID)
        self.container = container
        self.database = container.publicCloudDatabase
    }

    // MARK: - Availability and identity

    func availability() async -> SocialAvailability {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available: return .online
            case .noAccount: return .offline(SocialAvailability.noAccount)
            case .restricted: return .offline(SocialAvailability.restricted)
            case .couldNotDetermine, .temporarilyUnavailable: return .offline(SocialAvailability.unreachable)
            @unknown default: return .offline(SocialAvailability.unreachable)
            }
        } catch {
            return .offline(SocialAvailability.unreachable)
        }
    }

    /// The iCloud user record's name: the player's identity everywhere.
    private func userID() async throws -> String {
        lock.lock()
        let cached = cachedUserID
        lock.unlock()
        if let cached { return cached }
        do {
            let recordID = try await container.userRecordID()
            let userName = recordID.recordName
            lock.lock()
            cachedUserID = userName
            lock.unlock()
            return userName
        } catch {
            throw CloudKitSocialBackend.map(error)
        }
    }

    private func rememberProfile(_ profile: SocialProfile) {
        lock.lock()
        cachedProfile = profile
        lock.unlock()
    }

    private func knownProfile() -> SocialProfile? {
        lock.lock()
        let profile = cachedProfile
        lock.unlock()
        return profile
    }

    // MARK: - Profile

    func myProfile() async throws -> SocialProfile? {
        let me = try await userID()
        guard let record = try await fetch(CloudKitSocialBackend.profileName(me)) else { return nil }
        let profile = CloudKitSocialBackend.profile(from: record)
        if let profile { rememberProfile(profile) }
        return profile
    }

    func publish(profile: SocialProfile) async throws -> SocialProfile {
        let me = try await userID()
        var stamped = profile
        stamped.id = me
        // The guild comes off the membership, never off what the caller says.
        if let membership = try await fetch(GuildMember.id(userID: me)),
           let guild = try await fetch(CloudKitSocialBackend.string(membership, "guildID")).map(CloudKitSocialBackend.guild(from:)) {
            stamped.guildID = guild.id
            stamped.guildName = guild.name
        } else {
            stamped.guildID = nil
            stamped.guildName = nil
        }
        let record = try await upsert(CloudKitSocialBackend.profileName(me), type: "SocialProfile") { record in
            try CloudKitSocialBackend.fill(record, with: stamped)
        }
        // The member row wears the same numbers as the profile.
        if stamped.guildID != nil, let membership = try await fetch(GuildMember.id(userID: me)) {
            membership["name"] = stamped.name
            membership["level"] = stamped.level
            membership["power"] = stamped.power
            _ = try? await save(membership)
        }
        let stored = CloudKitSocialBackend.profile(from: record) ?? stamped
        rememberProfile(stored)
        return stored
    }

    func search(name: String) async throws -> [SocialProfile] {
        let key = SocialProfile.key(name)
        guard !key.isEmpty else { return [] }
        let me = try await userID()
        let rows = try await records(
            ofType: "SocialProfile",
            where: NSPredicate(format: "nameKey BEGINSWITH %@", key),
            limit: 25
        )
        return rows.compactMap(CloudKitSocialBackend.profile(from:))
            .filter { $0.id != me }
            .sorted { $0.arenaPoints > $1.arenaPoints }
    }

    // MARK: - Friends

    func friends() async throws -> [Friendship] {
        let me = try await userID()
        let rows = try await records(
            ofType: "Friendship",
            where: NSPredicate(format: "members CONTAINS %@", me),
            limit: 100
        )
        let others = rows.map { row -> (id: String, members: [String], since: Date, other: String) in
            let members = CloudKitSocialBackend.list(row, "members")
            return (
                id: row.recordID.recordName,
                members: members,
                since: CloudKitSocialBackend.date(row, "since"),
                other: members.first(where: { $0 != me }) ?? ""
            )
        }
        let profiles = try await fetchMany(others.map { CloudKitSocialBackend.profileName($0.other) })
            .compactMap(CloudKitSocialBackend.profile(from:))
        return others.compactMap { row in
            guard let friend = profiles.first(where: { $0.id == row.other }) else { return nil }
            return Friendship(id: row.id, members: row.members, since: row.since, friend: friend)
        }
        .sorted { $0.since > $1.since }
    }

    func friendRequests() async throws -> [FriendRequest] {
        let me = try await userID()
        let rows = try await records(
            ofType: "FriendRequest",
            where: NSPredicate(format: "toID == %@ AND status == %@", me, FriendRequestStatus.pending.rawValue),
            sortedBy: "sentAt",
            limit: 50
        )
        return rows.compactMap(CloudKitSocialBackend.request(from:))
    }

    func sendFriendRequest(to profileID: String) async throws -> FriendRequest {
        let me = try await userID()
        guard profileID != me else { throw SocialError.invalid("That is you.") }
        if try await fetch(Friendship.id(me, profileID)) != nil {
            throw SocialError.conflict("You are already friends.")
        }
        var myName = knownProfile()?.name
        if myName == nil { myName = try await myProfile()?.name }
        let request = FriendRequest(
            id: FriendRequest.id(from: me, to: profileID),
            fromID: me,
            fromName: myName ?? "Demigod",
            toID: profileID,
            status: .pending,
            sentAt: Date()
        )
        let record = CKRecord(recordType: "FriendRequest", recordID: CKRecord.ID(recordName: request.id))
        record["fromID"] = request.fromID
        record["fromName"] = request.fromName
        record["toID"] = request.toID
        record["status"] = request.status.rawValue
        record["sentAt"] = request.sentAt
        do {
            _ = try await save(record)
        } catch SocialError.conflict {
            throw SocialError.conflict("A request to that demigod is already waiting.")
        }
        return request
    }

    func respond(request: FriendRequest, accept: Bool) async throws {
        let me = try await userID()
        guard let record = try await fetch(request.id) else { throw SocialError.notFound("That request") }
        record["status"] = (accept ? FriendRequestStatus.accepted : FriendRequestStatus.declined).rawValue
        _ = try await save(record)
        guard accept else { return }
        let friendship = CKRecord(
            recordType: "Friendship",
            recordID: CKRecord.ID(recordName: Friendship.id(me, request.fromID))
        )
        friendship["members"] = [me, request.fromID]
        friendship["since"] = Date()
        do {
            _ = try await save(friendship)
        } catch SocialError.conflict {
            // Already friends: the other side accepted a mirrored request.
        }
    }

    // MARK: - Mail

    func mail() async throws -> [Mail] {
        let me = try await userID()
        let rows = try await records(
            ofType: "Mail",
            where: NSPredicate(format: "toID == %@", me),
            sortedBy: "sentAt",
            limit: 50
        )
        return rows.compactMap(CloudKitSocialBackend.mail(from:))
    }

    func send(mail: Mail) async throws {
        let me = try await userID()
        var outgoing = mail
        outgoing.fromID = me
        let record = CKRecord(recordType: "Mail", recordID: CKRecord.ID(recordName: outgoing.id))
        try CloudKitSocialBackend.fill(record, with: outgoing)
        _ = try await save(record)
    }

    func claim(mail: Mail) async throws -> [ShopService.Grant] {
        guard let record = try await fetch(mail.id) else { throw SocialError.notFound("That mail") }
        guard CloudKitSocialBackend.int(record, "claimed") == 0 else {
            throw SocialError.conflict("That mail was already claimed.")
        }
        let grants = CloudKitSocialBackend.grants(from: record)
        record["claimed"] = 1
        do {
            _ = try await save(record)
        } catch SocialError.conflict {
            throw SocialError.conflict("That mail was already claimed.")
        }
        return grants
    }

    // MARK: - Guild

    func guild() async throws -> Guild? {
        let me = try await userID()
        guard let membership = try await fetch(GuildMember.id(userID: me)) else { return nil }
        let guildID = CloudKitSocialBackend.string(membership, "guildID")
        guard let record = try await fetch(guildID) else { return nil }
        return CloudKitSocialBackend.guild(from: record)
    }

    func findGuilds(name: String) async throws -> [Guild] {
        let key = SocialProfile.key(name)
        let predicate = key.isEmpty
            ? NSPredicate(value: true)
            : NSPredicate(format: "nameKey BEGINSWITH %@", key)
        let rows = try await records(ofType: "Guild", where: predicate, sortedBy: "warPoints", limit: 30)
        return rows.map(CloudKitSocialBackend.guild(from:))
    }

    func createGuild(name: String, crest: String) async throws -> Guild {
        let me = try await userID()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 24 else {
            throw SocialError.invalid("A guild's name is two to twenty-four characters.")
        }
        guard try await fetch(GuildMember.id(userID: me)) == nil else {
            throw SocialError.conflict("Leave your guild before founding another.")
        }
        let key = SocialProfile.key(trimmed)
        let taken = try await records(ofType: "Guild", where: NSPredicate(format: "nameKey == %@", key), limit: 1)
        guard taken.isEmpty else { throw SocialError.conflict("A guild called \(trimmed) already exists.") }
        let now = Date()
        let guild = Guild(
            id: "guild_\(UUID().uuidString.lowercased())",
            name: trimmed,
            crest: Guild.crests.contains(crest) ? crest : Guild.crests[0],
            leaderID: me,
            memberCount: 1,
            warPoints: 0,
            season: WarRules.seasonKey(for: now),
            weekKey: WarRules.weekKey(for: now),
            weekPoints: 0,
            createdAt: now
        )
        let record = CKRecord(recordType: "Guild", recordID: CKRecord.ID(recordName: guild.id))
        CloudKitSocialBackend.fill(record, with: guild)
        _ = try await save(record)
        _ = try await save(try await membershipRecord(me, in: guild, role: .leader, now: now))
        try await refreshProfileGuild(me)
        return guild
    }

    func joinGuild(id: String) async throws -> Guild {
        let me = try await userID()
        guard try await fetch(GuildMember.id(userID: me)) == nil else {
            throw SocialError.conflict("Leave your guild before joining another.")
        }
        guard let record = try await fetch(id) else { throw SocialError.notFound("That guild") }
        let members = try await memberRecords(of: id)
        guard members.count < Guild.capacity else {
            throw SocialError.conflict("\(CloudKitSocialBackend.string(record, "name")) is full.")
        }
        let guild = CloudKitSocialBackend.guild(from: record)
        _ = try await save(try await membershipRecord(me, in: guild, role: .member, now: Date()))
        try await recount(guildID: id)
        try await refreshProfileGuild(me)
        return try await fetch(id).map(CloudKitSocialBackend.guild(from:)) ?? guild
    }

    func leaveGuild() async throws {
        let me = try await userID()
        guard let membership = try await fetch(GuildMember.id(userID: me)) else {
            throw SocialError.conflict("You are not in a guild.")
        }
        let guildID = CloudKitSocialBackend.string(membership, "guildID")
        do {
            _ = try await database.deleteRecord(withID: membership.recordID)
        } catch {
            throw CloudKitSocialBackend.map(error)
        }
        try await recount(guildID: guildID)
        try await refreshProfileGuild(me)
    }

    func guildMembers() async throws -> [GuildMember] {
        let me = try await userID()
        guard let membership = try await fetch(GuildMember.id(userID: me)) else { return [] }
        let guildID = CloudKitSocialBackend.string(membership, "guildID")
        let week = WarRules.weekKey()
        let attacks = try await records(
            ofType: "WarAttack",
            where: NSPredicate(format: "week == %@ AND guildID == %@", week, guildID),
            limit: 400
        )
        var scored: [String: Int] = [:]
        for attack in attacks {
            scored[CloudKitSocialBackend.string(attack, "attackerID"), default: 0] += CloudKitSocialBackend.int(attack, "points")
        }
        return try await memberRecords(of: guildID)
            .map { row in
                var member = CloudKitSocialBackend.member(from: row)
                member.weekPoints = scored[member.userID] ?? 0
                return member
            }
            .sorted { $0.weekPoints == $1.weekPoints ? $0.joinedAt < $1.joinedAt : $0.weekPoints > $1.weekPoints }
    }

    func postToBoard(text: String) async throws -> BoardPost {
        let me = try await userID()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SocialError.invalid("Write something first.") }
        guard trimmed.count <= 200 else { throw SocialError.invalid("A post is two hundred characters at most.") }
        guard let membership = try await fetch(GuildMember.id(userID: me)) else {
            throw SocialError.conflict("Join a guild to use its board.")
        }
        let post = BoardPost(
            id: "post_\(UUID().uuidString.lowercased())",
            guildID: CloudKitSocialBackend.string(membership, "guildID"),
            authorID: me,
            authorName: CloudKitSocialBackend.string(membership, "name"),
            text: trimmed,
            postedAt: Date()
        )
        let record = CKRecord(recordType: "BoardPost", recordID: CKRecord.ID(recordName: post.id))
        record["guildID"] = post.guildID
        record["authorID"] = post.authorID
        record["authorName"] = post.authorName
        record["text"] = post.text
        record["postedAt"] = post.postedAt
        _ = try await save(record)
        return post
    }

    func board() async throws -> [BoardPost] {
        let me = try await userID()
        guard let membership = try await fetch(GuildMember.id(userID: me)) else { return [] }
        let guildID = CloudKitSocialBackend.string(membership, "guildID")
        let rows = try await records(
            ofType: "BoardPost",
            where: NSPredicate(format: "guildID == %@", guildID),
            sortedBy: "postedAt",
            limit: 30
        )
        return rows.map { row in
            BoardPost(
                id: row.recordID.recordName,
                guildID: CloudKitSocialBackend.string(row, "guildID"),
                authorID: CloudKitSocialBackend.string(row, "authorID"),
                authorName: CloudKitSocialBackend.string(row, "authorName"),
                text: CloudKitSocialBackend.string(row, "text"),
                postedAt: CloudKitSocialBackend.date(row, "postedAt")
            )
        }
    }

    // MARK: - The war

    func war() async throws -> GuildWar? {
        let me = try await userID()
        guard let mine = try await guild() else { return nil }
        let now = Date()
        let week = WarRules.weekKey(for: now)
        guard let opponent = try await pairing(for: mine, week: week) else { return nil }

        let myAttacks = try await records(
            ofType: "WarAttack",
            where: NSPredicate(format: "week == %@ AND attackerID == %@", week, me),
            limit: 100
        )
        let today = WarRules.dayKey(for: now)
        let foughtToday = myAttacks.filter { CloudKitSocialBackend.string($0, "day") == today }.count
        let beaten = Set(
            myAttacks
                .filter { CloudKitSocialBackend.int($0, "won") == 1 }
                .map { CloudKitSocialBackend.string($0, "targetID") }
        )
        let myPower = knownProfile()?.power ?? 0

        let theirMembers = try await memberRecords(of: opponent.id)
        let profiles = try await fetchMany(theirMembers.map { CloudKitSocialBackend.profileName(CloudKitSocialBackend.string($0, "userID")) })
            .compactMap(CloudKitSocialBackend.profile(from:))
        let targets = profiles
            .map { profile in
                WarTarget(
                    id: profile.id,
                    profile: profile,
                    guildID: opponent.id,
                    beaten: beaten.contains(profile.id),
                    pointsForWin: WarRules.points(won: true, attackerPower: myPower, targetPower: profile.power)
                )
            }
            .sorted { $0.profile.power < $1.profile.power }

        let ourAttacks = try await records(
            ofType: "WarAttack",
            where: NSPredicate(format: "week == %@ AND guildID == %@", week, mine.id),
            limit: 800
        )
        let theirAttacks = try await records(
            ofType: "WarAttack",
            where: NSPredicate(format: "week == %@ AND guildID == %@", week, opponent.id),
            limit: 800
        )
        let bothAttacks = ourAttacks + theirAttacks
        return GuildWar(
            week: week,
            opponent: opponent,
            targets: targets,
            standings: [
                CloudKitSocialBackend.standing(of: mine, attacks: bothAttacks, mine: true),
                CloudKitSocialBackend.standing(of: opponent, attacks: bothAttacks, mine: false),
            ],
            attacksLeftToday: max(0, WarRules.attacksPerDay - foughtToday),
            endsAt: WarRules.weekEnd(for: now)
        )
    }

    func reportWarAttack(result: WarAttackResult) async throws -> WarStanding {
        let me = try await userID()
        guard let mine = try await guild() else { throw SocialError.conflict("Join a guild to fight its war.") }
        let now = Date()
        let week = WarRules.weekKey(for: now)
        let day = WarRules.dayKey(for: now)
        let thisWeek = try await records(
            ofType: "WarAttack",
            where: NSPredicate(format: "week == %@ AND attackerID == %@", week, me),
            limit: 100
        )
        let todayCount = thisWeek.filter { CloudKitSocialBackend.string($0, "day") == day }.count
        guard todayCount < WarRules.attacksPerDay else {
            throw SocialError.conflict("No war attacks left today. They return at midnight UTC.")
        }
        // A second win over a target already beaten this week scores nothing;
        // the attack is still spent and recorded.
        let alreadyBeaten = thisWeek.contains {
            CloudKitSocialBackend.string($0, "targetID") == result.targetID && CloudKitSocialBackend.int($0, "won") == 1
        }
        let points = alreadyBeaten ? 0 : WarRules.points(
            won: result.won,
            attackerPower: knownProfile()?.power ?? 0,
            targetPower: result.targetPower
        )
        let attack = CKRecord(
            recordType: "WarAttack",
            recordID: CKRecord.ID(recordName: "war_\(week)_\(day)_\(me)_\(todayCount)")
        )
        attack["week"] = week
        attack["day"] = day
        attack["attackerID"] = me
        attack["attackerName"] = knownProfile()?.name ?? "Demigod"
        attack["guildID"] = mine.id
        attack["targetID"] = result.targetID
        attack["targetGuildID"] = result.targetGuildID
        attack["won"] = result.won ? 1 : 0
        attack["points"] = points
        attack["foughtAt"] = result.foughtAt
        do {
            _ = try await save(attack)
        } catch SocialError.conflict {
            throw SocialError.conflict("No war attacks left today. They return at midnight UTC.")
        }
        try await addPoints(points, to: mine.id, week: week, season: WarRules.seasonKey(for: now))

        let all = try await records(
            ofType: "WarAttack",
            where: NSPredicate(format: "week == %@ AND guildID == %@", week, mine.id),
            limit: 800
        )
        let fresh = try await fetch(mine.id).map(CloudKitSocialBackend.guild(from:)) ?? mine
        return CloudKitSocialBackend.standing(of: fresh, attacks: all, mine: true)
    }

    // MARK: - Ranks

    func leaderboard(kind: LeaderboardKind) async throws -> [LeaderboardEntry] {
        let me = try await userID()
        switch kind {
        case .arena:
            let rows = try await records(ofType: "SocialProfile", where: NSPredicate(value: true), sortedBy: "arenaPoints", limit: 50)
            var entries = rows.compactMap(CloudKitSocialBackend.profile(from:)).enumerated().map { offset, profile in
                LeaderboardEntry(
                    id: profile.id,
                    rank: offset + 1,
                    name: profile.name,
                    detail: "Lv.\(profile.level) · \(profile.tier.displayName) · power \(profile.power.formatted())",
                    score: profile.arenaPoints,
                    crest: nil,
                    isMine: profile.id == me
                )
            }
            // Outside the top fifty, the player's own row still closes the
            // table, unranked, so he can see what the fiftieth holds.
            if !entries.contains(where: { $0.isMine }), let own = knownProfile() {
                entries.append(
                    LeaderboardEntry(
                        id: own.id,
                        rank: 0,
                        name: own.name,
                        detail: "Lv.\(own.level) · \(own.tier.displayName) · power \(own.power.formatted())",
                        score: own.arenaPoints,
                        crest: nil,
                        isMine: true
                    )
                )
            }
            return entries
        case .guild:
            let myGuild = knownProfile()?.guildID
            let rows = try await records(ofType: "Guild", where: NSPredicate(value: true), sortedBy: "warPoints", limit: 50)
            return rows.map(CloudKitSocialBackend.guild(from:)).enumerated().map { offset, guild in
                LeaderboardEntry(
                    id: guild.id,
                    rank: offset + 1,
                    name: guild.name,
                    detail: "\(guild.memberCount) member\(guild.memberCount == 1 ? "" : "s")",
                    score: guild.warPoints,
                    crest: guild.crest,
                    isMine: guild.id == myGuild
                )
            }
        }
    }

    // MARK: - Guild bookkeeping

    private func membershipRecord(_ me: String, in guild: Guild, role: GuildRole, now: Date) async throws -> CKRecord {
        var profile = knownProfile()
        if profile == nil { profile = try await myProfile() }
        let record = CKRecord(recordType: "GuildMember", recordID: CKRecord.ID(recordName: GuildMember.id(userID: me)))
        record["userID"] = me
        record["guildID"] = guild.id
        record["name"] = profile?.name ?? "Demigod"
        record["level"] = profile?.level ?? 1
        record["power"] = profile?.power ?? 0
        record["role"] = role.rawValue
        record["joinedAt"] = now
        return record
    }

    private func memberRecords(of guildID: String) async throws -> [CKRecord] {
        try await records(
            ofType: "GuildMember",
            where: NSPredicate(format: "guildID == %@", guildID),
            sortedBy: "joinedAt",
            ascending: true,
            limit: Guild.capacity * 2
        )
    }

    /// The member count and the leader, read off the rows rather than
    /// nudged up and down: two joins in the same second cannot double count
    /// what is recounted. An empty guild is deleted.
    private func recount(guildID: String) async throws {
        guard let record = try await fetch(guildID) else { return }
        let members = try await memberRecords(of: guildID)
        if members.isEmpty {
            do {
                _ = try await database.deleteRecord(withID: record.recordID)
            } catch {
                throw CloudKitSocialBackend.map(error)
            }
            return
        }
        record["memberCount"] = members.count
        let leaderID = CloudKitSocialBackend.string(record, "leaderID")
        if !members.contains(where: { CloudKitSocialBackend.string($0, "userID") == leaderID }),
           let heir = members.first {
            record["leaderID"] = CloudKitSocialBackend.string(heir, "userID")
            heir["role"] = GuildRole.leader.rawValue
            _ = try? await save(heir)
        }
        _ = try await save(record)
    }

    private func refreshProfileGuild(_ me: String) async throws {
        guard let record = try await fetch(CloudKitSocialBackend.profileName(me)) else { return }
        if let membership = try await fetch(GuildMember.id(userID: me)),
           let guild = try await fetch(CloudKitSocialBackend.string(membership, "guildID")) {
            record["guildID"] = guild.recordID.recordName
            record["guildName"] = CloudKitSocialBackend.string(guild, "name")
        } else {
            record["guildID"] = nil as String?
            record["guildName"] = nil as String?
        }
        let saved = try await save(record)
        if let profile = CloudKitSocialBackend.profile(from: saved) { rememberProfile(profile) }
    }

    /// The week's points onto the guild record, with the tag the record was
    /// read with, retried when another member wrote first.
    private func addPoints(_ points: Int, to guildID: String, week: String, season: String) async throws {
        var attempt = 0
        while attempt < 4 {
            attempt += 1
            guard let record = try await fetch(guildID) else { return }
            var guild = CloudKitSocialBackend.guild(from: record)
            if guild.season != season {
                guild.season = season
                guild.warPoints = 0
            }
            if guild.weekKey != week {
                guild.weekKey = week
                guild.weekPoints = 0
            }
            guild.weekPoints += points
            guild.warPoints += points
            CloudKitSocialBackend.fill(record, with: guild)
            do {
                _ = try await save(record)
                return
            } catch SocialError.conflict {
                continue
            }
        }
        throw SocialError.conflict("The guild's points could not be written; try again.")
    }

    /// The week's rival, read off the pairing record when one exists and
    /// written when this is the first look of the week (`WarRules.opponent`).
    private func pairing(for guild: Guild, week: String) async throws -> Guild? {
        let pairingID = "pairing_\(week)_\(guild.id)"
        if let stored = try await fetch(pairingID),
           let opponent = try await fetch(CloudKitSocialBackend.string(stored, "opponentID")) {
            return CloudKitSocialBackend.guild(from: opponent)
        }
        let everyone = try await records(ofType: "Guild", where: NSPredicate(value: true), sortedBy: "warPoints", limit: 200)
            .map(CloudKitSocialBackend.guild(from:))
        guard let opponent = WarRules.opponent(for: guild, among: everyone, week: week) else { return nil }
        let record = CKRecord(recordType: "WarPairing", recordID: CKRecord.ID(recordName: pairingID))
        record["week"] = week
        record["guildID"] = guild.id
        record["opponentID"] = opponent.id
        record["pairedAt"] = Date()
        do {
            _ = try await save(record)
        } catch SocialError.conflict {
            // Somebody in the guild looked first: theirs stands.
            if let stored = try await fetch(pairingID),
               let theirs = try await fetch(CloudKitSocialBackend.string(stored, "opponentID")) {
                return CloudKitSocialBackend.guild(from: theirs)
            }
        }
        return opponent
    }

    private static func standing(of guild: Guild, attacks: [CKRecord], mine: Bool) -> WarStanding {
        let own = attacks.filter { string($0, "guildID") == guild.id }
        return WarStanding(
            id: guild.id,
            guildName: guild.name,
            crest: guild.crest,
            points: own.reduce(0) { $0 + int($1, "points") },
            wins: own.filter { int($0, "won") == 1 }.count,
            attacks: own.count,
            isMine: mine
        )
    }

    // MARK: - Records in and out

    private func fetch(_ recordName: String) async throws -> CKRecord? {
        guard !recordName.isEmpty else { return nil }
        do {
            return try await database.record(for: CKRecord.ID(recordName: recordName))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw CloudKitSocialBackend.map(error)
        }
    }

    private func fetchMany(_ recordNames: [String]) async throws -> [CKRecord] {
        let ids = recordNames.filter { !$0.isEmpty }.map { CKRecord.ID(recordName: $0) }
        guard !ids.isEmpty else { return [] }
        do {
            let results = try await database.records(for: ids)
            return ids.compactMap { id -> CKRecord? in
                guard let outcome = results[id], case .success(let record) = outcome else { return nil }
                return record
            }
        } catch {
            throw CloudKitSocialBackend.map(error)
        }
    }

    private func records(
        ofType recordType: String,
        where predicate: NSPredicate,
        sortedBy key: String? = nil,
        ascending: Bool = false,
        limit: Int = 50
    ) async throws -> [CKRecord] {
        let ckQuery = CKQuery(recordType: recordType, predicate: predicate)
        if let key {
            ckQuery.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        }
        do {
            let (matches, _) = try await database.records(matching: ckQuery, resultsLimit: limit)
            return matches.compactMap { pair -> CKRecord? in
                guard case .success(let record) = pair.1 else { return nil }
                return record
            }
        } catch {
            throw CloudKitSocialBackend.map(error)
        }
    }

    /// Saves with the change tag the record carries: a new record whose id
    /// exists, or a fetched one changed since, comes back as `.conflict`.
    private func save(_ record: CKRecord) async throws -> CKRecord {
        do {
            return try await database.save(record)
        } catch {
            throw CloudKitSocialBackend.map(error)
        }
    }

    /// Fetch-or-new, fill, save; once more from a fresh fetch when another
    /// device of the same account wrote in between.
    private func upsert(_ recordName: String, type: String, fill: (CKRecord) throws -> Void) async throws -> CKRecord {
        var attempt = 0
        while true {
            attempt += 1
            let record = try await fetch(recordName)
                ?? CKRecord(recordType: type, recordID: CKRecord.ID(recordName: recordName))
            try fill(record)
            do {
                return try await save(record)
            } catch SocialError.conflict where attempt < 3 {
                continue
            }
        }
    }

    static func map(_ error: Error) -> SocialError {
        if let social = error as? SocialError { return social }
        guard let cloud = error as? CKError else { return .unknown(error.localizedDescription) }
        switch cloud.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable:
            return .network
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .offline(SocialAvailability.noAccount)
        case .unknownItem:
            return .notFound("The record")
        case .serverRecordChanged, .serverRejectedRequest:
            return .conflict("Somebody changed that first. Refresh and try again.")
        case .permissionFailure:
            return .permission
        case .requestRateLimited, .zoneBusy:
            return .rateLimited
        case .quotaExceeded:
            return .quota
        case .invalidArguments, .limitExceeded:
            return .invalid(cloud.localizedDescription)
        case .missingEntitlement, .badContainer:
            return .notEntitled
        default:
            return .unknown(cloud.localizedDescription)
        }
    }

    // MARK: - Field helpers

    private static func profileName(_ userID: String) -> String { "profile_\(userID)" }

    private static func string(_ record: CKRecord, _ key: String) -> String {
        record[key] as? String ?? ""
    }

    private static func int(_ record: CKRecord, _ key: String) -> Int {
        (record[key] as? NSNumber)?.intValue ?? 0
    }

    private static func date(_ record: CKRecord, _ key: String) -> Date {
        record[key] as? Date ?? Date(timeIntervalSince1970: 0)
    }

    private static func data(_ record: CKRecord, _ key: String) -> Data? {
        record[key] as? Data
    }

    private static func list(_ record: CKRecord, _ key: String) -> [String] {
        record[key] as? [String] ?? []
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func fill(_ record: CKRecord, with profile: SocialProfile) throws {
        record["userID"] = profile.id
        record["name"] = profile.name
        record["nameKey"] = profile.nameKey
        record["level"] = profile.level
        record["power"] = profile.power
        record["arenaPoints"] = profile.arenaPoints
        record["guildID"] = profile.guildID
        record["guildName"] = profile.guildName
        record["team"] = try encoder.encode(profile.defence)
        record["updatedAt"] = profile.updatedAt
    }

    private static func profile(from record: CKRecord) -> SocialProfile? {
        let id = string(record, "userID")
        guard !id.isEmpty else { return nil }
        let team = data(record, "team").flatMap { try? decoder.decode([TeamSnapshotUnit].self, from: $0) } ?? []
        let guildID = string(record, "guildID")
        let guildName = string(record, "guildName")
        return SocialProfile(
            id: id,
            name: string(record, "name"),
            level: int(record, "level"),
            power: int(record, "power"),
            arenaPoints: int(record, "arenaPoints"),
            guildID: guildID.isEmpty ? nil : guildID,
            guildName: guildName.isEmpty ? nil : guildName,
            defence: team,
            updatedAt: date(record, "updatedAt")
        )
    }

    private static func request(from record: CKRecord) -> FriendRequest? {
        guard let status = FriendRequestStatus(rawValue: string(record, "status")) else { return nil }
        return FriendRequest(
            id: record.recordID.recordName,
            fromID: string(record, "fromID"),
            fromName: string(record, "fromName"),
            toID: string(record, "toID"),
            status: status,
            sentAt: date(record, "sentAt")
        )
    }

    private static func fill(_ record: CKRecord, with mail: Mail) throws {
        record["toID"] = mail.toID
        record["fromID"] = mail.fromID
        record["fromName"] = mail.fromName
        record["subject"] = mail.subject
        record["body"] = mail.body
        record["grants"] = try encoder.encode(mail.grants)
        record["claimed"] = mail.claimed ? 1 : 0
        record["sentAt"] = mail.sentAt
    }

    private static func grants(from record: CKRecord) -> [ShopService.Grant] {
        data(record, "grants").flatMap { try? decoder.decode([ShopService.Grant].self, from: $0) } ?? []
    }

    private static func mail(from record: CKRecord) -> Mail? {
        let toID = string(record, "toID")
        guard !toID.isEmpty else { return nil }
        return Mail(
            id: record.recordID.recordName,
            toID: toID,
            fromID: string(record, "fromID"),
            fromName: string(record, "fromName"),
            subject: string(record, "subject"),
            body: string(record, "body"),
            grants: grants(from: record),
            claimed: int(record, "claimed") != 0,
            sentAt: date(record, "sentAt")
        )
    }

    private static func fill(_ record: CKRecord, with guild: Guild) {
        record["name"] = guild.name
        record["nameKey"] = guild.nameKey
        record["crest"] = guild.crest
        record["leaderID"] = guild.leaderID
        record["memberCount"] = guild.memberCount
        record["warPoints"] = guild.warPoints
        record["season"] = guild.season
        record["weekKey"] = guild.weekKey
        record["weekPoints"] = guild.weekPoints
        record["createdAt"] = guild.createdAt
    }

    private static func guild(from record: CKRecord) -> Guild {
        Guild(
            id: record.recordID.recordName,
            name: string(record, "name"),
            crest: string(record, "crest"),
            leaderID: string(record, "leaderID"),
            memberCount: int(record, "memberCount"),
            warPoints: int(record, "warPoints"),
            season: string(record, "season"),
            weekKey: string(record, "weekKey"),
            weekPoints: int(record, "weekPoints"),
            createdAt: date(record, "createdAt")
        )
    }

    private static func member(from record: CKRecord) -> GuildMember {
        GuildMember(
            id: record.recordID.recordName,
            userID: string(record, "userID"),
            guildID: string(record, "guildID"),
            name: string(record, "name"),
            level: int(record, "level"),
            power: int(record, "power"),
            role: GuildRole(rawValue: string(record, "role")) ?? .member,
            joinedAt: date(record, "joinedAt")
        )
    }
}
