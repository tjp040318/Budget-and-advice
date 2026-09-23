# The Treasury — real-money purchases

*2026-09-23. The owner: "Build it today." Until today the bazaar sold for the
game's own currencies only and the game earned nothing. This is the research,
the options and the choices for the first real-money store, what was built,
and the owner's steps in App Store Connect.*

Everything here is mirrored three ways, like every tuning number in the game:
`Pantheon/Core/Store/StoreCatalog.swift` (the truth), `tools/balance.py
--store` (the measurement, which also reads `Pantheon.storekit` and refuses to
run if its products drift from the catalog) and `PantheonTests/StoreTests.swift`
(the pins). Change a number in all three and in `Pantheon.storekit`.

## 1. What the genre sells

Tags: **[live]** was read from a source this session could reach (most wikis
and trackers are refused by the network policy, so many come through a search
engine's summary of the page); **[recall]** is from memory and should be
checked in the game itself before it is quoted to anyone.

| Game | Premium currency ladder | First purchase | Monthly pass | Season pass |
|---|---|---|---|---|
| **Summoners War** | Crystals: Handful 72, Bundle 120, Pile 240+10, Sack 480+20, Box 1,200+200, Chest 2,400+600 — the bonus grows with the tier (CAD $3.99 → $139.99; the US App Store lists the Chest at $99.99). About 24 crystals a dollar at the bottom and 30 at the top. [live] | not found [—] | no daily-crystal subscription could be verified for Sky Arena [—]; its packages are one-time and rotating [live] | Chronicles (the spin-off) sells a Summoner Pass, repriced $17.99 → $9.99 [live] |
| **Epic Seven** | Skystones; the top tier is 3,800 for $99.99 [live] | "Double Reward for First Recharge" on the skystone packs [live] | Monthly Pack I (~$5) and II (~$10) pay skystones daily for 30 days [live] | [—] |
| **Raid** | Gems: 4,200 for $100 in the permanent shop, 42 a dollar [live] | [—] | Daily Gem Pack: 2,140 gems over a month for $10 — about 5x the shop's rate [live]; the RAID Card is an AUTO-renewing subscription ($9.99 a month, $49.99 for six) [live] | [—] |
| **Genshin Impact** (the ladder every gacha copies) | Genesis Crystals 60 / 300+30 / 980+110 / 1,980+260 / 3,280+600 / 6,480+1,600 at $0.99 / 4.99 / 14.99 / 29.99 / 49.99 / 99.99 — 60.6 a dollar rising to 80.8 [live] | each tier's FIRST purchase is double its base, tiers independent, reset once a year [live] | Blessing of the Welkin Moon, $4.99: 300 at once and 90 a day for 30 days on login [live] | Gnostic Hymn [recall] |
| **Honkai: Star Rail** | as Genshin [recall] | as Genshin [recall] | Express Supply Pass, $4.99: 300 at once, 90 a day for 30 days [live] | Nameless Glory $9.99 (+680 jade), Nameless Medal $19.99 [live] |

**The shape every one of them has:** a ladder of six currency packs from
$0.99 to $99.99 that gets a little better per dollar as it climbs (Genshin
1.33x from bottom to top, Summoners War about 1.25x); a first-purchase double
per tier; a $4.99 thirty-day pass that is by far the best repeatable value
(Genshin's is 7.4x its top tier per dollar, Raid's 5.1x); a one-time starter
bundle; and a season pass beside them. The monthly pass is the purchase most
paying players make, and a season pass is bought by about 70% of payers where
overall conversion is under 2% (`Docs/MARKET_2026.md` §8, [live]).

A caveat for the record: the task named "SW's Crystal/Monthly style" for the
thirty-day pass. No such pack could be verified for Summoners War: Sky Arena
this session; the thirty-day daily pass is Genshin's, Star Rail's, Epic
Seven's and Raid's shape, and that is what was built.

## 2. Apple's rules

- **Guideline 3.1.1** (read from developer.apple.com this session): in-game
  currency must be sold through In-App Purchase; "Any credits or in-game
  currencies purchased via in-app purchase may not expire, and you should
  make sure you have a restore mechanism for any restorable in-app
  purchases"; and "Apps offering 'loot boxes' or other mechanisms that
  provide randomized virtual items for purchase must disclose the odds of
  receiving each type of item to customers prior to purchase."
  **Divinity buys summons, so selling divinity makes every summon a paid
  random item.** The odds are already published per banner (`RateTableView`);
  the Treasury now links to them from its header and from the starter's card,
  which holds scrolls.
- **Guideline 3.1.2** governs AUTO-renewable subscriptions: ongoing value, at
  least seven days, every device, and the terms, price and period described
  before the purchase with links to the Terms of Use and the Privacy Policy
  (Schedule 2).
- **Non-renewing subscriptions:** "It's your app's responsibility to make the
  subscription available on all of the user's devices and to let users
  restore the purchase" (App Store Connect help, via search [live]).
- **StoreKit 2** (Apple's documentation JSON, read this session):
  `Transaction.updates` must be listened to from launch — "If your app has
  unfinished transactions, the updates listener receives them once,
  immediately after the app launches"; `Transaction.unfinished` returns them
  at any time; `finish()` is called "after you deliver the purchased content";
  `currentEntitlements` holds non-consumables, live auto-renewables and "the
  latest transaction for each non-renewing subscription, including finished
  ones" but never consumables or refunded items; `AppStore.sync()` shows an
  App Store sign-in and belongs only behind an explicit Restore button;
  `AppStore.canMakePayments` is false under Screen Time's purchase
  restriction or an MDM profile, and then "don't enable your user interface
  for making Apple In-App Purchases"; a purchase that needs a parent's
  approval (Ask to Buy) returns `.pending` and arrives later through
  `updates`; `appAccountToken` rides on the transaction for the account that
  bought it.
- **App Store Connect:** the first In-App Purchases must be submitted WITH a
  new app version, all of them together; each needs a review screenshot and
  review notes [live]. The Paid Apps agreement, tax forms and banking must be
  active first, which takes about a day after they are complete [live].
- **Age and parents.** Every developer had to answer Apple's new age-rating
  questionnaire by 31 January 2026; it asks about loot boxes, and an app that
  says yes is rated **18+ on the Brazil storefront** automatically [live].
  Texas's App Store Accountability Act (in force 1 January 2026) makes the
  STORE verify age and get a parent's consent for a minor's downloads and
  purchases; Apple's Declared Age Range API passes the age band to the app
  [live]. Parental approval of each purchase is Apple's Ask to Buy, which the
  Treasury handles as `.pending`.
- **Belgium** has treated paid loot boxes as illegal gambling since 2018
  [live]; several gacha games never shipped there.

## 3. The options, and what was chosen

### 3.1 How much a dollar buys

Divinity is the currency a Pantheon Scroll costs 100 of. The game's own free
income is generous by the genre's measure: about 6,000 divinity-equivalent a
month in divinity and Pantheon Scrolls alone, 14,700 with every scroll, and a
pantheon banner's 5★ every 29.5 pulls on average (3% with pity at 90;
`balance.py --gacha`).

| Option | Top tier | A pantheon pull | A pantheon 5★ | $100 against a free month |
|---|---|---|---|---|
| A. The genre's price per PULL (Genshin's ladder, per 100) | 50 a dollar | $2.00 – $2.48 | about $59 | 0.8 of a month |
| B. $100 = one free month | 60 a dollar | $1.67 | about $49 | 1.0 |
| C. Generous | 100 a dollar | $1.00 | about $30 | 1.7 |

