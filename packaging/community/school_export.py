"""Adapt school mode to the public community-plugin API."""
import shutil


def export_desktop(root, destination):
    from export import TEMPLATES, PREFIX
    shutil.copy2(TEMPLATES / 'school-desktop.py', destination / 'school-desktop.py')
    for filename in ('window-session', 'shortcut-policy'):
        text = (root / 'shell/plugins/screen-time/school' / filename).read_text()
        text = text.replace('omarchy.screen-time', PREFIX + 'screen-time')
        text = text.replace('omarchy-school-mode', 'omarchy-community-school-mode')
        text = text.replace('special:omarchy-school-parked', 'special:omarchy-community-school-parked')
        text = text.replace('name:omarchy-school', 'name:omarchy-community-school')
        text = text.replace('RUNTIME_ROOT=${XDG_RUNTIME_DIR:-/tmp/omarchy-community-school-mode-$UID}',
            'RUNTIME_ROOT=${XDG_RUNTIME_DIR:?Run this command in the Omarchy desktop session}')
        text = text.replace('mkdir -p -- "$STATE_DIR"', '''umask 077
[[ ! -L $STATE_DIR ]] || { echo "Refusing a symlink state directory" >&2; exit 1; }
mkdir -p -- "$STATE_DIR"
[[ -O $STATE_DIR ]] || { echo "State directory has another owner" >&2; exit 1; }
chmod 700 "$STATE_DIR"
[[ ! -L $LOCK_FILE ]] || { echo "Refusing a symlink lock" >&2; exit 1; }''')
        if filename == 'shortcut-policy':
            start = text.index('# A child install\'s shortcuts')
            end = text.index("printf 'version=1", start)
            keys = ['SUPER + RETURN', 'SUPER + SHIFT + F', 'SUPER + ALT + SHIFT + F',
                    'SUPER + SHIFT + B', 'SUPER + SHIFT + ALT + B', 'SUPER + SHIFT + N',
                    'SUPER + ALT + RETURN', 'SUPER + CTRL + RETURN',
                    *['SUPER + SHIFT + ' + key for key in 'MDGOWACESYPX'],
                    *['SUPER + SHIFT + ALT + ' + key for key in 'MAEGX'],
                    'SUPER + SHIFT + CTRL + G', 'SUPER + SHIFT + SLASH']
            text = text[:start] + '# Use the filtered menu to launch apps during school mode.\n' + '\n'.join(
                'unbind "' + key + '"' for key in dict.fromkeys(keys)) + '\n\n' + text[end:]
        (destination / filename).write_text(text)
        (destination / filename).chmod(0o755)


def export_school(root, destination):
    from export import replace, TEMPLATES, PREFIX
    export_desktop(root, destination)
    shutil.copy2(TEMPLATES / 'SchoolService.qml', destination / 'Service.qml')
    menu = destination / 'Menu.qml'
    replace(menu, 'omarchyPath ? omarchyPath + "/shell/plugins/screen-time/school" : ""',
            'decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\\/\\//, "")).replace(/\\/$/, "")')
    replace(menu, 'root.sourceAppLibrary ? root.sourceAppLibrary.isHiddenEntry(entry) : false',
            'root.sourceAppLibrary && typeof root.sourceAppLibrary.isHiddenEntry === "function" ? root.sourceAppLibrary.isHiddenEntry(entry) : false')
    replace(menu, 'a parent changes the list with omarchy-kids time school-apps.', 'a parent changes the list in the School / Free Time settings.')
    for path in destination.glob('*.qml'):
        text = path.read_text()
        for name in ('number-grove', 'paw-post', 'pawberry'):
            text = text.replace('"omarchy-' + name + '"', '"' + PREFIX + name + '"')
        path.write_text(text)
    for filename in ('ShellIntegration.js', 'NotificationState.js'):
        (destination / filename).unlink(missing_ok=True)
