import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "SchoolSchedule.js" as Schedule

// The School Mode schedule editor. It opens only after the parent password
// has been checked in the panel, and saves only the school module's periods.
Item {
  id: root

  property var service: null
  property string clientPath: ""
  property string password: ""
  property string note: ""
  property color noteColor: Color.foreground
  property var localPeriods: []
  property var pendingPatch: null
  readonly property int totalPeriodLimit: 8
  readonly property var dayKeys: Schedule.DAYS
  readonly property var dayLabels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  readonly property string iconClose: "\uf00d"

  readonly property bool lightTheme: {
    var bg = Color.background
    return (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) > 0.5
  }
  readonly property color okColor: lightTheme ? "#3C7C4E" : "#5FA46B"
  readonly property color errColor: lightTheme ? "#B03434" : "#E06C6C"

  function fadeText(amount) {
    var foreground = Color.foreground
    var background = Color.background
    return Qt.rgba(foreground.r + (background.r - foreground.r) * amount,
                   foreground.g + (background.g - foreground.g) * amount,
                   foreground.b + (background.b - foreground.b) * amount, 1)
  }

  function show(passwordValue) {
    root.password = String(passwordValue || "")
    root.note = ""
    root.localPeriods = Schedule.schoolPeriods(root.service ? root.service.blockedPeriods : [])
    win.visible = true
  }

  function close() {
    win.visible = false
    root.password = ""
    root.pendingPatch = null
  }

  function nonSchoolCount() {
    var source = root.service && root.service.blockedPeriods ? root.service.blockedPeriods : []
    return source.filter(function(period) { return !period || period.mode !== "free" }).length
  }

  function canAddPeriod() {
    return root.nonSchoolCount() + root.localPeriods.length < root.totalPeriodLimit
  }

  function writePeriods(schools) {
    root.localPeriods = Schedule.clonePeriods(schools)
    var allPeriods = Schedule.merge(root.service ? root.service.blockedPeriods : [], root.localPeriods)
    root.patch({ "blocked_periods": allPeriods })
  }

  function setPeriod(index, key, value) {
    var periods = Schedule.clonePeriods(root.localPeriods)
    if (index < 0 || index >= periods.length || periods[index][key] === value) return
    periods[index][key] = value
    root.writePeriods(periods)
  }

  function addPeriod() {
    if (!root.canAddPeriod()) return
    var periods = Schedule.clonePeriods(root.localPeriods)
    periods.push({
      label: "School",
      enabled: true,
      start: "08:30",
      end: "15:00",
      days: ["mon", "tue", "wed", "thu", "fri"],
      mode: "free"
    })
    root.writePeriods(periods)
  }

  function removePeriod(index) {
    var periods = Schedule.clonePeriods(root.localPeriods)
    if (index < 0 || index >= periods.length) return
    periods.splice(index, 1)
    root.writePeriods(periods)
  }

  function togglePeriodDay(index, day) {
    root.writePeriods(Schedule.toggleDay(root.localPeriods, index, day))
  }

  function saveTime(index, key, value, field) {
    var text = String(value || "").trim()
    if (Schedule.validTime(text)) {
      root.setPeriod(index, key, text)
      return
    }
    field.text = String(root.localPeriods[index][key] || "")
    root.note = "Use a 24-hour time such as 08:30."
    root.noteColor = root.errColor
  }

  function patch(obj) {
    // Day buttons are easy to click faster than a process can finish. Keep
    // the newest complete array queued so no visible edit is silently lost.
    root.pendingPatch = obj
    root.sendPendingPatch()
  }

  function sendPendingPatch() {
    if (patchProc.running || root.pendingPatch === null) return
    var next = root.pendingPatch
    root.pendingPatch = null
    patchProc.launched = false
    patchProc.command = [root.clientPath, "--password-stdin", "config", "patch", JSON.stringify(next)]
    patchProc.running = true
  }

  Process {
    id: patchProc
    property bool launched: false
    stdinEnabled: true
    onStarted: { launched = true; write(root.password + "\n") }
    stdout: StdioCollector {
      onStreamFinished: {
        var payload
        try { payload = JSON.parse(text) } catch (error) { payload = null }
        if (payload && payload.ok === true) {
          root.note = "Saved."
          root.noteColor = root.okColor
        } else if (payload && payload.error === "password_locked_out") {
          root.note = "Too many tries. Close this window and unlock it again later."
          root.noteColor = root.errColor
        } else if (payload && payload.error === "bad_password") {
          root.note = "The parent password is no longer accepted. Close this window and unlock it again."
          root.noteColor = root.errColor
        } else {
          root.note = "Could not save the school hours."
          root.noteColor = root.errColor
        }
      }
    }
    onRunningChanged: if (!running) {
      if (!launched) {
        root.note = "Could not save the school hours."
        root.noteColor = root.errColor
      }
      launched = false
      Qt.callLater(root.sendPendingPatch)
    }
  }

  FloatingWindow {
    id: win
    visible: false
    title: "School hours"
    color: Color.background
    implicitWidth: 520
    implicitHeight: 660
    minimumSize: Qt.size(520, 420)
    maximumSize: Qt.size(520, 760)

    FocusScope {
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        anchors.margins: Style.space(20)
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          id: content
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          PanelSectionHeader {
            text: "SCHOOL HOURS"
            foreground: Color.foreground
          }

          Text {
            textFormat: Text.PlainText
            text: "At these times the laptop enters School Mode automatically. Only a parent can return it to Free Time."
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.fadeText(0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { width: parent.width }

          Text {
            textFormat: Text.PlainText
            visible: root.localPeriods.length === 0
            text: "No school hours yet. Add a schedule to turn School Mode on automatically."
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.fadeText(0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.localPeriods

            delegate: Column {
              id: periodRow
              required property var modelData
              required property int index
              width: content.width
              spacing: Style.space(8)

              Row {
                id: periodTop
                width: parent.width
                spacing: Style.space(8)

                ToggleSwitch {
                  id: periodToggle
                  anchors.verticalCenter: parent.verticalCenter
                  checked: periodRow.modelData.enabled === true
                  onToggled: root.setPeriod(periodRow.index, "enabled", !periodRow.modelData.enabled)
                }

                TextField {
                  width: periodTop.width - periodToggle.width - periodRemove.width - periodTop.spacing * 2
                  text: String(periodRow.modelData.label || "School")
                  placeholderText: "School"
                  activeFocusOnTab: true
                  onEditingFinished: root.setPeriod(periodRow.index, "label", text.trim() || "School")
                }

                PanelActionButton {
                  id: periodRemove
                  iconText: root.iconClose
                  tooltipText: "Remove these school hours"
                  foreground: Color.foreground
                  hoverColor: root.errColor
                  size: Style.space(22)
                  focusable: true
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: root.removePeriod(periodRow.index)
                }
              }

              Row {
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: "from"
                  color: root.fadeText(0.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }
                TextField {
                  id: startField
                  width: Style.space(64)
                  text: String(periodRow.modelData.start || "")
                  activeFocusOnTab: true
                  onEditingFinished: root.saveTime(periodRow.index, "start", text, startField)
                }
                Text {
                  textFormat: Text.PlainText
                  text: "until"
                  color: root.fadeText(0.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }
                TextField {
                  id: endField
                  width: Style.space(64)
                  text: String(periodRow.modelData.end || "")
                  activeFocusOnTab: true
                  onEditingFinished: root.saveTime(periodRow.index, "end", text, endField)
                }
              }

              Row {
                spacing: Style.space(4)
                Repeater {
                  model: root.dayKeys.length
                  delegate: Button {
                    text: root.dayLabels[index]
                    bordered: true
                    focusable: true
                    selected: (periodRow.modelData.days || []).indexOf(root.dayKeys[index]) >= 0
                    onClicked: root.togglePeriodDay(periodRow.index, root.dayKeys[index])
                  }
                }
              }

              PanelSeparator {
                width: parent.width
                visible: periodRow.index < root.localPeriods.length - 1
              }
            }
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: "Add school time"
              focusable: true
              enabled: root.canAddPeriod()
              onClicked: root.addPeriod()
            }

            Text {
              textFormat: Text.PlainText
              visible: !root.canAddPeriod()
              text: "The eight-period Screen Time limit is full."
              color: root.fadeText(0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSeparator { width: parent.width }

          Row {
            width: parent.width

            Text {
              textFormat: Text.PlainText
              text: root.note !== "" ? root.note : "Changes apply immediately."
              color: root.note !== "" ? root.noteColor : root.fadeText(0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              width: parent.width - closeButton.width
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              id: closeButton
              text: "Close"
              focusable: true
              onClicked: root.close()
            }
          }
        }
      }
    }
  }
}
