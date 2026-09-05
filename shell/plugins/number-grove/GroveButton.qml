import QtQuick
import QtQuick.Controls.Basic

Button {
  id: root
  property bool primary: false
  property bool selected: false
  implicitHeight: 48
  implicitWidth: 180
  hoverEnabled: true
  font.pixelSize: 16
  font.weight: Font.DemiBold
  contentItem: Text {
    text: root.text
    font: root.font
    color: root.primary || root.selected ? "#FFFDF5" : "#254A37"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
  background: Rectangle {
    radius: 12
    antialiasing: true
    color: root.primary || root.selected ? (root.down ? "#123F30" : root.hovered ? "#357553" : "#236044")
      : root.hovered ? "#E2E8D4" : "#FDFBF4"
    border.color: root.activeFocus ? "#C8862A" : root.primary || root.selected ? "transparent" : "#D1D9C5"
    border.width: root.activeFocus ? 3 : 1
    opacity: root.enabled ? 1 : 0.45
  }
}
