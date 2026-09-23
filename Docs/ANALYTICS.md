# Anonymous play data (2026-09-23)

The owner, on measuring play after launch: **"Yes, anonymous only"** — no
names, no emails; declared to Apple; enough to tune the game by: where
players quit, which stages are too hard, what they spend on.

Built: the phone sends a closed list of events under a random number of its
own to one insert-only table in the Supabase project that already keeps the
saves (`Docs/BACKEND.md`), and six SQL views in the dashboard answer the
questions. A switch on More → Support turns it off. This file is the
owner's manual (§1), the research and the choice (§2–§4), and the reference
(§5–§9).

Files: `Pantheon/Core/Backend/Analytics.swift` (the vocabulary, pure),
`Pantheon/Core/Backend/AnalyticsService.swift` (the queue, the sessions,
the uploads), `Backend/supabase/migrations/20260923010000_analytics_events.sql`
(the table, its guard, the views, the nightly prune),
`PantheonTests/AnalyticsTests.swift`. The hooks: `QuestService.record`
(one line), `CampaignService.settle` (one record of every run),
`AppSession.install` / the two sign-in buttons / `PantheonApp.init`
(one line each), the switch on the Support board, and
`Pantheon/PrivacyInfo.xcprivacy`.

## 1. What the owner does (once; about fifteen minutes)

The dashboard's labels are from memory — `supabase.com` is closed to the
build environment — so a label may sit one menu over.

**A. The database**

1. Dashboard → **SQL Editor** → **New query**. Paste the whole of
   `Backend/supabase/migrations/20260923010000_analytics_events.sql` and
   press **Run**. It ends with "Success. No rows returned". Running it again
   is safe.
2. Check: **Table Editor** → schema **public** → `events` is listed (empty
   until a phone plays). Open the schema menu at the top left of the Table
   Editor → **analytics** → six views: `daily`, `retention`, `first_hour`,
   `stages`, `quit_points`, `economy`. The **Security Advisor** may list
   "Function search path mutable" for `analytics.num` and `analytics.txt`
   (deliberate: a SET clause would stop Postgres inlining them into the
   views) and may call the insert policy on `events` permissive (deliberate:
   anyone may add a row, nobody may read one). Nothing else is expected.
