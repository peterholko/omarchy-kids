import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import "../../services/MathModel.js" as MathGate

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool strandedLock: false
  property bool strandedLockResolved: false

  // Screen time (plans/kids-screen-time.md). Root owns the budget and writes
  // status.json. With no time left the password still unlocks the session, then
  // Math time takes over until the kid earns more. A parent-password unlock
  // credits five minutes before this handoff, so the final gate check cancels it.
  property bool childInstall: false
  property string timeStatusRaw: ""
  readonly property var timeGate: MathGate.gateFromStatus(timeStatusRaw, childInstall)
  readonly property string timeStatusPath: "/var/lib/omarchy/parent/" + userName + "/time/status.json"
  property bool mathSummonPending: false
  // The parent helper credits minutes during authentication, before PAM
  // answers; the status file on disk is ahead of the copy cached here. The
  // handoff to Math time waits for a dedicated read started after the unlock.
  property bool timeStatusFresh: true
  property bool postUnlockStatusPending: false
  property bool timeStatusReadQueued: false
  property bool postUnlockReadQueued: false

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
  // What the kid has banked, shown on the lock screen whenever screen time
  // is on. With no time left the password still opens the screen; the math
  // plugin then takes over the session until she has earned some.
  readonly property string timeLabel: childInstall && timeGate.enabled
    ? (timeGate.gated ? "No time left: unlock to do your math" : MathGate.remainingLabel(timeGate.budget))
    : ""

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  function refreshTimeStatus() {
    if (childInstall) queueTimeStatusRead(false)
  }

  function queueTimeStatusRead(postUnlock) {
    timeStatusReadQueued = true
    if (postUnlock) postUnlockReadQueued = true
    timeStatusReadTimer.restart()
  }

  function startTimeStatusRead() {
    if (!timeStatusReadQueued || timeStatusProc.running) return

    timeStatusProc.postUnlockRead = postUnlockReadQueued
    timeStatusReadQueued = false
    postUnlockReadQueued = false
    timeStatusProc.launched = false
    timeStatusProc.running = true
  }

  function acceptTimeStatus(raw, postUnlockRead) {
    // A read already running when PAM completed may still contain zero from
    // before the parent grant. Finish it, but let the queued post-unlock read
    // be the first result allowed to decide the handoff.
    if (!(postUnlockStatusPending && !postUnlockRead)) {
      timeStatusRaw = String(raw || "")
      timeStatusFresh = true
      if (postUnlockRead) postUnlockStatusPending = false
      queueMathHandoff()
    }

    if (timeStatusReadQueued) timeStatusReadTimer.restart()
  }

  // With no time left, the math plugin takes over the session the moment
  // the lock screen opens it; the daemon's failsafe locks if it disappears.
  function summonMath() {
    if (!summonMathProc.running) summonMathProc.running = true
  }

  // ext-session-lock tears its Wayland surfaces down after authentication's
  // callback. Do not ask layer-shell to map Math time until both lock states
  // are clear, then give that teardown a brief settling window.
  function queueMathHandoff() {
    if (!mathSummonPending || !timeStatusFresh || sessionLock.locked || sessionLock.secure) return
    mathHandoffTimer.restart()
  }

  function completeMathHandoff() {
    if (!mathSummonPending || !timeStatusFresh || sessionLock.locked || sessionLock.secure) return

    mathSummonPending = false
    if (!childInstall || !timeGate.enabled || !timeGate.gated) return

    logEvent("math: summoned with no time left")
    summonMath()
  }

  // The daemon warns and locks at zero. After an empty-budget unlock it lets
  // an open Math time session continue, with a one-minute failsafe whenever
  // the app or shell is absent. The shell's part is to keep Math time on the
  // screen while no time is banked.
  function enforceTimeBudget() {
    if (!childInstall || !timeGate.enabled || !timeGate.gated) return
    if (locked || lockRequested || mathSummonPending) return
    if (shell && typeof shell.callIfLoaded === "function" && shell.callIfLoaded("omarchy.screen-time", "mathOpen", "") === "true") return
    logEvent("math: summoned, no time left and nothing on screen")
    summonMath()
  }

  onTimeStatusRawChanged: enforceTimeBudget()
  onChildInstallChanged: {
    refreshTimeStatus()
    enforceTimeBudget()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    mathSummonPending = false
    postUnlockStatusPending = false
    postUnlockReadQueued = false
    timeStatusReadQueued = false
    timeStatusReadTimer.stop()
    mathHandoffTimer.stop()
    resetAuthenticationState()
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()
    refreshTimeStatus()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.locked && !lockRequested) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    // Whether Math time takes over is decided by a new process started after
    // this unlock. A FileView load already in flight may have begun before the
    // parent helper credited five minutes, so it cannot certify freshness.
    mathSummonPending = childInstall
    postUnlockStatusPending = childInstall
    timeStatusFresh = !childInstall
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
    if (postUnlockStatusPending) queueTimeStatusRead(true)
  }

  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function runWake() {
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
  }

  function runBlank() {
    if (!blankProcess.running) blankProcess.running = true
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      finishUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
      root.queueMathHandoff()
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }

      root.queueMathHandoff()
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        passwordText: root.enteredPassword
        timeLabel: root.timeLabel
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
      }

    }
  }

  // status.json is root's and world-readable; the tick and every credit
  // rewrite it, so watching it is how the lock learns the budget moved.
  FileView {
    id: timeStatusView
    path: root.timeStatusPath
    watchChanges: true
    printErrors: false
    // FileView is only the change signal. Its async text can belong to an
    // earlier load, so every value comes from the serialized process below.
    onLoaded: root.refreshTimeStatus()
    onLoadFailed: root.refreshTimeStatus()
    onFileChanged: reload()
  }

  // Reads are serialized so a pre-authentication read cannot finish after the
  // post-authentication one and replace it. StdioCollector publishes at EOF.
  Timer {
    id: timeStatusReadTimer
    interval: 100
    repeat: false
    onTriggered: root.startTimeStatusRead()
  }

  Process {
    id: timeStatusProc
    property bool launched: false
    property bool postUnlockRead: false
    command: ["cat", root.timeStatusPath]
    stdout: StdioCollector { id: timeStatusOut; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: launched = true
    onExited: root.acceptTimeStatus(timeStatusOut.text, postUnlockRead)
    onRunningChanged: if (!running && !launched) root.acceptTimeStatus("", postUnlockRead)
  }

  Process {
    id: childInstallProc
    command: ["bash", "-c", "omarchy-profile-child && echo child || echo default"]
    stdout: StdioCollector { id: childInstallOut; waitForEnd: true }
    onExited: root.childInstall = String(childInstallOut.text || "").trim() === "child"
    Component.onCompleted: running = true
  }

  Process {
    id: summonMathProc
    command: ["omarchy-shell", "-q", "shell", "summon", "omarchy.screen-time", "{\"math\":true,\"forced\":true}"]
  }

  Process {
    id: notifyProc
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Timer {
    id: mathHandoffTimer
    interval: 100
    repeat: false
    onTriggered: root.completeMathHandoff()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
