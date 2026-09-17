# The social layer on CloudKit (2026-09-17)

Friends, an inbox, guilds with an ASYNC guild war, and an arena and a guild
leaderboard. No chat and no live PvP — chosen by the owner today, and the
two things left out are the two the market study said would eat a solo
developer (`Docs/MARKET_2026.md`: chat brings moderation and a legal burden,
live PvP brings shared mutable state under concurrent writes). Everything
here is a RECORD somebody writes and somebody else reads later, which is what
a hosted database does well without a line of server code.

The build is four Core files, one screen, one entitlements file and a test
file. The lead folds this page into `Docs/PLAN.md` and wires the entry points
(a button on the island's header and on More, a `GameStore` pay-out for mail,
a battle context for a war attack, and tour step 45).

---

## What the genre does

Everything below is from memory of the games themselves; the data sites are
refused by this environment, so treat the numbers as [recall].

**Summoners War.** Friends up to a cap (fifty at the start, more with
achievements), a friend list with a **"send" button per row** that gifts a
small social currency once a day, a **rep monster** each friend lends you for
one stage, a **mailbox** with a reward attached to every system message
("receive" per row, "receive all"), **guilds** of up to thirty with a notice
board, a guild shop and the **guild battle**: a fixed number of attacks per
member per battle day against the opposing guild's defence teams, the
guild's score the sum of its members', a rank that moves at the end of the
week, and a siege mode on top of it later. **Rankings**: the arena rank
table with the player's own row pinned, and a guild ranking table.

**Epic Seven.** Friends with a daily friendship point, guilds with donations
and a **guild war** of two attacks per member per war, each attack a fight
against a member's defence, the war decided by the total; mail with
attachments that are claimed once and expire.

**Raid: Shadow Legends.** Clans with a clan boss everybody hits over a day
(shared damage — the co-op kind the market study warns off), clan quests,
and an inbox.

The common shape, which is what this build reproduces:

- **Mail is the delivery channel** for everything the game or another player
  gives you: a row per message, a reward strip on the row, one Claim.
- **Friends are a rail with a face**: the friend's leader, their level and
  power, one button to send them something.
- **The guild is roster + board + a war tab** with a list of enemy members
  to attack and a bar that compares the two guilds' points.
- **Rankings are a table with your own row highlighted.**

## What the tools can do

**CloudKit's public database** is a hosted record store every iOS app gets
with an iCloud container: record types with typed fields, queries with
indexes, a per-record change tag for optimistic writes, and the iCloud
account as the identity (the user's record ID is stable per container and
per account, and never reveals the Apple ID). It costs nothing at this
scale [recall: the free allowance scales with the app's user count and a
social record here is a few hundred bytes]. There is **no server logic**: no
function runs between one client's write and another's read, so a client
is trusted exactly as the arena already trusts it (a determined user can
write himself any number; nothing here changes that, and the seam for a
real backend is the `SocialBackend` protocol).

Three things about CloudKit shape the schema and are easy to get wrong:

1. **A query needs an index.** In the Development environment the schema is
   created just in time by the first save of each record type, but the
   indexes are not — a `CKQuery` on a type whose `recordName` is not marked
   queryable fails with "Field 'recordName' is not marked queryable". The
   owner adds the indexes in the CloudKit Dashboard; the list is below.
   Fetching by record ID needs no index, so every lookup that can be a
   fetch by a DETERMINISTIC id is one (a player's profile is
   `profile_<userID>`, a membership is `member_<userID>`, a friend request
   is `req_<from>_<to>`), which also makes those things unique for free.
2. **Predicates are limited.** Equality, `IN`, `BEGINSWITH` on a string,
   `CONTAINS` on a list field, and `AND`; no `OR`. So a friendship stores
   both ids in one list field `members` and is found with
   `members CONTAINS <me>`; a name search is `nameKey BEGINSWITH <lowercase>`.
