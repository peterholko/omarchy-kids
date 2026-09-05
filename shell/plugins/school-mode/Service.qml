import QtQuick
import Quickshell
import Quickshell.Io
import "Allowlist.js" as Allowlist
import "ModeState.js" as ModeState
import "NotificationState.js" as NotificationState
import "ShellIntegration.js" as ShellIntegration

// School mode and free time on a child install (plans/kids-screen-time.md),
// after elgevan's omarchy-kids-menu. The screen-time daemon owns the mode:
// school hours are school mode, the kid may choose it, and the parent may
// override it; status.json says which. This service makes the desktop
// follow: the menu shows only the school apps, their shortcuts alone stay
// bound, notifications go quiet, the free-time windows are parked, and the
// browser opens in a clean school profile. Everything it changes is reversed
// when free time returns, and nothing here runs on a "Me" install.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool childInstall: false
  property bool childChecked: false
  property bool statusLoaded: false
  property bool schoolEnabled: false
  property string mode: "free"
  property string modeReason: ""
  property string schoolUntil: ""
  property string schoolLabel: ""
  property var allowedDesktopIds: []
  property var blockedPeriods: []
  property bool connected: false
  readonly property bool schoolMode: childInstall && schoolEnabled && mode === "school"

  property bool directoryReady: false
  property bool notificationStateLoaded: false
  property bool notificationStateManaged: false
  property bool notificationRestoreDnd: false
  property bool notificationApplied: false
  property int notificationSetupAttempts: 0
  property int hiddenWindowCount: 0
  property bool windowSessionBusy: false
  property string windowSessionError: ""
  property bool windowSessionDesired: false
  property int windowGuardAttemptsRemaining: 0
  property var stockMenuRestore: null
  property bool shortcutPolicyApplied: false
  property bool shortcutPolicyBusy: false
  property string shortcutPolicyError: ""
  property bool shortcutPolicyDesired: false
  property bool shortcutPolicyRunning: false

  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string statusPath: "/var/lib/omarchy/parent/" + userName + "/school-mode/status.json"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || homeDir + "/.local/state") + "/omarchy-school-mode"
  readonly property string notificationStatePath: stateDir + "/notifications.json"
  readonly property string pluginDir: omarchyPath + "/shell/plugins/school-mode"
  readonly property string windowSessionTool: pluginDir + "/window-session"
  readonly property string shortcutPolicyTool: pluginDir + "/shortcut-policy"
  readonly property string pluginId: "omarchy.school-mode"
  readonly property string modePillId: pluginId + ".mode"
  readonly property string modePillPath: pluginDir + "/ModePill.qml"
  readonly property var notificationService: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("omarchy.notifications") : null

  signal allowlistChanged()

  function sameIds(left, right) {
    var a = Allowlist.normalizeIds(left)
    var b = Allowlist.normalizeIds(right)
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }

  function isAllowed(desktopId) {
    return Allowlist.contains(root.allowedDesktopIds, desktopId)
  }

  function loadStatus(rawText) {
    var status = ModeState.parseStatus(rawText)
    if (!status.valid) { root.connected = false; return }
    root.connected = true
    root.blockedPeriods = status.blockedPeriods
    var ids = Allowlist.normalizeIds(status.schoolApps)
    schoolEnabled = status.enabled
    mode = status.mode
    modeReason = status.reason
    schoolUntil = status.schoolUntil
    schoolLabel = status.schoolLabel
    if (!root.sameIds(root.allowedDesktopIds, ids)) {
      root.allowedDesktopIds = ids
      root.allowlistChanged()
    }
    statusLoaded = true
    root.applyMode()
  }

  onSchoolModeChanged: root.applyMode()

  function removalReady() {
    return !root.schoolEnabled && !root.notificationApplied && !root.shortcutPolicyApplied
      && !root.shortcutPolicyBusy && !root.windowSessionBusy && root.hiddenWindowCount === 0 ? "ready" : "restoring"
  }

  function applyMode() {
    if (!root.childChecked || !root.statusLoaded) return
    root.scheduleNotificationSetup()
    root.scheduleWindowSessionSync()
    root.scheduleShellIntegration()
    root.scheduleShortcutPolicySync()
  }

  // --- notifications: quiet in school mode, back as they were after -----

  function loadNotificationState(rawText) {
    var state = NotificationState.parseState(rawText)
    root.notificationStateManaged = state.managed
    root.notificationRestoreDnd = state.restoreDnd
    root.notificationStateLoaded = true
    root.scheduleNotificationSetup()
  }

  function applyNotificationPolicy() {
    var notifications = root.notificationService
    if (!root.schoolMode || !root.directoryReady || !root.notificationStateLoaded || !notifications
        || notifications.settingsLoaded !== true)
      return false
    if (!root.notificationStateManaged) {
      root.notificationRestoreDnd = notifications.doNotDisturb === true
      root.notificationStateManaged = true
      notificationStateFile.setText(NotificationState.stateText(true, root.notificationRestoreDnd))
    }
    notifications.setDoNotDisturb(true)
    root.notificationApplied = true
    return true
  }

  function releaseNotificationPolicy() {
    if (!root.notificationStateLoaded || !root.notificationStateManaged) {
      root.notificationApplied = false
      return true
    }
    var notifications = root.notificationService
    if (!notifications || notifications.settingsLoaded !== true) return false
    notificationStateFile.setText(NotificationState.stateText(false, false))
    root.notificationStateManaged = false
    root.notificationApplied = false
    notifications.setDoNotDisturb(root.notificationRestoreDnd)
    return true
  }

  function scheduleNotificationSetup() {
    root.notificationSetupAttempts = 0
    notificationSetup.restart()
  }

  function syncModeEffects() {
    if (!root.childChecked || !root.statusLoaded || !root.notificationStateLoaded || !root.directoryReady)
      return false
    return root.schoolMode ? root.applyNotificationPolicy() : root.releaseNotificationPolicy()
  }

  // --- windows: parked for school, back for free time -------------------

  function parseToolOutput(rawText) {
    try {
      var parsed = JSON.parse(String(rawText || "").trim())
      return parsed && typeof parsed === "object" ? parsed : null
    } catch (error) {
      return null
    }
  }

  function scheduleWindowSessionSync() {
    if (!root.childChecked || !root.statusLoaded) return
    root.windowSessionDesired = root.schoolMode
    windowSessionSync.restart()
  }

  function syncWindowSession() {
    if (!root.childInstall || windowSessionEnter.running || windowSessionExit.running) return
    root.windowSessionBusy = true
    root.windowSessionError = ""
    if (root.windowSessionDesired) windowSessionEnter.running = true
    else windowSessionExit.running = true
  }

  function finishWindowSession(action, exitCode, output) {
    var result = root.parseToolOutput(output)
    root.windowSessionBusy = false
    if (exitCode !== 0 || !result) {
      root.windowSessionError = action === "enter" ? "Could not park the open windows" : "Could not bring the windows back"
    } else if (action === "enter") {
      root.hiddenWindowCount = Math.max(0, Number(result.hidden || 0))
    } else {
      root.hiddenWindowCount = 0
    }
    if ((action === "enter") !== root.windowSessionDesired) windowSessionSync.restart()
  }

  function guardAppLaunch() {
    if (!root.schoolMode) return
    root.windowGuardAttemptsRemaining = 2
    windowGuardTimer.interval = 650
    windowGuardTimer.restart()
  }

  // --- shortcuts: the school layer on, the real bindings back ----------

  function scheduleShortcutPolicySync() {
    if (!root.childChecked || !root.statusLoaded) return
    root.shortcutPolicyDesired = root.schoolMode
    shortcutPolicySync.restart()
  }

  function syncShortcutPolicy() {
    if (!root.childInstall || root.shortcutPolicyBusy) return
    root.shortcutPolicyBusy = true
    root.shortcutPolicyError = ""
    root.shortcutPolicyRunning = root.shortcutPolicyDesired
    if (root.shortcutPolicyRunning) shortcutPolicyEnter.running = true
    else shortcutPolicyExit.running = true
  }

  function finishShortcutPolicy(action, exitCode, output) {
    var result = root.parseToolOutput(output)
    root.shortcutPolicyBusy = false
    if (exitCode !== 0 || !result) {
      root.shortcutPolicyError = action === "enter" ? "Could not filter the shortcuts" : "Could not restore the shortcuts"
      root.shortcutPolicyApplied = action === "exit"
    } else {
      root.shortcutPolicyApplied = action === "enter" && result.applied === true
      if (result.error) root.shortcutPolicyError = String(result.error)
    }
    if (root.shortcutPolicyRunning !== root.shortcutPolicyDesired) shortcutPolicySync.restart()
  }

  // --- the bar: this plugin's button in the menu's slot, the pill on the right ---

  function scheduleShellIntegration() {
    shellIntegrationSetup.restart()
  }

  function syncShellIntegration() {
    if (!root.childInstall || !root.statusLoaded || !root.shell
        || typeof root.shell.mutateShellConfig !== "function")
      return
    // The stock menu is off while school mode is on: its IPC route cannot be
    // redirected, so the shortcuts and the button go to this plugin instead.
    if (root.schoolMode && typeof root.shell.hide === "function")
      root.shell.hide(ShellIntegration.STOCK_MENU_ID)
    root.shell.mutateShellConfig(function(config) {
      var result = ShellIntegration.activate(config, root.pluginId, root.modePillId, root.modePillPath, root.schoolMode)
      if (result && result.restore) root.stockMenuRestore = result.restore
    })
  }

  function releaseShellIntegration() {
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return
    root.shell.mutateShellConfig(function(config) {
      ShellIntegration.deactivate(config, root.modePillId, root.stockMenuRestore)
    })
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadStatus(text())
    onLoadFailed: root.loadStatus("")
    onFileChanged: reload()
  }

  FileView {
    id: notificationStateFile
    path: root.notificationStatePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadNotificationState(text())
    onLoadFailed: root.loadNotificationState("")
    onFileChanged: reload()
  }

  Process {
    id: childInstallProc
    command: ["bash", "-c", "omarchy-profile-child && echo child || echo default"]
    stdout: StdioCollector { id: childInstallOut; waitForEnd: true }
    onExited: {
      root.childInstall = String(childInstallOut.text).trim() === "child"
      root.childChecked = true
      root.applyMode()
    }
  }

  Process {
    id: ensureDirectory
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      root.directoryReady = exitCode === 0
      if (root.directoryReady) root.scheduleNotificationSetup()
    }
  }

  Process {
    id: windowSessionEnter
    command: [root.windowSessionTool, "enter"]
    stdout: StdioCollector { id: windowSessionEnterOutput; waitForEnd: true }
    onExited: function(exitCode) { root.finishWindowSession("enter", exitCode, windowSessionEnterOutput.text) }
  }

  Process {
    id: windowSessionExit
    command: [root.windowSessionTool, "exit"]
    stdout: StdioCollector { id: windowSessionExitOutput; waitForEnd: true }
    onExited: function(exitCode) { root.finishWindowSession("exit", exitCode, windowSessionExitOutput.text) }
  }

  Process {
    id: windowSessionGuard
    command: [root.windowSessionTool, "guard"]
    stdout: StdioCollector { id: windowSessionGuardOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var result = root.parseToolOutput(windowSessionGuardOutput.text)
      if (exitCode === 0 && result && Number(result.blocked || 0) > 0)
        Quickshell.execDetached(["omarchy-notification-send", "That is a free-time window; it waits until free time."])
      root.windowGuardAttemptsRemaining--
      if (root.windowGuardAttemptsRemaining > 0 && root.schoolMode) {
        windowGuardTimer.interval = 1200
        windowGuardTimer.restart()
      }
    }
  }

  Process {
    id: shortcutPolicyEnter
    command: [root.shortcutPolicyTool, "enter"]
    stdout: StdioCollector { id: shortcutPolicyEnterOutput; waitForEnd: true }
    onExited: function(exitCode) { root.finishShortcutPolicy("enter", exitCode, shortcutPolicyEnterOutput.text) }
  }

  Process {
    id: shortcutPolicyExit
    command: [root.shortcutPolicyTool, "exit"]
    stdout: StdioCollector { id: shortcutPolicyExitOutput; waitForEnd: true }
    onExited: function(exitCode) { root.finishShortcutPolicy("exit", exitCode, shortcutPolicyExitOutput.text) }
  }

  Timer {
    id: notificationSetup
    interval: 100
    repeat: true
    onTriggered: {
      root.notificationSetupAttempts++
      if (root.syncModeEffects()) stop()
      else if (root.notificationSetupAttempts >= 100) stop()
    }
  }

  Timer { id: shellIntegrationSetup; interval: 0; onTriggered: root.syncShellIntegration() }
  Timer { id: windowSessionSync; interval: 250; onTriggered: root.syncWindowSession() }
  Timer { id: shortcutPolicySync; interval: 100; onTriggered: root.syncShortcutPolicy() }
  Timer {
    id: windowGuardTimer
    interval: 650
    onTriggered: { if (!windowSessionGuard.running) windowSessionGuard.running = true }
  }

  onShellChanged: root.applyMode()
  onNotificationServiceChanged: root.scheduleNotificationSetup()

  Component.onCompleted: {
    childInstallProc.running = true
    ensureDirectory.running = true
  }

  Component.onDestruction: {
    if (root.childInstall && root.pluginRegistry && !root.pluginRegistry.isEnabled(root.pluginId)) {
      root.releaseNotificationPolicy()
      root.releaseShellIntegration()
      Quickshell.execDetached([root.windowSessionTool, "exit"])
      Quickshell.execDetached([root.shortcutPolicyTool, "exit"])
    }
  }
}
