#!/bin/bash
#
# `omarchy-parent time` switches screen time on and off for the kid account and
# tunes it, over the daemon's client as root. The functions run extracted
# against a scratch tree, with the client, systemctl, and runuser stubbed and
# their calls recorded; the daemon itself is covered by
# screen-time-daemon-test.sh.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

parent="$ROOT/bin/omarchy-parent"
parent_time="$ROOT/bin/omarchy-parent-time"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin" "$test_tmp/sudoers.d" "$test_tmp/units" "$test_tmp/etc" "$test_tmp/home/kid"
export CALLS="$test_tmp/calls" PROFILE_JSON="$test_tmp/profile.json"
printf '{"earn": {"questions_per_set": 5, "set_minutes": 30, "level": "grade5", "daily_cap_minutes": 120}, "blocked_periods": [{"label": "Bedtime", "enabled": false, "start": "20:00", "end": "07:00", "days": ["mon","tue","wed","thu","fri","sat","sun"], "mode": "block"}]}\n' >"$PROFILE_JSON"
cat >"$stub_bin/omarchy-parent-time-client" <<'SH'
#!/bin/bash
printf 'client %s\n' "$*" >>"$CALLS"
case "$*" in
  *"ping") printf '{"ok":true,"modules":{"time":{"users":%s},"school":{"users":%s}}}\n' "$(jq length <<<"${STUB_USERS:-[]}")" "${STUB_SCHOOL_USERS:-0}" ;;
  *"config get") printf '{"ok": true, "config": {"active_profile": "kid", "profiles": {"kid": %s}}}\n' "$(cat "$PROFILE_JSON")" ;;
  *"users"|*"users --human") printf '{"ok": true, "users": %s}\n' "${STUB_USERS:-[]}" ;;
  *"grant"*) printf '{"ok": true, "remaining_seconds": 1800}\n' ;;
  *"--human status") echo "Screen time for kid: running" ;;
  *) printf '{"ok": true}\n' ;;
esac
SH
for stub in systemctl runuser; do
  cat >"$stub_bin/$stub" <<SH
#!/bin/bash
printf '$stub %s\\n' "\$*" >>"\$CALLS"
SH
done
cat >"$stub_bin/getent" <<'SH'
#!/bin/bash
[[ $1 == passwd && $2 == kid ]] && echo "kid:x:1000:1000::$TEST_HOME/kid:/bin/bash"
SH
chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH" TEST_HOME="$test_tmp/home"
export OMARCHY_SUDOERS_DIR="$test_tmp/sudoers.d" OMARCHY_SYSTEM_UNIT_DIR="$test_tmp/units" \
  OMARCHY_PARENT_STATE_DIR="$test_tmp/state" OMARCHY_PATH="$ROOT" \
  OMARCHY_PARENT_TIME_CONFIG="$test_tmp/etc/screen-time.json" OMARCHY_PARENT_TIME_CLIENT="$stub_bin/omarchy-parent-time-client"

source "$ROOT/install/helpers/parent.sh"
eval "$(sed -n '/^CONFIG=/,/^USER_NAME=""/p' "$parent_time")"
eval "$(sed -n '/^fail() {/,/^}/p' "$parent_time")"
eval "$(sed -n '/^# --- screen time ---$/,/^# --- end screen time ---$/p' "$parent_time")"
systemd_running() { [[ ${STUB_SYSTEMD:-running} == running ]]; }
USER_NAME=kid

: >"$CALLS"
printf 'kid ALL=(root) NOPASSWD: /usr/bin/omarchy-parent-quiz question\n' >"$test_tmp/sudoers.d/omarchy-parent-kid-time"
: >"$test_tmp/units/omarchy-parent-time.timer"
time_on >/dev/null
[[ -f $test_tmp/etc/screen-time.json ]] && jq -e '.version == 3 and .users == {} and .profiles.default' "$test_tmp/etc/screen-time.json" >/dev/null || fail "time on writes the daemon's current config once" "$(cat "$test_tmp/etc/screen-time.json" 2>/dev/null)"
[[ -f $test_tmp/units/omarchy-parent-timed.service ]] || fail "time on installs the daemon's unit"
grep -q 'systemctl enable --now omarchy-parent-timed.service' "$CALLS" || fail "time on starts the daemon" "calls: $(<"$CALLS")"
grep -q '^client --user kid users add kid$' "$CALLS" || fail "time on tells the daemon to manage the account" "calls: $(<"$CALLS")"
[[ ! -e $test_tmp/sudoers.d/omarchy-parent-kid-time && ! -e $test_tmp/units/omarchy-parent-time.timer ]] || fail "time on takes the old design's grant and timer away"
grep -q 'systemctl disable --now omarchy-parent-time.timer' "$CALLS" || fail "time on stops the old timer" "calls: $(<"$CALLS")"
grep -q '^runuser -u kid -- env OMARCHY_PATH=' "$CALLS" && grep -q 'omarchy.screen-time' "$CALLS" || fail "time on puts the pill on the kid's bar, as the kid" "calls: $(<"$CALLS")"
pass "time on installs the daemon, names the account, and retires the old design"

