# Number Grove

Number Grove is an original arithmetic grid game distributed as `omarchy-kids-grove`. The module depends only on `omarchy-kids-core`. It introduces no root service, new password, browser requirement or external network connection.

## Boundaries

| Component | Responsibility |
| --- | --- |
| `shell/plugins/number-grove/GameEngine.js` | Pure board generation, movement, collision, difficulty, scoring and round state. No Qt or service dependencies. |
| `Facts.js` | Standalone practice questions and six distinct answer choices. Grades 1–4 build number facts; grades 5–6 use multiplication/division through 12 only. |
| `GameView.qml` | Portable Qt Quick interface, keyboard input, pause/focus handling and session/request state. It emits reward requests and accepts replies. |
| `SeedSprite.qml`, `GroveButton.qml` | Original geometric characters and controls. No borrowed game artwork, sounds or assets. |
| `NumberGrove.qml` | Quickshell plugin and ordinary application window. It obeys the optional School Mode service's application allowlist. |
| `RewardBridge.qml` | Optional public time-status reader and asynchronous subprocess adapter, with timeout, cancellation and stale-request handling. |
| `lib/parent/omarchy_kids/number_grove/rewards.py` | Narrow unprivileged client for the existing `time` quiz protocol. |

The launcher is `omarchy kids grove`, the shell plugin ID is `omarchy.number-grove`, and the desktop ID is `omarchy-number-grove.desktop`. The package owns the global desktop entry directly; it is not copied into the child's application directory. These names are separate from Math Time and the existing `omarchy.math` plugin.

## Practice and rewards

Practice questions are generated and checked locally. Each round covers ten facts with three hearts, score and streaks. Correct answers increase the pace of wandering bugs; calm mode leaves them resting. Every board keeps its numbered seeds reachable. Pausing, switching away, question loading and answer feedback stop the game clock. A wrong fact stays on screen until the child continues.

Reward mode requests `{"scope":"time","cmd":"quiz.next","choices":6}`. The server returns six shuffled candidates without marking the answer. Clients that omit `choices` keep the existing Math Time response. Only a normal `quiz.answer` request can earn time; the server identifies the account from Unix peer credentials and controls the grade, question ID, answer delay, expiry, reward rate and daily cap. The client cannot select another child or grant minutes. An answer cannot earn after the parent disables rewards. Wrong, expired or replayed answers cannot add time.

The game displays only confirmed credits. Closing or starting a new round invalidates pending UI requests. It never retries an uncertain answer automatically, because the server may already have recorded it; the time ledger remains authoritative. Math Time and Grove share one pending quiz question per child, so opening a new question in either invalidates the other's old question gracefully.

Without Screen Time, practice remains available. Installing or removing School Mode, DNS or browsing logging does not change the package dependencies. When School Mode is installed, parents can add `omarchy-number-grove` to its app list to permit practice during school; otherwise the game window is hidden and paused. With an exhausted time budget, the existing lock/Math Time flow remains in charge. Grove uses a normal application window and does not replace the lock screen or force an earning session.

## Install and remove

Build the updated checkout on Omarchy, then include `grove` in `./packaging/install ./build-output --user CHILD_USERNAME grove`. The installer retains the previously installed modules. `--all` and a default clean conversion also include Grove. Future Kids ISO builds include the same package in the offline mirror.

Once the matching archives are cached, `omarchy kids plugin add grove` and `omarchy kids plugin remove grove` manage it individually. Grove is an application, so it has no separate enable/disable operation. Parent authentication still applies to package changes. Screen-time rewards use the parent's existing Screen Time settings.

## Local verification

Run `./test/kids` on Omarchy for game rules, reward contract and module-staging tests alongside the existing Kids regressions. `node --test test/number-grove/engine.test.cjs` runs the standalone rules tests. Package tests exercise all 32 combinations of optional modules and ensure Grove alone does not load the time or school backend.

The actual reusable interface can also be checked locally with PySide6 Essentials:

```bash
python3 -m venv /tmp/number-grove-qt
/tmp/number-grove-qt/bin/pip install PySide6-Essentials
/tmp/number-grove-qt/bin/python test/number-grove/visual.py /tmp/number-grove-captures
```

This drives keyboard/mouse input through a real Qt Quick window, completes correct and incorrect rounds, checks movement timing and pause/focus behavior, resizes the view, and injects delayed, stale and capped reward replies. It saves screenshots for inspection. It does not verify Quickshell IPC, Hyprland application filtering, the lock screen, package installation or ISO boot. Those integration checks still need an Omarchy laptop; no hosted build or ISO test is required to run the local checks.

The September 2026 development check ran on macOS: 45 Python tests, seven game-rule groups, the runnable Kids shell checks, and command metadata validation passed. The Qt harness completed both practice outcomes and optional reward/error flows. Linux user-namespace and shortcut checks were skipped by the suite. The full CLI suite could not run through macOS's old `/bin/bash`; its command metadata and the Grove route were checked explicitly using Bash 5. Actual Omarchy window, lock and installation integration remains unverified for this addition.
