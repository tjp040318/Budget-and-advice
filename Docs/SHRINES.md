# Hidden Shrines and summoning pieces

*2026-09-23. The Labyrinth's fifth room. Research, the options weighed, the
choice, and the numbers `python3 tools/balance.py --shrines` measured and
asserts. The code is `Pantheon/Core/PvE/ShrineService.swift` (the rules),
`Pantheon/App/GameStore+Shrines.swift` (the store's side and the one hook),
`Pantheon/UI/Campaign/ShrinesView.swift` (the room, the notice, the tiles)
and `PantheonTests/ShrineTests.swift` (the numbers pinned).*

## What it is, in one paragraph

A clear of a Labyrinth level or a Hall of Essence floor sometimes finds a
**hidden shrine**: a one-battle dungeon open for **an hour**, keyed to one
family FORM — a family and an element, never Radiance or Umbra. Every win
there pays **summoning pieces** of that form (three, and a fourth one win in
two) with a little of a Hall's loot; **20 pieces summon a 3★, 40 a 4★, 100 a
5★**, through the same reveal a scroll plays. Pieces never expire. A new
shrine is, half the time, a form you already hold pieces of — so a god you
have started comes back.

## Research (rule 2)

The network policy refused every page fetch (`summonerswar.fandom.com`,
`summonerswarskyarena.info`, `spokland`, Plarium's support site, Ellia's
wiki); the facts below are from the search engine's summaries of those
pages, and the places that are memory are marked.

### Summoners War's Secret Dungeons — the model

- **Where they come from.** "Hidden dungeons opened for exactly one hour,
  which can be found from the five Halls of Elements … as a random stage
  clear reward", and the monster is "a random monster from the table, of the
  same element as the hall" (the Fandom wiki, via search).
- **How often.** Not published by Com2uS. The community disagrees: one guide
  says "the higher the difficulty level you choose, the higher the chance";
  a wiki thread's theory is that B1 to B10 share one rate. Players report
  "a small chance".
- **The dungeon.** Ten stages, "each stage requiring players to defeat waves
  of one particular monster"; its awakened form appears from stage 3; "on
  the final stage, a boss version and two awakened versions".
- **The pieces.** Stage 1 pays no base piece and a 33% chance of one, stage 2
  none and 66%, stage 3 one sure, "up to four pieces per run on stage 10"
  with a chance of an extra. Mana (3,000–5,000) and the odd scroll beside
  them; **no runes** — the stamina spent there is stamina not spent on runes.
- **The prices.** 1★ 10 pieces, 2★ 20, **3★ 40, 4★ 50, 5★ 100**.
- **Sharing.** A friend who enters your secret dungeon earns you one extra
  piece, once per friend.
- **The pain** (memory, and the reason Raid built what it built below):
  pieces of a monster whose dungeon never opens again sit in the inventory
  for ever, a third of a monster at a time.

### Raid: Shadow Legends' fragments

- **100 fragments** summon the champion. A fragment event runs about **13
  days** and offers about **115 fragments without a tournament win**, so the
  event is designed to complete (search summaries of HellHades and Plarium).
- Fragments never expire; since patch 8.20 unspent ones can be traded in
  (the **Fragment Exchange**: 1 legendary fragment or 5 epic ones = 1 point,
  5 points = a chest) — the genre's admission that stranded pieces are a
  problem worth a system.

### Epic Seven and AFK Arena — a chosen hero over time

- Epic Seven: **200 summons (10,000 Mystic Medals)** pity a 5★ Moonlight hero,
  110 a 4★; Custom Mystic Summons over twelve weeks let a player name the hero
  (epic7x, via search). The day-one Selective Summon is already this game's
  `SelectorService`.
- AFK Arena: **60 soulstones** summon an elite hero; hero-specific stones are
  sold, generic ones earned daily (the AFK Arena wiki, via search).

### What this project already had

- **Mileage** (`MileageService`) is the road to a NAMED unit: 153 points for a
  5★ on a pantheon banner, 1.7 times its pity. Pieces must not undercut it.
- **The Light & Dark rule**: Radiance and Umbra come from the Light & Dark
  scroll alone (`Banner.excludingLightDark`). No shrine may offer one.
- The Labyrinth and the Halls are one-battle stages on the campaign's
  plumbing (`CampaignService.settle`), with auto-repeat, the sweep, the event
  calendar and the Night Market's one-hour clock.

## The options

| | What | For | Against |
|---|---|---|---|
| A | Summoners War literally: ten stages a shrine, pieces climbing with the stage | the genre's own screen | ten medallions and ten stages of one monster per shrine to tune; the stranded-pieces pain intact |
| B | Raid's fragment events: a scheduled event that pays enough fragments of one featured unit | completes by design | it is an event calendar, not a discovery; nothing is *hidden*; `EventCalendar` already owns the week |
| C | **Chosen.** Summoners War's discovery and hour, ONE battle a shrine at the found floor's difficulty, pieces priced by grade, and a **stock rule** — a new shrine is a form you hold pieces of half the time | the genre's surprise; one battle fits the Labyrinth's rooms; the stock rule answers the stranded-pieces pain at the source | a 5★ is slow (by design, below) |
| D | Raid's exchange for stranded pieces | a floor under bad luck | a second currency to explain; the stock rule makes most stocks completable, so it is deferred |

## The choice, and why each number

- **Found by** any VICTORIOUS clear of a Labyrinth level or a Hall floor:
  **0.5% for each point of energy the stage costs** — Hall B1 (6 energy) 3%,
  Labyrinth B7 3.5%, B10 4%, Hall B5 5%. Proportional to the energy so no
  floor is a cheaper shrine farm than another, while a deeper (dearer) floor
  finds one more often per clear — Summoners War's "higher difficulty, higher
  chance". A shrine's own wins never find another.
- **Open 60 minutes**, Summoners War's exact hour and the Night Market's
  clock. **Three at most**; a clear that would find a fourth finds nothing,
  so a shrine is never taken away. An expired shrine vanishes; a repeat
  session begun inside the hour runs to its count.
- **The form**: the summon pool's fire, water and wind forms, 3★ to 5★ — 96,
  132 and 63 forms — through `Banner.excludingLightDark`, so never Radiance or
  Umbra, and never a fusion prize (the pool never held them). The Hall of
  Embers, Tides and Gales find their own element (Summoners War's rule); the
  Labyrinth and the Halls of Radiance and Shadows find any of the three.
- **The grade** by how deep the clear was (the found floor's relic grade):

  | found on | 3★ | 4★ | 5★ |
  |---|---|---|---|
  | Labyrinth B1–3, Hall B1 | 75% | 24% | 1% |
  | Labyrinth B4–6, Hall B2 | 63% | 35% | 2% |
  | Labyrinth B7–9, Hall B3–5 | 53% | 43% | 4% |
  | Labyrinth B10 | 44% | 51% | 5% |

- **The stock rule**: 50% of the time a new shrine is one of the forms you
  hold pieces of (that grade, the elements the room allows, weighted by the
  pieces held); otherwise a form of the pool at random.
- **The battle**: three waves of the form, Summoners War's waves of one
  monster — three plain, then one awakened between two, then the form as the
  **boss ×1.6** at the higher of the floor's grade and its natural one (the
  Labyrinth boss's rule) with two awakened at its side (awakened only when the
  family has an awakening). The level, grade, multiplier, energy and
  recommended power are the found floor's, so the team that found it can take
  it. It stands in the form's pantheon's place: the Hall of Two Truths, the
  Gate of Olympus, the Roots of Yggdrasil, the Forum, the Peach Garden.
- **A win pays 3 pieces and a 4th half the time** (3.5), the found floor's
  drachma and experience, the form's element's **Mid essence 30%** and an
  **Unknown Scroll 10%** — and **no relic**, as a secret dungeon pays no runes:
  the energy spent there is energy not spent on the relic hunt.
- **A summon takes 20 pieces for a 3★, 40 for a 4★, 100 for a 5★.** The 3★ is
  this game's fodder tier (an Unknown Scroll is 5,000 drachma), so half
  Summoners War's 40; the 4★ is "one shrine's hour" — 11.4 wins, 80 energy at
  B7, inside the 150 an hour holds at level 30; the 5★ is the genre's 100, more
  than any one hour (229 energy at B10 against an endgame hour's 190), so a
  god needs his shrine to come back.
- **The summon** is the scroll's own reveal (`SummonRevealView`), its circle
  lit in the form's element; a duplicate is a skill-up, as every summon is; it
  counts for the missions and the feats; it pays no mileage (no banner).

## Measured (`balance.py --shrines`)

Normal play: 288 energy a day, three quarters of it in the Labyrinth and the
Halls, every shrine farmed at once with an hour's energy (the bar and twelve
regenerated), a 3★ or 4★ until its unit is summoned, a 5★ until the hour runs
out. Sixty seeded players a profile.

| profile | a clear | shrines a day | 3★ a week | 4★ a week | 5★ a week | a 5★ shrine | the first 5★ |
|---|---|---|---|---|---|---|---|
| a new account, Hall B1 | 3.0% | 0.93 | 4.16 | 1.17 | 0.02 | every 109 d | 368 d |
| **normal play, Labyrinth B7** | 3.5% | **0.87** | 2.66 | **1.79** | 0.11 | every 26 d | **114 d** |
| normal play, Hall B3 | 4.0% | 0.87 | 2.58 | 1.76 | 0.08 | every 26 d | 120 d |
| the endgame, Labyrinth B10 | 4.0% | 0.87 | 2.24 | 2.03 | 0.11 | every 23 d | 89 d |

Against the scrolls, a unit of each grade at B7:

| grade | pieces | wins | energy | a random one by scroll | a NAMED one by mileage |
|---|---|---|---|---|---|
| 3★ | 20 | 5.7 | 40 | 17 divinity (an Unknown Scroll) | 2,100 |
| 4★ | 40 | 11.4 | 80 | 497 (a pantheon banner) | 6,100 |
| 5★ | 100 | 28.6 | 200 | 2,947 (a pantheon banner) | 15,300 |

Pieces are cheap in ENERGY and dear in TIME: the form is not chosen and its
shrine is rare, so the honest comparison is days. The free pulls come to 2.01
a day on a pantheon banner (the missions, their bonus, the login week): a
named 5★ by mileage is **76 days**, a random 5★ from the same pulls every 15.
A 5★ by pieces is the first in **114 days** at B7 (89 at B10), then one every
66 — a supplement to the 5★s the pulls bring, never the road to one. The
shrines take 18% of normal play's dungeon energy.

**Asserted** (the report fails otherwise): 0.6–1.2 shrines a day of normal
play; every grade table sums to one, 5★ at most 5%, 3★ and 4★ at least 95%;
no Radiance, Umbra or fusion prize in the pool; a 3★ by pieces dearer than an
Unknown Scroll (the shrine is never the fodder farm); a 4★ inside one hour at
level 30; a 5★ outside one hour even at B10; the first 5★ by pieces later
than a named one by mileage at EVERY profile; the steady 5★ rate under half
the free pulls'; the shrines under a quarter of the dungeon energy.

To make 5★ pieces faster, raise the 5★ column of the grade table (Swift,
`balance.py` and `ShrineTests` together) and read `--shrines`: it says when
pieces start to undercut mileage.

## How it is wired

- **Save**: `Player.shrines` (the open shrines) and `Player.shrinePieces`
  (pieces by blueprint id), both Optional in one marked block.
- **The hook**: one line in `GameStore.finishCampaignBattle` —
  `noteShrines(after:result:)` — rolls a Labyrinth or Hall win's chance and
  pays a shrine win's pieces. A shrine's stage is an ordinary `Stage` in
  chapter `shrine` (id `shrine_<form>`), so `startCampaignBattle`, the battle,
  its spoils and **auto-repeat** run it unchanged.
- **The sweep does not call it yet.** `GameStore.sweep` settles each run in
  its own loop; one line there (`ShrineService.noteClear(stage:result:player:rng:)`
  after each settle, inside the loop's `update`) would let a swept run find a
  shrine as a fought one does — the house rule that the two never pay
  differently. Left for the owner's word because the task allowed one edit
  to `GameStore.swift`.
- **The room**: the Labyrinth's fifth wing (Dungeons · Halls · Tower · Titans ·
  Shrines): a rail of the open shrines with their clocks and the pieces held,
  and a room with the form's face, its pieces as a meter with the next win's
  ghost, what a win pays, and the deck — Fight, Auto ×N (the wins the unit
  still needs, as far as the energy goes) and Summon once enough are held.
  The Labyrinth strip's subtitles were shortened so five segments fit an
  iPhone 16 Pro's strip with a veteran's wallet (measured with the bundled
  fonts: a 126-point title budget at worst).
- **The notice**: a dungeon room that comes back from a fight (or a sweep)
  with a new shrine open shows `ShrineNoticeCard` — the form's face, its
  clock, and "Enter the shrine", which opens the shrine room over the room.

## Not done, and what it would cost

- **A painted piece.** The pieces tile is the form's card in a socket with a
  puzzle-piece seal. A painted "summoning shard" icon (`item_pieces`, one cell
  of a Meshy sheet, 6 credits) and a painted **shrine** backdrop per pantheon
  (five Gemini paintings, about 70 cents, on the owner's word) would give the
  room its own look; it borrows the pantheons' places today.
- **The island**: the Labyrinth's bubble could show an open shrine's clock
  (`IslandView`, not this change's file).
- **Sharing** (Summoners War's friend piece) through the Allies layer.
- **The exchange** for stranded pieces (option D), if the stock rule is not
  enough in play.
