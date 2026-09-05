"""Exercise real passwords, sudo, PAM setup and LUKS keys in a disposable CI container."""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

if os.geteuid() != 0 or not Path('/.dockerenv').exists() or os.environ.get('CI') != 'true':
    raise SystemExit('Run only in the disposable GitHub Actions conversion container.')

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packaging'))
import conversion
spec = importlib.util.spec_from_file_location('kids_install', ROOT / 'packaging/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


# Start with one ordinary password-authenticated administrator and no Kids
# profile. Package replacement is independently tested by package-upgrade.py.
run('useradd', '-m', '-G', 'wheel', 'kid')
run('groupadd', '-f', 'docker')
run('usermod', '-aG', 'docker', 'kid')
run('chpasswd', input='kid:ci-kid-password\nroot:ci-kid-password\n')
Path('/etc/sudoers').write_text('root ALL=(ALL:ALL) ALL\n@includedir /etc/sudoers.d\n')
Path('/etc/sudoers.d/00-omarchy-wheel').write_text('%wheel ALL=(ALL:ALL) ALL\n')
Path('/etc/sudoers.d/00-omarchy-wheel').chmod(0o440)
Path('/etc/pam.d/sddm').write_text('#%PAM-1.0\nauth include system-login\naccount include system-login\nsession include system-login\n')
Path('/etc/omarchy').mkdir(exist_ok=True)
Path('/etc/omarchy/profile').write_text('default\n')
hypr = Path('/home/kid/.config/hypr/hyprland.lua')
assert hypr.exists(), 'the matching settings package must seed the user'
personal = Path('/home/kid/personal-file')
personal.write_text('keep me')

device = '/tmp/conversion-test.luks'
with open(device, 'wb') as image:
    image.truncate(64 * 1024 * 1024)
run('cryptsetup', 'luksFormat', '--batch-mode', '--type', 'luks2', '--pbkdf', 'pbkdf2',
    '--pbkdf-force-iterations', '1000', '--key-file', '-', device, input='ci-kid-password')
before = json.loads(subprocess.check_output(['cryptsetup', 'luksDump', '--dump-json-metadata', device], text=True))['keyslots']

sys.argv = ['install.py', str(ROOT / 'build-output'), '--user', 'kid', '--convert']
with patch.object(conversion, 'root_luks_device', return_value=device), \
        patch.object(conversion.os, 'isatty', return_value=True), \
        patch.object(conversion.getpass, 'getpass', side_effect=['ci-parent-password', 'ci-parent-password', 'ci-kid-password']):
    installer.main()

assert conversion.password_matches('kid', 'ci-kid-password')
assert conversion.password_matches('root', 'ci-parent-password')
assert not conversion.password_matches('root', 'ci-kid-password')
assert conversion.unlocks(device, 'ci-kid-password')
assert conversion.unlocks(device, 'ci-parent-password')
after = json.loads(subprocess.check_output(['cryptsetup', 'luksDump', '--dump-json-metadata', device], text=True))['keyslots']
assert before.keys() < after.keys(), 'conversion must add a slot and keep the existing slot'
groups = subprocess.check_output(['id', '-nG', 'kid'], text=True).split()
assert not {'wheel', 'docker'} & set(groups)
assert '/usr/bin/omarchy-kids-unlock' in Path('/etc/pam.d/sddm').read_text()
assert '/usr/bin/omarchy-kids-unlock' in Path('/etc/pam.d/omarchy-lock-password').read_text()
for number in range(2, 7):
    assert os.readlink(f'/etc/systemd/system/getty@tty{number}.service') == '/dev/null'
run('runuser', '-u', 'kid', '--', 'sudo', '-k', '-S', '-p', '', '/usr/bin/true', input='ci-parent-password\n')
refused = subprocess.run(['runuser', '-u', 'kid', '--', 'sudo', '-k', '-S', '-p', '', '/usr/bin/true'],
                         input='ci-kid-password\n', text=True, capture_output=True)
assert refused.returncode != 0, 'the kid password must never authorize sudo'
run('runuser', '-u', 'kid', '--', 'sudo', '-K')
assert subprocess.run(['runuser', '-u', 'kid', '--', 'sudo', '-n', '/usr/bin/true'], capture_output=True).returncode != 0
cache = Path('/var/cache/omarchy-kids/packages')
assert len(list(cache.glob('*.pkg.tar.zst'))) == 7
assert personal.read_text() == 'keep me'

# A completed --convert is a normal update on retry; it never resets passwords
# or spends another LUKS slot.
with patch.object(conversion.getpass, 'getpass', side_effect=AssertionError('unexpected password reset')):
    installer.main()
latest = json.loads(subprocess.check_output(['cryptsetup', 'luksDump', '--dump-json-metadata', device], text=True))['keyslots']
assert latest == after
print('PASS: conversion, retry, real parent-only sudo, dual disk keys, PAM and package cache')
