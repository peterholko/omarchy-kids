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
from omarchy_kids.core.auth import ParentAuth

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
temporary = tempfile.TemporaryDirectory(prefix='pawberry-qt-policy-')
os.environ['SCREEN_TIME_ROOT'] = temporary.name
uid = os.getuid() or pwd.getpwnam('nobody').pw_uid
user = pwd.getpwuid(uid).pw_name
host = Daemon(paths.detect(), modules=['pawberry', 'time'], log=lambda _: None)
host.auth = ParentAuth(verifier=lambda user, password: password == 'correct password')
host.clock.logical = datetime(2026, 9, 10, 12).timestamp()
def send(command, **kw): return host.dispatch(uid, {'scope':'pawberry','cmd':command,**kw})
def limits(add, subtract, multiply):
    result = host.dispatch(0, {'scope':'pawberry','cmd':'limits.set','user':user,'limits':{'add':add,'subtract':subtract,'multiply':multiply}})
    assert result['ok'], result
limits(1, 0, 1)

class Bridge(QObject):
    reply = Signal(int, 'QVariant')
    changed = Signal()
    def __init__(self):
        super().__init__(); self.data = send('status'); self.online = True; self.serial = 0; self.controlled = True; self.requests = 0; self.delay = 20
    @Property(bool, notify=changed)
    def ready(self): return self.online
    @Property(bool, notify=changed)
    def managed(self): return self.controlled
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
        self.requests += 1
        def finish():
            if serial != self.serial: return
            result = send(**dict(command=payload['cmd'], **{k:v for k,v in payload.items() if k != 'cmd'})) if self.online else {'ok':False,'error':'unavailable'}
            if 'remaining' in result: self.data = result; self.changed.emit()
            self.reply.emit(token, result)
        QTimer.singleShot(self.delay, finish)
    @Slot(int, 'QVariant', str, 'QVariant')
    def saveLimits(self, token, limits, password, rewards):
        if hasattr(limits, 'toVariant'): limits = json.loads(engine.evaluate('JSON.stringify').call([limits]).toString())
        if hasattr(rewards, 'toVariant'): rewards = json.loads(engine.evaluate('JSON.stringify').call([rewards]).toString())
        self.last_limits = limits
        self.request(token, {'cmd':'settings.set' if rewards else 'limits.set', 'limits':limits,
            'screen_time':rewards or {}, 'password':password})

errors=[]
def message(kind, context, text):
    if 'file:' in text or 'Error' in text: errors.append(text)
qInstallMessageHandler(message)
app = QGuiApplication(sys.argv); app.styleHints().setTabFocusBehavior(Qt.TabFocusAllControls); bridge = Bridge()
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
def type_text(value):
    for char in value:
        QTest.keyClick(view, Qt.Key(ord(char.upper())), Qt.ShiftModifier if char.isupper() else Qt.NoModifier)
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
click('nextButton')
assert state()['problems'][1]['operation']=='divide', 'the next pet bypassed the multiplication cap'
js('game.reset()'); QTest.qWait(40)
assert not find('operation-multiply').isEnabled()
for digits in (1,2,3):
    click('digits-'+str(digits)); assert not find('operation-multiply').isEnabled()
