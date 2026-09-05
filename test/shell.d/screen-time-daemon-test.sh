#!/bin/bash
#
# The screen-time daemon of a child install (lib/screen-time): its own unit
# tests, then a live daemon in the test layout driven through the client the
# shell and omarchy-parent time use, with the parent password stubbed to a
# fixed word and the lock command to true.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

python3 "$ROOT/lib/screen-time/tests/test_core.py" >"$ROOT/../.screen-time-unit.log" 2>&1 && rm -f "$ROOT/../.screen-time-unit.log" || {
  cat "$ROOT/../.screen-time-unit.log"; rm -f "$ROOT/../.screen-time-unit.log"; fail "the daemon's unit tests pass"
}
pass "the daemon's unit tests pass"

grep -q 'Account(self.layout, uid, self.config, owner_uid=None, log=self.log)' "$ROOT/lib/parent/omarchy_parent/screen_time/service.py" || fail "the state is root's in every layout; handing it to the kid was the crash at startup"
grep -q 'could not set up uid' "$ROOT/lib/parent/omarchy_parent/screen_time/service.py" || fail "one account's trouble does not take the daemon down"
grep -q '"OMARCHY_PATH": omarchy_path' "$ROOT/lib/parent/omarchy_parent/core/session.py" || fail "root hands the kid's session OMARCHY_PATH for omarchy-shell"
grep -q 'journalctl -u "\$UNIT" -n 12' "$ROOT/bin/omarchy-parent-time" || fail "a daemon that does not start shows its journal"
pass "the system-mode startup is root-owned and its failures are visible"

