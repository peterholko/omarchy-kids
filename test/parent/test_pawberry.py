import contextlib
import io
import json
import os
import pwd
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lib/parent'))
from omarchy_kids.core import paths, proto
from omarchy_kids.core.auth import ParentAuth
from omarchy_kids.core.daemon import Daemon
from omarchy_kids.pawberry import client
from omarchy_kids.pawberry.service import answer_for


class PawberryLimitsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='pawberry-limits-', dir='/tmp')
        self.addCleanup(self.tmp.cleanup)
        env = patch.dict(os.environ, {'SCREEN_TIME_ROOT': self.tmp.name})
        env.start(); self.addCleanup(env.stop)
        self.uid = os.getuid() or pwd.getpwnam('nobody').pw_uid
        self.user = pwd.getpwuid(self.uid).pw_name
        self.host = self.make_host()

    def make_host(self):
        host = Daemon(paths.detect(), modules=['pawberry'], log=lambda _: None)
        host.clock.logical = datetime(2026, 9, 10, 12).timestamp()
        host.auth = ParentAuth(verifier=lambda user, password: password == 'correct')
        return host

    def send(self, command, parent=False, **kw):
        return self.host.dispatch(0 if parent else self.uid, {'scope': 'pawberry', 'cmd': command, 'user': self.user, **kw})

    def begin(self, operation='add', a=24, b=12):
        return self.send('begin', problem={'operation': operation, 'a': a, 'b': b})

    def finish(self, operation='add', a=24, b=12):
        issue = self.begin(operation, a, b)
        self.assertTrue(issue['ok'], issue)
        return self.send('complete', id=issue['id'], answer=answer_for({'a': a, 'b': b, 'operation': operation}))

    def test_independent_limits_and_restart(self):
        self.assertEqual(set(self.host.services), {'pawberry'})
        self.assertEqual(self.send('status')['remaining'], dict.fromkeys(('add','subtract','multiply','divide')))
        self.assertTrue(self.send('limits.set', parent=True, limits={'add': 2, 'subtract': 1})['ok'])
        for _ in range(2): self.assertTrue(self.finish()['ok'])
        self.assertEqual(self.begin()['error'], 'daily_limit')
        self.assertTrue(self.finish('subtract')['ok'])
        self.assertEqual(self.begin('subtract')['error'], 'daily_limit')
        for op, a, b in [('multiply', 7, 8), ('divide', 56, 8)]: self.assertTrue(self.finish(op, a, b)['ok'])
        self.host = self.make_host()
        self.assertEqual(self.begin()['error'], 'daily_limit')
        self.assertEqual(self.send('status')['completed'], {'add':2,'subtract':1,'multiply':1,'divide':1})
        for file in Path(self.tmp.name).rglob('*.json'):
            self.assertEqual(file.stat().st_mode & 0o077, 0, str(file))

    def test_restarts_and_wrong_attempts_do_not_spend_slots(self):
        self.send('limits.set', parent=True, limits={'add':1})
        for _ in range(20): issue = self.begin()
        self.assertEqual(self.send('status')['completed']['add'], 0)
        self.assertEqual(self.send('complete', id=issue['id'], answer=37)['error'], 'incorrect_answer')
        self.assertEqual(self.send('complete', id=issue['id'], answer=True)['error'], 'incorrect_answer')
        self.host = self.make_host()
        result = self.send('complete', id=issue['id'], answer=36)
        self.assertEqual(result['remaining']['add'], 0)
        self.assertTrue(self.send('complete', id=issue['id'], answer=36)['already_completed'])
        self.assertEqual(self.send('status')['completed']['add'], 1)

    def test_authentication_and_peer_identity(self):
        self.assertEqual(self.send('limits.set', limits={'add':0})['error'], 'bad_password')
        self.assertTrue(self.send('limits.set', limits={'add':0}, password='correct', user='root')['ok'])
        self.assertEqual(self.send('status')['limits']['add'], 0)
        self.assertEqual(self.begin()['error'], 'daily_limit')
        self.assertEqual(self.send('reset')['error'], 'unknown_command')
        self.assertEqual(self.send('limits.set', parent=True, limits={'divide':0})['error'], 'invalid_limits')
        for value in [-1, True, '5', 2.5, 10001]:
            self.assertEqual(self.send('limits.set', parent=True, limits={'add':value})['error'], 'invalid_limits')
        self.assertTrue(self.send('limits.set', parent=True, limits={'add':None})['ok'])
        self.assertTrue(self.finish()['ok'])

    def test_day_rollover_and_clock_rollback(self):
        self.send('limits.set', parent=True, limits={'add':1})
        result = self.finish(); receipt = result['id']
        self.host.clock.logical = datetime(2026, 9, 11, 0, 1).timestamp()
        self.assertEqual(self.send('status')['remaining']['add'], 1)
        self.assertTrue(self.send('complete', id=receipt, answer=36)['already_completed'])
        self.assertEqual(self.send('status')['completed']['add'], 0)
        self.finish()
        self.host.clock.logical = datetime(2026, 9, 10, 23).timestamp()
        self.assertEqual(self.begin()['error'], 'daily_limit')
        self.assertEqual(self.send('status')['day'], '2026-09-11')

    def test_multiplication_limit_shares_all_digit_levels_and_keeps_existing_counts(self):
        self.assertIsNone(self.send('status')['limits']['multiply'])
        self.assertTrue(self.finish('multiply', 7, 8)['ok'])
        self.host = self.make_host()
        result = self.send('limits.set', password='correct', limits={'multiply':3})
        self.assertEqual(result['completed']['multiply'], 1)
        self.assertEqual(result['remaining']['multiply'], 2)
        for _ in range(3): issued = self.begin('multiply', 7, 8)
        self.assertEqual(self.send('complete', id=issued['id'], answer=55)['error'], 'incorrect_answer')
        self.assertEqual(self.send('status')['remaining']['multiply'], 2)
        self.assertTrue(self.finish('multiply', 24, 12)['ok'])
        result = self.finish('multiply', 123, 234)
        self.assertEqual(result['remaining']['multiply'], 0)
        self.assertTrue(self.send('complete', id=result['id'], answer=28782)['already_completed'])
        self.host = self.make_host()
        for a, b in [(7, 8), (24, 12), (123, 234)]:
            self.assertEqual(self.begin('multiply', a, b)['error'], 'daily_limit')
        self.assertEqual(self.send('status')['completed']['multiply'], 3)
        self.assertTrue(self.finish('divide', 56, 8)['ok'])
        self.host.clock.logical = datetime(2026, 9, 11, 0, 1).timestamp()
        self.assertEqual(self.send('status')['remaining']['multiply'], 3)
        self.assertTrue(self.finish('multiply', 7, 8)['ok'])

    def test_multiplication_unavailable_unlimited_and_partial_updates(self):
        issued = self.begin('multiply', 7, 8)
        self.assertEqual(self.send('limits.set', limits={'multiply':0})['error'], 'bad_password')
        self.assertTrue(self.send('limits.set', password='correct', limits={'multiply':0})['ok'])
        self.assertEqual(self.send('complete', id=issued['id'], answer=56)['error'], 'daily_limit')
        self.assertEqual(self.begin('multiply', 24, 12)['error'], 'daily_limit')
        self.send('settings.set', password='correct', limits={'add':5,'subtract':5})
        self.assertEqual(self.send('status')['limits']['multiply'], 0)
        self.send('limits.set', password='correct', limits={'multiply':None})
        self.assertTrue(self.finish('multiply', 7, 8)['ok'])
        self.assertEqual(self.send('status')['limits'], {'add':5,'subtract':5,'multiply':None})

    def test_parent_lowering_limit_and_concurrent_windows(self):
        issue = self.begin()
        self.send('limits.set', parent=True, limits={'add':0})
        self.assertEqual(self.send('complete', id=issue['id'], answer=36)['error'], 'daily_limit')
        self.send('limits.set', parent=True, limits={'add':1})
        other = self.begin()
        self.assertEqual(self.send('complete', id=issue['id'], answer=36)['error'], 'stale_problem')
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: self.send('complete', id=other['id'], answer=36), range(8)))
        self.assertTrue(all(r['ok'] for r in results))
        self.assertEqual(sum(not r['already_completed'] for r in results), 1)
        self.assertEqual(self.send('status')['completed']['add'], 1)

    def test_slow_parent_auth_does_not_stop_other_requests(self):
        checking, release = threading.Event(), threading.Event()
        def verifier(*_): checking.set(); release.wait(3); return True
        self.host.auth = ParentAuth(verifier=verifier)
        worker = threading.Thread(target=lambda: self.send('limits.set', limits={'add':1}, password='correct'))
        worker.start(); self.assertTrue(checking.wait(1))
        try: self.assertTrue(self.send('status')['ok'])
        finally: release.set(); worker.join(2)

    def test_invalid_problems_and_failed_save_never_spend_or_acknowledge(self):
        for problem in [None, {}, {'a':True,'b':8,'operation':'multiply'}, {'a':57,'b':8,'operation':'divide'}, {'a':99,'b':3,'operation':'divide'}, {'a':9,'b':10,'operation':'add'}]:
            self.assertEqual(self.send('begin', problem=problem)['error'], 'invalid_problem')
        issue = self.begin()
        with patch('omarchy_kids.pawberry.service.storage.write_json', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.send('complete', id=issue['id'], answer=36)
        self.assertEqual(self.send('status')['completed']['add'], 0)
        self.assertTrue(self.send('complete', id=issue['id'], answer=36)['ok'])

    def test_game_client_round_trip_uses_peer_identity(self):
        self.send('limits.set', parent=True, limits={'add':1})
        self.host.listen()
        worker = threading.Thread(target=self.host.serve, daemon=True)
        worker.start()
        try:
            def request(payload):
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    code = client.main(['request', json.dumps(payload)])
                return code, json.loads(output.getvalue())
            code, issued = request({'cmd':'begin','user':'root','problem':{'operation':'add','a':12,'b':34}})
            self.assertEqual(code,0)
            code, result = request({'cmd':'complete','id':issued['id'],'answer':46})
            self.assertEqual(code,0)
            self.assertEqual(result['remaining']['add'],0)
            self.assertEqual(result['user'],self.user)
            code, result = request({'cmd':'begin','problem':{'operation':'add','a':12,'b':34}})
            self.assertEqual(code,1)
            self.assertEqual(result['error'],'daily_limit')
        finally:
            self.host.shutdown(); worker.join(2)

    def test_cli_password_and_unavailable_service(self):
        with patch.object(proto, 'request', return_value={'ok':True}) as request, patch('os.geteuid', return_value=self.uid), patch('sys.stdin', io.StringIO('correct\n')), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.main(['limits','--addition','0','--subtraction','unlimited','--password-stdin']), 0)
            payload = request.call_args.args[1]
            self.assertEqual(payload['limits'], {'add':0,'subtract':None})
            self.assertEqual(payload['password'], 'correct')
        with patch.object(proto, 'request', side_effect=OSError), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.main(['status']), 1)
        self.assertEqual(json.loads(output.getvalue()), {'ok':False, 'error':'unavailable'})

    def test_cli_multiplication_limit_for_both_parent_commands(self):
        for command in ('limits', 'settings'):
            for value, expected in [('5',5), ('0',0), ('unlimited',None)]:
                with patch.object(proto, 'request', return_value={'ok':True}) as request, patch('os.geteuid', return_value=self.uid), patch('sys.stdin', io.StringIO('correct\n')), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(client.main([command,'--multiplication',value,'--password-stdin']), 0)
                    payload = request.call_args.args[1]
                    self.assertEqual(payload['limits'], {'multiply':expected})
                    self.assertEqual(payload['password'], 'correct')


if __name__ == '__main__': unittest.main()
