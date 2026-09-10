"""Render the real controls with portable Qt and inert Quickshell IO fixtures.

Run with PySide6 Essentials: python test/controls/visual.py OUTPUT_DIRECTORY
The fixture never invokes sudo, a daemon, desktop commands, a VM or the ISO.
"""
import json
import re
import os
from pathlib import Path
import shutil
import sys
import tempfile
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE', 'Basic')
from PySide6.QtCore import QUrl, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
workspace = tempfile.TemporaryDirectory(prefix='controls-qt-fixture-')
base = Path(workspace.name)
def write(name, text):
    p=base/name; p.parent.mkdir(parents=True, exist_ok=True);p.write_text(text)
for part in ('Ui','Commons'):
    shutil.copytree(ROOT/'shell'/part, base/'qs'/part)
shutil.copytree(ROOT/'shell/plugins/screen-time', base/'controls', symlinks=False)
shutil.copytree(ROOT/'shell/plugins/screen-time/math', base/'math')
math_file = base/'math/MathTime.qml'
math_source = math_file.read_text().replace('  PanelWindow {', '  FloatingWindow {\n    implicitWidth: 1100\n    implicitHeight: 800')
math_source = re.sub(r'^    (?:anchors \{ top:.*|WlrLayershell\..*|exclusionMode:.*)\n', '', math_source, flags=re.M)
math_file.write_text(math_source)
(base/'controls/math/MathTime.qml').write_text(math_source)
write('Quickshell/qmldir', 'module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\nsingleton DesktopEntries 1.0 DesktopEntries.qml\nFloatingWindow 1.0 FloatingWindow.qml\n')
write('Quickshell/Quickshell.qml', '''pragma Singleton
import QtQuick
QtObject { function env(name) { return name === "USER" ? "linnea" : name === "OMARCHY_PATH" ? "/fixture" : "" }
function execDetached(command) {} }
''')
write('Quickshell/DesktopEntries.qml','''pragma Singleton
import QtQuick
QtObject { property var applications: ({values: [{id:"omarchy-pawberry.desktop"},{id:"omarchy-number-grove.desktop"},{id:"omarchy-paw-post.desktop"}]}) }
''')
write('Quickshell/FloatingWindow.qml','''import QtQuick
Window { transientParent: null; property int implicitWidth: 600; property int implicitHeight: 740
property size minimumSize; property size maximumSize
width: implicitWidth; height: implicitHeight }
''')
write('Quickshell/Wayland/qmldir', 'module Quickshell.Wayland\nsingleton ToplevelManager 1.0 ToplevelManager.qml\nIdleInhibitor 1.0 IdleInhibitor.qml\n')
write('Quickshell/Wayland/ToplevelManager.qml', '''pragma Singleton
import QtQuick
QtObject { property QtObject toplevels: QtObject { property var values: [] } }
''')
write('Quickshell/Wayland/IdleInhibitor.qml', 'import QtQuick\nQtObject { property var window; property bool enabled: false }\n')
write('Quickshell/Io/qmldir','module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\nFileView 1.0 FileView.qml\nSplitParser 1.0 SplitParser.qml\n')
write('Quickshell/Io/Process.qml','''import QtQuick
QtObject { property var command: []; property bool running: false; property bool stdinEnabled: false
property var stdout; property var stderr; signal started(); signal exited(int code, int status)
function write(text) {} function closeWriteChannel() {} }
''')
write('Quickshell/Io/StdioCollector.qml','''import QtQuick
QtObject { property string text: ""; property bool waitForEnd: false; signal streamFinished() }
''')
write('Quickshell/Io/SplitParser.qml', 'import QtQuick\nQtObject { signal read(string data) }\n')
write('Quickshell/Io/FileView.qml','''import QtQuick
QtObject { property string path: ""; property bool watchChanges: false; property bool printErrors: false
property bool atomicWrites: false; property bool blockLoading: false; property bool preload: false; property bool loaded: false
signal fileChanged(); signal loadFailed(int error); signal loadedChangedUnused()
signal loaded(); function text() { return "" } function reload() {} function setText(value) {} }
'''.replace('property bool loaded: false','property bool exists: false'))
write('controls/school/Menu.qml', '''import QtQuick
Item { property var shell; property var manifest; property string omarchyPath
property bool opened: false; function open(payload) { opened = true } function close() { opened = false }
function removalReady() { return \"ready\" } function guardAppLaunch() {} function launchSchoolBrowser() {}
function launchAllowedApp(payload) {} function refresh() {} }
''')
# The source Qt widgets and theme engine are unchanged; only OS IO is inert.
status = {'connected': True, 'phase':'school', 'profileName':'Linnea', 'remainingSeconds':2700,
          'spentSeconds':900, 'earnedSeconds':360, 'grantedSeconds':0, 'budgetSeconds':3600,
          'minWarnSeconds':60, 'earnEnabled':True, 'earnRoomSeconds':6840, 'earnEvents':[],
          'budgetMinutes':{'mon':60,'tue':60,'wed':60,'thu':60,'fri':60,'sat':90,'sun':90},
          'blockedPeriods':[{'label':'Bedtime','enabled':True,'start':'20:00','end':'07:00','days':['mon','tue','wed','thu','fri','sat','sun'],'mode':'block'}],
          'blockedLabel':'', 'nextBlock':None, 'philosophy':'limits', 'agreementText':'We take breaks together.',
          'agreementMinutes':60, 'breakNudgeMinutes':45, 'stretchSeconds':0, 'reflections':[],
          'level':'grade7', 'questionsPerSet':10, 'setMinutes':30, 'earnCapMinutes':120,
          'freeLabel':'School', 'lockInSeconds':None, 'clientPath':'/fixture/time', 'schoolClientPath':'/fixture/school'}
