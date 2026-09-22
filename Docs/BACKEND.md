# The backend — Supabase (2026-09-22, phase 1)

The owner: "lets get the database for it going. I have supabase or turso so
maybe we can add a new database thats needed." Phase 1 is built: every
player — a guest as much as an Apple ID — has a cloud copy of his save in a
Supabase project, and "Reset account" starts a clean game on the phone AND
in the cloud. `Docs/PLAN.md` *The backend — Supabase, and starting over* has
the options weighed and why Supabase over Turso; this file is the owner's
manual and the shape of the data.

Until the plist below is filled the game plays offline exactly as before,
with iCloud for an Apple account's cloud copy. Nothing here runs under the
CI tour (`-tour`), whatever the plist says.

## 1. Set the project up (the owner, once; about ten minutes)

The dashboard's labels are from memory — `supabase.com` is closed to the
build environment — so a label may sit one menu over from where it is named.

1. Open https://supabase.com/dashboard and press **New project**. Name it
   `pantheon`, pick the region nearest the players (US East for now), set a
   database password and keep it in the password manager. Wait for the
   project to finish provisioning (a minute or two).
2. Left rail → **Authentication** → **Sign In / Providers** (older
   dashboards: **Providers**). Under the user sign-ups settings turn
   **Allow anonymous sign-ins** ON and press Save. A guest's save is kept
   under an anonymous user; without this every guest launch fails with
   "Anonymous sign-ins are disabled" (worded in the console and the game
   plays on offline).
3. Same page → **Apple** → Enable. In **Client IDs** (also called
   *Authorized Client IDs*) enter `com.pantheon.game` — the app's bundle id,
   which is what a native Sign in with Apple token names as its audience.
   Leave the OAuth secret empty: the phone signs in with Apple's own button
   and hands the identity token to Supabase; no web redirect is used. Save.
4. Left rail → **SQL Editor** → **New query**. Paste the whole of
   `Backend/supabase/migrations/20260922000000_players_saves.sql` and press
   **Run**. It ends with "Success. No rows returned". Re-running it is safe
   (every statement is `if not exists` / `drop … if exists`).
5. Left rail → **Project Settings** → **API** (in newer dashboards
   **Project Settings** → **Data API** for the URL and **API Keys** for the
   key). Copy **Project URL** (`https://<ref>.supabase.co`) and the **anon
   public** key. NEVER the `service_role` key: that one bypasses every
   row-level rule and belongs on a server only. The Data API page also
   prints the REST endpoint, `https://<ref>.supabase.co/rest/v1` — either
   form works since 2026-09-22 (the app strips a service path, because the
   first paste was the REST one and every call would have gone to
   `…/rest/v1/auth/v1/…`), but the plain project URL is the one to keep.
6. In the repository open `Pantheon/Resources/Backend.plist` and paste the
   two values between the `<string></string>` tags of `SupabaseURL` and
   `SupabaseAnonKey`. Commit it: the anon key is public by design (it
   ships in every app that uses Supabase); row-level security is what
   keeps a player to his own rows. **Done 2026-09-22:** the plist holds
   project `kqlblqnioumkdoudhibi`'s URL and anon key (checked: the key's
   role is `anon`, its project matches the URL), and a unit test now
   refuses a service path on the URL or a secret key in the plist.
7. Build and run on the phone. The console prints `[Backend] …` lines: no
   line is the plist still empty; `sign-in failed: …` names what the
   dashboard still needs.
8. Left rail → **Table Editor** → `players`: one row per phone that has
   launched, with its `player_code` (the six characters the Account panel
   prints as Player ID). `saves`: one row per player, `bytes` the size of
   the save, `revision` counting the uploads.

### Checking the dashboard side without a phone (2026-09-22)

`*.supabase.co` is closed to the Claude Code environment (a 403 at
CONNECT), so from here only the plist can be checked, and the three
things the dashboard must hold cannot. Each is one look:

1. **The tables.** Left rail → **Table Editor**. `players` and `saves`
   must both be listed. If they are not, step 4 was not run (or ran in
   another project): paste the migration into **SQL Editor** and press
   **Run** again. To see the guard too: **Database** → **Triggers** →
   `saves_guard` on `saves`.
2. **Anonymous sign-ins.** **Authentication** → **Sign In / Providers** →
   scroll to **Allow anonymous sign-ins**: ON. Off, every guest launch
   logs `sign-in failed: Anonymous sign-ins are disabled` and plays
   offline.
3. **Apple.** Same page → **Apple** → Enabled, with `com.pantheon.game`
   (the app's bundle id, from Xcode's Signing & Capabilities) in
   **Client IDs**. Without it an Apple ID's token is refused as
   "audience mismatch" and that account plays offline; guests are
   unaffected.

Or open the environment to the project so it can be checked from here:
claude.ai/code → the cloud icon → the environment's gear → **Network
access: Custom** → add `kqlblqnioumkdoudhibi.supabase.co` → tick "Also
include default list of common package managers" (new sessions only).