3. **A record is writable by its creator only** unless a security role says
   otherwise. A mail is created by its sender and marked claimed by its
   recipient, a friend request is created by the sender and answered by the
   recipient, a guild's points are written by every member: those three
   record types need the Authenticated role given write access in the
   Dashboard (a numbered step below). Everything else stays creator-only.

**The entitlement is a hard gate.** A process that touches `CKContainer`
without `com.apple.developer.icloud-services` in its code signature is
killed with an uncaught `CKException`, not handed an error. The CI job
builds the app with `CODE_SIGNING_ALLOWED=NO`, so the tour's app has no
signature and no entitlement at all, and the unit tests run in the same
binary. So before anything asks CloudKit anything,
`CloudKitSocialBackend.isEntitled` reads the running executable's embedded
entitlements blob (the `0xFADE7171` blob in the code signature, the same
XML plist Xcode wrote from `Pantheon.entitlements`) and answers false when
there is none. That is what keeps CI green: no entitlement → the offline
backend → the seeded roster, with the notice line.

## The options weighed

1. **CloudKit's public database** — chosen. No server to run, no account
   system to build (iCloud is the account), no cost, and every feature the
   owner chose is a record somebody writes and somebody reads. Its limits
   are exactly the features left out: no chat (needs moderation, needs push),
   no live PvP (needs a referee), no cheat protection.
2. **Game Center** — friends and leaderboards for free with Apple's own
   sheets, but no mail, no guilds and no defence snapshots, so it cannot
   carry the war. Worth adding LATER as a second publisher of the arena
   board (`GKLeaderboard`) for the Game Center overlay; not this pass.
3. **A real backend** (a hosted Postgres with functions, or a game server) —
   what chat, live PvP and a server-verified battle need. Out of scope and
   out of budget for now; `SocialBackend` is the seam, and the battle itself
   is already deterministic on a seed (`SeededRandom`) so a server could
   re-run a reported war attack when one exists.

## What was built

```
Pantheon/Core/Social/SocialBackend.swift          the value types, the protocol, WarRules
Pantheon/Core/Social/CloudKitSocialBackend.swift  the real backend
Pantheon/Core/Social/LocalSocialBackend.swift     the offline fake (seeded, in UserDefaults)
Pantheon/Core/Social/SocialService.swift          @MainActor ObservableObject over a backend
Pantheon/UI/Social/SocialView.swift               one GameScreen, four tabs
Pantheon/Pantheon.entitlements                    iCloud container + CloudKit, no aps-environment
PantheonTests/SocialTests.swift                   the local backend and the war rules
```

`SocialService` builds the player's profile FROM a `Player` it is handed
(`SocialService.profile(from:id:guild:)`): name, level, the arena points,
the total power, and the arena DEFENCE team as the snapshot. It never touches
`GameStore`. Claiming a mail returns the grants, and the screen hands them to
an `onClaim` closure so the lead can pay them through `GameStore`.

### The defence snapshot

`TeamSnapshotUnit` is what one unit of a defence team looks like on the wire:
the family key (`blueprintID`, e.g. `anubis_ember`), the name, level, stars,
element, awakened, the portrait name, the RESOLVED stats (after relics, sets,
awakening — the eight numbers `Stats` holds), the skill levels, the completed
relic sets with their multiplicity (`[RelicSet.rawValue: completions]`), the
boon in the socket, and the power. It is exactly what `Combatant.init` reads
off a `ResolvedUnit`, so `TeamSnapshotUnit.resolved()` rebuilds one from the
blueprint on THIS build: a `Unit` at that level and grade, six stat-less
carrier relics of the recorded sets so `activeRelicSets` still lights Vigil
or Wrath, the recorded stats written over the resolve. A war attack is then
`BattleEngine(playerTeam: offence, opponentTeam: snapshot, mode:
.arenaOffense, seed:)` — the same call `ArenaService.startAttack` makes, so
resonance, leader skills and boons all apply exactly as in the arena. A
family this build does not know (a newer app on the other side) is skipped.

