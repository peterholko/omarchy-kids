# Kids mode, apps and themes: what a child install comes with

Rev 1, 2026-09-01. Branch `kids/child-apps-themes`, cut from `kids/child-profile`; its own PR after the child profile lands.

## Direction

DHH, on the child profile: "If child, then we trigger a different install profile. That's what'll include the different apps and different themes." And the boundary: "I don't want to build a panopticon for teenagers. ... for me, this is chiefly about a preteen config." Peter's daughter, eleven, is the first tester. Others are working on child-friendly themes; this branch is the infrastructure they plug into, plus one placeholder theme so a child install has somewhere to start.

## Decisions

- **The launcher is school and creativity.** Peter set the app policy for an eleven-year-old (2026-09-02) in three tiers. Visible: Chromium, LibreOffice, Files, the document, image, and media viewers, Omawrite, Omacalc, Pinta, Xournal++, Aether, Obsidian, Kdenlive, Cliamp, Google Maps. Only with supervision: YouTube (a supervised Google account with the "older kids" setting in the browser, not the unrestricted shortcut), Zoom, LocalSend, Moonlight and games, OBS Studio, WhatsApp. Removed or hidden: ChatGPT, Grok, and the other AI agents, Discord and X, Basecamp, HEY, Google Messages, Docker and Lazydocker, package and AUR installers, Disks and administrative settings, terminals and developer tools unless she is learning programming.
- **Apps are the launcher entries, the bindings, and the menu, not the package set.** The shipped launcher entries (`applications/`) are copied by `omarchy-refresh-applications`; on a child install it copies only the names in `install/omarchy-child.applications` (Google Maps, imv, mpv) plus `applications/child/` (Khan Academy, Wikipedia), and no terminal entry. The bindings keep browser, files, editor, Obsidian, Omawrite, Google Maps, Music on Cliamp, Khan Academy, and Wikipedia, and leave out Tmux, Herdr, Docker, Signal, 1Password, ChatGPT, Grok, HEY, WhatsApp, Google Messages, X, YouTube, Google Photos, Spotify. The menu hides the package and AUR installers, the AI, development, editor, terminal, and TUI rows, and the Neovim, Bash, Tmux, and Herdr learn rows; the rest, the Windows VM included, stays for the parent, who is asked for the parent password. `install/user/mise.sh` writes no agent CLI stubs on a child install. The packaged apps of the supervision and hidden tiers (LocalSend, Moonlight, OBS Studio, Disks, the terminal's own entries, btop, Neovim, the Avahi browsers) are the app list's job: `plans/kids-apps.md` ships them denied by default, with `sudo omarchy-kids apps allow` as the supervision.
- **Native packages are untouched.** Pulling packages out of the base set ripples into the install scripts and the update path (Docker's firewall rules, for one), and the app list hides and closes what is installed. `install/omarchy-child.packages` adds packages on child installs; a child app that belongs on every kid's machine goes there.
- **Themes are a list, and the list is the infrastructure.** `install/omarchy-child.themes` names the themes a child install offers, first line first; `omarchy-theme-offered` is the predicate the switcher and `omarchy-theme-list` ask; `install/user/theme.sh` starts a child install on the first name. A "Me" install offers everything, a child install without the list offers everything, and the kid's own `~/.config/omarchy/themes` is always offered. Contributors add a theme under `themes/` and name it in the list.
- **The boot screen follows.** Peter asked (2026-09-02) for the boot splash text to match the theme. Two things were in the way: Plymouth's messages were drawn in a fixed white (fixed on `fix/plymouth-message-color`, an upstream-bound branch, which also lets `omarchy-plymouth-set` run from the installer's chroot), and Bubblegum had no boot assets. It now ships `unlock.png` (the wordmark in its accent) and `preview-unlock.png`, so _Style > Unlock_ offers it, and `install/config/plymouth.sh` applies the first child theme to the boot and login screens on child installs, never failing the install if it cannot. Peter asked (2026-09-02) for the wordmark to match the theme "on login and elsewhere": the boot and login wordmark is the theme's own `unlock.png`, which Bubblegum draws in its accent, so those were already covered; the ASCII wordmark that `omarchy-show-logo` puts at the top of every menu presentation now takes the current theme's accent on a child install (truecolor), and the first-boot form repaints console colour 2 with the first child theme's accent through the Linux console's palette escape, on a console only. A "Me" install stays Omarchy green everywhere.
- **Bubblegum is the placeholder**: a light pink-and-lilac palette, `Yaru-magenta` icons, a pink keyboard, and the Catppuccin Latte editor themes, complete enough to switch to and easy to replace or rename. Its backgrounds are two pictures Peter chose for his daughter: a spring meadow in the theme's own pastels first, which the switcher previews since the theme ships no screenshot, and a painted dusk over a mountain lake second.

## Naming

| What | Name |
| --- | --- |
| Profile predicate in Lua | `o.child_install()` in `default/hypr/helpers.lua`, reading `/etc/omarchy/profile` (or `OMARCHY_PROFILE_FILE`) |
| Bindings | `default/hypr/bindings/applications.lua`, the preinstalled block split by `o.child_install()` |
| Menu | `learn.community` guarded with `"when":"! omarchy-profile-child"` |
| Theme list | `install/omarchy-child.themes` |
| Theme predicate | `bin/omarchy-theme-offered <theme>` (hidden), asked by `omarchy-theme-list` and `omarchy-theme-switcher` |
| Default theme | `install/user/theme.sh`, first name of the list on a child install |
| Placeholder | `themes/bubblegum/` |

## Tests

`test/shell.d/child-apps-themes-test.sh`: the bindings under both profiles through the Lua harness the Hyprland tests use, with no key collisions on the child set; the menu guard; `omarchy-theme-offered` against a scratch tree in both profiles, with and without the list, and for the kid's own theme; both callers asking it; the switcher's cache keyed on the list; the default theme under both profiles through `install/user/theme.sh`; and the shipped list naming real themes with a complete placeholder first.

## Later

A parent-side `omarchy-kids themes` to pick which of the offered themes the kid sees (DHH's "Themes" under `omarchy-kids`), and a real preview screenshot for Bubblegum once it has run on a machine.