## 2. Reset the account (today, on the phone)

1. Island → **More** (the fifth tab) → **Settings**.
2. Press the **Reset account** tile.
3. Press **Delete everything** in the dialog.

What happens: the store is retired; this phone's save is moved aside as
`reset_<stamp>_pantheon_save_<key>.json` (kept, never deleted; the file is
in Application Support/Pantheon and the export on the Account panel can
still reach it by hand); the seeded offline social world is wiped; the
cloud copy is erased (the Supabase row, or the iCloud record when no
backend is configured); and a NEW game opens for the SAME account with no
restore — one 4★ fire Anubis, the starter relics, the first summon. The
account itself (the Apple ID or the guest id) is kept, so the Player ID
does not change.

If the cloud could not be reached at the moment of the reset, its old copy
stays. It is of the old lineage, so the new game's uploads never overwrite
it and it never overwrites the new game: it comes back as "Pantheon Cloud
holds a different save, from <date>" on the Account panel with a **Restore
from Pantheon Cloud** button — the player's choice, either way.

## 3. What is stored

Two tables, both behind row-level security (`auth.uid()` must equal the
row's id): a signed-in user reads and writes his own rows and nobody
else's; the anon key alone can do nothing.

`players` — one row per Supabase user:

| column | what |
|---|---|
| `id` | the auth user's uuid (anonymous for a guest, Apple's for an Apple ID) |
| `provider` | `guest` or `apple` |
| `display_name` | the name Apple sent at the first authorisation, or null |
| `player_code` | the six characters the Account panel prints as Player ID |
| `created_at`, `last_seen_at` | the row's birth and the last launch |

`saves` — one row per player:

| column | what |
|---|---|
| `player_id` | the player's uuid |
| `payload` | the save file's exact bytes as text (byte-for-byte round trip) |
| `version` | `SaveGame.currentVersion` |
| `lineage` | the player's `createdAt`: two saves of one lineage are one game on two phones |
| `saved_at` | the save's own `savedAt` — the clock every comparison uses |
| `bytes`, `revision`, `updated_at` | size, upload count, the server's stamp |

The `saves_guard` trigger enforces the rules `CloudSaveStore` had on the
phone, on the server: an update whose `lineage` differs from the row's
raises `lineage` (the app remembers the row as a foreign save and offers
it); an update older than the row raises `stale` (another phone saved
since; the upload is skipped). So no client, modified or not, can bury a
newer save or another game's.

Who talks to it: `Pantheon/Core/Backend/` — `BackendConfig` (the plist),
`SupabaseClient` (auth, REST, functions over URLSession; the session in
`backend_session_<key>.json` beside the saves, file-protected),
`SupabaseSaveStore` (the cloud copy; `CloudSaveSyncing` is the protocol it
shares with the CloudKit store, so `GameStore` and the Account panel speak
one language). Uploads are coalesced to one a minute and one on the way to
the background, the same as iCloud's.

## 4. Accounts on the backend

- A **guest** signs in as an anonymous Supabase user on the first launch;
  the session is kept on the phone, so the same user is used every launch.
- An **Apple ID** signs in with Apple's identity token
  (`grant_type=id_token`), so one Apple ID is one Supabase user on every
  phone: the restore on a new phone comes from there.
- A guest who **binds** to his Apple ID keeps his progress: the phone
  renames the save file (as before) and the next upload goes under the
  Apple user. The anonymous user's old row is left behind, harmless; a
  later phase can link the two users or sweep abandoned anonymous rows
  (Supabase's dashboard can delete anonymous users older than N days).
- **Sign out** keeps the save on the phone and in the cloud; signing back
  in restores whichever is newer.

## 5. What phase 1 does NOT do, said plainly

The save is still trusted as the phone wrote it: a modified phone can
upload any save it likes into its own row. That is the same trust the
offline game and iCloud had. What changes the trust is phase 2 —
server-side summons (an Edge Function rolls the banner and writes the
result), receipt validation for real-money purchases (StoreKit 2's signed
transactions checked by a function before anything is granted), and the
energy clock on the server — which needs the game's economy to be settled
first. Phase 3 moves the social layer (friends, mail, guilds, the boards)
from CloudKit's public database onto these tables, so an Android or a
web client could one day read them too. Each phase is its own migration
file in `Backend/supabase/migrations/`.

## 6. Security notes

- The anon key is public. The `service_role` key is not: never in the
  app, never in the repository, never in a screenshot.
- Anonymous sign-ins are rate-limited by Supabase per IP (thirty an hour
  by default); the game makes one per phone, ever.
- Every table has RLS enabled and policies for `authenticated` only; the
  `anon` role's grants are revoked in the migration.
- Row size: a veteran's save is a few hundred kilobytes of JSON; the
  `payload` column is `text`, which Postgres stores compressed out of
  line, so a thousand players are well under the free tier's database
  allowance.
