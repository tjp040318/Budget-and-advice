# The Draft Arena

*2026-09-23. Summoners War's World Arena draft, played offline against a
demigod the game plays. Built in `Pantheon/Core/PvP/DraftService.swift`
(the rules), `Pantheon/App/GameStore+Draft.swift` (the save),
`Pantheon/UI/Arena/DraftView.swift`, `DraftBoardModel.swift` and
`DraftBoardParts.swift` (the board), `BattleContext.draft` (the fight),
`Player.draft` (the record) and `PantheonTests/DraftTests.swift` (every number
below, pinned).*

## 1. The research

### What the genre does

**Summoners War: World Arena (RTA).** Both players draft **five monsters each
from their own boxes**, taking turns in the **1-2-2-2-2-1** snake (the first
picker takes one, then two each way, then the last one). Then each player
**bans one of the other's five**, leaving four a side, and **then both choose
a leader** from the four they kept. Each decision has a 30-second clock.
Everyone starts a season at **Challenger ★★ with 1,000 victory points**; from
Challenger to Conqueror a player climbs by **victory medals and is never
demoted below a grade already reached**, and from Punisher to Legend it is
victory points and rank. A season lasts **about three months** and ends with
rewards by grade and rank; **every win pays 2–5 medals by grade**, spent in
the World Arena shop (scrolls among them). At a season's end the points are
**reset according to the grade reached**.

**Epic Seven: World Arena.** The same **1-2-2-2-2-1** order of five, the
first pick **assigned at random**, then **each player bans one of the other's
heroes** (the post-ban). Above that sit **pre-bans**: each player strikes
**two heroes from the whole pool** before the draft, so neither side can pick
them. One draft tool reports that **the third pick overall cannot be
post-banned** (a protected pick). Rewards come **every week by rank**, in the
season's glory crests: Bronze 150 … Master 350–430 … Legend 800–1,200 — a
ladder spanning five to eight times from the bottom rank to the top.

### Sources, and what came from memory

`WebFetch` is refused by this environment's egress policy for every site
tried (the Summoners War wiki, SWLens, mobi.gg, Wikipedia, e7arena, the E7
RTA bot), so everything above came through `WebSearch` summaries:

- SW's order of events — five each, one ban each of the other's five, then
  the leader from the four; the 30-second decisions — the Summoners War Sky
  Arena wiki's *World Arena* page and mobi.gg's *RTA: how it works and
  rewards*, as summarised.
- SW's 1,000 points at Challenger ★★, the medals-then-points climb with no
  demotion in the lower grades, the three-month season, the 2–5 medals per
  win and the grade-based reset — the same wiki's summary.
- The **1-2-2-2-2-1** order, E7's random first pick, the post-ban and the
  protected third pick — e7arena.com's *Drafting 101* and the Epic7BPHelper
  project, as summarised.
- E7's pre-ban of two heroes a player — the same summaries (the rank at which
  pre-bans open was not in them).
- E7's weekly glory-crest ladder — epic7x.com's *Glory Crest* page summary.
- **From memory, not confirmed:** that SW's first pick is decided at random
  (the searches did not say); SW's exact point thresholds per grade (the
  wiki's table did not come through); the World Arena shop's prices. None of
  these is load-bearing: the thresholds and prices here are this game's own,
  set against its own arena (§5).

## 2. The options

| | What it is | For | Against |
|---|---|---|---|
| **A** | SW's draft as it is: 1-2-2-2-2-1 from each side's box, each bans one of the other's five, leaders from the four, 4v4 | The genre's own shape, the one the owner plays; four is our arena's team (`ArenaService.teamSize`) | — |
| **B** | E7's: A plus two pre-bans a side from the whole pool, and a protected pick | Answers a live meta of must-picks | A pre-ban works because both players draw from one hero list. Here each side drafts from its own box and the rival's is generated: a player's pre-ban would strike units he cannot see, and the rival's would strike, from a young box of eight or ten, the only five it can field. There is no meta to answer offline. |
| **C** | A lighter draft: pick four each, no bans | Quicker | Loses the genre's two best decisions — the counter-pick in the middle turns and the strike after the picks |
| **D** | A 30-second clock per decision | Genre-true pressure | Offline nobody is waiting; a clock that picks for a demigod still learning the mode is a punishment without an opponent. Easy to add later (`DraftBoardModel` already paces the rival). |

**The choice: A.** A coin flip for the first pick, shown (a drachma spins on
the board). No pre-bans, no protected pick, no clock — each is written above
with why, and each can be added without touching the rest.

