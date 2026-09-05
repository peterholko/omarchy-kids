#!/bin/bash
#
# Screen time no longer gates the lock screen's PAM stacks: when the budget
# is empty root locks the session, the kid unlocks with her password, and
# the math plugin holds the screen until she has earned time. The stacks
# omarchy-apply-lock writes must therefore be the same with screen time on
# and off, and carry no budget gate for the fingerprint either.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

apply_lock="$ROOT/bin/omarchy-apply-lock"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
pam_dir="$test_tmp/pam.d"
mkdir -p "$stub_bin" "$pam_dir"
cat >"$stub_bin/sudo" <<SH
#!/bin/bash
args=()
for arg in "\$@"; do args+=("\${arg//\/etc\/pam.d/$pam_dir}"); done
exec "\${args[@]}"
SH
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ ${STUB_FINGERPRINT:-no} == yes ]]
SH
cat >"$stub_bin/fprintd-list" <<'SH'
#!/bin/bash
echo "right-index-finger"
SH
cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$stub_bin/omarchy-profile-child" <<'SH'
#!/bin/bash
[[ ${STUB_PROFILE:-default} == child ]]
SH
chmod +x "$stub_bin"/*

state="$test_tmp/state"
mkdir -p "$state/kid/time"
export OMARCHY_KIDS_STATE_DIR="$state"

run_apply_lock() {
  OMARCHY_INSTALL_USER=kid OMARCHY_PAM_DIR="$pam_dir" PATH="$stub_bin:$PATH" bash "$apply_lock" >/dev/null
}

STUB_PROFILE=child run_apply_lock
before=$(<"$pam_dir/omarchy-lock-password")
touch "$state/kid/time/enabled"
STUB_PROFILE=child STUB_FINGERPRINT=yes run_apply_lock
[[ $(<"$pam_dir/omarchy-lock-password") == "$before" ]] || fail "screen time on leaves the password stack as it was" "$(cat "$pam_dir/omarchy-lock-password")"
! grep -q 'omarchy-kids-quiz' "$pam_dir/omarchy-lock-password" || fail "no budget gate in the password stack"
! grep -q 'omarchy-kids-quiz' "$pam_dir/omarchy-lock-fingerprint" || fail "no budget gate in the fingerprint stack"
[[ $(sed -n '2p' "$pam_dir/omarchy-lock-fingerprint") == 'auth       required                    pam_fprintd.so' ]] || fail "the fingerprint stack starts with the print" "$(cat "$pam_dir/omarchy-lock-fingerprint")"
! grep -q 'budget_gate\|omarchy-kids-quiz gate' "$apply_lock" || fail "omarchy-apply-lock no longer knows a budget gate"
pass "the lock screen's PAM stacks carry no screen-time gate; the math plugin holds the session instead"
