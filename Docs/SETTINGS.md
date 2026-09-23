# Settings — notifications, graphics and comfort, account deletion, the App Store paperwork (2026-09-23)

Four things the Settings screen (More) needed before the game can be
submitted: reminders a player asked for, a way to trade looks for battery and
to calm the camera, a way to delete the account from inside the app, and the
files App Store Connect reads. This file has what was researched, the options
weighed and what was built. The owner's steps for the account-deletion
server side are `Docs/BACKEND.md` §7.

## What was read

Apple's pages were read from `developer.apple.com` (its documentation JSON;
the rendered pages need JavaScript) on 2026-09-23:

- *Offering account deletion in your app* (developer.apple.com/support):
  "Make the account deletion option easy to find in your app. Typically,
  it's included in the app's account settings." — "Offer to delete the
  entire account record, along with associated personal data", including
  content shared with others (posts). Extra confirmation and identity steps
  are allowed; "apps that make it unnecessarily difficult for a user to
  delete their account will not pass review". "Users should have the option
  to delete automatically generated accounts (sometimes called 'guest'
  accounts)". "Apps that support Sign in with Apple should use the Sign in
  with Apple REST API to revoke user tokens." A deletion that takes time is
  acceptable if the player is told how long.
- App Review Guidelines 5.1.1(v) ("If your app supports account creation,
  you must also offer account deletion within the app"), 5.1.1(i) (a link
  to the privacy policy inside the app "in an easily accessible manner", and
  in App Store Connect), 4.5.4 (notifications never required to use the
  app; promotions only with explicit opt-in and an in-app opt-out).
- TN3194 *Handling account deletions and revoking tokens for Sign in with
  Apple* (2025-10-03): `/auth/revoke` needs a refresh or access token; if
  the app has neither it must still delete the account and send the player
  to Settings → Sign in with Apple to stop using it; observe
  `credentialRevokedNotification`.
- The Sign in with Apple REST API pages *Generate and validate tokens* and
  *Revoke tokens*, and *Creating a client secret*: the authorization code is
  single use and valid five minutes; `redirect_uri` is sent only if the
  authorization request had one (a native app's has none); the client
  secret is an ES256 JWT with `kid`, `iss` = Team ID, `iat`, `exp`, `aud` =
  `https://appleid.apple.com`, `sub` = the client id; both endpoints take
  `application/x-www-form-urlencoded`; revoke answers 200 with no body.
- *Asking permission to use notifications*: ask "in a context that helps
  people understand why"; provisional authorization delivers quietly to the
  Notification Center only. The HIG *Managing notifications*: pick an
  honest interruption level (passive, active, time sensitive), never
  marketing without explicit consent, and an in-app screen to change the
  choice.
- *Optimizing iPhone and iPad apps to support ProMotion displays*: an
  iPhone never draws faster than 60 Hz unless the app's Info.plist carries
  `CADisableMinimumFrameDurationOnPhone` = true; an iPad Pro needs nothing.
  `SCNView.preferredFramesPerSecond` defaults to 60.
- The privacy manifest pages (*Describing use of required reason API*, the
  `NSPrivacyAccessedAPIType` and `NSPrivacyCollectedDataType` values) and
  *Complying with encryption export regulations*.
- Supabase's own docs, from its GitHub repository (`supabase.com` is closed
  to this environment): a `security definer` function must set
  `search_path`, and execution must be revoked from `public` and `anon` and
  granted to the role that may call it; Edge Functions verify the caller's
  JWT by default (`verify_jwt`), read secrets with `Deno.env.get`, and can
  be written and deployed from the Dashboard's editor.

The genre's own screens could not be opened: the Summoners War forums,
PCGamingWiki and the guide sites are refused by the network policy. What is
said of them below is from memory and marked so.

## 1. Notifications

**The genre (from memory).** Summoners War's settings carry push switches
by kind (energy recharged, arena wings, guild), and — because Korean law
asks a separate consent for night-time advertising pushes — a *night push*
switch; Raid and Epic Seven have an energy-full push. All of them are
server pushes.

**Options weighed.**