The **bans are simultaneous**, as the genre's are: the rival's strike is
**sealed the moment the tenth pick lands**, computed from the ten picks
alone, before the player chooses his (`DraftSession.pick` seals it;
`DraftTests.testTheRivalsStrikeIsSealedBeforeThePlayers` holds it still
whichever of the rival's five the player strikes). **Two units of the same
monster cannot stand in one five** (SW's rule; two elements of one family are
two monsters).

## 3. The rival

**Its box** is fourteen different monsters from the summon pool, less
anything the battle would stage as a boss (a primordial, or three metres
tall), at most **two light or dark forms** (the Light & Dark scroll's
premium), with **two healers and two tanks first** so it can answer a need.

**Its strength.** `ArenaService` builds a challenger from the player's arena
POINTS: one strength `n` sets the level (15 + 45n), the grade and the relic
grade (3 + 3n), the relic level (15n), the skill levels (5n), the awakening
(past 0.4) and the relic sets (Fury and Ruin for an attacker, Bulwark and
Aegis else). The draft uses **that recipe** (`DraftService.rivalUnit`), but
cannot key it to a rating — every demigod starts at 1,000 whatever his box —
so it finds, by bisection, **the `n` whose box's best five match the player's
own best five**, times the crown's lean: **0.8, 0.9, 1.0, 1.1, 1.2** from the
first crown to the last. Below 0 the recipe's level keeps falling (level 1 at
−0.31), so a young box meets a rival its own size. Each unit rolls on its own
seeded stream, so the same seed gives the same box at every strength and only
its numbers move.

**Its name and rating.** A Greek name (not the arena's challengers'), and the
player's rating ±50.

**The rival waits.** The draft's seed is the save's lineage, the bouts fought
and the week (`DraftService.sessionSeed`): leaving the board and coming back
finds the same coin and the same box, until a bout is fought. Leaving before
the fight costs nothing and rerolls nothing.

## 4. The rival's mind

A readable heuristic, and the board says it out loud ("Theron takes Sekhmet:
Ember beats your Perseus."):

- **A pick** is worth its power against the strongest it could still take,
  **+0.30** for each of the other side's picks its element beats, **−0.18**
  for each that beats it, **+0.45** for the first healer and **+0.35** for
  the first tank once the side has a pick, **−0.25** for a third of one role,
  **+0.10** for a leader skill that would reach three of the side.
- **A strike** takes the other side's biggest threat: power, **+0.25** for
  each of the striking side's picks it beats, **+0.20** for an only healer.
- **A leader** is the arena leader skill that reaches the most of the four at
  the largest bonus, else the strongest.

The same sums light the player's best strike for the tour's frame and read
every tapped unit against the rival's picks ("Tank · beats Sekhmet · beaten
by Zeus").

## 5. The fight, the ladder and the purse

**The fight** is `BattleContext.draft(DraftBout)`: the four each side kept,
leaders first, through `BattleEngine` in the arena's mode (`.arenaOffense`:
leader skills that work in the arena, and both lineups' resonance), on the
Arena of Souls. It spends no attack and no energy. Its settle is
`GameStore.finishDraftBout`, never `.arena`'s. A bout counts as an arena
battle for the daily mission and the arena feats (`QuestService` has no draft
event, and a draft bout is a fight in the arena).

**The rating** is Elo: start **1,000** (SW's), **K 32** (±16 at even ratings),
**K 48 for the first ten bouts** (the placement). **Five crowns** of the
Panhellenic games: **Nemean** (wild celery) 0+, **Isthmian** (pine) 1,100+,
**Pythian** (laurel) 1,250+, **Olympic** (olive) 1,450+, and the
**Periodonikes** — the victor of all four — 1,700+. **A loss never takes the
rating under its crown's floor** (the arena's rule, and SW's lower grades').
**An Olympiad is four weeks**: at its turn the rating falls **halfway back to
1,000** (1,700 → 1,350), SW's grade-based reset in one line; the best rating
is kept for life.

**The purse.** Every bout moves the rating; **the first five of a day pay
laurels**: a win **15, 20, 25, 30, 35** by crown, a loss **5**. Thursday's
Double Laurels doubles them, as it does the arena's. **A week of three bouts
or more leaves a chest** for the crown it closed on, claimed on the board or
at the arena's door:

| Crown | Laurels | Scrolls | Scrolls at the exchange |
|---|---|---|---|
| Nemean | 60 | Mystical ×1 | 112 |
| Isthmian | 100 | Pantheon ×1 | 150 |
| Pythian | 150 | Pantheon ×1, Mystical ×1 | 262 |
| Olympic | 220 | Pantheon ×2 | 300 |
| Periodonikes | 300 | Pantheon ×1, Light & Dark ×1 | 400 |

The exchange prices are the bazaar's own (a Pantheon Scroll 150 laurels, a
Light & Dark 250); a Mystical Scroll has no laurel price and is valued at its
75 divinity at the exchange's 150-for-100.

**Balanced against the arena.** The arena pays **12 + 6 × tier** a win and
**3** a loss, ten attacks stored and one back every thirty minutes. A week at
a **60% win rate** — the draft's five paid bouts a day with its chest,
against ten arena attacks a day at the peer tier:

| Crown / arena tier | Draft week, laurels | + scrolls at the exchange | Arena week | Draft laurels / arena |
|---|---|---|---|---|
| Nemean / Initiate | 445 | 557 | 588 | 76% |
| Isthmian / Acolyte | 590 | 740 | 840 | 70% |
| Pythian / Oracle | 745 | 1,007 | 1,092 | 68% |
| Olympic / Champion | 920 | 1,220 | 1,344 | 68% |
| Periodonikes / Ascendant | 1,105 | 1,505 | 1,596 | 69% |

