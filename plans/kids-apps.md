# Kids mode, app allowlist: `sudo omarchy-kids apps`

Rev 1, 2026-09-01. Branch `kids/apps`, cut from `kids/child-profile`; lands after phase 0 as its own PR, beside the web filter (`plans/kids-dns.md`) and before screen time (`plans/kids-screen-time.md`).

## What it does

A parent decides which desktop apps the kid can open. In **denylist** mode every app is available except the ones the parent denies; in **allowlist** mode only the apps the parent allows are, and anything installed later stays out until allowed. A blocked app disappears from the launcher and its program stops running for the kid, by permissions root sets and puts back, re-applied after every package install or upgrade. Off until a parent turns it on.

```
sudo omarchy-kids apps                     # status
sudo omarchy-kids apps list                # every app, allowed or blocked
sudo omarchy-kids apps denylist            # on: everything but the deny list
sudo omarchy-kids apps allowlist           # on: only the allow list (seeded from today's apps)
sudo omarchy-kids apps off
sudo omarchy-kids apps allow APP...        # by launcher name or desktop id
sudo omarchy-kids apps deny APP...
sudo omarchy-kids apps remove APP...
sudo omarchy-kids apps apply               # after editing the lists by hand
```

## Decisions

- **On by default, denylist, seeded.** Peter's launcher policy for an eleven-year-old (2026-09-02, `plans/kids-apps-themes.md`) has a supervision tier and a hidden tier of packaged apps, so a child install starts with `apps=denylist` and `/etc/omarchy/parent/apps.deny` seeded from `default/parent/apps-child.deny` the first time the list is applied: LocalSend, Moonlight, OBS Studio, the terminal's own entries (foot stays on the never-close list, so Super+Return still works), btop, Neovim, Disks, and the Avahi browsers. `install/config/parent-apps.sh` runs `omarchy-kids-apps apply --quiet` on a child install, which also installs the pacman hook; `sudo omarchy-kids apps allow NAME` is the supervision, and a parent's off is kept by later applies.
- **Enforced by permissions, not by hiding alone.** A blocked app's desktop entry loses its world-read bit, so the launcher, which reads `/usr/share/applications` as the kid, no longer lists it; and the program it starts loses its world execute bit, so a terminal cannot start it either. Both files are root's, so the kid cannot put them back. A pacman hook re-applies the lists after any transaction that touches applications or programs, since a package upgrade restores the packaged modes. The original modes are recorded so `off` and a change of mind restore exactly what was there.
- **Programs are shared, so a program is only closed when every app that uses it is blocked.** LibreOffice's Writer and Calc entries start the same `libreoffice`; deny Calc alone and its entry hides while the program stays for Writer, and `list` says so. A short never-close list keeps the interpreters and launchers a desktop entry might name (`bash`, `env`, `python`, `xdg-open`, `gtk-launch`, and the terminal emulators) out of reach of the feature entirely: closing those would break the desktop, and closing the terminal would lock the parent out of the floating terminal the menu uses to run `omarchy-kids` itself.
- **The terminal stays.** Following from the above, the terminal cannot be blocked here; the web filter and the parent password around installs are what bound what a terminal can do.
- **Web apps are the browser.** Omarchy's web app launchers live in the kid's own `~/.local/share/applications`, which she can rewrite, and each is only a browser window on a site; they are governed by the web filter and by whether the browser itself is allowed, not by this list.
- **Allowlist starts from today.** Switching to allowlist with an empty allow list seeds it with every app installed and not denied, so the switch hides nothing by surprise; from then on a newly installed app stays hidden until allowed, which is the difference between the modes.
- **Apps are named as the launcher shows them.** `deny Steam` matches an entry's `Name=` or its desktop id (`steam`, `org.gnome.Nautilus`), case aside; an ambiguous name lists the candidates and stops. The lists store ids.
- **Lists are files a parent can edit**: `/etc/omarchy/parent/apps.allow` and `apps.deny`, one id per line, `#` comments, with `apps=off|denylist|allowlist` in `/etc/omarchy/parent.conf`; `apply` picks up a hand edit.

## Naming

