# Plan: Five modules for kids mode

Status: implemented in `peterholko/omarchy-kids`, based on the tested `build/kids-all` commit `0193e412` from `peterholko/omarchy`. The text below records the original design. See `docs/kids-modules.md` for the implemented file layout, packaging and migration behavior.

## Recommendation

Define five first-party modules in the existing repository: **Kids / Parent Password**, **DNS Filtering**, **Browsing Logging**, **Screen Time**, and **School / Free Time Mode**. Each owns its behavior, configuration, lifecycle, UI integration, and tests. Keep the current CLI and shell plugin entry points stable while moving their implementations behind those boundaries.

Start implementation by extracting code and configuration boundaries, then ship separate selectable first-party module packages built from the same repository and compatible release. Selectable installation is part of the finished design, following Peter's clarification; independent enablement alone does not complete it. The package transaction must deliver compatible commands, privileged services, and QML together.

The key outcome is that a parent can use school mode without enabling screen-time limits, or enable screen time without school mode. DNS filtering and browsing logging remain independently selectable in either mode.

## Parent selection and reuse of existing plugins

Parents choose which optional modules to install during Kids setup or later from a parent-authenticated module picker. The same actions are available through `omarchy parent plugin`. The picker and the first-party package catalog are proposed additions, not current functionality.

| Module | Installation choice | Existing implementation to reuse |
| --- | --- | --- |
| Kids / Parent Password | Required foundation for Kids setup and all four optional modules. | Parent CLI/profile helpers, operating-system authentication, and the existing polkit and lock integrations. |
| DNS Filtering | Optional, independently installable. | `omarchy-parent-dns`, resolver service, firewall/list management, and browser-policy generation. |
| Browsing Logging | Optional, independently installable. | `omarchy-parent-browsing`, its collection timer/service, history extraction, and reports. |
| Screen Time | Optional; includes Math as part of this module. | `omarchy.screen-time` and `omarchy.math` shell plugins, the time CLI, and accounting/quiz backend. |
| School / Free Time | Optional, independently installable from Screen Time. | `omarchy.school-mode`, including the existing menu, schedule panel, shortcuts, window restoration, and notification integration. |

The parent-facing operations distinguish **Install**, **Enable/Disable**, and **Remove**. Removing an optional module preserves its configuration and history unless the parent explicitly requests deletion. Show required dependencies before applying a selection. Browsing collection remains an explicit opt-in even if its code is installed as part of a preset. Core cannot be removed while dependent modules remain installed.

Reuse both existing plugin mechanisms for their respective jobs:

- **Shell plugins:** retain the existing manifest schema, plugin IDs, entry points, bar placement, and shell IPC. The module package supplies its UI plugins in the first-party discovery locations. A new DNS or browsing panel, if wanted later, can use that same shell contract; this modularization does not require inventing new feature UIs.
- **Parent plugins:** extend `bin/omarchy-parent-plugin` as the module-management entry point. It already supports add/list/remove, a catalog hook, manifests, and optional enablement. Add first-party package-backed catalog entries so it can install the selected module and its backend/UI dependencies through the existing package helpers. Preserve the existing Git add-on path separately from these packaged first-party modules.

Keep the five source modules together in `peterholko/omarchy`. Separate package outputs let parents install only selected features without requiring five Git repositories. Normal Omarchy package updates update installed modules; they do not install unselected optional features. The existing shell-plugin Git updater continues serving user-installed shell plugins and must not become an independent updater for a packaged parent's UI/backend pair.

The parent-plugin management additions need:

1. A first-party catalog mapping module IDs to packages, required core/API versions, supported lifecycle commands, and supplied shell plugin IDs. Package names remain to be finalized in the packaging work.
2. Dependency resolution and installed/enabled/healthy reporting. A shell widget being hidden must not be interpreted as the parent disabling its backend service.
3. Parent authorization for module installation, enable/disable, removal, and configuration changes; use the existing terminal or GUI privilege path as appropriate.
4. Removal that completes the module's shutdown/restoration before uninstalling it and aborts if that operation fails. Stop and remove backend resources before removing UI/code needed for restoration. Keep dependencies required by other modules.
5. Coordinated package upgrades and configuration migrations, with recovery on failure. First-party packages own their commands and files directly; they must not also create competing Git-store symlinks for those same command names.

