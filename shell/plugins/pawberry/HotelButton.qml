import QtQuick
import QtQuick.Controls.Basic

Button {
  id: root
  property bool primary: false
  property bool selected: false
  implicitWidth: 144
  implicitHeight: 46
  hoverEnabled: true
  font.pixelSize: 15
  font.weight: Font.DemiBold
  contentItem: Text {
    text: root.text; font: root.font
    color: root.primary || root.selected ? "#FFFFFF" : "#614957"
    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
  }
  background: Rectangle {
    radius: 14; antialiasing: true
    color: root.primary || root.selected ? (root.down ? "#95566D" : root.hovered ? "#BF7B92" : "#A95F79") : root.hovered ? "#F5E8EC" : "#FFFDFC"
    border.color: root.activeFocus ? "#477B72" : root.primary || root.selected ? "transparent" : "#E3D5DA"
    border.width: root.activeFocus ? 3 : 1
    opacity: root.enabled ? 1 : 0.5
  }
}