props='\n'.join('property var '+k+': '+json.dumps(v) for k,v in status.items())
write('Fixture.qml', '''import QtQuick
import "controls" as Controls
import "math" as MathPlugin
import qs.Commons
Item {
 id: fixture
 property var mock: QtObject {
  '''+props+'''
  property bool schoolMode: schoolService.schoolMode
  property var shell: null
  property var schoolService: QtObject {
   property bool schoolEnabled: true; property bool schoolMode: true
   property string userName: "linnea"; property var allowedDesktopIds: ["chromium", "omarchy-pawberry"]
   property var blockedPeriods: [{label:"School", enabled:true, start:"08:30", end:"15:00", days:["mon","tue","wed","thu","fri"], mode:"free"}]
  }
 }
 Controls.SettingsWindow { id: controls; service: fixture.mock }
 property alias controls: controls
 MathPlugin.MathTime { id: math }
 property alias math: math
 Controls.Service { id: compiledService }
 Controls.Entry { id: entry; shell: QtObject { function serviceFor(id) { return compiledService } } }
 property alias entry: entry
 function lightTheme() { Color.foreground = "#5a3a60"; Color.background = "#fff5fa"; Color.accent = "#d32b77" }
}
''')
errors=[]
def log(kind,context,text):
    if 'file:' in text or 'Error' in text: errors.append(text)
    print(text, file=sys.stderr)
qInstallMessageHandler(log)
app=QGuiApplication(sys.argv); app.styleHints().setTabFocusBehavior(Qt.TabFocusAllControls)
engine=QQmlApplicationEngine();engine.addImportPath(str(base))
engine.load(QUrl.fromLocalFile(str(base/'Fixture.qml')))
assert engine.rootObjects(), errors
fixture=engine.rootObjects()[0]
engine.globalObject().setProperty('fixture',engine.newQObject(fixture))
def js(code):
    result=engine.evaluate(code)
    assert not result.isError(),result.toString()
    return result.toVariant()
def capture(name):
    QTest.qWait(120)
    window=next(w for w in app.allWindows() if w.isVisible())
    assert window.grabWindow().save(str(out/(name+'.png')))
    return window
js('fixture.controls.show()')
window=capture('locked-controls')
assert not js('fixture.controls.unlocked')
# Inject the result of successful parent authentication; no password service runs.
js('fixture.controls.children[1]') if False else None
# The live page objects are found by type through the QObject child hierarchy.
def descendants(item):
    yield item
    for child in item.children(): yield from descendants(child)
