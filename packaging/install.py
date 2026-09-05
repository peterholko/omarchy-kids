"""Install a coherent kids release through one pacman transaction."""
import argparse
import hashlib
import json
import os
import pwd
import re
import shutil
import subprocess
import sys
from pathlib import Path

MODULES = ('dns', 'browsing', 'time', 'school')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', type=Path, help='directory containing the seven built packages and release.json')
    parser.add_argument('modules', nargs='*', choices=['core', *MODULES], help='additional modules to install; existing selections are retained')
    parser.add_argument('--user', required=True, help='existing child account')
    args = parser.parse_args()
    if os.geteuid() != 0 or sys.platform != 'linux':
        parser.error('run packaging/install on the child Arch Linux laptop')
    if pwd.getpwnam(args.user).pw_uid == 0 or Path('/etc/omarchy/profile').read_text().strip() != 'child':
        parser.error('this installer needs an existing child-profile Omarchy installation')
    release = json.loads((args.packages / 'release.json').read_text())
    packages = release['packages']
    expected = {'omarchy-kids-base', 'omarchy-kids-settings', 'omarchy-parent-core'} | {'omarchy-parent-' + m for m in MODULES}
    if set(packages) != expected:
        parser.error('incomplete kids release')
    archives = {}
    for name, info in packages.items():
        filename = info['file']
        if Path(filename).name != filename:
            parser.error('invalid archive filename')
        archive = args.packages / filename
        if hashlib.sha256(archive.read_bytes()).hexdigest() != info['sha256']:
            parser.error('checksum mismatch: ' + filename)
        archives[name] = archive.resolve()
    installed = set(subprocess.check_output(['pacman', '-Qq'], text=True).splitlines())
    selected = {'core', *args.modules} | {m for m in MODULES if 'omarchy-parent-' + m in installed}
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
    names = ['omarchy-kids-settings', 'omarchy-kids-base'] + ['omarchy-parent-' + m for m in sorted(selected)]
    print('Installing: ' + ', '.join(names), flush=True)
    was_running = subprocess.run(['systemctl', 'is-active', '--quiet', 'omarchy-parent-timed.service']).returncode == 0
    if was_running:
        subprocess.run(['systemctl', 'stop', 'omarchy-parent-timed.service'], check=True)
    try:
        # This is the release update entrypoint. No file-overwrite flags: the
        # base recipes relinquish module ownership in the same transaction.
        subprocess.run(['pacman', '-U', '--needed', *map(str, (archives[n] for n in names))],
                       env={**os.environ, 'OMARCHY_UPDATE_PACMAN': '1'}, check=True)
    finally:
        if was_running:
            subprocess.run(['systemctl', 'start', 'omarchy-parent-timed.service'], check=True)
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
    from omarchy_parent.core.files import adopt_browser_policy
    from omarchy_parent.core.paths import write_private
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
    subprocess.run(['/usr/bin/omarchy-parent', 'apply', '--user', args.user], env=environment, check=True)
    subprocess.run(['/usr/bin/omarchy-parent-refresh'], env=environment, check=True)
    print('Installed. New optional modules remain disabled until you enable them.')
    print('Reboot to activate the package path, then run: omarchy parent plugin pick')


if __name__ == '__main__':
    main()
