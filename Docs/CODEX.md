# The Codex — the collection book (2026-09-23)

Every family of every live pantheon, each in its five element forms and,
where the family has one, each form's awakened face: **830 pages** on the
roster of 2026-09-23 (99 families, 495 forms, 335 awakened faces). The forms
the player has held are lit; the rest stand in shadow under a "?". Every new
page pays a little divinity, a family's first page pays a little more, and a
pantheon pays a prize at a quarter, a half, three quarters and the whole of
its pages.

Code: `Pantheon/Core/Codex/CodexService.swift` (the book, the ledger, the
table, the claims, the roads), `Pantheon/App/GameStore+Codex.swift` (the
store's three claim actions and the badge count),
`Pantheon/UI/Codex/CodexView.swift` (the book), `CodexPageView.swift` (a
form's page), `CodexParts.swift` (the rows, tiles, card, track and marks),
`PantheonTests/CodexTests.swift` (the table and the claim rules). One save
field: `Player.codexClaims` (Optional). The door is a glyph in the
Collection's strip.

## The research

**What this environment could reach.** The web search tool answers with
summaries; every page that holds the detail was refused by the egress policy
when fetched — `summonerswar.fandom.com`, `namu.wiki`,
`summonerswar.spokland.com`, `www.swmasters.com` (EGRESS_BLOCKED, as the
data sites were for the relic odds). So the genre's collection books below
are described from knowledge of the games and from the search summaries, and
a claim about a game's exact reward amount is not made here, because none
could be checked. What the brief itself states of Summoners War — every
monster listed by element, the owned ones lit, a reward for each new one — is
taken as given.

**The genre's books.**

- **Summoners War: Monster Collection.** Every monster in the game, filed by
  element; the ones summoned in colour and the rest as dark silhouettes; the
  awakened form beside the plain one; an unowned monster's page still shows
  what it is — its stats and skills — which is what makes the book a hunting
  list rather than a trophy cabinet.
- **Epic Seven: Collection → Heroes.** Filterable by grade, element and
  class; a hero's page carries the art, the story, the skills and where the
  hero is found.
- **Raid: Shadow Legends: the Champion Index.** Opened from the Bastion's
  Index button, filed by **faction** — which is exactly what a pantheon is
  here — and within a faction by rarity.
- **Completion prizes.** The pattern of a region's book paying at shares of
  completion (Pokémon GO's collector medals at bronze, silver and gold) is
  the milestone track this game already draws for events and chests.
- **Collection EFFECTS** (Summoners War: Chronicles, Lineage M's 도감):
  permanent stat bonuses for registering monsters. Rejected below.

**What this project already had.** `Player.codex` — "blueprint ids ever
owned, for the codex" — written by the summon, the mileage exchange, the
selector, the fusion, the Night Market's unit row and the starter, and read
by the More screen's count (`codex.count / UnitDatabase.collectiblePool`)
and one Counsel step. The book had a record and a number, and no screen.

## The options, and the choices

### What counts as held

1. **A new "ever owned" field** for forms and awakened faces. Rejected: the
   forms already have one (`Player.codex`), and a second record of the same
   thing is a record that can disagree with the first.
2. **The roster alone.** Rejected: a unit fed to another would un-light its
   page, and the genre's book never forgets.
3. **Chosen: `Player.codex` ∪ the roster ∪ the claims.** The roster is in it
   because the tour's seed adds units without writing the codex (and any
   future path that forgets to is covered). An awakened face has no record
   at all — an awakening writes only the unit — so it is lit by an awakened
   unit in the roster or by its own claim: once taken, the page stays lit
   after the unit is gone. The ONE new field is the claims, which is also
   what makes a claimed page permanent.

### The layout

- **A. Summoners War's element tabs**: pick an element, see every family's
  form in it as one grid. A family's five forms are split across five tabs,
  and no pantheon's completion can be read anywhere.
- **B. Chosen: a pantheon rail, and a table of families by the five
  elements.** A row per family, its five forms in the order every column
  keeps (ember, tide, gale, radiance, umbra), Forms or Awakened in the
  strip. It is this game's own design — "a character is not one unit, it is
  five" (Docs/DESIGN.md) — laid out as a table, so a family's completion
  reads across a row and an element's down a column; the pantheons are
  Raid's factions, each with its count, its meter and its milestone track;
  and each pantheon's pages stand in its own realm's painting, so the book
  is a walk through the five realms.
- **C. Epic Seven's one filtered grid**: 830 cards behind filters is a wall,
  and the family is lost in it.

### The reward

1. **Collection effects** (a stat per page). Rejected: every curve in this
   game is measured by `tools/balance.py`, and a bonus that grows with the
   collection moves all of them at once.
2. **A flat reward per page.** Rejected: a 3★ common's page would pay what a
   5★ god's does, and there are 160 common pages.
3. **Chosen: by grade**, the awakened face above its form (an awakening is
   twenty Hall runs of work for a 5★; a summon is luck), Radiance and Umbra
   double (the premium pair, the Light & Dark scroll's alone), a family's
   first page a little more (a new character is worth more than a new colour
   of one), and a pantheon's tiers paying scrolls — the prizes grow from a
   Pantheon Scroll to the premium one.
4. **Cosmetics** (titles, frames): the game has no system for them.

### Claiming

A page is claimed on its page (`ClaimPlate`), a pantheon's tier by tapping
its marker on the track, and everything waiting at once with the strip's
**Claim N** — a player opening the book on a veteran save has a hundred
pages waiting, and a hundred taps is not a reward. An unclaimed page wears a
small gold seal on its tile's shoulder; a pantheon with anything waiting
wears it on its face on the rail; the Collection strip's Codex door wears it
while anything in the book waits.

### The unseen card

The cards are opaque paintings, so there is no silhouette to cut. Two
treatments were rendered on real cards before choosing (the fire Anubis,
the water Isis, Zeus, Odin, the light Shabti, Mars, Sun Wukong, Horus): an
**etched bronze plate** (the card's luminance as a black mask over bronze,
`luminanceToAlpha`), and **the card in shadow** (drained of colour, warmed
toward bronze, 62% dark). The etching was the more striking; the shadow was
chosen because it is built from three modifiers whose arithmetic is certain
(`saturation(0)`, `colorMultiply`, a black overlay), where the etching
depends on how SwiftUI's luminance mask treats colour space, which nothing
here can run to check. The light Shabti's halo, bright in the painting, is
the one card the etching turned to a blot.

## The reward table

| Page | 3★ | 4★ | 5★ |
|---|---|---|---|
| A form recorded | 5 divinity | 10 | 25 |
| An awakened face recorded | — | 20 | 40 |
| The first page of a family claimed (on top) | 5 | 20 | 50 |

Radiance and Umbra pages pay double (`premiumMultiple`); the family's first
is never doubled. The dearest single page is a 5★ Radiance or Umbra
awakened face, 80 — under a Pantheon Scroll's 100, which is the line: the
book is a small return on the summons, never a second income
(`CodexTests.testTheRewardTableIsPinned` pins it).

| A pantheon's pages recorded | Prize |
|---|---|
| 25% | a Pantheon Scroll and 100 divinity |
| 50% | a Divine Scroll |
| 75% | a Light & Dark Scroll and 300 divinity |
| 100% | three Light & Dark Scrolls and 1,000 divinity |

A tier is reached on the pages **recorded**, whether or not their own
rewards were taken — the share is of the collection, not of the claims —
and its share rounds up (25% of Rome's 85 is 22). The shares are real
distances: Egypt's 75% needs 162 pages and its non-premium pages are 129, so
three quarters of a pantheon asks for Light & Dark pulls; 100% asks for
every Radiance and Umbra 5★, about 1,950 Light & Dark scrolls of mileage for
Egypt's twelve — the whale's crown, as the genre's 100% always is.

## What the book pays — measured

Divinity-equivalent at the bazaar's prices (a Pantheon Scroll 100, a
Mystical 75, a Divine 600, a Light & Dark 450, an Unknown 5,000 drachma at
300 a divinity), as `tools/balance.py --counsel` counts it.

**The whole book** (`CodexTests.testTheWholeBookIsWhatTheDocMeasured`):

| | |
|---|---|
| 495 forms | 8,225 divinity |
| 335 awakened faces | 12,600 divinity |
| 99 families' firsts | 2,190 divinity |
| 20 pantheon tiers | 7,000 divinity + 5 Pantheon, 5 Divine and 20 Light & Dark Scrolls = 19,500 |
| **Everything** | **about 42,500** |

11,900 of the pages' 23,015 are Radiance and Umbra pages, and most of the
tiers' 19,500 is the 75% and 100% prizes: the book's long tail is paid for
with the rarest pulls in the game.

**Against the economy.** `python3 tools/codex_calib.py` reads the family
table out of the Swift, builds all 830 pages and plays a month of pulls forty
times with the scrolls' real odds and pools, and exits non-zero if a first
month passes 10% of its income or a first year 5% (it mirrors the table:
change a number in `CodexService`, there, here and in `CodexTests`
together; it belongs in `tools/balance.py` as `--codex`, which was another
feature's file the day this was built). The pulls are a first month's from
the game's own sources — the daily
missions' three Unknown, one Mystical and one Pantheon Scroll a day, the
login gift, the Counsel road, the chapter clears and the starting wallet,
with the month's divinity spent on Pantheon Scrolls — about 110 Unknown, 55
Mystical and 110 Pantheon pulls and one Light & Dark, spread over the five
pantheon banners; one awakening in the first month and two a month after.
The income it is measured against is `balance.py --counsel`'s first month
(13,961: first clears, Normal and Hard chests, the login gift) plus the
daily missions (9,950 a month).

| Window | Recorded | The book pays | Share of the window's income |
|---|---|---|---|
| First month | 116 forms of 55 families, 1 awakened | about 1,540 | 6.4% (11% without the missions) |
| First year | 261 forms of 96 families, 24 awakened; every pantheon's 25% | about 6,700 | 2.3% (4% without) |

Beside the other things the game pays for walking it: Athena's Counsel is
6,562 over the first month (47% of the month's floor), a Normal chapter's
three tribute chests 460, all 108 chests about 23,300, the feats about
7,100. The book's month is a quarter of the Counsel road's — **a bonus, not
an income** — and it tapers, as a collection does: the first month is mostly
new families' firsts and commons' pages; a year in, the pages left are 5★s,
awakenings and the premium pair.

**A save that already exists** opens the book on its backlog: every form
already in `Player.codex` is a page waiting. A player a month in has about
1,500 waiting, a year in about 6,700 — one Claim, once. The genre pays a new
collection feature's backlog the same way.

## The screen

A PLACE, so glass over art (Glass.swift): each pantheon's pages stand in its
realm's painting — the Hall of Two Truths for Egypt, where the dead are
weighed and recorded; Olympus's gate; Yggdrasil's roots; the Forum; the
Peach Garden — with a dark wash, deeper on the two pale paintings.

Measured for an iPhone 16 Pro in landscape, a sheet's content box of
750 × 329:

- **The strip**: CODEX, "132 of 830 recorded", Forms | Awakened, Claim N
  (only while something waits), the divinity well.
- **The rail** (176): the five pantheons, each a row of 50 — the banner's
  god in a ring, the name, a meter in the pantheon's colour and "84/215" —
  five rows standing whole and unscrolled above the rail's fade.
- **The room** (574): the realm's name carved with the pantheon and its
  percent as the eyebrow, beside the **milestone track** (276): the recorded
  share as a gold meter with four markers at 25/50/75/100%, each carrying
  its prize's painted scroll; a reached marker glows and pulses until
  claimed, a claimed one wears a tick, and a tap on any other says its prize
  and how many pages it still asks.
- **The table** on dark glass (259 tall): a row per family, the rarest first
  — the name (the roster's widest, "TERRACOTTA SOLDIER", is 170 points of
  Cinzel at 13) over its stars, "3/5" and its role, in a column of 190 —
  then its five forms at 48 points, 8 apart. Four rows of 54 end at 234,
  clear of the resting list's 16-point foot fade (it starts at 243; on an
  iPhone 16 at 234); the fifth rests below the fold with the glass's
  chevron. The table **opens on the first family with a page waiting** (else
  the first with anything recorded), once per pantheon and face: a mock of
  the first frame from the real painting and cards, drawn at this geometry
  before handing over, showed a young save's Egypt opening on four rows of
  5★ shadows — Horus, Isis, Osiris, Ra — with every face it owned below the
  fold; filed rarest-first, it now opens on Sekhmet, Thoth and Anubis lit.
  The same mock left 80 points of bare glass at the table's right, which the
  role line and the looser spacing took up.
- **A page** (a tap on any form): three plates. The card (108, in its carved
  frame once recorded) with the form's full name, and the page's reward —
  the form's tile, the family's first's tile while it is owed, a line that
  says which is which, and CLAIM. The skills, read as the unit sheet reads
  them (`ProgressionService.resolve` of the form at level 1, awakened on an
  awakened page), with the leader skill as the crown's tile, and the
  family's lore. WHERE TO GET IT, read off the systems themselves: every
  banner whose pool draws the form (`SummonService.eligible(for:)`, so a
  Radiance or Umbra form lists the Light & Dark scroll alone) with the
  grade's rate and the mileage it costs there, a fusion recipe with its four
  corners, the Night Market's rare row, the opening gift while it is owed,
  the starter; an awakened page leads with the awakening and its essence
  bill. The strip steps through the family's five elements and its two
  faces. An unrecorded form's name, skills, lore and roads are all shown —
  the book is a hunting list.

Nothing on either screen is under the type floor (body 11, numbers 11.5,
Cinzel 13), no control in the strip truncates, and every list rests on whole
rows.

## Integration

The Collection strip's Codex glyph is the door. The lead wires the tour step
(`codex`, with `-tour-codex-page` and `-tour-codex-awakened` relaunches), a
door on More, and — optionally — the island badge; the exact Swift is in the
hand-off report.

## Not built, and what it would cost

- **A bespoke painting for the book** — a hall of records, shelves of
  painted tablets under a lamp — to stand behind the rail while the realm
  paintings stay behind the tables: one nano-banana-pro picture through
  Meshy, 9 credits, on the owner's word.
- **A painted Codex door** (`tab_codex`, a bound book with a gold clasp) for
  the Collection strip and More, in place of the SF closed book: one cell of
  the tab-icons sheet, about 6 credits.
- **The rate per form.** A road prints its grade's rate ("5★ at 3% a pull"),
  not the form's own share of it: the featured double weight and the 5★
  fifty-fifty make a per-form figure a small model of its own, and a wrong
  one would be worse than none.