Privileged services load root-owned installed modules. The ordinary shell plugin manager installs code under the user's configuration directory, so it supplies the presentation layer rather than the authority to change system restrictions. Keep the existing distinction between root-backed controls and school mode's session-level desktop behavior.

## What is coupled today

| Area | Current implementation | Boundary to establish |
| --- | --- | --- |
| Identity and parent authentication | `bin/omarchy-parent`, `bin/omarchy-profile-child`, `install/helpers/parent.sh`, provisioning, PAM, polkit, and `screen_time.daemon.parent_password_ok` / `check_parent` | Authentication and child identity must be available without a screen-time account or daemon. |
| DNS filtering | `bin/omarchy-parent-dns`, resolver service, resolver lists, NetworkManager/resolved integration, firewall rules, and browser policies | Mostly separate already; isolate shared file writes and installation hooks. |
| Browsing logging | `bin/omarchy-parent-browsing`, a systemd timer/service, browser-history collection, reports, and browser policies | Mostly separate already; preserve independent collection and private reports. |
| Screen time | `lib/screen-time/screen_time/`, `bin/omarchy-parent-time*`, screen-time and Math shell plugins, and lock-screen integration | Remove ownership of school schedules, school apps, mode selection, and password verification. |
| School / free time | `shell/plugins/school-mode/` plus code embedded in the time daemon, time CLI, and time configuration | Give it its own backend, enrollment, configuration, status, and commands. |

Specific coupling to remove:

- School mode currently reads `/var/lib/omarchy/parent/<user>/time/status.json` and requires `timeEnabled` before applying its desktop restrictions.
- The time daemon owns `mode.get`, `mode.set`, school app lists, and both school and bedtime periods in `blocked_periods`.
- The school settings window uses the time client's configuration API. `omarchy-parent time on` and `install/user/screen-time.sh` add both UI features.
- Parent-password retry counters belong to time accounts, although password verification is needed by other features.
- The PAM parent-unlock helper directly grants screen time. Successful parent authentication already survives the time service being off or broken; that separation must remain.
- DNS and browsing each edit Firefox's single `policies.json`; the browser installation helper also writes that file. Chromium uses separate policy files, but browser locations and policy-directory handling are duplicated.
- Screen-time settings import grade descriptions from the Math presentation plugin. Those descriptions belong to the screen-time domain and should be shared with both views.

There are two existing plugin systems: Quickshell plugins and privileged `omarchy-parent plugin` add-ons. The reuse plan above builds on them, but neither currently provides the complete lifecycle needed for these five modules. In particular, the parent add-on installer validates a manifest and links commands, but has no dependency/schema negotiation or coordinated upgrade, and removal continues even when its `off` command fails. Those gaps are implementation work, not features we can assume already exist.

## Module ownership

### 1. Kids / Parent Password (`core`)

Own the child-install profile, account resolution, parent-password integration, and the small runtime helpers the other modules share. The parent password remains the existing root password verified through the operating system; this refactor does not introduce a second credential database or PIN.

Responsibilities:

- Child/parent identity and root-versus-child caller verification.
- Parent password setup/change, sudoers/polkit policy, and the child-install portions of login/lock authentication and provisioning.
- Existing parent administrative controls such as TTY and Wi-Fi permissions.
- Shared authentication results, retry limiting, and safe configuration/file utilities.
- A small static host for the interactive time and school backends, plus capability/status discovery.

Keep ordinary provisioning and lock-screen mechanics in their existing Omarchy owners; they call narrow parent-specific adapters. The core module must not absorb the entire installer or desktop shell.

Extract password verification from `screen_time.daemon` behind an internal `authorize(peer, action, target, credential)` interface. Obtain the peer identity from the socket, never from client-supplied identity fields. Each feature decides which actions require a parent; core verifies that authorization. A child entering school is allowed; a child deliberately selecting free time needs parent authorization.

Keep verification attached to the requested operation. A QML `authenticated = true` flag must never authorize a later backend mutation. Preserve the existing settings-window behavior of checking each save, clearing its credential on close, and keeping credentials out of argv, files, logs, and public status. Use one shared password-entry component under `shell/Ui/` for checking, failure, retry, and duplicate-submit feedback. This shares presentation without replacing PAM or polkit authentication flows.

