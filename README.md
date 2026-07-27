# Debt payoff scheduling engine — v1 prototype

One self-contained file: `index.html`. No build step, no dependencies, no network calls.
Open it in a browser and it runs; the test suite executes before the first paint and
reports into the UI.

All data is mocked. There are no bank connections, no auth, no money movement.

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

The engine never learns where data came from. Everything enters through a `DataSource`:

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

`MockDataSource` ships today. `PlaidDataSource` (balances, transactions, deposit history) and
`MethodDataSource` (liability detail, payment execution) implement the same shape with zero
engine changes. Dates are integer day numbers throughout; calendars and formatting live only
at the edges.

## Tests

`runTests()` runs on load and renders into the app — a green strip at the top when passing, a
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

## Personas

| | |
|---|---|
| **Dana Reyes** | Biweekly W-2, one card, one nearly-paid-off car, rent. Baseline correctness. |
| **Priya Nandakumar** | Deposits swinging $2.4k–$4.4k month to month. Proves the income-floor logic. |
| **Alex & Sam Ortega** | Two offset pay schedules, three checking accounts, shared and individual debts. Proves multi-account handling. |

In each persona the highest-APR debt is deliberately *not* the smallest balance, and not the
highest-utilization card, so avalanche, snowball and statement-close timing produce genuinely
different plans instead of collapsing into the same move.

## Out of scope for v1

Real bank connections, auth, any backend, actual money movement, LLM calls, investing,
anything requiring a license.
