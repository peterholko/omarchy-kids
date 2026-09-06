"""Exercise Paw Post's actual Qt Quick view locally with PySide6 Essentials.

Usage: python test/paw-post/visual.py CAPTURE_DIRECTORY
No Quickshell, Linux installation, network access or ISO is started here.
"""
import json
import os
import sys
from pathlib import Path

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtCore import QEvent, QPointF, QTimer, QUrl, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication, QKeyEvent
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
view.setSource(QUrl.fromLocalFile(str(ROOT / 'shell/plugins/paw-post/TypingView.qml')))
assert view.status() != QQuickView.Error, view.errors()
view.resize(1080, 820); view.show(); QTest.qWait(250)
game = view.rootObject()
engine = view.engine()
engine.globalObject().setProperty('game', engine.newQObject(game))

def js(code):
    result = engine.evaluate(code)
    assert not result.isError(), result.toString()
    return result.toVariant()

def state():
    return js('JSON.parse(JSON.stringify(game.session))')

def find(name):
    pending = [game]
    while pending:
        item = pending.pop()
        if item.objectName() == name: return item
        pending.extend(item.childItems())
    raise AssertionError(name)

def click(name):
    item = find(name)
    point = item.mapToScene(QPointF(item.width() / 2, item.height() / 2)).toPoint()
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, point)
    QTest.qWait(30)

def key(code, modifiers=Qt.NoModifier):
    QTest.keyClick(view, code, modifiers)
    QTest.qWait(25)

def type_text(text):
    for char in text:
        code = int(Qt.Key(ord(char.upper() if char.isalpha() else char)))
        modifiers = Qt.ShiftModifier if char.isupper() else Qt.NoModifier
        # QtTest's offscreen keyClick gives lowercase event text for Shift+A.
        # Deliver actual key events with the text a keyboard would produce.
        QGuiApplication.sendEvent(view, QKeyEvent(QEvent.KeyPress, code, modifiers, char))
        QGuiApplication.sendEvent(view, QKeyEvent(QEvent.KeyRelease, code, modifiers, char))
        QTest.qWait(25)

def capture(name):
    QTest.qWait(140)
    assert view.grabWindow().save(str(output / (name + '.png')))

engine.globalObject().setProperty('artwork', engine.newQObject(find('menuArtwork')))
assert js('artwork.status === 1'), 'illustration did not load'
capture('menu')
click('lesson-home')
assert game.property('lesson') == 'home'
click('lesson-stories')
capture('story-menu')
click('lesson-words')
click('startButton')
assert state()['phase'] == 'play'
capture('play')
QTest.qWait(500)
assert state()['elapsed'] == 0, 'clock ran before the first key'
wrong = 'z' if state()['target'][0] != 'z' else 'x'
type_text(wrong)
assert state()['error']; assert state()['typed'] == wrong
assert game.property('nextKey') == 'Backspace'
capture('correction')
key(Qt.Key_Backspace)
assert state()['typed'] == '' and not state()['error']
app.clipboard().setText(state()['target'])
key(Qt.Key_V, Qt.ControlModifier)
assert state()['typed'] == '', 'paste completed typing practice'
for delivery in range(10):
    if delivery:
        QTest.qWait(1000)
    target = state()['target']
    assert state()['phase'] == 'play'
    type_text(target)
    assert state()['delivered'] == delivery + 1, state()
    if delivery == 0: capture('delivered')
assert state()['phase'] == 'results'
assert state()['mistakes'] == 1
assert state()['bestStreak'] == 9
capture('cozy-results')
click('againButton')
click('lesson-stories')
click('startButton')
assert state()['target'][0].isupper()
assert game.property('nextKey').startswith('Shift +')
text = state()['target']
type_text(text[:5])
capture('story-play')
type_text(text[5:])
assert state()['delivered'] == 1, state()
QTest.qWait(1000)

# Record actual frames for a short movement/pause review, in the capture directory.
frames = output / 'motion'
frames.mkdir(exist_ok=True)
frame_index = [0]
def record():
    view.grabWindow().save(str(frames / f'{frame_index[0]:04d}.png'))
    frame_index[0] += 1
recording = QTimer()
recording.setInterval(100)
recording.timeout.connect(record)
recording.start()
for char in state()['target'][:12]:
    type_text(char); QTest.qWait(90)
key(Qt.Key_Escape)
assert state()['paused']
snapshot = state()
QTest.qWait(700)
key(Qt.Key_A)
assert state() == snapshot
capture('paused')
click('resumeButton')
assert not state()['paused']
game.setProperty('windowActive', False)
assert state()['paused']
snapshot = state()
QTest.qWait(300)
assert state() == snapshot
game.setProperty('windowActive', True)
assert state()['paused'], 'returning focus resumed automatically'
recording.stop()
click('routeButton')
click('motionButton')
assert game.property('reducedMotion')
view.resize(810, 615); QTest.qWait(120)
capture('small-menu')
click('startButton')
capture('small-play')
key(Qt.Key_Escape); click('routeButton')
view.resize(1080, 820)
click('dashMode'); click('lesson-words'); click('startButton')
assert state()['mode'] == 'dash'
type_text(state()['target'][0])
QTest.qWait(250)
assert state()['elapsed'] > 0
js('var s = JSON.parse(JSON.stringify(game.session)); s.lastAt -= 90001; game.session = s;')
QTest.qWait(150)
assert state()['phase'] == 'results' and state()['elapsed'] == 90000
capture('dash-results')
assert not errors, '\n'.join(errors)
print('PASS: artwork, lesson/mode picker, real typing/correction, paste rejection, ten deliveries, punctuation, pause/focus, resize, reduced motion and dash completion')