Slow password checks must run outside the countdown/schedule state lock. After verification, reacquire current state and evaluate the requested transition against the current trusted clock before committing it; a schedule boundary may have passed while the password was being checked. Keep retry state independent of screen-time enrollment, so switching features cannot reset the application's retry limit.

Core is required while any child-control module is enabled. Disabling a feature must never remove the parent password or its authorization policy.

### 2. DNS Filtering (`dns`)

Own resolver selection, domain allow/deny lists, URL/path restrictions already enforced through browser policy, dnsmasq configuration/service, NetworkManager and systemd-resolved integration, firewall restrictions, and DNS diagnostics/history.

Keep `omarchy parent dns ...` as the public interface. Filtering remains machine-wide, and the same policy applies in school and free time. DNS query history stays here; it is not a source of full browsing URLs or video titles.

Its lifecycle installs/applies/removes only DNS-owned resolver, firewall, and browser-policy contributions. Turning DNS off preserves its lists and leaves browsing collection and its policies active.

### 3. Browsing Logging (`browsing`)

Own browser-history discovery and collection, collection cursors, page/video reports, the collection timer, and the browser policies needed to retain history. Keep the existing root-owned per-user journal and `omarchy parent browsing ...` interface.

Collection stays opt-in. Turning it off stops collection and preserves existing reports; deleting stored history is a separate explicit operation. Keep raw URLs, titles, and reports out of child-readable status files.

This module does not depend on DNS, school mode, or screen time. It continues collecting in both desktop modes when enabled. Preserve the current browser coverage and sampled title-based reporting; expanding coverage or changing retention is separate work.

### 4. Screen Time (`screen-time`)

Own daily allowances, usage accounting, grants, pause/resume, bedtime and other blocking periods, warnings, locks, the ledger, earned time, and Math questions. Keep `omarchy parent time ...`, the time pill/settings, and the Math plugin as this module's interfaces.

Move the current arithmetic behavior intact: grades 1–4 retain their current fact mix, and grades 5–6 remain multiplication/division tables only. Preserve reward settings, weak-fact history, zero-budget behavior, and the parent's five-minute unlock grant.

The time module consumes an optional trusted school-policy snapshot to decide whether time is exempt from counting and enforcement. It does not choose the desktop mode or write school configuration. With school mode explicitly disabled or absent, ordinary time and bedtime rules continue without a school exemption.

Make the post-parent-unlock grant a narrow optional integration. A missing time module must never turn a valid parent login into an authentication failure. Preserve the existing user/test layouts while separating the child-install system host; do not accidentally remove those supported execution paths during relocation.

### 5. School / Free Time Mode (`school-mode`)

Own school schedules, current mode, override origin/expiry, school app lists, and reversible desktop changes: menu contents, shortcuts, window parking/restoration, and notification state. Keep the existing `omarchy.school-mode` shell plugin ID.

Add a dedicated `omarchy parent school ...` command with operations for status, enable/disable, schedule, mode, and apps. Keep `omarchy parent time school`, `time mode`, and `time school-apps` as compatibility routes to the new owner during migration.

Publish its own status and allow it to run with screen time disabled. Keep one browser profile, as currently configured. Mode changes do not alter DNS filtering or browsing collection. School app visibility must continue respecting the separate application restrictions; permanent child app restrictions remain owned by the existing apps feature, outside this refactor's five modules.

Backend authorization owns the mode transition; the shell applies the resulting desktop state. Moving the code does not make user-session menu/window restrictions a new operating-system security boundary.

## Runtime and dependency shape

    Kids / Parent Password core
      ├── DNS filtering          existing resolver service
      ├── Browsing logging       existing collector timer/service
      ├── Screen time            interactive backend + time/Math UI
      └── School / free time     interactive backend + school UI

    School policy ── optional trusted input ──> Screen-time accounting
    Parent unlock ── optional grant ─────────> Screen time

Keep time and school as separate modules in one small privileged host for the first implementation. This provides a consistent clock and an ordered policy/accounting update without adding a second daemon, polling races, or a message bus. Extract the host from the existing daemon; retain the existing service/launcher names as compatibility entry points initially. A neutral `omarchy-parentd` name can follow after extraction.