**Chosen: A.** A pull costs what a pull costs everywhere in the genre, so
nobody who knows the genre finds the Treasury cheap or dear; the game's own
3% rate already makes a paid 5★ half of Genshin's, which is the generosity;
and a month of play stays worth more than $100, so a free player is never
told his month was worth a coffee. C would make the free month look worthless
beside the store. B was the close second.

### 3.2 What kinds of products

| Offer | Product type | Why |
|---|---|---|
| Six divinity packs | **Consumable** | The currency; the genre's ladder. |
| The starter ("A Demigod's Welcome") | **Consumable, once per save** | A non-consumable would be RESTORED into every new account on the phone — a guest, a reset, a second demigod — and pay its divinity again each time. As a consumable it is paid once to the save that bought it; the Treasury hides the button once the save has one. |
| The thirty-day "Blessing of the Gods" | **Non-renewing subscription** | See below. |
| A season pass | **not built — v2** | See §7. |

**The Blessing: non-renewing, not auto-renewable.** An auto-renewable
subscription brings Schedule 2's disclosures (price, period, renewal terms,
Terms-of-Use and Privacy links on the paywall and the store page), a
subscription group, billing retry and grace periods, upgrades and downgrades,
and a review that reads all of it; the genre's players buy the monthly pass
by hand each month and expect to. A non-renewing subscription is the honest
type for "thirty days of something" (a consumable would do the same job and
is what several games use, but it is not what Apple's catalogue calls a
time-limited service), needs none of the renewal machinery, and asks only
that the app restore it — which the save's cloud copy does for a signed-in
demigod, and the App Store's own history (`Transaction.all`,
`currentEntitlements`) does for the account that bought it (§4.4).

