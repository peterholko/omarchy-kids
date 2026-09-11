"""Real co-hosted services: optional credits, policy gates and durable retries."""
import contextlib
import io
import json
import os
import pwd
import sys
import tempfile
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


class PawberryRewardsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='pawberry-rewards-', dir='/tmp')
        self.addCleanup(temporary.cleanup)
        environment = patch.dict(os.environ, {'SCREEN_TIME_ROOT': temporary.name})
        environment.start(); self.addCleanup(environment.stop)
        self.now = datetime(2026, 9, 10, 12).timestamp()
        clock = patch('time.time', return_value=self.now)
        clock.start(); self.addCleanup(clock.stop)
        self.uid = os.getuid() or pwd.getpwnam('nobody').pw_uid
        self.user = pwd.getpwuid(self.uid).pw_name
        self.host = self.make_host()

    def make_host(self, modules=None):
        host = Daemon(paths.detect(), modules=modules, log=lambda _: None)
        host.clock.logical = self.now
        host.auth = ParentAuth(verifier=lambda user, password: password == 'correct')
        return host

    def send(self, command, parent=False, scope='pawberry', **values):
        return self.host.dispatch(0 if parent else self.uid,
            {'scope':scope, 'cmd':command, 'user':self.user, **values})

    def enable(self, minutes=2, cap=5):
        self.send('users.set', scope='time', parent=True, enabled=True)
        result = self.send('settings.set', password='correct', screen_time={
            'enabled':True, 'minutes_per_problem':minutes, 'daily_cap_minutes':cap})
        self.assertTrue(result['ok'], result)
        return self.host.services['time'].account_for(self.uid)

    def begin(self):
        return self.send('begin', problem={'operation':'multiply', 'a':7, 'b':8})['id']

    def complete(self, identifier=None):
        return self.send('complete', id=identifier or self.begin(), answer=56)

    def test_off_by_default_and_absent_modules_never_enroll_implicitly(self):
        self.assertFalse(self.send('status')['screen_time']['enabled'])
        self.assertEqual(self.complete()['reward_seconds'],0)
        refused = self.send('settings.set', password='correct', limits={'add':0}, screen_time={'enabled':True})
        self.assertEqual(refused['error'],'screen_time_not_managed')
        self.assertIsNone(self.send('status')['limits']['add'])
        self.assertEqual(self.send('status', scope='time')['error'],'not_managed')
        self.host = self.make_host(['pawberry'])
        self.assertFalse(self.send('status')['screen_time']['available'])
        self.assertEqual(self.complete()['reward_seconds'],0)

    def test_separate_pawberry_cap_shared_balance_and_restart(self):
        account = self.enable()
        before = account.day.remaining
        results = [self.complete() for _ in range(4)]
        self.assertEqual([r['reward_seconds'] for r in results],[120,120,60,0])
        self.assertEqual(account.day.remaining,before+300)
        self.assertEqual(account.day.earned,300)
        self.assertEqual(account.day.granted,0)
        self.assertTrue(any(e.get('meta',{}).get('source')=='pawberry' for e in account.day.ledger))
        self.host = self.make_host()
        status = self.send('status')['screen_time']
        self.assertEqual(status['earned_today_seconds'],300)
        self.assertEqual(status['remaining_today_seconds'],0)
        self.assertEqual(self.complete()['reward_seconds'],0)

    def test_older_time_package_does_not_break_ordinary_play(self):
        account = self.enable()
        with patch.object(account,'credit_activity',None):
            self.assertFalse(self.send('status')['screen_time']['available'])
            self.assertEqual(self.complete()['reward_seconds'],0)
            self.assertTrue(self.send('settings.set',password='correct',limits={'add':5},screen_time={'enabled':True})['ok'])
        self.assertEqual(self.complete()['reward_seconds'],120)

    def test_global_earning_cap_is_shared_with_other_math(self):
        account = self.enable(minutes=2, cap=30)
        account.profile['earn']['daily_cap_minutes']=3
        account.day.add('earn',150,{'q':'Other math'})
        self.assertEqual(self.complete()['reward_seconds'],30)
        self.assertEqual(account.day.earned,180)
        self.assertEqual(self.complete()['reward_seconds'],0)
        self.assertEqual(self.send('status')['screen_time']['earned_today_seconds'],30)

    def test_wrong_answers_replays_and_parallel_completions(self):
        account = self.enable(cap=30)
        identifier = self.begin()
        self.assertEqual(self.send('complete', id=identifier, answer=55)['error'],'incorrect_answer')
        self.assertEqual(account.day.earned,0)
        with ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda _: self.complete(identifier), range(6)))
        self.assertTrue(all(r['reward_seconds']==120 for r in results))
        self.assertEqual(sum(not r['already_completed'] for r in results),1)
        self.assertEqual(account.day.earned,120)
        for _ in range(250): account.day.record('reflection',meta={'text':'Test'})
        account.save()
        self.host = self.make_host()
        self.assertEqual(self.complete(identifier)['reward_seconds'],120)
        self.assertEqual(self.send('status',scope='time')['earned_seconds'],120)

    def test_parent_auth_validation_and_atomic_settings(self):
        account = self.enable()
        self.assertEqual(self.send('settings.set', limits={'add':0}, screen_time={'enabled':False}, password='bad')['error'],'bad_password')
        self.assertIsNone(self.send('status')['limits']['add'])
        for settings in ({'enabled':1}, {'minutes_per_problem':0}, {'minutes_per_problem':61}, {'daily_cap_minutes':1441}, {'daily_cap_minutes':True}, {'minutes_per_problem':1.5}, {'unknown':1}):
            self.assertFalse(self.send('settings.set', password='correct', limits={'add':0}, screen_time=settings)['ok'])
            self.assertIsNone(self.send('status')['limits']['add'])
        self.complete()
        self.assertTrue(self.send('settings.set', password='correct', user='root', limits={'add':5}, screen_time={'enabled':False})['ok'])
        self.assertEqual(self.complete()['reward_seconds'],0)
        self.assertEqual(account.day.earned,120)
        self.assertEqual(self.send('status')['limits']['add'],5)

    def test_school_bedtime_disabled_earning_and_paused_time(self):
        account = self.enable(cap=30)
        gates = [({'school_snapshot':lambda now: {'mode':'school'}},'school_mode_active'),
                 ({'blocking_period':lambda now: {'label':'Bedtime'}},'bedtime'),
                 ({'paused':True},'screen_time_paused')]
        for attrs, reason in gates:
            with patch.multiple(account,**attrs):
                self.assertEqual(self.send('status')['screen_time']['reason'],reason)
                self.assertEqual(self.complete()['reward_seconds'],0)
        account.profile['earn']['enabled']=False
        self.assertEqual(self.complete()['reward_seconds'],0)
        account.profile['earn']['enabled']=True
        account.profile['philosophy']='together'
        self.assertEqual(self.complete()['reward_seconds'],0)
        account.profile['philosophy']='limits'
        self.assertEqual(self.complete()['reward_seconds'],120)

    def test_settings_changed_during_problem_and_old_completions(self):
        account = self.enable()
        identifier = self.begin()
        self.send('settings.set', password='correct', screen_time={'enabled':False})
        self.assertEqual(self.complete(identifier)['reward_seconds'],0)
        self.send('settings.set', password='correct', screen_time={'enabled':True})
        self.assertEqual(self.complete(identifier)['reward_seconds'],0)
        self.assertEqual(account.day.earned,0)
        self.assertEqual(self.complete()['reward_seconds'],120)

    def test_credit_write_failure_recovers_without_a_phantom_balance(self):
        account = self.enable()
        identifier = self.begin()
        with patch.object(account.store,'save_day',side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.complete(identifier)
        self.assertEqual(account.day.earned,0)
        self.host = self.make_host()
        self.assertEqual(self.complete(identifier)['reward_seconds'],120)
        self.assertEqual(self.send('status',scope='time')['earned_seconds'],120)

    def test_lost_acknowledgement_does_not_credit_twice(self):
        account = self.enable()
        identifier = self.begin()
        service = self.host.services['pawberry']
        persist = service.persist
        def fail_receipt(uid,state):
            if (state.get('receipt') or {}).get('reward_seconds') == 120:
                raise OSError('failed acknowledgement')
            persist(uid,state)
        with patch.object(service,'persist',side_effect=fail_receipt):
            with self.assertRaises(OSError): self.complete(identifier)
        self.assertEqual(account.day.earned,120)
        self.host = self.make_host()
        self.assertEqual(self.complete(identifier)['reward_seconds'],120)
        self.assertEqual(self.send('status',scope='time')['earned_seconds'],120)

    def test_new_day_resets_caps_without_recrediting_yesterdays_problem(self):
        self.enable(minutes=2,cap=2)
        result = self.complete()
        self.host.clock.logical += 86400
        self.assertEqual(self.send('status')['screen_time']['earned_today_seconds'],0)
        self.assertEqual(self.complete(result['id'])['reward_seconds'],120)
        self.assertEqual(self.send('status',scope='time')['earned_seconds'],0)
        self.assertEqual(self.complete()['reward_seconds'],120)

    def test_unprivileged_protocol_has_no_credit_or_grant_command(self):
        account = self.enable()
        for command in ('credit_activity','reward','grant'):
            self.assertFalse(self.send(command, minutes=1000, reward_seconds=60000)['ok'])
        self.assertEqual(account.day.earned,0)

    def test_settings_client_keeps_password_on_stdin(self):
        with patch.object(proto,'request',return_value={'ok':True}) as request, patch('os.geteuid',return_value=self.uid), patch('sys.stdin',io.StringIO('correct\n')), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.main(['settings','--addition','5','--screen-time','on','--minutes-per-problem','2','--daily-reward-minutes','30','--password-stdin']),0)
        payload=request.call_args.args[1]
        self.assertEqual(payload['cmd'],'settings.set')
        self.assertEqual(payload['screen_time'],{'enabled':True,'minutes_per_problem':2,'daily_cap_minutes':30})
        self.assertEqual(payload['limits'],{'add':5})
        self.assertEqual(payload['password'],'correct')


if __name__ == '__main__': unittest.main()
