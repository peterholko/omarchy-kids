# Omarchy Kids

Selectable parental-control modules for Omarchy.

| Module | Package | What it includes |
| --- | --- | --- |
| Kids / Parent Password | `omarchy-kids-core` | Required foundation: parent password, child profile controls, shared authentication, module picker and service host. |
| DNS Filtering | `omarchy-kids-dns` | Domain and page lists, resolver, firewall rules and managed browser policies. |
| Browsing Logging | `omarchy-kids-browsing` | Browser-history collection, page/video reports and its collection timer. |
| Screen Time and Math | `omarchy-kids-time` | Daily budgets, bedtime, time grants and arithmetic practice. |
| School / Free Time | `omarchy-kids-school` | School schedule, app list, desktop restrictions and password-protected free time. |

The four optional modules can be installed and removed individually. School mode works without screen time. Removing an optional module preserves its settings and history; removal first disables its services and restores its desktop or browser changes. Browsing logging is enabled only by an explicit parent action.

The existing `omarchy.screen-time`, `omarchy.math` and `omarchy.school-mode` shell plugins are reused. There is one browser profile. Grades 5 and 6 use multiplication and division tables exclusively; younger grades practice small arithmetic facts. Selecting free time always requires the parent password, and the password field shows “Checking password…” while authentication runs.

## Install on an existing child laptop

These instructions require an Omarchy laptop already configured with the **child profile**, such as an installation created with a kids ISO. They update the existing kids installation without reinstalling the OS. For initial setup, use an ISO configured for the child profile; conversion of a regular Omarchy installation into a kids installation is not implemented by this installer.

On the Omarchy laptop, open a terminal in your `omarchy-kids` checkout. Run these three commands one at a time as the regular signed-in user; the package installation steps will ask for the parent password:

```bash
omarchy pkg add base-devel python git imagemagick

./packaging/build

./packaging/install ./build-output --user CHILD_USERNAME dns browsing time school
```

Replace `CHILD_USERNAME` with the laptop’s existing child account. Optional module names may be omitted. The installer preserves modules and enrollments already present, including enabled features from the old bundled branch. Newly selected modules remain disabled until a parent enables them.

This installs a matching `omarchy-kids-base` / `omarchy-kids-settings` pair alongside the selected modules. The base pair replaces the monolithic Omarchy packages and relinquishes ownership of module files in the same pacman transaction. Do not copy these module files over an unrelated Omarchy release. Reboot once after installing to activate `/usr/share/omarchy` as `OMARCHY_PATH`; the previous source checkout is kept.

All seven package archives remain in `/var/cache/omarchy-kids/packages`, so the parent can install another module later. CI also builds an x86_64 package artifact under the repository’s Actions tab. ARM package recipes are included; ARM runtime validation remains outstanding.

## Choose modules

From the child’s session:

```bash
omarchy kids plugin pick
omarchy kids plugin list
omarchy kids plugin add school
omarchy kids plugin enable school
omarchy kids plugin disable time
omarchy kids plugin remove browsing
```

The picker is also under **Setup → Kids Modules**, and is offered during first-boot provisioning when the module packages/cache are included in an image. Administrative actions ask for the parent password. Use `--user CHILD_USERNAME` when running from another account. `add time --enable` installs and enables screen time explicitly. Installing code alone does not start logging or impose a new restriction.

Examples of independent configuration:

```bash
omarchy kids school schedule mon-fri 08:00-15:30
omarchy kids school apps add obsidian
omarchy kids school mode free
omarchy kids time bedtime 20:30-07:00
omarchy kids time level grade5
omarchy kids time earn 10 30
```

The older `time school`, `time mode` and `time school-apps` commands forward to the school module.

## Update this build

```bash
git pull --ff-only
./packaging/build
./packaging/install ./build-output --user CHILD_USERNAME
```

A successful build replaces the previous package output. The installer verifies the complete release’s checksums and updates the compatible base pair, core and currently installed optional modules together. Standard `omarchy update` continues to update system packages; it does not fetch a new kids release from this private repository. Switching to the upstream stable/edge packages is a separate migration and must not be mixed with these module packages.

The command family is `omarchy kids`, and the five module packages use the `omarchy-kids-` prefix. Upgrading a previous installation replaces its packages together and migrates the login rules, services and browser-policy filenames. Existing settings and history are preserved. Conflicting destination files or commands stop the upgrade for review; originals are backed up under `/var/lib/omarchy/kids-namespace-backup`.

The [namespace inventory](docs/kids-namespace-rename.md) lists every renamed source file and the compatibility references retained for upgrades and external plugins.

## Development and validation

```bash
./test/kids
./test/cli
```

The focused suite covers the existing password, arithmetic and browser-policy behavior; migration recovery; module lifecycle; and all 16 combinations of optional package contents. The GitHub workflow runs those suites on Linux, builds real Arch packages, and renders the shared password field for inspection. Full desktop acceptance uses the disposable-VM procedure in [the acceptance guide](agents/skills/acceptance-tests.md).

See [module architecture and migration](docs/kids-modules.md), [the original design](plans/kids-modules.md), and [upstream Omarchy](https://github.com/basecamp/omarchy). Existing source history and vendored MIT licenses are retained.
