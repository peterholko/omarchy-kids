"""Exercise the actual portable Qt Quick game locally; requires PySide6 Essentials.

This does not emulate or start the Quickshell/Wayland desktop. Screenshots are
written to the directory supplied as the sole argument, outside the checkout.
"""
import json
import os
import sys
from collections import deque
from pathlib import Path

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtCore import QPointF, QTimer, QUrl, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
errors = []
def message(kind, context, text):
    if 'file:' in text or 'Error' in text:
        errors.append(text)
    print(text, file=sys.stderr)
qInstallMessageHandler(message)
app = QGuiApplication(sys.argv)
view = QQuickView()
view.setResizeMode(QQuickView.SizeRootObjectToView)
view.setSource(QUrl.fromLocalFile(str(ROOT / 'shell/plugins/number-grove/GameView.qml')))
assert view.status() != QQuickView.Error, view.errors()
view.resize(1040, 760)
view.show()
QTest.qWait(250)
game = view.rootObject()
view.engine().globalObject().setProperty('game', view.engine().newQObject(game))

def js(code):
    result = view.engine().evaluate(code)
    assert not result.isError(), result.toString()
    return result.toVariant()

def state():
    return js('JSON.parse(JSON.stringify(game.session))')

def capture(name):
    QTest.qWait(180)
    assert view.grabWindow().save(str(output / (name + '.png')))

def click(name):
    pending = [game]
    item = None
    while pending:
        candidate = pending.pop()
        if candidate.objectName() == name:
            item = candidate
            break
        pending.extend(candidate.childItems())
    assert item is not None, name
    point = item.mapToScene(QPointF(item.width() / 2, item.height() / 2)).toPoint()
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, point)
    QTest.qWait(30)

def key(code):
    QTest.keyClick(view, code)
    QTest.qWait(15)

def walk_to(value):
    s = state()
    target = s['tiles'].index(value)
    queue = deque([(s['player'], [])])
    seen = {s['player']}
    directions = [(1, 0, Qt.Key_Right), (-1, 0, Qt.Key_Left), (0, 1, Qt.Key_Down), (0, -1, Qt.Key_Up)]
    while queue:
        cell, path = queue.popleft()
        if cell == target:
            for k in path: key(k)
            assert state()['player'] == target
            return
        x, y = cell % 7, cell // 7
        for dx, dy, k in directions:
            nx, ny = x + dx, y + dy
            nxt = ny * 7 + nx
            if 0 <= nx < 7 and 0 <= ny < 5 and nxt not in s['stones'] and nxt not in seen:
                seen.add(nxt); queue.append((nxt, path + [k]))
    raise AssertionError('seed unreachable')

capture('start')
click('grade1')
assert game.property('grade') == 1
capture('grade1')
click('grade6')
click('calmMode')
click('practiceButton')
assert state()['phase'] == 'play'
assert '×' in state()['question']['text'] or '÷' in state()['question']['text']
capture('play')
for round_no in range(10):
    if round_no:
        key(Qt.Key_Return)
    walk_to(state()['question']['answer'])
    if round_no == 0: capture('on-seed')
    key(Qt.Key_Space)
    assert state()['correct'] == round_no + 1
    assert state()['phase'] == ('results' if round_no == 9 else 'feedback')
    if round_no == 0: capture('correct')
capture('results')
key(Qt.Key_Return)
assert game.property('screen') == 'start'
key(Qt.Key_Return)
for miss in range(3):
    if miss: key(Qt.Key_Return)
    s = state()
    walk_to(next(n for n in s['question']['choices'] if n != s['question']['answer']))
    key(Qt.Key_Space)
    assert state()['hearts'] == 2 - miss
    if miss == 0: capture('wrong')
assert state()['phase'] == 'results'
key(Qt.Key_Return)
click('calmMode')
key(Qt.Key_Return)
# Keep a short real-render recording of movement and pausing for visual review.
frames = output / 'motion'
frames.mkdir(exist_ok=True)
frame_number = [0]
def record_frame():
    view.grabWindow().save(str(frames / f'{frame_number[0]:04d}.png'))
    frame_number[0] += 1
recording = QTimer()
recording.setInterval(100)
recording.timeout.connect(record_frame)
recording.start()
old_bugs = state()['bugs']
QTest.qWait(1750)
assert old_bugs != state()['bugs'], 'adventure timer did not move bugs'
key(Qt.Key_P)
assert game.property('paused')
snapshot = state()
QTest.qWait(1750)
assert state() == snapshot, 'paused game moved'
capture('paused')
key(Qt.Key_P)
game.setProperty('windowActive', False)
assert game.property('paused')
game.setProperty('windowActive', True)
assert game.property('paused'), 'focus return must not resume automatically'
recording.stop()
js('game.reset()')
view.resize(780, 570)
QTest.qWait(150)
capture('small-start')
view.resize(1040, 760)

# The same UI accepts delayed server replies and ignores abandoned sessions.
game.setProperty('calm', True)
game.setProperty('rewardAvailable', True)
game.setProperty('rewardGrade', 6)
game.setProperty('rewardQuestions', 2)
requests = []
game.rewardRequest.connect(lambda token, kind, qid, value: requests.append((token, kind, qid, value)))
click('earnButton')
assert state()['phase'] == 'waiting'
token = requests[-1][0]
reply = {'ok': True, 'level': 'grade6', 'questions_per_set': 2,
    'question': {'id': 'test-question', 'text': '7 × 8', 'choices': [42, 48, 54, 56, 63, 72]}}
js(f'game.acceptReward({token + 99}, {json.dumps(reply)})')
assert state()['phase'] == 'waiting'
js(f'game.acceptReward({token}, {json.dumps(reply)})')
walk_to(56)
key(Qt.Key_Space)
assert requests[-1][1:] == ('answer', 'test-question', 56)
assert state()['phase'] == 'checking'
snapshot = state()
QTest.qWait(1800)
assert state() == snapshot
capture('checking')
token = requests[-1][0]
js(f'game.acceptReward({token}, {{ok: true, correct: true, answer: 56, reward_seconds: 30}})')
assert state()['earned'] == 30
capture('reward')
key(Qt.Key_Return)
abandoned = requests[-1][0]
js('game.reset(); game.start("practice")')
snapshot = state()
js(f'game.acceptReward({abandoned}, {json.dumps(reply)})')
assert state() == snapshot
js('game.reset(); game.start("earn")')
token = requests[-1][0]
js(f'game.acceptReward({token}, {{ok: false, error: "daily_cap_reached"}})')
assert state()['phase'] == 'error'
capture('cap')
assert not errors, '\n'.join(errors)
print('PASS: real Qt Quick menu, grades, 10 correct facts, 3 misses, movement, pause/focus, resize, delayed rewards, stale replies and cap feedback')