click('operation-mixed'); click('startButton')
assert all(problem['operation']=='divide' for problem in state()['problems']), 'Mixed bypassed the multiplication cap'
js('game.reset()'); QTest.qWait(40)
capture('three-exhausted-limits')
view.resize(840,600); capture('compact-three-exhausted-limits'); view.resize(1120,800)
click('operation-divide'); capture('division-menu')
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
assert find('operation-multiply').isEnabled()
assert send('status')['remaining']['add']==1
view.resize(840,600); capture('compact-division-menu')
# The parent settings are part of the game, using the same persistent service.
issued=send('begin',problem={'operation':'add','a':12,'b':34})
assert send('complete',id=issued['id'],answer=46)['ok']
issued=send('begin',problem={'operation':'multiply','a':7,'b':8})
assert send('complete',id=issued['id'],answer=56)['ok']
view.resize(1120,800)
click('parentSettingsButton'); assert game.property('parentSettingsOpen')
assert not find('startButton').isVisible()
assert find('add-limit-count').property('text')=='1'
assert find('subtractionLimits').property('choice')=='off'
assert find('multiply-limit-count').property('text')=='1'
assert not find('saveParentSettingsButton').isEnabled()
capture('parent-settings')
click('add-limit-daily'); click('subtract-limit-daily'); click('multiply-limit-daily')
find('add-limit-count').setProperty('text','5')
find('subtract-limit-count').setProperty('text','7')
find('multiply-limit-count').setProperty('text','3')
# Polling while the parent is editing must not replace an unsaved draft.
bridge.refresh(); QTest.qWait(30)
assert find('add-limit-count').property('text')=='5'
assert find('multiply-limit-count').property('text')=='3'
find('parentPasswordInput').forceActiveFocus()
type_text('wrong password')
engine.globalObject().setProperty('passwordInput',engine.newQObject(find('parentPasswordInput')))
assert js('passwordInput.echoMode === 2')
assert 'wrong password' not in find('parentPasswordInput').property('displayText')
bridge.delay=450
click('saveParentSettingsButton')
assert game.property('parentSaving')
assert find('parentPasswordInput').property('text')==''
assert find('parentPasswordInput').property('readOnly')
assert find('parentPasswordInput').property('placeholderText')=='Checking password…'
assert not find('saveParentSettingsButton').isEnabled()
assert not find('closeParentSettingsButton').isEnabled()
requests=bridge.requests
QTest.keyClick(view,Qt.Key_Return); assert bridge.requests==requests
capture('checking-parent-password')
QTest.qWait(450)
assert not game.property('parentSaving')
assert send('status')['limits']=={'add':1,'subtract':0,'multiply':1}
assert "wasn't accepted" in find('parentSettingsFeedback').property('text'), find('parentSettingsFeedback').property('text')
assert find('add-limit-count').property('text')=='5'
capture('incorrect-parent-password')
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
QTest.keyClick(view,Qt.Key_Return); QTest.qWait(500)
assert send('status')['limits']=={'add':5,'subtract':7,'multiply':3}
assert send('status')['completed']['add']==1 and send('status')['remaining']['add']==4
assert send('status')['completed']['multiply']==1 and send('status')['remaining']['multiply']==2
assert not find('saveParentSettingsButton').isEnabled()
assert find('parentPasswordInput').property('text')==''
assert 'saved' in find('parentSettingsFeedback').property('text')
assert not find('parentSettings').property('dirty')
capture('saved-parent-settings')
view.resize(840,600); capture('compact-saved-parent-settings'); view.resize(1120,800)
# Server lockout feedback disables retries until its countdown expires.
click('add-limit-increase')
host.auth.failures[uid] = (5, host.auth.monotonic() + 1.5)
bridge.delay=20
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
click('saveParentSettingsButton')
assert find('parentSettings').property('retrySeconds') > 0
assert not find('saveParentSettingsButton').isEnabled()
assert 'Too many' in find('parentSettingsFeedback').property('text')
capture('parent-password-lockout')
QTest.qWait(2200)
assert find('parentSettings').property('retrySeconds')==0
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
click('saveParentSettingsButton')
assert send('status')['limits']['add']==6
# Unlimited and Unavailable have distinct meanings and round-trip on reopening.
click('add-limit-unlimited'); click('subtract-limit-off'); click('multiply-limit-off')
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
click('saveParentSettingsButton'); QTest.qWait(500)
assert send('status')['limits']=={'add':None,'subtract':0,'multiply':0}
click('closeParentSettingsButton'); click('parentSettingsButton')
assert find('additionLimits').property('choice')=='unlimited'
assert find('subtractionLimits').property('choice')=='off'
assert find('multiplicationLimits').property('choice')=='off'
click('multiply-limit-unlimited')
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
click('saveParentSettingsButton')
assert send('status')['limits']['multiply'] is None
assert send('status')['completed']['multiply']==1
click('add-limit-daily')
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
for invalid in ('', '0', '10001', '-1', '1.5', '1,000'):
    find('add-limit-count').setProperty('text',invalid)
    assert not find('saveParentSettingsButton').isEnabled(), f'invalid daily limit was accepted: {invalid!r}'
find('add-limit-count').setProperty('text','5'); click('multiply-limit-daily')
assert find('multiplicationLimits').property('choice')=='daily'
for invalid in ('', '0', '10001', '-1', '1.5', '1,000'):
    find('multiply-limit-count').setProperty('text',invalid)
    assert not find('saveParentSettingsButton').isEnabled(), f'invalid multiplication limit was accepted: {invalid!r}, valid={find("multiplicationLimits").property("valid")}, supported={find("parentSettings").property("multiplicationSupported")}'
