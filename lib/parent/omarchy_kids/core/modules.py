"""Package-backed first-party modules behind `omarchy kids plugin`."""
import argparse
import json
import os
import pwd
import re
import subprocess
import sys
import time
from pathlib import Path
from omarchy_kids import VERSION
from . import session
from .storage import read_json

ALIASES = {'screen-time': 'time', 'school-mode': 'school'}


class Manager:
    def __init__(self, omarchy_path, package_dir=None):
        self.root = Path(omarchy_path)
        self.catalog = json.loads((self.root / 'default/parent/plugins/catalog.json').read_text())
        self.package_dir = Path(package_dir or '/var/cache/omarchy-kids/packages')

    def installed(self, name):
        return subprocess.run(['omarchy-pkg-present', self.catalog[name]['package']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

    def resolve(self, names):
        ordered = []
        visiting = set()
        def add(name):
            name = ALIASES.get(name, name)
            if name not in self.catalog:
                raise ValueError(f'unknown module: {name}')
            if name in ordered:
                return
            if name in visiting:
                raise ValueError('module dependency cycle: ' + name)
            visiting.add(name)
            for dependency in self.catalog[name]['requires']:
                add(dependency)
            visiting.remove(name)
            ordered.append(name)
        for name in names:
            add(name)
        return ordered

    def install(self, names):
        names = self.resolve(names)
        packages = [self.catalog[n]['package'] for n in names]
        archives = [list(self.package_dir.glob(p + '-' + VERSION + '-*-any.pkg.tar.zst')) for p in packages]
        if any(len(files) > 1 for files in archives):
            raise ValueError('multiple package revisions in the cache; rebuild a clean release directory')
        if all(len(files) == 1 for files in archives):
            # Local package installation is package-helper behavior. Never
            # use overwrite flags to conceal a conflicting bundled base.
            subprocess.run(['pacman', '-U', '--needed', *[str(files[0]) for files in archives]], check=True)
        else:
            subprocess.run(['omarchy-pkg-add', *packages], check=True)
        subprocess.run(['systemctl', 'try-restart', 'omarchy-kids-timed.service'], check=True)
        self.refresh_desktops()

    def users(self, name):
        if name == 'browsing':
            return [p.parent.parent.name for p in Path('/var/lib/omarchy/parent').glob('*/browsing/enabled')]
        if name in ('time', 'school'):
            filename = 'screen-time.json' if name == 'time' else 'school-mode.json'
            return sorted(read_json(Path('/etc/omarchy/parent') / filename, {}).get('users', {}))
        return []

    def refresh_desktops(self):
        # First-party shell manifests are scanned at shell startup. Reload
        # active sessions after a package transaction so new/removed widgets
        # are reflected immediately.
        for entry in pwd.getpwall():
            if entry.pw_uid == 0 or not session.graphical_sessions(entry.pw_uid):
                continue
            result = session._as_user(entry.pw_uid, ['omarchy-restart-shell'], timeout=40)
            if result is None or result.returncode != 0:
                raise ValueError('packages were updated; unlock the session and run omarchy restart shell for ' + entry.pw_name)

    def change(self, name, enabled, user=None):
        name = ALIASES.get(name, name)
        if name not in self.catalog or name == 'core':
            raise ValueError('Kids / Parent Password is the required foundation')
        if not self.installed(name):
            raise ValueError(f'{name} is not installed')
        item = self.catalog[name]
        command = [str(self.root / 'bin' / item['command']), item['enable' if enabled else 'disable']]
        if name != 'dns':
            if not user or user == 'root':
                raise ValueError('choose a child account with --user NAME')
            pwd.getpwnam(user)
            command += ['--user', user]
        subprocess.run(command, check=True)
        if not enabled and name == 'school':
            self.wait_school_restore(user)

    def wait_school_restore(self, user):
        uid = pwd.getpwnam(user).pw_uid
        watcher = session.SessionWatcher(uid)
        watcher.poll()
        if not watcher.present:
            return
        env = session._user_env(uid)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            command = ['runuser', '-u', user, '--', 'env', *[k + '=' + v for k, v in env.items()],
                       'omarchy-shell', 'shell', 'call', 'omarchy.school-mode', 'removalReady', '']
            result = subprocess.run(command, capture_output=True, text=True)
            if result.returncode == 0 and result.stdout.strip() == 'ready':
                return
            time.sleep(0.25)
        raise ValueError('school desktop restoration did not finish; module remains installed. Restore the running shell and retry removal')

    def remove(self, name):
        name = ALIASES.get(name, name)
        if name == 'core':
            raise ValueError('Kids / Parent Password cannot be removed from a child install')
        if name not in self.catalog:
            raise ValueError('unknown module')
        if not self.installed(name):
            return
        dependents = [n for n, item in self.catalog.items() if name in item['requires'] and self.installed(n)]
        if dependents:
            raise ValueError('required by: ' + ', '.join(dependents))
        users = self.users(name)
        if name == 'dns':
            self.change(name, False)
        for user in users:
            self.change(name, False, user)
        subprocess.run(['omarchy-pkg-drop', self.catalog[name]['package']], check=True)
        subprocess.run(['systemctl', 'try-restart', 'omarchy-kids-timed.service'], check=True)
        self.refresh_desktops()

    def listing(self):
        from . import proto, paths
        try:
            ping = proto.request(paths.client_socket_candidates(), {'cmd': 'ping'}, timeout=2)
        except (OSError, proto.ProtocolError):
            ping = {}
        running = ping.get('modules', {}) if isinstance(ping, dict) else {}
        result = []
        for name, item in self.catalog.items():
            installed = self.installed(name)
            enabled, healthy = False, None
            if installed:
                if name == 'core':
                    enabled, healthy = True, True
                elif name in running:
                    enabled = running[name]['users'] > 0
                    healthy = running[name].get('healthy')
                elif name in ('time', 'school', 'browsing'):
                    enabled = bool(self.users(name)) if os.geteuid() == 0 else None
                    unit = 'omarchy-kids-browsing.timer' if name == 'browsing' else 'omarchy-kids-timed.service'
                    if enabled:
                        healthy = subprocess.run(['systemctl', 'is-active', '--quiet', unit]).returncode == 0
                else:
                    conf = Path('/etc/omarchy/parent.conf')
                    setting = re.search(r'^dns=(.+)$', conf.read_text(), re.M) if conf.exists() else None
                    enabled = bool(setting and setting[1] != 'off')
                    if enabled:
                        healthy = subprocess.run(['systemctl', 'is-active', '--quiet', 'omarchy-kids-dns.service']).returncode == 0
            result.append({'id': name, **item, 'installed': installed, 'enabled': enabled, 'healthy': healthy})
        return result

    def pick(self, user):
        while True:
            choice = subprocess.run(['gum', 'choose', '--header', 'Kids modules', 'Install modules', 'Enable a module', 'Disable a module', 'Remove a module', 'Done'], capture_output=True, text=True)
            if choice.returncode != 0 or choice.stdout.strip() == 'Done':
                return
            action = choice.stdout.strip()
            installed = {i['id']: i['installed'] for i in self.listing()}
            names = [n for n in self.catalog if n != 'core' and (action == 'Install modules' or installed[n])]
            labels = {self.catalog[n]['name']: n for n in names}
            if not labels:
                print('No optional modules are installed.'); continue
            command = ['gum', 'choose', '--header', action]
            if action == 'Install modules':
                command += ['--no-limit']
            result = subprocess.run([*command, *labels], capture_output=True, text=True)
            if result.returncode != 0:
                continue
            selected = [labels[line] for line in result.stdout.splitlines() if line in labels]
            if action == 'Install modules' and selected:
                self.install(selected)
                for name in selected:
                    if subprocess.run(['gum', 'confirm', 'Enable ' + self.catalog[name]['name'] + ' now?']).returncode == 0:
                        self.change(name, True, user)
            else:
                for name in selected:
                    if action == 'Remove a module':
                        self.remove(name)
                    else:
                        self.change(name, action == 'Enable a module', user)


def main():
    parser = argparse.ArgumentParser(description='Install and manage first-party kids modules')
    parser.add_argument('action', choices=['list', 'add', 'remove', 'enable', 'disable', 'pick'])
    parser.add_argument('modules', nargs='*')
    parser.add_argument('--user', default=os.environ.get('SUDO_USER'))
    parser.add_argument('--enable', action='store_true')
    parser.add_argument('--yes', action='store_true')
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--package-dir')
    args = parser.parse_args()
    if args.action != 'list' and os.geteuid() != 0:
        raise SystemExit('This operation needs the parent password; use omarchy kids plugin.')
    manager = Manager(os.environ['OMARCHY_PATH'], args.package_dir)
    try:
        if args.action == 'list':
            values = manager.listing()
            if args.json:
                print(json.dumps(values))
            else:
                for item in values:
                    state = 'available'
                    if item['installed']:
                        state = 'installed; ' + ('enabled' if item['enabled'] else 'disabled' if item['enabled'] is False else 'status unavailable')
                        if item['healthy'] is False:
                            state += '; service needs attention'
                    print(item['id'] + '\t' + item['name'] + '\t' + state)
        else:
            subprocess.run(['omarchy-profile-child'], check=True)
            if args.action == 'pick':
                manager.pick(args.user)
            elif args.action == 'add':
                if not args.modules: raise ValueError('add needs one or more module IDs')
                manager.install(args.modules)
                if args.enable:
                    for name in args.modules:
                        manager.change(name, True, args.user)
            else:
                if len(args.modules) != 1: raise ValueError('choose one module')
                if args.action == 'remove': manager.remove(args.modules[0])
                else: manager.change(args.modules[0], args.action == 'enable', args.user)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Error: {exc}\n')
