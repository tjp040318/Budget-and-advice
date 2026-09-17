# Events — a calendar with no server (2026-09-17)

The owner wants the Summoners War gaps closed, and one of the widest is the
**calendar**: Summoners War is a different game on Tuesday than on Saturday,
and this one is the same game every day. `Docs/MARKET_2026.md` item 9 ("A
clock-driven calendar so the game is different on Tuesday") ranked it as a
one-week job in bucket A — the bucket that needs no server — and said how:
"a perpetual calendar baked into the build: the device clock tells you the
day of week and the week of year, and a table tells you what is different.
Nothing phones home." This is that, built.

## What Summoners War's calendar does

From memory, and marked as such (the data sites are refused by the network
policy, so nothing here was re-read):

- **Double-reward weekends on a rotating target.** A Cairos rune dungeon
  (Giant's Keep, Dragon's Lair, the Necropolis) or one of the elemental
  Halls pays double for a weekend. The target changes; the SHAPE — a
  weekend, one place, ×2 — is fixed, and the community plans its farming
  around it ("Giant's is 2× this weekend, save your energy").
- **Boost days.** A 2× experience day; half-energy days, where scenario
  stages cost half; double mana-stone events.
- **Special Login.** Around an update or an anniversary, a run of days with a
  gift for each day you log in, better than the ordinary daily login reward
  and gone when the run ends.
- **Event missions with a reward shop.** A themed mission set for a fortnight
  whose rewards are points, spent in an event exchange.
- **Two 2025 facts from the market research:** Ameria's Luck is a *daily*
  rotating drop-rate buff, and the Temple of Chaos runs "one week each
  month, starting on the first Monday". The genre's calendar has a DAILY
  beat, a WEEKLY beat and a MONTHLY beat.

The lesson the market doc drew, and the one this build takes: "the calendar
is not the content — the calendar is the *reason to open the app today
rather than Saturday*."

## The three ways to build it, and the one chosen

1. **A fixed weekly rota.** Monday is always drachma day, Wednesday always
   half-energy. Learnable in a week and never wrong; but every weekend is
   the same weekend, so there is nothing to look forward to and nothing to
   plan around.
2. **A rota seeded by the ISO week.** The same weekday shape, but the
   weekend's headline is drawn from a cycle by the week number, so this
   weekend's Hall is not last weekend's and next month's is knowable. Every
   player on Earth reads the same week off the same date; nothing is saved.
3. **Hand-authored seasonal events by date.** A table of (start, end,
   event) — a Saturnalia in December, an anniversary week. The truest to
   the genre and the only one that can carry a THEME, but every entry is a
   promise to ship the next one, and a table that ends is a game that goes
   quiet.

**Chosen: (2), with (1) as its weekday spine, and the table of (3) left as
the seam it would slot into.** The weekdays are a fixed rota (Mon 2×
drachma, Tue 2× experience, Wed half-energy campaign, Thu 2× laurels), the
weekend headline rotates by the ISO week (a Hall of Essence in three weeks
of four, a Labyrinth in the fourth), and the fourth week is the **Festival**
— the monthly beat — with a gift for every day of it. Daily, weekly and
monthly, like the genre; deterministic from the date, like item 9 asked;
and the only thing the save holds is which festival gifts were claimed.

**The clock.** UTC or the player's own day? The whole game keeps the
player's calendar day — `QuestService`'s missions reset at his midnight,
the arena refreshes on his day, the login streak counts his days — and a
second clock in the same game would have the Events screen say "ends at
5 pm" under a Missions screen that says "resets at midnight". So the
calendar reads the **local date** through an ISO-8601 calendar (Monday
first, whatever the region's setting): every player's Monday is drachma
day, and the week index is the same for everyone but the twenty-six hours
that straddle Monday somewhere on Earth. Summoners War runs on server time
because everything there does; a game with one clock keeps the one it has.
`EventCalendar.calendar` is the one place this is decided — switching to UTC
is one line — and the tests build their dates through it, so they pass in
any zone.

**Why the week is counted, not read.** The ISO week NUMBER restarts every
January, so a cycle read off it repeats or skips a headline at the year's
end. `EventCalendar.weekIndex(at:)` counts Monday-to-Sunday weeks from
Monday 1 January 2024 instead — a continuous ISO week — so the Halls come
round in order across the year boundary and nothing is ever seen twice in
a row.

## The rota

| Day | Event | What it changes | Constant |
|---|---|---|---|
| Monday | Double Drachma | every settled clear pays ×2 drachma | `EventTuning.drachma` 2.0 |
| Tuesday | Double Experience | unit and summoner experience ×2 on every clear | `EventTuning.experience` 2.0 |
| Wednesday | Half-Energy Campaign | campaign chapter stages cost half, rounded up (3 → 2, 4 → 2, 6 → 3); Halls, Labyrinth, Tower and Titans full price | `EventTuning.energy` 0.5 |
| Thursday | Double Laurels | arena battles pay ×2 laurels, won or lost | `EventTuning.laurels` 2.0 |
| Fri–Sun | the headline: **a Hall of Essence ×2** (three weeks of four; the element cycles Ember, Tide, Gale, Radiance, Umbra) or **a Labyrinth ×2** (the fourth week; the Vault, the Lair, the Necropolis in turn) | the Hall's every essence drop pays ×2 of the amount; the Labyrinth's relic roll is made twice, so a level that drops one every run drops two | `EventTuning.essence` 2, `EventTuning.relicRolls` 2 |
| the fourth week, Mon–Sun | **the Festival of the Gods** | a gift a day, claimed once per date (`Player.eventGiftsClaimed`), missed days simply missed | `EventCalendar.festivalGifts` |

Every number is in `EventTuning` (the top of `EventCalendar.swift`) and
mirrored in `tools/balance.py` as `EVENTS`; the rota's shape is three
statics on `EventCalendar` (`weekdayRota`, `weekendStart` 4 = Friday,
`labyrinthEvery` 4, `festivalEvery` 4), mirrored as `EVENT_WEEKDAY_ROTA`,
`EVENT_WEEKEND_START`, `EVENT_LABYRINTH_EVERY` and `EVENT_FESTIVAL_EVERY`.

**Why the Labyrinth's event is "two relics", not "double chance".** Every
Labyrinth level drops a relic on EVERY run (`relicChance` 1.0), so doubling a
chance would double nothing. The genre's "Reward ×2" on a rune dungeon is two
rewards a run, and that is what this is: the relic roll runs
`EventTuning.relicRolls` times. On a stage whose chance is under 1 the same
rule reads as two independent rolls, which is the honest ×2 there too.

**Why the essence event doubles the AMOUNT.** A Hall floor's Mid essence
already drops at 100% from B5 (`0.5 + 0.1 × floor`), so a doubled chance
would cap at one. Every essence roll that hits pays ×2, which is what "the
Hall pays double" means when read off the wallet.

**Why half-energy is campaign-only.** The Halls and the Labyrinth have their
own days. Halving their energy on Wednesday would be a second 2× essence
day for every Hall at once — bigger than the weekend headline it is meant
to sit beside — and would stack with nothing else only by luck. A stage is
"campaign" when `StageDatabase.chapterOrder(of:)` finds its chapter on the
road; a tier suffix (`duat_1@hard`) still counts.

**Why nothing stacks.** Each resource has ONE day: drachma Monday, experience
Tuesday, energy Wednesday, laurels Thursday, one Hall's essence or one
Labyrinth's relics the weekend. `balance.py --events` asserts that no day's
multiplier on any resource exceeds the single constant and that no
resource's weekly mean exceeds 2× — the lead's rule — and prints the tight
figures (drachma and experience 1.29× over a week, laurels 1.14×, a
headline farm 1.43×), because the loose rule would also pass a calendar
that had drifted.

**The Festival's gifts.** Seven, one per day of the fourth week, in
divinity-equivalent at the bazaar's rates: 15,000 drachma (50), two
Mystical Scrolls (150), 40 energy (40), 100 divinity (100), a Pantheon
Scroll (100), a 5★ relic (150), and on Sunday two Pantheon Scrolls and 100
divinity (300) — about 890, roughly nine pantheon summons, once every four
weeks. The ordinary seven-day login gift is about 473 a week, so the
festival is a second login week at nearly twice the rate, once a month: a
reason to open the app every day of that week, and about 6% of a first
month's income on top of `balance.py --counsel`'s baseline. A missed
festival day is missed — the genre's special login pays what you show up
for — where the ordinary gift's streak restarts.

## What is NOT built, and where it would go

- **Event missions with a reward shop.** The genre's fortnightly themed
  mission set. It needs `QuestService`'s counters scoped to an event window
  and a `ShopService` stall that opens and closes with it — a second week
  of work that touches the mission and shop systems other agents are in
  now. The seam is `EventKind`: an `.eventMissions(id)` case whose window
  `events(at:)` returns, with the counters keyed by the event id.
- **Seasonal events by date.** Option (3). `EventCalendar.events(at:)` is
  built from the rota; a `seasons: [(DateInterval, EventKind)]` table
  consulted first would add a Saturnalia without touching the rota. Not
  built because a table that ends is a game that goes quiet, and the owner
  should decide the cadence before the first entry is promised.
- **A banner rate bump** (item 9's "one pantheon's banner gets a small rate
  bump"). Deliberately left out: the gacha's rates are printed in the summon
  room and asserted by `balance.py --gacha`, and a rate that changes by the
  day is a rate that has to be disclosed by the day.

## Where the hooks are

Every hook is one line reading the calendar, commented `event`:

- `CampaignService.settle(stage:result:player:rng:now:)` reads
  `EventCalendar.boosts(for:at:)` once and hands them to
  `applyRewards(…, boosts:)`, which multiplies the drachma, both
  experiences, the essence amount and the number of relic rolls.
  `applyRewards` itself never reads a clock, so every existing test that
  asserts "exactly one relic" or a drachma figure stays deterministic
  whatever day CI runs on — the reason the date enters at `settle`, the one
  path a fought AND a swept run take (`GameStore.finishCampaignBattle`,
  `GameStore.sweep`).
- `CampaignService.startBattle`, `spendSweptRun` and `refund` charge and
  refund `EventCalendar.energyCost(for:at:)`; `spendSweptRun` returns what
  it charged so a receipt can add it up.
- `SweepService.affordableRuns` and `refusal` count runs at the event price.
- `ArenaService.applyResult(_:against:player:now:)` multiplies the laurels.
- `EventCalendar.claimGift(player:rng:at:)` pays the festival's gift once
  per date into `Player.eventGiftsClaimed` (Optional, like every save field
  since the first).

## Measured

`python3 tools/balance.py --events` prints the week that contains today, the
next eight weekend headlines, the multiplier matrix (six resources by seven
days with each row's mean), the campaign's daily drachma at a mid-chapter
stage on a flat day and a doubled one (288 energy a day, the sim's own
figure), and the festival against the ordinary login week; it asserts the
rota covers seven days, every resource has exactly one day, nothing stacks
and no weekly mean tops 2×.

`PantheonTests/EventTests.swift` pins the rota to the weekdays, the
headline's cycle to the week index, the multipliers to 1 outside an event
and the constant inside, the half-energy rounding, a gift that claims once,
the Optional save field, and a settle that pays double drachma on Monday,
double experience on Tuesday, double essence on the Hall's weekend and two
relics on the Labyrinth's.

## Wiring left for the lead (GameStore, the island, the map)

1. `GameStore.claimEventGift() -> [ShopService.Grant]?` — `attempt { player in
   try EventCalendar.claimGift(player: &player, rng: &rng) }`, the shape of
   `claimLoginGift`. `EventsView(onClaim:)` takes it.
2. `GameStore.sweep`'s receipt: `energySpent` should sum what
   `spendSweptRun` now returns instead of `outcomes.count * stage.energyCost`.
3. The screens that print `stage.energyCost` (the stage popup's "Fight — N
   energy", the briefing's "Begin", `SweepView`'s "No battle — N energy",
   `LabyrinthView`'s "Climb") should print
   `EventCalendar.energyCost(for: stage)` on a Wednesday; `ArenaView`'s
   laurels label likewise `× EventCalendar.multiplier(for: .arenaLaurelsBoost)`.
4. `EventBadge(event:)` on the island's header and the chapter map for
   `EventCalendar.active()`; `EventCalendar.claimableCount(player:)` for the
   red badge. The Events sheet opens from the island and More like Missions.
5. The tour: a step `events` after `island_decor` (46th screen) showing
   `EventsView(now: <a festival Monday>, onClaim: { _ in nil })` so the frame
   carries the gift band, the TODAY card and the weekend headline at once.

## The honest posture

Item 9's fourth point stands: the store listing should say this is a
schedule, not live events. "It is not a lesser thing; Another Eden built a
following on exactly this posture." What a server would add is not the
calendar — it is the ability to change it after the fact.
