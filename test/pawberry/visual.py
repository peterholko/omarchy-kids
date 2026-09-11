"""Drive the actual portable Qt view; no Linux, Quickshell or ISO is started.

Usage: python test/pawberry/visual.py CAPTURE_DIRECTORY
Requires PySide6 Essentials. This checks the component, not installed Omarchy.
"""
import json
import os
import sys
import tempfile
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
# Match keyboard-focusable Linux controls when this runs on macOS.
app.styleHints().setTabFocusBehavior(Qt.TabFocusAllControls)
view = QQuickView(); view.setResizeMode(QQuickView.SizeRootObjectToView)
save_directory = tempfile.TemporaryDirectory(prefix='pawberry-collection-')
save_path = Path(save_directory.name) / 'profile with spaces #1' / 'collection.ini'
view.setInitialProperties({'collectionLocation': QUrl.fromLocalFile(str(save_path))})
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
def click(name, focused=False):
    item = find(name)
    if focused: item.forceActiveFocus(Qt.TabFocusReason)
    point = item.mapToScene(QPointF(item.width()/2, item.height()/2)).toPoint()
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, point); QTest.qWait(30)
def key(code): QTest.keyClick(view, code); QTest.qWait(10)
def tab_to(name):
    for _ in range(30):
        if view.activeFocusItem() == find(name): return
        key(Qt.Key_Tab)
    raise AssertionError('could not reach button with Tab: ' + name)
def type_number(value):
    key(Qt.Key_Delete)
    for char in str(value): key(Qt.Key(ord(char)))
def enter(value, submit_key=Qt.Key_Return):
    type_number(value)
    key(submit_key)
def capture(name):
    QTest.qWait(180); assert view.grabWindow().save(str(out / (name + '.png')))
def step():
    s = state()
    return s['problems'][s['problemIndex']]['steps'][s['stepIndex']]

room = find('guestRoom')
portrait = find('petPortrait', room)
door = find('mysteryDoor', room)
def hidden_guest():
    assert state()['phase'] == 'work'
    assert not room.property('welcomed') and not portrait.isVisible()
    assert door.isVisible() and door.opacity() == 1
    assert not room.property('revealing')
def welcomed_guest():
    assert room.property('welcomed') and portrait.isVisible()
    assert portrait.opacity() == 1 and not door.isVisible()
    assert abs(portrait.scale() - 1) < 0.001

engine.globalObject().setProperty('artwork', engine.newQObject(portrait))
assert js('artwork.status === 1'), 'pet artwork failed to load'
assert not find('petPortrait', find('previewRoom')).isVisible(), 'menu spoiled the surprise'
capture('menu')
click('operation-mixed', focused=True); click('digits-3', focused=True)
tab_to('startButton'); key(Qt.Key_Space)
s = state()
assert len(s['problems']) == 3
assert all(p['operation'] in ['add','subtract','multiply','divide'] for p in s['problems'])
assert all((10 <= p['a'] <= 99 and 2 <= p['b'] <= 9) if p['operation'] == 'divide' else (100 <= p['a'] <= 999 and 100 <= p['b'] <= 999) for p in s['problems'])
key(Qt.Key_Space); assert state() == s, 'hidden Start button restarted the visit'
# Fixed examples exercise the same view and session transitions as generated visits.
for name in ['WorkSteps.js', 'WorkSession.js']:
    js((ROOT / 'shell/plugins/pawberry' / name).read_text())
js('game.visitPets = ["peaches", "biscuit", "bluebell"]; game.session = create([build(300,156,"subtract"),build(203,104,"multiply"),build(67,58,"add")]); game.answerInput = "";')
hidden_guest(); capture('subtraction')
assert js('game.collection.completed') == 0
enter(144)
assert state()['stepIndex'] == 0 and state()['rooms'] == 0 and state()['mistakes'] == 1
hidden_guest()
capture('correction')
click('hintButton', focused=True); assert game.property('showHint'); capture('hint')
enter(step()['expected'], Qt.Key_Enter)
assert state()['stepIndex'] == 1, 'hint button consumed the answer'
hidden_guest()
type_number(step()['expected']); click('checkButton', focused=True)
assert state()['stepIndex'] == 2
for _ in range(2):
    enter(step()['expected'])
    hidden_guest()