: >"$CALLS"
STUB_SYSTEMD=chroot time_on >/dev/null
jq -e '.users.kid.profile == "kid" and .profiles.kid.name == "kid"' "$test_tmp/etc/screen-time.json" >/dev/null || fail "in the install chroot time on names the account in the config the daemon will read" "$(cat "$test_tmp/etc/screen-time.json")"
! grep -q 'enable --now' "$CALLS" || fail "the chroot never starts the daemon"
pass "time on works inside the install chroot"

: >"$CALLS"
time_command earn 4 30 >"$test_tmp/out" || fail "earn succeeds" "$(<"$test_tmp/out")"
grep -q '^client --user kid config patch {"earn":{"questions_per_set":4,"set_minutes":30}}$' "$CALLS" || fail "earn patches the set" "calls: $(<"$CALLS")"
[[ $(<"$test_tmp/out") == *"per right answer"* ]] || fail "earn says what a right answer is worth" "$(<"$test_tmp/out")"
! (time_command earn 0 30) >/dev/null 2>&1 || fail "earn refuses no questions"
: >"$CALLS"
time_command level grade2 >/dev/null
grep -q '^client --user kid config patch {"earn":{"level":"grade2"}}$' "$CALLS" || fail "level patches the grade"
! (time_command level grade9) >/dev/null 2>&1 || fail "level refuses an unknown grade"
: >"$CALLS"
time_command cap 90 >/dev/null; time_command questions 8 >/dev/null; time_command rate 3 >/dev/null
grep -q '{"earn":{"daily_cap_minutes":90}}' "$CALLS" && grep -q '{"earn":{"questions_per_set":8}}' "$CALLS" && grep -q '{"earn":{"set_minutes":15}}' "$CALLS" || fail "cap, questions, and rate patch their keys; rate multiplies by the set's questions" "calls: $(<"$CALLS")"
: >"$CALLS"
time_command budget 45 weekdays >/dev/null
grep -q '{"budget_minutes":{"mon":45,"tue":45,"wed":45,"thu":45,"fri":45}}' "$CALLS" || fail "budget sets the named days" "calls: $(<"$CALLS")"
time_command budget 90 >/dev/null
grep -q '"sun":90' "$CALLS" || fail "budget without days is every day"
: >"$CALLS"
[[ $(time_command grant 30) == *"Granted 30 minutes"*"30 minutes left today"* ]] || fail "grant reports the new balance"
grep -q '^client --user kid grant 30$' "$CALLS" || fail "grant goes to the daemon as root, no password" "calls: $(<"$CALLS")"
time_command pause >/dev/null; time_command lock >/dev/null
grep -q '^client --user kid pause$' "$CALLS" && grep -q '^client --user kid lock$' "$CALLS" || fail "pause and lock go to the daemon"
pass "the settings and the parent's actions go through the client"

[[ $(days_json 'Mon,Wed,fri') == '["mon","wed","fri"]' && $(days_json sat-mon) == '["mon","sat","sun"]' && $(days_json weekends) == '["sat","sun"]' ]] || fail "day lists parse, in week order" "$(days_json sat-mon)"
! days_json fry >/dev/null || fail "an unknown day is rejected"
! window_parts 25:00-26:00 >/dev/null || fail "an impossible time is rejected"
: >"$CALLS"
time_bedtime 20:30-07:00 >/dev/null
[[ $(sed -n 's/^client --user kid config patch //p' "$CALLS" | tail -1 | jq -c '.blocked_periods[-1] | [.label, .mode, .start, .end]') == '["Bedtime","block","20:30","07:00"]' ]] || fail "bedtime is a locked period every night" "$(<"$CALLS")"
pass "bedtime belongs to screen time"

: >"$CALLS"
STUB_USERS='[]' time_off >/dev/null
grep -q '^client --user kid users remove kid$' "$CALLS" || fail "time off tells the daemon to drop the account" "calls: $(<"$CALLS")"
grep -q 'systemctl disable --now omarchy-parent-timed.service' "$CALLS" || fail "time off stops the daemon when no account is left" "calls: $(<"$CALLS")"
[[ -f $test_tmp/etc/screen-time.json ]] || fail "time off keeps the settings"
: >"$CALLS"
STUB_USERS='["sib"]' time_off >/dev/null
! grep -q 'disable' "$CALLS" || fail "the daemon stays while another account has screen time on"
: >"$CALLS"
STUB_USERS='[]' STUB_SCHOOL_USERS=1 time_off >/dev/null
! grep -q 'disable' "$CALLS" || fail "the parent host stays while school mode is on"
pass "time off drops the account and stops the daemon only with the last one"

grep -q '^# omarchy:summary=Screen time earned with arithmetic' "$parent_time" || fail "omarchy-parent-time announces itself as a feature"
! grep -q '^  time)' "$parent" || fail "omarchy-parent carries no time code of its own"
[[ $(OMARCHY_PATH="$ROOT" bash "$parent" --help) == *"time      Screen time earned with arithmetic"* ]] || fail "omarchy-parent --help lists screen time as a feature"
grep -q 'omarchy-parent time earn QUESTIONS MINUTES' "$parent_time" || fail "the usage offers earn QUESTIONS MINUTES"
grep -q '^ExecStart=/usr/bin/omarchy-parent-timed$' "$ROOT/default/parent/omarchy-parent-timed.service" && grep -q '^WantedBy=multi-user.target$' "$ROOT/default/parent/omarchy-parent-timed.service" || fail "the daemon's unit runs it as root at boot"
pass "screen time plugs into omarchy-parent as a feature command over the daemon"