3. Check the nightly prune: left rail → **Integrations** → **Cron** (older
   dashboards: **Database** → **Cron Jobs**) → a job named
   `pantheon-analytics-prune`, schedule `17 4 * * *`.
   - If it is listed: nothing to do.
   - If it is not (the Run in step 1 printed "pg_cron is not available
     here"): **Integrations** → **Cron** → **Enable** (if asked) → **Create
     job** → Name `pantheon-analytics-prune`, Schedule `17 4 * * *`, type
     **SQL snippet**, command `select analytics.prune();` → **Create cron
     job**.
4. Decide the window. The prune keeps **120 days**. On the **free plan**
   (500 MB for saves and play data together) keep **60**: SQL Editor →
   `select cron.schedule('pantheon-analytics-prune', '17 4 * * *', $$select analytics.prune(interval '60 days')$$);`
   → Run (the same name replaces the job). On **Pro** (8 GB) leave 120. §8
   has the arithmetic.

**B. App Store Connect → your app → App Privacy** (with the answers in
`Docs/SETTINGS.md` §4, which this changes in three places)

5. **Edit** the data types → tick **Identifiers → Device ID** and
   **Purchases → Purchase History** (leave the others ticked) → **Save**.
6. **Device ID** → purposes: **Analytics** only → "linked to the user's
   identity?" **No** → "used for tracking?" **No**.
7. **Product Interaction** → purposes: tick **Analytics** beside **App
   Functionality** → linked: **Yes** → tracking: **No**. (Yes because the
   backend's player row keeps the last launch, which is linked, and Apple
   asks once per data type — §3.)
8. **Purchase History** → purposes: **App Functionality** and **Analytics**
   → linked: **Yes** (the save's purchase ledger travels with the cloud
   copy) → tracking: **No**.
9. Check the result against `Pantheon/PrivacyInfo.xcprivacy`, which says
   the same; Xcode's **Product → Archive → Generate Privacy Report** prints
   it as a label.

**C. The privacy policy** (the page `Pantheon/Resources/LegalLinks.plist`
points to) — add a paragraph that says, in the owner's words:

10. what is sent (the list in §5: sessions, stages won or lost with turns
    and team power, summons, upgrades, purchases by product, the tutorial's
    steps, the app version), under a random number made on the phone for
    this install and never sent with the account; that it is kept 120 days
    (or the window chosen in step 4) in the game's Supabase project, which
    processes it for the game; that Supabase's own request logs see the
    phone's IP address for a day (free plan) or a week (Pro) and the game
    never stores or joins it; and that **More → Support → Share anonymous
    play data** turns it off, which also forgets the install's number.

**D. Reading it** — SQL Editor → a query → **Run** (a result can be
exported as CSV, and recent dashboards can chart it):

11. `select * from analytics.daily limit 30;` — each day's active installs,
    new installs, sessions, minutes, fights, summons.
12. `select * from analytics.retention limit 30;` — D1/D3/D7/D14/D30 by
    install day.
13. `select * from analytics.first_hour;` — the first hour, step by step.
14. `select * from analytics.stages where fail_pct > 40 order by attempts desc;`
    — the stages that fail most.
15. `select * from analytics.quit_points limit 20;` — where the players
    who stopped were.
16. `select * from analytics.economy limit 30;` — the day's spending.

**E. Checking it on a phone** (after steps 1–3)

17. Run the game from Xcode on the phone (a debug build: its rows say
    `channel = debug`, which the views skip), play a minute, then press the
    Home button — the way to the background sends the batch.
18. Dashboard → **Table Editor** → **public** → `events`: rows with an
    `install_id`, `session_start`, `session_end`, perhaps `stage_result`.
    Or: `select name, props, occurred_at from public.events order by id desc limit 20;`
19. **More → Support → Share anonymous play data** off → play → background:
    no new rows. On again: rows under a NEW `install_id`.
20. Nothing arrives? **More → Diagnostics** shows an `[Analytics]` line
    ("upload failed: … 404" means step 1 was not run in this project).

## 2. What a game this size should measure

Com2uS does not publish Summoners War's telemetry, so the genre's practice
is read off the tools built for it. GameAnalytics — a free analytics
service built for games and used by a great many mobile ones — organises a
game's events into four kinds
([Event types](https://docs.gameanalytics.com/event-tracking-and-integrations/sdks-and-collection-api/api/event-types/)):
**progression** (a start and then a fail or a complete per level, which is
what makes a difficulty curve readable —
[Progression events](https://docs.gameanalytics.com/event-types/progression-events/)),
**resource** (every source and sink of each currency —
[Resource events](https://docs.gameanalytics.com/event-types/resource-events/)),
**business** (real money —
[Business events](https://docs.gameanalytics.com/events-metrics-and-filtering/event-types/business-events/)),
and **design** (anything else). Its starter guide ranks what to track first
by the same KPIs every free-to-play game is judged on
([What events should you track first](https://www.gameanalytics.com/blog/what-events-should-you-track-first-game-analytics)):
retention, the first-time experience, progression, the economy, revenue.

What that means here, and what answers it:

| Question | KPI | Answered by |
|---|---|---|
| Do players come back? | D1, D7, D30 retention by install day; daily active installs | `retention`, `daily` |
| Where does the first hour lose them? | the funnel: first open → account → Athena's six lessons and the four things she asks for (fight, summon, equip, power up) → farewell, or Skip | `first_hour` |
| Which stages are too hard? | per stage and tier: attempts, fail rate (a loss or a forfeit), turns to win, the team's power as a share of the recommended power when it won and when it failed | `stages` |
| Where do players stop? | the last stage each silent install fought, and how it ended | `quit_points` (with `first_hour` for those who never fought) |
| What do they spend on? | summons and 5★ pulls; divinity and drachma out and in; energy; swept runs; power-ups and relic upgrades; evolutions, awakenings, fusions; purchases by product | `economy` |
| How long do they play? | sessions per day, median session length, minutes per install | `daily` |

The yardstick: GameAnalytics' 2025 benchmarks across 16,000+ mobile games
put the median **D1 near 22%** (top quarter 26.5–27.7%) and the median
**D7 near 3.4–3.9%** (top quarter 7–8%); that cycle has no genre cut, and
RPGs trade a slower start for a longer tail
([2025 Mobile Gaming Benchmarks](https://www.gameanalytics.com/reports/2025-mobile-gaming-benchmarks),
[summary](https://gamedevreports.substack.com/p/gameanalytics-mobile-gaming-benchmarks)).
A stage whose losses sit at or above 100% of its recommended power is the
one number a hand-tuned curve cannot see and this data can.

What is deliberately NOT measured: taps and screens (a heat-map is not a
tuning question and would be most of the volume), crash logs (Xcode's
Organizer already has them, from Apple, for opted-in phones), the device
model, the locale, anything about other apps.

## 3. Anonymous, and small

**The rules the design keeps:**

1. **A random number per install**, made on the phone (`UUID`), kept in
   the app's own UserDefaults. Never the account, never Apple's user id,
   never the Player ID, never the IDFV or the IDFA (GameAnalytics' SDK uses
   the IDFV unless told otherwise —
   [iOS configuration](https://docs.gameanalytics.com/integrations/sdk/ios/configuration)).
   It lives **13 months** and is then made again, never extended by use;
   turning the switch off **forgets** it, and on again makes a new one.
2. **Never sent with the account**: the upload carries the anon key alone,
   never a player's session, so no request holds an event and an account
   together, and the table has no column for either.
3. **No free text**: event names are one Swift enum (`AnalyticsEventName`);
   a property is a number or a token of `[a-z0-9_]` at most 40 long (a
   stage's id, a step's name); product ids lose the app's prefix; and the
   server's trigger strips any key or value that is anything else, so a
   modified phone cannot store a sentence either.
4. **No IP address stored.** Supabase's request logs see it, as every
   server does, for a day on the free plan and a week on Pro
   ([Supabase logging](https://supabase.com/docs/guides/telemetry/logs),
   [retention by plan](https://github.com/orgs/supabase/discussions/36252));
   the game never reads or joins them.
5. **Small**: batches of 20 (up to 100 a request), sent on the way to the
   background under a background task; at most **400 events an install a
   UTC day** on the phone and **500** on the server; things done by the
   hundred (power-ups, relic upgrades, sweeps, energy, the wallet's
   movements) are counted and sent once, in the session's end; the table
   is pruned to **120 days** every night.
6. **Nowhere it should not run**: never under the CI tour (`-tour`), never
   in the unit tests' host or an Xcode preview, and nothing at all while
   `Backend.plist` is empty.

**Apple's rules.** "Collect" means sending data off the phone where it is
kept longer than the request needs; data is **not linked** when direct
identifiers such as a user ID or name are stripped before collection and it
is never linked back or tied to other datasets; and **linkage is answered
per data type** ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)).
The types involved, in Apple's words
([NSPrivacyCollectedDataType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype)):
**Product Interaction** — "app launches, taps, clicks, … saved place in a
game … or other information about how the user interacts with the app";
**Purchase History** — "an account's or individual's purchases or purchase
tendencies"; **Device ID** — "the device's advertising identifier, or other
device-level ID". Gameplay Content ("saved games, multiplayer matching or
gameplay logic") is the save, already declared.

So the honest declaration is: **Device ID — not linked, Analytics** (the
install's number, collected by nothing else); **Product Interaction** and
**Purchase History** — **linked**, App Functionality AND Analytics, because
their App Functionality use is linked (the player row's last launch; the
purchase ledger inside the cloud save) and one data type carries one answer.
The play data itself is still unlinked in fact; the label is conservative
where Apple's form cannot say both. TelemetryDeck, a privacy-first
analytics service, tells its customers to answer the same two types the
same unlinked way for its SDK
([How to set up Apple's app privacy details](https://telemetrydeck.com/docs/articles/apple-app-privacy/)).
Apple adds that personal data under a privacy law counts as linked; see the
EU note next.

**The EU.** Storing an identifier on a phone for analytics needs consent
under the ePrivacy rules unless it is exempt; France's CNIL exempts
audience measurement that is **used only for that**, produces **anonymous
statistics**, is **not cross-referenced** or shared, keeps its tracker **no
longer than 13 months, not extended by visits**, keeps its data **no longer
than 25 months**, and tells the user, who can object
([CNIL sheet 16](https://www.cnil.fr/en/sheet-ndeg16-use-analytics-your-websites-and-applications);
[a summary](https://www.truendo.com/en/blog/what-is-audience-measurement-cookies-consent-exemption)).
This design meets each condition (the number's 13 months, 120 days of data,
first-party only, the switch, the policy's paragraph). The honest caveat: a
persistent random number makes the data pseudonymous rather than anonymous
in the strict GDPR sense. **Decision for the owner:** on by default is his
choice (made 2026-09-23). If a lawyer asks for consent first in the EU, the
default flips to off in two lines — `Analytics.isSharing` (`?? true` →
`?? false`) and the `sharePlayData` default on the Support board in
`RootView.swift` (`= true` → `= false`) — and the switch becomes the
opt-in.

## 4. Supabase or a third-party SDK — the options and the choice

| | Supabase table (built) | TelemetryDeck SDK | GameAnalytics / Firebase SDK | PostHog / Aptabase |
|---|---|---|---|---|
| Where the data lives | the game's own project, beside the saves | TelemetryDeck (EU) | GameAnalytics / Google | their cloud, or self-hosted |
| Package dependency | none | Swift package | Swift package / CocoaPods | Swift package |
| Identifier | random, per install, 13 months | double-hashed user id | IDFV by default / app instance id | PostHog: a distinct id; Aptabase: none (so no retention) |
| Game dashboards | six SQL views, the SQL editor's charts | generic app charts | GameAnalytics: made for games (progression, economy) | generic product charts |
| Cost | database storage (§8) | free to 50,000 signals a month since July 2026, paid after ([pricing update](https://telemetrydeck.com/blog/pricing-update-2026/)) — 1,000 daily players × 45 is 1.35 M a month | free | free tiers, then usage |
| Privacy label | Device ID unlinked + Analytics on two types | the same, per its guide | the SDK's own list, IDFV included | varies |

**The choice: the Supabase table.** It fits this project in four ways the
others do not:

1. **No dependency.** The project has none, on purpose: `tools/swiftcheck.py`
   stands in for a compiler by reading plain Swift, and CI builds without
   resolving packages. A third-party SDK is code this environment can
   neither read into the checker nor compile.
2. **One place, one processor.** The saves already live in the owner's
   Supabase project and the privacy policy already names it; analytics in a
   second company adds a second processor to disclose, a second privacy
   manifest to aggregate, and a second account to keep.
3. **Anonymous by construction, and provably so.** The table cannot be
   read with the key the app carries; the phone cannot send a name; the
   server strips what a modified phone might try. With an SDK, "anonymous"
   is the vendor's configuration and promise.
4. **The owner's own questions, as SQL.** The views answer exactly §2's
   table, and any new question is one query away — no event schema a
   vendor's dashboard has to understand.

What the choice gives up, said plainly: ready-made charts and cohort tools
(GameAnalytics has game dashboards for free), and the storage bill is ours.
If the owner later wants those dashboards, the same events can be forwarded
from the table to a tool by a nightly Edge Function without touching the
app. Turso was not a candidate: `Docs/BACKEND.md` kept it out for having no
row-level security, and an insert-only table for the anon key is exactly
that.

## 5. The events

Every row: `install_id`, `name`, `props`, `app_version` (`1.2+57`),
`channel` (`release` or `debug`), `occurred_at` (the phone's clock, kept
unless five minutes ahead or a week behind), `created_at` (the server's).

| name | when | props |
|---|---|---|
| `first_open` | the first launch of an install (not of a phone that already held a save when this version arrived) | — |
| `session_start` | the app comes to the front | `d` days since the first open (the phone's calendar), `n` the session's number, `cold` 1 for a launch, `gap_min` minutes since the last session ended |
| `session_end` | the app goes to the back | `seconds`, and the session's counts: `power_ups`, `relic_ups`, `relic_15`, `sweeps`, `energy`, `offerings`, `divinity_spent`, `divinity_earned`, `drachma_spent`, `drachma_earned` |
| `funnel` | a step of the first hour, once per install | `step` (`account_guest`, `account_apple`, `welcome`, `first_fight`, `fight_done`, `first_summon`, `summon_done`, `first_relic`, `equip_done`, `first_powerup`, `power_up_done`, `farewell`, `skipped`), `minutes` since the first open |
| `stage_result` | every fought run, won or lost (campaign, Halls, Labyrinth, Tower, raids, shrines) | `stage` (the id without its tier), `tier`, `kind` (`campaign`, `hall`, `labyrinth`, `tower`, `raid`, `other`), `chapter`, `index`, `result` (`won`, `lost`, `forfeit`, `draw`), `turns`, `stars`, `power_pct` (team power ÷ recommended, to the nearest 10%), `power` (two significant figures), `energy`, `first` (1 on a first clear) |
| `summon` | a summon, a mileage redemption, a shrine summon | `count`, `best` (stars) |
| `arena` | an arena or draft fight | `won` |
| `evolve` / `awaken` / `fuse` | each one | `stars` for `evolve` |
| `level_up` | a demigod level not reached before on this install | `level` |
| `purchase` | a real-money purchase paid into the save | `product` (`divinity_phial`) |

Where each comes from: `QuestService.record` translates the game's own
records (`Analytics.translate` lists every case, so a new record is a
decision, not a gap) — including `stageSettled`, which
`CampaignService.settle` now records for every run, won or lost, because a
fail rate needs its failures. A swept run is told from a fight by the
result `SweepService.masteredResult` builds (nothing dealt or taken), and a
forfeit by `BattleViewModel.forfeit()`'s (a defeat with the same zeros);
`AnalyticsTests` pins both. The store's `player` feeds the first hour's
steps, level-ups, purchases (`Player.treasury`, `Docs/STORE.md`) and the
wallet's movements; the two sign-in buttons feed the account step; the
app's own comings and goings feed the sessions.

## 6. The views

All in schema `analytics`, release builds only, readable only in the
dashboard.

- **`daily`** — per UTC day: `active_installs`, `new_installs`, `sessions`,
  `sessions_per_install`, `median_session_minutes`, `minutes_per_install`,
  `fights`, `summons`.
- **`retention`** — per install day: `installs`, `d1_pct` … `d30_pct` (a
  day not yet over shows null, never a false zero) and the counts behind
  D1, D7 and D30.
- **`first_hour`** — for installs of the last 90 days: each step's
  `installs`, `pct_of_installs` and `median_minutes` from the first open.
  The biggest drop between two adjacent steps is the first thing to fix.
- **`stages`** — the last 30 days, in the game's order (kind, tier, chapter,
  stage): `attempts`, `installs`, `won`, `lost`, `forfeited`, `fail_pct`,
  `first_clears` (the progression funnel: how many got past it),
  `median_turns_won`, `median_power_pct_won`, `median_power_pct_failed`.
- **`quit_points`** — installs silent for seven days, by the last stage
  they fought and how it ended; one `before_any_fight` row for the rest.
- **`economy`** — per UTC day: `installs_summoning`, `summons`,
  `pulls_with_a_five_star`, divinity and drachma spent and earned,
  `energy_spent`, `swept_runs`, `power_ups`, `relic_upgrades`,
  `evolutions`, `awakenings`, `fusions`, `purchases`. By product:
  `select props->>'product' as product, count(*) from public.events where name = 'purchase' and channel = 'release' group by 1 order by 2 desc;`

One version only, after a balance patch:
`select * from public.events where app_version = '1.1+60' and name = 'stage_result';`
— every view's query is in the migration to copy and narrow.

## 7. On the phone

- **The switch**: More → Support → **Share anonymous play data**, on by
  default, its caption the list of what is sent. Off: the queue, the open
  session and the install's number are forgotten, and nothing is made.
  On: a new number and a session from that moment.
- **The queue** lives in memory; a batch of 20 flushes at once; the way to
  the background ends the session, writes the queue to the phone FIRST,
  then sends under a background task and clears what went. What a killed
  launch left is sent at the next session's start.
- **Failures are quiet**: one `[Analytics]` line in More → Diagnostics
  when uploads start failing and one when they recover; retries back off
  from 15 seconds to 15 minutes; a batch the table refuses outright (a 400)
  is dropped rather than retried for ever; at most 500 rows wait.
- **The first hour and the level** are read off the save each time it
  changes. What a save had already done when its store opened is marked as
  sent without sending, so a veteran updating to this version does not
  flood the funnel.

## 8. Volume and cost

Measured on a scratch PostgreSQL 16 with a synthetic month of 300 installs
(10,566 rows, a realistic mix): **about 330 bytes a row with its indexes**.
An active player makes about **45 rows a day** (four sessions, thirty
fights, a few summons and steps), about **15 KB**.

| daily players | a day | 60 days | 120 days |
|---|---|---|---|
| 250 | 3.7 MB | 220 MB | 450 MB |
| 1,000 | 15 MB | 0.9 GB | 1.8 GB |
| 5,000 | 74 MB | 4.5 GB | 8.9 GB |

The free plan's **500 MB** is shared with the saves: 60 days fit up to
about 400 daily players. **Pro** ($25 a month) includes **8 GB**: 120 days
fit to about 4,000 daily players. Supabase pauses a free project after a
week without requests
([pricing summary](https://uibakery.io/blog/supabase-pricing)), which
`Docs/BACKEND.md` §7 G already says to avoid before release. The nightly
prune is what keeps a full disk from ever reaching the saves.

## 9. What was checked here, and what cannot be

Checked: `python3 tools/swiftcheck.py --members --types` is clean (the
allow-list gained `NotificationCenter`, `UIBackgroundTaskIdentifier` and
`NSClassFromString`); `python3 tools/balance.py` exits 0; every Swift file
touched parses under tree-sitter's Swift grammar. The migration was run
**twice** on a scratch PostgreSQL 16 with Supabase's `anon` and
`authenticated` roles, its default grants and the two earlier migrations:
a bulk insert of the shape PostgREST sends for `return=minimal`
(`json_to_recordset`, `RETURNING 1`) succeeds as `anon`; `anon` cannot read, update or delete a row, set the id
or the arrival time, reach a view or run the prune; a name off the list is
refused; free text, booleans and nested objects are stripped from `props`;
505 rows from one install in a day keep 500; a clock a year ahead or a
month behind is replaced by the arrival; a row with text where a view
expects a number breaks no view; all six views return what §6 says over a
synthetic month; the helper functions inline into the plans and the views
use the name-and-time index; the prune deletes what is older than its
window.

Not checked, because nothing here can reach them: the Swift has never been
compiled (no toolchain; CI compiles it and runs `AnalyticsTests` on every
push); Supabase itself (`supabase.com` is closed) — in particular that
`create extension pg_cron` succeeds in the SQL editor (if not, step 3 says
what to do) and that the API serves the new table at once (PostgREST
reloads its schema after the migration; if an upload answers 404 for a
minute, that is the reload); the upload from a phone, the background task
finishing before suspension, and the App Store Connect answers. The CI tour
never sends (it is `-tour`), so its frames show the Support board's switch
and nothing more.
