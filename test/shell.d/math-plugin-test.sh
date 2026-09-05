#!/bin/bash
#
# Math time is the arithmetic app of a child install: practice at any grade,
# checked in the app, or a set that earns screen time through
# omarchy-parent-quiz. The model is pure JavaScript shared with QML, so Node
# exercises it; the wiring is asserted from the QML source.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const quiz = requireFromRoot('shell/plugins/math/MathModel.js')
const status = quiz.gateFromStatus('{"enabled":true,"school":false,"budget":0,"earnedToday":12,"usedToday":300,"cap":120,"rate":6,"questions":5,"sessionMinutes":30,"level":"grade5"}', true)
assert(status.gated, 'an empty budget on a child install is gated')
assertEqual(status.questions, 5, 'the session length comes from status.json')
assertEqual(status.sessionMinutes, 30, 'the session earnings come from status.json')
assertEqual(status.level, 'grade5', 'the parent\'s level comes along')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"level":"grade2"}', true).level, 'grade2', 'a lower level comes along')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"level":"grade9"}', true).level, 'grade5', 'an unknown level falls back to grade 5')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"rate":4,"questions":3}', true).sessionMinutes, 12, 'session minutes fall back to rate times questions')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"questions":4,"sessionMinutes":30,"creditSeconds":450}', true).creditSeconds, 450, 'the share per right answer comes along')
assertEqual(quiz.gateFromStatus('{"enabled":true,"budget":0,"questions":4,"sessionMinutes":30}', true).creditSeconds, 450, 'the share is the set over its questions when not given')
assert(!quiz.gateFromStatus('{"enabled":true,"school":true,"budget":0}', true).gated, 'school hours are not gated')
assert(!quiz.gateFromStatus('{"enabled":true,"budget":0}', false).gated, 'a default install is never gated')
assert(!quiz.gateFromStatus('not json', true).gated, 'unreadable status fails open')
assert(quiz.isForcedOpen('{"forced":true}'), 'the lock handoff is recognized as forced')
assert(!quiz.isForcedOpen('{}') && !quiz.isForcedOpen('not json'), 'manual and malformed summons are not forced')
assertDeepEqual(quiz.GRADES, [1, 2, 3, 4, 5, 6], 'six grades')
assertEqual(quiz.PRACTICE_COUNT, 10, 'a practice set is ten questions')
assertEqual(quiz.levelNumber('grade3'), 3, 'a level name becomes its number')
assertEqual(quiz.levelNumber('nonsense'), 5, 'an unknown level is grade 5')
assertEqual(quiz.levelName(2), 'grade2', 'a number becomes its level name')
assertEqual(quiz.levelName(0), 'grade5', 'an out-of-range number is grade 5')
assertEqual(quiz.gradeLabel(4), 'Grade 4', 'the picker labels a grade')
assert(quiz.gradeBlurb(1).includes('20') && quiz.gradeBlurb(1).includes('subtraction')
  && quiz.gradeBlurb(2).includes('2 to 5')
  && quiz.gradeBlurb(3).includes('division tables to 10')
  && quiz.gradeBlurb(4).includes('division tables to 12')
  && quiz.gradeBlurb(5) === 'Multiplication and division tables to 12 only'
  && quiz.gradeBlurb(6) === 'Multiplication and division tables to 12 only',
  'each grade describes small arithmetic facts and table recall')