The host manages the union of users enrolled in time or school. Disabling time stops its accounting/enforcement and UI without stopping the school backend. Stop the shared host only when no hosted feature requires it. DNS and browsing keep their existing processes.

This provides independent configuration and enablement, but time and school still share a process failure domain. Separate processes are a later option if independent restart or fault isolation becomes a requirement; they are not necessary to establish the requested code boundaries.

Use direct internal interfaces, a static allowlist of first-party modules, and the current local socket transport. Load only installed/enabled modules; importing core must not require an uninstalled optional module. The catalog has separate dependency sets for Screen Time and School Mode, so neither package pulls the other in. Do not add arbitrary root-loaded code from user-writable shell plugin directories. Shell plugins remain views and session adapters.

### Contracts to establish

| Contract | Producer / owner | Consumers and rules |
| --- | --- | --- |
| Parent authorization | Core | Feature backends; failures use consistent error codes and retry information. No authority is conferred by public status. |
| School policy snapshot | School | Time receives effective mode, reason, active schedule, override expiry, and revision. UI receives only display/app-policy fields it needs. |
| Time status / budget gate | Time | Time pill, Math, and lock adapters. Keep the existing public time-status shape during migration. |
| Feature availability | Core host and feature commands | UI can distinguish installed, enabled, and healthy. An unavailable service is not interpreted as an explicit disable. |
| Browser-policy contributions | DNS and browsing | A shared file-writing adapter applies each module's owned keys while preserving other policies. |

Add schema/API versions and generation/revision information to new status interfaces. Preserve old commands and response fields through adapters until all consumers migrate. Prefer separate `school.*` and `time.*` operations over allowing either module to patch arbitrary keys in a common configuration object.

Retain an ordered backend update: evaluate school policy, apply the time decision, then publish corresponding status revisions. The time backend reads trusted in-process state rather than reading the QML view or a child-writable cache. If an enabled school backend becomes unavailable, report it and retain the last valid restrictive desktop state; do not interpret missing data as permission to select free time. Recovery and cold-start behavior require explicit acceptance coverage.

## Source and configuration layout

Suggested destination for implementation code:

    lib/parent/omarchy_parent/
      core/          authentication, identity, host, shared file utilities
      dns/           filtering implementation and policy generation
      browsing/      collection, storage, and reports
      screen_time/   accounting, ledger, quiz, and enforcement
      school_mode/   schedule, mode policy, overrides, and school settings

Keep executable metadata and thin compatibility entry points in `bin/`, shell plugins in `shell/plugins/`, shared UI controls in `shell/Ui/`, unit/default sources in `default/parent/`, and installation leaves in `install/`. Those locations are part of existing packaging and shell discovery. A module ownership table can list its files across those directories; physical colocation of every asset is not required.

Move runtime helpers out of `install/helpers/` with compatibility forwarding files while callers migrate. Keep Bash where it works; extracting DNS and browsing does not require rewriting them in Python. Preserve the existing vendored licenses and attribution for the time and school components.

Configuration changes should be limited and staged:

| Module | Configuration / state destination |
| --- | --- |
| Core | Existing child profile and parent OS authentication files; core-owned keys in `parent.conf`. |
| DNS | Existing `dns.allow`, `dns.deny`, and DNS-owned `parent.conf` keys initially. |
| Browsing | Existing `/var/lib/omarchy/parent/<user>/browsing/` state and enable marker initially. |
| Time | Existing `screen-time.json` and ledgers, with school fields extracted. |
| School | New `/etc/omarchy/parent/school-mode.json` and `/var/lib/omarchy/parent/<user>/school-mode/status.json`. |

Each module is the only semantic writer of its own configuration. Shared files such as `parent.conf` and Firefox policies require a common lock and atomic update, preserving unrelated keys. Reuse the existing browser-policy hardening helper and extend its write boundary; do not introduce a sixth browser feature. Track which keys each module contributes and preserve prior/unrelated policy values when a contribution is removed. Browser install/update must reapply enabled contributions through that same adapter.

## Behavior that the extraction must preserve

