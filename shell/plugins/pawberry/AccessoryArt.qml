import QtQuick

Item {
  id: root
  property var accessory: null
  readonly property string shape: accessory ? accessory.shape : ""
  readonly property color tint: accessory ? accessory.color : "transparent"
  implicitWidth: 80; implicitHeight: 60
  Accessible.role: Accessible.Graphic
  Accessible.name: accessory ? accessory.name : ""
  Item {
    width: 80; height: 60; scale: Math.min(root.width / 80, root.height / 60)
    anchors.centerIn: parent
    Item {
      anchors.fill: parent; visible: root.shape === "bow"
      Rectangle { x: 8; y: 15; width: 31; height: 31; radius: 10; rotation: 25; color: root.tint; border.color: Qt.darker(root.tint, 1.2) }
      Rectangle { x: 41; y: 15; width: 31; height: 31; radius: 10; rotation: -25; color: root.tint; border.color: Qt.darker(root.tint, 1.2) }
      Rectangle { x: 33; y: 19; width: 14; height: 23; radius: 6; color: Qt.lighter(root.tint, 1.15); border.color: Qt.darker(root.tint, 1.2) }
    }
    Item {
      anchors.fill: parent; visible: root.shape === "hat"
      Rectangle { x: 20; y: 11; width: 40; height: 31; radius: 15; color: root.tint; border.color: Qt.darker(root.tint, 1.2) }
      Rectangle { x: 20; y: 31; width: 40; height: 8; color: "#FFF4E1" }
      Rectangle { x: 5; y: 38; width: 70; height: 12; radius: 6; color: root.tint; border.color: Qt.darker(root.tint, 1.2) }
    }
    Item {
      anchors.fill: parent; visible: root.shape === "crown"
      Repeater {
        model: 3
        delegate: Rectangle {
          required property int index
          x: 14 + index * 19; y: index === 1 ? 8 : 16; width: 14; height: 27; radius: 3; rotation: (index - 1) * 17; color: root.tint
          Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: -3; width: 8; height: 8; radius: 4; color: "#FFF3CB"; border.color: Qt.darker(root.tint, 1.2) }
        }
      }
      Rectangle { x: 11; y: 35; width: 58; height: 13; radius: 4; color: root.tint; border.color: Qt.darker(root.tint, 1.2) }
      Rectangle { x: 35; y: 36; width: 10; height: 10; radius: 3; rotation: 45; color: "#D57E9B" }
    }
    Item {
      anchors.fill: parent; visible: root.shape === "flower"
      Repeater {
        model: 6
        delegate: Rectangle {
          required property int index
          x: 30 + Math.cos(index * Math.PI / 3) * 17; y: 20 + Math.sin(index * Math.PI / 3) * 17
          width: 20; height: 20; radius: 10; color: root.tint; border.color: Qt.darker(root.tint, 1.12)
        }
      }
      Rectangle { x: 31; y: 21; width: 18; height: 18; radius: 9; color: "#E5B761" }
    }
    Text { anchors.centerIn: parent; visible: root.shape === "star"; text: "★"; font.pixelSize: 58; color: root.tint; style: Text.Outline; styleColor: Qt.darker(root.tint, 1.2) }
    Item {
      anchors.fill: parent; visible: root.shape === "scarf"
      Rectangle { x: 43; y: 25; width: 18; height: 31; radius: 5; rotation: -12; color: root.tint; border.color: Qt.darker(root.tint, 1.2) }
      Rectangle { x: 8; y: 13; width: 64; height: 20; radius: 10; color: root.tint; border.color: Qt.darker(root.tint, 1.2) }
      Rectangle { x: 17; y: 18; width: 40; height: 4; radius: 2; color: Qt.lighter(root.tint, 1.2) }
    }
  }
}
