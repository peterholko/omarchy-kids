"""Install a coherent kids release through one pacman transaction."""
import argparse
import json
import os
import pwd
import re
import shutil
import subprocess
import sys
from pathlib import Path
from conversion import Conversion, PROFILE
from release import MODULE_NAMES, verify

MODULES = tuple(name for name in MODULE_NAMES if name != 'core')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', type=Path, help='directory containing all built packages and release.json')
    parser.add_argument('modules', nargs='*', choices=['core', *MODULES], help='additional modules to install; existing selections are retained')
    parser.add_argument('--user', required=True, help='existing account to configure for the kid')
    parser.add_argument('--convert', action='store_true', help='convert a clean Omarchy 4 account; install every module by default')
    parser.add_argument('--all', action='store_true', help='install all modules')
    args = parser.parse_args()
    if os.geteuid() != 0 or sys.platform != 'linux':
        parser.error('run packaging/install on the Omarchy laptop')
    if pwd.getpwnam(args.user).pw_uid == 0:
        parser.error('the kid account cannot be root')
    source = Path(__file__).resolve().parents[1]
    conversion = Conversion(args.user, source)
    profile = PROFILE.read_text().strip() if PROFILE.exists() else 'default'
    if profile not in ('default', 'child'):
        parser.error('unknown Omarchy profile')
    if profile != 'child' or conversion.pending:
        if not args.convert:
            parser.error('use --convert to set up the kid and parent passwords on this laptop')
    else:
        conversion = None
    archives = verify(args.packages, os.uname().machine)
    installed = set(subprocess.check_output(['pacman', '-Qq'], text=True).splitlines())
    selected = {'core', *args.modules} | {m for m in MODULES if {'omarchy-kids-' + m, 'omarchy-parent-' + m} & installed}
    if args.all or args.convert and not args.modules:
        selected.update(MODULES)
    legacy_policy_modules = []
    # Preserve enabled modules when moving from the tested bundled branch.
    legacy = Path('/etc/omarchy/parent/screen-time.json')
    if legacy.exists():
        config = json.loads(legacy.read_text())
        if config.get('users'):
            selected.add('time')
            if config.get('version', 1) < 3:
                selected.add('school')
    school = Path('/etc/omarchy/parent/school-mode.json')
    if school.exists() and json.loads(school.read_text()).get('users'):
        selected.add('school')
    conf = Path('/etc/omarchy/parent.conf')
    if conf.exists() and any(line.startswith('dns=') and line.strip() != 'dns=off' for line in conf.read_text().splitlines()):
        selected.add('dns')
        legacy_policy_modules.append('dns')
    if list(Path('/var/lib/omarchy/parent').glob('*/browsing/enabled')):
        selected.add('browsing')
        legacy_policy_modules.append('browsing')
    names = ['omarchy-kids-settings', 'omarchy-kids-base'] + ['omarchy-kids-' + m for m in sorted(selected)]
    sys.path.insert(0, str(source / 'lib/parent'))
    from omarchy_kids.core.namespace import Migration, check_command_collisions
    check_command_collisions(source)
    Migration().plan()
    if conversion:
        conversion.prepare()
        conversion.begin()
    print('Installing: ' + ', '.join(names), flush=True)
    was_running = subprocess.run(['systemctl', 'is-active', '--quiet', 'omarchy-kids-timed.service']).returncode == 0
    if was_running:
        subprocess.run(['systemctl', 'stop', 'omarchy-kids-timed.service'], check=True)
    try:
        # This is the release update entrypoint. No file-overwrite flags: the
        # base recipes relinquish module ownership in the same transaction.
        subprocess.run(['pacman', '-U', '--needed', *map(str, (archives[n] for n in names))],
                       env={**os.environ, 'OMARCHY_UPDATE_PACMAN': '1'}, check=True)
    finally:
        if was_running:
            subprocess.run(['systemctl', 'start', 'omarchy-kids-timed.service'], check=True)
    cache = Path('/var/cache/omarchy-kids/packages')
    cache.mkdir(parents=True, exist_ok=True)
    for archive in archives.values():
        target = cache / archive.name
        if archive != target.resolve():
            stage = target.with_suffix(target.suffix + '.new')
            shutil.copy2(archive, stage)
            os.replace(stage, target)
    current = {archive.name for archive in archives.values()}
    for old in cache.glob('*.pkg.tar.zst'):
        if old.name not in current:
            old.unlink()
    if (args.packages / 'release.json').resolve() != (cache / 'release.json').resolve():
        shutil.copy2(args.packages / 'release.json', cache / 'release.json')
    environment = {**os.environ, 'OMARCHY_PATH': '/usr/share/omarchy', 'PATH': '/usr/bin:/bin'}
    sys.path.insert(0, '/usr/share/omarchy/lib/parent')
    from omarchy_kids.core.files import adopt_browser_policy
    from omarchy_kids.core.paths import write_private
    if legacy_policy_modules:
        for file in ('/usr/lib/firefox/distribution/policies.json', '/opt/zen-browser/distribution/policies.json'):
            if Path(file).exists():
                adopt_browser_policy(file, legacy_policy_modules)
    # Use the session's existing top-level path configuration, just as
    # omarchy-dev-unlink does. Keep the old checkout and a config backup.
    session_config = Path('/etc/omarchy.conf')
    previous = session_config.read_text() if session_config.exists() else ''
    backup = session_config.with_name('omarchy.conf.before-kids-modules')
    if not backup.exists():
        write_private(backup, previous)
    line = 'export OMARCHY_PATH="/usr/share/omarchy"'
    updated = re.sub(r'^export OMARCHY_PATH=.*$', line, previous, flags=re.M)
    if updated == previous and line not in previous.splitlines():
        updated = previous.rstrip() + '\n' + line + '\n'
    write_private(session_config, updated)
    session_config.chmod(0o644)
    Path('/etc/sudoers.d/omarchy-dev-path').unlink(missing_ok=True)
    if conversion:
        conversion.activate()
    subprocess.run(['/usr/bin/omarchy-kids-setup', '--user', args.user], env=environment, check=True)
    subprocess.run(['/usr/bin/omarchy-kids-refresh'], env=environment, check=True)
    if conversion:
        conversion.finish()
    print('Installed. Applications are ready to launch. New restriction modules remain disabled until you enable them.')
    print('Reboot before handing the laptop to the kid, then run: omarchy kids plugin pick')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f'Installation stopped: {exc}\nFix the reported problem and rerun the same command to resume.')
