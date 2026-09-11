"""Public documentation for each exported repository."""
PREFIX = 'io.github.peterholko.'


def readme(name, repository, title, description):
    plugin = PREFIX + name
    service = name == 'screen-time'
    game = name in {'number-grove', 'paw-post', 'pawberry'}
    icon_directory = '$HOME/.local/share/icons/hicolor/512x512/apps'
    icon_install = (f'mkdir -p "{icon_directory}"\n'
                    f'ln -sfn "$HOME/.config/omarchy/plugins/{plugin}/assets/launcher.png" "{icon_directory}/{plugin}.png"\n') if game else ''
    icon_remove = f'rm -f "{icon_directory}/{plugin}.png"\n' if game else ''
    module = 'controls'
    text = f'''# {title}

{description}

A community plugin for **Omarchy Quattro with the Quickshell plugin system**. It works on a regular Omarchy installation; an Omarchy Kids ISO or fork is not required. The plugin ID is `{plugin}`.

'''
    if name in {'number-grove', 'paw-post', 'pawberry'}:
        text += '![The game running in Qt](preview.png)\n\n'
    if service:
        text += '![The combined parent control window in portable Qt](preview.png)\n\n'
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

Setup asks for a new **controls parent password** of at least eight characters. School & Screen Time uses this password and the `omarchy-kids-controls.service` service. Setup copies only this repository's local, reviewed payload; it does not download code. The one plugin contains both controls. An upgrade preserves existing settings and enrollments; a fresh setup enrolls both controls. Use matching plugin releases; mismatched service versions require an explicit `--upgrade`, and unknown files or locally modified installed service files stop setup.

Only the named account is enrolled. Root owns the password hash, schedules, budgets and reward checks. The UI sends passwords over stdin, and the local service authenticates callers by their Unix socket peer credentials. It rate limits failed parent-password attempts. The controls password is separate from the login, administrator and disk passwords.

These are desktop controls for a cooperative family setup. An account that retains administrator access can disable the service, and user-controlled shell plugins are not an application sandbox. This installer does not convert or demote OS accounts. It refuses to enroll an account already configured for the original Omarchy Kids backend, to prevent two services enforcing different policies.

'''
        text += f'''### Allow the temporary school desktop changes

In the enrolled user's desktop, run the following **without sudo**. This explicitly permits School Mode to temporarily hide the stock launcher, route `Super+Space` and `Super+Alt+Space` to the school app list, disable the standard Omarchy app-launch shortcuts, quiet notifications and park existing windows. Free Time restores the previous state; windows are not closed.

```bash
python3 -I "$HOME/.config/omarchy/plugins/{plugin}/school/school-desktop.py" enable
```

Click the School & Screen Time widget to open the one control panel. Today shows the budget, activity and time grants; Time + Math sets budgets, bedtime and recall level; School + Apps sets school hours and app permissions. Free Time and changes to the schedule or allowed apps require the controls parent password; the password field displays checking feedback. School Mode never automatically opens Math Time after login or unlock, and stops an earning session already in progress. Deliberately opened practice remains optional. Bedtime still applies.

