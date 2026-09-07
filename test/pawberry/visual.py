"""Drive the actual portable Qt view; no Linux, Quickshell or ISO is started.

Usage: python test/pawberry/visual.py CAPTURE_DIRECTORY
Requires PySide6 Essentials. This checks the component, not installed Omarchy.
"""
import json
import os
import sys
from pathlib import Path

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtCore import QPointF, QUrl, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
errors = []
def message(kind, context, text):
    if 'file:' in text or 'Error' in text: errors.append(text)
    print(text, file=sys.stderr)
qInstallMessageHandler(message)
app = QGuiApplication(sys.argv)
view = QQuickView(); view.setResizeMode(QQuickView.SizeRootObjectToView)
view.setSource(QUrl.fromLocalFile(str(ROOT / 'shell/plugins/pawberry/HotelView.qml')))
assert view.status() != QQuickView.Error, view.errors()
view.resize(1120, 800); view.show(); QTest.qWait(300)
game = view.rootObject(); engine = view.engine()
engine.globalObject().setProperty('game', engine.newQObject(game))
def js(code):
    result = engine.evaluate(code)
    assert not result.isError(), result.toString()
    return result.toVariant()
def state(): return js('JSON.parse(JSON.stringify(game.session))')
def find(name, parent=None):
    pending = [parent or game]
    while pending:
        item = pending.pop()
        if item.objectName() == name: return item
        pending.extend(item.childItems())
    raise AssertionError(name)
def click(name):
    item = find(name)
    point = item.mapToScene(QPointF(item.width()/2, item.height()/2)).toPoint()
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, point); QTest.qWait(30)
def key(code): QTest.keyClick(view, code); QTest.qWait(10)
def enter(value):
    key(Qt.Key_Delete)
    for char in str(value): key(Qt.Key(ord(char)))
    key(Qt.Key_Return)
def capture(name):
    QTest.qWait(180); assert view.grabWindow().save(str(out / (name + '.png')))
def step():
    s = state()
    return s['problems'][s['problemIndex']]['steps'][s['stepIndex']]

engine.globalObject().setProperty('artwork', engine.newQObject(find('menuPets')))
assert js('artwork.status === 1'), 'pet artwork failed to load'
capture('menu')
click('operation-mixed'); click('digits-3'); click('startButton')
s = state()
assert [p['operation'] for p in s['problems']] == ['add','subtract','multiply']
assert all(100 <= p['a'] <= 999 and 100 <= p['b'] <= 999 for p in s['problems'])
# Fixed examples exercise the same view and session transitions as generated visits.
for name in ['WorkSteps.js', 'WorkSession.js']:
    js((ROOT / 'shell/plugins/pawberry' / name).read_text())
js('game.session = create([build(300,156,"subtract"),build(203,104,"multiply"),build(67,58,"add")]); game.answerInput = "";')
game.forceActiveFocus(); capture('subtraction')
enter(144)
assert state()['stepIndex'] == 0 and state()['rooms'] == 0 and state()['mistakes'] == 1
capture('correction')
click('hintButton'); assert game.property('showHint'); capture('hint')
enter(step()['expected'])
portrait = find('petPortrait', find('guestRoom'))
(out / 'motion').mkdir(exist_ok=True)
scales = []
for frame in range(10):
    scales.append(portrait.scale())
    assert view.grabWindow().save(str(out / 'motion' / f'{frame:04d}.png'))
    QTest.qWait(50)
assert max(scales) > 1.01 and abs(portrait.scale() - 1) < 0.001
for _ in range(3): enter(step()['expected'])
assert state()['board']['regroup'][:3] == [10,9,2]
capture('borrowing-across-zero')
while step()['kind'] != 'final': enter(step()['expected'])
assert state()['phase'] == 'work' and state()['rooms'] == 0
capture('final-answer')
enter(144)
assert state()['phase'] == 'complete' and state()['rooms'] == 1
capture('cozy-room')
click('nextButton')
assert state()['problemIndex'] == 1 and state()['stepIndex'] == 0
game.setProperty('windowActive', False)
assert state()['paused']
old = state(); enter(99); assert state() == old
game.setProperty('windowActive', True); assert state()['paused']
capture('paused'); click('resumeButton')
assert not state()['paused']
while step()['kind'] != 'partial-product': enter(step()['expected'])
capture('partial-product')
while step()['kind'] != 'add-column': enter(step()['expected'])
capture('three-partial-products')
view.resize(840,600); capture('compact-multiplication'); view.resize(1120,800)
game.setProperty('reducedMotion', True)
while state()['phase'] == 'work': enter(step()['expected'])
assert abs(find('petPortrait', find('guestRoom')).scale() - 1) < 0.001
assert state()['rooms'] == 2
click('nextButton')
while state()['phase'] == 'work': enter(step()['expected'])
assert state()['rooms'] == 3
click('nextButton'); assert state()['phase'] == 'results'
assert state()['mistakes'] == 1
capture('results')
click('againButton'); assert game.property('session') is None
assert not errors, '\n'.join(errors)
print('PASS: generated practice, required intermediates, borrowing, partial products, final gate, correction, hints, focus/pause, three visits, reduced motion and compact layout.')
view.close()