assertDeepEqual(quiz.parseQuestion('17 What is 342 + 519?'), { id: '17', text: 'What is 342 + 519?' }, 'an earning question splits into id and text')
assertDeepEqual(quiz.parsePractice('What is 7 × 8?\t56\n'), { text: 'What is 7 × 8?', answer: '56' }, 'a practice line splits into text and answer')
assertEqual(quiz.parsePractice('What is 7 × 8?'), null, 'a practice line without an answer is refused')
assertEqual(quiz.parsePractice('What is 7 × 8?\tfifty-six'), null, 'a practice answer must be a number')
assertEqual(quiz.normalizeAnswer(' 1,234 '), '1234', 'answers drop commas and spaces')
assertDeepEqual(quiz.judgePractice('56', '56', 0), { kind: 'correct', credited: 0, budget: 0 }, 'a right practice answer is correct and earns nothing')
assertDeepEqual(quiz.judgePractice('55', '56', 0), { kind: 'wrong', expected: '' }, 'a first practice miss keeps the question')
assertDeepEqual(quiz.judgePractice('55', '56', 1), { kind: 'wrong', expected: '56' }, 'a second practice miss reveals the answer')
assertDeepEqual(quiz.judgePractice('', '56', 0), { kind: 'wrong', expected: '' }, 'an empty answer is a miss')
assert(quiz.isCalculatorAppId('omacalc'), 'the Omacalc Wayland app id is recognized')
assert(!quiz.isCalculatorAppId('libreoffice-calc'), 'a spreadsheet is not mistaken for Omacalc')
assertDeepEqual(quiz.parseAnswer('correct 360 360'), { kind: 'correct', credited: 360, budget: 360 }, 'a correct earning answer carries its credit in seconds and the budget')
assertDeepEqual(quiz.parseQuestionJson('{"ok": true, "question": {"id": "ab12", "text": "342 + 519", "reward_seconds": 180}}'), { id: 'ab12', text: '342 + 519', answer: '' }, 'an earning question comes from the daemon as JSON')
assertDeepEqual(quiz.parseQuestionJson('{"ok": true, "text": "7 × 8", "answer": 56, "kind": "table"}'), { id: '', text: '7 × 8', answer: '56' }, 'a practice question carries its answer')
assertEqual(quiz.parseQuestionJson('{"ok": false, "error": "daily_cap_reached"}').error, 'daily_cap_reached', 'a refusal carries its reason')
assert(/limit/.test(quiz.questionErrorText({ error: 'daily_cap_reached' })), 'the cap is explained')
assert(/Could not get a question/.test(quiz.questionErrorText({ error: 'no_daemon' })), 'no daemon is the plain failure')
assertEqual(quiz.questionErrorText({ error: 'daemon_timeout' }), 'Screen time did not answer. Press Enter to try again.', 'a client that never answered says so')
assertEqual(quiz.questionErrorText({ error: 'failed_to_start' }), 'Could not start the screen-time client. Press Enter to try again.', 'a client that could not start says so')
assert(/\(no daemon: \[Errno 13\] Permission denied\)/.test(quiz.questionErrorText({ error: 'no daemon: [Errno 13] Permission denied' })), 'an unfamiliar reason is shown, for the parent testing')
assertDeepEqual(quiz.parseVerdictJson('{"ok": true, "correct": true, "answer": 861, "reward_seconds": 180, "remaining_seconds": 900}'), { kind: 'correct', credited: 180, budget: 900 }, 'a right earning answer carries the seconds it earned and the budget')
assertDeepEqual(quiz.parseVerdictJson('{"ok": true, "correct": false, "answer": 861, "reward_seconds": 0}'), { kind: 'wrong', expected: '861' }, 'a miss reveals the answer at once')
assertDeepEqual(quiz.parseVerdictJson('{"ok": false, "error": "too_fast", "wait_seconds": 1.2}'), { kind: 'too_fast', wait: 1.2 }, 'too fast keeps the question')
assertEqual(quiz.parseVerdictJson('{"ok": false, "error": "expired"}').kind, 'stale', 'an expired question is stale')
assertEqual(quiz.parseVerdictJson('garbage').kind, 'error', 'no daemon is an error')
assertEqual(quiz.feedbackFor({ kind: 'too_fast', wait: 1 }, 'earn'), 'Too fast. Read it again and answer in a moment.', 'too fast is explained')
assertDeepEqual(quiz.parseAnswer('wrong 861'), { kind: 'wrong', expected: '861' }, 'a second wrong answer reveals the expected value')
assertEqual(quiz.feedbackFor({ kind: 'correct', credited: 360, budget: 360 }, 'earn'), 'Correct!', 'an earning hit says just Correct; the minutes wait for the end')
assertEqual(quiz.feedbackFor({ kind: 'correct', credited: 0, budget: 360 }, 'earn'), 'Correct!', 'a capped hit says the same')
assertEqual(quiz.feedbackFor({ kind: 'correct', credited: 0, budget: 0 }, 'practice'), 'Correct!', 'a practice hit is just right')
assertEqual(quiz.feedbackFor({ kind: 'wrong', expected: '' }, 'practice'), 'Not quite. Try once more.', 'a first miss invites another try')
assertEqual(quiz.feedbackFor({ kind: 'wrong', expected: '861' }, 'earn'), 'The answer is 861.', 'a second miss shows the answer')
assertEqual(quiz.feedbackFor({ kind: 'stale' }, 'earn'), 'That one timed out. Here is a fresh one.', 'a stale question is replaced')
assert(quiz.questionDone({ kind: 'correct', credited: 6, budget: 360 }), 'a right answer finishes the question')
assert(quiz.questionDone({ kind: 'wrong', expected: '861' }), 'a second miss finishes the question')
assert(!quiz.questionDone({ kind: 'wrong', expected: '' }), 'a first miss keeps the question')
assert(!quiz.questionDone({ kind: 'stale' }), 'a stale question is replaced, not counted')
assertEqual(quiz.progressLabel(0, 5), 'Question 1 of 5', 'progress counts from one')
assertEqual(quiz.progressLabel(4, 5), 'Question 5 of 5', 'progress reaches the last question')
assertEqual(quiz.streakLabel(1), '', 'one right is not a run')
assertEqual(quiz.streakLabel(3), '3 in a row', 'three right is a run')
assertEqual(quiz.formatDuration(45), '45 s', 'short durations are seconds')
assertEqual(quiz.formatDuration(130), '2 min 10 s', 'longer durations are minutes and seconds')
assertEqual(quiz.remainingLabel(0), 'No time left', 'an empty budget says so')
assertEqual(quiz.remainingLabel(90), '2 min left', 'a budget rounds up to minutes')
assertDeepEqual(quiz.sessionSummary('practice', 8, 10, 0, 0, 4), ['8 of 10 right', 'Best run: 4 in a row'], 'a practice summary is the score and the run, never the time taken')
assertDeepEqual(quiz.sessionSummary('earn', 5, 5, 1800, 1800, 5), ['5 of 5 right', 'Best run: 5 in a row', '+30 min of screen time earned', '30 min banked'], 'an earning summary tells the screen time gained at the end')
assertDeepEqual(quiz.sessionSummary('earn', 3, 4, 1350, 1350, 3), ['3 of 4 right', 'Best run: 3 in a row', '+22 min 30 s of screen time earned', '23 min banked'], 'a set of four for thirty tells the odd seconds too')
assertDeepEqual(quiz.sessionSummary('earn', 1, 5, 0, 0, 1), ['1 of 5 right', 'No screen time earned this time', '0 min banked'], 'a poor set says no screen time, and no run')
assertEqual(quiz.PALETTE.paper, '#ffffff', 'the sheet is white paper')
assertEqual(quiz.formatMinutes(450), '7 min 30 s', 'a share with odd seconds says both')
assertEqual(quiz.formatMinutes(45), '45 s', 'under a minute is seconds')
assert(!/min/.test(quiz.feedbackFor({ kind: 'correct', credited: 360, budget: 360 }, 'earn')), 'no minutes are mentioned per question')
JS
pass "the math model judges practice locally and shapes the earning conversation"

