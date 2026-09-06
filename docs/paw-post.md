# Paw Post

Paw Post is an optional typing game for Omarchy Kids, designed with an 11-year-old learner in mind. The `omarchy-kids-typing` package requires only Kids core. It is independent of Number Grove, Math Time, DNS, browsing logging and the Screen Time backend.

## Play

Home row introduces words built from the home-row keys. Word trails uses familiar words with a mix of lengths, and is the default. Story mail adds short, encouraging messages with capitals, spaces and punctuation. Prompts are curated English text bundled with the game. A shuffled deck covers the lesson before repeating, with no immediate repeat across deck boundaries.

The cozy route finishes at ten deliveries without a countdown. The optional dash lasts 90 seconds of active typing practice. Both show live accuracy and words per minute. A wrong character stays pink until Backspace corrects it; completing the exact message delivers the envelope automatically. Correcting errors does not erase them from the accuracy calculation. Round results include completed deliveries, accuracy, WPM, best streak and an encouraging badge.

The timer starts with the first printable key. Escape, loss of window focus, and automatic delivery feedback suspend active typing time. Returning to the window leaves it paused until the child resumes. Reduced motion removes envelope transitions and shortens the delivery pause. Keyboard hints use a QWERTY guide; the actual characters come from the current keyboard layout.

## Boundaries

| File | Responsibility |
| --- | --- |
| `shell/plugins/paw-post/Lessons.js` | Lesson names, curated prompts and next-key labels. |
| `TypingEngine.js` | Pure state transitions, shuffled routes, error correction, active time, accuracy, WPM and badges. Receives explicit timestamps; no Qt, file, network or backend access. |
| `TypingView.qml` | Reusable Qt Quick view, focused keyboard input, timers and animation. |
| `PostButton.qml`, `MailSprite.qml` | Original code-native controls and animated envelope. |
| `assets/cloud-post.png` | Bundled illustration of the animal destinations. |
| `PawPost.qml` | Small Quickshell window adapter and optional School Mode allowlist integration. |

The command is `omarchy kids typing`, the plugin ID is `omarchy.paw-post`, and the desktop ID is `omarchy-paw-post.desktop`. The package exclusively owns its global desktop entry; no child-directory copy is created. Parents can add `omarchy-paw-post` to School Mode's app list to allow the game during school. The normal application window remains subject to the existing lock and screen-time controls.

The game accepts keyboard events only inside its focused window. It does not inspect the clipboard, monitor global typing, create accounts, use network services or award time. Paste and held-key autorepeat do not complete prompts. Statistics exist only for the current round; closing the app discards them. Starting another route deliberately starts fresh.

WPM is `(completed characters + current correct prefix) / 5 / active minutes`, rounded to a whole number. Characters removed with Backspace are not counted twice. Accuracy is correct character attempts divided by all character attempts; Backspace itself is not an attempt. These are practice measures, not parent-controlled rewards or secure assessment scores.

## Installation

From an updated Omarchy Kids checkout, build with `./packaging/build`, then run `./packaging/install ./build-output --user CHILD_USERNAME typing`. Previously selected modules are retained. Once the matching archives are cached, `omarchy kids plugin add typing` and `omarchy kids plugin remove typing` manage the game independently. It has no enable/disable operation. Default clean conversions, `--all`, and future Kids ISO builds include it.

## Verification

Run `node --test test/paw-post/engine.test.cjs` for the deterministic typing rules, or `./test/kids` for the focused Kids checks including all 64 module combinations. On a machine with PySide6 Essentials, `python test/paw-post/visual.py /tmp/paw-post-captures` drives the actual Qt component with mouse and keyboard events. It checks lessons, correction, paste rejection, ten deliveries, case and punctuation, pause/focus behavior, resizing, reduced motion and completion of the dash. Screenshots and a short sequence of movement frames are saved for visual review.

The September 2026 local check passed 46 Python tests, nine typing-rule groups, the runnable Kids shell checks, command metadata validation, and the real Qt interaction harness. Linux-specific namespace and shortcut checks were skipped by the suite. The package tests covered all 64 optional combinations.

Component checks on macOS do not prove Quickshell IPC, Hyprland behavior, actual package installation or ISO boot. Those integration checks remain for an Omarchy laptop. No hosted workflow or ISO test is needed for the local typing-game checks.

## Artwork

The illustration was created with the built-in image-generation tool and is stored at `shell/plugins/paw-post/assets/cloud-post.png`. The original generated file was copied without modification. It is bundled for offline use; image generation does not happen while the game runs. The UI, envelope and controls are code-native. See the [generation prompt](../shell/plugins/paw-post/assets/PROMPT.md).
