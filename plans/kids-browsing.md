# Kids mode, browsing history: `sudo omarchy-kids browsing`

Rev 1, 2026-09-01. Branch `kids/browsing`, cut from `kids/child-profile`; its own PR, and its own decision whether it goes upstream at all.

## Direction, and the line

Peter wants to know exactly which YouTube videos his eleven-year-old watches. DHH, on kids mode: "I don't want to build a panopticon for teenagers. Parents do what's right for their families but I'm not a fan of some of the spyware available for mobile. So for me, this is chiefly about a preteen config." Peter's answer: a debatable topic, so keep it a separate component. This branch is that component, and nothing else in kids mode depends on it.

DNS cannot answer the question: HTTPS hides the URL, so the web filter's log only ever sees `youtube.com`. The exact answer is in the browser's own history, which root can read and, with the browser told so by policy, the kid cannot erase or sidestep with a private window. A second source, the titles of the windows on screen, catches what a wiped profile would lose.

## What it does

```
sudo omarchy-kids browsing on [--user NAME]   # keep NAME's browsing history where she cannot erase it
sudo omarchy-kids browsing off                # stop keeping it; what was kept stays, root-only
sudo omarchy-kids browsing                    # status: on for whom, last collection, how much is kept
sudo omarchy-kids browsing videos [DAYS]      # YouTube videos watched, most recent first (default 7 days)
sudo omarchy-kids browsing pages [DAYS] [N]   # every page visited, most recent first
```

## Decisions

- **Off by default, per account, its own command**, like every `omarchy-kids` feature. `on` names the kid account (`--user`, or the account that invoked sudo).
- **Two sources.** Every minute, a root timer copies each browser history database the kid has (Chromium and its relatives, Firefox) and takes the visits newer than the last one it saw into a root-only log; and it asks Hyprland, through the kid's own session socket, for the titles of the windows on screen, keeping any that end in "- YouTube" as one row per minute, which is how many minutes a video was on screen. History gives the URL, the video id, and the title; the titles give what was watched even if the profile is wiped between two collections.
- **The browser is told.** While it is on, the Chromium family gets a managed policy that disables private windows and guest mode and forbids deleting history; Firefox's policies file gets private browsing disabled and history kept on shutdown. The browser shows it is managed; nothing here is hidden from the kid, and the manual tells the parent to say so.
- **Root keeps the log** under `/var/lib/omarchy/parent/<kid>/browsing/`, mode 0700, so the kid can neither read nor clear it. `off` keeps what was kept.
- **YouTube is the question, so `videos` answers it**: watch, shorts, and `youtu.be` links, grouped by video id, with the title, when it was first opened, how many times, and how many minutes it was on screen. `pages` is the plain list for everything else.
- **No new packages**: the history databases are read with the Python that Omarchy already ships.

## Naming

| What | Name |
| --- | --- |
| Command | `bin/omarchy-kids-browsing`, reached as `sudo omarchy-kids browsing ...` |
| State | `/var/lib/omarchy/parent/<kid>/browsing/` (`enabled`, `visits.tsv`, `titles.tsv`, `cursors`) |
| Units | `default/parent/omarchy-kids-browsing.{service,timer}` → `/etc/systemd/system/`, every minute while any account is on |
| Collector | `omarchy-kids-browsing collect` (root, run by the timer) |
| Browser policy | `omarchy-kids-browsing.json` in each present Chromium-family managed policy directory; `DisablePrivateBrowsing` and `SanitizeOnShutdown` merged into each present Firefox `policies.json` |
| History files read | `~/.config/chromium/*/History`, `~/.config/google-chrome/*/History`, `~/.config/BraveSoftware/Brave-Browser/*/History`, `~/.config/microsoft-edge/*/History`, `~/.mozilla/firefox/*/places.sqlite` |
| Test overrides | `OMARCHY_KIDS_STATE_DIR`, `OMARCHY_KIDS_SYSROOT` (policy and unit paths, `/run/user`), `OMARCHY_KIDS_NOW` |

## Design notes

- `visits.tsv` rows are `epoch TAB url TAB title TAB browser`; `titles.tsv` rows are `epoch TAB title`. Tabs and newlines in titles are replaced by spaces.
- Chromium stores `visits.visit_time` as microseconds since 1601-01-01; Firefox stores `moz_historyvisits.visit_date` as microseconds since 1970. `cursors` keeps, per history file, the largest visit time already taken, so a collection only reads what is new, and a file whose modification time has not moved is skipped.
- The database is copied before it is opened, since the browser holds it open, and opened read-only.
- Window titles come from `hyprctl -j clients` run as the kid with her runtime directory and the Hyprland instance signature found under `/run/user/<uid>/hypr/`; no session, no titles, no error.
- `videos` matches `youtube.com/watch?v=`, `youtube.com/shorts/`, and `youtu.be/`; the history title carries " - YouTube", the window title the same plus the browser's suffix, and both are trimmed to join the two sources.

## Tests

`test/shell.d/parent-browsing-test.sh`: the Chromium and Firefox extractors against databases the test builds with Python, with the cursor moving and a rerun taking nothing; the title collector against a stubbed `runuser` returning canned `hyprctl` JSON; `videos` and `pages` rendering from canned logs, grouped and ordered; the policy files in and out; the units' shape; the `on`/`off` sequence through the real command with `systemctl` stubbed, as namespaced root where the kernel allows.

## Manual

`manual/48-security.md`, a "Browsing history" subsection: what is kept, that the browser shows it is managed, that `videos` is the YouTube answer, and the same line as the web filter's log: tell your kid.
