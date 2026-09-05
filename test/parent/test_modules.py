import copy
import importlib.util
import json
import os
import pwd
import sys
import subprocess
import tempfile
import threading
import time
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lib/parent'))
from omarchy_kids.core import paths
from omarchy_kids.core.auth import ParentAuth
from omarchy_kids.core.daemon import Daemon
from omarchy_kids.core.files import browser_change, config_change, adopt_browser_policy
from omarchy_kids.core.migrate import migrate, split_config
from omarchy_kids.core.storage import write_json, read_json
from omarchy_kids.school_mode.policy import Policy
from omarchy_kids.school_mode.config import sanitize_profile


class ModulesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kids-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {'SCREEN_TIME_ROOT': str(self.base), 'SCREEN_TIME_LOCK_COMMAND': '/usr/bin/true', 'OMARCHY_PATH': str(ROOT)})
        self.env.start(); self.addCleanup(self.env.stop)
        self.uid = os.getuid() or pwd.getpwnam('nobody').pw_uid
        self.user = pwd.getpwuid(self.uid).pw_name
        self.layout = paths.detect()
        write_json(self.layout.config_path, {'version': 3, 'active_profile': 'default', 'profiles': {'default': {}}, 'users': {}})

    def host(self, modules=None):
        host = Daemon(self.layout, modules=modules, log=lambda _: None)
        host.auth = ParentAuth(verifier=lambda username, password: password == 'correct')
        return host

    def send(self, host, scope, command, parent=True, **kw):
        return host.dispatch(0 if parent else self.uid, {'scope': scope, 'cmd': command, 'user': self.user, **kw})

    def enable(self, host, scope):
        result = self.send(host, scope, 'users.set', enabled=True)
        self.assertTrue(result['ok'], result)

    def test_independent_enrollment(self):
        host = self.host()
        self.enable(host, 'school')
        self.assertEqual(self.send(host, 'time', 'status')['error'], 'not_managed')
        self.assertTrue(self.send(host, 'school', 'mode.set', mode='school', parent=False)['ok'])
        self.assertEqual(self.send(host, 'school', 'mode.set', mode='free', parent=False)['error'], 'parent_required')
        self.enable(host, 'time')
        self.send(host, 'time', 'users.set', enabled=False)
        self.assertEqual(self.send(host, 'school', 'mode.get')['mode'], 'school')
        self.enable(host, 'time')
        self.send(host, 'school', 'users.set', enabled=False)
        self.assertTrue(self.send(host, 'time', 'status')['ok'])
        self.assertEqual(host.school_snapshot(self.uid, host.clock.now()), {})

    def test_missing_backends(self):
        for modules in ([], ['time'], ['school'], ['time', 'school']):
            host = self.host(modules)
            self.assertEqual(set(host.services), set(modules))
            for feature in {'time', 'school'} - set(modules):
                self.assertEqual(self.send(host, feature, 'status')['error'], 'module_not_installed')

    def test_authentication_and_target_scope(self):
        host = self.host(); self.enable(host, 'school'); self.enable(host, 'time')
        bad = self.send(host, 'school', 'mode.set', mode='free', parent=False, password='wrong')
        self.assertEqual(bad['error'], 'bad_password')
        good = self.send(host, 'school', 'mode.set', mode='free', parent=False, password='correct')
        self.assertTrue(good['ok'])
        self.assertEqual(host.resolve_uid(self.uid, {'user': 'root'}), self.uid)
        self.assertEqual(self.send(host, 'time', 'grant', parent=False, minutes=5)['error'], 'bad_password')
        self.assertEqual(self.send(host, 'school', 'config.get', parent=False, password='wrong')['error'], 'bad_password')
        self.assertEqual(self.send(host, 'time', 'config.get', parent=False, password='wrong')['error'], 'password_locked_out')

    def test_slow_auth_does_not_hold_clock_lock(self):
        host = self.host(); self.enable(host, 'school'); self.enable(host, 'time')
        checking, finish = threading.Event(), threading.Event()
        def verify(*_):
            checking.set(); finish.wait(3); return True
        host.auth = ParentAuth(verifier=verify)
        thread = threading.Thread(target=lambda: self.send(host, 'school', 'mode.set', mode='free', parent=False, password='correct'))
        thread.start(); self.assertTrue(checking.wait(1))
        try:
            self.assertTrue(host.lock.acquire(timeout=0.2)); host.lock.release()
            self.assertTrue(self.send(host, 'time', 'status')['ok'])
            self.assertEqual(self.send(host, 'school', 'mode.set', mode='free', parent=False, password='correct')['error'], 'password_checking')
        finally:
            finish.set(); thread.join(2)

    def test_migration_preserves_profiles_and_is_repeatable(self):
        legacy = {'version': 2, 'active_profile': 'shared', 'users': {self.user: {'profile': 'shared'}},
                  'profiles': {'shared': {'budget_minutes': {'mon': 20}, 'school_apps': ['chromium'],
                    'blocked_periods': [{'mode': 'free', 'enabled': True, 'label': 'Class', 'start': '08:00', 'end': '15:00'},
                                        {'mode': 'block', 'enabled': True, 'label': 'Bedtime', 'start': '20:00', 'end': '07:00'}]}}}
        write_json(self.layout.config_path, legacy); migrate(self.layout)
        expected_time, expected_school = split_config(legacy)
        self.assertEqual(read_json(self.layout.config_path), expected_time)
        self.assertEqual(read_json(self.base / 'school-mode.json'), expected_school)
        self.assertEqual(read_json(self.base / 'config.json.before-kids-modules'), legacy)
        migrate(self.layout)
        self.assertEqual(read_json(self.layout.config_path), expected_time)
        # Replay a crash after the journal, before the last file replacement.
        write_json(self.base / '.kids-migration.json', {'time': expected_time, 'school': expected_school})
        (self.base / 'school-mode.json').unlink(); migrate(self.layout)
        self.assertEqual(read_json(self.base / 'school-mode.json'), expected_school)

    def test_module_settings_cannot_write_other_module(self):
        host = self.host(); self.enable(host, 'school'); self.enable(host, 'time')
        result = self.send(host, 'school', 'config.patch', patch={'budget_minutes': {'mon': 0}})
        self.assertEqual(result['error'], 'bad_patch')
        result = self.send(host, 'time', 'config.patch', patch={'school_apps': ['chromium'], 'earn': {'level': 'grade1'}})
        self.assertEqual(result['error'], 'mixed_module_patch')
        self.assertEqual(host.services['time'].config['profiles'][self.user]['earn']['level'], 'grade5')

    def test_policy_and_accounting_precedence(self):
        host = self.host(); self.enable(host, 'school'); self.enable(host, 'time')
        now = datetime(2026, 9, 2, 18, 0).timestamp(); host.clock.logical = now
        policy = host.services['school'].policy_for(self.uid)
        account = host.services['time'].account_for(self.uid)
        policy.set_mode('school', now, False)
        self.assertFalse(account.screen_time_exempt(now))
        policy.set_mode('school', now, True)
        self.assertTrue(account.screen_time_exempt(now))
        account.profile['blocked_periods'] = [{'enabled': True, 'mode': 'block', 'start': '20:00', 'end': '07:00'}]
        self.assertFalse(account.screen_time_exempt(datetime(2026, 9, 2, 21, 0).timestamp()))
        policy.profile['blocked_periods'] = [{'enabled': True, 'mode': 'free', 'label': 'School', 'start': '17:00', 'end': '22:00'}]
        policy.set_mode('free', now, True)
        self.assertTrue(account.screen_time_exempt(now))
        self.assertTrue(account.screen_time_exempt(datetime(2026, 9, 2, 21, 0).timestamp()))

    def test_browsing_and_dns_policy_ownership(self):
        target = self.base / 'policies.json'
        write_json(target, {'policies': {'Custom': 42, 'DisablePrivateBrowsing': False}})
        browser_change(target, 'dns', {'DNSOverHTTPS': {'Enabled': False}})
        browser_change(target, 'browsing', {'DisablePrivateBrowsing': True})
        browser_change(target, 'dns', {})
        self.assertEqual(read_json(target)['policies'], {'Custom': 42, 'DisablePrivateBrowsing': True})
        browser_change(target, 'browsing', {})
        self.assertEqual(read_json(target)['policies'], {'Custom': 42, 'DisablePrivateBrowsing': False})

    def test_shared_configuration_concurrent_updates(self):
        target = self.base / 'parent.conf'
        threads = [threading.Thread(target=config_change, args=(target, name, 'on')) for name in ('dns', 'wifi', 'test')]
        for t in threads: t.start()
        for t in threads: t.join()
        for name in ('dns', 'wifi', 'test'):
            self.assertIn(name + '=on', target.read_text())

    def test_practice_works_with_enforcement_off(self):
        self.assertFalse(self.layout.socket_path.exists())
        output = subprocess.check_output(['bash', str(ROOT / 'bin/omarchy-kids-time-client'), 'practice', 'grade5'], text=True)
        response = json.loads(output)
        self.assertTrue(response['ok'])
        self.assertTrue('×' in response['text'] or '÷' in response['text'])
        self.assertIsInstance(response['answer'], int)

    def test_legacy_browser_keys_are_adopted_before_removal(self):
        target = self.base / 'policies.json'
        original = {'policies': {'Custom': 42, 'DNSOverHTTPS': {'Enabled': False, 'Locked': True}, 'DisablePrivateBrowsing': True}}
        write_json(target, original)
        adopt_browser_policy(target, ['dns', 'browsing'])
        browser_change(target, 'dns', {})
        self.assertEqual(read_json(target)['policies'], {'Custom': 42, 'DisablePrivateBrowsing': True})
        browser_change(target, 'browsing', {})
        self.assertEqual(read_json(target)['policies'], {'Custom': 42})
        self.assertEqual(read_json(target.with_name('policies.json.before-kids-modules')), original)

    def test_invalid_school_schedule_does_not_change_policy(self):
        host = self.host(); self.enable(host, 'school')
        before = copy.deepcopy(host.services['school'].config)
        for periods in (None, [{'mode': 'block', 'start': '08:00', 'end': '15:00'}], [{'mode': 'free', 'start': '27:00', 'end': '28:00'}]):
            result = self.send(host, 'school', 'config.patch', patch={'blocked_periods': periods})
            self.assertEqual(result['error'], 'bad_patch')
            self.assertEqual(host.services['school'].config, before)

    def test_manual_school_choice_survives_restart(self):
        host = self.host(); self.enable(host, 'school')
        self.send(host, 'school', 'mode.set', mode='school', parent=False)
        host.services['school'].save()
        restarted = self.host()
        response = self.send(restarted, 'school', 'mode.get', parent=False)
        self.assertEqual((response['mode'], response['mode_reason']), ('school', 'chosen'))
        self.assertEqual(self.send(restarted, 'school', 'mode.set', mode='free', parent=False)['error'], 'parent_required')

    def test_enabling_again_preserves_shared_profile_assignments(self):
        host = self.host()
        for scope in ('school', 'time'):
            service = host.services[scope]
            service.config['profiles']['shared'] = copy.deepcopy(service.config['profiles']['default'])
            service.config['users'][self.user] = {'profile': 'shared'}
            self.enable(host, scope)
            self.assertEqual(service.config['users'][self.user]['profile'], 'shared')

            self.send(host, scope, 'users.set', enabled=False)
            self.enable(host, scope)
            self.assertEqual(service.config['users'][self.user]['profile'], 'shared')

    def test_migration_accepts_an_unconfigured_school_initializer(self):
        legacy = {'version': 2, 'active_profile': 'default', 'profiles': {'default': {'name': 'Default', 'blocked_periods': [{'mode': 'free', 'start': '08:00', 'end': '15:00'}]}}, 'users': {}}
        write_json(self.layout.config_path, legacy)
        write_json(self.base / 'school-mode.json', {'version': 1, 'active_profile': 'default', 'profiles': {'default': {}}, 'users': {}})
        migrate(self.layout)
        self.assertEqual(read_json(self.base / 'school-mode.json')['profiles']['default']['blocked_periods'], legacy['profiles']['default']['blocked_periods'])

if __name__ == '__main__':
    unittest.main()
