import QtQuick
import QtQuick.Controls.Basic

FocusScope {
  id: root
  property var status: ({})
  property bool connected: false
  property bool managed: false
  property bool busy: false
  property bool loaded: false
  property bool dirty: false
  property string feedback: ""
  property bool failed: false
  property int retrySeconds: 0
  property bool screenTimeTab: false
  readonly property bool available: connected && managed
  readonly property bool valid: addition.valid && subtraction.valid && rewards.valid
  readonly property bool canSave: available && loaded && dirty && valid && !busy && retrySeconds === 0 && password.text.length > 0
  signal saveRequested(var limits, string password, var screenTime)
  signal closeRequested()
  signal retryRequested()
  function clear() {
    password.text = ""; feedback = ""; failed = false; loaded = false; dirty = false; screenTimeTab = false
  }
  function load(source) {
    var current = source || status
    if (!available || !current || !current.limits) return
    addition.load(current.limits.add); subtraction.load(current.limits.subtract)
    rewards.load(current.screen_time)
    loaded = true; dirty = false
  }
  function open() { clear(); load(); forceActiveFocus() }
  function edit() { dirty = true; feedback = ""; failed = false }
  function submit() {
    if (!canSave) return
    var secret = password.text
    password.text = ""; feedback = ""; failed = false
    saveRequested({add: addition.limit, subtract: subtraction.limit}, secret, rewards.supported ? rewards.settings : null)
  }
  function finish(result) {
    if (result.ok) {
      load(result); feedback = "Settings saved. Today's completed totals and earned time are kept."; failed = false
    } else {
      failed = true
      retrySeconds = Math.max(0, Math.ceil(Number(result.retry_in_seconds) || 0))
      feedback = result.error === "bad_password" ? "The parent password wasn't accepted. Please try again."
        : result.error === "password_locked_out" ? "Too many password attempts. Please wait before trying again."
        : result.error === "password_checking" ? "A parent password is already being checked. Try again shortly."
        : result.error === "invalid_limits" ? "Use a daily limit from 1 to 10,000, or choose Unlimited or Unavailable."
        : result.error === "invalid_rewards" ? "Use 1–60 minutes per problem and a daily maximum of 1–1,440 minutes."
        : result.error === "screen_time_not_managed" ? "Enable School & Screen Time for this account before turning on rewards."
        : "Couldn't confirm the save. Reconnect and check the saved limits before trying again."
      if (available && retrySeconds === 0) password.forceActiveFocus()
    }
  }
  onStatusChanged: if (visible && !dirty && !busy) load()
  onAvailableChanged: if (visible && available && !loaded) load()
  onVisibleChanged: if (!visible) password.text = ""
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) { if (!busy) closeRequested(); event.accepted = true }
  }
  Timer { interval: 1000; repeat: true; running: root.retrySeconds > 0; onTriggered: root.retrySeconds-- }

  Rectangle { anchors.fill: parent; color: "#FAF5F2" }
  Text { x: 36; y: 20; text: "Parent settings"; color: "#594355"; font.pixelSize: 30; font.bold: true }
  Text { x: 38; y: 64; text: root.status && root.status.user ? "Practice settings for " + root.status.user : "Practice settings"; color: "#927888"; font.pixelSize: 16 }
  HotelButton { objectName: "closeParentSettingsButton"; x: 832; y: 22; width: 216; height: 43; text: "Back to the hotel"; enabled: !root.busy; onClicked: root.closeRequested() }
  Row {
    x: 36; y: 98; spacing: 10
    HotelButton { objectName: "practiceSettingsTab"; width: 244; height: 40; text: "Daily practice"; selected: !root.screenTimeTab; onClicked: root.screenTimeTab = false }
    HotelButton { objectName: "screenTimeSettingsTab"; width: 244; height: 40; text: "Screen time"; selected: root.screenTimeTab; onClicked: root.screenTimeTab = true }
  }
  PracticeLimitRow {
    id: addition; objectName: "additionLimits"; x: 36; y: 154; width: 1012; visible: !root.screenTimeTab
    operation: "add"; title: "Addition"; enabled: root.available && root.loaded && !root.busy
    completed: root.status && root.status.completed ? Number(root.status.completed.add) || 0 : 0
    onEdited: root.edit()
  }
  PracticeLimitRow {
    id: subtraction; objectName: "subtractionLimits"; x: 36; y: 294; width: 1012; visible: !root.screenTimeTab
    operation: "subtract"; title: "Subtraction"; enabled: root.available && root.loaded && !root.busy
    completed: root.status && root.status.completed ? Number(root.status.completed.subtract) || 0 : 0
    onEdited: root.edit()
  }
  ScreenTimeSettings {
    id: rewards; objectName: "screenTimeSettings"; x: 36; y: 154; width: 1012; height: 268
    visible: root.screenTimeTab; status: root.status.screen_time || null
    enabled: root.available && root.loaded && !root.busy
    onEdited: root.edit()
  }
  Rectangle {
    x: 36; y: 437; width: 1012; height: 163; radius: 18; color: "#F1E4E9"
    visible: root.available
    Text { x: 22; y: 16; text: "PARENT PASSWORD"; color: "#977288"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.3 }
    TextField {
      id: password; objectName: "parentPasswordInput"
      x: 22; y: 42; width: 554; height: 48
      echoMode: TextInput.Password; selectByMouse: true
      readOnly: root.busy || root.retrySeconds > 0
      placeholderText: root.busy ? "Checking password…" : "Enter the parent password to save"
      color: "#594355"; placeholderTextColor: "#94798A"; font.pixelSize: 17
      leftPadding: 14; rightPadding: 14
      cursorVisible: activeFocus && !readOnly
      inputMethodHints: Qt.ImhHiddenText | Qt.ImhNoPredictiveText
      Accessible.name: "Parent password"
      background: Rectangle { radius: 12; color: "#FFFDFC"; border.color: root.failed ? "#BA6266" : password.activeFocus ? "#477B72" : "#C4A8B6"; border.width: 2 }
      onAccepted: root.submit()
    }
    HotelButton {
      objectName: "saveParentSettingsButton"; x: 596; y: 42; width: 394; height: 48; primary: true
      enabled: root.canSave
      text: root.busy ? "Checking password…" : root.retrySeconds > 0 ? "Try again in " + root.retrySeconds + "s" : "Save settings"
      onClicked: root.submit()
    }
    Text {
      objectName: "parentSettingsFeedback"; x: 24; y: 104; width: 964; height: 46
      text: root.busy ? "Checking the parent password and saving your changes…"
        : root.feedback || (!addition.valid || !subtraction.valid ? "Daily practice: enter a limit from 1 to 10,000." : !rewards.valid ? "Screen time: use 1–60 minutes per problem and a daily maximum of 1–1,440 minutes." : "Only completed problems count. New allowances start each day; today's progress is kept.")
      color: root.failed ? "#A35462" : root.feedback ? "#477B72" : "#806C7C"
      font.pixelSize: 14; wrapMode: Text.WordWrap
    }
  }
  Rectangle {
    x: 36; y: 437; width: 1012; height: 163; radius: 18; color: "#F1E4E9"; visible: !root.available
    Text { x: 22; y: 19; text: root.connected && !root.managed ? "Parent controls need a one-time setup" : "Connecting to parent controls"; color: "#594355"; font.pixelSize: 20; font.bold: true }
    Text { x: 22; y: 57; width: 958; text: root.connected && !root.managed ? "Set up the optional parent service to protect daily limits. Then manage them here in Pawberry." : "Your saved limits are kept. Check the connection, then try again."; color: "#806C7C"; font.pixelSize: 15; wrapMode: Text.WordWrap }
    HotelButton { objectName: "retryParentConnectionButton"; x: 22; y: 107; width: 230; height: 38; text: "Check connection"; onClicked: root.retryRequested() }
    HotelButton { objectName: "parentSetupGuideButton"; x: 266; y: 107; width: 230; height: 38; text: "Setup guide"; visible: root.connected && !root.managed; onClicked: Qt.openUrlExternally("https://github.com/peterholko/omarchy-pawberry#parent-daily-practice-limits") }
  }
}