1. *Server push* (APNs from a Supabase function on a schedule). Needs the
   `aps-environment` entitlement (the entitlements file deliberately has
   none, and CI signs nothing), a device-token table and a job runner — to
   send times the phone can already compute. Rejected for now.
2. *Local notifications scheduled when the app goes to the background* —
   **built.** Every time in question is known on the phone: energy refills
   one point every five minutes from `Wallet.lastEnergyTick`
   (`GameStore.refreshTimedResources`), the missions and the daily offering
   turn over at local midnight (`QuestService.refreshDay`,
   `ShopService.isDailyAvailable`), and the event calendar is a pure
   function of the date (`EventCalendar`). Nothing to run, nothing to pay.
3. *Background refresh* (`BGTaskScheduler`) to recompute while closed:
   nothing changes while the app is closed that was not known when it
   closed. Rejected.

**When to ask.** Never at launch and never under `-tour`. Two moments:

- a switch turned on in Settings → Notifications (the system prompt follows
  the tap; if the player had said no before, the page says so and offers
  **Open iPhone Settings**, since iOS never asks twice);
- the first time energy runs out (below 4, the price of an ordinary
  campaign stage): a small card, once ever, *before* the system prompt —
  "Your energy is spent … Remind me / Not now". A "no" to iOS's prompt is
  permanent, so the prompt is only shown to a player who has already said
  yes to the card. Provisional authorization (quiet delivery with no prompt
  at all) was weighed and not used: every switch is off until the player
  turns it on, so an explicit yes is what the game has anyway, and a quiet
  energy reminder would arrive unseen.

**What is sent — at most one in the morning and one when energy fills.**

| Switch | When | Level |
|---|---|---|
| Energy full | the minute energy reaches the maximum, if that is at least ten minutes after the app closed | active |
| Daily reset | the morning after local midnight: new missions, the daily offering, the Festival's gift | passive |
| Event days | the morning an event STARTS: a weekday event, Friday's weekend headline, a Festival Monday | passive |

- The morning line is ONE notification per day, whichever of the two
  morning switches are on; the next three mornings are scheduled, so a
  player who stops opening the game hears three times and then nothing.
- **Nights are quiet:** nothing arrives between 22:00 and 08:00. An energy
  reminder that would is held to 08:00 (it is still true then), and when it
  lands on a morning line it is folded into it.
- Everything pending or delivered is removed the moment the game returns to
  the foreground, and rescheduled from the new state when it leaves.
- The switches live in `UserDefaults` (`notifications.*`), not in the save:
  they belong to the phone.

**Built.** `Pantheon/Core/Notifications/NotificationService.swift`:
`NotificationPlanner` (pure, tested: `PantheonTests/NotificationTests.swift`,
including a test that pins its energy clock to `GameStore`'s own) and
`NotificationService` (the switches, the authorization, the scheduling);
`Pantheon/UI/Settings/SettingsPages.swift` (the page and the energy card).
Hooked in `PantheonApp.swift`: the scene going to the background schedules,
the return clears, and the store's energy is watched for the card.

## 2. Graphics and comfort

**The genre (from memory, and one search snippet).** Raid offers a frame
rate limit (30 / 60) and a graphics quality; Honkai: Star Rail — the
closest turn-based gacha on a phone — offers 30 / 60 / 120 FPS where the
screen can, a special-effects quality, shadows and bloom as separate
switches; Genshin has a motion-blur switch. The common shape: frame rate,
effects, shadows, and a way to stop the camera moving.

**Options weighed.**

- *Frame rate.* 30 / 60 / 120. **Built** with the stages' own rates kept:
  60 is today exactly (the fight and the summon reveal at 60, the island at
  its deliberate 30); 30 caps all three; 120 raises the fight and the reveal
  and leaves the island at 30 (it is ambient). 120 is offered only where the
  app can draw it: a ProMotion iPad today, and a ProMotion iPhone once the
  app's Info.plist carries `CADisableMinimumFrameDurationOnPhone` — which
  cannot be a build setting (it is not one of Xcode's `INFOPLIST_KEY_`
  keys), so it needs a partial Info.plist excluded from the synchronized
  folder's resources. Left for the owner to decide; the option appears by
  itself when the key is there.
- *Effects quality.* Full / Reduced. **Built:** Reduced turns the bloom off
  (the fight's 0.22, the reveal's 0.34) and halves every particle burst or
  loop of a dozen particles or more — sparks, rising motes, weather, flames,
  the awakened aura — while a painted flipbook sheet or a sprite of a few
  (the effect itself) is never touched. Rejected: dropping the multisampling
  (cheap on Apple GPUs, and the look relies on it) and rendering below the
  screen's resolution (a real saving, but it blurs the paintings; a later
  "battery saver" preset if the owner wants one).
