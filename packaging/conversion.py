"""Convert one clean Omarchy 4 account without replacing its home or disk keys."""
import ctypes
import ctypes.util
import getpass
import hmac
import json
import os
import pwd
import re
import shutil
import subprocess
from contextlib import contextmanager
from pathlib import Path

STATE = Path('/var/lib/omarchy/kids-conversion')
PROFILE = Path('/etc/omarchy/profile')


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def password_matches(username, password):
    # Python 3.13 removed crypt/spwd. Use libcrypt directly to check the local
    # shadow hash, including yescrypt, without putting either secret in argv.
    hashed = output('getent', 'shadow', username).split(':')[1]
    if not hashed or hashed.startswith(('!', '*')):
        return False
    library = ctypes.CDLL(ctypes.util.find_library('crypt') or 'libcrypt.so.2')
    library.crypt.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    library.crypt.restype = ctypes.c_char_p
    actual = library.crypt(password.encode(), hashed.encode())
    return bool(actual) and hmac.compare_digest(actual, hashed.encode())


def luks_ancestors(tree):
    devices = set()
    for item in tree:
        if item.get('fstype') == 'crypto_LUKS':
            devices.add(item['name'])
        devices.update(luks_ancestors(item.get('children', [])))
    return devices


def root_luks_device():
    source = output('findmnt', '-nro', 'SOURCE', '/').split('[', 1)[0]
    if not source.startswith('/dev/'):
        raise ValueError('conversion requires a normal local Omarchy root filesystem')
    tree = json.loads(output('lsblk', '--inverse', '--json', '--paths', '--output', 'NAME,FSTYPE', source))
    devices = luks_ancestors(tree['blockdevices'])
    if len(devices) > 1:
        raise ValueError('multiple encrypted root devices need a separate conversion procedure')
    return next(iter(devices), None)


@contextmanager
def key_fd(password):
    # Anonymous RAM-backed descriptor: no password files, arguments or logs.
    fd = os.memfd_create('omarchy-kids-key', os.MFD_CLOEXEC)
    try:
        os.write(fd, password.encode())
        os.lseek(fd, 0, os.SEEK_SET)
        yield fd
    finally:
        os.close(fd)