The settings include optional access to Number Grove, Paw Post Typing and Pawberry Pet Hotel when their desktop launchers are installed. Service 2.3.0 supports [Pawberry 1.5.0](https://github.com/peterholko/omarchy-pawberry)'s in-game **Parents** screen for independent addition, subtraction and multiplication daily limits and optional screen-time rewards. Parents choose minutes per completed problem and a Pawberry daily maximum; rewards start off and share the overall earning cap. Both time rewards and daily limits are saved with the controls parent password. Other desktop IDs can be configured with the client’s `config patch` command.

There is one browser profile. This plugin does not filter websites; use a separate DNS/browser policy if needed. The filtered launcher and standard shortcut changes do not prevent custom shortcuts, terminal commands or manually started applications.

The desktop helper journals recovery before applying changes and changes only its own `disabledPlugins` entry in `~/.config/omarchy/shell.json`. Other bar and shell settings are preserved. It keeps a first-use backup under `~/.local/state/omarchy-community-school-mode/`. Custom `XDG_CONFIG_HOME` and `XDG_STATE_HOME` are respected by the helper. Run `school-desktop.py disable` before disabling or removing the plugin; this also revokes desktop consent.

'''
        text += f'''Math Time is bundled inside this same plugin. Open optional practice with:

```bash
omarchy-shell shell summon {plugin} math
```

At zero free time, the service locks the session; after a normal OS unlock, the combined plugin opens its Math Time activity to earn minutes. It first checks the current mode, so School Mode cannot trigger this handoff. The controls parent password can grant a short bypass. The stock OS lock screen continues to use the account's normal unlock credentials. The separately published Math Time plugin is only needed when installing arithmetic practice by itself.

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
- Commands: `/usr/bin/omarchy-kids-controls` and `omarchy-kids-controls-{{time,school,grove,pawberry}}-client`
- Unit: `/etc/systemd/system/omarchy-kids-controls.service`
- Private configuration and password: `/etc/omarchy-kids-controls/`
- Private service state and per-user read-only status: `/var/lib/omarchy-kids-controls/`
- Local socket: `/run/omarchy-kids-controls/sock`

'''
    else:
        details = {
            'math': 'Practice uses the same local recall generator as the service, with grades 1–7: number bonds, facts within 20, core 1–10 multiplication/division tables, then familiar fractions, decimals, percentages, divisibility and signed facts. Practice works without the controls service. Earning time is available only when the School & Screen Time service enables it; answers and time grants are checked by that service.',
            'number-grove': 'Choose calm or adventure play and a grade from 1–6. Move through the garden and collect answers with Space or Enter. Grades 5 and 6 focus on multiplication and division tables. Optional time rewards use the School & Screen Time service; ordinary play is fully standalone.',
            'paw-post': 'Deliver animal mail through home-row practice, everyday words and short messages, with accuracy and typing-speed feedback. No background service is required.',
            'pawberry': 'Collect 23 pets and 20 accessories by completing two- and three-digit addition/subtraction, one- through three-digit multiplication, and easy two-digit / one-digit division with no remainders. Enter the carries, borrowing and partial products before the final answer. Each finished problem welcomes a pet and earns a new accessory until the wardrobe is full. New pets are chosen before returning guests. Use **Try it on** after a reward or **My collection** to dress your friends in bows, hats, crowns, flowers, stars and scarves. Incorrect answers never take away earned rewards. Your collection and outfits are saved immediately under `$XDG_STATE_HOME/omarchy-pawberry/collection.ini` (normally `~/.local/state/omarchy-pawberry/collection.ini`) and retained across updates, restarts and removal. The Kids package and standalone plugin share this per-user collection. Ordinary play needs no background service. Optional parent limits use the School & Screen Time service.',
        }
        text += '## Play\n\n' + details[name] + '\n\n'
        if name == 'pawberry':
            text += """### Parent daily practice limits

Open **Parents → Daily practice** inside Pawberry. For addition, subtraction and multiplication separately, choose **Unlimited**, **Daily limit** or **Unavailable**. Enter the number of completed problems allowed per day, then enter the controls parent password and select **Save settings**. For example, choose **Daily limit** and **5** for each to allow five of each per day. The password is masked; **Checking password…** stays visible while it verifies. An incorrect password leaves saved settings unchanged. Opening settings pauses an active visit; **Back to the hotel** returns to the same work.

![Pawberry's in-game parent settings with separate addition, subtraction and multiplication limits](parent-settings.png)

Parent limits and optional rewards need a one-time setup of the [School & Screen Time](https://github.com/peterholko/omarchy-screen-time) service. Version **2.3.0** supports all three practice limits and optional time rewards. Older services still support addition/subtraction limits (2.1.0+) and time rewards (2.2.0+); the multiplication row asks for an update until service 2.3.0 is installed. For an existing installation, update both plugins, then review and install the local service payload:

```bash
omarchy plugin update io.github.peterholko.pawberry
omarchy plugin update io.github.peterholko.screen-time
sudo "$HOME/.config/omarchy/plugins/io.github.peterholko.screen-time/setup" --user linnea --upgrade
```

Replace `linnea` with the child's account name. On a first install, follow the linked plugin's installation instructions; setup asks for a separate controls parent password. A fresh setup also enrolls School & Screen Time; you can disable those controls while retaining the service for Pawberry with `sudo omarchy-kids-controls disable controls --user linnea`. Updating an existing setup preserves its enrollments. The in-game settings apply to the account playing Pawberry, using that controls password.

All three operations default to unlimited. Only completed full problems count; incorrect answers and unfinished problems do not. Restarting, changing difficulty or saving a new limit does not reset today's completed count. The multiplication allowance is shared by 1-, 2- and 3-digit problems, including work completed before setting its first limit. New allowances start each local calendar day. Exhausted operations become unavailable, including in Mixed; division remains unlimited. The next pet switches to an available operation. Root owns the limits and counters separately from the saved collection. A configured service must respond before a problem can start or award a pet; there is no unlimited fallback on service failure.

The optional CLI alternative is `omarchy-kids-controls-pawberry-client limits --addition 5 --subtraction 5 --multiplication 10` from the child's session. It asks for the controls parent password. Use `0` to disable an operation or `unlimited` to remove its cap; omitted operations keep their settings.

### Optional screen-time rewards

Inside **Parents → Screen time**, turn **Earn screen time** on, choose **minutes per completed problem** and a **daily maximum from Pawberry**, then save with the controls parent password. Rewards start off; the initial values are one minute per problem and a maximum of 30 minutes per day. Screen Time must be enabled for this account with earning turned on. The time already earned today is shown in the settings.

![Optional Pawberry screen-time rewards configured inside the game](screen-time-settings.png)

A completed problem in any of the four operations adds minutes to the normal screen-time balance. The game confirms the amount after the pet reveal, and the activity log labels it as Pawberry. Both Pawberry's cap and the overall daily earning cap apply; a final reward can be smaller near the cap. Wrong answers, unfinished problems and repeated submissions cannot add time. Saving new settings or disabling rewards keeps earned time and today's counters. School Mode, bedtime/break periods, paused tracking, locked sessions and Together mode do not award minutes. The normal lock flow still applies at zero time; Pawberry does not hold the lock off or open automatically after unlock. Pet and accessory rewards remain available when time rewards are off or capped.

"""
            text += '![Bubbles the axolotl wearing a collected bow in the accessory wardrobe](collection.png)\n\n'
        text += f'''### Optional app launcher and School Mode

To make the plugin appear in the apps menu and School Mode's app picker, explicitly install its desktop launcher:

```bash
mkdir -p "$HOME/.local/share/applications"
install -m 644 "$HOME/.config/omarchy/plugins/{plugin}/{plugin}.desktop" "$HOME/.local/share/applications/{plugin}.desktop"
{icon_install}```

The launcher has a unique ID. {'Its bundled icon uses the same unique name, and the symbolic link picks up artwork updates from the plugin checkout. ' if game else ''}Check before replacing an existing file with that ID if you have customized it. When School Mode is installed, the parent must separately allow the app; installation does not grant school access automatically.

## Dependencies and data

Uses the Quickshell and Qt Quick runtime supplied by Omarchy. {'Math Time uses Python 3’s standard library for offline questions and to remember the chosen grade under the user’s XDG state directory.' if name == 'math' else 'The game runs locally; there are no accounts, API keys or network services.'} The optional controls service is not bundled with this plugin. School-mode status, if available, is read from `/var/lib/omarchy-kids-controls/`; the plugin does not write root-owned settings or reward totals.

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

Updating the user-owned shell checkout never silently replaces the installed privileged service. Upgrade preserves each existing account’s enabled/disabled time and school enrollment. To explicitly enable both for an account, run `sudo omarchy-kids-controls enable controls --user CHILD_USERNAME`.

### Move from the old separate School Mode plugin

Before enabling this combined plugin, restore the desktop with the old plugin and disable its UI (without sudo, in the child’s desktop):

```bash
python3 -I "$HOME/.config/omarchy/plugins/io.github.peterholko.school-mode/school-desktop.py" disable
omarchy plugin disable io.github.peterholko.school-mode
```

Then install/update this plugin and run its `setup --upgrade` command above. Enable the combined plugin’s school desktop helper as shown above. The service reuses the existing school and time configuration; do not remove the old service module or its state to perform this migration.

'''
    text += '## Remove\n\n'
    if service:
        text += f'''First restore the desktop **in each enrolled user's active session**, without sudo:

```bash
python3 -I "$HOME/.config/omarchy/plugins/{plugin}/school/school-desktop.py" disable
```

'''
    if service:
        text += f'''Disable this module's enrollments and remove its service installation before removing the shell plugin:

```bash
sudo omarchy-kids-controls remove {module}
omarchy plugin remove {plugin}
```

Removing `controls` disables both parts and removes the service, unit and owned command wrappers after restoring school desktops. Configuration, password and history are retained for a deliberate reinstall; inspect `/etc/omarchy-kids-controls/` and `/var/lib/omarchy-kids-controls/` before deleting that data yourself. Modified or unexpected installed files stop automatic removal for review.

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
