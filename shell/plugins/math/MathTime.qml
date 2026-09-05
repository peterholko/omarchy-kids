import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "MathModel.js" as Quiz

// Math time (plans/kids-screen-time.md): the arithmetic app of a child
// install. Two ways to use it. Practice: any grade from 1 to 6, ten
// questions, checked here from the answer the daemon hands over with the
// question, recorded by nobody. Earn time: the parent's grade and set,
// questions from and answers to omarchy-kids-timed over its socket, so
// root keeps the answers and the credits. Full screen and holding the
// keyboard, like the lock screen; with no time left it opens straight into
// an earning set. After the lock-screen handoff Escape offers a parent-only
// five-minute bypass; otherwise the lock screen re-opens it if it goes, and
// the daemon's one-minute failsafe applies whenever the app is not covering
// the zero-budget session.
//
// Not Math.qml: a QML file's name is a type in its directory, and a type
// called Math shadows JavaScript's Math here and in MathModel.js, so every
// Math.max and Math.round threw and the question drew into a zero-width
// column.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string clientPath: Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-kids-time-client"
  readonly property string statusPath: "/var/lib/omarchy/parent/" + userName + "/time/status.json"
  readonly property string gradePath: homeDir + "/.local/state/omarchy/math-grade"
  property string statusRaw: ""
  readonly property var status: Quiz.gateFromStatus(statusRaw, true)

  // Which screen, and which kind of set.
  property string screen: "start"
  property string mode: "practice"
  property bool forcedOpen: false
  property bool parentPromptOpen: false
  property string parentPromptNote: ""
  property bool parentPromptError: false
  // open() decides practice or earning on a status read taken after the
  // summon, never on a copy cached from before a credit landed.
  property bool decidePending: false
  property int grade: 5
  readonly property bool earning: mode === "earn"
  readonly property bool canEarn: status.enabled && !status.school
  readonly property bool parentBypassAvailable: forcedOpen && status.enabled && status.gated
  readonly property bool showEscapeHint: !forcedOpen && !status.gated
  readonly property int level: earning ? Quiz.levelNumber(status.level) : grade
  readonly property int total: earning ? Math.max(1, status.questions) : Quiz.PRACTICE_COUNT

  // One set.
  property int answered: 0
  property int correctAnswers: 0
  property int earned: 0 // seconds of screen time this set has earned
  property int attempts: 0
  property int streak: 0
  property int bestStreak: 0
  property string questionId: ""
  property string questionText: ""
  property string expectedAnswer: ""
  property string feedback: ""
  property string feedbackKind: ""
  property bool checking: false
  property bool questionTimedOut: false
  property string answerText: ""

  readonly property string modeLabel: earning ? "Earn time" : "Practice"
  readonly property string headline: Quiz.gradeLabel(level) + "  ·  " + modeLabel
  readonly property string progress: Quiz.progressLabel(answered, total)
  readonly property string streakText: Quiz.streakLabel(streak)
  readonly property string promise: total + (total === 1 ? " question earns " : " questions earn ") + status.sessionMinutes + " min at " + Quiz.gradeLabel(Quiz.levelNumber(status.level))
  readonly property string balance: Quiz.remainingLabel(status.budget)
  readonly property var summary: Quiz.sessionSummary(mode, correctAnswers, total, earned, status.budget, bestStreak)

  // A white sheet with dark ink, the same on every theme and opaque, so
  // nothing behind it shows through; not the lock screen's glass.
  readonly property color paper: Quiz.PALETTE.paper
  readonly property color ink: Quiz.PALETTE.ink
  readonly property color inkSoft: Quiz.PALETTE.inkSoft
  readonly property color rule: Quiz.PALETTE.rule
  readonly property color mark: Quiz.PALETTE.mark
  readonly property color good: Quiz.PALETTE.good
  readonly property color bad: Quiz.PALETTE.bad
  readonly property color feedbackColor: feedbackKind === "correct" ? good
    : (feedbackKind === "wrong" || feedbackKind === "reveal") ? bad
    : ink

  function open(payloadJson) {
    gradeView.reload()
    forcedOpen = Quiz.isForcedOpen(payloadJson)
    parentPromptOpen = false
    parentPromptNote = ""
    parentPromptError = false
    opened = true
    screen = ""
    blockCalculatorWindows()
    decidePending = true
    statusView.reload()
  }

  function decideStart() {
    if (!decidePending) return
    decidePending = false
    // With no time left the app is the session: straight into earning.
    if (status.gated) {
      mode = "earn"
      startSession()
    } else {
      if (!canEarn) mode = "practice"
      screen = "start"
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  function close() {
    opened = false
    forcedOpen = false
    parentPromptOpen = false
    parentPromptNote = ""
    parentPromptError = false
    parentPasswordInput.text = ""
    decidePending = false
    screen = "start"
    questionId = ""
    questionText = ""
    expectedAnswer = ""
    feedback = ""
    feedbackKind = ""
    answerText = ""
  }

  function toggle() {
    if (opened) close()
    else open("{}")
  }

  function chooseGrade(n) {
    if (earning || n < 1 || n > 6) return
    grade = n
    saveGradeProc.command = ["bash", "-c", "mkdir -p ~/.local/state/omarchy && printf '%s\\n' " + n + " >~/.local/state/omarchy/math-grade"]
    saveGradeProc.running = true
  }

  function chooseMode(next) {
    if (next === "earn" && !canEarn) return
    mode = next
  }

  // Omacalc stays available to the child normally, but cannot be kept open or
  // launched while a question is on screen. Watching compositor toplevels
  // covers the launcher, calculator keys, terminals, and alternate binaries.
  function blockCalculatorWindows() {
    if (!opened) return
    var toplevels = ToplevelManager.toplevels.values || []
    for (var i = toplevels.length - 1; i >= 0; i--) {
      var toplevel = toplevels[i]
      if (toplevel && Quiz.isCalculatorAppId(toplevel.appId)) toplevel.close()
    }
  }

  function startSession() {
    answered = 0
    correctAnswers = 0
    earned = 0
    streak = 0
    bestStreak = 0
    feedback = ""
    feedbackKind = ""
    answerText = ""
    screen = "question"
    askQuestion()
  }

  function askQuestion() {
    if (questionProc.running) return
    attempts = 0
    questionId = ""
    questionText = ""
    expectedAnswer = ""
    answerText = ""
    questionTimedOut = false
    // launched goes false before the command: after a start that failed, the
    // Process still means to run and starts again on the next command.
    questionProc.launched = false
    if (earning) questionProc.command = [clientPath, "quiz"]
    else questionProc.command = [clientPath, "practice", Quiz.levelName(grade)]
    questionProc.running = true
    slowQuestionTimer.restart()
    questionWatchdog.restart()
    Qt.callLater(function() { answerInput.forceActiveFocus() })
  }

  // The client's reply, or the reason there is none. Quickshell reports a
  // helper that could not start at all with runningChanged alone, no exited,
  // so a failure arrives here with a name of its own.
  function takeQuestion(raw, failure) {
    slowQuestionTimer.stop()
    questionWatchdog.stop()
    var question = Quiz.parseQuestionJson(raw)
    if (!(question && question.text) && failure) question = { error: failure }
    if (question && question.text) {
      questionId = question.id || ""
      questionText = question.text
      expectedAnswer = question.answer || ""
      feedback = ""
      feedbackKind = ""
    } else {
      questionId = ""
      questionText = ""
      expectedAnswer = ""
      feedback = Quiz.questionErrorText(question)
      feedbackKind = "info"
    }
  }

  function submit() {
    if (screen !== "question") return
    var answer = Quiz.normalizeAnswer(answerText)
    if (checking || answerProc.running) return
    if (questionText.length === 0) { askQuestion(); return }
    if (answer.length === 0) return
    if (earning) {
      checking = true
      answerProc.launched = false
      answerProc.command = [clientPath, "answer", questionId, answer]
      answerProc.running = true
      answerWatchdog.restart()
    } else {
      handleResult(Quiz.judgePractice(answer, expectedAnswer, attempts))
    }
  }

  function handleAnswer(reply) {
    answerWatchdog.stop()
    checking = false
    handleResult(Quiz.parseVerdictJson(reply))
  }

  function handleResult(result) {
    feedback = Quiz.feedbackFor(result, mode)
    if (earning) statusView.reload()
    if (result.kind === "correct") {
      correctAnswers += 1
      earned += result.credited
      streak += 1
      if (streak > bestStreak) bestStreak = streak
      feedbackKind = "correct"
    } else if (result.kind === "wrong") {
      streak = 0
      feedbackKind = result.expected ? "reveal" : "wrong"
    } else {
      feedbackKind = "info"
    }
    if (Quiz.questionDone(result)) {
      answered += 1
      questionId = ""
      if (answered >= total) {
        finishTimer.interval = result.kind === "correct" ? 900 : 2200
        finishTimer.restart()
        return
      }
    }
    // A first practice miss keeps the question for one more try, and "too
    // fast" keeps it too; anything else brings the next after the banner.
    if ((result.kind === "wrong" && !result.expected) || result.kind === "too_fast") {
      if (result.kind === "wrong") attempts += 1
      answerText = ""
      return
    }
    nextQuestionTimer.interval = result.kind === "correct" ? 900 : 2200
    nextQuestionTimer.restart()
  }

  function finishSession() {
    screen = "results"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Done on the results screen: leave, or go again while there is still no time.
  function finish() {
    if (status.gated && status.enabled) startSession()
    else close()
  }

  function openParentPrompt() {
    if (!parentBypassAvailable || bypassProc.running) return
    parentPromptOpen = true
    parentPromptNote = ""
    parentPromptError = false
    parentPasswordInput.text = ""
    Qt.callLater(function() { parentPasswordInput.forceActiveFocus() })
  }

  function cancelParentPrompt() {
    if (bypassProc.running) return
    parentPromptOpen = false
    parentPromptNote = ""
    parentPromptError = false
    parentPasswordInput.text = ""
    Qt.callLater(function() {
      if (root.screen === "question") answerInput.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  function submitParentBypass() {
    if (!parentPromptOpen || bypassProc.running) return
    var password = parentPasswordInput.text
    if (password.trim() === "") return
    parentPromptNote = "Checking…"
    parentPromptError = false
    bypassProc.pendingPassword = password
    parentPasswordInput.text = ""
    bypassProc.launched = false
    bypassProc.command = [clientPath, "--password-stdin", "grant", "5"]
    bypassProc.running = true
  }

  function handleParentBypass(raw) {
    var payload
    try { payload = JSON.parse(raw) } catch (error) { payload = null }
    parentPasswordInput.text = ""
    if (payload && payload.ok === true) {
      close()
      return
    }
    var reason = payload ? String(payload.error || "") : ""
    parentPromptError = true
    if (reason === "bad_password") parentPromptNote = "That is not the parent password."
    else if (reason === "password_locked_out") parentPromptNote = "Too many tries. Wait " + payload.retry_in_seconds + " seconds."
    else parentPromptNote = "Could not grant time. Try again."
    Qt.callLater(function() { parentPasswordInput.forceActiveFocus() })
  }

  // Escape: a set in progress goes back to the start screen, the start
  // screen closes the app. With no time left there is nowhere for the child
  // to go; after an unlock, however, it opens the parent-password bypass.
  function back() {
    if (status.gated && status.enabled) {
      if (parentBypassAvailable) openParentPrompt()
      return
    }
    if (screen === "question" || screen === "results") {
      questionId = ""
      questionText = ""
      feedback = ""
      feedbackKind = ""
      answerText = ""
      screen = "start"
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      close()
    }
  }

  Timer {
    id: nextQuestionTimer
    interval: 900
    onTriggered: root.askQuestion()
  }

  Timer {
    id: finishTimer
    interval: 900
    onTriggered: root.finishSession()
  }

  // A question is normally back well under a second. Say so when it is not,
  // and give up on a client that hangs, so the banner can offer Enter; the
  // client itself stops waiting for the daemon after five.
  Timer {
    id: slowQuestionTimer
    interval: 1500
    onTriggered: if (root.questionText.length === 0 && root.feedback.length === 0) { root.feedback = "Getting a question…"; root.feedbackKind = "info" }
  }

  Timer {
    id: questionWatchdog
    interval: 10000
    onTriggered: { root.questionTimedOut = true; questionProc.running = false }
  }

  Timer {
    id: answerWatchdog
    interval: 10000
    onTriggered: answerProc.running = false
  }

  // status.json is root's and world-readable; every credit rewrites it.
  FileView {
    id: statusView
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.statusRaw = text()
      root.decideStart()
    }
    onLoadFailed: {
      root.statusRaw = ""
      root.decideStart()
    }
    onFileChanged: reload()
  }

  // The grade she practised last, hers to keep.
  FileView {
    id: gradeView
    path: root.gradePath
    printErrors: false
    onLoaded: {
      var n = parseInt(String(text()).trim(), 10)
      if (n >= 1 && n <= 6) root.grade = n
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.blockCalculatorWindows() }
  }

  // Both clients: exited brings the reply; a start that failed outright
  // (no such file, not executable) brings only runningChanged, so that case
  // is caught by the launch never having been seen.
  Process {
    id: questionProc
    property bool launched: false
    stdout: StdioCollector { id: questionOut; waitForEnd: true }
    onStarted: launched = true
    onExited: function(exitCode) { root.takeQuestion(questionOut.text, root.questionTimedOut ? "daemon_timeout" : "") }
    onRunningChanged: if (!running && !launched) root.takeQuestion("", "failed_to_start")
  }

  Process {
    id: answerProc
    property bool launched: false
    stdout: StdioCollector { id: answerOut; waitForEnd: true }
    onStarted: launched = true
    onExited: root.handleAnswer(answerOut.text)
    onRunningChanged: if (!running && !launched) root.handleAnswer("")
  }

  Process {
    id: bypassProc
    property string pendingPassword: ""
    property bool launched: false
    stdinEnabled: true
    stdout: StdioCollector { id: bypassOut; waitForEnd: true }
    onStarted: {
      launched = true
      write(pendingPassword + "\n")
      pendingPassword = ""
    }
    onExited: root.handleParentBypass(bypassOut.text)
    onRunningChanged: if (!running && !launched) root.handleParentBypass("")
  }

  Process {
    id: saveGradeProc
  }

  // A choice on the start screen and a button on the results screen.
  // An inline component has no view of the file's ids, so the sheet's colors
  // come from the model here rather than from root.
  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool picked: false
    property bool dim: false
    property real fontSize: Style.font.heading
    property real chipPadding: Style.space(18)
    readonly property color paper: Quiz.PALETTE.paper
    readonly property color ink: Quiz.PALETTE.ink
    readonly property color rule: Quiz.PALETTE.rule
    readonly property color mark: Quiz.PALETTE.mark
    signal tapped()
    implicitWidth: chipLabel.implicitWidth + chipPadding * 2
    implicitHeight: chipLabel.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: picked ? Util.alpha(mark, 0.12) : paper
    border.width: 2
    border.color: picked ? mark : rule
    opacity: dim ? 0.35 : 1
    Behavior on opacity { NumberAnimation { duration: 150 } }
    Text {
      id: chipLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.label
      color: chip.picked ? chip.mark : chip.ink
      font.family: Style.font.family
      font.pixelSize: chip.fontSize
      font.bold: chip.picked
    }
    MouseArea {
      anchors.fill: parent
      enabled: !chip.dim
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.tapped()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: root.paper
    WlrLayershell.namespace: "omarchy-math"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The screen stays on while she works, on paper or otherwise.
    IdleInhibitor {
      window: panel
      enabled: root.opened
    }

    Chip {
      objectName: "parentEscape"
      visible: root.parentBypassAvailable && !root.parentPromptOpen
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(24)
      z: 20
      label: "Esc · Parent"
      fontSize: Style.font.body
      chipPadding: Style.space(14)
      onTapped: root.openParentPrompt()
    }

    // Keys on the start and results screens; the answer field has its own.
    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.opened && root.screen !== "question"
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; return }
        if (root.screen === "start") {
          if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) { root.chooseGrade(event.key - Qt.Key_0); event.accepted = true }
          else if (event.key === Qt.Key_Left) { root.chooseGrade(Math.max(1, root.grade - 1)); event.accepted = true }
          else if (event.key === Qt.Key_Right) { root.chooseGrade(Math.min(6, root.grade + 1)); event.accepted = true }
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { root.chooseMode(root.earning ? "practice" : "earn"); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.startSession(); event.accepted = true }
        } else if (root.screen === "results") {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.finish(); event.accepted = true }
          else if (event.key === Qt.Key_Space || event.key === Qt.Key_A) { root.startSession(); event.accepted = true }
        }
      }
    }

    // ---- Start: pick a grade, pick a mode, go. ----
    Column {
      visible: root.screen === "start"
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(96), Style.space(820))
      spacing: Style.space(22)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "Math time"
        color: root.ink
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.displayLarge * 1.5)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.canEarn ? "Practise any grade, or earn screen time at yours." : "Ten questions at the grade you pick."
        color: root.inkSoft
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(10)
        Repeater {
          model: 6
          Chip {
            required property int index
            readonly property int n: index + 1
            label: String(n)
            picked: root.level === n
            dim: root.earning && root.level !== n
            fontSize: Math.round(Style.font.display * 1.1)
            chipPadding: Style.space(24)
            onTapped: root.chooseGrade(n)
          }
        }
      }

      Text {
        objectName: "gradeBlurb"
        textFormat: Text.PlainText
        width: parent.width
        text: root.earning
          ? Quiz.gradeLabel(root.level) + ", set by your parent: " + Quiz.gradeBlurb(root.level)
          : Quiz.gradeLabel(root.level) + ": " + Quiz.gradeBlurb(root.level)
        color: root.ink
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(12)
        Chip {
          label: "Practice  ·  " + Quiz.PRACTICE_COUNT + " questions"
          picked: !root.earning
          onTapped: root.chooseMode("practice")
        }
        Chip {
          visible: root.canEarn
          label: "Earn time  ·  " + root.promise
          picked: root.earning
          onTapped: root.chooseMode("earn")
        }
      }

      Chip {
        anchors.horizontalCenter: parent.horizontalCenter
        label: "Start"
        picked: true
        fontSize: Style.font.display
        chipPadding: Style.space(40)
        onTapped: root.startSession()
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: (root.status.enabled ? root.balance + "  ·  " : "") + "1 to 6 picks a grade  ·  Enter to start" + (root.showEscapeHint ? "  ·  Esc to leave" : (root.parentBypassAvailable ? "  ·  Esc for parent" : ""))
        color: root.inkSoft
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }
    }

    // ---- Question: one at a time, big, with the answer under it. ----
    Column {
      visible: root.screen === "question"
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(96), Style.space(820))
      spacing: Style.space(18)

      Row {
        width: parent.width
        Text {
          objectName: "headline"
          textFormat: Text.PlainText
          width: parent.width / 2
          text: root.headline
          color: root.inkSoft
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width / 2
          text: root.progress + (root.streakText.length > 0 ? "  ·  " + root.streakText : "")
          color: root.inkSoft
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          horizontalAlignment: Text.AlignRight
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(6)
        radius: height / 2
        color: Util.alpha(root.ink, 0.12)
        Rectangle {
          width: parent.width * Math.min(1, root.answered / Math.max(1, root.total))
          height: parent.height
          radius: height / 2
          color: root.mark
          Behavior on width { NumberAnimation { duration: 250 } }
        }
      }

      Item { width: 1; height: Style.space(16) }

      Text {
        objectName: "question"
        textFormat: Text.PlainText
        width: parent.width
        text: root.questionText.length > 0 ? root.questionText.replace(/^What is /, "").replace(/\?$/, "") : "…"
        color: root.ink
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.displayLarge * 2.4)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Rectangle {
        id: field
        width: Style.space(420)
        height: Style.space(88)
        anchors.horizontalCenter: parent.horizontalCenter
        color: root.paper
        radius: Style.cornerRadius
        border.width: 3
        border.color: root.feedbackKind === "wrong" || root.feedbackKind === "reveal" ? root.bad : root.mark

        RegularExpressionValidator {
          id: digitsOnly
          regularExpression: /[0-9]{0,9}/
        }

        TextInput {
          id: answerInput
          anchors.fill: parent
          anchors.leftMargin: Style.space(18)
          anchors.rightMargin: Style.space(18)
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignHCenter
          focus: root.opened && root.screen === "question"
          enabled: !root.checking
          readOnly: root.checking
          inputMethodHints: Qt.ImhDigitsOnly
          validator: digitsOnly
          text: root.answerText
          color: root.ink
          selectionColor: Util.alpha(root.mark, 0.3)
          selectedTextColor: root.ink
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.displayLarge * 1.4)
          font.bold: true
          onTextChanged: root.answerText = text
          onAccepted: root.submit()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true }
            else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U) { root.answerText = ""; event.accepted = true }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.fill: answerInput
          visible: answerInput.text.length === 0
          text: root.checking ? "Checking…" : "Your answer"
          color: root.inkSoft
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.displayLarge * 1.1)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
      }

      // The verdict: green for right, red for a miss, the answer on a second miss.
      Rectangle {
        objectName: "feedback"
        width: parent.width
        height: root.feedback.length > 0 ? feedbackText.implicitHeight + Style.space(28) : 0
        radius: Style.cornerRadius
        color: Util.alpha(root.feedbackColor, root.feedbackKind === "info" ? 0.12 : 0.18)
        opacity: root.feedback.length > 0 ? 1 : 0
        clip: true
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on height { NumberAnimation { duration: 120 } }
        Text {
          id: feedbackText
          anchors.centerIn: parent
          width: parent.width - Style.space(40)
          textFormat: Text.PlainText
          text: root.feedback
          color: root.feedbackKind === "info" ? root.ink : root.feedbackColor
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.bold: root.feedbackKind === "correct"
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      Text {
        objectName: "footer"
        textFormat: Text.PlainText
        width: parent.width
        text: "Enter to answer" + (root.showEscapeHint ? "  ·  Esc to stop" : (root.parentBypassAvailable ? "  ·  Esc for parent" : ""))
        color: root.inkSoft
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }
    }

    // ---- Results: how it went, then again or done. ----
    Column {
      visible: root.screen === "results"
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(96), Style.space(820))
      spacing: Style.space(20)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.correctAnswers === root.total ? "All of them!" : (root.correctAnswers >= root.total * 0.7 ? "Nice work" : "Set done")
        color: root.ink
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.displayLarge * 1.5)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        objectName: "results"
        textFormat: Text.PlainText
        width: parent.width
        text: root.summary.join("\n")
        color: root.ink
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        lineHeight: 1.3
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(14)
        Chip {
          label: "Again"
          picked: root.status.gated && root.status.enabled
          fontSize: Style.font.display
          chipPadding: Style.space(32)
          onTapped: root.startSession()
        }
        Chip {
          visible: !(root.status.gated && root.status.enabled)
          label: "Done"
          picked: true
          fontSize: Style.font.display
          chipPadding: Style.space(32)
          onTapped: root.finish()
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.status.gated && root.status.enabled
          ? "No time left yet: another set earns some.  ·  Enter for another set" + (root.parentBypassAvailable ? "  ·  Esc for parent" : "")
          : "Enter to finish  ·  Space for another set"
        color: root.inkSoft
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }

    Rectangle {
      id: parentPrompt
      objectName: "parentPrompt"
      anchors.fill: parent
      visible: root.parentPromptOpen
      z: 100
      color: Qt.rgba(0, 0, 0, 0.38)

      MouseArea {
        anchors.fill: parent
        onClicked: parentPasswordInput.forceActiveFocus()
      }

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(48), Style.space(520))
        height: parentPromptContent.implicitHeight + Style.space(64)
        radius: Style.cornerRadius
        color: root.paper
        border.width: 2
        border.color: root.rule

        Column {
          id: parentPromptContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.space(32)
          spacing: Style.space(16)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Parent access"
            color: root.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Enter the parent password to leave Math time and add 5 minutes."
            color: root.inkSoft
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Rectangle {
            width: parent.width
            height: Style.space(56)
            radius: Style.cornerRadius
            color: root.paper
            border.width: 2
            border.color: root.parentPromptError ? root.bad : root.mark

            TextInput {
              id: parentPasswordInput
              anchors.fill: parent
              anchors.leftMargin: Style.space(14)
              anchors.rightMargin: Style.space(14)
              enabled: !bypassProc.running
              focus: root.parentPromptOpen
              echoMode: TextInput.Password
              inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
              color: root.ink
              selectionColor: Util.alpha(root.mark, 0.3)
              selectedTextColor: root.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              verticalAlignment: TextInput.AlignVCenter
              onAccepted: root.submitParentBypass()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelParentPrompt()
                  event.accepted = true
                }
              }
            }

            Text {
              anchors.top: parentPasswordInput.top
              anchors.bottom: parentPasswordInput.bottom
              anchors.left: parentPasswordInput.left
              anchors.right: parentPasswordInput.right
              anchors.leftMargin: Style.space(14)
              visible: parentPasswordInput.text.length === 0
              textFormat: Text.PlainText
              text: "Parent password"
              color: root.inkSoft
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              verticalAlignment: Text.AlignVCenter
            }
          }

          Text {
            visible: root.parentPromptNote !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.parentPromptNote
            color: root.parentPromptError ? root.bad : root.inkSoft
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(12)

            Chip {
              label: "Cancel"
              dim: bypassProc.running
              onTapped: root.cancelParentPrompt()
            }

            Chip {
              label: bypassProc.running ? "Checking…" : "Add 5 min"
              picked: true
              dim: bypassProc.running
              onTapped: root.submitParentBypass()
            }
          }
        }
      }
    }
  }
}
