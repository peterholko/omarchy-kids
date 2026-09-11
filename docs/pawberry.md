# Pawberry Pet Hotel

Pawberry is an optional offline math game for two- and three-digit addition/subtraction, one- through three-digit multiplication, and easy exact two-digit / one-digit division. Each visit welcomes three surprise guests from a roster of 23 pets. The original Peaches the kitten, Biscuit the puppy, and Bluebell the bunny are joined by 20 new friends. Each guest waits behind a mystery door. Checked intermediate values prepare the bed, treat, and toy, fill the progress bar, and join the visible work log. The correct final answer reveals the pet with a short burst of hearts and sparkles and a welcome message. Completing three problems shows the three earned guests together. Each completed problem also awards one unowned accessory until all 20 are collected, and every reward is saved immediately. Practice has no countdown, lives, or screen-time rewards.

Room preparation and pet rewards are separate: even when all three comforts are ready, the guest stays hidden until the final answer is correct. Incorrect answers never reveal a pet or remove earned progress. Moving to the next problem closes the door for the next guest and clears the previous room's preparation. Room preparation belongs to the current visit; pets, accessories, and equipped outfits are kept in the saved collection. Guests are chosen from uncollected pets first, with no duplicate guest within a visit. After all 23 pets are collected, friends return for more care. Accessories never repeat; once all 20 are owned, new visits continue without adding duplicates.

## Required working

| Operation | Values the child must enter before the final answer |
| --- | --- |
| Addition | Each full column total, including the incoming carry; every outgoing carry. The checked total's last digit is written on the worksheet. |
| Subtraction | The remaining donor digit, the amount received by the next column, and any group passed along across a zero; then each column difference. Original digits are crossed out and the child's checked regrouped values appear above them. |
| Multiplication | Place-value zeros for the tens/hundreds rows; each digit product including its incoming carry; every outgoing carry; each whole aligned partial product; then column totals and carries when adding the partial products. |
| Easy division | Equal groups from a two-digit / one-digit table fact, the multiplication check, and the zero remainder; then the final quotient. |

The final-answer step appears only after all preceding values are correct. Entering the whole answer early cannot skip steps. A wrong value stays on the current step, leaves checked work intact, and increments the retry count. Hints explain the method; the game does not use a timer or punish pets. Subtraction problems have nonnegative answers. Both operands use the selected number of digits. Mixed visits contain one problem of each operation.

Type digits and press Enter or **Check step**. Backspace edits, Delete clears the entry, and H toggles the hint. Escape or the Pause button pauses; losing focus also pauses until explicitly resumed. **Reveal my pet** checks the final answer, and the child can enjoy the pet and review the completed work before preparing the next room. Tab and Space operate the buttons; after an action, a dedicated input item receives answer keys so hidden buttons cannot restart or advance the visit. Reduced motion reveals pets immediately with the same welcome message, without fading, bouncing, or sparkles. Unfinished arithmetic exists only for the current visit; closing the game or choosing to start fresh discards that working while preserving every previously earned collectible.

## Pets and the accessory wardrobe

The 20 new pets are Mochi the hamster, Poppy the guinea pig, Clover the chinchilla, Hazel the hedgehog, Noodle the ferret, Maple the red panda, Pip the fox, Olive the otter, Pebble the seal pup, Sprout the turtle, Mango the parrot, Sunny the cockatiel, Waffles the duckling, Kiwi the penguin, Pudding the capybara, Tofu the alpaca, Truffle the piglet, Dottie the fawn, Juniper the raccoon, and Bubbles the axolotl.

Earn bows, hats, crowns, flower clips, star pins, scarves and bow ties in 20 color/style combinations. **Try it on** equips the newest reward on the guest just welcomed. **My collection** opens the pet album and accessory wardrobe from the menu, a completed room or visit results. Choose an owned pet, select an owned accessory, or choose **Take accessory off**. Each pet remembers one accessory; accessories are reusable across multiple pets and are never consumed. Locked accessories can be previewed but cannot be equipped, and undiscovered pets remain a mystery.

The collection uses stable pet/accessory IDs and a versioned JSON value in a Qt settings file at `$XDG_STATE_HOME/omarchy-pawberry/collection.ini`, normally `~/.local/state/omarchy-pawberry/collection.ini` on Omarchy. Saves happen immediately when a problem is completed or an outfit changes. The file belongs to the child account, survives package updates and removal, and is shared by the Kids package and standalone Pawberry plugin. It contains only collected IDs, outfits and a completed-problem count, with no personal details or answer history. Earlier versions had no saved collection to migrate. Missing or malformed collection values start an empty collection; invalid IDs and unowned outfits are ignored.

## Module boundaries

| File | Responsibility |
| --- | --- |
| `shell/plugins/pawberry/WorkSteps.js` | Pure problem generator and ordered long-arithmetic steps, with explicit effects on the worksheet. |
| `WorkSession.js` | Immutable submission, correction, pause, progress and completion rules. Every intermediate must pass before the final step. |
| `WorkBoard.qml` | Place-value columns, checked carries, regrouping, partial products and the growing answer row. |
| `HotelView.qml` | Reusable Qt Quick interface, practice selection, focused input, hints and work log. |
| `PetCatalog.js`, `PetCollection.js` | Stable pet and accessory data, new-guest selection, immutable rewards, saved-data validation and outfit rules. |
| `CollectionStore.qml` | Per-user Qt settings persistence, independent of math and the shell adapter. |
| `CollectionView.qml`, `PetPortrait.qml`, `AccessoryArt.qml` | Album, wardrobe, shared pet portraits and wearable accessory rendering. |
| `PetRoom.qml`, `HotelButton.qml` | Mystery door, discrete room comforts, explicit pet reveal, optional celebration and controls. |
| `Pawberry.qml` | Thin Quickshell window adapter, including optional School Mode allowlist filtering. |