**Days bank; they are never forfeited.** Genshin and Star Rail pay the day
only if you log in that day. Here a claim pays EVERY day the Blessing has run
that is not yet paid: a missed day waits. Three reasons: Guideline 3.1.2(a)'s
"without … checking in to the app a certain number of times" is written for
auto-renewables but its spirit reaches any paid time-limited product and a
reviewer can apply it; the market report's standing advice is to sell
certainty and nothing predatory; and a banked total is exploit-proof — a
clock moved forward can only bring days forward, never mint more than thirty
a purchase. The daily moment is kept: a gold dot on the Treasury's rail row,
"Today's is waiting" and a gold CLAIM 50 on the card.

### 3.3 Granting exactly once

The ledger (`TreasuryLedger`, `Player.treasury`) lives **in the save**, not in
a file of its own:

- The grant and the record of it are ONE mutation of `Player`, written in one
  atomic file write, so there is no instant in which the divinity exists
  without the record (a double grant on relaunch) or the record without the
  divinity (a lost purchase). A separate file is two writes, and a crash
  between them is exactly the bug the ledger exists to prevent.
- It travels with the save's cloud copy (Supabase or iCloud), so a demigod
  restored onto a new phone knows what it was already paid.
- A reset (`AppSession.startOver`) starts a fresh ledger with the fresh save.
  That is correct: consumables already finished are never delivered again,
  and a Blessing still running restores its remaining days — which were paid
  for — and never its up-front divinity.

The order, every time: verify (StoreKit's JWS check; an unverified
transaction is never granted and never finished) → grant and record in one
`update` → write the save to disk synchronously (`SaveStore.save`) → only then
`finish()`. A crash before the write re-delivers the transaction at launch
and the ledger does not know it, so it is granted; a crash after the write
re-delivers it and the ledger knows it, so it is only finished. A write that
fails leaves the transaction unfinished for the next launch.

A transaction that arrives while no store is open (the sign-in screen, an
account being deleted) is left unfinished; when a store opens,
`Transaction.unfinished` is swept into it. A FINISHED transaction the ledger
does not know was delivered elsewhere (another phone) and is never paid again
— except that a Blessing restores its days still ahead (§4.4).

### 3.4 Where the check is done

**On the device, v1.** StoreKit 2 verifies every transaction's signed JWS
against Apple's certificate chain before the app sees `.verified`. A server
check (a Supabase Edge Function running Apple's App Store Server Library, the
transaction recorded server-side) is the genre's way and is **v2** — it needs
the summon on the server too before it buys anything a modified client cannot
fake (`Docs/PLAN.md`, *The backend*).

### 3.5 Refunds

A refunded transaction arrives through `updates` with a `revocationDate`, and
one refunded while the game was closed is found at the next sign-in in
`Transaction.all` (which keeps refunded consumables). The ledger takes back
what that transaction paid THIS save — its divinity, the starter's scrolls and
drachma where still held, a Blessing's unpaid days — never below zero, and
marks it so it is taken once and never restored; a refund of something the
save was never paid changes nothing. The genre's servers go further (negative
balances, bans); an offline game settles for making buy-spend-refund
pointless.

### 3.6 The odds

Every paid random item is a summon bought with divinity. The Treasury's header
carries **Odds**, which lists every scroll's grade odds and opens its full
published table (`RateTableView`); the starter's card, which holds Pantheon
and Divine Scrolls, carries its own **Odds**.

## 4. The catalog (`StoreCatalog`)

Prices are the tiers to pick in App Store Connect (US$); the App Store shows
each storefront its own price, and the Treasury prints the App Store's
`displayPrice` and nothing else — "—" when the App Store has not answered.

### 4.1 Divinity