- *Shadows.* On / Off — the fight's key light and the reveal's figure
  shadow, both deferred.
- *Where it is applied.* One helper, `GraphicsSettings.configure(_:for:)`
  (`Pantheon/Render/GraphicsSettings.swift`), called where the three stage
  views are configured (`BattleSceneView`, `IslandSceneView`, the summon
  reveal's `SummonStageView`). It sets the frame rate and wraps the view's
  render delegate in a `StageRenderGovernor` that forwards every callback
  and applies the choice on the render thread: bloom off on the camera
  being drawn, particle systems thinned as they appear, shadows off — each
  remembered and put back the moment the player returns to Full, so a
  change reaches even the island, which is never rebuilt. At the defaults
  it only forwards, so every stage looks exactly as it did.

**Reduce Motion.** iOS's switch (`UIAccessibility.isReduceMotionEnabled`)
or the game's own (`MotionComfort`). With it on: no camera shake
(`CameraDirector.shake`), no white flash on an ultimate's cut-in
(`BattleView.ultimateFlash`), the skill zoom goes 40% of the way at a
slower ease, and the cinematic camera's cuts and orbits are held off (the
gentle zoom plays instead; the switch keeps its setting).

## 3. Deleting the account

**The genre (from memory).** HoYoverse and Com2uS delete after a grace
period (a week to a month, cancelled by signing in), behind a list of what
goes and a typed or ticked confirmation.

**Options weighed.**

- *Immediate or a grace period.* A grace period needs something on the
  server that deletes on day N and a "restore" door; Apple accepts either
  if the player is told. **Immediate**, behind a list of exactly what is
  deleted, the word DELETE typed, and — for an Apple account — Apple's own
  confirmation sheet.
- *Revoking Sign in with Apple.* TN3194's server flow validates the
  authorization code at sign-in and stores Apple's refresh token; this game
  never sent the code at sign-in and the backend holds no Apple token. So a
  **fresh authorization at deletion** (`AppleReauthorizer`) gives a code
  valid five minutes, which the Edge Function `apple-revoke` exchanges at
  `/auth/token` and revokes at `/auth/revoke` with a client secret signed by
  the team's Sign in with Apple key — a secret that can only live on a
  server. Not deployed (or refused): everything else is still deleted, one
  `[Account]` line is logged, and the sign-in screen tells the player how to
  stop using the Apple ID by hand, as TN3194 prescribes.
- *Deleting the backend user.* An Edge Function with the service role
  (`auth.admin.deleteUser`) or a `security definer` SQL function limited to
  `auth.uid()`: **the SQL function** (`delete_my_account()`, its own
  migration): no secret, deployed with the SQL, and it can only ever delete
  the caller. The `players` and `saves` rows go with the user (cascades,
  and explicit deletes first).
- *When to stop.* A copy left on the backend restores on the next sign-in,
  so the order is the cloud copy, Apple's revocation, the user, then
  CloudKit and the phone, and a failure among the first three stops the
  deletion with nothing on the phone touched (the account reopens; the
  sheet says to try again with a connection). An Apple ID first signs in
  again with the fresh sheet's identity token; with no session after that
  it stops as well — unless the backend refused the sign-in outright (a
  4xx other than 408 and 429), since then no sign-in can reach that copy
  either. A guest whose session the backend refused is deleted all the
  same, for the same reason: nobody can sign in as that anonymous user
  again, and its orphaned row waits for the sweep of abandoned anonymous
  users that `Docs/BACKEND.md` §4 describes.
