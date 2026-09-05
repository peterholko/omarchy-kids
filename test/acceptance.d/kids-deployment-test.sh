#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

omarchy-profile-child || fail "the Kids ISO creates a child profile"
[[ -n ${OMARCHY_ACCEPTANCE_SUDO_PASSWORD:-} ]] || fail "the deployment test requires the parent fixture password"
printf '%s\n' "$OMARCHY_ACCEPTANCE_SUDO_PASSWORD" | sudo -S -k -v 2>/dev/null || fail "the parent can inspect module setup"
trap 'sudo -K' EXIT
for package in base settings core dns browsing time school; do
  pacman -Q "omarchy-kids-$package" || fail "Kids package is installed: $package"
done
[[ $OMARCHY_PATH == "/usr/share/omarchy" ]] || fail "the session uses the installed Kids runtime"
[[ $(omarchy-channel-current) == "kids" ]] || fail "updates recognize the Kids package pair"
if id -nG | grep -qwE 'wheel|docker'; then
  fail "the kid has no wheel or docker membership"
fi
sudo -n python3 - <<'PY'
import hashlib, json
from pathlib import Path
cache = Path('/var/cache/omarchy-kids/packages')
release = json.loads((cache / 'release.json').read_text())
assert len(release['packages']) == 7
for info in release['packages'].values():
    assert hashlib.sha256((cache / info['file']).read_bytes()).hexdigest() == info['sha256']
for file in ('screen-time.json', 'school-mode.json'):
    path = Path('/etc/omarchy/parent') / file
    if path.exists():
        assert not json.loads(path.read_text()).get('users'), 'optional restriction enabled without a parent choice'
assert not list(Path('/var/lib/omarchy/parent').glob('*/browsing/enabled'))
PY
pass "all modules and the matching package cache are installed; optional collection and limits await setup"

plugins=$(omarchy-shell shell listPlugins)
for plugin in omarchy.screen-time omarchy.school-mode omarchy.math; do
  [[ $plugins == *"$plugin"* ]] || fail "the installed shell sees $plugin"
done
screenshot "success-kids-desktop"