assert state()['board']['regroup'][:3] == [10,9,2]
capture('borrowing-across-zero')
while step()['kind'] != 'final':
    enter(step()['expected'])
    hidden_guest()
assert state()['phase'] == 'work' and state()['rooms'] == 0
assert room.property('comforts') == 3, 'room should be prepared before the final answer'
capture('final-answer')
enter(145); hidden_guest()
assert js('game.collection.completed') == 0, 'wrong or intermediate answers awarded collectibles'
assert state()['mistakes'] == 2 and state()['rooms'] == 0
capture('wrong-final')
key(Qt.Key_Delete); key(Qt.Key_Return); hidden_guest()
type_number(144)
(out / 'motion').mkdir(exist_ok=True)
assert view.grabWindow().save(str(out / 'motion' / '0000.png'))
click('checkButton', focused=True)
assert state()['phase'] == 'complete' and state()['rooms'] == 1
scales, opacities = [], []
for frame in range(1, 25):
    scales.append(portrait.scale()); opacities.append(portrait.opacity())
    assert view.grabWindow().save(str(out / 'motion' / f'{frame:04d}.png'))
    QTest.qWait(50)
assert min(scales) < 0.98 and max(scales) > 1.01
assert min(opacities) < 1 and opacities[-1] == 1
welcomed_guest(); assert not room.property('revealing')
capture('cozy-room')
assert js('game.collection.completed') == 1
assert js('game.collection.pets') == ['peaches']
assert len(js('game.collection.accessories')) == 1
assert save_path.exists(), 'reward was not saved immediately'
completed = state()
for k in (Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter): key(k)
assert state() == completed, 'repeat answer keys skipped the pet reward'
assert js('game.collection.completed') == 1, 'repeat keys duplicated the reward'
click('wearRewardButton', focused=True)
assert js('game.collection.outfits.peaches === game.lastReward.accessoryId')
assert find('wornAccessory', portrait).isVisible()
capture('accessory-reward')
click('collectionButton', focused=True); assert game.property('collectionOpen')
assert find('collectionPortrait').property('accessoryId') == js('game.lastReward.accessoryId')
click('accessoriesTab', focused=True); capture('first-accessory')
locked_id = js('game.collection.accessories[0] === "berry-bow" ? "sky-bow" : "berry-bow"')
assert not find('wardrobe-' + locked_id).isEnabled()
outfits_before = js('JSON.stringify(game.collection.outfits)')
click('wardrobe-' + locked_id)
assert js('JSON.stringify(game.collection.outfits)') == outfits_before, 'a locked accessory could be equipped'
click('removeAccessoryButton', focused=True)
assert not js('game.collection.outfits.peaches')
click('closeCollectionButton', focused=True)
assert not game.property('collectionOpen')
click('wearRewardButton', focused=True)
click('nextButton', focused=True)
assert state()['problemIndex'] == 1 and state()['stepIndex'] == 0
hidden_guest(); assert room.property('comforts') == 0
old = state(); key(Qt.Key_Space); assert state() == old, 'hidden Next button consumed input'
game.setProperty('windowActive', False)
assert state()['paused']
old = state(); enter(99); assert state() == old
game.setProperty('windowActive', True); assert state()['paused']
capture('paused'); click('resumeButton', focused=True)
assert not state()['paused']
while step()['kind'] != 'partial-product':
    enter(step()['expected'], Qt.Key_Enter)
    hidden_guest()
capture('partial-product')
while step()['kind'] != 'add-column': enter(step()['expected'])
capture('three-partial-products')
view.resize(840,600); capture('compact-multiplication'); view.resize(1120,800)
click('motionButton', focused=True)
assert game.property('reducedMotion')
while state()['phase'] == 'work': enter(step()['expected'])
welcomed_guest(); assert not room.property('revealing'), 'reduced motion must still reveal the pet'
assert state()['rooms'] == 2
capture('quiet-welcome')
tab_to('nextButton'); key(Qt.Key_Space)
hidden_guest(); assert room.property('comforts') == 0
while step()['kind'] != 'final': enter(step()['expected'])
hidden_guest()
type_number(step()['expected']); tab_to('checkButton'); key(Qt.Key_Space)
assert state()['rooms'] == 3
welcomed_guest()
click('nextButton', focused=True); assert state()['phase'] == 'results'
assert state()['mistakes'] == 2
for i in range(3):
    earned_room = find('welcomedPet-' + str(i))
    assert earned_room.isVisible() and earned_room.property('welcomed')
    assert find('petPortrait', earned_room).isVisible()
    assert find('petPortrait', earned_room).opacity() == 1
    assert not find('mysteryDoor', earned_room).isVisible()