## The schema

Record types are named as the value types. `userID` everywhere is the
CloudKit user record's `recordName`. Every string that is searched has a
lowercase twin (`nameKey`) because `BEGINSWITH` is case-sensitive.

| Record type | recordName | Fields | Written by |
|---|---|---|---|
| `SocialProfile` | `profile_<userID>` | `userID` String, `name` String, `nameKey` String, `level` Int, `power` Int, `arenaPoints` Int, `guildID` String?, `guildName` String?, `team` Bytes (JSON `[TeamSnapshotUnit]`), `updatedAt` Date | the player, on every refresh |
| `FriendRequest` | `req_<from>_<to>` | `fromID`, `fromName`, `toID` String, `status` String (`pending`/`accepted`/`declined`), `sentAt` Date | sender creates, recipient answers |
| `Friendship` | `friend_<a>_<b>` (ids sorted) | `members` String list (both ids), `since` Date | the accepting side |
| `Mail` | `mail_<uuid>` | `toID`, `fromID`, `fromName`, `subject`, `body` String, `grants` Bytes (JSON `[ShopService.Grant]`), `claimed` Int (0/1), `sentAt` Date | sender creates, recipient claims |
| `Guild` | `guild_<uuid>` | `name`, `nameKey`, `crest`, `leaderID` String, `memberCount` Int, `warPoints` Int (the season's), `season` String (`2026-09`), `weekKey` String (`2026-W38`), `weekPoints` Int, `createdAt` Date | founder creates, members update |
| `GuildMember` | `member_<userID>` | `userID`, `guildID`, `name` String, `level`, `power` Int, `role` String (`leader`/`member`), `joinedAt` Date | the member |
| `BoardPost` | `post_<uuid>` | `guildID`, `authorID`, `authorName`, `text` String, `postedAt` Date | the author |
| `WarAttack` | `war_<week>_<day>_<attackerID>_<slot>` | `week`, `day` String, `attackerID`, `attackerName`, `guildID`, `targetID`, `targetGuildID` String, `won` Int, `points` Int, `foughtAt` Date | the attacker |
| `WarPairing` | `pairing_<week>_<guildID>` | `week`, `guildID`, `opponentID` String, `pairedAt` Date | whoever looks first |

The `WarAttack` id is the daily limit: three slots a day (`0`, `1`, `2`);
a fourth attack has no id to save under, and a second save of the same slot
fails with `serverRecordChanged`. A `GuildMember` id per user is the
one-guild-per-player rule. A `FriendRequest` id per pair is the
one-request-per-pair rule.

### The indexes the owner creates (CloudKit Dashboard → Schema → Indexes)

| Record type | Index |
|---|---|
| `SocialProfile` | `recordName` QUERYABLE · `nameKey` QUERYABLE · `arenaPoints` SORTABLE · `guildID` QUERYABLE |
| `FriendRequest` | `recordName` QUERYABLE · `toID` QUERYABLE · `fromID` QUERYABLE · `status` QUERYABLE |
| `Friendship` | `recordName` QUERYABLE · `members` QUERYABLE |
| `Mail` | `recordName` QUERYABLE · `toID` QUERYABLE · `sentAt` SORTABLE |
| `Guild` | `recordName` QUERYABLE · `nameKey` QUERYABLE · `warPoints` SORTABLE |
| `GuildMember` | `recordName` QUERYABLE · `guildID` QUERYABLE · `userID` QUERYABLE |
| `BoardPost` | `recordName` QUERYABLE · `guildID` QUERYABLE · `postedAt` SORTABLE |
| `WarAttack` | `recordName` QUERYABLE · `week` QUERYABLE · `attackerID` QUERYABLE · `guildID` QUERYABLE · `targetGuildID` QUERYABLE |
| `WarPairing` | none (fetched by id only) |

### The security roles the owner sets (Dashboard → Schema → Security Roles)

`FriendRequest`, `Mail`, `Guild`: **Authenticated** (`_icloud`) gets
Create, Read and Write. Every other type keeps the default (world reads,
the creator writes, authenticated users create).

## The war's rules

1. **The week** is the ISO week in UTC (`WarRules.weekKey`: `2026-W38`);
   the **season** is the month (`2026-09`). Both are computed on the
   client from the clock; nothing runs at midnight.
2. **The pairing.** For a guild G in week W: every other guild is a
   candidate, sorted by how far its points are from G's
   (`WarRules.pairingPoints`: the season's `warPoints` less this week's
   `weekPoints`, so points scored during the war do not re-pair it), ties
   by id; the three nearest are kept; the hash of `W + G.id` (FNV-1a)
   picks one of the three. Deterministic for the week, never G itself, and
   the two nearest guilds do not fight each other forever. The first client
   of a guild to look at the war in a week writes the pairing as a
   `WarPairing` record, and every later look reads that, so a guild created
   mid-week cannot move it. One guild alone has no war: the card says a
   second guild is needed, which is truer than a fake rival.
3. **The attacks.** Each member gets `WarRules.attacksPerDay` = 3 a day
   (UTC), on any member of the opposing guild whose defence he has not
   beaten this week, fought locally by `BattleEngine` exactly as an arena
   attack (`SocialService.warBattle(against:player:seed:)`), the attacker's
   arena OFFENCE team against the target's defence snapshot.
4. **The points.** A win reports `WarRules.winPoints` = 10, plus
   `WarRules.upsetBonus` = 5 when the target's power is above the
   attacker's; a loss reports 0 and still spends the attack and is recorded,
   so the standings show attempts. A second win over a target the same
   attacker already beat this week scores nothing (both backends check the
   week's attacks, not the button), and the row says BEATEN.
5. **The standings** are the week's sums per guild (`weekPoints`, also
   written on the `Guild` record so a leaderboard can read them without
   summing rows), with each guild's wins and attacks from the `WarAttack`
   rows. The season's `warPoints` accumulate every week's points and reset
   when the first report of a new month lands; the guild leaderboard sorts
   by them.
6. **The reward** is the lead's wiring (`Docs/PLAN.md` will say what a war
   week pays); the backend records the grade of the fact, not the prize.