# Closing discards edits and credentials, without touching saved limits.
click('closeParentSettingsButton'); click('parentSettingsButton')
assert find('additionLimits').property('choice')=='unlimited'
assert find('multiplicationLimits').property('choice')=='unlimited'
assert find('parentPasswordInput').property('text')==''
view.resize(840,600); capture('compact-parent-settings'); view.resize(1120,800)
click('closeParentSettingsButton')
# Parent controls pause a visit; password keystrokes cannot answer or skip work.
bridge.delay=20
click('operation-multiply'); click('digits-1'); click('startButton')
before=state(); click('parentSettingsButton'); assert state()['paused']
find('parentPasswordInput').forceActiveFocus(); type_text('123456')
QTest.keyClick(view,Qt.Key_Return)
assert state()['stepIndex']==before['stepIndex'] and game.property('answerInput')==''
QTest.keyClick(view,Qt.Key_Escape); QTest.qWait(30)
assert not game.property('parentSettingsOpen') and not state()['paused']
assert find('parentPasswordInput').property('text')==''
click('pauseButton'); click('pausedParentSettingsButton')
assert game.property('parentSettingsOpen')
click('closeParentSettingsButton'); assert state()['paused']
click('resumeButton'); js('game.reset()')
# The same parent screen optionally links completed problems to the real time balance.
bridge.refresh(); click('parentSettingsButton'); click('screenTimeSettingsTab')
assert not find('screenTimeOnButton').isEnabled()
assert 'Enable School' in find('screenTimeSettingsNote').property('text')
capture('screen-time-not-enrolled')
enrolled = host.dispatch(0, {'scope':'time','cmd':'users.set','user':user,'enabled':True})
assert enrolled['ok']
bridge.refresh(); QTest.qWait(30)
assert find('screenTimeOnButton').isEnabled()
click('screenTimeOnButton')
find('screenTimeMinutesInput').setProperty('text','2')
find('screenTimeCapInput').setProperty('text','5')
find('parentPasswordInput').forceActiveFocus(); type_text('wrong password')
click('saveParentSettingsButton')
assert not send('status')['screen_time']['enabled']
assert find('screenTimeSettings').property('rewardEnabled')
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
click('saveParentSettingsButton')
assert send('status')['screen_time']['enabled']
assert send('status')['screen_time']['minutes_per_problem']==2
assert send('status')['screen_time']['daily_cap_minutes']==5
assert 'saved' in find('parentSettingsFeedback').property('text')
capture('screen-time-parent-settings')
view.resize(840,600); capture('compact-screen-time-settings'); view.resize(1120,800)
# Invalid reward inputs cannot change either tab's settings.
click('screenTimeOffButton'); click('screenTimeOnButton')
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
for name, bad in [('screenTimeMinutesInput','0'),('screenTimeMinutesInput','61'),('screenTimeMinutesInput','1.5'),('screenTimeCapInput','1441')]:
    find('screenTimeMinutesInput').setProperty('text','2'); find('screenTimeCapInput').setProperty('text','5')
    find(name).setProperty('text',bad)
    assert not find('saveParentSettingsButton').isEnabled()
click('closeParentSettingsButton')
account = host.services['time'].account_for(uid)
before = account.day.remaining
click('operation-multiply'); click('digits-1'); click('startButton'); complete()
assert account.day.remaining == before + 120
assert game.property('timeRewardSeconds')==120
assert '2 min' in find('stepFeedback').property('text')
capture('screen-time-earned')
click('parentSettingsButton'); click('screenTimeSettingsTab')
assert '2.0 min earned' in find('screenTimeTotals').property('text')
click('screenTimeOffButton')
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
click('saveParentSettingsButton')
assert not send('status')['screen_time']['enabled']
assert account.day.earned == 120
click('closeParentSettingsButton'); js('game.reset()')
# An older backend still supports editing the original daily practice limits.
bridge.data = {key:value for key,value in send('status').items() if key != 'screen_time'}
bridge.changed.emit(); click('parentSettingsButton')
bridge.data.pop('screen_time',None); bridge.changed.emit(); QTest.qWait(20)
bridge.data['limits'].pop('multiply',None); bridge.changed.emit(); QTest.qWait(20)
assert not find('multiplicationLimits').isEnabled()
assert 'Update parent controls' in find('multiplicationLimits').property('unavailableNote')
capture('multiplication-service-upgrade')
click('screenTimeSettingsTab')
assert not find('screenTimeOnButton').isEnabled()
assert 'Update the parent controls service' in find('screenTimeSettingsNote').property('text')
capture('screen-time-service-upgrade')
click('practiceSettingsTab'); click('subtract-limit-daily')
find('parentPasswordInput').forceActiveFocus(); type_text('correct password')
click('saveParentSettingsButton')
assert 'multiply' not in bridge.last_limits, 'the new UI sent an unsupported limit to an older service'
assert send('status')['limits']['subtract']==5
click('closeParentSettingsButton')
# Standalone play without a configured backend gets a setup explanation, not a fake save.
bridge.controlled=False; bridge.changed.emit(); click('parentSettingsButton')
assert find('parentSetupGuideButton').isVisible()
assert not find('additionLimits').isEnabled()
capture('parent-controls-setup')
bridge.controlled=True; bridge.online=False; bridge.changed.emit(); QTest.qWait(20)
assert not find('parentSetupGuideButton').isVisible()
assert not find('additionLimits').isEnabled()
capture('parent-controls-offline')
assert not errors, '\n'.join(errors)
print('PASS: real service + Qt practice limits, parent authentication, optional screen-time settings, credits and caps, invalid inputs, old-service compatibility, daily reset, compact UI, and pause/focus restoration.')
view.close()