tmp=$(mktemp -d)
daemon_pid=""
cleanup() {
  [[ -n $daemon_pid ]] && kill "$daemon_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
export SCREEN_TIME_ROOT="$tmp/root" SCREEN_TIME_TICK_SECONDS=0.2 SCREEN_TIME_LOCK_COMMAND=/usr/bin/true SCREEN_TIME_TEST_PASSWORD=letmein OMARCHY_PATH="$ROOT"
mkdir -p "$SCREEN_TIME_ROOT"
me=$(id -un)
cat >"$SCREEN_TIME_ROOT/config.json" <<JSON
{"version": 2, "users": {"$me": {"profile": "$me"}}, "active_profile": "$me", "profiles": {"$me": {"name": "Kid", "budget_minutes": {"mon":60,"tue":60,"wed":60,"thu":60,"fri":60,"sat":60,"sun":60}, "earn": {"level": "grade1", "questions_per_set": 3, "set_minutes": 30, "min_answer_seconds": 0},
  "blocked_periods": [{"label": "School", "enabled": true, "start": "00:00", "end": "23:59", "mode": "free"}]}}}
JSON
bash "$ROOT/bin/omarchy-parent-timed" >"$tmp/daemon.log" 2>&1 &
daemon_pid=$!
client() { bash "$ROOT/bin/omarchy-parent-time-client" "$@"; }
school_client() { bash "$ROOT/bin/omarchy-parent-school-client" "$@"; }
for _ in $(seq 1 50); do [[ -S $SCREEN_TIME_ROOT/sock ]] && break; sleep 0.1; done
[[ -S $SCREEN_TIME_ROOT/sock ]] || fail "the daemon listens on its socket" "$(cat "$tmp/daemon.log")"
[[ $(client ping | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["ok"], d["mode"])') == "True test" ]] || fail "ping answers with the layout"
status=$(client status)
python3 - "$status" <<'PY' || fail "status carries the set and the budget" "$status"
import json, sys
d = json.loads(sys.argv[1]); assert d["ok"] and d["remaining_seconds"] == 3600, d
assert d["earn"]["questions_per_set"] == 3 and d["earn"]["set_minutes"] == 30 and d["earn"]["seconds_per_correct"] == 600 and d["earn"]["level"] == "grade1", d["earn"]
PY
pass "the daemon answers status with the set the parent configured"

practice=$(client practice grade2)
python3 - "$practice" <<'PY' || fail "practice hands the app a question with its answer" "$practice"
import json, sys
d = json.loads(sys.argv[1]); assert d["ok"] and eval(d["text"].replace("×", "*").replace("÷", "//")) == d["answer"], d
PY
question=$(client quiz)
qid=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["question"]["id"])' "$question")
text=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["question"]["text"])' "$question")
[[ $(client answer "$qid" 999999 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["correct"], d["reward_seconds"])') == "False 0" ]] || fail "a wrong answer earns nothing"
question=$(client quiz); qid=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["question"]["id"])' "$question"); text=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["question"]["text"])' "$question")
right=$(python3 -c 'import sys; print(eval(sys.argv[1].replace("×","*").replace("÷","//")))' "$text")
[[ $(client answer "$qid" "$right" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["correct"], d["reward_seconds"], d["remaining_seconds"])') == "True 600 4200" ]] || fail "a right answer credits the set's share, ten minutes of thirty over three"
pass "questions come from the daemon and a right answer is credited by it"

status_file="$SCREEN_TIME_ROOT/status/$me/time/status.json"
for _ in $(seq 1 30); do grep -q '"budget": 4200' "$status_file" 2>/dev/null && break; sleep 0.1; done
grep -q '"budget": 4200' "$status_file" && grep -q '"enabled": true' "$status_file" && grep -q '"questions": 3' "$status_file" && grep -q '"sessionMinutes": 30' "$status_file" && grep -q '"level": "grade1"' "$status_file" || fail "the daemon publishes the status.json the lock screen and Math time read" "$(cat "$status_file" 2>/dev/null)"
pass "status.json is published for the lock screen"

[[ $(printf 'letmein\n' | client --password-stdin grant 5 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["ok"], d["remaining_seconds"])') == "True 4500" ]] || fail "the parent password grants minutes"
[[ $(printf 'wrong\n' | client --password-stdin grant 5 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("error"))') == "bad_password" ]] || fail "a wrong parent password is refused"
[[ $(printf 'letmein\n' | client --password-stdin grant -600 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["remaining_seconds"], d["applied_seconds"])') == "0 -4500" ]] || fail "taking time stops at a zero bank instead of creating debt"
[[ $(printf 'letmein\n' | client --password-stdin grant 5 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["remaining_seconds"], d["applied_seconds"])') == "300 300" ]] || fail "five granted minutes are immediately usable after reaching zero"
[[ $(printf 'letmein\n' | client --password-stdin config patch '{"earn": {"level": "grade2", "questions_per_set": 4}}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["ok"])') == "True" ]] || fail "the parent password changes the set"
[[ $(client status | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["earn"]["level"], d["earn"]["seconds_per_correct"])') == "grade2 450" ]] || fail "the new set reads back: four for thirty, 450 seconds each"
day=$(client --human day)
[[ $day == *"right   "*"+10 min"* && $day == *"given   5 min"* ]] || fail "the day's report lists the right answer and the grant" "$day"
pass "the parent's grant has a zero floor, and the patch and report go through the client"

# School mode: the whole day is a school period in this config, so it is
# school mode by the schedule, the kid cannot take free time alone, and the
# parent password can.
[[ $(client mode | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode"], d["mode_reason"], d["school_until"])') == "school schedule 23:59" ]] || fail "school hours are school mode"
grep -q '"mode": "school"' "$status_file" && grep -q '"schoolApps"' "$status_file" || fail "status.json carries the mode and the school apps for the shell" "$(cat "$status_file")"
[[ $(client mode free </dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "parent_required" ]] || fail "the kid cannot take free time inside school hours"
[[ $(printf '\n' | client --password-stdin mode free | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "parent_required" ]] || fail "an empty password from the panel cannot take free time"
[[ $(printf 'wrong\n' | client --password-stdin mode free | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "bad_password" ]] || fail "the mode switch rejects an incorrect parent password"
[[ $(client mode | python3 -c 'import json,sys; print(json.load(sys.stdin)["mode"])') == "school" ]] || fail "refused mode switches leave school mode active"
[[ $(printf 'letmein\n' | client --password-stdin mode free | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["ok"], d["mode"], d["mode_reason"])') == "True free parent" ]] || fail "the parent password takes free time"
[[ $(printf 'wrong\n' | client --password-stdin mode free | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "bad_password" ]] || fail "a supplied password is checked even when free time is already active"
[[ $(client mode auto | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode"], d["mode_reason"])') == "school schedule" ]] || fail "the kid may hand free time back to the school schedule"
[[ $(client mode school | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["ok"], d["mode"])') == "True school" ]] || fail "school mode can be chosen any time"
[[ $(client --human mode) == "School mode (chosen"* ]] || fail "mode reads back for people" "$(client --human mode)"
[[ $(printf 'letmein\n' | client --password-stdin config patch '{"school_apps": ["obsidian", "Wikipedia"]}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["ok"])') == "True" ]] || fail "the school app list is the parent's to set"
[[ $(client mode | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)["school_apps"]))') == "obsidian,Wikipedia" ]] || fail "the school app list reads back"

# Outside scheduled school hours, a child's own mode choice is only the
# filtered desktop. A parent-authenticated choice also pauses screen time.
[[ $(printf 'letmein\n' | school_client --password-stdin config patch '{"blocked_periods": []}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["ok"])') == "True" ]] || fail "the school schedule can be cleared"
printf 'letmein\n' | client --password-stdin mode auto >/dev/null
[[ $(client mode free </dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "parent_required" ]] || fail "every deliberate free-time choice needs the parent, even when already free"
[[ $(client mode auto </dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "parent_required" ]] || fail "auto needs the parent when it resolves to free time"
[[ $(printf '\n' | client --password-stdin mode school | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode"], d["mode_reason"])') == "school chosen" ]] || fail "the tray's passwordless school mode records the kid as its chooser"
[[ $(client status | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode_reason"], d["phase"] == "school")') == "chosen False" ]] || fail "the kid's school mode still uses screen time"
[[ $(client mode free </dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "parent_required" ]] || fail "the kid cannot leave chosen school mode"
[[ $(client mode auto </dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "parent_required" ]] || fail "auto cannot bypass the parent password when it would leave school mode"
[[ $(printf 'letmein\n' | client --password-stdin mode free | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode"], d["mode_reason"])') == "free parent" ]] || fail "the parent password can leave chosen school mode"
[[ $(printf 'letmein\n' | client --password-stdin mode school | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode"], d["mode_reason"])') == "school parent" ]] || fail "a parent password marks school mode as the parent's"
[[ $(client status | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode_reason"], d["phase"], d["counting"])') == "parent school False" ]] || fail "parent school mode pauses screen time"
python3 - "$status_file" <<'PY' || fail "the Math-time gate sees parent school mode as free of screen time" "$(cat "$status_file")"
import json, sys
d = json.load(open(sys.argv[1])); assert d["school"] is True and d["modeReason"] == "parent", d
PY
[[ $(printf 'letmein\n' | client --password-stdin config patch '{"philosophy": "together"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["ok"])') == "True" ]] || fail "the parent may select agreement mode"
[[ $(printf 'wrong\n' | client --password-stdin config get | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error"))') == "bad_password" ]] || fail "agreement mode does not turn the parent-password gate into any non-empty password"
pass "school mode follows the schedule, keeps the kid's choice counting, and pauses time for a parent choice"
