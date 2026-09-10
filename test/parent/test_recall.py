"""Grade boundaries and exact answer judging, shared by practice and earning."""
from fractions import Fraction
import random
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lib/parent'))
from omarchy_kids.screen_time import quiz, config


class RecallTest(unittest.TestCase):
    def test_all_grades_cover_their_facts_with_valid_exact_answers(self):
        self.assertEqual(config.LEVELS, ['grade' + str(n) for n in range(1, 8)])
        for level, kinds in quiz.GRADES.items():
            generator = quiz.Generator(random.Random(2718))
            seen = set()
            for _ in range(2500):
                q = generator.question(level, 0)
                seen.add(q.kind)
                self.assertNotIn('answer', q.public(180, 90))
                self.assertEqual(q.issued_at, 0)
                self.assertIsNotNone(quiz.parse_number(q.answer))
                terms = re.fullmatch(r'(-?\d+) ([+×÷-]) (-?\d+)', q.text)
                if terms:
                    a, op, b = terms.groups(); a, b = int(a), int(b)
                    if op == '+':
                        expected = a + b
                        self.assertLessEqual(expected, 10 if level == 'grade1' else 20)
                    elif op == '-':
                        expected = a - b
                        self.assertGreaterEqual(expected, 0)
                        self.assertLessEqual(a, 10 if level == 'grade1' else 20)
                    elif op == '×':
                        expected = a * b
                        if q.kind != 'place_value': self.assertLessEqual(max(abs(a), abs(b)), 10)
                        if level == 'grade3': self.assertIn(a, (0, 1, 2, 5, 10))
                    else:
                        self.assertNotEqual(b, 0)
                        expected = Fraction(a, b)
                        if q.kind != 'place_value':
                            self.assertLessEqual(abs(b), 10)
                            self.assertLessEqual(abs(expected), 10)
                        if level == 'grade3': self.assertIn(b, (1, 2, 5, 10))
                    self.assertEqual(quiz.parse_number(q.answer), expected, q.text)
                if level in ('grade1', 'grade2'):
                    self.assertNotIn('×', q.text); self.assertNotIn('÷', q.text)
            self.assertEqual(seen, {kind for kind, _ in kinds}, level)

    def test_number_bonds_put_the_missing_number_in_different_positions(self):
        generator = quiz.Generator(random.Random(42)); positions = set()
        for _ in range(500):
            text, answer = generator.make('bond10')
            left, total = text.split(' = ')
            first, operator, second = left.split()
            positions.add((operator, first == '?'))
            a, b = answer if first == '?' else int(first), answer if second == '?' else int(second)
            self.assertEqual(a + b if operator == '+' else a - b, int(total))
            self.assertIn(int(total) if operator == '+' else int(first), (5, 10))
        self.assertEqual(len(positions), 3)

    def test_exact_equivalents_and_signed_inputs(self):
        for a, b in [('0.5', '1/2'), ('50%', '1/2'), ('12.5%', '1/8'),
                     ('33 1/3%', '1/3'), ('66 2/3%', '2/3'), ('−8', '-8'),
                     ('-.125', '-1/8'), ('-0 1/2', '-.5'), ('0', '0.0'), ('YES', 'yes')]:
            self.assertEqual(quiz.parse_number(a), quiz.parse_number(b))
        self.assertNotEqual(quiz.parse_number('.333'), quiz.parse_number('1/3'))
        self.assertNotEqual(quiz.parse_number('33.33%'), quiz.parse_number('1/3'))
        for value in ('1/0', '0/0', '1e3', 'one', '1x2', '1,2', 'NaN', 'Infinity', '', '-', '9' * 100):
            with self.assertRaises((ValueError, ZeroDivisionError), msg=value): quiz.parse_number(value)

    def test_fractions_percentages_and_divisibility_are_correct(self):
        generator = quiz.Generator(random.Random(71))
        for kind in ('fraction_decimal', 'equivalent', 'extended_equivalent', 'percent_of', 'divisibility'):
            for _ in range(500):
                text, answer = generator.make(kind)
                if ' = ' in text:
                    self.assertEqual(quiz.parse_number(text.split(' = ')[0]), quiz.parse_number(answer))
                elif ' of ' in text:
                    a, b = text.split(' of ')
                    self.assertEqual(quiz.parse_number(a) * int(b), quiz.parse_number(answer))
                else:
                    a, b = map(int, re.findall(r'\d+', text))
                    self.assertEqual(answer, 'yes' if a % b == 0 else 'no')

    def test_grade_five_emphasizes_harder_tables_and_retains_simple_facts(self):
        generator = quiz.Generator(random.Random(11)); hard, tables, zeros = 0, 0, 0
        for _ in range(5000):
            q = generator.question('grade5', 0)
            if q.kind in ('hard_table', 'hard_div'):
                tables += 1
                a, _, b = q.text.split(); family = int(a) if q.kind == 'hard_table' else int(b)
                hard += family in (3, 4, 6, 7, 8, 9)
                zeros += quiz.parse_number(q.answer) == 0
        self.assertGreater(tables, 3000)
        self.assertGreater(hard / tables, .8)
        self.assertGreater(zeros, 0)

    def test_exact_earning_answer_is_consumed_once_and_invalid_input_keeps_question(self):
        engine = quiz.Quiz(config.sanitize_earn({'min_answer_seconds': 0}))
        q = quiz.Question('equivalent', '1/8 = ? (percent)', '12.5%', 1000)
        engine.pending = q
        self.assertEqual(engine.answer(q.id, '1/0', 1001)['error'], 'not_a_number')
        self.assertIs(engine.pending, q)
        self.assertTrue(engine.answer(q.id, '0.125', 1002)['correct'])
        self.assertEqual(engine.answer(q.id, '12.5%', 1003)['error'], 'no_such_question')
        for kind, answer in [('signed_table', -56), ('equivalent', '12.5%'), ('divisibility', 'yes'), ('place_value', 100000)]:
            q = quiz.Question(kind, 'example', answer, 0)
            choices = q.choices()
            self.assertEqual(len(choices), 2 if answer == 'yes' else 6)
            self.assertEqual(sum(quiz.parse_number(c) == quiz.parse_number(answer) for c in choices), 1)


if __name__ == '__main__': unittest.main()
