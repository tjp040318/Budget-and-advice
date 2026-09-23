import Foundation
import CloudKit

/// The CloudKit half of deleting an account (`Docs/SETTINGS.md` §3): the
/// Apple ID's save record in the PRIVATE database (`CloudSaveStore`,
/// `save_<key>`) and everything the player wrote to the PUBLIC database
/// through the Allies screen (`Docs/SOCIAL.md`'s schema).
///
/// Gated exactly as the social layer is: the initialiser fails unless the
/// running binary carries the iCloud entitlement
/// (`CloudKitSocialBackend.isEntitled`) — touching `CKContainer` without it
/// is an uncatchable exception, and CI builds unsigned — and each half asks
/// `accountStatus` first, since a phone with no iCloud account has nothing
/// there to delete.
///
/// The public records are found the way the social layer finds them — by the
/// iCloud user record's name, which is the player's Allies identity — and
/// deleted one by one; a record another player created (a friendship he
/// accepted) is refused by the security roles and logged, and so is a query
/// the Dashboard has no index for (`Docs/BACKEND.md` §7 lists the two to
/// add: `BoardPost.authorID`, `Mail.fromID`). The guild is left through the
/// social layer's own `leaveGuild`, which recounts it, hands it to an heir or
/// deletes it when the player was the last one in.
@MainActor
final class CloudAccountEraser: CloudAccountErasing {
    private let container: CKContainer

    init?() {
        guard CloudKitSocialBackend.isEntitled else { return nil }
        container = CKContainer(identifier: CloudKitSocialBackend.containerID)
    }

    // MARK: - The private save

    func eraseSave(key: String) async -> DeletionOutcome {
        guard let store = CloudSaveStore(key: key) else { return .skipped("this build is not signed for iCloud") }
        guard await store.accountAvailable() else { return .skipped("no iCloud account on this phone") }
        return await store.erase() ? .done : .failed(store.lastError ?? "iCloud could not be reached")
    }

    // MARK: - The public Allies records

    func eraseSocialRecords() async -> DeletionOutcome {
        let available = (try? await container.accountStatus()) == .available
        guard available else { return .skipped("no iCloud account on this phone") }
        let database = container.publicCloudDatabase
        let me: String
        do {
            me = try await container.userRecordID().recordName
        } catch {
            return .failed(error.localizedDescription)
        }
        var problems: [String] = []

        // The guild, through the social layer's own leave (the membership
        // deleted, the guild recounted, handed on or deleted).
        let membership = try? await database.record(for: CKRecord.ID(recordName: GuildMember.id(userID: me)))
        if membership != nil {
            do {
                try await CloudKitSocialBackend().leaveGuild()
            } catch {
                problems.append("guild: \(error.localizedDescription)")
            }
        }

        // Everything else that names the player, type by type.
        let searches: [(type: String, predicate: NSPredicate)] = [
            ("FriendRequest", NSPredicate(format: "fromID == %@", me)),
            ("FriendRequest", NSPredicate(format: "toID == %@", me)),
            ("Friendship", NSPredicate(format: "members CONTAINS %@", me)),
            ("Mail", NSPredicate(format: "toID == %@", me)),
            ("Mail", NSPredicate(format: "fromID == %@", me)),
            ("BoardPost", NSPredicate(format: "authorID == %@", me)),
            ("WarAttack", NSPredicate(format: "attackerID == %@", me)),
        ]
        for search in searches {
            do {
                let query = CKQuery(recordType: search.type, predicate: search.predicate)
                let (matches, _) = try await database.records(matching: query, resultsLimit: 200)
                for (recordID, _) in matches {
                    if let problem = await delete(recordID, from: database) {
                        problems.append("\(search.type): \(problem)")
                    }
                }
            } catch {
                problems.append("\(search.type) search: \(error.localizedDescription)")
            }
        }

        // The profile last: the leave above rewrites it.
        if let problem = await delete(CKRecord.ID(recordName: "profile_\(me)"), from: database) {
            problems.append("SocialProfile: \(problem)")
        }
        return problems.isEmpty ? .done : .failed(problems.joined(separator: "; "))
    }

    /// One record deleted; a record that is already gone counts as deleted.
    private func delete(_ recordID: CKRecord.ID, from database: CKDatabase) async -> String? {
        do {
            _ = try await database.deleteRecord(withID: recordID)
            return nil
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