def unlocks(device, password):
    with key_fd(password) as fd:
        return subprocess.run(['cryptsetup', 'open', '--test-passphrase', '--key-file',
                               f'/proc/self/fd/{fd}', device], pass_fds=(fd,),
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def add_disk_key(device, current, parent):
    if unlocks(device, parent):
        return  # Also makes a retry after an interrupted conversion safe.
    with key_fd(current) as old_fd, key_fd(parent) as new_fd:
        subprocess.run(['cryptsetup', 'luksAddKey', '--batch-mode', '--key-file',
                        f'/proc/self/fd/{old_fd}', device, f'/proc/self/fd/{new_fd}'],
                       pass_fds=(old_fd, new_fd), check=True)
    if not unlocks(device, parent):
        raise ValueError('could not verify the new parent disk key; existing keys are still present')


def check_sudoers(source, username, etc=Path('/etc')):
    subprocess.run(['visudo', '-c'], check=True, stdout=subprocess.DEVNULL)
    main = (etc / 'sudoers').read_text()
    # A conversion of a clean install must not silently retain an override
    # that asks for the kid's password, or grants passwordless administration.
    for raw in main.splitlines():
        line = raw.strip()
        if not line or line.startswith('#') and not line.startswith(('#include', '#includedir')):
            continue
        if re.fullmatch(r'(?:@|#)includedir\s+/etc/sudoers.d/?', line):
            continue
        if re.fullmatch(r'(root|%wheel)\s+ALL\s*=\s*\(ALL(?::ALL)?\)\s+ALL', line):
            continue
        # These ordinary defaults do not select an authentication identity.
        if re.fullmatch(r'Defaults\s+(env_reset|use_pty|always_set_home|mail_badpass|secure_path\s*=\s*"[^"]+")', line):
            continue
        raise ValueError('custom /etc/sudoers settings need review before conversion')
    for file in (etc / 'sudoers.d').iterdir():
        if '.' in file.name or file.name.endswith('~') or not file.is_file():
            continue  # sudo does not read these names in an includedir.
        expected = source / 'etc/sudoers.d' / file.name
        if expected.is_file() and file.read_text() == expected.read_text():
            continue
        lines = [line.strip() for line in file.read_text().splitlines()
                 if line.strip() and not line.lstrip().startswith('#')]
        if lines and all(re.fullmatch(r'(?:%wheel|' + re.escape(username) +
                                     r')\s+ALL\s*=\s*\(ALL(?::ALL)?\)\s+ALL', line) for line in lines):
            continue
        raise ValueError(f'custom sudo rule {file} needs review before conversion')


class Conversion:
    def __init__(self, user, source, state=STATE):
        self.user, self.source, self.state = user, source, state
        self.journal = state / 'conversion.json'
        self.saved = json.loads(self.journal.read_text()) if self.journal.exists() else {}
        if self.saved and self.saved['user'] != user:
            raise ValueError(f'resume conversion with --user {self.saved["user"]}')

    @property
    def pending(self):
        return bool(self.saved) and self.saved.get('phase') != 'complete'

    def prepare(self):
        account = pwd.getpwnam(self.user)
        if account.pw_uid < 1000 or account.pw_uid == 65534 or not re.fullmatch(r'[a-z_][a-z0-9_-]*', self.user):
            raise ValueError('choose the existing regular Omarchy account')
        if not self.pending:
            regular = [u.pw_name for u in pwd.getpwall() if 1000 <= u.pw_uid < 65534]
            if regular != [self.user]:
                raise ValueError('conversion currently supports a clean laptop with one regular account')
            version = Path('/usr/share/omarchy/version')
            if not version.exists() or not version.read_text().strip().startswith('4.'):
                raise ValueError('conversion requires the Omarchy 4 package layout; upgrade Omarchy first')
            if not (Path(account.pw_dir) / '.config/hypr/hyprland.lua').is_file():
                raise ValueError('the account must have completed normal Omarchy 4 setup first')
            check_sudoers(self.source, self.user)
        if output('passwd', '-S', self.user).split()[1] != 'P':
            raise ValueError('the kid account needs a working local login password')
        groups = set(output('id', '-nG', self.user).split())
        if groups & {'disk', 'lxd', 'incus-admin', 'lxc'} or output('id', '-gn', self.user) in {'wheel', 'docker', 'root'}:
            raise ValueError('custom privileged account groups need review before conversion')
        device = root_luks_device()
        uuid = output('cryptsetup', 'luksUUID', device) if device else None
        if self.pending and uuid != self.saved.get('luks_uuid'):
            raise ValueError('the root disk changed since conversion started; refusing to continue')
        print(f'Converting {self.user} to a kid account. Its login password and home will be kept.', flush=True)
        print('The parent password will also unlock the encrypted disk.' if device else
              'This disk is unencrypted; conversion will leave it unencrypted.', flush=True)
        if not os.isatty(0):
            raise ValueError('run conversion in a terminal so passwords can be entered privately')
        parent = getpass.getpass('Parent password: ' if self.saved.get('root_password_set') else 'New parent password: ')
        if not parent or any(c in parent for c in '\n\r\0'):
            raise ValueError('the parent password cannot be empty or contain line breaks')
        if self.saved.get('root_password_set'):
            if not password_matches('root', parent):
                raise ValueError('enter the parent password set by the previous conversion attempt')
        elif parent != getpass.getpass('Confirm parent password: '):
            raise ValueError('parent passwords did not match')
        if password_matches(self.user, parent):
            raise ValueError('the parent password must differ from the kid login password')
        current = None
        if device and not unlocks(device, parent):
            current = getpass.getpass('Current disk-unlock password: ')
            if not unlocks(device, current):
                raise ValueError('current disk-unlock password was not accepted; nothing was changed')
        self.device, self.uuid, self.parent, self.current = device, uuid, parent, current

    def save(self, **changes):
        self.saved.update(changes)
        self.state.mkdir(parents=True, mode=0o700, exist_ok=True)
        self.state.chmod(0o700)
        stage = self.journal.with_suffix('.new')
        stage.touch(mode=0o600, exist_ok=True)
        stage.write_text(json.dumps(self.saved, indent=2) + '\n')
        os.replace(stage, self.journal)

    def begin(self):
        if self.pending:
            return
        self.state.mkdir(parents=True, mode=0o700, exist_ok=True)
        self.state.chmod(0o700)
        backup = self.state / 'before'
        backup.mkdir(mode=0o700, exist_ok=True)
        for relative in ('etc/shadow', 'etc/group', 'etc/gshadow', 'etc/sudoers', 'etc/sudoers.d',
                         'etc/polkit-1/rules.d', 'etc/pam.d', 'etc/omarchy.conf', 'etc/omarchy/profile'):
            file = Path('/') / relative
            target = backup / relative
            if not file.exists() or target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            if file.is_dir():
                shutil.copytree(file, target, symlinks=True)
            else:
                shutil.copy2(file, target)
        if self.device and not (backup / 'luks-header').exists():
            subprocess.run(['cryptsetup', 'luksHeaderBackup', self.device, '--header-backup-file',
                            str(backup / 'luks-header')], check=True)
        self.save(user=self.user, phase='prepared', luks_uuid=self.uuid, root_password_set=False)

    def activate(self):
        # Packages are installed before we touch credentials. Keep every old
        # LUKS slot, so failure at any later step still permits disk recovery.
        if self.device:
            add_disk_key(self.device, self.current, self.parent)
        if not self.saved.get('root_password_set'):
            subprocess.run(['chpasswd'], input='root:' + self.parent + '\n', text=True, check=True)
            self.save(root_password_set=True, phase='parent-password-set')
        PROFILE.parent.mkdir(parents=True, exist_ok=True)
        PROFILE.write_text('child\n')
        PROFILE.chmod(0o644)
        self.save(phase='configuring-child')
        self.parent = self.current = None

    def finish(self):
        self.save(phase='complete')