capture('results')
view.resize(840,600); capture('compact-results'); view.resize(1120,800)
click('againButton', focused=True); assert game.property('session') is None

# Starting another visit and interrupting celebrations must not reveal a later pet.
game.setProperty('reducedMotion', False)
click('startButton', focused=True)
js('game.session = create([build(12,23,"add"),build(40,18,"subtract"),build(12,30,"multiply")]);')
hidden_guest()
while state()['phase'] == 'work': enter(step()['expected'])
assert room.property('revealing')
click('nextButton', focused=True)
QTest.qWait(1100); hidden_guest()
assert room.property('comforts') == 0
while state()['phase'] == 'work': enter(step()['expected'])
assert room.property('revealing')
click('motionButton', focused=True)
welcomed_guest(); assert not room.property('revealing')
click('pauseButton', focused=True); assert state()['paused']
click('leaveButton', focused=True); assert game.property('session') is None
click('startButton', focused=True); enter(step()['expected'])
assert state()['stepIndex'] == 1, 'Leave/Start kept a hidden button focused'
hidden_guest()
js('game.reset()')
view.resize(840,600); capture('compact-menu')

# Collect every new guest through the real answer handler, then inspect the album.
view.resize(1120,800)
js((ROOT / 'shell/plugins/pawberry/PetCatalog.js').read_text())
for pet_id in js('petIds'):
    js('game.reset(); game.start(); game.visitPets = [' + json.dumps(pet_id) + ', "biscuit", "bluebell"]; game.session = create([build(12,23,"add")]);')
    js('while (game.session.phase === "work") { game.answerInput = String(activeStep(game.session).expected); game.check(); }')
    QTest.qWait(20)
    assert js('artwork.status === 1'), pet_id + ' portrait failed to load'
    assert room.property('petId') == pet_id
js('game.reset()')
assert len(js('game.collection.pets')) == 23
assert len(js('game.collection.accessories')) == 20
click('collectionButton', focused=True)
click('petsTab', focused=True)
capture('pet-album')
album = find('collectionGrid')
album.setProperty('contentY', 290); QTest.qWait(60); capture('more-pets')
album.setProperty('contentY', 435); QTest.qWait(60)
capture('last-pets')
click('album-bubbles', focused=True)
click('accessoriesTab', focused=True)
click('wardrobe-berry-bow', focused=True)
assert js('game.collection.outfits.bubbles') == 'berry-bow'
assert find('wornAccessory', find('collectionPortrait')).isVisible()
capture('wardrobe')
view.resize(840,600); capture('compact-collection'); view.resize(1120,800)
saved_collection = js('JSON.parse(JSON.stringify(game.collection))')
key(Qt.Key_Escape); assert not game.property('collectionOpen')
view.close(); view.deleteLater(); QTest.qWait(100)

# A fresh Qt engine reloads the on-disk collection, including the equipped bow.
view = QQuickView(); view.setResizeMode(QQuickView.SizeRootObjectToView)
view.setInitialProperties({'collectionLocation': QUrl.fromLocalFile(str(save_path))})
view.setSource(QUrl.fromLocalFile(str(ROOT / 'shell/plugins/pawberry/HotelView.qml')))
assert view.status() != QQuickView.Error, view.errors()
view.resize(1120,800); view.show(); QTest.qWait(150)
game = view.rootObject(); engine = view.engine()
engine.globalObject().setProperty('game', engine.newQObject(game))
assert js('JSON.parse(JSON.stringify(game.collection))') == saved_collection, 'reopening lost collectibles or outfits'
click('collectionButton', focused=True); capture('restored-collection')
assert not errors, '\n'.join(errors)
print('PASS: arithmetic, reward gates, all 23 pets, all 20 accessories, outfit selection/removal, immediate saves, fresh-engine persistence, keyboard focus, animations and compact layouts.')
view.close()
