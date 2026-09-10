"""Public documentation for each exported repository."""
PREFIX = 'io.github.peterholko.'


def readme(name, repository, title, description):
    plugin = PREFIX + name
    service = name in {'screen-time', 'school-mode'}
    game = name in {'number-grove', 'paw-post', 'pawberry'}
    icon_directory = '$HOME/.local/share/icons/hicolor/512x512/apps'
    icon_install = (f'mkdir -p "{icon_directory}"\n'
                    f'ln -sfn "$HOME/.config/omarchy/plugins/{plugin}/assets/launcher.png" "{icon_directory}/{plugin}.png"\n') if game else ''
    icon_remove = f'rm -f "{icon_directory}/{plugin}.png"\n' if game else ''
    module = 'time' if name == 'screen-time' else 'school'
    text = f'''# {title}

{description}

A community plugin for **Omarchy Quattro with the Quickshell plugin system**. It works on a regular Omarchy installation; an Omarchy Kids ISO or fork is not required. The plugin ID is `{plugin}`.

'''
    if name in {'number-grove', 'paw-post', 'pawberry'}:
        text += '![The game running in Qt](preview.png)\n\n'
    text += f'''## Install

Run these commands in the intended user's Omarchy desktop session:

```bash
omarchy plugin add https://github.com/peterholko/{repository} --enable
'''
    if service:
        text += f'omarchy bar put {plugin} --section right\n'
    else:
        text += f'omarchy-shell shell summon {plugin} \'{{}}\'\n'
    text += '```\n\n'
    if service:
        text += f'''### Set up the background service

Adding the shell plugin alone does not install or authorize a privileged service. Review `setup` and `service/`, then run this in a terminal. Replace `CHILD_USERNAME` with the local account to enroll (for example, `linnea`):

```bash
omarchy pkg add python
sudo "$HOME/.config/omarchy/plugins/{plugin}/setup" --user CHILD_USERNAME
```

Setup asks for a new **controls parent password** of at least eight characters. Screen Time and School Mode share this password and the `omarchy-kids-controls.service` service. Setup copies only this repository's local, reviewed payload; it does not download code. Installing the second plugin preserves the first plugin's settings and enrollments. Use matching plugin releases; mismatched service versions require an explicit `--upgrade`, and unknown files or locally modified installed service files stop setup.

Only the named account is enrolled. Root owns the password hash, schedules, budgets and reward checks. The UI sends passwords over stdin, and the local service authenticates callers by their Unix socket peer credentials. It rate limits failed parent-password attempts. The controls password is separate from the login, administrator and disk passwords.

These are desktop controls for a cooperative family setup. An account that retains administrator access can disable the service, and user-controlled shell plugins are not an application sandbox. This installer does not convert or demote OS accounts. It refuses to enroll an account already configured for the original Omarchy Kids backend, to prevent two services enforcing different policies.

'''
        if name == 'school-mode':
            text += f'''### Allow the temporary school desktop changes

In the enrolled user's desktop, run the following **without sudo**. This explicitly permits School Mode to temporarily hide the stock launcher, route `Super+Space` and `Super+Alt+Space` to the school app list, disable the standard Omarchy app-launch shortcuts, quiet notifications and park existing windows. Free Time restores the previous state; windows are not closed.

```bash
python3 -I "$HOME/.config/omarchy/plugins/{plugin}/school-desktop.py" enable
```

Click the book/sun widget to enter School Mode or request Free Time. Free Time and changes to the schedule or allowed apps require the controls parent password; the password field displays checking feedback. The settings include optional access to Number Grove, Paw Post Typing and Pawberry Pet Hotel when their desktop launchers are installed. Other desktop IDs can be configured with the client’s `config patch` command.

There is one browser profile. This plugin does not filter websites; use a separate DNS/browser policy if needed. The filtered launcher and standard shortcut changes do not prevent custom shortcuts, terminal commands or manually started applications.

The desktop helper journals recovery before applying changes and changes only its own `disabledPlugins` entry in `~/.config/omarchy/shell.json`. Other bar and shell settings are preserved. It keeps a first-use backup under `~/.local/state/omarchy-community-school-mode/`. Custom `XDG_CONFIG_HOME` and `XDG_STATE_HOME` are respected by the helper. Run `school-desktop.py disable` before disabling or removing the plugin; this also revokes desktop consent.

'''
        else:
            text += '''Click the screen-time widget to inspect remaining time, configure weekday budgets and bedtime, or grant extra time with the controls parent password. Only active, unlocked graphical-session time is counted. School Mode, when separately enabled for the account, pauses the free-time budget during school hours.

Install [Math Time](https://github.com/peterholko/omarchy-math-time) to earn time through arithmetic. Without it, daily budgets and bedtime still work. At zero time the service locks the session. After a normal OS unlock, the Screen Time plugin opens Math Time; the service retains its lock fallback if the overlay cannot open. The controls parent password can grant a short bypass in Math Time. The stock OS lock screen continues to use the account's normal unlock credentials.

'''
        text += f'''### Manage enrollment and password

```bash
sudo omarchy-kids-controls password
sudo omarchy-kids-controls disable {module} --user CHILD_USERNAME
sudo omarchy-kids-controls enable {module} --user CHILD_USERNAME
```

### Service paths and dependencies

The shared service uses Python 3's standard library, systemd/logind and Omarchy's shell/lock/notification commands. School desktop effects also use Bash 5, Hyprland's Lua IPC, jq and flock, supplied by Omarchy. No pip packages, network services or API keys are needed.

- Code: `/usr/lib/omarchy-kids-controls/`
- Commands: `/usr/bin/omarchy-kids-controls` and `omarchy-kids-controls-{{time,school,grove}}-client`
- Unit: `/etc/systemd/system/omarchy-kids-controls.service`
- Private configuration and password: `/etc/omarchy-kids-controls/`
- Private service state and per-user read-only status: `/var/lib/omarchy-kids-controls/`
- Local socket: `/run/omarchy-kids-controls/sock`

'''
    else:
        details = {
            'math': 'Practice uses local arithmetic facts for grades 1–6. Grades 5 and 6 use multiplication and division tables only. Practice works without the controls service. Earning time is available only when the separately installed Screen Time service enables it; answers and time grants are checked by that service.',
            'number-grove': 'Choose calm or adventure play and a grade from 1–6. Move through the garden and collect answers with Space or Enter. Grades 5 and 6 focus on multiplication and division tables. Optional time rewards use the separately installed Screen Time service; ordinary play is fully standalone.',
            'paw-post': 'Deliver animal mail through home-row practice, everyday words and short messages, with accuracy and typing-speed feedback. No background service is required.',
            'pawberry': 'Collect 23 pets and 20 accessories by completing two- and three-digit addition, subtraction and multiplication. Enter the carries, borrowing and partial products before the final answer. Each finished problem welcomes a pet and earns a new accessory until the wardrobe is full. New pets are chosen before returning guests. Use **Try it on** after a reward or **My collection** to dress your friends in bows, hats, crowns, flowers, stars and scarves. Incorrect answers never take away earned rewards. Your collection and outfits are saved immediately under `$XDG_STATE_HOME/omarchy-pawberry/collection.ini` (normally `~/.local/state/omarchy-pawberry/collection.ini`) and retained across updates, restarts and removal. The Kids package and standalone plugin share this per-user collection. No background service is required.',
        }
        text += '## Play\n\n' + details[name] + '\n\n'
        if name == 'pawberry':
            text += '![Bubbles the axolotl wearing a collected bow in the accessory wardrobe](collection.png)\n\n'
        text += f'''### Optional app launcher and School Mode

To make the plugin appear in the apps menu and School Mode's app picker, explicitly install its desktop launcher:

```bash
mkdir -p "$HOME/.local/share/applications"
install -m 644 "$HOME/.config/omarchy/plugins/{plugin}/{plugin}.desktop" "$HOME/.local/share/applications/{plugin}.desktop"
{icon_install}```

The launcher has a unique ID. {'Its bundled icon uses the same unique name, and the symbolic link picks up artwork updates from the plugin checkout. ' if game else ''}Check before replacing an existing file with that ID if you have customized it. When School Mode is installed, the parent must separately allow the app; installation does not grant school access automatically.

## Dependencies and data

Uses the Quickshell and Qt Quick runtime supplied by Omarchy. {'Math Time also uses Python 3 to remember the chosen grade under the user’s XDG state directory.' if name == 'math' else 'The game runs locally; there are no accounts, API keys or network services.'} The optional controls service is not bundled with this plugin. School-mode status, if available, is read from `/var/lib/omarchy-kids-controls/`; the plugin does not write root-owned settings or reward totals.

'''
    text += f'''## Update

```bash
omarchy plugin update {plugin}
```

'''
    if service:
        text += f'''Review any service changes, then update the root-owned copy explicitly:

```bash
sudo "$HOME/.config/omarchy/plugins/{plugin}/setup" --user CHILD_USERNAME --upgrade
```

Updating the user-owned shell checkout never silently replaces the installed privileged service.

'''
    text += '## Remove\n\n'
    if name == 'school-mode':
        text += f'''First restore the desktop **in each enrolled user's active session**, without sudo:

```bash
python3 -I "$HOME/.config/omarchy/plugins/{plugin}/school-desktop.py" disable
```

'''
    if service:
        text += f'''Disable this module's enrollments and remove its service installation before removing the shell plugin:

```bash
sudo omarchy-kids-controls remove {module}
omarchy plugin remove {plugin}
```

If the other module is installed, its shared service, password and settings remain. Removing the last module stops and removes the service, unit and owned command wrappers. Configuration, password and history are retained for a deliberate reinstall; inspect `/etc/omarchy-kids-controls/` and `/var/lib/omarchy-kids-controls/` before deleting that data yourself. Modified or unexpected installed files stop automatic removal for review.

'''
    else:
        text += f'''Remove the optional launcher, if you installed it, then remove the plugin:

```bash
rm -f "$HOME/.local/share/applications/{plugin}.desktop"
{icon_remove}omarchy plugin remove {plugin}
```

'''
    text += '''## License and source

MIT. See [LICENSE](LICENSE) and [ATTRIBUTION.md](ATTRIBUTION.md) for retained copyright notices and asset provenance. [SOURCE.json](SOURCE.json) records the source revision and reproducible exporter in [Omarchy Kids](https://github.com/peterholko/omarchy-kids).

## Validation

```bash
omarchy plugin validate .
```

These packages are checked with the upstream manifest validator and local source tests. Full desktop enforcement, systemd installation and removal require validation on an actual Omarchy laptop. There are no GitHub Actions workflows in this repository.
'''
    if name in {'number-grove', 'paw-post', 'pawberry'}:
        text += '\nGame logic tests (Node.js, development only):\n\n```bash\nnode --test test/*.cjs\n```\n'
    return text
