# Kids namespace rename inventory

The previous implementation used `omarchy-parent` (singular); the plural `omarchy-parents` had no matches. This inventory records every affected tracked file and its original line numbers before the rename. Source history is unchanged.

## Canonical names

| Previous | Current |
| --- | --- |
| `omarchy parent …`, `omarchy-parent*` commands | `omarchy kids …`, `omarchy-kids*` |
| Five `omarchy-parent-*` module packages | Five `omarchy-kids-*` module packages |
| `omarchy_parent` Python package | `omarchy_kids` |
| `OMARCHY_PARENT_*` overrides | `OMARCHY_KIDS_*` |
| Prefixed service, policy, hook and socket names | Matching `omarchy-kids` names |

The existing `omarchy-kids-base`, `omarchy-kids-settings`, package cache and school-menu IPC name are distinct and retained. Preflight checked every destination filename, including case-insensitive matches, before moving files.

## File inventory

| Original file | Current file | Original lines |
| --- | --- | --- |
| `.github/workflows/kids.yml` | `.github/workflows/kids.yml` | 28, 29 |
| `README.md` | `README.md` | 7, 8, 9, 10, 11, 40, 41, 42, 43, 44, 45, 53, 54, 55, 56, 57, 58 |
| `applications/child/Math Time.desktop` | `applications/child/Math Time.desktop` | 5 |
| `bin/omarchy` | `bin/omarchy` | 69 |
| `bin/omarchy-apply-lock` | `bin/omarchy-apply-lock` | 26, 42, 72 |
| `bin/omarchy-parent` | `bin/omarchy-kids` | 5, 13, 22, 23, 24, 25, 50, 54, 58, 62, 65, 68, 87, 88, 120, 132, 203, 229, 230, 255, 267, 281, 282 |
| `bin/omarchy-parent-apps` | `bin/omarchy-kids-apps` | 5, 9, 22, 23, 24, 25, 42, 43, 68, 72, 78, 108, 109, 121, 268, 326, 420, 450, 462 |
| `bin/omarchy-parent-browsing` | `bin/omarchy-kids-browsing` | 5, 8 |
| `bin/omarchy-parent-client` | `bin/omarchy-kids-client` | 5 |
| `bin/omarchy-parent-dns` | `bin/omarchy-kids-dns` | 5, 8 |
| `bin/omarchy-parent-files` | `bin/omarchy-kids-files` | 5 |
| `bin/omarchy-parent-modules` | `bin/omarchy-kids-modules` | 13 |
| `bin/omarchy-parent-plugin` | `bin/omarchy-kids-plugin` | 5, 20, 21, 22, 26, 27, 28, 29, 30, 61, 66, 72, 122, 136, 224, 228, 233, 283, 332, 342, 346 |
| `bin/omarchy-parent-refresh` | `bin/omarchy-kids-refresh` | 8 |
| `bin/omarchy-parent-school` | `bin/omarchy-kids-school` | 8, 12, 13, 14, 16, 19, 20, 108 |
| `bin/omarchy-parent-school-client` | `bin/omarchy-kids-school-client` | 5 |
| `bin/omarchy-parent-time` | `bin/omarchy-kids-time` | 5, 9, 10, 11, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 68, 69, 70, 78, 79, 80, 82, 174, 180, 181, 217, 222, 260 |
| `bin/omarchy-parent-time-client` | `bin/omarchy-kids-time-client` | 5 |
| `bin/omarchy-parent-timed` | `bin/omarchy-kids-timed` | 5 |
| `bin/omarchy-parent-unlock` | `bin/omarchy-kids-unlock` | 47, 69, 71 |
| `bin/omarchy-parentd` | `bin/omarchy-kidsd` | 5 |
| `bin/omarchy-provision-owner` | `bin/omarchy-provision-owner` | 15, 733, 833, 1180, 1183 |
| `default/libalpm/hooks/95-omarchy-parent-modules.hook` | `default/libalpm/hooks/95-omarchy-kids-modules.hook` | 6, 11 |
| `default/omarchy/omarchy-menu.jsonc` | `default/omarchy/omarchy-menu.jsonc` | 25, 372, 373 |
| `default/parent/apps-child.deny` | `default/parent/apps-child.deny` | 5 |
| `default/parent/apps-never-close.list` | `default/parent/apps-never-close.list` | 1, 4 |
| `default/parent/omarchy-parent-apps.hook` | `default/parent/omarchy-kids-apps.hook` | 3, 18 |
| `default/parent/omarchy-parent-browsing.service` | `default/parent/omarchy-kids-browsing.service` | 4, 11 |
| `default/parent/omarchy-parent-browsing.timer` | `default/parent/omarchy-kids-browsing.timer` | 2 |
| `default/parent/omarchy-parent-dns.service` | `default/parent/omarchy-kids-dns.service` | 2, 4, 14, 16 |
| `default/parent/omarchy-parent-timed.service` | `default/parent/omarchy-kids-timed.service` | 11, 16 |
| `default/parent/plugins/catalog.json` | `default/parent/plugins/catalog.json` | 2, 3, 4, 5, 6 |
| `docs/file-layout.md` | `docs/file-layout.md` | 303, 315, 356 |
| `docs/kids-modules.md` | `docs/kids-modules.md` | 7, 8, 9, 13, 35 |
| `install/config/all.sh` | `install/config/all.sh` | 5, 18 |
| `install/config/parent-apps.sh` | `install/config/parent-apps.sh` | 9 |
| `install/config/parent-dns.sh` | `install/config/parent-dns.sh` | 7, 9 |
| `install/config/parent.sh` | `install/config/parent.sh` | 1, 6 |
| `install/helpers/browser-policy.sh` | `install/helpers/browser-policy.sh` | 168, 169 |
| `install/helpers/parent.sh` | `install/helpers/parent.sh` | 2 |
| `install/omarchy-child.packages` | `install/omarchy-child.packages` | 5 |
| `install/user/all.sh` | `install/user/all.sh` | 2, 5 |
| `install/user/school-mode.sh` | `install/user/school-mode.sh` | 2 |
| `install/user/screen-time.sh` | `install/user/screen-time.sh` | 2 |
| `lib/parent/omarchy_parent/__init__.py` | `lib/parent/omarchy_kids/__init__.py` | filename |
| `lib/parent/omarchy_parent/browsing/__init__.py` | `lib/parent/omarchy_kids/browsing/__init__.py` | filename |
| `lib/parent/omarchy_parent/browsing/command.sh` | `lib/parent/omarchy_kids/browsing/command.sh` | 5, 9, 22, 23, 24, 25, 26, 62, 63, 64, 67, 68, 69, 395, 400, 407, 411, 463, 475 |
| `lib/parent/omarchy_parent/core/__init__.py` | `lib/parent/omarchy_kids/core/__init__.py` | filename |
| `lib/parent/omarchy_parent/core/auth.py` | `lib/parent/omarchy_kids/core/auth.py` | filename |
| `lib/parent/omarchy_parent/core/cli.py` | `lib/parent/omarchy_kids/core/cli.py` | 5, 220, 221, 287 |
| `lib/parent/omarchy_parent/core/clock.py` | `lib/parent/omarchy_kids/core/clock.py` | filename |
| `lib/parent/omarchy_parent/core/daemon.py` | `lib/parent/omarchy_kids/core/daemon.py` | 9, 34, 36 |
| `lib/parent/omarchy_parent/core/files.py` | `lib/parent/omarchy_kids/core/files.py` | 32, 33, 66, 67 |
| `lib/parent/omarchy_parent/core/migrate.py` | `lib/parent/omarchy_kids/core/migrate.py` | filename |
| `lib/parent/omarchy_parent/core/modules.py` | `lib/parent/omarchy_kids/core/modules.py` | 1, 11, 59, 132, 154, 162, 208 |
| `lib/parent/omarchy_parent/core/parent.sh` | `lib/parent/omarchy_kids/core/parent.sh` | 1, 7, 36, 38, 51, 58 |
| `lib/parent/omarchy_parent/core/paths.py` | `lib/parent/omarchy_kids/core/paths.py` | 7, 25 |
| `lib/parent/omarchy_parent/core/periods.py` | `lib/parent/omarchy_kids/core/periods.py` | filename |
| `lib/parent/omarchy_parent/core/proto.py` | `lib/parent/omarchy_kids/core/proto.py` | filename |
| `lib/parent/omarchy_parent/core/schedule.sh` | `lib/parent/omarchy_kids/core/schedule.sh` | filename |
| `lib/parent/omarchy_parent/core/session.py` | `lib/parent/omarchy_kids/core/session.py` | filename |
| `lib/parent/omarchy_parent/core/storage.py` | `lib/parent/omarchy_kids/core/storage.py` | filename |
| `lib/parent/omarchy_parent/dns/__init__.py` | `lib/parent/omarchy_kids/dns/__init__.py` | filename |
| `lib/parent/omarchy_parent/dns/command.sh` | `lib/parent/omarchy_kids/dns/command.sh` | 5, 9, 24, 25, 26, 27, 28, 29, 30, 31, 77, 78, 84, 86, 89, 90, 91, 214, 215, 283, 285, 306, 350, 360, 373, 374, 385, 386, 494, 502, 509, 513, 520, 532, 559, 640, 656, 663, 672 |
| `lib/parent/omarchy_parent/school_mode/__init__.py` | `lib/parent/omarchy_kids/school_mode/__init__.py` | filename |
| `lib/parent/omarchy_parent/school_mode/config.py` | `lib/parent/omarchy_kids/school_mode/config.py` | 2 |
| `lib/parent/omarchy_parent/school_mode/defaults.py` | `lib/parent/omarchy_kids/school_mode/defaults.py` | filename |
| `lib/parent/omarchy_parent/school_mode/policy.py` | `lib/parent/omarchy_kids/school_mode/policy.py` | 3 |
| `lib/parent/omarchy_parent/school_mode/service.py` | `lib/parent/omarchy_kids/school_mode/service.py` | 7, 8 |
| `lib/parent/omarchy_parent/screen_time/__init__.py` | `lib/parent/omarchy_kids/screen_time/__init__.py` | filename |
| `lib/parent/omarchy_parent/screen_time/cli.py` | `lib/parent/omarchy_kids/screen_time/cli.py` | 3 |
| `lib/parent/omarchy_parent/screen_time/clock.py` | `lib/parent/omarchy_kids/screen_time/clock.py` | 3 |
| `lib/parent/omarchy_parent/screen_time/config.py` | `lib/parent/omarchy_kids/screen_time/config.py` | filename |
| `lib/parent/omarchy_parent/screen_time/daemon.py` | `lib/parent/omarchy_kids/screen_time/daemon.py` | 3, 4, 5 |
| `lib/parent/omarchy_parent/screen_time/paths.py` | `lib/parent/omarchy_kids/screen_time/paths.py` | 3 |
| `lib/parent/omarchy_parent/screen_time/proto.py` | `lib/parent/omarchy_kids/screen_time/proto.py` | 3 |
| `lib/parent/omarchy_parent/screen_time/quiz.py` | `lib/parent/omarchy_kids/screen_time/quiz.py` | filename |
| `lib/parent/omarchy_parent/screen_time/service.py` | `lib/parent/omarchy_kids/screen_time/service.py` | 9, 10 |
| `lib/parent/omarchy_parent/screen_time/session.py` | `lib/parent/omarchy_kids/screen_time/session.py` | 3 |
| `lib/parent/omarchy_parent/screen_time/state.py` | `lib/parent/omarchy_kids/screen_time/state.py` | filename |
| `lib/screen-time/README.md` | `lib/screen-time/README.md` | 3 |
| `lib/screen-time/screen_time` | `lib/screen-time/screen_time` | symlink target |
| `lib/screen-time/tests/test_core.py` | `lib/screen-time/tests/test_core.py` | 152, 316, 352, 353 |
| `manual/48-security.md` | `manual/48-security.md` | 21, 25, 29, 33, 35, 37, 41, 43, 47, 51, 55, 57, 59, 61 |
| `migrations/1788416500.sh` | `migrations/1788416500.sh` | 3, 9, 10, 28 |
| `packaging/install.py` | `packaging/install.py` | 28, 41, 61, 63, 65, 73, 90, 91, 110, 111, 113 |
| `packaging/modules.PKGBUILD` | `packaging/modules.PKGBUILD` | 1, 2, 17, 22, 24, 27, 29, 32, 34, 37, 39 |
| `packaging/modules.json` | `packaging/modules.json` | 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 18, 21, 22, 23, 30, 31, 32, 33, 36, 37, 38, 48, 49, 50 |
| `packaging/release.py` | `packaging/release.py` | 31 |
| `packaging/stage.py` | `packaging/stage.py` | 34, 52 |
| `plans/kids-apps-themes.md` | `plans/kids-apps-themes.md` | 12, 36 |
| `plans/kids-apps.md` | `plans/kids-apps.md` | 1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 23, 25, 36, 41, 44, 81, 86 |
| `plans/kids-browsing.md` | `plans/kids-browsing.md` | 1, 14, 15, 16, 17, 18, 23, 34, 36, 37, 38, 40 |
| `plans/kids-dns.md` | `plans/kids-dns.md` | 1, 3, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 43, 48, 49, 50, 51, 53, 54, 60, 71, 91, 96, 104, 136, 140, 148 |
| `plans/kids-modules.md` | `plans/kids-modules.md` | 15, 20, 21, 30, 48, 49, 50, 51, 58, 64, 94, 100, 108, 120, 137, 163 |
| `plans/kids-passwords.md` | `plans/kids-passwords.md` | 3, 12, 29, 33, 39, 42, 44, 51, 62, 79, 80, 81, 82, 84, 86, 107, 109, 121, 122, 123, 127, 128, 129, 133, 147, 163, 180, 181, 222, 237 |
| `plans/kids-screen-time.md` | `plans/kids-screen-time.md` | 3, 11, 17, 26, 42, 44, 46, 56, 59, 68, 70, 79, 83, 85, 88, 90, 97, 98, 104, 108, 111, 119, 122, 135, 136, 144, 145, 149, 151, 157, 174, 180 |
| `shell/plugins/math/MathTime.qml` | `shell/plugins/math/MathTime.qml` | 12, 33 |
| `shell/plugins/school-mode/Menu.qml` | `shell/plugins/school-mode/Menu.qml` | 79 |
| `shell/plugins/school-mode/Panel.qml` | `shell/plugins/school-mode/Panel.qml` | 34 |
| `shell/plugins/screen-time/BarWidget.qml` | `shell/plugins/screen-time/BarWidget.qml` | 108 |
| `shell/plugins/screen-time/MathModel.js` | `shell/plugins/screen-time/MathModel.js` | 3, 22, 93 |
| `shell/plugins/screen-time/Service.qml` | `shell/plugins/screen-time/Service.qml` | 5, 64 |
| `shell/plugins/screen-time/SettingsWindow.qml` | `shell/plugins/screen-time/SettingsWindow.qml` | 609 |
| `test/acceptance.d/parent-test.sh` | `test/acceptance.d/parent-test.sh` | 43, 45, 47, 68, 69, 70, 79 |
| `test/cli` | `test/cli` | 765, 767, 768, 774, 775, 778, 779, 786, 789 |
| `test/parent/test_modules.py` | `test/parent/test_modules.py` | 18, 19, 20, 21, 22, 23, 24, 25, 160 |
| `test/parent/test_packages.py` | `test/parent/test_packages.py` | 14, 27, 28, 39, 44, 78 |
| `test/parent/test_unlock.py` | `test/parent/test_unlock.py` | 22, 25 |
| `test/shell.d/fixtures/parent-plugin/bin/omarchy-parent-fixture` | `test/shell.d/fixtures/parent-plugin/bin/omarchy-kids-fixture` | 14 |
| `test/shell.d/fixtures/parent-plugin/manifest.json` | `test/shell.d/fixtures/parent-plugin/manifest.json` | 6 |
| `test/shell.d/lock-budget-gate-test.sh` | `test/shell.d/lock-budget-gate-test.sh` | 46, 57, 58, 60 |
| `test/shell.d/math-plugin-test.sh` | `test/shell.d/math-plugin-test.sh` | 5, 112, 145 |
| `test/shell.d/parent-apps-test.sh` | `test/shell.d/parent-apps-test.sh` | 5, 11, 12, 13, 15, 17, 20, 25, 31, 163, 191 |
| `test/shell.d/parent-browsing-test.sh` | `test/shell.d/parent-browsing-test.sh` | 3, 14, 15, 16, 17, 19, 21, 22, 23, 30, 133, 228, 229, 234, 235, 236 |
| `test/shell.d/parent-dns-test.sh` | `test/shell.d/parent-dns-test.sh` | 5, 11, 12, 13, 15, 17, 18, 24, 25, 31, 92, 118, 129, 192, 193, 199, 205, 227, 266, 270, 307, 320, 329 |
| `test/shell.d/parent-plugin-test.sh` | `test/shell.d/parent-plugin-test.sh` | 3, 14, 18, 19, 20, 21, 24, 25, 26, 27, 28, 30, 31, 32, 33, 34, 35, 50, 54, 55, 56, 76, 77, 89, 101, 113, 117, 122, 132, 134 |
| `test/shell.d/parent-school-test.sh` | `test/shell.d/parent-school-test.sh` | 8, 9 |
| `test/shell.d/parent-test.sh` | `test/shell.d/parent-test.sh` | 3, 14, 19, 20, 21, 23, 25, 58, 60, 62, 73, 125, 162, 166, 188, 189, 191, 194, 206, 212, 217, 224, 227, 235, 236, 237, 238, 244, 292, 296, 297, 299, 300, 303, 305, 307, 308, 312, 320, 324, 327, 329, 336, 337, 340, 343, 347, 350, 357 |
| `test/shell.d/parent-time-test.sh` | `test/shell.d/parent-time-test.sh` | 3, 15, 16, 24, 49, 50, 60, 61, 64, 65, 67, 68, 113, 123, 124, 125, 126, 127, 128 |
| `test/shell.d/parent-unlock-test.sh` | `test/shell.d/parent-unlock-test.sh` | 5, 12, 53, 54, 57, 113, 147, 150, 175, 177 |
| `test/shell.d/provision-owner-test.sh` | `test/shell.d/provision-owner-test.sh` | 39 |
| `test/shell.d/school-mode-plugin-test.sh` | `test/shell.d/school-mode-plugin-test.sh` | 141, 288 |
| `test/shell.d/screen-time-daemon-test.sh` | `test/shell.d/screen-time-daemon-test.sh` | 5, 19, 20, 21, 22, 39, 41, 42 |
| `test/shell.d/screen-time-plugin-test.sh` | `test/shell.d/screen-time-plugin-test.sh` | 25, 54, 62 |
| `test/shell.d/sudoless-docker-posture-test.sh` | `test/shell.d/sudoless-docker-posture-test.sh` | 48 |