| Product id | Name | Price | Divinity | Bonus | Total | a dollar | FIRST purchase |
|---|---|---|---|---|---|---|---|
| `com.pantheon.game.divinity.phial` | Phial of Divinity | $0.99 | 40 | 0 | 40 | 40.4 | 80 |
| `com.pantheon.game.divinity.chalice` | Chalice of Divinity | $4.99 | 200 | 10 | 210 | 42.1 | 400 |
| `com.pantheon.game.divinity.amphora` | Amphora of Divinity | $9.99 | 400 | 30 | 430 | 43.0 | 800 |
| `com.pantheon.game.divinity.coffer` | Coffer of Divinity | $19.99 | 800 | 80 | 880 | 44.0 | 1,600 |
| `com.pantheon.game.divinity.chest` | Chest of Divinity | $49.99 | 2,000 | 300 | 2,300 | 46.0 | 4,000 |
| `com.pantheon.game.divinity.hoard` | Hoard of Divinity | $99.99 | 4,000 | 1,000 | 5,000 | 50.0 | 8,000 |

A pack's first purchase in a save is DOUBLE its base, in place of its bonus
(Genshin's rule), once per pack, for ever. The ladder climbs 1.24x from
bottom to top (Genshin 1.33x).

### 4.2 The starter — `com.pantheon.game.starter.welcome`, $4.99, once per save

"A Demigod's Welcome": **500 divinity, 5 Pantheon Scrolls, 1 Divine Scroll
(a 4★ or better; 12% a 5★) and 100,000 drachma** — about 1,930
divinity-equivalent, 7.7x the Hoard's rate per dollar.

### 4.3 The Blessing — `com.pantheon.game.blessing30`, $4.99, non-renewing

"Blessing of the Gods": **300 divinity at once, then 50 a day for 30 days**,
1,800 in all — 7.2x the Hoard's rate per dollar (Genshin's Welkin: 7.4x).
Buying it while it runs adds thirty days to its end, up to 180 days waiting
(the Welkin's cap). Buying it after it has ended pays any days still waiting
at once and starts a new thirty.

### 4.4 Restoring

- **At every sign-in**, automatically: `Transaction.unfinished` is swept into
  the save, then every Blessing transaction in `Transaction.all` that the
  ledger does not know — and whose `appAccountToken` is this account's, or
  none — restores the days of its window still ahead, never the ones behind
  and never its up-front divinity. Windows stack in purchase order, as live
  purchases do.
- **Restore** in the Treasury's header: `AppStore.sync()` (Apple's sign-in
  sheet), then the same sweep, then a sentence saying what came back.
- Consumables are not restorable (Apple's rule); the save's cloud copy
  carries their divinity. **A guest's purchases live only in the guest's
  save** — on a new phone a guest is a new account; the Treasury's footnote
  says so and suggests Sign in with Apple.

### 4.5 What it is worth (`python3 tools/balance.py --store`)

The measure the owner asked for: a pass against the free income. The free
month is the game's own sources in divinity-equivalent (a Pantheon Scroll
100, a Mystical 75, an Unknown 5,000 drachma at 300 a divinity, energy 1:1):
the daily missions and their bonus 9,950 a month (the figure the Codex was
measured against), the login week 2,021, the Daily Offering 2,750 — **14,721
a steady month**, of which **6,043** is divinity and Pantheon Scrolls, the
part the Treasury sells. A first month adds its one-offs, 20,036 in all: the
twelve chapters' first clears 2,934, their Normal chests 5,520 and half of
them on Hard 3,480 (`--counsel`'s month without the login gifts the steady
month already counts), Athena's Counsel 6,562 and the Codex about 1,540.

| | Divinity | a dollar | x the Hoard | against a steady free month |
|---|---|---|---|---|
| The Blessing, $4.99 | 1,800 | 360.7 | 7.2x | +30% of its divinity and Pantheon Scrolls, +12% of everything |
| The starter, $4.99 | ≈1,930 | 387 | 7.7x | once |
| The Hoard, $99.99 | 5,000 | 50.0 | 1.0 | 0.83 of the month's divinity and scrolls |

`--store` asserts: every pack better per dollar than the one below it; a
first purchase exactly twice the base; the Blessing and the starter each at
least five times the best pack; the Blessing never more than half of a
steady free month's divinity and scrolls, and the Hoard less than all of them
(a month of play is worth more than $100); and that `Pantheon.storekit` lists
exactly the catalog's products, types and prices.

## 5. The screen

