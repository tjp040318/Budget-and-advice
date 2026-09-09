#!/bin/bash
# Waits for the GitHub Actions run on a commit and prints its steps.
# usage: ciwait.sh <sha>
SHA="$(git -C /home/user/Budget-and-advice rev-parse "$1")"
API="https://api.github.com/repos/tjp040318/Budget-and-advice/actions"
for i in $(seq 1 24); do
  RUN=$(curl -s "$API/runs?head_sha=$SHA&per_page=3" | python3 -c "import sys,json; r=json.load(sys.stdin).get('workflow_runs',[]); print(r[0]['id'] if r else '')")
  [ -n "$RUN" ] && break
  sleep 10
done
[ -z "$RUN" ] && { echo "no run for $SHA"; exit 1; }
echo "run $RUN"
for i in $(seq 1 120); do
  ST=$(curl -s "$API/runs/$RUN" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['status'], r.get('conclusion'))")
  case "$ST" in completed*) break;; esac
  sleep 30
done
echo "$SHA $ST"
curl -s "$API/runs/$RUN/jobs" | python3 -c "
import sys,json
for j in json.load(sys.stdin)['jobs']:
    print('job:', j['status'], j['conclusion'])
    for s in j['steps']:
        print('  %-45s %s %s %s %s' % (s['name'], s['status'], s['conclusion'], (s.get('started_at') or '')[11:19], (s.get('completed_at') or '')[11:19]))
"
