#!/bin/bash
# Exercise the school CLI against a scratch config and a recording client.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"
export OMARCHY_PATH="$ROOT"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export OMARCHY_KIDS_SCHOOL_CONFIG="$test_tmp/school-mode.json"
eval "$(sed -n '/^CONFIG=/,/^user=""/p' "$ROOT/bin/omarchy-kids-school")"
USER_NAME=kid
client() {
  if [[ $* == "config get" ]]; then
    printf '{"ok":true,"config":{"active_profile":"class","users":{"kid":{"profile":"class"}},"profiles":{"class":{"school_apps":["chromium"],"blocked_periods":[]}}}}\n'
  else
    printf '%s\n' "$*" >>"$test_tmp/calls"
    echo '{"ok":true}'
  fi
}
config_init
jq -e '.version == 1 and .users == {}' "$CONFIG" >/dev/null || fail "school initializes its own configuration"
school_schedule mon-fri 08:00-15:30 sat 09:00-11:00 >/dev/null
payload=$(sed -n 's/^config patch //p' "$test_tmp/calls" | tail -1)
jq -e '.blocked_periods | length == 2 and all(.[]; .mode == "free")' <<<"$payload" >/dev/null || fail "school writes only school periods"
jq -e '.blocked_periods[0].days == ["mon","tue","wed","thu","fri"]' <<<"$payload" >/dev/null || fail "weekday school hours retain their days"
(school_schedule fry 08:00-10:00) >/dev/null 2>&1 && fail "school rejects invalid days"
(school_schedule mon 25:00-26:00) >/dev/null 2>&1 && fail "school rejects invalid times"
school_command apps add obsidian >/dev/null
grep -q '"school_apps":\["chromium","obsidian"\]' "$test_tmp/calls" || fail "the app editor resolves shared school profiles"
[[ ! -e $test_tmp/screen-time.json ]] || fail "school must not initialize screen time"
pass "school schedules and apps use their own profile without screen time"
