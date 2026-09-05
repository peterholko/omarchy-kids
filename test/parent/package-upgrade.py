"""Run only in CI's disposable Arch container, after installing the old packages."""
import json
import os
from pathlib import Path
import subprocess

if os.environ.get('GITHUB_ACTIONS') != 'true' or not Path('/.dockerenv').exists():
    raise SystemExit('This destructive fixture runs only in the GitHub Actions Docker container.')


def write(name, data, mode=0o644):
    path = Path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data)
    path.chmod(mode)


assert Path('/usr/bin/omarchy-parent').is_file(), 'install the previous packages first'
write('/etc/pam.d/omarchy-lock-password', 'auth sufficient pam_exec.so /usr/bin/omarchy-parent-unlock\n')
write('/etc/sudoers.d/omarchy-parent-kid', 'kid ALL=(ALL:ALL) ALL\n', 0o440)
write('/etc/systemd/system/omarchy-parent-timed.service', Path('/usr/lib/systemd/system/omarchy-parent-timed.service').read_text())
write('/etc/omarchy/parent/screen-time.json', '{"version":3,"users":{},"profiles":{"default":{}},"active_profile":"default"}\n', 0o600)
write('/etc/chromium/policies/managed/omarchy-parent-dns.json', '{"URLBlocklist":["example.com"]}\n')
packages = sorted(map(str, Path('build-output').glob('*.pkg.tar.zst')))
# Answer only this disposable container's package conflict/removal prompts.
subprocess.run(['pacman', '-Udd', '--noscriptlet', *packages], input='y\n' * 20, text=True, check=True)
installed = set(subprocess.check_output(['pacman', '-Qq'], text=True).splitlines())
expected = {'omarchy-kids-' + name for name in ('base', 'settings', 'core', 'dns', 'browsing', 'time', 'school')}
assert expected <= installed, expected - installed
assert not any(name.startswith('omarchy-parent-') for name in installed)
assert not Path('/usr/bin/omarchy-parent').exists()
assert Path('/usr/bin/omarchy-kids').is_file()
protected = list(Path('/usr/bin').glob('omarchy-kids*'))
protected += list(Path('/usr/share/omarchy/lib/parent/omarchy_kids').rglob('*'))
protected.append(Path('/usr/lib/systemd/system/omarchy-kids-timed.service'))
for path in protected:
    info = path.stat()
    assert info.st_uid == 0 and info.st_gid == 0 and not info.st_mode & 0o022, f'unsafe package ownership or permissions: {path}'
assert 'omarchy-kids-unlock' in Path('/etc/pam.d/omarchy-lock-password').read_text()
assert Path('/etc/sudoers.d/omarchy-kids-kid').stat().st_mode & 0o777 == 0o440
assert not Path('/etc/systemd/system/omarchy-parent-timed.service').exists()
assert 'omarchy-kids-timed' in Path('/etc/systemd/system/omarchy-kids-timed.service').read_text()
assert json.loads(Path('/etc/chromium/policies/managed/omarchy-kids-dns.json').read_text()) == {'URLBlocklist': ['example.com']}
assert json.loads(Path('/etc/omarchy/parent/screen-time.json').read_text())['version'] == 3
print('PASS: old packages replaced in one transaction; PAM, services, policy and sudo permissions migrated')
