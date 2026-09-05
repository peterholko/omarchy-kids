"""Move installed integration files to the kids namespace without losing state."""
import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile

from .storage import locked, read_json, write_json

LEGACY = 'omarchy-parent'
CURRENT = 'omarchy-kids'
UNITS = tuple(LEGACY + suffix for suffix in ('-timed.service', '-dns.service', '-browsing.service', '-browsing.timer'))
COMMAND = re.compile(r'(?<![A-Za-z0-9_-])omarchy-parent(?:d|-(?:apps|browsing|client|dns|files|modules|plugin|refresh|school-client|school|time-client|timed|time|unlock))?(?![A-Za-z0-9_-])')


def rename(value):
    return value.replace(LEGACY, CURRENT).replace('omarchy_parent', 'omarchy_kids').replace('OMARCHY_PARENT', 'OMARCHY_KIDS')


@dataclass
class Change:
    source: Path
    target: Path
    data: bytes | str
    symlink: bool


class Migration:
    def __init__(self, root=Path('/'), run=subprocess.run):
        self.root = Path(root)
        self.run = run
        self.backup = self.root / 'var/lib/omarchy/kids-namespace-backup'
        self.journal = self.backup / 'pending.json'

    def plan(self):
        # Only generated integration locations are considered. Persistent
        # profiles, DNS lists, history and budgets keep their existing paths.
        sources = {}
        patterns = [
            'etc/sudoers.d/' + LEGACY, 'etc/sudoers.d/' + LEGACY + '-*',
            'etc/polkit-1/rules.d/40-' + LEGACY + '.rules',
            'etc/polkit-1/rules.d/45-' + LEGACY + '-wifi.rules',
            'etc/NetworkManager/conf.d/50-' + LEGACY + '-dns.conf',
            'etc/NetworkManager/dispatcher.d/50-' + LEGACY + '-dns',
            'etc/systemd/resolved.conf.d/50-' + LEGACY + '-dns.conf',
            'etc/pacman.d/hooks/' + LEGACY + '-apps.hook',
        ]
        for unit in UNITS:
            patterns += ['etc/systemd/system/' + unit, 'etc/systemd/system/' + unit + '.d/*',
                         'etc/systemd/system/*.wants/' + unit, 'etc/systemd/system/*.requires/' + unit]
        for pattern in patterns:
            for source in self.root.glob(pattern):
                if source.is_file() or source.is_symlink():
                    if source.parent == self.root / 'etc/sudoers.d' and source.name != LEGACY:
                        # Third-party add-ons also used this prefix. Only the
                        # known per-account administrative grant belongs here.
                        user = source.name.removeprefix(LEGACY + '-')
                        if source.is_symlink() or not re.search(r'^' + re.escape(user) + r'\s+ALL=\(ALL:ALL\) ALL$', source.read_text(), re.M):
                            continue
                    sources[source] = 'integration'
        for directory in ('etc/chromium/policies/managed', 'etc/opt/chrome/policies/managed',
                          'etc/brave/policies/managed', 'etc/opt/edge/policies/managed'):
            for module in ('dns', 'browsing'):
                sources[self.root / directory / (LEGACY + '-' + module + '.json')] = 'verbatim'
        for directory in ('usr/lib/firefox/distribution', 'opt/zen-browser/distribution'):
            sources[self.root / directory / ('.' + LEGACY + '-policies.json')] = 'verbatim'
        for name in ('etc/pam.d/omarchy-lock-password', 'etc/pam.d/sddm'):
            sources[self.root / name] = 'pam'
        sources[self.root / 'etc/omarchy/parent/dnsmasq.conf'] = 'resolver'
        changes = []
        for source, kind in sorted(sources.items()):
            if not source.exists() and not source.is_symlink():
                continue
            target = self.root / rename(str(source.relative_to(self.root)))
            symlink = source.is_symlink()
            before = os.readlink(source) if symlink else source.read_bytes()
            after = before
            if kind != 'verbatim':
                text = before if symlink else before.decode()
                if kind == 'pam':
                    text = text.replace('/usr/bin/' + LEGACY + '-unlock', '/usr/bin/' + CURRENT + '-unlock')
                elif kind == 'resolver':
                    text = text.replace('/run/' + LEGACY + '/', '/run/' + CURRENT + '/')
                else:
                    text = COMMAND.sub(lambda match: match[0].replace(LEGACY, CURRENT), text)
                    text = text.replace('omarchy_parent', 'omarchy_kids').replace('OMARCHY_PARENT', 'OMARCHY_KIDS')
                after = text if symlink else text.encode()
            if source == target and after == before:
                continue
            change = Change(source, target, after, symlink)
            if source != target and (target.exists() or target.is_symlink()):
                same = target.is_symlink() == symlink
                if same:
                    same = (os.readlink(target) if symlink else target.read_bytes()) == after
                if not same:
                    raise ValueError(f'namespace collision: {source} -> {target}; resolve the conflicting files before upgrading')
            changes.append(change)
        return changes

    def install(self, change):
        source, target = change.source, change.target
        backup = self.backup / 'originals' / source.relative_to(self.root)
        backup.parent.mkdir(parents=True, exist_ok=True)
        if not backup.exists() and not backup.is_symlink():
            shutil.copy2(source, backup, follow_symlinks=False)
        target.parent.mkdir(parents=True, exist_ok=True)
        info = source.lstat()
        fd, name = tempfile.mkstemp(prefix='.kids-rename-', dir=target.parent)
        stage = Path(name)
        try:
            if change.symlink:
                os.close(fd)
                stage.unlink()
                stage.symlink_to(change.data)
            else:
                with os.fdopen(fd, 'wb') as stream:
                    stream.write(change.data)
                    stream.flush()
                    os.fsync(stream.fileno())
                stage.chmod(stat.S_IMODE(info.st_mode))
            if os.geteuid() == 0:
                os.chown(stage, info.st_uid, info.st_gid, follow_symlinks=False)
            os.replace(stage, target)
            if source != target:
                source.unlink()
        finally:
            stage.unlink(missing_ok=True)

    def apply(self, systemd=True):
        self.backup.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.backup.chmod(0o700)
        with locked(self.backup / '.lock'):
            changes = self.plan()  # Validate every destination before stopping services or writing files.
            states = read_json(self.journal, {}).get('units', {})
            if systemd and not states:
                for unit in UNITS:
                    active = self.run(['systemctl', 'is-active', '--quiet', unit]).returncode == 0
                    enabled = self.run(['systemctl', 'is-enabled', '--quiet', unit]).returncode == 0
                    if active or enabled:
                        states[unit] = {'active': active, 'enabled': enabled}
            if not changes and not states:
                return
            write_json(self.journal, {'units': states})
            if systemd:
                for unit in states:
                    if self.run(['systemctl', 'is-active', '--quiet', unit]).returncode == 0:
                        self.run(['systemctl', 'stop', unit], check=True)
            for change in changes:
                self.install(change)
            # Discard empty old drop-in directories after moving their files.
            for unit in UNITS:
                directory = self.root / 'etc/systemd/system' / (unit + '.d')
                if directory.is_dir() and not any(directory.iterdir()):
                    directory.rmdir()
            if systemd:
                self.run(['systemctl', 'daemon-reload'], check=True)
                for unit, state in states.items():
                    if state['enabled']:
                        self.run(['systemctl', 'enable', rename(unit)], check=True)
                    if state['active']:
                        self.run(['systemctl', 'start', rename(unit)], check=True)
            self.journal.unlink(missing_ok=True)


def check_command_collisions(source, root=Path('/')):
    """A command in /usr/local/bin would shadow a renamed packaged command."""
    for command in (Path(source) / 'bin').glob('omarchy-kids*'):
        target = Path(root) / 'usr/local/bin' / command.name
        if target.exists() or target.is_symlink():
            raise ValueError(f'command collision: {target}; move or rename the existing command before installing')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    if os.geteuid() != 0:
        parser.error('the package transaction must run this migration as root')
    systemd = Path('/run/systemd/system').is_dir() and subprocess.run(
        ['systemd-detect-virt', '--quiet', '--chroot']).returncode != 0
    Migration().apply(systemd=systemd)