overview=next(o for o in descendants(fixture) if o.metaObject().className().startswith('OverviewPage'))
engine.globalObject().setProperty('overview',engine.newQObject(overview))
js('overview.tryUnlock("fixture-only")')
assert js('overview.authenticating')
capture('checking-password')
js('fixture.controls.close()')
assert not js('overview.authenticating') and js('overview.parentPassword') == ''
js('fixture.controls.show()')
js('overview.parentPassword = "fixture-only"; overview.parentUnlocked = true')
capture('today')
js('fixture.controls.selectedTab = 1');capture('time-math')
page = next(o for o in descendants(fixture) if o.metaObject().className().startswith('TimeSettingsPage'))
engine.globalObject().setProperty('timePage',engine.newQObject(page))
flickable = next(o for o in descendants(page) if o.metaObject().indexOfProperty('contentY') >= 0 and o.property('height') > 200)
flickable.setProperty('contentY', 480);capture('math-settings-grade7')
assert flickable.property('contentY') > 200, 'math settings cannot scroll into view'
js('fixture.controls.selectedTab = 2');capture('school-apps')
js('fixture.lightTheme()');capture('school-apps-light')
window.setWidth(520);window.setHeight(420);capture('compact-school')
js('fixture.controls.close()')
assert not js('fixture.controls.unlocked')
assert js('overview.parentPassword') == ''
assert not any(w.isVisible() for w in app.allWindows())
# Simulate login/unlock while School Mode is active: no window may appear,
# even with a stale public file saying that free time has run out.
js('fixture.math.statusRaw = JSON.stringify({enabled:true,budget:0,school:false}); fixture.math.open(\"{\\\"forced\\\":true}\")')
QTest.qWait(25)
assert not any(w.isVisible() for w in app.allWindows()), 'forced math flashed before the live policy reply'
js('fixture.math.statusRaw = JSON.stringify({ok:true,remaining_seconds:0,mode:\"school\",phase:\"school\"}); fixture.math.decideStart()')
assert not js('fixture.math.opened')
assert not any(w.isVisible() for w in app.allWindows()), 'school login opened math'
# Optional practice remains available during School Mode, including Grade 7.
js('fixture.math.open(\"{}\"); fixture.math.statusRaw = JSON.stringify({enabled:true,school:true,budget:0}); fixture.math.decideStart(); fixture.math.chooseGrade(7)')
capture('grade-seven-practice')
js('fixture.math.mode = \"practice\"; fixture.math.screen = \"question\"; fixture.math.takeQuestion(JSON.stringify({ok:true,text:\"1/8 = ? (percent)\",answer:\"12.5%\",hint:\"Use % for a percentage.\"}), \"\")')
window=capture('percent-practice')
answer=next(o for o in descendants(fixture) if o.objectName() == 'mathAnswer' and o.property('visible'))
engine.globalObject().setProperty('answer',engine.newQObject(answer))
js('answer.forceActiveFocus()')
for key in (Qt.Key_1,Qt.Key_2,Qt.Key_Period,Qt.Key_5,Qt.Key_Percent): QTest.keyClick(window,key)
assert js('fixture.math.answerText') == '12.5%'
QTest.keyClick(window,Qt.Key_Return)
assert js('fixture.math.correctAnswers') == 1
js('fixture.math.close()')
# A school transition cancels an already-open earning session.
js('fixture.math.statusRaw = JSON.stringify({enabled:true,school:false,budget:0}); fixture.math.open(\"{\\\"forced\\\":true}\"); fixture.math.decideStart()')
assert js('fixture.math.opened')
js('fixture.math.statusRaw = JSON.stringify({enabled:true,mode:\"school\",school:true,budget:0})')
assert not js('fixture.math.opened')
assert not any(w.isVisible() for w in app.allWindows())
js('fixture.entry.open(\"{}\")')
assert js('fixture.entry.opened') and js('fixture.entry.mathOpen()') == 'false'
js('fixture.entry.close(); fixture.entry.open(\"{\\\"menu\\\":\\\"apps\\\"}\")')
assert js('fixture.entry.opened')
js('fixture.entry.close()')
assert not js('fixture.entry.opened')
js('fixture.entry.open(JSON.stringify({mode:"input",prompt:"Example"}))')
assert js('fixture.entry.opened')
js('fixture.entry.close(); fixture.entry.open("math")')
compiled = next(o for o in descendants(fixture) if o.metaObject().className().startswith('Service'))
bundled = next(o for o in descendants(compiled) if o.metaObject().className().startswith('MathTime'))
engine.globalObject().setProperty('bundled', engine.newQObject(bundled))
js('bundled.statusRaw = JSON.stringify({enabled:true,school:true,budget:0}); bundled.decideStart()')
assert js('fixture.entry.mathOpen()') == 'true'
assert len([w for w in app.allWindows() if w.isVisible()]) == 1
js('fixture.entry.close()')
assert not js('fixture.entry.opened')
assert not errors, errors
print('PASS: one window, three pages, parent authentication state and compact layout')
