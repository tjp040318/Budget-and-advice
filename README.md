# Debt payoff scheduler

One self-contained file: `index.html`. No build step, no dependencies, no network calls.
Open it in a browser and it runs.

## Using it on your own money

Open `index.html`, go to **Your money**, and either start from an empty plan or copy one of
the three worked examples and edit it. You will need your checking balance, each debt with
its balance / APR / minimum / due day, your income and when it lands, and roughly what you
spend in a normal month. Ten minutes, once.

Everything you type is saved to that browser's `localStorage` and never leaves your machine.
There is no server, no account, and nothing to sign up for. That also means:

- **Clearing site data wipes it.** Use *Export a backup* — it writes a JSON file you can load
  again later or on another machine.
- **It is per browser and per machine.** The backup file is how you move between them.
- **Private browsing may block saving.** The app detects that and says so rather than
  silently losing your work.

From **This week** you can push the whole schedule to your calendar as an `.ics` file — every
payment as an all-day event with a reminder the morning it is due and the reason attached, so
the plan acts on you instead of sitting in a tab. There is also a CSV of the schedule and a
print layout.

### What it still is not

It does not connect to your bank and it does not move money. Both need things a single HTML
file cannot have: Plaid and Method require merchant accounts, API keys and a backend to hold
them, and moving money requires licensing. What the file *does* have is the boundary those
would plug into — see **Adapter boundary** below. Balances are whatever you last typed, so
the app tracks how stale they are and nags you when they drift.

Treat the output as a well-argued plan, not financial advice. Every number is derived from
what you entered.

---

## The problem this is actually solving

Ranking debts by APR is the easy half. The hard half is that income arrives on specific
dates, obligations are due on other dates, credit card statements close on a third set of
dates, and the checking balance moves continuously between all of them. The question is not
"which debt is highest APR" — it is "given the slack this month, on which calendar day does
each dollar move so that nothing overdrafts, nothing is late, and interest is minimised."

`buildPlan(dataSource, overrides)` is a deterministic solver for that. No model calls
anywhere, including in the explanation strings.

## Design direction

**Palette — cool ledger paper.** Ground `#EEF2F3`, surfaces white, ink `#0F2229` (deep
slate, never black). Deep teal `#0E5A61` carries structure and action. Slate blue `#3C5C8C`
is reserved exclusively for credit-score timing moves, so "we did something clever" never
reads the same as "here is a bill." Moss `#3F6B4A` means covered.

Red `#A32118` appears in exactly one situation: something is actually going wrong — a failing
check, a breached floor, a late payment. Never for debt balances, never for outgoing money.
The buffer-floor line on the chart is grey while the plan respects it, and only turns red if
it is breached.

Deliberately avoided: cream/serif/terracotta, dark-with-one-acid-accent, and
big-number-with-small-label hero cards.

**Type.** Nothing external loads, so the pairing is structural rather than decorative: a
humanist system sans for prose, monospace with `tabular-nums` for every figure. Columns line
up the way a ledger does. Layout is dated rows, not cards.

## How the engine works

A single deterministic forward pass over the horizon, one day at a time: income lands,
background spending clears, interest accrues, obligations get paid, spare cash is allocated,
end-of-day balances are recorded. Three runs make a plan:

1. **plan** — commits against the conservative income floor; this is the schedule shown.
2. **replay** — takes that schedule as fixed, runs it against nominal income, and sweeps
   anything above the floor at the target debt.
3. **projection** — the same engine over 15 years, for payoff dates and lifetime interest.
   Payoff dates come from the same code path as the schedule, not separate closed-form math.

### Hard constraints

1. Household checking never drops below `bufferFloor` on any day, and no individual checking
   account ever goes below zero.
2. Every minimum is scheduled on or before its due date, every period.
3. No payment is scheduled from money that has not arrived.

### The lookahead is a running minimum, not a net total

The single most important detail in the solver. Available cash is computed by walking the
next 45 days *in order* and taking the worst point along the way — not by netting income
against obligations over the window. A paycheck arriving on the 15th cannot pay rent due on
the 1st, even though the month nets out fine. Netting was the first implementation and it
overdrafted every persona.

### Statement-close timing, and when it is declined

When `optimizeForCreditScore` is on, a card payment is pulled ahead of the statement close
rather than left at the due date. Same dollars, lower reported utilization.

The engine refuses the move in three cases, each of which is a way a naive implementation
quietly makes things worse:

- **The card is under ~30% utilization.** The reported number is already in a range where
  moving it does almost nothing to a score.
- **The card is already the surplus target.** Every spare dollar is being sent there on the
  day it lands, which is ahead of the close anyway. Pulling the minimum forward only reserves
  the same money for a later date — it costs a day or two of interest and reports an
  identical balance. Measured on the steady persona, doing it blindly made the reported
  balance $1.72 *worse*.
- **Another card with worse utilization has a close in the same window.** Utilization is
  reported per card and the worst card dominates, so the two cannot both have first claim on
  the cash. The worse card wins.

Because of this, the feature is correctly invisible on Dana's default screen, and the UI says
so in plain language rather than pretending. It is live on Priya and on the Ortegas.

### Irregular income