| Scenario | Required result |
| --- | --- |
| Child selects school | Allowed; outside scheduled hours it still spends time if limits are enabled. |
| Child deliberately selects free time, including `auto` that would resolve to free | Backend requires the parent password, even if free time is already current. |
| Parent selects school outside school hours | Time is exempt, except during a blocking period such as bedtime. |
| Scheduled school starts | School mode begins; a free-time choice made before that period does not suppress it. |
| Parent selects free time during the current school period | The mode exception expires at that period's end. |
| Parent password takes several seconds or is rejected | Checking feedback appears immediately; duplicate submissions are prevented; failure permits retry. |
| DNS/logging is enabled while the mode changes | Its policy and collection state remain active. |
| Parent unlocks while time is off/unavailable | Authentication succeeds; the optional time grant cannot prevent access. |

One subtle current behavior needs explicit characterization before moving code: scheduled school hours exempt time even when the parent selects free time during those hours, and the scheduled exemption currently takes precedence over overlapping blocking periods. This follows `Account.screen_time_exempt`; it is more nuanced than “school means pause, free means count.” Preserve it during extraction and treat any later policy change as a separate decision.

The intended new behavior is independent enablement: `time off` leaves an enabled school module running, and `school off` leaves time, DNS, and logging running. These lifecycle changes should be documented explicitly rather than hidden in file moves. Keep current install defaults: the parent foundation on child installs, DNS defaults, and opt-in browsing/time behavior; migrating an existing time-enabled account must also enroll it in school so its existing behavior survives.

## Incremental implementation plan

| Step | Deliverable | Completion check |
| --- | --- | --- |
| 1. Record contracts | Ownership map, baseline fixtures, explicit mode/time precedence, and existing public command/status contracts. | Current behavior is reproducible, including slow authentication, schedules, and existing laptop settings. |
| 2. Extract core helpers | Shared parent authentication, identity, file utilities, and password UI state; old imports/commands forward to them. | Parent password works independently of time enrollment; countdown and schedules continue during slow checks. |
| 3. Isolate DNS and browsing | Thin command entry points, module implementations, and coordinated browser-policy writes/install hooks. | Both work separately and together; disabling either preserves the other's policy and stored data. |
| 4. Extract school policy | Move schedule/mode/app logic into the school module, initially behind the existing time daemon APIs/configuration. | Identical outputs for existing mode, schedule, bedtime, and authentication cases. |
| 5. Separate lifecycle and storage | Split school config/status, host enrollment, commands, and UI readers. Time consumes the optional school policy interface. | School works with time off; time works with school off; legacy school-related time commands still route correctly. |
| 6. Complete deployment and cleanup | Migrations, ownership docs, compatibility checks, coordinated package delivery, and removal of obsolete internal coupling. | Upgrade and recovery pass on an existing child installation and a fresh disposable VM. |
| 7. Deliver selectable installation | Split first-party package outputs, extend the parent-plugin catalog/lifecycle, and add the module picker to Kids setup and the parent controls. | Parents can install/remove each optional module independently, with its UI and backend handled together; unselected modules remain absent through updates. |

Keep each step reviewable and behavior-preserving except the explicitly planned independent enablement. Do not combine password-policy changes, arithmetic changes, or new browsing restrictions with this refactor.

### School configuration migration

1. Under a privileged migration lock, read and back up the existing configuration and schema version. Resolve every user/profile mapping, including shared profiles.
2. Extract all `blocked_periods` entries with `mode: "free"` into school schedules, preserving labels, days, order, times, and enabled flags. Move `school_apps`; keep `mode: "block"` periods with time. Preserve allowances, earning settings, and ledgers exactly.
3. Stage and validate the new configuration before switching writers. Use a migration journal/schema marker so interruption cannot leave two authoritative writers or a partially migrated configuration. Repeated runs must safely resume or no-op.
4. Enroll currently time-managed children in school to preserve the feature they already had. Do not enable previously disabled features or create default schedules over parent choices.
5. Switch new backends to their own configuration while compatibility APIs translate old school-related commands. A legacy patch that spans both owners must use a validated coordinated transaction or be rejected intact, never half-applied.
6. Start and verify the backend, then refresh the shell. Keep the backup and compatibility reader for the supported rollback window. Rollback must reconcile post-migration edits or refuse an incompatible downgrade with a clear recovery path; restoring an old backup alone can discard parent changes.

