import QtQuick

Item {
  id: root
  property int petIndex: 0
  property real progress: 0
  property int celebration: 0
  property bool reducedMotion: false
  readonly property var names: ["Peaches", "Biscuit", "Bluebell"]
  readonly property var roomColors: ["#F5E3DA", "#DFECF0", "#EAE0F1"]
  onCelebrationChanged: if (!reducedMotion && visible) bounce.restart()
  Rectangle { anchors.fill: parent; radius: 24; color: root.roomColors[root.petIndex] }
  Rectangle { x: 20; y: 56; width: parent.width - 40; height: parent.height - 80; radius: 70; color: "#FFF9F4"; opacity: 0.65 }
  Text { x: 22; y: 18; text: root.names[root.petIndex] + "’s room"; color: "#654E5E"; font.pixelSize: 19; font.bold: true }
  Text { anchors.right: parent.right; anchors.rightMargin: 24; y: 17; text: "♥"; color: "#B96785"; font.pixelSize: 24; opacity: 0.3 + root.progress * 0.7 }
  Rectangle { x: parent.width * 0.15; y: parent.height - 64; width: parent.width * 0.7; height: 35; radius: 17; color: "#DFA4B5"; opacity: 0.2 + root.progress * 0.8 }
  Rectangle { x: parent.width * 0.22; y: parent.height - 64; width: parent.width * 0.56; height: 23; radius: 12; color: "#FFE9D4"; opacity: root.progress }
  Image {
    id: pet
    objectName: "petPortrait"
    anchors.horizontalCenter: parent.horizontalCenter
    y: 48; width: parent.width * 0.72; height: parent.height - 93
    source: "assets/pets.png"
    sourceClipRect: Qt.rect(root.petIndex * 512 + 8, 0, 496, 1024)
    fillMode: Image.PreserveAspectFit
    smooth: true; mipmap: true
  }
  Rectangle {
    x: 28; y: parent.height - 69; width: 40; height: 24; radius: 9
    color: "#81AEA0"; opacity: Math.min(1, Math.max(0, (root.progress - 0.2) * 4))
    Rectangle { x: 4; y: 0; width: 32; height: 8; radius: 4; color: "#628779" }
    Text { anchors.centerIn: parent; text: "♥"; color: "#F6F9E8"; font.pixelSize: 14 }
  }
  Rectangle {
    x: parent.width - 59; y: parent.height - 76; width: 32; height: 32; radius: 16
    color: "#EAB97D"; opacity: Math.min(1, Math.max(0, (root.progress - 0.5) * 4))
    Rectangle { anchors.centerIn: parent; width: 8; height: parent.height; radius: 4; rotation: 24; color: "#FFF0D4" }
  }
  Text {
    anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 27
    text: root.progress >= 1 ? "All settled in. Thank you!" : "A little cozier with every checked step."
    color: "#6C5965"; font.pixelSize: 12
  }
  SequentialAnimation {
    id: bounce
    NumberAnimation { target: pet; property: "scale"; to: 1.04; duration: 120; easing.type: Easing.OutQuad }
    NumberAnimation { target: pet; property: "scale"; to: 1; duration: 220; easing.type: Easing.InOutQuad }
  }
  onReducedMotionChanged: if (reducedMotion) { bounce.stop(); pet.scale = 1 }
}
