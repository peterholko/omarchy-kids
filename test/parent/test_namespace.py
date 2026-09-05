import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lib/parent'))
from omarchy_kids.core.namespace import Migration, check_command_collisions


class NamespaceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kids-rename-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def put(self, name, data, mode=0o644):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        path.chmod(mode)
        return path

    def test_integration_migration_preserves_data_permissions_and_backups(self):
        old = 'omarchy-parent'
        unit = self.put(f'etc/systemd/system/{old}-timed.service', f'ExecStart=/usr/bin/{old}-timed\nRuntimeDirectory={old}/screen-time\n')
        self.put(f'etc/systemd/system/{old}-timed.service.d/custom.conf', f'Environment=OMARCHY_PARENT_CONF=/custom/settings.conf\n')
        link = self.root / f'etc/systemd/system/multi-user.target.wants/{old}-timed.service'
        link.parent.mkdir()
        link.symlink_to('/etc/systemd/system/' + old + '-timed.service')
        self.put(f'etc/sudoers.d/{old}-kid', 'kid ALL=(ALL:ALL) ALL\n', 0o440)
        self.put('etc/pam.d/omarchy-lock-password', f'auth sufficient pam_exec.so /usr/bin/{old}-unlock\n')
        resolver = self.put('etc/omarchy/parent/dnsmasq.conf', f'resolv-file=/run/{old}/dns/resolv.conf\naddress=/{old}.example/\n')
        policy = '{"policies":{"WebsiteFilter":{"Block":["omarchy-parent.example"]}}}\n'
        self.put(f'etc/chromium/policies/managed/{old}-dns.json', policy)
        self.put(f'usr/lib/firefox/distribution/.{old}-policies.json', policy, 0o600)
        history = self.put('var/lib/omarchy/parent/kid/browsing/history.tsv', 'existing history\n', 0o600)
        settings = self.put('etc/omarchy/parent/screen-time.json', '{"users":{"kid":{"profile":"shared"}}}\n', 0o600)
        external = self.put('etc/sudoers.d/omarchy-parent-llm', 'kid ALL=(root) NOPASSWD: /usr/bin/omarchy-parent-llm collect\n', 0o440)
        migration = Migration(self.root)
        migration.apply(systemd=False)
        new_unit = self.root / 'etc/systemd/system/omarchy-kids-timed.service'
        self.assertIn('/usr/bin/omarchy-kids-timed', new_unit.read_text())
        self.assertFalse(unit.exists())
        self.assertEqual(os.readlink(link.with_name('omarchy-kids-timed.service')), '/etc/systemd/system/omarchy-kids-timed.service')
        self.assertIn('OMARCHY_KIDS_CONF', (self.root / 'etc/systemd/system/omarchy-kids-timed.service.d/custom.conf').read_text())
        self.assertEqual((self.root / 'etc/sudoers.d/omarchy-kids-kid').stat().st_mode & 0o777, 0o440)
        self.assertIn('/usr/bin/omarchy-kids-unlock', (self.root / 'etc/pam.d/omarchy-lock-password').read_text())
        self.assertIn('/run/omarchy-kids/dns', resolver.read_text())
        self.assertIn('address=/omarchy-parent.example/', resolver.read_text())
        for name in ('etc/chromium/policies/managed/omarchy-kids-dns.json', 'usr/lib/firefox/distribution/.omarchy-kids-policies.json'):
            self.assertEqual((self.root / name).read_text(), policy)
        self.assertEqual(history.read_text(), 'existing history\n')
        self.assertEqual(settings.read_text(), '{"users":{"kid":{"profile":"shared"}}}\n')
        self.assertIn('/usr/bin/omarchy-parent-llm', external.read_text())
        saved = migration.backup / 'originals/etc/systemd/system' / (old + '-timed.service')
        self.assertIn(old + '-timed', saved.read_text())
        self.assertEqual(migration.plan(), [])
        migration.apply(systemd=False)
        self.assertIn(old + '-timed', saved.read_text())

    def test_conflicting_names_abort_before_any_changes(self):
        original = 'kid ALL=(ALL:ALL) ALL\n# original\n'
        different = 'kid ALL=(ALL:ALL) ALL\n# different\n'
        old = self.put('etc/sudoers.d/omarchy-parent-kid', original, 0o440)
        new = self.put('etc/sudoers.d/omarchy-kids-kid', different, 0o440)
        pam = self.put('etc/pam.d/omarchy-lock-password', '/usr/bin/omarchy-parent-unlock')
        calls = []
        with self.assertRaisesRegex(ValueError, 'namespace collision'):
            Migration(self.root, run=lambda *args, **kwargs: calls.append(args)).apply()
        self.assertEqual(calls, [])
        self.assertEqual(old.read_text(), original)
        self.assertEqual(new.read_text(), different)
        self.assertEqual(pam.read_text(), '/usr/bin/omarchy-parent-unlock')

    def test_restart_failure_can_resume_after_old_unit_has_moved(self):
        old = 'omarchy-parent-timed.service'
        new = 'omarchy-kids-timed.service'
        self.put('etc/systemd/system/' + old, 'ExecStart=/usr/bin/omarchy-parent-timed\n')
        calls = []
        active = {old}
        fail_start = True

        def run(args, **kwargs):
            nonlocal fail_start
            calls.append(args)
            operation, unit = args[1], args[-1]
            if operation == 'is-active':
                return subprocess.CompletedProcess(args, 0 if unit in active else 3)
            if operation == 'is-enabled':
                return subprocess.CompletedProcess(args, 0 if unit == old else 1)
            if operation == 'stop':
                active.discard(unit)
            if operation == 'start' and fail_start:
                fail_start = False
                raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0)

        migration = Migration(self.root, run)
        with self.assertRaises(subprocess.CalledProcessError):
            migration.apply()
        self.assertTrue(migration.journal.exists())
        migration.apply()
        self.assertFalse(migration.journal.exists())
        self.assertEqual(calls.count(['systemctl', 'stop', old]), 1)
        self.assertEqual(calls.count(['systemctl', 'start', new]), 2)
        self.assertIn(['systemctl', 'enable', new], calls)

    def test_local_command_shadowing_is_detected(self):
        self.put('usr/local/bin/omarchy-kids-menu', 'unrelated menu')
        check_command_collisions(ROOT, self.root)
        self.put('usr/local/bin/omarchy-kids-time', 'custom command')
        with self.assertRaisesRegex(ValueError, 'command collision'):
            check_command_collisions(ROOT, self.root)
