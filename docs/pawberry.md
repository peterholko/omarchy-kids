# Pawberry Pet Hotel

Pawberry is an optional offline math game for two- and three-digit addition, subtraction, and multiplication. A visit has three pets: Peaches the kitten, Biscuit the puppy, and Bluebell the bunny. Every checked value fills their room's progress bar, adds comfort, and joins the visible work log. Each completed problem settles a guest into its room. Practice has no countdown, lives, or screen-time rewards.

## Required working

| Operation | Values the child must enter before the final answer |
| --- | --- |
| Addition | Each full column total, including the incoming carry; every outgoing carry. The checked total's last digit is written on the worksheet. |
| Subtraction | The remaining donor digit, the amount received by the next column, and any group passed along across a zero; then each column difference. Original digits are crossed out and the child's checked regrouped values appear above them. |
| Multiplication | Place-value zeros for the tens/hundreds rows; each digit product including its incoming carry; every outgoing carry; each whole aligned partial product; then column totals and carries when adding the partial products. |

The final-answer step appears only after all preceding values are correct. Entering the whole answer early cannot skip steps. A wrong value stays on the current step, leaves checked work intact, and increments the retry count. Hints explain the method; the game does not use a timer or punish pets. Subtraction problems have nonnegative answers. Both operands use the selected number of digits. Mixed visits contain one problem of each operation.

Type digits and press Enter or **Check step**. Backspace edits, Delete clears the entry, and H toggles the hint. Escape or the Pause button pauses; losing focus also pauses until explicitly resumed. **Finish the room** checks the final answer, and the child can review the completed work before welcoming the next guest. Reduced motion disables the pet's small celebration bounce. Work exists only for the current visit; closing the game or choosing to start fresh discards it.

## Module boundaries

| File | Responsibility |
| --- | --- |
| `shell/plugins/pawberry/WorkSteps.js` | Pure problem generator and ordered long-arithmetic steps, with explicit effects on the worksheet. |
| `WorkSession.js` | Immutable submission, correction, pause, progress and completion rules. Every intermediate must pass before the final step. |
| `WorkBoard.qml` | Place-value columns, checked carries, regrouping, partial products and the growing answer row. |
| `HotelView.qml` | Reusable Qt Quick interface, practice selection, focused input, hints and work log. |
| `PetRoom.qml`, `HotelButton.qml` | Pet-room progress, gentle animation and controls. |
| `Pawberry.qml` | Thin Quickshell window adapter, including optional School Mode allowlist filtering. |

The `omarchy-kids-pawberry` package requires only Kids core. It owns `omarchy kids pawberry`, plugin ID `omarchy.pawberry`, and the global `omarchy-pawberry.desktop` launcher. It introduces no daemon or optional-backend dependency. It is ready when installed and has no separate enable/disable action.

Build the checkout with `./packaging/build`, then run `./packaging/install ./build-output --user CHILD_USERNAME pawberry`. Existing selected modules are retained. With matching cached packages, `omarchy kids plugin add pawberry` and `omarchy kids plugin remove pawberry` manage it independently. Default clean conversions and future Kids ISO builds include its archive.

Parents can separately allow it under **School settings → School apps → Pawberry Pet Hotel**, after entering the parent password. The choice preserves other apps and school hours and starts off unless already allowed. The command-line equivalent is `omarchy kids school apps add omarchy-pawberry --user CHILD_USERNAME`; use `remove` to revoke it. The normal window remains subject to existing lock and screen-time controls.

## Local verification

`node --test test/pawberry/work.test.cjs` checks carries, borrowing across zeros, multiplication with internal zeros and place-value shifts, final-answer gating, rejected values, pause behavior, and complete visits. It also solves 960 generated problems and compares worksheet results, partial products, and regrouping conservation with independent arithmetic. `./test/kids` includes this suite and all 128 optional package combinations.

`python test/pawberry/visual.py CAPTURE_DIRECTORY`, with PySide6 Essentials, drives the actual Qt view with keyboard and mouse input. It covers a full three-pet visit, wrong answers and hints, a blocked early final answer, borrowing across zero, three partial products, final answers, focus/pause handling, reduced motion, and compact layout. It saves screenshots and a short celebration frame sequence. These checks do not prove Quickshell IPC, Hyprland, real package installation, lock integration or ISO boot; those remain for an Omarchy laptop. No GitHub Actions or ISO test is part of this local verification.

The September 2026 local check passed 47 Python tests, seven Pawberry rule groups (including the 960 generated problems), the existing game and runnable Kids shell checks, and command metadata validation. All 128 optional module combinations passed. The real Qt interaction harness passed, and its worksheet, compact layout, pet animation and School apps screenshots were reviewed. Linux-specific checks remained skipped on macOS.

## Artwork

The original kitten, puppy and bunny illustration was generated with the built-in image-generation tool. The unchanged transparent PNG is bundled at `shell/plugins/pawberry/assets/pets.png`; the interface displays separate portrait regions. The [final prompt](../shell/plugins/pawberry/assets/PROMPT.md) is included. Room furniture and controls are code-native. The game uses no network services, accounts or global keystroke recording, and generation does not run during play.