## Upgrading an installed laptop

The module packages declare replacements and conflicts for their previous package names. The release installer retains optional modules already installed under either namespace, including disabled modules. One pacman transaction installs the compatible package set.

Before that transaction, the installer checks for conflicting destination files and local commands that would shadow the packaged commands. The package hook migrates the known PAM, sudo, polkit, systemd, NetworkManager, resolver, app-hook and browser-policy integrations. It preserves file ownership and permissions, copies originals under `/var/lib/omarchy/kids-namespace-backup`, and records pending service restarts so an interrupted migration can resume. Different files at a destination stop migration; identical files can be consolidated.

Persistent configuration and data locations such as `/etc/omarchy/parent`, `/etc/omarchy/parent.conf` and `/var/lib/omarchy/parent` retain their existing identities. DNS entries, browser-policy values and collected history are not renamed as text. Authentication requirements are preserved. “Parent password” still describes the adult’s password.

External plugin installation refuses reserved module IDs, built-in command names and commands owned by another installation. Removing a plugin removes only its own command symlinks. Existing external plugins remain reachable through `omarchy kids` even when the external repository exports its original command names.

## Intentional references to the previous names

| File | Why the previous name remains |
| --- | --- |
| `lib/parent/omarchy_kids/core/namespace.py` | Identifies installed files and command references that need migration. |
| `packaging/modules.PKGBUILD` | Replaces/conflicts/provides metadata lets pacman replace the old packages safely. |
| `packaging/install.py` | Detects old installed package names when retaining module selections. |
| `bin/omarchy-kids`, `bin/omarchy-kids-plugin` | Supports existing third-party plugin commands and prevents them from shadowing built-ins. |
| `bin/omarchy-kids-time` | Removes obsolete timers and grants under either prefix. |
| `migrations/1788416500.sh` | The historical LLM extraction uses an existing external repository and service identity; renaming its URL would point to a different repository. |
| `test/parent/test_namespace.py`, `test/parent/package-upgrade.py`, `test/shell.d/parent-plugin-test.sh` | Exercises upgrades from the real previous names and existing external plugin commands. |
| This document | Records the requested before/after inventory. |

All shipped first-party command filenames, module package names, Python imports, service names, hook names, policy filenames, runtime socket paths, CLI routes and active documentation examples use the kids namespace. CI builds both package generations and tests the actual replacement transaction in a disposable container, in addition to the module and CLI regression suites.
