"""Exercise the real Qt game against the actual parent service in a temp directory."""
import json
import os
import pwd
import sys
import tempfile
from datetime import datetime
from pathlib import Path

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtCore import QObject, Property, Signal, Slot, QTimer, QUrl, QPointF, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'lib/parent'))
from omarchy_kids.core import paths
from omarchy_kids.core.daemon import Daemon

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
temporary = tempfile.TemporaryDirectory(prefix='pawberry-qt-policy-')
os.environ['SCREEN_TIME_ROOT'] = temporary.name
uid = os.getuid() or pwd.getpwnam('nobody').pw_uid
user = pwd.getpwuid(uid).pw_name
host = Daemon(paths.detect(), modules=['pawberry'], log=lambda _: None)
host.clock.logical = datetime(2026, 9, 10, 12).timestamp()
def send(command, **kw): return host.dispatch(uid, {'scope':'pawberry','cmd':command,**kw})
def limits(add, subtract):
    result = host.dispatch(0, {'scope':'pawberry','cmd':'limits.set','user':user,'limits':{'add':add,'subtract':subtract}})
    assert result['ok'], result
limits(1, 0)

class Bridge(QObject):
    reply = Signal(int, 'QVariant')
    changed = Signal()
    def __init__(self):
        super().__init__(); self.data = send('status'); self.online = True; self.serial = 0
    @Property(bool, notify=changed)
    def ready(self): return self.online
    @Property(bool, constant=True)
    def managed(self): return True
    @Property('QVariant', notify=changed)
    def status(self): return self.data
    @Slot()
    def cancel(self): self.serial += 1
    @Slot()
    def refresh(self):
        self.data = send('status'); self.changed.emit()
    @Slot(int, 'QVariant')
    def request(self, token, payload):
        # Match PracticeBridge's JSON wire format (Qt variants may expose JS integers as floats).
        if hasattr(payload, 'toVariant'): payload = json.loads(engine.evaluate('JSON.stringify').call([payload]).toString())
        serial = self.serial
        def finish():
            if serial != self.serial: return
            result = send(**dict(command=payload['cmd'], **{k:v for k,v in payload.items() if k != 'cmd'})) if self.online else {'ok':False,'error':'unavailable'}
            if 'remaining' in result: self.data = result; self.changed.emit()
            self.reply.emit(token, result)
        QTimer.singleShot(20, finish)

errors=[]
def message(kind, context, text):
    if 'file:' in text or 'Error' in text: errors.append(text)
qInstallMessageHandler(message)
app = QGuiApplication(sys.argv); bridge = Bridge()
view = QQuickView(); view.setResizeMode(QQuickView.SizeRootObjectToView)
view.setInitialProperties({'policy':bridge, 'collectionLocation':QUrl.fromLocalFile(str(Path(temporary.name)/'collection.ini'))})
view.setSource(QUrl.fromLocalFile(str(ROOT/'shell/plugins/pawberry/HotelView.qml')))
assert view.status() != QQuickView.Error, view.errors()
view.resize(1120,800); view.show(); QTest.qWait(100)
game = view.rootObject(); engine = view.engine(); engine.globalObject().setProperty('game',engine.newQObject(game))
def js(code):
    result=engine.evaluate(code); assert not result.isError(), result.toString(); return result.toVariant()
def state(): return js('JSON.parse(JSON.stringify(game.session))')
def step(): return js('JSON.parse(JSON.stringify(game.step))')
def find(name):
    pending=[game]
    while pending:
        item=pending.pop()
        if item.objectName()==name: return item
        pending.extend(item.childItems())
    raise AssertionError(name)
def click(name):
    item=find(name); point=item.mapToScene(QPointF(item.width()/2,item.height()/2)).toPoint()
    QTest.mouseClick(view,Qt.LeftButton,Qt.NoModifier,point);QTest.qWait(70)
def capture(name):
    QTest.qWait(100); assert view.grabWindow().save(str(out/(name+'.png')))
def check(value, wait=True):
    js('game.answerInput='+json.dumps(str(value))+';game.check()')
    if wait: QTest.qWait(35)
def complete():
    while state()['phase']=='work': check(step()['expected'])

assert not find('operation-subtract').isEnabled()
click('startButton'); assert state()['phase']=='work'
check(step()['expected']+1)
assert send('status')['completed']['add']==0
while step()['kind']!='final': check(step()['expected'])
assert send('status')['completed']['add']==0
check(step()['expected'],wait=False)
assert game.property('checking'); assert not find('checkButton').isEnabled()
js('game.check();game.check()'); QTest.qWait(70)
assert send('status')['completed']['add']==1 and js('game.collection.completed')==1
click('nextButton')
assert state()['problemIndex']==1 and state()['problems'][1]['operation'] in ['multiply','divide'], 'pre-generated additions bypassed the cap'
js('game.reset()'); QTest.qWait(60)
assert not find('operation-add').isEnabled() and not find('operation-subtract').isEnabled()
capture('daily-limits')
# Choosing another difficulty or restarting a visit cannot revive a spent operation.
click('digits-3'); click('operation-add'); click('startButton'); assert state() is None
click('operation-multiply'); click('digits-1'); capture('one-digit-menu')
click('startButton'); assert 1<=state()['problems'][0]['a']<=9 and 1<=state()['problems'][0]['b']<=9
capture('one-digit-multiplication')
complete(); assert send('status')['completed']['multiply']==1
js('game.reset()'); QTest.qWait(40); click('operation-divide'); capture('division-menu')
click('startButton'); capture('division-working')
assert step()['kind']=='divide-groups'
check(step()['expected']); assert step()['kind']=='divide-product'
check(step()['expected']); assert step()['kind']=='divide-remainder'
capture('division-check')
check(step()['expected']); assert step()['kind']=='final'
# A failed service request cannot award a pet or silently enable standalone play.
bridge.online=False; bridge.changed.emit(); before=js('game.collection.completed')
check(step()['expected']); assert state()['phase']=='work' and js('game.collection.completed')==before
bridge.online=True; bridge.changed.emit(); check(step()['expected'])
assert state()['phase']=='complete' and send('status')['completed']['divide']==1
js('game.reset()'); QTest.qWait(40)
bridge.online=False; bridge.changed.emit(); QTest.qWait(10)
assert not find('startButton').isEnabled()
bridge.online=True; bridge.changed.emit()
# The next day re-enables addition, while the explicit zero subtraction cap remains.
host.clock.logical=datetime(2026,9,11,0,1).timestamp(); bridge.refresh(); QTest.qWait(20)
assert find('operation-add').isEnabled() and not find('operation-subtract').isEnabled()
assert send('status')['remaining']['add']==1
view.resize(840,600); capture('compact-division-menu')
assert not errors, '\n'.join(errors)
print('PASS: real service + Qt quota gates, restart/difficulty bypass, next guest, easy modes, asynchronous reward checking, service failure, daily reset, and compact UI.')
view.close()