- *What is deleted* — on the confirmation, in these words: this phone's
  save and every copy kept aside, the cloud copy (Pantheon Cloud and any
  iCloud copy), the backend sign-in, the public Allies records on an
  iCloud-signed build (profile, guild membership, friend requests and
  friendships, mail sent to the player, board posts, war attacks), the
  offline practice world, the reminders, and the account's line in this
  phone's sign-in ledger. Settings (sound, graphics) stay: they belong to
  the phone. A guest's deletion is the same without Apple.

**Built.** `Pantheon/Core/Account/AccountDeletion.swift` (the ordered
steps, testable with the backend's canned transport:
`PantheonTests/AccountDeletionTests.swift`),
`Pantheon/Core/Account/AppleReauthorizer.swift`,
`Pantheon/Core/Account/CloudAccountEraser.swift` (gated exactly as the
social layer is), `AccountService.forget`, `AppSession.deleteAccount`,
`Pantheon/UI/Account/DeleteAccountSheet.swift`, the Account board's
**Delete account** row, `Backend/supabase/migrations/20260923000000_delete_my_account.sql`
and `Backend/supabase/functions/apple-revoke/index.ts`.

## 4. The App Store paperwork

- **`Pantheon/PrivacyInfo.xcprivacy`.** The app folder is a synchronized
  group, which puts the file in Copy Bundle Resources at the bundle's root
  with no project edit. `NSPrivacyTracking` false, no tracking domains.
  Collected, every one linked to the player, none for tracking, all for App
  Functionality: **User ID** (the Supabase user, the Apple `sub` inside the
  identity token, the Player ID), **Name** (the name Apple sends, on the
  backend's player row and the Allies profile), **Email Address** (inside
  Apple's identity token, which Supabase keeps on the user), **Gameplay
  Content** (the save, the Allies defence snapshot, war results), **Other
  User Content** (guild board posts), **Product Interaction** (the player
  row's last launch). The App Store Connect questionnaire must say the same.
  Required-reason APIs: **UserDefaults** `CA92.1` (the app's own settings);
  **File timestamp** `C617.1` (the only timestamp read is a `CKRecord`'s
  `modificationDate` in the app's own CloudKit container — declared because
  the selector is the file attribute's name); **System boot time** `35F9.1`
  (`CACurrentMediaTime` times the effects; it is the boot clock, and
  declaring it costs nothing). No disk-space or keyboard API is used.
- **`ITSAppUsesNonExemptEncryption` = NO** as the build setting
  `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` (a supported key) on the
  app target, in the project and in `project.yml`: the app's only
  encryption is Apple's (HTTPS through URLSession, CloudKit, Sign in with
  Apple) and SHA-256 hashing, which is exempt.
- **Privacy policy and Terms** rows on the Support board open the URLs in
  `Pantheon/Resources/LegalLinks.plist` (`PrivacyPolicyURL`,
  `TermsOfUseURL`); an empty value hides its row. **Guideline 5.1.1(i)
  requires the privacy policy link in the app: fill it before submitting.**
  The policy must say what is collected (the list above), that the account
  and its data can be deleted in the app (More → Account → Delete account)
  and what, if anything, backups keep.

## What was checked here, and what cannot be

Checked: `tools/swiftcheck.py --members --types` is clean; every file
touched parses under a Swift grammar (tree-sitter); the Edge Function
type-checks under `tsc --strict` against a Deno stand-in and was run in
Node against a mocked Apple with a freshly generated P-256 key — the
client secret it signs verifies as ES256 with the right `kid`, `iss`,
`sub`, `aud` and a five-minute life, the code exchange sends no
`redirect_uri`, and the revoke sends the refresh token with its hint. The
unit tests (`NotificationTests`, `AccountDeletionTests`, `SettingsTests`)
run on CI: the planner against the store's own energy clock, the deletion
against canned backends, the render governor against a real SceneKit
scene, and the bundle for the privacy manifest and the export key.

No Swift compiler, no signed build and no Apple or Supabase servers are
reachable from this environment. Not verified: the system permission
prompt and the delivery times on a device; Apple's re-authorization sheet;
the Edge Function against Apple itself (it needs the team's key); CloudKit
deletes (CI builds unsigned, so `isEntitled` is false there); the frame
rate on a ProMotion screen. The CI tour can photograph the Settings pages
and the deletion sheet, never press them.
