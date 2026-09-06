import QtQuick
import QtQuick.Controls.Basic

Button {
  id: root
  property bool primary: false
  property bool selected: false
  implicitWidth: 160
  implicitHeight: 46
  hoverEnabled: true
  font.pixelSize: 15
  font.weight: Font.DemiBold
  contentItem: Text {
    text: root.text; font: root.font
    color: root.primary || root.selected ? "#FFFFFF" : "#514460"
    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
  }
  background: Rectangle {
    radius: 13; antialiasing: true
    color: root.primary || root.selected ? (root.down ? "#635087" : root.hovered ? "#8B73AF" : "#786099") : root.hovered ? "#F0E9F5" : "#FFFDFC"
    border.color: root.activeFocus ? "#C78858" : root.primary || root.selected ? "transparent" : "#E3DCE7"
    border.width: root.activeFocus ? 3 : 1
  }
}
