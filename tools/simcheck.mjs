// Headless balance harness. Dev-only: the game itself is index.html and has no
// build step and no dependencies. This loads the same script the browser does,
// with no document and no window, and runs whole seasons to check that the
// simulation terminates, the numbers stay sane, and bankruptcies land where
// they are supposed to.
//
//   node tools/simcheck.mjs            30 seeds, three policies
//   node tools/simcheck.mjs --day 1    trace one day, minute by minute

import { readFileSync } from "node:fs";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.error("no <script> block in index.html"); process.exit(1); }
new Function(m[1])();
const GS = globalThis.GS;
if (!GS) { console.error("game did not expose GS"); process.exit(1); }

const CFG = GS.CFG;

// --- Policies ---------------------------------------------------------------
// Each is a { onTick, onMaintenance } pair standing in for a player.

const POLICIES = {
  // Never touches a control. The floor: what happens if you just watch.
  passive: {
    onTick() {},
    onMaintenance: () => "defer"
  },
  // Pays for every check the moment it is due.
  diligent: {
    onTick() {},
    onMaintenance: () => "authorize"
  },
  // Competent, but never pays for a check. The intended trap: free today, and
  // an aeroplane that breaks twice as often in the week you can least afford it.
  greedy: {
    onTick(st) { POLICIES.competent.onTick(st); },
    onMaintenance: () => "defer"
  },
  // Roughly what an attentive player does: kill a flight the crew can no longer
  // legally fly, spend reserves on the ones with the most people on board.
  competent: {
    onTick(st) {
      for (const f of st.flights) {
        if (!f.crewBlocked) continue;
        if (f.status === "cancelled" || f.status === "arrived" || f.status === "departed") continue;
        if (st.reservesLeft > 0 && f.paxCount >= 100) {
          if (GS.callReserve(st, f)) continue;
        }
        // Cancel early rather than late: it frees the aircraft downstream.
        if (st.clock > f.plannedDep + 20) GS.cancelFlight(st, f, "policy");
      }
    },
    onMaintenance: (st, ac) => (st.cash > 90000 ? "authorize" : "defer")
  }
};

function runSeason(seed, policy) {
  GS.newRun(seed);
  const st = GS.state;
  st.phase = "day";
  let guard = 0;

  while (st.phase !== "over" && guard++ < 200000) {
    if (st.phase === "day") {
      GS.simTick(st);
      if (st.clock % 5 === 0) policy.onTick(st);
    } else if (st.phase === "report") {
      st.phase = GS.maintenanceDueList(st).some(a => !a.decided) ? "maintenance" : "advance";
    } else if (st.phase === "maintenance") {
      const due = GS.maintenanceDueList(st).filter(a => !a.decided);
      if (!due.length) { st.phase = "advance"; continue; }
      if (policy.onMaintenance(st, due[0]) === "authorize") GS.authorizeCheck(st, due[0]);
      else GS.deferCheck(st, due[0]);
    } else if (st.phase === "advance") {
      st.phase = "report";           // advanceDay expects to be leaving a report
      GS.advanceDay(st);
    }
  }

  const days = st.history.length;
  const avgOtp = days ? st.history.reduce((s, h) => s + h.otp, 0) / days : 0;
  const cancels = st.history.reduce((s, h) => s + h.cancelled, 0);
  const avgNet = days ? st.history.reduce((s, h) => s + h.net, 0) / days : 0;
  return {
    seed, days, avgOtp, cancels, avgNet,
    cash: st.cash, rep: st.reputation,
    bankrupt: st.overReason === "bankrupt",
    stalled: guard >= 200000,
    lowWater: Math.min(...st.history.map(h => h.balance), st.cash)
  };
}

function traceDay(seed) {
  GS.newRun(seed);
  const st = GS.state;
  st.phase = "day";
  console.log(`\nDAY 1 TRACE  seed=${seed}  ${st.flights.length} flights  rep=${st.reputation}`);
  const rot = {};
  for (const f of st.flights) (rot[f.aircraft] ||= []).push(f);
  for (const [tail, list] of Object.entries(rot)) {
    console.log(`  ${tail}: ` + list.map(f =>
      `${f.id} ${f.from}-${f.to} ${String(Math.floor(f.schedDep/60)).padStart(2,"0")}:${String(f.schedDep%60).padStart(2,"0")}`
    ).join("  "));
  }
  let lastLog = 0;
  while (st.phase === "day") {
    GS.simTick(st);
    while (lastLog < st.events.length) {
      const e = st.events[lastLog++];
      const t = `${String(Math.floor(e.t/60)).padStart(2,"0")}:${String(e.t%60).padStart(2,"0")}`;
      console.log(`  ${t}  ${e.text}`);
    }
  }
  const r = st.lastReport;
  console.log(`\n  OTP ${Math.round(r.stats.otp*100)}%  operated ${r.stats.operated}  cancelled ${r.stats.cancelled}` +
              `  pax ${r.stats.paxCarried}  stranded ${r.stats.stranded}`);
  console.log(`  revenue ${Math.round(r.cash.revenue)}  costs ${Math.round(r.cash.costs)}  net ${Math.round(r.cash.net)}`);
}

// --- Entry ------------------------------------------------------------------

