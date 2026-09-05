#!/bin/bash
#
# The screen-time plugin of a child install (shell/plugins/screen-time),
# vendored from Jankees van Woezik's omarchy-screen-time and adapted: our id
# and client, the parent password in place of a PIN, grades in the settings,
# Math time opened from the panel, and the lock screen keeping Math time on
# screen while there is no time. Asserted from the sources, plus the manifest.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

plugin="$ROOT/shell/plugins/screen-time"
python3 - "$plugin/manifest.json" <<'PY' || fail "the manifest declares a service, a bar widget, and a panel under omarchy.screen-time"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["id"] == "omarchy.screen-time" and m["keepLoaded"] is True, m
assert sorted(m["kinds"]) == ["bar-widget", "service"], m["kinds"]
assert m["entryPoints"] == {"service": "Service.qml", "barWidget": "BarWidget.qml"}, m["entryPoints"]
assert m["barWidget"]["defaultSection"] == "right", m["barWidget"]
PY
[[ -f $ROOT/lib/screen-time/LICENSE ]] && grep -q 'Jankees van Woezik' "$ROOT/lib/screen-time/LICENSE" || fail "the vendored code carries its MIT licence"
pass "the screen-time plugin ships with its manifest and licence"

grep -q 'Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-kids-time-client"' "$plugin/Service.qml" || fail "the service watches the daemon through our client"
grep -q 'command: \[root.clientPath, "watch"\]' "$plugin/Service.qml" || fail "the service holds the one watch stream"
grep -q 'onRunningChanged: if (!running) { root.connected = false; retryTimer.restart() }' "$plugin/Service.qml" || fail "the watch retries after a stream that ended or a client that could not start"
grep -q 'level = String(earn.level || "grade5")' "$plugin/Service.qml" && grep -q 'questionsPerSet = Number(earn.questions_per_set)' "$plugin/Service.qml" || fail "the service carries the set and the grade"
for f in BarWidget.qml SettingsWindow.qml; do
  ! grep -q -E 'pin-stdin|"PIN"|pinField|pin_set|pinMissing|bad_pin' "$plugin/$f" || fail "$f asks for no PIN"
  grep -q -- '--password-stdin' "$plugin/$f" || fail "$f sends the parent password over stdin"
done
grep -q 'moduleName: "omarchy.screen-time"' "$plugin/BarWidget.qml" && grep -q 'serviceFor("omarchy.screen-time")' "$plugin/BarWidget.qml" || fail "the bar widget is omarchy.screen-time"
grep -q 'ParentPasswordField {' "$plugin/BarWidget.qml" || fail "the parent drawer asks for the parent password"
grep -q 'root.bar.shell.summon("omarchy.math", "{}")' "$plugin/BarWidget.qml" || fail "the panel opens Math time full screen"
! grep -q 'answerField' "$plugin/BarWidget.qml" || fail "the panel no longer takes answers inline"
grep -q 'if (phase === "school") return iconBook' "$plugin/BarWidget.qml" || fail "school time gets its own glyph"
grep -q '"earn": { "level": "grade" + (index + 1) }' "$plugin/SettingsWindow.qml" || fail "the settings pick a grade"
grep -Fq 'import "MathModel.js" as MathModel' "$plugin/SettingsWindow.qml" \
  && grep -Fq 'MathModel.gradeBlurb(MathModel.levelNumber(root.level))' "$plugin/SettingsWindow.qml" \
  && grep -Fq 'text: root.gradeBlurb' "$plugin/SettingsWindow.qml" \
  || fail "the parent settings and Math time share the same arithmetic-fact descriptions"
grep -q '"questions_per_set": value' "$plugin/SettingsWindow.qml" && grep -q '"set_minutes": value' "$plugin/SettingsWindow.qml" || fail "the settings set the questions and the minutes of a set"
grep -q 'togglePeriodDay' "$plugin/SettingsWindow.qml" && ! grep -q '"School time" : "Locks"' "$plugin/SettingsWindow.qml" || fail "time periods have days and cannot write school mode"
[[ ! -e $plugin/Countdown.qml ]] || fail "the bottom-centre countdown card is retired"
grep -q '| Screen time   | `omarchy.screen-time`' "$ROOT/shell/plugins/README.md" || fail "the plugin is listed"
pass "the bar pill, the panel, and the settings speak the parent password and the grades"

lock="$ROOT/shell/plugins/lock/Service.qml"
! grep -q 'warnTimeLow' "$lock" || fail "the lock screen no longer warns itself; the daemon does"
grep -q 'shell.isPluginOpen("omarchy.math")' "$lock" && grep -q 'math: summoned, no time left and nothing on screen' "$lock" || fail "the lock screen re-opens Math time while there is no time"
! grep -q 'lock-requested: screen time spent' "$lock" || fail "the lock screen no longer locks at zero itself; the daemon does, a minute after an unlock that earned nothing"
grep -q 'function isPluginOpen(id: string): string' "$ROOT/shell/shell.qml" || fail "root can ask the shell whether the real Math time plugin is open"
grep -q 'session.shell_plugin_open(self.uid, "omarchy.math") is True' "$ROOT/lib/parent/omarchy_kids/screen_time/service.py" || fail "an open Math time session holds off the zero-budget relock"
grep -q '"unlock_grace_seconds": 60' "$ROOT/lib/screen-time/screen_time/config.py" || fail "a missing or closed Math time app still gets only a minute before relock"
grep -q '"grace_seconds": 10' "$ROOT/lib/screen-time/screen_time/config.py" || fail "the normal time-up countdown lasts ten seconds"
pass "no time left means Math time may stay open, with a one-minute failsafe when it is absent"

leaf="$ROOT/install/user/screen-time.sh"
grep -q 'omarchy-profile-child' "$leaf" && grep -q 'omarchy.screen-time' "$leaf" && grep -q 'bar.layout.right' "$leaf" || fail "a child install gets the pill on its bar"
grep -q 'user/screen-time.sh' "$ROOT/install/user/all.sh" || fail "the leaf runs at install"
[[ ! -e $ROOT/bin/omarchy-kids-quiz && ! -e $ROOT/bin/omarchy-kids-time-tick && ! -e $ROOT/default/parent/omarchy-kids-time-guard.service ]] || fail "the old backend and its guard are gone"
pass "the pill is on a child install's bar and the old design is retired"
