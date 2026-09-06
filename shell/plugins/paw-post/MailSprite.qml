import QtQuick

// A code-native envelope overlays the illustrated world and flies on delivery.
Item {
  id: root
  property color ink: "#BA7B87"
  implicitWidth: 64; implicitHeight: 48
  Rectangle {
    anchors.fill: parent; radius: 9; color: "#FFFCF4"
    border.color: root.ink; border.width: 2; antialiasing: true
  }
  Rectangle { x: parent.width * 0.08; y: parent.height * 0.15; width: parent.width * 0.48; height: 2; rotation: 29; transformOrigin: Item.Left; color: root.ink; antialiasing: true }
  Rectangle { x: parent.width * 0.5; y: parent.height * 0.46; width: parent.width * 0.48; height: 2; rotation: -29; transformOrigin: Item.Left; color: root.ink; antialiasing: true }
  Text { anchors.centerIn: parent; anchors.verticalCenterOffset: 4; text: "♥"; color: "#D48495"; font.pixelSize: root.height * 0.39 }
}
