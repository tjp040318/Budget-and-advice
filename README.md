# Ground Stop

A 2D airline crisis-management game. You run a small carrier. Each run is a
30-day season, each day a real-time shift where flights depart, things break,
and one grounded aeroplane quietly ruins three others.

**Every decision makes you more profitable and more fragile.** Efficiency and
resilience are directly opposed. There are no correct answers.

Open `index.html`. That is the whole game — one file, no build step, no
dependencies, no network. Canvas 2D for everything, WebAudio for everything.

---

## Where this is up to

Stages **1–6** of the build order are done and playable end to end: the board,
the cascade, player decisions, crew duty hours, passenger connections and
reputation, and the full season with cash and bankruptcy.

Not built, deliberately: standing procedures (stage 7), airline types and the
rival (stage 8), the route map, the gate view, and everything in the
out-of-scope list. Stage 7 is next, once 1–6 have been played enough to know
whether they are actually fun — that judgement is yours, not mine.

## Playing it

Tap **BEGIN SEASON**. The day runs 06:00 to 24:00. Pause whenever you like: it
costs nothing and the game expects you to.

- **Tap any flight** for its aircraft, its crew's duty clock, and — the number
  that matters — the ground time between each leg of that tail's day.
- **Four levers**, each of which costs something: swap a tail, hold a departure,
  call a reserve crew, cancel the flight.
- **Two reserve crews a day.** The question is never whether one works. It is
  whether you will want it more at 19:00.
- The day ends with a wire report. The operational numbers are today's; the
  reputation story is **yesterday's**. You can fix the operation and still watch
  the story break tomorrow.

### The three things worth understanding

**Slack absorbs cascades.** A 40-minute delay vanishes into a 70-minute turn and
lands whole on a 30-minute one. The flight sheet shows the ground time before
every leg, colour-coded, because you cannot make that judgement without it.

**Ground slack and duty slack pull opposite ways.** Generous turns absorb delays
but eat the crew's 14-hour clock. Each of the six rotations sits somewhere
different on that line — N688GS has both, N118GS has all the ground slack and no
duty margin, N340GS is the reverse. Learn which is which; the schedule never
changes.

**Delays become cancellations.** A crew that cannot legally finish the trip does
not fly it, and a cancellation costs far more than a delay and hurts far more.
That conversion is the whole puzzle.

## The numbers

Tuned by simulation, not by feel — see below. As they stand:

| | |
|---|---|
| Break-even | ≈ 82% on time, at the starting reputation of 70 |
| A clean day at rep 70 | about +$15,000 |
| Reputation | drives load factor, which drives everything |
| Season | calm for 3 days, ramps to full by day 19, winter from day 20 |

Against 40 simulated seasons of competent play: 11 bankruptcies, **9 of them on
days 23–29**, survivors finishing around $250,000. Play passively and you are
gone by day 12. Defer every maintenance check and you go bankrupt half again as
often as someone who pays for them.

Everything tunable lives in the `CFG` block at the top of the script.

## Verifying changes

The simulation never touches the canvas or the audio context, so it runs
headless. `tools/simcheck.mjs` loads the same script the browser does, with no
`document` and no `window`, and plays whole seasons against four stand-in
players. It is a dev tool — the game itself still has no dependencies.

```bash
node tools/simcheck.mjs 40          # 40 seasons per policy: bankruptcies, on-time, cash
node tools/simcheck.mjs --arc competent 30   # median net, balance, delays day by day
node tools/simcheck.mjs --day seed1          # one day, minute by minute, every event
```

Change a number in `CFG` and re-run it. The arc view is the one that tells you
whether the season still has a shape.

## How it is put together

One `state` object of plain serializable objects; no classes, no framework.

| | |
|---|---|
| `recomputeChain` | the cascade. A flight's earliest departure is the latest of its schedule, its aircraft getting back and turned, its aircraft being repaired, and any hold. Recomputing the whole tail chain from that rule means delays propagate automatically and can never get out of step with the model. |
| `crewLegality` | duty and flight-time limits, checked at the moment of departure |
| `simTick` | one in-game minute |
| `setCell` / `tickCell` | the split-flap. Each character wheel spins *forward* through the alphabet to its new letter, so A→B is instant and Z→B takes a moment. Characters that did not change do not move. |
| `revealAt` | staggers when the board is *allowed* to show a change. The model is already correct; this is the only thing between the player and being handed the whole cascade at once. |

Chains are keyed on the aircraft rather than the rotation, which is what makes a
tail swap a single reassignment the cascade picks up for free.

### iOS

Built for portrait Safari under a Capacitor wrapper. Audio context is created on
the first tap, never on load. `requestAnimationFrame` only. Canvas is sized to
`devicePixelRatio`. Safe-area insets are read from a hidden probe element,
because CSS knows them and JS does not. Double-tap zoom, pull-to-refresh and
rubber-banding are all off. Every touch target is at least 44pt. The loop pauses
on `visibilitychange`, because phone calls happen mid-day.

Measured at a steady 60fps in headless Chromium at 3× device pixel ratio.

## Known rough edges

- Economy numbers are tuned against a simulated player, not a real one. Expect
  to move them once someone actually plays it.
- Audio is synthesized and unmixed; the split-flap click carries most of it.
- No tutorial. The title screen carries three sentences and that is all.