`balance.py` mirrors nothing here — no tuning constant of the fight changed,
and the war's numbers are `WarRules`, asserted by `SocialTests`.

## What is offline

`LocalSocialBackend` stands in whenever CloudKit cannot be used: no
entitlement in the signature (CI, and any unsigned build), no iCloud account
(`accountStatus` other than `.available`), or a container error at the first
call. It is seeded from one number so the screens are never empty: twelve
rival summoners with real defence teams rolled from the summon pool (the
same generator shape as the arena's challengers, so their power is honest),
four guilds with members and a board, one welcome mail with a small reward,
one incoming friend request. A rival answers a friend request at once —
those whose name hashes even accept, the rest decline — so the round trip
can be tested. What the player does offline (friends made, mail claimed, the
guild joined, the attacks fought) persists in `UserDefaults` under
`social.local.v1`; the seeded world is regenerated from the seed on every
launch, so a roster change never leaves a dangling family.

The screens wear one line under the strip while offline:

> Offline: sign in to iCloud in Settings to see other summoners.

(or, when the build carries no entitlement, "Offline: this build is not
signed for iCloud; showing the practice roster.")

## The owner's Xcode steps

1. Open `Pantheon.xcodeproj`, select the **Pantheon** target, open
   **Signing & Capabilities**, and make sure your **Team** is set.
2. Press **+ Capability** and add **iCloud**.
3. In the iCloud section tick **CloudKit**. Under **Containers** press **+**
   and enter exactly `iCloud.com.pantheon.game` (the bundle id
   `com.pantheon.game` with the `iCloud.` prefix; it must equal
   `CloudKitSocialBackend.containerID`). Xcode registers the container with
   the App ID and writes it into `Pantheon/Pantheon.entitlements`, which is
   already checked in with that value and is already named in the target's
   `CODE_SIGN_ENTITLEMENTS`; if Xcode asks to create a new entitlements
   file, cancel and point it at the existing one.
4. If **Push Notifications** appeared as a capability, remove it: the
   entitlements file must NOT carry `aps-environment` (the CI build is
   unsigned and the app sends no push).
5. Run on a device signed in to iCloud (or on a simulator whose Settings
   app is signed in to iCloud). Open **Summoners** (the island's header, or
   More) and do one of each: it publishes your profile on opening; search a
   name; send a request; create a guild; post to the board; send a friend
   a greeting; fight a war target. Each first save creates the record type
   in the Development schema.
6. Open the CloudKit Dashboard (icloud.developer.apple.com/dashboard),
   choose the container, **Schema → Record Types**, and confirm the nine
   types above exist.
7. **Schema → Indexes**: for each record type add the indexes in the table
   above (`recordName` QUERYABLE on every queried type first — without it
   every query fails).
8. **Schema → Security Roles**: for `FriendRequest`, `Mail` and `Guild`
   give **Authenticated** Create, Read and Write. Save.
9. **Deploy Schema Changes…** to **Production** before any TestFlight build;
   a TestFlight or App Store binary reads the Production schema.
10. Nothing changes in CI: the job builds with `CODE_SIGNING_ALLOWED=NO`,
    the app carries no entitlement, `CloudKitSocialBackend.isEntitled` is
    false, and the tour photographs the seeded roster.

## What the lead wires

- **GameStore** (the lead's file): `receive(_ grants: [ShopService.Grant])`
  → `update { player in ShopService.grant(...) }` for each grant, returning
  the flattened list for the receipt; `startWarAttack(_ target: WarTarget)
  -> BattleEngine?` → `social.warBattle(against: target, player: player,
  seed: nextSeed())`; `finishWarAttack(_ target:, result:)` → `await
  social.reportWarAttack(against: target, result: result)`, which returns
  the points the attack earned.
  The store owns one `SocialService` (`let social = SocialService()`) so its
  published state survives the screen closing.
- **BattleViewModel/BattleContext** (the lead's file): a
  `.guildWar(WarTarget)` case beside `.arena`, the environment
  `.arenaOfSouls`, the title "vs <name>", and the settle path calling
  `finishWarAttack` and listing the points on the reckoning.
- **SettingsView's account reset** (the lead's file): `LocalSocialBackend.wipe()`
  beside `SaveStore.deleteSave()`, so the offline world's claimed mail and
  joined guild go with the account.
- **RootView / IslandView / More**: a Summoners button (icon
  `person.2.fill`) beside the missions scroll in the island's header and a
  tile on More, presenting `SocialView(social: store.social, onAttack:
  { target in ... }, onClaim: { grants in store.receive(grants) })` as a
  sheet; a badge with `social.pendingCount`.
- **TourView**: step 45, `("summoners", 2)`, showing
  `SocialView(social: SocialService(backend: LocalSocialBackend(seed: 7,
  persisting: false)), opening: .guild, onAttack: { _ in }, onClaim: { _ in })`,
  relaunched with `-tour-social-tab friends|inbox|ranks` for the other tabs
  the way `chapter_maps` relaunches per chapter.

## What is NOT built, said plainly

No chat, no push, no rep monsters, no kicking or promoting members (a
leader who leaves hands the guild to the earliest member; the last member
out deletes it), no war reward (the lead's wiring), no read-only mode for a
device without an iCloud account (the public database can be READ without
an account, so the live leaderboards could show there; a later refinement),
no server verification of anything a client reports.