# A QML file's name is a type in its directory, and inside the component (and
# the JavaScript it imports) that type shadows a JavaScript global of the same
# name: as Math.qml, every Math.max and Math.round in the app threw, and the
# question drew into a zero-width column. Keep the shell clear of such names.
shadowing=$(find "$ROOT/shell" -name '*.qml' | sed 's|.*/||; s|\.qml$||' | grep -xE 'Math|Date|JSON|Number|String|Object|Array|Boolean|RegExp|Error|Promise|Map|Set|Symbol|Function|Reflect|Proxy|Intl|Qt' || true)
[[ -z $shadowing ]] || fail "a QML file is named after a JavaScript global and would shadow it: $shadowing"
qml="$ROOT/shell/plugins/math/MathTime.qml"
grep -q 'WlrLayershell.namespace: "omarchy-math"' "$qml" || fail "the app keeps a stable layer namespace"
grep -q 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive' "$qml" && grep -q 'WlrLayershell.layer: WlrLayer.Overlay' "$qml" || fail "the app holds the keyboard on the overlay layer"
grep -q 'IdleInhibitor {' "$qml" && grep -q 'enabled: root.opened' "$qml" || fail "the screen stays on while the app is open"
grep -q 'questionProc.command = \[clientPath, "quiz"\]' "$qml" || fail "an earning question comes from the daemon"
grep -q 'answerProc.command = \[clientPath, "answer", questionId, answer\]' "$qml" || fail "an earning answer goes to the daemon, which keeps the answers"
grep -q 'questionProc.command = \[clientPath, "practice", Quiz.levelName(grade)\]' "$qml" || fail "a practice question comes from the daemon's generator with its answer"
grep -q 'bin/omarchy-parent-time-client' "$qml" || fail "the app talks through the daemon's client"
! grep -q 'sudo' "$qml" || fail "the app needs no sudo grant any more"
grep -q 'readonly property bool parentBypassAvailable: forcedOpen && status.enabled && status.gated' "$qml" || fail "the parent bypass exists only after the lock-screen handoff at zero"
grep -q 'bypassProc.command = \[clientPath, "--password-stdin", "grant", "5"\]' "$qml" || fail "the bypass sends the parent password on stdin and grants five minutes"
grep -q 'if (parentBypassAvailable) openParentPrompt()' "$qml" && grep -q 'objectName: "parentPrompt"' "$qml" || fail "Escape opens the parent-password prompt on a forced Math session"
grep -q 'if (reason === "bad_password")' "$qml" && grep -q 'reason === "password_locked_out"' "$qml" || fail "the parent prompt reports a refused or rate-limited password"
grep -q 'readonly property bool showEscapeHint: !forcedOpen && !status.gated' "$qml" || fail "the Escape hint is limited to a manual session that Escape can leave"
grep -q 'root.showEscapeHint ? "  ·  Esc to leave"' "$qml" && grep -q 'root.showEscapeHint ? "  ·  Esc to stop"' "$qml" || fail "both Escape instructions follow the manual-session hint"
grep -q 'root.parentBypassAvailable ? "  ·  Esc for parent"' "$qml" || fail "a forced Math session tells the parent about Escape"
grep -q 'Quiz.judgePractice(answer, expectedAnswer, attempts)' "$qml" || fail "a practice answer is judged in the app"
grep -q 'if (status.gated) {' "$qml" && grep -q 'mode = "earn"' "$qml" || fail "with no time left the app opens straight into an earning set"
grep -q 'decidePending = true' "$qml" && grep -q 'root.decideStart()' "$qml" || fail "the app decides practice or earning on a status read taken after the summon"
grep -q 'onRunningChanged: if (!running && !launched) root.takeQuestion("", "failed_to_start")' "$qml" && grep -q 'onRunningChanged: if (!running && !launched) root.handleAnswer("")' "$qml" || fail "a client that could not start at all (runningChanged without exited) ends in the banner, not a blank"
grep -q 'id: questionWatchdog' "$qml" && grep -q 'id: answerWatchdog' "$qml" && grep -q 'questionProc.launched = false' "$qml" && grep -q 'answerProc.launched = false' "$qml" || fail "a client that hangs is given up on, and the launch flag is reset before every start"
grep -q '"Getting a question…"' "$qml" || fail "a slow question says so instead of a blank"
lock="$ROOT/shell/plugins/lock/Service.qml"
grep -Fq '"{\"forced\":true}"' "$lock" || fail "the automatic zero-budget handoff identifies itself to Math time"
grep -q 'id: timeStatusProc' "$lock" && grep -q 'command: \["cat", root.timeStatusPath\]' "$lock" || fail "the lock screen gets every status value from a serialized process"
grep -q 'if (postUnlock) postUnlockReadQueued = true' "$lock" && grep -q 'timeStatusProc.postUnlockRead = postUnlockReadQueued' "$lock" || fail "the status read requested after authentication is tagged for the Math time handoff"
grep -q 'if (!(postUnlockStatusPending && !postUnlockRead))' "$lock" && grep -q 'if (postUnlockRead) postUnlockStatusPending = false' "$lock" || fail "a read started before the parent grant is ignored until the post-authentication read finishes"
! grep -q 'timeStatusRaw = text()' "$lock" || fail "an asynchronous FileView result can never overwrite the serialized status read"
grep -q 'if (!mathSummonPending || !timeStatusFresh' "$lock" || fail "Math time waits for the post-authentication status result"
grep -q 'readonly property int level: earning ? Quiz.levelNumber(status.level) : grade' "$qml" || fail "earning is at the parent's level, practice at the kid's pick"
grep -q 'visible: root.canEarn' "$qml" || fail "the earn choice is only offered while screen time is on"
grep -q 'math-grade' "$qml" || fail "the grade she picked is remembered"
for screen in start question results; do
  grep -q "visible: root.screen === \"$screen\"" "$qml" || fail "the app has a $screen screen"
done
grep -q 'objectName: "feedback"' "$qml" && grep -q 'feedbackKind === "correct" ? good' "$qml" || fail "the verdict banner colours right and wrong apart"
grep -q 'color: root.paper' "$qml" && grep -q 'readonly property color paper: Quiz.PALETTE.paper' "$qml" || fail "the app is an opaque white sheet, not the lock screen's glass"
! grep -q 'Color\.\|Border\.surfaceSpec' "$qml" || fail "the sheet keeps its own ink on every theme"
! grep -q 'elapsedSeconds\|formatDuration' "$qml" || fail "no clock on the question screen or the results"
grep -q 'Quiz.isCalculatorAppId(toplevel.appId)) toplevel.close()' "$qml" || fail "Omacalc is closed while the app is up"
grep -q '"when":"omarchy-profile-child && omarchy-cmd-present omarchy-parent-time","action":"omarchy-shell shell summon omarchy.math' "$ROOT/default/omarchy/omarchy-menu.jsonc" || fail "the menu offers Math time when its module is installed, screen time on or off"
grep -q '^Exec=omarchy-shell shell summon omarchy.math$' "$ROOT/applications/child/Math Time.desktop" || fail "the child launcher has a Math Time entry"
pass "Math time is wired as the child install's math app"
