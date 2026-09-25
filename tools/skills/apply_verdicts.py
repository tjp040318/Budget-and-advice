"""Record the judges' verdicts in Art/Motions/skills.json.

  python3 tools/skills/apply_verdicts.py <journal.jsonl> [<journal.jsonl> ...] [--repair]

A verdict is applied to a take only if the judge who gave it STARTED after
that take was queued (its agent transcript's first timestamp against the
record's `queued`): a workflow's journal is rewritten as long as it runs, so
its file time says nothing about which take its early judges saw, and
applying by file time put second-take verdicts on third takes (2026-09-25).
--repair first clears any record whose verdict is its previous take's (the
same reason word for word), so the right judge's verdict can land.
Uses skill_moves' own load/save/touch, so a running `run` is merged."""
import json, sys, os
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import skill_moves as S
from retarget import Motion

VERDICT_FIELDS = ('contact_frames', 'contacts', 'judged', 'judged_prompt', 'judge_reason', 'judge_notes', 'suggested', 'kept_as')


def stamp(text):
    if not text:
        return 0.0
    text = text.rstrip('Z').split('.')[0]
    return datetime.strptime(text, '%Y-%m-%dT%H:%M:%S').replace(tzinfo=timezone.utc).timestamp()


args = sys.argv[1:]
repair = '--repair' in args
args = [a for a in args if a != '--repair']
if '--skip' in args:                      # accepted and ignored: the start-time guard replaces it
    i = args.index('--skip'); args = args[:i] + args[i + 2:]

m = S.load()
if repair:
    fixed = []
    for k, rec in m['moves'].items():
        hist = rec.get('history') or []
        if hist and rec.get('judge_reason') and hist[-1].get('judge_reason') == rec.get('judge_reason'):
            for f in VERDICT_FIELDS:
                rec.pop(f, None)
            S.touch(rec)
            fixed.append(k)
    print(f"repaired {len(fixed)} record(s) carrying their previous take's verdict: {' '.join(sorted(fixed))}")

verdicts = []
for journal in args:
    d = Path(journal).parent
    for line in open(journal):
        o = json.loads(line)
        if o.get('type') == 'result' and o.get('result'):
            t = d / f"agent-{o['agentId']}.jsonl"
            started = stamp(json.loads(open(t).readline()).get('timestamp')) if t.exists() else 0.0
            verdicts += [dict(v, _started=started) for v in o['result'].get('motions', [])]

n = {'keep': 0, 'aim': 0, 'reroll': 0}
for v in verdicts:
    key = v['key']
    rec = m['moves'].get(key)
    if rec is None:
        continue
    if rec.get('judged_prompt') == rec.get('prompt') and rec.get('contact_frames') is not None:
        continue                                   # recorded already, for this take
    if rec.get('state') != 'archived' or stamp(rec.get('queued')) > v['_started']:
        continue                                   # a judge who saw an earlier take
    if rec.get('retired'):
        continue
    frames = len(Motion.load(str(S.archive_path(key))).anim['T'])
    cf = sorted(int(f) for f in v['contact_frames'] if 0 <= int(f) < frames)
    rec['contact_frames'] = cf
    rec['contacts'] = [round(f / (frames - 1), 3) for f in cf]
    rec['judged'] = 'keep' if v['verdict'] == 'aim' else v['verdict']
    if v['verdict'] == 'aim':
        rec['kept_as'] = 'aimed at ship'
    rec['judged_prompt'] = rec.get('prompt')
    rec['judge_reason'] = v.get('reason', '')[:600]
    rec['judge_notes'] = v.get('notes', '')[:400]
    if v['verdict'] == 'reroll':
        rec['suggested'] = v.get('new_sentence', '').strip()
    S.touch(rec)
    n[v['verdict']] += 1
S.save(m)
print(f"{n['keep']} kept, {n['aim']} kept to be aimed, {n['reroll']} flagged for a re-roll (recorded; nothing re-bought)")
