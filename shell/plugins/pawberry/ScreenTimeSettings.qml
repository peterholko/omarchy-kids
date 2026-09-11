import QtQuick
import QtQuick.Controls.Basic

Rectangle {
  id: root
  property var status: null
  property bool rewardEnabled: false
  readonly property bool supported: status !== null && status !== undefined
  readonly property bool canEnable: supported && !!status.available
  readonly property bool minutesValid: minutes.acceptableInput && Number.isInteger(Number(minutes.text)) && Number(minutes.text) >= 1 && Number(minutes.text) <= 60
  readonly property bool capValid: cap.acceptableInput && Number.isInteger(Number(cap.text)) && Number(cap.text) >= 1 && Number(cap.text) <= 1440
  readonly property bool valid: !rewardEnabled || (minutesValid && capValid)
  readonly property var settings: ({enabled: rewardEnabled,
    minutes_per_problem: minutesValid ? Number(minutes.text) : Number(status && status.minutes_per_problem) || 1,
    daily_cap_minutes: capValid ? Number(cap.text) : Number(status && status.daily_cap_minutes) || 30})
  signal edited()
  function load(value) {
    value = value || {}
    rewardEnabled = !!value.enabled
    minutes.text = String(value.minutes_per_problem || 1)
    cap.text = String(value.daily_cap_minutes || 30)
  }
  function note() {
    if (!supported) return "Update the parent controls service to use screen-time rewards. Daily practice limits still work."
    if (!canEnable) return "Enable School & Screen Time for this account to link rewards, and make sure it is up to date."
    if (!rewardEnabled) return "Optional: completed problems can earn extra Free Time. Pet rewards always stay available."
    if (!status.enabled) return "Rewards will start when you save. They share Screen Time's overall daily earning cap."
    var reasons = {school_mode_active: "Rewards are paused during School Mode.", bedtime: "Rewards are paused during bedtime or a scheduled break.",
      earning_disabled: "Turn on earning in School & Screen Time to award minutes.", screen_time_paused: "Rewards are paused while Screen Time is paused or the session is locked.",
      daily_cap_reached: "Today's earning limit is reached. Pet rewards are still available."}
    return reasons[status.reason] || "Rewards share Screen Time's overall daily earning cap. School hours and bedtime still apply."
  }
  radius: 18; color: "#FFFDF9"; border.color: "#E9DDE0"
  Text { x: 24; y: 20; text: "Earn screen time"; color: "#594355"; font.pixelSize: 24; font.bold: true }
  Row {
    x: 652; y: 16; spacing: 8
    HotelButton { objectName: "screenTimeOffButton"; width: 154; height: 40; text: "Off"; selected: !root.rewardEnabled; enabled: root.supported; onClicked: { root.rewardEnabled = false; root.edited() } }
    HotelButton { objectName: "screenTimeOnButton"; width: 154; height: 40; text: "On"; selected: root.rewardEnabled; enabled: root.canEnable; onClicked: { root.rewardEnabled = true; root.edited() } }
  }
  Text { objectName: "screenTimeSettingsNote"; x: 24; y: 71; width: 964; height: 44; text: root.note(); color: "#806C7C"; font.pixelSize: 15; wrapMode: Text.WordWrap }
  Item {
    x: 24; y: 125; width: 964; height: 90; enabled: root.rewardEnabled && root.canEnable; opacity: enabled ? 1 : 0.5
    Text { text: "MINUTES PER COMPLETED PROBLEM"; color: "#977288"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1 }
    TextField {
      id: minutes; objectName: "screenTimeMinutesInput"; y: 28; width: 114; height: 44; text: "1"; selectByMouse: true
      validator: IntValidator { bottom: 1; top: 60 }
      inputMethodHints: Qt.ImhDigitsOnly
      horizontalAlignment: TextInput.AlignHCenter; color: "#594355"; font.pixelSize: 21
      Accessible.name: "Screen-time minutes per completed problem"
      background: Rectangle { radius: 10; color: "#FFFDFC"; border.color: root.minutesValid ? "#C4A8B6" : "#BA6266"; border.width: 2 }
      onTextEdited: root.edited()
    }
    Text { x: 132; y: 41; text: "minutes  (1–60)"; color: "#806C7C"; font.pixelSize: 15 }
    Text { x: 500; text: "DAILY MAXIMUM FROM PAWBERRY"; color: "#977288"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1 }
    TextField {
      id: cap; objectName: "screenTimeCapInput"; x: 500; y: 28; width: 114; height: 44; text: "30"; selectByMouse: true
      validator: IntValidator { bottom: 1; top: 1440 }
      inputMethodHints: Qt.ImhDigitsOnly
      horizontalAlignment: TextInput.AlignHCenter; color: "#594355"; font.pixelSize: 21
      Accessible.name: "Maximum daily screen-time minutes from Pawberry"
      background: Rectangle { radius: 10; color: "#FFFDFC"; border.color: root.capValid ? "#C4A8B6" : "#BA6266"; border.width: 2 }
      onTextEdited: root.edited()
    }
    Text { x: 632; y: 41; text: "minutes  (1–1,440)"; color: "#806C7C"; font.pixelSize: 15 }
  }
  Text {
    objectName: "screenTimeTotals"; x: 24; y: 234; width: 964; color: "#477B72"; font.pixelSize: 14
    text: root.canEnable ? "Today: " + (Number(root.status.earned_today_seconds) / 60).toFixed(1) + " min earned in Pawberry  ·  " + (Number(root.status.remaining_today_seconds) / 60).toFixed(1) + " min left to earn" : "Screen-time rewards are off by default."
  }
}