The rule the tests hold (`testTheDraftPaysLessThanTheArena`): at every crown
the draft's laurels stay **under 80%** of the arena's week, and **with its
scrolls priced at the exchange it pays no more than the arena's week**. A
draft bout is two or three attacks' time, so an evening of drafting pays less
per minute than an evening of arena and pays its difference in scrolls, once
a week. The draft is a mode of skill; the arena stays the laurel farm.

## 6. The save

**One field:** `Player.draft: DraftRecord?` (nil until the board first opens),
in its own marked block. `DraftRecord`: `rating`, `highestRating`, `wins`,
`losses`, `bouts`, `dayKey` and `paidToday`, `week` and `boutsThisWeek`,
`chestTier` and `chestWeek`. Every field has a default and this version
writes them all; **a field added after this one must be Optional**.
`DraftService.rollOver` brings it up to date: a new day refills the paid
bouts, a new week banks the finished week's chest (at most one waits; a
better crown replaces a worse one), a new Olympiad pulls the rating back.

## 7. The board

A PLACE, by phase B's rule: the Arena of Souls full bleed, dark glass where
the words go. An iPhone 16 Pro gives it 750 × 329 points under the strip
(`DraftBoardMetrics`; a narrow class under 700 for an SE):

- **The strip:** back, DRAFT ARENA, the week's chest when one waits, the
  day's paid bouts ("5/5 paid"), and the crown's well (crest, name in its
  colour, rating, and the ? with the ladder).
- **The two fives facing each other:** the player's down the left in gold,
  faces at the outer edge; the rival's mirrored down the right in crimson.
  Each place is a face with the name and one line (the role's glyph and the
  power, or BANNED, LEADER, CHOSEN); an empty place shows its pick's number;
  the places on the clock breathe in their side's colour; a strike is a red X.
- **The pick-order track** over the middle: ten numbered pips in the
  1-2-2-2-2-1 order with a gap between turns, made ones lit, a chosen but not
  locked pick half lit, the turn on the clock breathing, and the phase's words
  under them ("YOUR TURN · CHOOSE TWO", "THERON IS CHOOSING").
- **The middle panel, by phase:** the coin; the player's box as a grid
  (`RestingList`, whole rows) with the five element tiles and four role tiles
  (attacker, tank — a defender or a vanguard —, support, controller) and a
  Lock in bar that reads the tapped unit against the rival's picks, or the
  rival's last decision in its words; the rival's five to strike, each with
  why it matters ("Beats 2 of yours", "Their healer"); the four to crown with
  the leader's words, the rival's crown, the two fours' power and FIGHT; after
  the bout, the crown, the rating and its swing, the climb to the next crown,
  the laurels, Leave and Draft again.
- **The door:** a Draft Arena card above the challengers in the Arena lobby —
  the crest, the crown and rating, "Pick five, strike one" (or "Last week's
  chest waits"), and a gold DRAFT plate with the paid bouts under it. It sits
  above the list, so the lobby shows two challengers and the third's top in
  the fade where it showed three. The challengers' empty state ("Finding
  challengers", about 206 points as the house `EmptyState`) no longer fit
  under the door on any phone (about 165 points are left on a 16 Pro, 138 on
  a mini), so the same words stand in one row about 85 points tall
  (`ArenaView.quietChallengers`).

Nothing is truncated: every label takes its own width (`fixedSize`) or wraps
to two lines; the type floors hold (11 body, 11.5 figures, 13 carved).

## 8. Not built, and what it would cost

- **Pre-bans, a protected pick, a pick clock** — §2 says why not; each is a
  small change in `DraftSession` and `DraftBoardModel`.
- **A real opponent** — the rival is local. `SocialBackend` could carry a
  defence box the way the guild war carries a defence team.
- **Painted crests** — `DraftCrest` draws `draft_crest_<name>` when it is in
  the bundle: five crowns (celery, pine, laurel, olive, the four together) as
  one Meshy picture sheet, about 9 credits, on the owner's word. Until then
  the arena's drawn crest (the painted laurel wreath and a disc) stands in.
- **A season chest** at the Olympiad's turn — the weekly chest carries the
  rewards for now.
- **`tools/balance.py` does not mirror these numbers yet** (it was being
  edited by another agent the day this was built). The tests pin them; a
  `--draft` table would print §5's purse from `DraftService`'s constants.

## 9. The CI tour

`DraftView(tourStage:)` freezes the board mid-draft on a fixed seed
(`DraftService.scriptedSession`): **`.bans`** — ten picks made, the player's
best strike marked with the red X and STRIKE live; **`.picks`** — two picks
each, the player's turn open with the heuristic's own pick chosen and LOCK IN
live; **`.leaders`** — both strikes landed, both crowns, FIGHT live.
