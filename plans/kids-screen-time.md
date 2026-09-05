# Plan: Kids mode, phase 1 — screen time earned with math

Revision 1. Builds on phase 0 (`plans/kids-passwords.md`): the child profile, the parent password kept for root, the kid account outside `wheel`, and `omarchy-kids` as the parent's control command.

## Ask

A child install where the kid earns time on the computer by solving arithmetic at her grade level (grade 5/6). Start with the four operations; the machine must actually hold her to it, not merely suggest it.

## Shape

A **screen-time budget** per child account, owned by root. While a graphical session is unlocked the budget counts down; at zero the session locks. On the lock screen she is offered arithmetic instead of the password field; every correct answer credits minutes, root checks the answers, and once the budget is positive the normal password unlock is allowed. The parent sets the rate, the daily cap, any free minutes, and the level under `sudo omarchy-kids time`, and can grant time outright.

"Force" is delivered by root, not by the user interface: the budget and its countdown, the locking, the answer checking, and a PAM backstop on the unlock all live outside the kid's account. Her shell is only a client that shows the question and types the answer.

## What this builds on

- **Phase 0.** `omarchy-profile-child`, `omarchy-kids` with its `apply` plumbing and per-account sudoers grants (`/etc/sudoers.d/omarchy-kids-<kid>`, staged and checked by `visudo`), the parent password as root's.
- **The lock screen.** `shell/plugins/lock/` (`omarchy.lock`, a `service` plugin) locks through the compositor's session-lock protocol, authenticates with a `PamContext` against `/etc/pam.d/omarchy-lock-password`, and recovers a stranded lock if the shell dies. Its IPC target `lock` offers `lock`, `isLocked`, `status`, `preview`, `hidePreview`, and no unlock, so nothing on the kid's side can lift a lock except PAM succeeding. `bin/omarchy-apply-lock` writes the PAM stack and is what `omarchy-system-sleep-lock` and friends call.
- **PAM gates.** The fingerprint setup already inserts `pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed` into PAM stacks; the same mechanism carries a budget gate.
- **Locking from outside the session.** `bin/omarchy-shell` recovers `WAYLAND_DISPLAY` from `XDG_RUNTIME_DIR` when called from a TTY or ssh, so a root process can lock the kid's session by running it as her.
- **Conventions.** Machine state under `/var/lib/omarchy/<area>/`; `default/**` ships wholesale to `/usr/share/omarchy/default/`, so unit files there need no packaging change; system units get installed at runtime the way the provisioning units are; bar widgets follow `shell/plugins/bar/widgets/SystemUpdate.qml` (a `Process` on a `Timer`).

## Threat model, stated plainly