The **Treasury** is the bazaar's first stall (`TreasuryStall`,
`Pantheon/UI/Shop/TreasuryStall.swift`), in the house's glass over the Forum:

- The header: TREASURY carved, "Real money · App Store" as its eyebrow, and
  two glass beads — **Odds** and **Restore** (and **Retry** while the App
  Store has not answered).
- The first row: the **Blessing** across two columns — a seal whose gold
  ring empties as the days run, with the days left in it; "30-DAY PASS" and
  its ? (the terms in full); "Day 12 of 30" and "Today's is waiting"; CLAIM 50
  over the plate that adds thirty days — and the **starter** in the third:
  "ONCE ONLY", its divinity, Pantheon and Divine Scrolls (the drachma and the
  scrolls' odds behind its ?), its price, OWNED once bought.
- Two rows of three packs: a pile of the painted crystal that grows with the
  tier (the gold chest behind the two largest), the amount it pays NOW,
  "FIRST BUY ×2" with a gold "×2" on the corner while the double stands or
  "+30 BONUS" after, and a gold BUY plate with the App Store's price.
- Under them a footnote: the prices are the App Store's and divinity bought
  here never expires; for a guest, that purchases stay with this save.
- The rail row carries a gold dot while a Blessing day is waiting.

Before the App Store answers — and always under `-tour` and in CI, which
signs nothing and has no StoreKit configuration — every tile shows its
contents with "—" for a price and a dark, disabled BUY, and the eyebrow says
why ("Asking the App Store", then "The App Store did not answer" with a Retry
bead after twelve seconds). A purchase in flight turns its plate to
"BUYING"; Ask to Buy says "Waiting for approval"; Screen Time's restriction
turns the eyebrow to "Purchases are off here" and every BUY dark.

## 6. Files

- `Pantheon/Core/Store/StoreCatalog.swift` — the catalog, the ledger types,
  `TreasuryService` (deliver, claim, restore, revoke; pure, tested).
- `Pantheon/Core/Store/PurchaseService.swift` — StoreKit 2: products,
  purchase, the `updates` listener, the unfinished sweep, restore.
- `Pantheon/App/GameStore+Store.swift` — the store's side: the durable
  delivery, the claim, the tour's seed.
- `Pantheon/UI/Shop/TreasuryStall.swift` — the stall, its tiles, the odds
  sheet. `ShopView.swift` puts it on the rail.
- `Pantheon/Core/Models/Player.swift` — `treasury`, Optional, in its own
  marked block.
- `Pantheon/App/PantheonApp.swift` — `PurchaseService.shared.start()` at
  launch and `attach` when a store is installed.
- `Pantheon.storekit` (repo root, OUTSIDE the synchronized `Pantheon/`
  folder, so it is never copied into the app) and the shared scheme's Run
  action pointing at it (`../../Pantheon.storekit`, the path Xcode writes for
  a file beside the project).
- `PantheonTests/StoreTests.swift`, `tools/balance.py --store`.

## 7. Not built, and what each would take

- **The season pass** (free and paid tracks, the market report's item 8): a
  30-day season keyed off the install date, points from everything the game
  already counts (`QuestService.record`), 50 tiers with the paid track as a
  non-consumable per season or a consumable per season. It is its own
  feature — a track screen, a points economy and a balance pass — and was
  left whole for v2 rather than half-built today.
- **Server verification** (§3.4) and the summon on the server.
- **The first-purchase doubles resetting yearly** (Genshin's anniversary).
- **Painted pack art**: six piles and a Blessing medallion as Meshy pictures,
  about 6 credits each on the owner's word; the stall draws piles of the
  existing crystal until then.
- **The wallet's divinity chip opening the Treasury** (the genre's "+"): a
  one-line change in `BarWallet`, another feature's file.

## 8. The owner's steps

### Before the build that goes to review

**Turn the Testing stall off**: `ShopService.testingPacksEnabled = false`
(`Pantheon/Core/Shop/ShopService.swift`). While it is on, the bazaar hands out
2,000 divinity, scrolls and relics for free, as often as asked, one row below
the Treasury that sells divinity — a reviewer reads that as a test build and
as currency given away beside the currency sold. It is one line, and it is the
owner's call when; it is left on here because he still tests with it.

### In App Store Connect (in this order)

1. **Business → Agreements**: accept the **Paid Apps** agreement (Account
   Holder only).
2. In the same place, fill **Tax Forms** (the U.S. form every developer
   completes) and **Bank Accounts**. Wait for the agreement to show
   **Active** — about a day.
3. **Apps → Pantheon → Monetization → In-App Purchases → (+)**, once for each
   row below. Type, Reference Name and Product ID exactly as written (a
   product id can never be reused, even after deletion):

   | Type | Reference Name | Product ID | Price |
   |---|---|---|---|
   | Consumable | Phial of Divinity | `com.pantheon.game.divinity.phial` | $0.99 |
   | Consumable | Chalice of Divinity | `com.pantheon.game.divinity.chalice` | $4.99 |
   | Consumable | Amphora of Divinity | `com.pantheon.game.divinity.amphora` | $9.99 |
   | Consumable | Coffer of Divinity | `com.pantheon.game.divinity.coffer` | $19.99 |
   | Consumable | Chest of Divinity | `com.pantheon.game.divinity.chest` | $49.99 |
   | Consumable | Hoard of Divinity | `com.pantheon.game.divinity.hoard` | $99.99 |
   | Consumable | A Demigod's Welcome | `com.pantheon.game.starter.welcome` | $4.99 |

4. **Monetization → Subscriptions → Non-Renewing Subscriptions → (+)**:
   Reference Name **Blessing of the Gods**, Product ID
   `com.pantheon.game.blessing30`, price **$4.99**.
5. For each of the eight: **Price Schedule** → the price above in the United
   States (base country) and let the other storefronts follow; **Availability**
   → all countries the app is in (consider leaving **Belgium** out, §2);
   **App Store Localization** (English U.S.) → the Display Name and
   Description from `Pantheon.storekit` (30 and 45 characters at most);
   **Review Information** → a screenshot of the Treasury showing that
   product (one landscape iPhone screenshot at a size the app supports) and
   the note: "Tap the wallet on the island (or More → Bazaar), then Treasury
   at the top of the stall list." Leave Family Sharing off.
6. **App Information → Age Rating → Edit**: answer the loot-box question
   **Yes** (divinity buys randomised summons) and In-App Controls truthfully.
   Expect 18+ on the Brazil storefront.
7. On the next app version's page, under **In-App Purchases and
   Subscriptions**, select all eight and submit them **with** the version.
8. **Users and Access → Sandbox → Testers (+)**: a sandbox Apple Account to
   buy with on a real phone (Settings → App Store → Sandbox Account).

### In Xcode, to buy with test money today

1. Open `Pantheon.xcodeproj`. **Product → Scheme → Edit Scheme… → Run →
   Options**: StoreKit Configuration should read **Pantheon.storekit**. If it
   reads None or shows the file in red, choose it from that menu (it is
   `Pantheon.storekit` beside the project; the menu can add it).
2. Run on a Simulator. Bazaar → Treasury: the prices read $0.99 … $99.99 and
   BUY opens Apple's sheet; nothing is charged.
3. **Debug → StoreKit → Manage Transactions** shows every test purchase;
   select one and **Refund** to watch the clawback, or **Delete** to start
   over. **Editor → Enable Ask to Buy** (with the .storekit file open) tests
   `.pending`.
4. For a real phone with a sandbox account: target **Pantheon → Signing &
   Capabilities → + Capability → In-App Purchase** (it marks the App ID; no
   entitlement key is written), set the scheme's StoreKit Configuration to
   **None**, and buy with the sandbox tester from step 8 above. Sandbox
   prices come from App Store Connect, up to an hour after an edit.
5. Every purchase, delivery, refund and restore writes a `[Treasury]` line to
   the console and to More → Diagnostics.

## 9. What CI cannot verify

- Nothing about StoreKit runs in CI: the job signs nothing, launches the app
  with `simctl` (no scheme, so no StoreKit configuration), and the tour skips
  StoreKit altogether. CI proves the build, the tests (`StoreTests` run the
  ledger, the Blessing, restore and refunds with no StoreKit at all) and the
  stall's look with "—" prices.
- A real purchase, Ask to Buy, a refund, `AppStore.sync()`'s sheet and the
  delivery through `Transaction.updates` can only be tried in Xcode with the
  configuration file (above) or with a sandbox account on a device.
- Whether Xcode's scheme editor lists a `.storekit` file that sits beside the
  project rather than in it: the scheme's reference is by path and should
  resolve; if not, step 1 above adds it in two clicks.
