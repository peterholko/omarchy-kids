# Kids module architecture

The implementation starts from `build/kids-all` at `0193e412`. One source snapshot builds a compatible base/settings pair plus five module packages. `packaging/modules.json` defines exclusive ownership; `stage.py` stages those files and removes them from both base packages. Exact package revisions tie the UI, commands and backend together. The build revision comes from the source commit count, and `release.json` records the source, dirty state and archive hashes.

## Runtime boundaries

- `lib/parent/omarchy_kids/core/`: shared OS parent authentication, peer credentials, socket transport, clock, atomic storage, parent.conf writes, Firefox policy ownership, migration and module management.
- `dns/command.sh`: DNS filtering and its resolver/firewall/browser lifecycle. The public command remains `omarchy-kids-dns`.
- `browsing/command.sh`: independently enabled history collection and reports. The public command remains `omarchy-kids-browsing`.
- `screen_time/`: budgets, accounting, bedtime and arithmetic. This module owns both the screen-time and Math shell plugins.
- `school_mode/`: school profiles, enrollment, schedules, persistent manual mode overrides and the school-mode shell plugin. It imports no screen-time code.

The root host, `omarchy-kidsd`, runs through `omarchy-kids-timed.service` and listens on `/run/omarchy-kids/screen-time/sock`. Only installed, allowlisted backend modules are loaded. Core can run with neither optional backend. DNS and browsing retain their separate service/timer lifecycles. The package hook migrates integration files from the previous namespace; see the [rename inventory](kids-namespace-rename.md).

Each socket request carries a scope (`time` or `school`), and the host identifies the caller using Unix peer credentials. A non-root caller cannot select another account. Shared authentication does not hold the accounting lock during the OS password check and throttles guesses across feature endpoints. Passwords travel over stdin and the local socket, never in command arguments. The fixed test password exists only in the explicit `SCREEN_TIME_ROOT` test layout.

The time backend consumes a narrow school-policy snapshot. Scheduled school time retains the tested accounting precedence; a child’s manual school choice outside scheduled hours still counts down, while a parent’s choice exempts it unless bedtime applies. A parent’s free-time exception during school expires at the period boundary. New manual choices survive host restarts until their expiry.

## Independent configuration and state

| Module | Settings | State / public status |
| --- | --- | --- |
| Core | `/etc/omarchy/parent.conf`, existing sudo/polkit configuration | Shared clock and migration journal beside module configuration |
| DNS | Own `dns*` parent.conf keys and `/etc/omarchy/parent/` lists | DNS service and generated network/browser policy |
| Browsing | Own enrollment markers | `/var/lib/omarchy/parent/USER/browsing/` |
| Time | `/etc/omarchy/parent/screen-time.json`, version 3 | Existing ledger under `/var/lib/omarchy/parent/screen-time/`; `USER/time/status.json` |
| School | `/etc/omarchy/parent/school-mode.json`, version 1 | Persistent overrides under `school-mode/UID/`; `USER/school-mode/status.json` |

Time and school retain independent profiles and per-user mappings. School’s `blocked_periods` key is retained for client compatibility but accepts only school (`free`) periods. Time accepts only blocking periods. Mixed legacy patches are rejected before any save. Public status files contain no password or authentication token. The school UI retains the last valid policy if a status read fails; only an explicit disabled status releases its active policy.

Shared parent.conf updates are locked and atomic. Firefox’s single policies.json is composed from a saved baseline plus independent DNS/browsing contributions; removing one preserves the other and unrelated policies. Chromium-family policies remain separate feature-owned files.

## Lifecycle and migration

`omarchy kids plugin` delegates the five first-party IDs to a package manager while retaining the existing Git-plugin path for external add-ons. Dependencies are resolved before installation. Core is required and cannot be removed from a child install. The module picker distinguishes install, enable, disable and remove; diagnostics report installation, enablement and service health where available.

Before removing school mode, the manager disables it and waits for the live shell to restore notifications, shortcuts and hidden windows. Failure leaves the package installed for repair/retry. Removing screen time leaves school enrollment intact, and vice versa. Shared services remain running while either has managed users. Package transactions reload the backend, and the manager restarts active shells to discover the new package contents.

The old combined config is split before the host opens its socket. The original is saved as `screen-time.json.before-kids-modules`; a durable journal allows an interrupted two-file migration to replay. Existing profiles, enrollment mappings, schedules, app lists and time ledgers are retained. Conflicting independently created school profiles stop migration rather than overwrite them. Version-1 default grace periods retain the prior conversion to ten seconds.

The old daemon kept manual overrides only in memory. Migration carries a published manual school restriction forward until midnight. An old free-time exception returns to the schedule and requires fresh parent authentication. Subsequent overrides use persistent school-owned state. Legacy generated Firefox policy keys are adopted into an ownership ledger, with a pre-migration policies.json backup.

Disabling or removing a module keeps its configuration, lists and collected history. Data deletion is deliberately separate; this release has no bulk history-purge action. Core remains required while the laptop uses the child profile.

## Validation limits

`test/kids` runs the module-boundary tests and focused Bash, Node and Python regressions. Package subset tests start the real core using only the staged files for each of the 16 optional combinations. Linux CI builds the actual split packages and renders the password field. The complete login/lock/network/desktop path and fresh-ISO provisioning require the disposable Omarchy VM acceptance suite; a component render is not a replacement for that acceptance run.

The installer targets an existing child-profile laptop. Building a new ISO also requires including this release’s packages and cache in that image. No package repository, ISO or changes to other GitHub repositories are published by this implementation.
