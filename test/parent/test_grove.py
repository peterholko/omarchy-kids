import contextlib
import io
import json
import os
import pwd
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lib/parent'))
from omarchy_kids.core import paths, proto
from omarchy_kids.core.daemon import Daemon
from omarchy_kids.core.storage import write_json
from omarchy_kids.number_grove import rewards


class GroveRewardsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        env = patch.dict(os.environ, {'SCREEN_TIME_ROOT': self.tmp.name, 'OMARCHY_PATH': str(ROOT)})
        env.start(); self.addCleanup(env.stop)
        self.uid = os.getuid() or pwd.getpwnam('nobody').pw_uid
        self.user = pwd.getpwuid(self.uid).pw_name
        self.layout = paths.detect()
        write_json(self.layout.config_path, {'version': 3, 'active_profile': 'default',
            'profiles': {'default': {'earn': {'level': 'grade6', 'min_answer_seconds': 2,
                'questions_per_set': 10, 'set_minutes': 10, 'daily_cap_minutes': 1}}},
            'users': {self.user: {'profile': 'default'}}})
        self.host = Daemon(self.layout, modules=['time'], log=lambda _: None)
        self.account = self.host.services['time'].account_for(self.uid)

    def send(self, command, **kw):
        return self.host.dispatch(self.uid, {'scope': 'time', 'cmd': command, **kw})

    def answer(self, question, value=None):
        pending = self.account.quiz.pending
        if pending:
            pending.issued_at -= 3
        return self.send('quiz.answer', id=question['id'], answer=pending.answer if value is None else value)

    def test_server_supplies_unmarked_choices_and_parent_grade(self):
        positions = set()
        for _ in range(80):
            reply = self.send('quiz.next', choices=6, level='grade1', user='root', reward_seconds=999999)
            self.assertEqual(reply['level'], 'grade6')
            question = reply['question']
            self.assertTrue('×' in question['text'] or '÷' in question['text'])
            self.assertEqual(set(question), {'id', 'text', 'kind', 'reward_seconds', 'timeout_seconds', 'choices'})
            self.assertEqual(len(set(question['choices'])), 6)
            self.assertIn(self.account.quiz.pending.answer, question['choices'])
            positions.add(question['choices'].index(self.account.quiz.pending.answer))
        self.assertGreater(len(positions), 1)
        self.assertNotIn('choices', self.send('quiz.next')['question'])
        for value in [-1, 1, 7, 50000, True, '6', None]:
            self.assertEqual(self.send('quiz.next', choices=value)['error'], 'invalid_choices')

    def test_delay_replay_and_daily_cap_remain_authoritative(self):
        question = self.send('quiz.next', choices=6)['question']
        value = self.account.quiz.pending.answer
        self.assertEqual(self.send('quiz.answer', id=question['id'], answer=value)['error'], 'too_fast')
        result = self.answer(question, value)
        self.assertTrue(result['correct'])
        self.assertEqual(result['reward_seconds'], 60)
        self.assertEqual(self.send('quiz.answer', id=question['id'], answer=value)['error'], 'no_such_question')
        self.assertEqual(self.send('quiz.next', choices=6)['error'], 'daily_cap_reached')
        self.assertEqual(self.account.day.earned, 60)

    def test_wrong_and_expired_questions_never_reward(self):
        question = self.send('quiz.next', choices=6)['question']
        value = next(n for n in question['choices'] if n != self.account.quiz.pending.answer)
        expected = self.account.quiz.pending.answer
        reply = self.answer(question, value)
        self.assertFalse(reply['correct'])
        self.assertEqual(reply['reward_seconds'], 0)
        self.assertEqual(reply['answer'], expected)
        question = self.send('quiz.next', choices=6)['question']
        self.account.quiz.pending.issued_at -= 4000
        self.assertEqual(self.answer(question)['error'], 'expired')
        self.assertEqual(self.account.day.earned, 0)

    def test_replaced_question_and_parent_disabling_cannot_credit(self):
        question = self.send('quiz.next', choices=6)['question']
        value = self.account.quiz.pending.answer
        self.send('quiz.next')  # Math Time may have opened in the meantime.
        self.assertEqual(self.send('quiz.answer', id=question['id'], answer=value)['error'], 'no_such_question')
        question = self.send('quiz.next', choices=6)['question']
        self.account.profile['earn']['enabled'] = False
        self.assertEqual(self.answer(question)['error'], 'earning_disabled')
        self.assertEqual(self.account.day.earned, 0)
        self.assertIsNone(self.account.quiz.pending)

    def test_missing_module_and_transport_failure_are_explicit(self):
        host = Daemon(self.layout, modules=[], log=lambda _: None)
        self.assertEqual(host.dispatch(self.uid, {'scope': 'time', 'cmd': 'quiz.next', 'choices': 6})['error'], 'module_not_installed')
        with patch.object(sys, 'argv', ['grove-client', 'next']), patch.object(proto, 'request', side_effect=OSError), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(rewards.main(), 1)
        self.assertEqual(json.loads(output.getvalue()), {'ok': False, 'error': 'unavailable'})

    def test_adapter_only_sends_quiz_requests(self):
        for args, expected in [(['next'], {'scope': 'time', 'cmd': 'quiz.next', 'choices': 6}),
                (['answer', 'nonce', '56'], {'scope': 'time', 'cmd': 'quiz.answer', 'id': 'nonce', 'answer': 56})]:
            with patch.object(sys, 'argv', ['grove-client', *args]), patch.object(proto, 'request', return_value={'ok': True}) as request, contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(rewards.main(), 0)
                self.assertEqual(request.call_args.args[1], expected)
                self.assertEqual(request.call_args.kwargs['timeout'], 5)