Manual mode overrides are currently held in memory. Define the handoff before the first service restart so extraction does not silently change an active choice. If persistence is added, store it as root-owned school state, preserve the original expiry and origin, and test it as a deliberate behavior change.

Use the repository's existing `migrations/` flow for existing installations; the privileged migration helper must also be idempotent across users. New installs use the separated install leaves. A failed migration remains pending and blocks dependent work.

### Deployment

Keep feature source and plugin-management changes in `peterholko/omarchy`; package definitions live in `omarchy-pkgs`, where coordinated packaging work must split ownership into core plus four optional feature packages. The main `omarchy` package must exclude files now owned by those packages, including the optional shell plugin directories. Installing only core must leave optional feature implementation and assets absent. This is an explicit packaging step in that repository, not a change to where feature source is developed or published.

Make installation leaves, menu guards, shell imports, and lock/parent-unlock adapters check the corresponding installed capability. The child-profile marker alone is insufficient: a child installation may have no Math, DNS, browsing, or school module. Generic Omarchy setup and the shell must still load normally when those commands and plugin directories are absent.

Verify that command wrappers, Python modules, unit files, and QML come from a compatible release. Services must load root-owned installed code; user-session `$OMARCHY_PATH` continues to follow Omarchy's established environment. Add a diagnostic reporting the installed backend release and connected UI/API version so a dev-linked UI and older installed daemon are recognizable. Avoid making selective manual copies the normal update procedure.

Core plus four optional feature packages are the release target, with explicit core/API dependencies and ordered upgrades. DNS and browsing are the easiest first candidates. The shared host means separate time/school packages still need coordinated runtime compatibility. Any newly shared Python package must support missing optional submodules. Preserve Omarchy's ordinary lock/polkit UI when optional parent modules are removed.

For existing installations, preserve the currently available bundle and each feature's enabled state through the packaging transition; do not infer consent to uninstall a feature or delete its history. Parents can remove optional modules afterwards. New installations present the module selection directly. An optional “all features” installation preset may select the four packages, but it must not remain a mandatory dependency that reinstalls a parent's removed module on the next update. Existing DNS defaults apply when that module is selected, and browsing activation still requires an explicit choice.

## Verification and completion criteria

Reuse the existing focused suites: `parent-test.sh`, `parent-unlock-test.sh`, `parent-dns-test.sh`, `parent-browsing-test.sh`, `parent-time-test.sh`, `screen-time-daemon-test.sh`, `school-mode-plugin-test.sh`, `screen-time-plugin-test.sh`, and `math-plugin-test.sh`, plus Python core tests and CLI metadata/routing tests. New shell tests belong in `test/shell.d/` and use `base-test.sh`.

Add meaningful boundary coverage: separate enrollment, malformed/missing status, wrong-password retry limits across actions, slow authentication concurrent with a schedule boundary, shared browser-policy writes, interrupted migrations, shared profiles, and disabled-feature upgrades. Check all 16 installed-module subsets with core present, plus enabled/disabled combinations for installed modules, using focused integration fixtures; use a smaller representative set for graphical VM testing. Extend `parent-plugin-test.sh` for catalog resolution, dependencies, authorization paths, removal failure, and state retention. Verify package ownership, absent optional imports/UI, and updates that keep unselected modules absent.

Record existing failures separately before refactoring. Earlier validation on this Mac recorded a `parent-time-test.sh` negative-case harness failure, and Linux-only paths cannot all run there; a partial local run is not a complete baseline.

Use a disposable Linux VM for actual resolver/firewall, PAM/polkit, systemd, browser-policy, lock, and graphical acceptance checks. Verify school/free transitions, window/shortcut/DND restoration, and password checking/failure feedback in the running UI following the repository's acceptance and visual-verification guides. Include reboot, backend restart, shell restart, and updating an already-configured installation.

The refactor is complete when each feature has a clear owner, parents can choose which optional modules are actually installed, changing one optional feature leaves the others configured correctly, school and time work independently, existing parent settings and history survive update, and the laptop can update all installed pieces through one supported release path.
