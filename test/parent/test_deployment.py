import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packaging'))
import conversion
import release


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.packages = {}
        for name in release.PACKAGE_NAMES:
            version = '4.0.0.kids-42' if name.endswith(('base', 'settings')) else '0.1.0-42'
            file = name + '.pkg.tar.zst'
            (self.path / file).write_bytes(name.encode())
            self.packages[name] = dict(file=file, pkgname=name, pkgver=version, arch='any',
                                       sha256=hashlib.sha256(name.encode()).hexdigest())

    def verify(self):
        (self.path / 'release.json').write_text(json.dumps({'packages': self.packages}))
        def metadata(file):
            return {key: self.packages[file.name.removesuffix('.pkg.tar.zst')][key]
                    for key in ('pkgname', 'pkgver', 'arch')}
        with patch.object(release, 'metadata', side_effect=metadata):
            return release.verify(self.path, 'x86_64')

    def test_complete_matching_release(self):
        self.assertEqual(set(self.verify()), release.PACKAGE_NAMES)

    def test_incomplete_or_corrupt_release(self):
        (self.path / self.packages['omarchy-kids-core']['file']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.verify()
        del self.packages['omarchy-kids-core']
        with self.assertRaisesRegex(ValueError, 'catalog modules'):
            self.verify()

    def test_identity_architecture_and_revision_mismatch(self):
        core = self.packages['omarchy-kids-core']
        for field, value, error in [('pkgname', 'unrelated', 'identity'), ('arch', 'aarch64', 'architecture'),
                                    ('pkgver', '0.1.0-43', 'mixed')]:
            with self.subTest(field=field):
                original = core[field]
                core[field] = value
                with self.assertRaisesRegex(ValueError, error):
                    self.verify()
                core[field] = original

    def test_path_escape_is_rejected(self):
        self.packages['omarchy-kids-core']['file'] = '../outside.pkg.tar.zst'
        with self.assertRaisesRegex(ValueError, 'filename'):
            self.verify()


class ConversionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.profile = self.path / 'etc/omarchy/profile'
        self.patch = patch.object(conversion, 'PROFILE', self.profile)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.convert = conversion.Conversion('kid', ROOT, state=self.path / 'state')
        self.convert.save(user='kid', phase='prepared', luks_uuid='uuid', root_password_set=False)
        self.convert.device = '/dev/test-luks'
        self.convert.parent = 'test-parent-secret'
        self.convert.current = 'test-disk-secret'

    def test_activation_sets_only_root_password_and_journals_without_secrets(self):
        with patch.object(conversion, 'add_disk_key') as add, patch.object(conversion.subprocess, 'run') as run:
            self.convert.activate()
        add.assert_called_once_with('/dev/test-luks', 'test-disk-secret', 'test-parent-secret')
        run.assert_called_once_with(['chpasswd'], input='root:test-parent-secret\n', text=True, check=True)
        self.assertEqual(self.profile.read_text(), 'child\n')
        text = self.convert.journal.read_text()
        self.assertNotIn('test-parent-secret', text)
        self.assertNotIn('test-disk-secret', text)
        self.assertIsNone(self.convert.parent)
        self.assertEqual(self.convert.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.convert.journal.stat().st_mode & 0o777, 0o600)
        resumed = conversion.Conversion('kid', ROOT, state=self.path / 'state')
        self.assertTrue(resumed.pending)
        resumed.finish()
        self.assertFalse(resumed.pending)

    def test_failed_disk_setup_leaves_credentials_and_profile_unchanged(self):
        with patch.object(conversion, 'add_disk_key', side_effect=ValueError('disk failure')), \
                patch.object(conversion.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'disk failure'):
                self.convert.activate()
        run.assert_not_called()
        self.assertFalse(self.profile.exists())
        self.assertFalse(self.convert.saved['root_password_set'])

    def test_resuming_cannot_change_the_account_or_reset_parent_password(self):
        with self.assertRaisesRegex(ValueError, '--user kid'):
            conversion.Conversion('another-kid', ROOT, state=self.path / 'state')
        self.convert.save(root_password_set=True)
        with patch.object(conversion, 'add_disk_key'), patch.object(conversion.subprocess, 'run') as run:
            self.convert.activate()
        run.assert_not_called()

    def test_unencrypted_conversion_does_not_touch_cryptsetup(self):
        self.convert.device = None
        with patch.object(conversion, 'add_disk_key') as add, patch.object(conversion.subprocess, 'run'):
            self.convert.activate()
        add.assert_not_called()

    def test_disk_key_retry_never_removes_slots(self):
        with patch.object(conversion, 'unlocks', return_value=True), \
                patch.object(conversion.subprocess, 'run') as run:
            conversion.add_disk_key('/dev/test', None, 'parent')
        run.assert_not_called()

    def test_root_disk_discovery_handles_nested_lvm_and_multiple_devices(self):
        tree = [{'name': '/dev/mapper/root', 'fstype': 'btrfs', 'children': [
            {'name': '/dev/mapper/lvm', 'children': [{'name': '/dev/nvme0n1p2', 'fstype': 'crypto_LUKS'}]}]}]
        with patch.object(conversion, 'output', side_effect=['/dev/mapper/root[/@]', json.dumps({'blockdevices': tree})]):
            self.assertEqual(conversion.root_luks_device(), '/dev/nvme0n1p2')
        tree.append({'name': '/dev/another', 'fstype': 'crypto_LUKS'})
        with patch.object(conversion, 'output', side_effect=['/dev/mapper/root', json.dumps({'blockdevices': tree})]):
            with self.assertRaisesRegex(ValueError, 'multiple encrypted'):
                conversion.root_luks_device()

    def test_custom_sudo_rules_are_refused_before_conversion(self):
        etc = self.path / 'etc'
        etc.mkdir(exist_ok=True)
        (etc / 'sudoers.d').mkdir()
        (etc / 'sudoers').write_text('root ALL=(ALL:ALL) ALL\n@includedir /etc/sudoers.d\n')
        rule = etc / 'sudoers.d/00-omarchy-wheel'
        rule.write_text('%wheel ALL=(ALL:ALL) ALL\n')
        with patch.object(conversion.subprocess, 'run'):
            conversion.check_sudoers(ROOT, 'kid', etc)
            rule.write_text('kid ALL=(ALL:ALL) NOPASSWD: ALL\n')
            with self.assertRaisesRegex(ValueError, 'custom sudo rule'):
                conversion.check_sudoers(ROOT, 'kid', etc)
            rule.unlink()
            (etc / 'sudoers').write_text('Defaults !rootpw\n')
            with self.assertRaisesRegex(ValueError, 'custom /etc/sudoers'):
                conversion.check_sudoers(ROOT, 'kid', etc)


if __name__ == '__main__':
    unittest.main()