| What | Name |
| --- | --- |
| Command | `bin/omarchy-kids-apps`, reached as `sudo omarchy-kids apps ...` |
| Setting | `apps=off\|denylist\|allowlist` in `/etc/omarchy/parent.conf` |
| Lists | `/etc/omarchy/parent/apps.allow`, `/etc/omarchy/parent/apps.deny` (desktop ids) |
| Never closed | `default/parent/apps-never-close.list` (program basenames) |
| Record of original modes | `/var/lib/omarchy/parent/apps/restore`, `MODE PATH` per line |
| Hook | `default/parent/omarchy-kids-apps.hook` → `/etc/pacman.d/hooks/omarchy-kids-apps.hook` |
| Entries considered | `/usr/share/applications/*.desktop` and `/usr/local/share/applications/*.desktop`, `Type=Application`, not `NoDisplay` or `Hidden` |
| Programs considered | the first word of `Exec=` after any `env` and `VAR=value` words, resolved in `/usr/local/bin`, `/usr/bin`, `/bin`, following symlinks, and only under `/usr/bin`, `/usr/local/bin`, `/usr/lib`, or `/opt`, owned by root |
| Test overrides | `OMARCHY_KIDS_SYSROOT` prefixes every system path; `OMARCHY_KIDS_APPS_OWNER` is the owner a program must have (root) |

## Design

### Scan

For every desktop entry in the directories above: id (file name without `.desktop`), `Name=`, the resolved program (or none), and whether it is displayable. Ids are compared case-insensitively.

### Decision

Under denylist an entry is blocked when its id is in `apps.deny`; under allowlist when its id is not in `apps.allow`, or is in `apps.deny`. A program is closed when it resolves, is not on the never-close list, and every displayable entry that names it is blocked; otherwise it is left open, and `list` marks the blocked entry as "program shared with NAME".

### Apply

For each entry: blocked, so hide (record the mode once, `chmod o-r`); or allowed, so restore if recorded. For each program: close (record once, `chmod o-rx`) or restore if recorded. Then restore anything still recorded that this pass did not touch (an app removed from the lists, or uninstalled and gone), and drop records of files that no longer exist. A desktop entry whose mode changed is rewritten in place (copy and rename) so a running launcher, watching the directory, notices. `--quiet` prints nothing unless something changed; the hook uses it.

### Switching

`denylist` and `allowlist` document the key, set it, create the lists, seed the allow list if empty under allowlist, install the hook, and apply. `off` sets the key, restores everything recorded, removes the hook, keeps the lists. `allow`, `deny`, `remove` move ids between the lists (resolving names first) and apply under an active mode. `status` prints the mode, the counts, and whether the hook is in place; `list` prints every displayable entry with its verdict.

### Hook

```
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/share/applications/*
Target = usr/local/share/applications/*
Target = usr/bin/*
Target = usr/local/bin/*
Target = opt/*

[Action]
Description = Applying the parent's app list...
When = PostTransaction
Exec = /usr/bin/omarchy-kids-apps apply --quiet
```

### Tests

`test/shell.d/parent-apps-test.sh`. Extracted functions against `OMARCHY_KIDS_SYSROOT` with a scratch `usr/share/applications`, `usr/bin`, and `opt`, owner override to the test user: field reading and displayability; `Exec` resolution through `env`, `VAR=`, quotes, absolute paths, symlinks, and the never-close list; name resolution by id, by name, and the ambiguity refusal; the verdicts under both modes; apply hiding entries and closing programs, leaving a shared program open, restoring on a change of mind, restoring everything on off, and dropping records of vanished files; the seed under allowlist; the hook text. Then the fake-root half (Linux) running the real command through `denylist`, `deny`, `allowlist`, `off`.

### Manual

`manual/48-security.md`, an "App allowlist" subsection under Child installs: the two modes, naming apps as the launcher does, shared programs, the terminal and web apps, the pacman hook, the lists.

## What it does not stop

Anything the kid can run without a system program: a script or a binary she downloads into her home, a web app, a game inside the browser. The terminal, by choice. A program a package puts somewhere other than the directories above. Those are the web filter's and the parent password's to bound.