- Enforced by root: the budget files, the per-minute countdown, the lock at zero, the answer checking that credits time, and the PAM gate that refuses an unlock at zero budget. Killing the shell does not help: the compositor keeps the session locked and the restarted shell reclaims it (existing stranded-lock recovery). Editing state does not help: everything is root-owned. Stopping the countdown does not help: it is a root timer.
- A kid who logs in on a text console (Ctrl+Alt+F3) to work around the desktop: the tick terminates non-graphical sessions of the child account while the budget is zero, and masking `getty@tty2-6` on child installs is a one-command hardening (`omarchy-kids tty off`) worth shipping alongside.
- Not defended, by choice: a live USB (phase 0's BIOS-password advice stands), and a kid who writes a program to solve her own arithmetic, who has earned the time.
- Not a bypass to worry about: the shell's own "lock when the budget hits zero" is kid-side convenience; the root tick relocks within a minute regardless.

## Design

### 1. State: `/var/lib/omarchy/parent/<kid>/time/`

Root-owned, directory 0755, so the kid's shell can read status without privilege. Written only by the root helpers below.

- `enabled` — marker; gating is on.
- `config` — key=value: `rate` (minutes per correct answer, default 3), `cap` (minutes that can be earned per day, default 120), `free` (minutes granted at the start of each day before any question, default 0), `level` (`grade5` or `grade6`).
- `budget` — seconds remaining, integer.
- `day` — the local date the daily counters belong to; `earned` — minutes earned today.
- `question` — 0600, the pending question: id, expected answer, issued-at, attempts.
- `status.json` — 0644, rewritten by every tick and credit: `{"enabled":true,"budget":540,"earnedToday":45,"cap":120,"level":"grade5"}`. The shell reads this file and nothing else.
- `log` — one line per event (question, correct, wrong, credit, grant, lock), for `omarchy-kids time log`.

`OMARCHY_KIDS_STATE_DIR` overrides the root for tests, in the style of `OMARCHY_PROVISIONING_DIR`.

### 2. The kid-facing root helper: `bin/omarchy-kids-quiz`

Hidden, root-only, reached from the kid's shell through a NOPASSWD grant. Every subcommand has a fixed argument list so the grant can name each one exactly, and the only free-form input travels over stdin.

- `question` — generates a question for the account's level, stores it in `question` with its expected answer, prints `<id> <text>` (for example `17 What is 342 + 519?`). A new question supersedes any pending one; a pending question expires after ten minutes.
- `answer` — reads `<id> <value>` from stdin. Correct: credits `rate` minutes, bounded by today's cap, updates `budget`, `earned`, `status.json`, prints `correct <budget-seconds>`. Wrong: counts an attempt, prints `wrong` or, after the second wrong attempt, `wrong <expected>` and retires the question. Nothing else can credit time.
- `status` — prints `status.json`.
- `gate` — exit 0 when gating is off or `budget` is positive, else 1. This is the PAM backstop (§4); it runs as whichever user PAM runs as and needs no privilege, since it only reads the 0644 status.
- `--user NAME consume SECONDS` and `--user NAME credit MINUTES` — root only, for the tick and the parent's `grant`; the grant never lists these forms. `consume 0` is how the tick rolls the day over and refreshes `status.json` with nobody logged in.

Grant, written by `omarchy-kids time on` to `/etc/sudoers.d/omarchy-kids-time-<kid>` through the same stage-validate-install path as phase 0's grants:

```
<kid> ALL=(root) NOPASSWD: /usr/bin/omarchy-kids-quiz question, /usr/bin/omarchy-kids-quiz answer, /usr/bin/omarchy-kids-quiz status
```

The generator, in bash arithmetic, integers only in this phase so the answer field is a plain number:

- `grade5`: addition and subtraction with answers up to four digits; multiplication of a two-digit by a two-digit number; and exact division with a one-digit divisor. Questions and answers never exceed four digits.
- `grade6`: everything above, plus three-digit by one-digit multiplication, exact division by a two-digit divisor, and simple order of operations (`a + b × c`, `a × b − c`). Questions and answers never exceed four digits.
- Operands avoid 0, 1, and powers of ten; the operation mix is weighted so a session is not all addition. Weights and ranges live in one table at the top of the script so they are easy to tune.

### 3. The countdown: `bin/omarchy-kids-time-tick` and a system timer

`default/parent/omarchy-kids-time.timer` (every minute, `AccuracySec=10s`) and `.service` (oneshot, runs the tick as root) ship in `default/parent/`; `omarchy-kids time on` installs them to `/etc/systemd/system/` and enables the timer, the way the factory reset installs the provisioning units. The tick, for every child account with `enabled`:

- Rolls the day over at local midnight: resets `earned`, adds `free` minutes to `budget` if configured.
- Reads the account's sessions from logind (`loginctl list-sessions`, then `show-session -p Type -p Class -p Active -p LockedHint`). If any graphical session is active and not locked, subtracts 60 seconds. Sleep, the idle lock, and a locked screen all stop the clock, since they show as locked or inactive.
- At zero or below: locks every graphical session by running `omarchy-shell -q lock lock` as the kid (`runuser -u <kid> -- env XDG_RUNTIME_DIR=/run/user/<uid> OMARCHY_PATH=/usr/share/omarchy omarchy-shell -q lock lock`), and terminates the account's non-graphical sessions (`loginctl terminate-session`), logging each. The lock state itself is asked of the shell over the same IPC (`lock isLocked`), since the shell's session lock does not raise logind's `LockedHint`; a session whose shell does not answer counts as unlocked, and, if it cannot be locked, is ended.
- Rewrites `status.json` every tick so the shell's remaining-time display stays honest.

### 4. The PAM backstop

`bin/omarchy-apply-lock` writes no budget gate (Rev 2): with the budget empty the password opens the lock screen and the guard below holds the session inside _Math time_ instead. The `gate` subcommand of `omarchy-kids-quiz` stays for the tests and for a PAM stack that wants it.

### 5. Math time, the session plugin (`shell/plugins/math/`), and the guard

- `omarchy.math` is a first-party `overlay` plugin, kept loaded: a full-screen `PanelWindow` on the `Overlay` layer with exclusive keyboard focus and the namespace `omarchy-math`, an `IdleInhibitor` bound to it so the display never blanks mid-problem, and the same `sudo -n /usr/bin/omarchy-kids-quiz question` and stdin-fed `answer` calls the lock screen used to make, through the kid's passwordless grant. While the plugin is open it watches the compositor's top-level windows and closes Omacalc, including an instance already open when the session starts; the calculator remains available outside _Math time_. A session is `status.json`'s `questions` questions; the screen shows the promise ("5 questions earn 30 minutes"), the progress, the question, a digits-only field with the verdict as its placeholder, the banked time, and the elapsed time. A right answer or a second miss finishes a question, a stale one is replaced uncounted, and after the last question a results screen sums the session ("You got 4 of 5 right in 3 min 12 s. +24 min. 36 min banked."); Enter leaves, or starts another session when there is still no time. Escape leaves at any point, and the guard answers for that.
- The lock screen (`shell/plugins/lock/`) is a plain lock screen again: it shows what is banked, or "No time left: unlock to do your math", and after an unlock with an empty budget it summons the plugin through `omarchy-shell shell summon omarchy.math`. The menu offers _Math time_ on a child install with screen time on, so she can earn ahead.
- The guard is `omarchy-kids-time-tick guard`, a loop in a `Restart=always` unit that `omarchy-kids time on` installs beside the timer: every five seconds, for every account at zero budget outside school hours with an active, unlocked graphical session, it asks her Hyprland (`hyprctl -j layers`, as her, through her own runtime directory) whether the `omarchy-math` layer is up, counts a miss otherwise, and on the second miss in a row locks the session the way the tick does and logs why. A positive budget or school hours clear the count.
- The pure parts (status parsing, question and answer parsing, the session's progress and results wording) live in `shell/plugins/math/MathModel.js` with the CommonJS guard the other models use; the lock screen imports the same file for its label.

### 6. The parent's controls: `sudo omarchy-kids time`

A feature command, `bin/omarchy-kids-time`, that phase 0's `omarchy-kids` dispatches to as `omarchy-kids time ...` (root, child installs only). It shares `install_sudoers` through `install/helpers/parent.sh` and never edits `omarchy-kids`, so it can land as its own PR:

- `status` — budget, earned today, cap, level, whether gating is on.
- `on` / `off` — create or remove the state directory's `enabled` marker, install or remove the sudoers grant and the timer, rerun `omarchy-apply-lock`. `off` leaves the budget history in place.
- `rate MIN`, `cap MIN`, `free MIN`, `level grade5|grade6` — write `config`.
- `grant MIN` — credits time outright (a reward, or a homework night), logged as such.
- `log` — the event log.
- `tty off|on` — mask or unmask `getty@tty2` through `tty6` on this machine. `omarchy-kids apply` closes them on every child install (decision 4), so this is the way back.
- `school DAYS HH:MM-HH:MM ...` / `school off` / `school` — the school schedule (added on Peter's request after phase 1 landed). Windows are stored normalized in `schedule` (day digits, HHMM start and end, one per line); inside one, `omarchy-kids-quiz` reports `school` true in `status.json`, `consume` charges nothing, `gate` stands aside, and the tick neither charges nor locks, so the lock screen shows the password and the laptop is hers for schoolwork. Days accept `mon-fri`, `mon,wed,fri`, `weekdays`, `weekends`, `daily`; windows are same-day.

Later phases can add a menu entry (_Setup > Parental > Screen Time_), a bedtime schedule, and subjects beyond arithmetic; none of that changes the state or the helpers above.

### 7. Optional in this phase: a remaining-time bar widget

`shell/plugins/bar/widgets/ScreenTime.qml` with its manifest, polling `status.json` on a timer and showing minutes left with a warning color under five. Cheap, since the file is world-readable, and `omarchy-kids time on` can enable it for the kid's bar through the shell's plugin IPC; worth doing only after the gate itself works.

### 8. Tests

- `test/shell.d/parent-quiz-test.sh`: with `OMARCHY_KIDS_STATE_DIR` pointing at a scratch tree and running as namespaced root where `unshare` allows (the `dns-sudoers-test.sh` pattern), the generator produces only exact-division and non-negative problems within each level's ranges over a few hundred draws; `answer` credits exactly `rate` minutes on a correct answer, never past the cap, and nothing on a wrong one; the second wrong attempt reveals the expected answer; a stale or superseded question earns nothing; `gate` follows the budget; the sudoers grant lists exactly the three subcommands and parses with `visudo`.
- `test/shell.d/parent-time-tick-test.sh`: stubbed `loginctl` and `runuser`; the budget decrements only for an active unlocked graphical session; it holds while locked or asleep; zero locks every graphical session and terminates console sessions; midnight resets `earned` and adds `free`.
- `test/shell.d/lock-budget-gate-test.sh` asserts the lock stacks carry no gate whatever the setting; `test/shell.d/math-plugin-test.sh` covers `MathModel.js` under Node and the plugin, lock, and menu wiring from source; the tick test drives the guard with a stubbed `hyprctl`; the quiz test covers the session shape, the use counter, and the report.
- Acceptance (`test/acceptance.d/`, child VM): with gating on and the budget zeroed, `omarchy-kids-quiz gate` exits 1, the lock shows a question, a correct answer typed through the harness credits time, and the password unlock then succeeds.

### 9. Docs

`manual/48-security.md`'s "Child installs" section gains a "Screen time" subsection: how earning works, the defaults, the parent commands, and the honest limits. The agent skill's privilege note needs nothing new.

## Sequencing

1. State layout, the generator, and `omarchy-kids-quiz` with its tests.
2. The tick, the timer units under `default/parent/`, and the lock-as-the-kid path, with tests.
3. The PAM gate in `omarchy-apply-lock`, with tests.
4. `omarchy-kids time` and `tty`, the sudoers grant, and the manual.
5. The lock screen gate, its model and tests, and visual verification.
6. The bar widget, if wanted.

## Decisions

Confirmed by Peter on 2026-09-01, and revised on 2026-09-02 after the first laptop trial:

1. **Defaults.** A session is five questions at six minutes each, so thirty minutes when every answer is right; a 120-minute daily cap, no free minutes, `grade5`. (Rev 1 had three minutes per answer, one at a time.)
2. **Revealing answers.** After the second wrong attempt, show the answer and move on with no credit.
3. **The math is a session in the desktop, not a gate on the lock screen.** Rev 1 put the question on the lock screen in place of the password field, so the kid answered and then typed her password too, and the screen blanked while she worked on paper. Now: time runs out, root locks, she unlocks with her password, and _Math time_, a full-screen plugin holding the keyboard, takes the session until the batch is done; it also opens from the menu to earn ahead. Peter's reasons: one password, and a real app that can show progress, results, and timing, and grow.
4. **Root keeps its hold with a guard, not a PAM gate.** While the budget is empty, a root loop asks her Hyprland every few seconds whether the `omarchy-math` layer is up and locks the session again otherwise, with two misses in a row so a fresh unlock has a moment. The trade, accepted: a few seconds of desktop after killing the shell, and a check that trusts her compositor's answer. The countdown and the crediting stay root's, unchanged.
5. **The screen stays on** while _Math time_ is open, through an idle inhibitor; a question stays answerable for half an hour.
6. **A report to root's disk, no email.** Each finished day is filed under `reports/<date>.txt` with use, earnings, and every question with its answer, what was given, and how long it took; `omarchy-kids time report [DATE]` prints one.
7. **Console hardening.** Child installs mask the text consoles by default; `omarchy-kids tty on` reopens them.
8. **What counts.** Any unlocked graphical session burns time. Exempting particular apps is a later phase.

## Rev 3, 2026-09-03: Math time as an app

Peter's laptop trial of Rev 2 found the math session not working at all, and he asked for a proper Math application: arithmetic for grades 1 to 6, designed with a good UX for the question and the feedback, tied into screen time so that a set the kid opens herself can add to her time. Decided:

- **One app, two modes.** _Math time_ (`shell/plugins/math`, still `omarchy.math`) opens on a start screen: a grade picker from 1 to 6, remembered in `~/.local/state/omarchy/math-grade`, and a choice between _Practice_ (ten questions, always) and _Earn time_ (the parent's `questions` at the parent's `level`, offered only while screen time is on and outside school hours). With no time left it opens straight into an earning set, as before, and root's guard and the lock screen are unchanged.
- **Practice needs no root.** `omarchy-kids-quiz practice gradeN` prints the question and its answer, tab apart, with nothing recorded and no privilege, and the app judges the answer itself, the way root judges an earning one: a second try, then the answer. Earning keeps the `question`/`answer` protocol through the sudo grant, so minutes are only ever credited for a question root generated and checked, at the grade the parent set, whatever grade she practises at.
- **Grades 1 to 6 in the generator.** Grade 1 adds and takes away within 20; grade 2 within 100 with tables of 2 to 5; grade 3 the tables to 9 × 9, their divisions, and sums to a thousand; grade 4 stays within three digits, with two-digit by one-digit multiplication and exact division; grades 5 and 6 stay within four digits, with grade 6 adding three-digit by one-digit multiplication, two-digit divisors, and order of operations. `omarchy-kids time level` takes any of them.
- **The feedback is the point.** A big question, a big answer field, and a banner under it: accent-coloured "Correct!", red "Not quite. Try once more." on a first miss, red "The answer is 861." on the second, then the next question after a beat. A progress bar, "Question 3 of 10", and "4 in a row" along the top. Peter asked (2026-09-03) that a question say only Correct and the screen time gained be told at the end, so no minutes show during a set, not even the balance; the results screen carries the score, the time, the best run, and, when earning, "+30 min of screen time earned" and what is banked; _Again_ and _Done_, with only _Again_ while there is still no time.
- **In the launcher.** `applications/child/Math Time.desktop` summons it, and the menu row no longer needs screen time to be on.
- **Still to verify on the laptop**: the QML has not run under a live shell here. The laptop is where the start screen, the field, and the banner get their first look, and where the earning set is proven against the guard.
- **The ratio is one setting.** Peter asked (2026-09-03) for the questions-to-minutes ratio to be configurable through `omarchy-kids time`. `time earn QUESTIONS MINUTES` writes `questions=` and `minutes=` (a set of five for thirty by default); each right answer is worth `minutes × 60 / questions` seconds, so four for thirty is 7 min 30 s each, and the credit, the daily tally, and the cap are all in seconds now. `questions N` keeps the minutes and changes the count, `rate M` is the old way round and writes the minutes it implies, and a config from before the pair, with `rate=` alone, still reads as minutes per answer. `status.json` carries `sessionMinutes` and `creditSeconds` for the app, which tells the set's worth up front and the seconds it gained at the end.
- **A credit that lands during the unlock counts.** The parent helper credits five minutes while PAM is still authenticating, so the status file is ahead of the shell's cached copy at the moment of the unlock. Peter's laptop trials (2026-09-03) showed that merely calling `FileView.reload()` after the unlock was insufficient: a watcher-triggered load begun before PAM finished could still satisfy the "fresh" flag with zero time. FileView now signals changes without supplying values; one serialized `cat` process supplies them, ignores any read begun before PAM while the handoff is pending, and then makes the decision from a read explicitly tagged as post-unlock. Math time likewise decides practice or earning on a read taken after the summon; a parent-password unlock therefore lands on the desktop with five minutes banked.
- **The passwordless grant must sort last.** Peter's laptop showed "Could not get a question" on every unlock (2026-09-03). sudo applies the last matching rule and reads `sudoers.d` in lexical order; the kid's own grant, `omarchy-kids-<user>` (`ALL`, with the parent password), and the screen-time grant, `omarchy-kids-time-<user>` (`NOPASSWD` for question, answer, status), both match `omarchy-kids-quiz question`, and for a username starting after "t" the account grant sorted last, so `sudo -n` wanted a password and the app got no question. The grant is now `omarchy-kids-<user>-time`, which sorts after the account grant for every username, and `time on` removes the old name.

## Rev 4, 2026-09-03: on Jankees van Woezik's daemon

Peter's laptop trial of Rev 3 and his reading of [jankeesvw/omarchy-screen-time](https://github.com/jankeesvw/omarchy-screen-time) changed the direction: use that code, keep Math time full screen with at least ten questions (configurable), open it on a kid-password unlock at zero, drop the mechanisms that policed switching and closing, and keep one rule, a lock a minute after an unlock that earned nothing. Decided, with Peter's three answers (the parent password instead of the PIN; our grades ported into their generator with their weighting; `earn QUESTIONS MINUTES` kept):

- **One engine, theirs, vendored.** `lib/screen-time/` holds the daemon (MIT, licence kept, README says what changed), run as root by `omarchy-kids-timed.service` in its strict mode under our paths: `/etc/omarchy/parent/screen-time.json`, `/var/lib/omarchy/parent/screen-time/`, `/run/omarchy-kids/screen-time/sock`. `bin/omarchy-kids-timed` and `bin/omarchy-kids-time-client` wrap it; `omarchy-kids time` drives it over the client as root, which the daemon trusts without a password since sudo already asked. The old tick, quiz backend, guard, timer, and the kid's sudo grant are gone: the app talks to the daemon's socket as herself, and the daemon knows who she is from the peer credentials.
- **The parent password stands in for the PIN.** A non-root caller must send it; the daemon checks it as the kid through `runuser`/`sudo -k -S` under `Defaults rootpw`, the same route as the lock screen, with a backoff on misses on top of faillock. The panel's drawer and the settings window ask for it and send it over stdin.
- **Grades 1 to 6 in their generator**, `screen_time/quiz.py`: a kind is drawn per grade with the weights from our table, then its operands; the small facts (within 20, the tables) are remembered one by one and the big-number kinds by kind, so a fact that went wrong comes back more often, their `drill_weak`. `practice` hands the app a question with its answer and records nothing.
- **The set is the setting.** `earn.questions_per_set` (10) and `earn.set_minutes` (30) at `earn.level`; a right answer is worth `set_minutes × 60 / questions_per_set` seconds, bounded by `daily_cap_minutes` (120). `time earn`, `questions`, `rate`, `level`, `cap`, and `budget` patch the profile.
- **School is a free period, bedtime a locked one.** Their periods gained `days` and a `mode`: `free` (nothing counts, nothing locks) for `time school`, `block` for `time bedtime` and whatever the settings window adds. The panel says which one is on.
- **No time left: Math time, with a one-minute failsafe.** An unlock with the kid's password at zero opens Math time full screen (the lock screen's handoff, unchanged). While the real `omarchy.math` plugin is visibly open, the daemon suspends its relock deadline so all ten questions can take as long as needed. It asks the shell through `isPluginOpen`, and treats an unavailable answer as closed. If Math time never appears, is closed, or the shell is killed, `unlock_grace_seconds` gives it one minute before the screen locks again. In the forced post-unlock session, Escape opens a parent-password prompt whose successful five-minute grant closes Math time; a manual session keeps its ordinary Escape behavior. The lock service re-summons the app whenever the status says no time and nothing is open.
- **The bank has a hard floor at zero.** A tick spends only what remains, a negative parent grant takes at most what remains, lowering a budget normalizes the current day, and loading an older overdrawn day forgives its hidden debt. A later five-minute grant is therefore five immediately usable minutes rather than a payment against an invisible negative balance.
- **Ten seconds when time runs out.** The ordinary `grace_seconds` countdown is 10 seconds before the first lock. Config version 2 migrates version 1's stored 60-second default, while preserving other customized values and keeping the separate one-minute post-unlock Math-app failsafe.
- **One try per earning question.** The daemon judges once and reveals the answer on a miss, so the earning flow follows it; practice keeps its second try in the app.
- **The pill, the panel, and the settings window** are theirs, adapted: `omarchy.screen-time`, the panel opens Math time instead of taking answers inline, the settings pick a grade and the set instead of tables, and `install/user/screen-time.sh` puts the pill on a child install's bar from the first login (it hides itself until screen time is on). Their agreement mode is left in place, unused. The bottom-centre countdown card was removed after the laptop trial because the bar already says how much time remains and Math time owns the zero-time handoff.
- **The bridge.** The daemon writes `/var/lib/omarchy/parent/<kid>/time/status.json` on every change, the file the lock screen and Math time already read, so the unlock handoff and the app's start decision are as in Rev 3.
- **Still to verify on the laptop**: the daemon under a real logind and NetworkManager-less chroot start, the pill in the bar, the panel and settings window in a live shell, the parent password through the panel, and the minute's relock.

## Rev 5, 2026-09-03: school mode and free time, on elgevan's kids menu

Peter pointed at [elgevan/omarchy-kids-menu](https://github.com/elgevan/omarchy-kids-menu) (MIT) and asked for a school mode and a free time mode inspired by it, with no games in school mode, the web filter untouched for now, and screen time as the thing that decides. That plugin is a Kids Mode for a shared parent account: a filtered copy of the stock menu over an allowlist, a reversible Hyprland shortcut layer, the parent's windows parked on a hidden workspace, Do Not Disturb, a separate Chromium profile, and an exit through the lock screen's password. Decided:

- **The daemon owns the mode.** `lib/screen-time`: a free period (school hours) is school mode by the schedule; `mode.set` lets the kid choose school mode any time (until midnight), but only root or the parent password may make any transition back to free time. `auto` cannot be used as a password bypass when it would resolve to free. A scheduled start enters school mode even after an earlier free-time choice; the one exception is a parent deliberately choosing free time while that same school period is already active, which lasts until the period ends. A kid-chosen school mode still consumes the allowance, while a parent-authorized school mode pauses it without overriding bedtime. `status.json` carries `mode`, `modeReason`, `schoolUntil`, `schoolLabel`, and `schoolApps`; `omarchy-kids time mode school|free|auto` and `school-apps [add|remove ID...]` are the parent's, and the profile's `school_apps` list (default: the school and creativity tier without games or media) is what school mode shows.
- **Free-time authentication is destination-based.** Every deliberate choice that resolves to Free Time requires root or the parent password, even when Free Time is already effective. School Mode remains passwordless, and `auto` remains passwordless only while it resolves to the scheduled School Mode.
- **The shell follows, in `shell/plugins/school-mode`**, vendored from the kids menu and adapted: `omarchy.school-mode` is a menu, a bar widget, and a service. On a child install the service takes the stock menu's bar slot with its own button (the kids menu's slot swap, `ShellIntegration.js`), places a mode pill on the right, and, in school mode, disables the stock menu, opens its filtered copy (`Menu.qml` over the installed one, `school-menu.jsonc`: apps and Style), applies the shortcut layer (`shortcut-policy`: Music and Google Maps unbound, the browser keys and the menu keys rerouted), quiets notifications, parks the open windows (`window-session`), and launches the browser and every web app in `~/.local/share/omarchy-kids/chromium-school`. Free time reverses all of it. A "Me" install runs none of it: the service asks `omarchy-profile-child` first.
- **Dropped from the plugin**: the password exit (the daemon decides, with the parent password where it must), the allowlist editor (the parent edits the list from the terminal), the runtime staging of the helpers (they are executable in place under `/usr/share/omarchy`).
- **Kept as the kids menu had it**: the window parking, the notification restore point, the launch guard that puts a surfaced free-time window back, the stock-menu restore record travelling with the bar entry.
- **Still to verify on the laptop**: the menu slot swap and its restore on a live shell, the filtered menu opening from Super+Space in school mode, the school browser profile, the parked windows coming back, and the panel's parent-password path.
- **One browser profile.** Peter chose (2026-09-03) one Chromium profile for both modes until he knows whether she needs two, so school mode opens the browser and the web apps the ordinary way and leaves the browser keys bound as they are. The separate school profile (no YouTube login, its own bookmarks and history, under `~/.local/share/omarchy-kids/chromium-school`) stays in `SchoolBrowser.js` behind `SEPARATE_PROFILE`; turning it on also means teaching `omarchy-kids browsing` that profile's history path.
- **School hours in the School Mode panel.** Its gear asks for the parent password and opens a focused schedule editor, shaped like Screen Time's settings: several named windows, enable switches, 24-hour start and end fields, and day buttons. It replaces only school-time periods in the daemon's shared list, preserving bedtime and every other locking period. Changes apply immediately.

## Rev 6, 2026-09-04: arithmetic facts for recall

Peter asked for easier arithmetic-table questions that practise the facts children memorize, with all four operations across the grades and only multiplication and division at grades 5 and 6. Grades 1 to 4 use addition pairs from 2 through 10 (totals up to 20) and their subtraction inverses. Grade 2 introduces the tables from 2 to 5; grade 3 includes multiplication and division through 10; grade 4 reaches 12 × 12; grades 5 and 6 exclusively practise multiplication and division through 12 × 12. Ten is included in both number bonds and tables. Every question is a single fact, and the existing per-fact mistake history keeps weak facts coming back. The same generator serves practice and earning, with the existing grade settings and rewards. Math time and the parent settings share the descriptions in `MathModel.js`.