// Median daily net and balance across many seasons, so the shape of the run is
// visible rather than inferred from an average.
function arc(policyName, seeds) {
  const policy = POLICIES[policyName];
  const runs = [];
  for (let i = 0; i < seeds; i++) { runs.push(runSeason("seed-" + i, policy).__hist || null); }
  return runs;
}

function arcReport(policyName, seeds) {
  const policy = POLICIES[policyName];
  const hists = [];
  for (let i = 0; i < seeds; i++) {
    GS.newRun("seed-" + i);
    const r = runSeasonKeepHistory(policy);
    hists.push(r);
  }
  console.log(`\nARC — ${policyName}, ${seeds} seasons`);
  console.log("day  medNet     medBal     medRep  medOTP  alive  cancels  ~misc  ~strand  late/dly  crewout/res");
  for (let d = 0; d < CFG.SEASON_DAYS; d++) {
    const rows = hists.map(h => h[d]).filter(Boolean);
    if (!rows.length) break;
    const med = (f) => { const v = rows.map(f).sort((a, b) => a - b); return v[Math.floor(v.length / 2)]; };
    const cancels = rows.reduce((s, r) => s + r.cancelled, 0) / rows.length;
    console.log(
      String(d + 1).padStart(3) +
      String(Math.round(med(r => r.net)).toLocaleString()).padStart(10) +
      String(Math.round(med(r => r.balance)).toLocaleString()).padStart(11) +
      String(Math.round(med(r => r.rep))).padStart(8) +
      String(Math.round(med(r => r.otp) * 100) + "%").padStart(8) +
      String(rows.length).padStart(7) +
      cancels.toFixed(2).padStart(9) +
      String(Math.round(rows.reduce((s2, r) => s2 + r.misconnected, 0) / rows.length)).padStart(9) +
      String(Math.round(rows.reduce((s2, r) => s2 + r.stranded, 0) / rows.length)).padStart(8) +
      (Math.round(med(r => r.delayed)) + "/" + Math.round(med(r => r.avgDelay)) + "m").padStart(10) +
      ((rows.reduce((s2, r) => s2 + r.crewBlocks, 0) / rows.length).toFixed(1) + "/" +
       (rows.reduce((s2, r) => s2 + r.reserveUses, 0) / rows.length).toFixed(1)).padStart(13));
  }
}

function runSeasonKeepHistory(policy) {
  const st = GS.state;
  st.phase = "day";
  let guard = 0;
  while (st.phase !== "over" && guard++ < 200000) {
    if (st.phase === "day") {
      GS.simTick(st);
      if (st.clock % 5 === 0) policy.onTick(st);
    } else if (st.phase === "report") {
      st.phase = GS.maintenanceDueList(st).some(a => !a.decided) ? "maintenance" : "advance";
    } else if (st.phase === "maintenance") {
      const due = GS.maintenanceDueList(st).filter(a => !a.decided);
      if (!due.length) { st.phase = "advance"; continue; }
      if (policy.onMaintenance(st, due[0]) === "authorize") GS.authorizeCheck(st, due[0]);
      else GS.deferCheck(st, due[0]);
    } else if (st.phase === "advance") {
      st.phase = "report";
      GS.advanceDay(st);
    }
  }
  return st.history;
}

const args = process.argv.slice(2);
if (args[0] === "--day") { traceDay(args[1] || "trace"); process.exit(0); }
if (args[0] === "--arc") { arcReport(args[1] || "competent", Number(args[2]) || 20); process.exit(0); }

const SEEDS = Number(args[0]) || 30;
console.log(`Ground Stop — ${SEEDS} seasons per policy, ${CFG.SEASON_DAYS} days each\n`);

for (const [name, policy] of Object.entries(POLICIES)) {
  const rows = [];
  for (let i = 0; i < SEEDS; i++) rows.push(runSeason("seed-" + i, policy));

  const stalled = rows.filter(r => r.stalled).length;
  const bust = rows.filter(r => r.bankrupt);
  const survived = rows.filter(r => !r.bankrupt);
  const avg = (f) => rows.reduce((s, r) => s + f(r), 0) / rows.length;

  console.log(`── ${name.toUpperCase()} ──`);
  if (stalled) console.log(`  !! ${stalled} run(s) hit the loop guard — the sim did not terminate`);
  console.log(`  bankrupt        ${bust.length}/${rows.length}` +
              (bust.length ? `  on days [${bust.map(r => r.days).sort((a,b)=>a-b).join(", ")}]` : ""));
  console.log(`  avg on-time     ${(avg(r => r.avgOtp) * 100).toFixed(1)}%`);
  console.log(`  avg cancels/day ${(avg(r => r.cancels / Math.max(1, r.days))).toFixed(2)}`);
  console.log(`  avg daily net   ${Math.round(avg(r => r.avgNet)).toLocaleString()}`);
  console.log(`  final cash      min ${Math.round(Math.min(...rows.map(r=>r.cash))).toLocaleString()}` +
              `  median ${Math.round(rows.map(r=>r.cash).sort((a,b)=>a-b)[Math.floor(rows.length/2)]).toLocaleString()}` +
              `  max ${Math.round(Math.max(...rows.map(r=>r.cash))).toLocaleString()}`);
  console.log(`  final rep       ${(avg(r => r.rep)).toFixed(1)}`);
  if (survived.length) console.log(`  survivors       ${survived.length}, avg cash ${Math.round(survived.reduce((s,r)=>s+r.cash,0)/survived.length).toLocaleString()}`);
  console.log("");
}