Variable streams are planned against the 25th percentile of the trailing 12 deposits, not the
mean. Every committed payment is sized against that floor, so a light month changes nothing.
The difference between the floor and what actually lands becomes a *conditional sweep* — an
extra payment at the target debt that fires only if that deposit clears the floor.

For Priya this is a ~$1,000/month gap between what the plan promises and what it expects.

### Multi-account households

Obligations are drafted from a named account. The engine moves money between checking
accounts itself when an account is thin, and tops accounts up on payday for the stretch ahead
rather than shuffling cash a bill at a time. Same-day transfers between the same pair of
accounts are merged into one row, because that is what the person actually does.

If required outflow would still breach the floor, the plan draws from savings — explicitly,
with a sentence, and it repays savings before any further extra goes at the debt.

## Documented extensions to the brief's data model

Three additions, each needed for the projection to be honest:

- **`Expense`** — recurring living costs (groceries, childcare, insurance) with weekly or
  monthly cadence. Without them every persona appears to have thousands a month of slack and
  the payoff dates are fiction. These are background outflow the engine reserves against but
  never "decides."
- **`Liability.accountId`** — which account an obligation is drafted from. Required for
  honest multi-account handling; defaults to the primary checking account.
- **`Settings.extraMonthly`** — what-if input; behaves as certain income.

`bufferFloor` is interpreted as a household total across checking accounts, with a hard zero
on each individual account.

## Adapter boundary

The engine never learns where data came from. Everything enters through a `DataSource`.
`makeDataSource(profile)` is the single implementation; the demo personas and your own
saved data are the same function with different inputs, which is what keeps the boundary
honest rather than theoretical:

```
interface DataSource {
  getProfile()                 -> { id, name, tagline, note }
  getAccounts()                -> Account[]
  getLiabilities()             -> Liability[]
  getExpenses()                -> Expense[]
  getIncomeEvents(startDn, n)  -> IncomeEvent[]
  getDepositHistory(streamId)  -> number[]
  getSettings()                -> Settings
}
```

`MockDataSource` (demo personas) and `LocalDataSource` (your saved profile) ship today.
`PlaidDataSource` (balances, transactions, deposit history) and `MethodDataSource` (liability
detail, payment execution) implement the same shape with zero engine changes. Dates are
integer day numbers throughout; calendars and formatting live only at the edges.

`normalizeProfile()` is the one place that guarantees ranges — day-of-month clamped to 1–31,
APR to 0–1, orphaned account references repointed. Hand-entered data can therefore never
reach the solver malformed, and the editor never has to fight someone mid-keystroke.
`validateProfile()` sits alongside it and reports what is wrong in plain language: a minimum
smaller than the monthly interest, outgoings above income, a card with no statement close
day. Errors that make a plan impossible are stated as arithmetic, not hidden behind a
schedule that cannot work.

## Tests

Two layers. `runTests()` covers the engine and runs on load, rendering into the app — a green strip at the top when passing, a
loud red banner when not. 33 assertions across the three personas, all properties of the plan
rather than golden values, so they keep meaning something after the numbers change:

- the buffer floor holds every day, in both the conservative and expected projections, and no
  account overdrafts
- no minimum is ever late or short
- total outflow never exceeds starting balance plus committed inflow
- avalanche sends strictly more to the highest-APR debt than snowball over 90 days
- statement-close timing never raises peak reported utilization, and strictly lowers it
  wherever the move is available
- every payment carries a dated, dollar-specific generated sentence
- two runs of identical inputs produce an identical plan
- variable income is committed at the 25th percentile and below the trailing mean
- **constraints hold from 18 different start dates** spanning month ends, short months and
  every weekday — this one caught several genuine bugs

A separate browser-driven suite (`e2e.js`, run during development, not shipped in the file)
covers the app around it: first-run onboarding, starting blank, copying a template, editing a
field and seeing the payoff recompute, persistence across reload, adding and removing rows,
fields appearing and disappearing as a debt's type changes, ICS/CSV/JSON export shape, an
impossible plan being flagged rather than silently scheduled, and demo profiles staying
read-only. 20 checks, all green.

## Personas

| | |
|---|---|
| **Dana Reyes** | Biweekly W-2, one card, one nearly-paid-off car, rent. Baseline correctness. |
| **Priya Nandakumar** | Deposits swinging $2.4k–$4.4k month to month. Proves the income-floor logic. |
| **Alex & Sam Ortega** | Two offset pay schedules, three checking accounts, shared and individual debts. Proves multi-account handling. |

In each persona the highest-APR debt is deliberately *not* the smallest balance, and not the
highest-utilization card, so avalanche, snowball and statement-close timing produce genuinely
different plans instead of collapsing into the same move.

## Views

| | |
|---|---|
| **This week** | What moves, when, from where, and why. The default screen. |
| **Timeline** | 90 days of income, payments and statement closes, with the projected balance line underneath. |
| **Debts** | Every balance with APR, payoff date and interest still to come. |
| **What if** | Sliders for extra monthly and buffer floor, plus strategy — recomputed live by the same engine. |
| **Your money** | Everything the plan is built from. Editable, saved locally. |
| **Engine checks** | The test suite, always one click away. |

## Out of scope

Real bank connections, auth, any backend, actual money movement, LLM calls, investing,
anything requiring a license.
