import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "school" as School

// One window and one parent authentication session for both sets of controls.
Item {
  id: root
  readonly property bool opened: win.visible
  property var service: null
  readonly property var school: service ? service.schoolService : null
  readonly property bool unlocked: overview.parentUnlocked
  property string notice: ""
  property int selectedTab: 0

  function show() { selectedTab = 0; win.visible = true }
  function close() {
    win.visible = false
    passwordInput.text = ""
    overview.resetPanel()
    timePage.password = ""
    timePage.pendingPatch = null
    schoolPage.password = ""
    schoolPage.pendingPatch = null
    modeProc.pendingPassword = ""
    selectedTab = 0
    notice = ""
  }
  function preparePages() {
    if (!unlocked) return
    timePage.show(overview.parentPassword)
    schoolPage.show(overview.parentPassword, null)
  }
  onUnlockedChanged: {
    if (unlocked) preparePages()
    else { timePage.password = ""; schoolPage.password = ""; selectedTab = 0 }
  }
  function changeMode(mode) {
    if (!school || !school.schoolEnabled || modeProc.running || (mode === "free" && !unlocked)) return
    modeProc.launched = false
    modeProc.pendingPassword = overview.parentPassword
    modeProc.command = [service.schoolClientPath, "--password-stdin", "mode", mode]
    notice = "Switching mode…"
    modeProc.running = true
  }
  function handleModeReply(raw) {
    if (!win.visible) return
    var result
    try { result = JSON.parse(raw) } catch (error) { result = {} }
    if (result.ok) {
      notice = result.mode === "school" ? "School Mode is on. Math practice is optional." : "Free Time is on."
    } else {
      if (result.error === "bad_password" || result.error === "password_locked_out") overview.resetPanel()
      notice = result.error === "bad_password" ? "The parent password was not accepted. Unlock the controls again."
        : result.error === "password_locked_out" ? "Too many attempts. Try unlocking again later."
        : "Could not change mode. Please try again."
    }
  }
  Process {
    id: modeProc
    property string pendingPassword: ""
    property bool launched: false
    stdinEnabled: true
    onStarted: { launched = true; write(pendingPassword + "\n"); pendingPassword = "" }
    stdout: StdioCollector { id: modeOutput; waitForEnd: true }
    onExited: { pendingPassword = ""; root.handleModeReply(modeOutput.text) }
    onRunningChanged: if (!running && !launched) { pendingPassword = ""; root.handleModeReply("") }
  }

  component SettingsTab: TabButton {
    id: tab
    implicitHeight: Style.space(38)
    contentItem: Text {
      text: tab.text
      color: tab.checked ? Color.background : Color.foreground
      opacity: tab.enabled ? 1 : 0.4
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
      color: tab.checked ? Color.accent : "transparent"
      border.width: tab.activeFocus ? 1 : 0
      border.color: Color.accent
      radius: Style.cornerRadius
    }
  }

  FloatingWindow {
    id: win
    visible: false
    title: "School & Screen Time"
    color: Color.background
    implicitWidth: 600
    implicitHeight: 740
    minimumSize: Qt.size(520, 420)
    maximumSize: Qt.size(800, 1000)
    onVisibleChanged: if (!visible && root.unlocked) root.close()

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.space(12)
      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "School & Screen Time"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          Layout.fillWidth: true
        }
        Button {
          text: "Math"; focusable: true
          onClicked: if (root.service && root.service.shell) root.service.shell.summon("omarchy.screen-time", '{"math":true}')
        }
        Button {
          text: "Apps"; focusable: true
          onClicked: if (root.service && root.service.shell) root.service.shell.summon("omarchy.screen-time", '{"menu":"root"}')
        }
        Button { text: "Close"; focusable: true; onClicked: root.close() }
      }
      RowLayout {
        Layout.fillWidth: true
        Button {
          focusable: true
          objectName: "schoolModeButton"
          text: root.school && root.school.schoolMode ? "School Mode ✓" : "School Mode"
          enabled: root.school && root.school.schoolEnabled && !modeProc.running
          Layout.fillWidth: true
          onClicked: root.changeMode("school")
        }
        Button {
          focusable: true
          objectName: "freeTimeButton"
          text: root.school && !root.school.schoolMode ? "Free Time ✓" : "Free Time"
          enabled: root.unlocked && root.school && root.school.schoolEnabled && !modeProc.running
          Layout.fillWidth: true
          onClicked: root.changeMode("free")
        }
      }
      Text {
        Layout.fillWidth: true
        text: root.notice || (root.school && root.school.schoolMode
          ? "School Mode pauses the free-time budget. No math after login or unlock."
          : "A parent password is required to switch to Free Time or change settings.")
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      RowLayout {
        visible: !root.unlocked
        Layout.fillWidth: true
        ParentPasswordField {
          id: passwordInput
          objectName: "controlsParentPassword"
          Layout.fillWidth: true
          checking: overview.authenticating
          onAccepted: { overview.tryUnlock(text); text = "" }
        }
        Button {
          focusable: true
          text: overview.authenticating ? "Checking…" : "Unlock controls"
          enabled: !overview.authenticating && passwordInput.text.length > 0
          onClicked: { overview.tryUnlock(passwordInput.text); passwordInput.text = "" }
        }
      }
      Text {
        visible: !root.unlocked && overview.parentNote !== ""
        Layout.fillWidth: true
        text: overview.parentNote
        color: overview.parentNoteColor
        wrapMode: Text.WordWrap
      }
      TabBar {
        id: tabs
        background: null
        Layout.fillWidth: true
        currentIndex: root.selectedTab
        onCurrentIndexChanged: root.selectedTab = currentIndex
        SettingsTab { text: "Today" }
        SettingsTab { text: "Time + Math"; enabled: root.unlocked && root.service && root.service.connected }
        SettingsTab { text: "School + Apps"; enabled: root.unlocked && root.school && root.school.schoolEnabled }
      }
      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: root.selectedTab
        OverviewPage {
          id: overview
          service: root.service
          opened: win.visible
          onCloseRequested: root.close()
          onSettingsRequested: root.selectedTab = 1
        }
        TimeSettingsPage {
          id: timePage
          service: root.service
          clientPath: root.service ? root.service.clientPath : ""
          enabled: root.unlocked
          onCloseRequested: root.close()
        }
        School.SchoolSettingsPage {
          id: schoolPage
          service: root.school
          clientPath: root.service ? root.service.schoolClientPath : ""
          enabled: root.unlocked
          onCloseRequested: root.close()
        }
      }
    }
    Shortcut { sequence: "Escape"; enabled: win.visible; onActivated: root.close() }
  }
}