The `omarchy-kids-pawberry` package requires only Kids core. It owns `omarchy kids pawberry`, plugin ID `omarchy.pawberry`, and the global `omarchy-pawberry.desktop` launcher. It adds an independent `pawberry` service to Kids core for parent-set daily addition/subtraction limits, without requiring School & Screen Time. Installing the package enables the core service host; it does not enroll the account in screen-time or school restrictions. The standalone plugin can play without a service; its optional limits use controls service 2.1.0 or newer. It is ready when installed and has no separate enable/disable action.

Build the checkout with `./packaging/build`, then run `./packaging/install ./build-output pawberry --user CHILD_USERNAME`. Existing selected modules are retained. With matching cached packages, `omarchy kids plugin add pawberry` and `omarchy kids plugin remove pawberry` manage it independently. Default clean conversions and future Kids ISO builds include its archive.

Parents can separately allow it under **School settings → School apps → Pawberry Pet Hotel**, after entering the parent password. The choice preserves other apps and school hours and starts off unless already allowed. The command-line equivalent is `omarchy kids school apps add omarchy-pawberry --user CHILD_USERNAME`; use `remove` to revoke it. The normal window remains subject to existing lock and screen-time controls.

## Local verification

`node --test test/pawberry/*.test.cjs` checks carries, borrowing across zeros, multiplication with internal zeros and place-value shifts, final-answer gating, rejected values, pause behavior, and complete visits. It also solves 960 generated problems and compares worksheet results, partial products, and regrouping conservation with independent arithmetic. Collection checks exercise all 23 pets and 20 accessories through and beyond completion, reward gating, reusable outfits, saved-data round trips and invalid references. `./test/kids` includes these suites and all 64 optional package combinations.

`python test/pawberry/visual.py CAPTURE_DIRECTORY`, with PySide6 Essentials, drives the actual Qt view with keyboard and mouse input. It covers a full three-pet visit, hidden guests through every intermediate and incorrect final answer, all three pet reveals, borrowing across zero, three partial products, hints, Tab/Space button activation, Enter/keypad Enter submission, focus/pause handling, reduced motion, interrupted celebrations, and compact menu/worksheet/results layouts. It also checks all 23 portraits, reward/equipment controls, locked items, collection layouts and saved rewards/outfits in a fresh Qt engine. It saves screenshots and a short reveal frame sequence. These checks do not prove Quickshell IPC, Hyprland, real package installation, lock integration or ISO boot; those remain for an Omarchy laptop. No GitHub Actions or ISO test is part of this local verification.

## Artwork

The original kitten, puppy and bunny illustration was generated with the built-in image-generation tool. The unchanged transparent PNG is bundled at `shell/plugins/pawberry/assets/pets.png`; the interface displays separate portrait regions. The [final prompt](../shell/plugins/pawberry/assets/PROMPT.md) is included. The 20 new portraits are in the unchanged transparent `assets/pets-more.png` atlas, with generation and layout prompts in [PETS-MORE-PROMPT.md](../shell/plugins/pawberry/assets/PETS-MORE-PROMPT.md). Room furniture, wearable accessories and controls are code-native. The game uses no network services, accounts or global keystroke recording, and generation does not run during play.

## Daily practice limits

`omarchy kids pawberry limits --user linnea --addition 5 --subtraction 5` is an example parent command. Both settings default to unlimited; use `0` to disable an operation or `unlimited` to remove its cap. `omarchy kids pawberry status --user linnea` reports limits, completed counts and remaining allowances. Settings apply across all difficulties and Mixed visits. Only a correct final answer after the game's intermediate steps spends an allowance. An unfinished problem or incorrect attempt never spends one. When an operation runs out mid-visit, the next pet gets an available operation.

`lib/parent/omarchy_kids/pawberry/service.py` handles Unix-socket requests in scope `pawberry`. Parent-authenticated `limits.set` patches independent `add`/`subtract` settings. `status`, `begin` and `complete` are scoped by the socket peer's UID; root can explicitly select an account. The host lock serializes mutations and atomic private writes commit before success. One outstanding problem per account prevents concurrent windows consuming the same allowance. The service verifies the final answer, rejects stale identifiers and acknowledges retries of the latest completion without charging twice. Parent changes apply at completion as well as issue time. The local calendar date advances counters once per day and never moves backwards. Settings live in `/etc/omarchy/parent/pawberry.json`; counts and pending identifiers live under `/var/lib/omarchy/parent/screen-time/pawberry/`. No parent command resets today's counts.

The UI checks intermediate work; these family controls are not a sandbox for a child who edits the plugin code or retains administrator access. The collection remains child-owned. The parent counters are separate, and editing or clearing the collection cannot restore spent practice allowances. A configured service failure keeps practice gated until it responds; only the community plugin with no installed controls client starts in standalone mode.

`python -m unittest discover -s test/parent -p test_pawberry.py` covers authentication, per-account limits, restart persistence, replay/concurrent submissions, incorrect answers, atomic-write failure, clock rollback and daily rollover. `python test/pawberry/limits_visual.py CAPTURE_DIRECTORY` drives the real Qt game against an isolated instance of that service, including quota buttons, mid-visit changes, new number choices, pending checks and service failure. It changes no OS accounts or installed services.
