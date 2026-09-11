import QtQuick
import QtQuick.Controls.Basic

Rectangle {
  id: root
  property string operation: "add"
  property string title: "Addition"
  property int completed: 0
  property string choice: "unlimited"
  readonly property bool valid: choice !== "daily" || (amount.acceptableInput && Number.isInteger(Number(amount.text)) && Number(amount.text) >= 1 && Number(amount.text) <= 10000)
  readonly property var limit: choice === "unlimited" ? null : choice === "off" ? 0 : Number(amount.text)
  signal edited()
  implicitHeight: 128
  radius: 18; color: "#FFFDF9"; border.color: "#E9DDE0"
  function load(value) {
    choice = value === null || value === undefined ? "unlimited" : value === 0 ? "off" : "daily"
    amount.text = value > 0 ? String(value) : "5"
  }
  Rectangle {
    x: 22; y: 27; width: 48; height: 48; radius: 16; color: "#F1E4E9"
    Text { anchors.centerIn: parent; text: root.operation === "add" ? "+" : "−"; color: "#A95F79"; font.pixelSize: 33 }
  }
  Text { x: 86; y: 27; text: root.title; color: "#594355"; font.pixelSize: 23; font.bold: true }
  Text { x: 86; y: 64; text: root.completed + " completed today"; color: "#94798A"; font.pixelSize: 14 }
  Row {
    x: 440; y: 19; spacing: 8
    Repeater {
      model: [{key: "unlimited", label: "Unlimited"}, {key: "daily", label: "Daily limit"}, {key: "off", label: "Unavailable"}]
      delegate: HotelButton {
        required property var modelData
        objectName: root.operation + "-limit-" + modelData.key
        width: 157; height: 40; font.pixelSize: 14
        text: modelData.label; selected: root.choice === modelData.key
        onClicked: { root.choice = modelData.key; root.edited() }
      }
    }
  }
  Row {
    x: 440; y: 73; spacing: 8; visible: root.choice === "daily"
    HotelButton {
      objectName: root.operation + "-limit-decrease"
      width: 40; height: 36; text: "−"; enabled: root.valid && Number(amount.text) > 1
      Accessible.name: "Decrease " + root.title.toLowerCase() + " daily limit"
      onClicked: { amount.text = String(Number(amount.text) - 1); root.edited() }
    }
    TextField {
      id: amount; objectName: root.operation + "-limit-count"
      width: 80; height: 36; text: "5"; selectByMouse: true
      validator: IntValidator { bottom: 1; top: 10000 }
      inputMethodHints: Qt.ImhDigitsOnly
      horizontalAlignment: TextInput.AlignHCenter; color: "#594355"; font.pixelSize: 18
      Accessible.name: root.title + " completed problems per day"
      background: Rectangle { radius: 9; color: "#FFFDFC"; border.color: amount.activeFocus ? "#477B72" : root.valid ? "#C4A8B6" : "#BA6266"; border.width: 2 }
      onTextEdited: root.edited()
    }
    HotelButton {
      objectName: root.operation + "-limit-increase"
      width: 40; height: 36; text: "+"; enabled: root.valid && Number(amount.text) < 10000
      Accessible.name: "Increase " + root.title.toLowerCase() + " daily limit"
      onClicked: { amount.text = String(Number(amount.text) + 1); root.edited() }
    }
    Text { y: 9; text: "completed problems per day"; color: "#806C7C"; font.pixelSize: 14 }
  }
  Text {
    x: 440; y: 82; width: 480; visible: root.choice !== "daily"
    text: root.choice === "off" ? "This operation stays unavailable until you change it." : "No daily limit for this operation."
    color: "#806C7C"; font.pixelSize: 14
  }
}
