import QtQuick
import "PetCatalog.js" as Catalog

Item {
  id: root
  property string petId: "peaches"
  property string accessoryId: ""
  property int roomNumber: 1
  readonly property var guest: Catalog.pet(petId)
  // Preparing every comfort still requires the final answer to welcome the pet.
  property real progress: 0
  property bool welcomed: false
  property bool reducedMotion: false
  property bool initialized: false
  property real revealProgress: welcomed ? 1 : 0
  property real confettiProgress: 1
  readonly property int comforts: Math.min(3, Math.floor(Math.max(0, progress) * 3))
  readonly property bool revealing: reveal.running
  readonly property var roomColors: ["#F5E3DA", "#DFECF0", "#EAE0F1"]

  function settle() {
    reveal.stop()
    revealProgress = welcomed ? 1 : 0
    confettiProgress = 1
    pet.scale = 1
  }
  Component.onCompleted: { settle(); initialized = true }
  onWelcomedChanged: if (initialized) {
    settle()
    if (welcomed && visible && !reducedMotion) reveal.restart()
  }
  onPetIdChanged: if (initialized) settle()
  onVisibleChanged: if (initialized && !visible) settle()
  onReducedMotionChanged: if (initialized && reducedMotion) settle()

  Rectangle { anchors.fill: parent; radius: 24; color: root.roomColors[(root.roomNumber - 1) % 3] }
  Rectangle { x: 20; y: 56; width: parent.width - 40; height: parent.height - 151; radius: 70; color: "#FFF9F4"; opacity: 0.8 }
  Text { x: 22; y: 18; text: root.welcomed ? "Meet " + root.guest.name + "!" : "A surprise guest…"; color: "#654E5E"; font.pixelSize: 19; font.bold: true }
  Text { anchors.right: parent.right; anchors.rightMargin: 24; y: 19; text: root.welcomed ? "♥" : root.roomNumber + " / 3"; color: "#B96785"; font.pixelSize: root.welcomed ? 24 : 13 }

  Rectangle { x: parent.width * 0.15; y: parent.height - 118; width: parent.width * 0.7; height: 28; radius: 14; color: "#DFA4B5"; opacity: root.comforts >= 1 ? 1 : 0.15 }
  Rectangle { x: parent.width * 0.22; y: parent.height - 118; width: parent.width * 0.56; height: 19; radius: 10; color: "#FFE9D4"; visible: root.comforts >= 1 }
  PetPortrait {
    id: pet
    objectName: "petPortrait"
    anchors.horizontalCenter: parent.horizontalCenter
    y: 48; width: parent.width * 0.72; height: parent.height - 137
    petId: root.petId; accessoryId: root.accessoryId
    visible: root.welcomed
    opacity: root.revealProgress
  }
  Rectangle {
    objectName: "mysteryDoor"
    anchors.horizontalCenter: parent.horizontalCenter
    y: 64; width: 154; height: parent.height - 162; radius: 30
    color: "#DCA7B7"; border.color: "#C38D9F"; border.width: 3
    visible: !root.welcomed || root.revealProgress < 1
    opacity: 1 - root.revealProgress
    Rectangle { x: 10; y: 10; width: parent.width - 20; height: parent.height - 20; radius: 23; color: "transparent"; border.color: "#EDC7D0"; border.width: 2 }
    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 19; text: "ROOM 0" + root.roomNumber; color: "#784F62"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5 }
    Item {
      anchors.centerIn: parent; width: 64; height: 65
      Repeater {
        model: 4
        delegate: Rectangle {
          required property int index
          x: index * 15; y: index === 0 || index === 3 ? 12 : 1
          width: 14; height: 18; radius: 7; rotation: (index - 1.5) * 16; color: "#FFF1E5"
        }
      }
      Rectangle { x: 10; y: 25; width: 44; height: 35; radius: 18; color: "#FFF1E5" }
      Text { anchors.horizontalCenter: parent.horizontalCenter; y: 27; text: "?"; color: "#B4748D"; font.pixelSize: 24; font.bold: true }
    }
    Rectangle { x: parent.width - 21; y: parent.height / 2; width: 10; height: 10; radius: 5; color: "#FFE8A9"; border.color: "#B18C60" }
    Text { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 29; text: "Who’s inside?"; color: "#784F62"; font.pixelSize: 11; font.bold: true }
    Accessible.role: Accessible.Graphic
    Accessible.name: "Surprise pet hidden. Finish the problem to reveal your guest."
  }
  Rectangle {
    x: 28; y: parent.height - 115; width: 40; height: 24; radius: 9
    color: "#81AEA0"; opacity: root.comforts >= 2 ? 1 : 0.15
    Rectangle { x: 4; y: 0; width: 32; height: 8; radius: 4; color: "#628779" }
    Text { anchors.centerIn: parent; text: "♥"; color: "#F6F9E8"; font.pixelSize: 14 }
  }
  Rectangle {
    x: parent.width - 59; y: parent.height - 123; width: 32; height: 32; radius: 16
    color: "#EAB97D"; opacity: root.comforts >= 3 ? 1 : 0.15
    Rectangle { anchors.centerIn: parent; width: 8; height: parent.height; radius: 4; rotation: 24; color: "#FFF0D4" }
  }
  Row {
    x: 20; y: parent.height - 82; width: parent.width - 40; spacing: 6
    Repeater {
      model: ["Bed", "Treat", "Toy"]
      delegate: Rectangle {
        required property string modelData
        required property int index
        readonly property bool ready: root.comforts > index
        width: (root.width - 52) / 3; height: 26; radius: 9
        color: ready ? "#EDF4E6" : "#FFF8F3"
        Text { anchors.centerIn: parent; text: (parent.ready ? "✓  " : "") + modelData; color: parent.ready ? "#527260" : "#A68A99"; font.pixelSize: 11; font.bold: parent.ready }
      }
    }
  }
  Text {
    objectName: "roomFeedback"
    x: 18; y: parent.height - 44; width: parent.width - 36; height: 36
    text: root.welcomed ? root.guest.name + " loves this cozy room. A friend to keep!" : root.comforts === 3 ? "Room ready! Finish the answer to meet your pet." : "Check each step to get the room ready."
    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
    color: "#6C5965"; font.pixelSize: 12
  }
  Repeater {
    model: 9
    delegate: Text {
      required property int index
      visible: root.welcomed && root.revealing && !root.reducedMotion
      x: root.width * (0.13 + index * 0.09) + Math.sin(index * 2) * root.confettiProgress * 18
      y: root.height * 0.55 - root.confettiProgress * (78 + (index % 3) * 25)
      text: index % 3 === 0 ? "♥" : "✦"; font.pixelSize: 14 + index % 3 * 3
      color: index % 2 === 0 ? "#B96785" : "#C29650"
      opacity: Math.sin(Math.PI * root.confettiProgress)
      rotation: (index % 2 === 0 ? 1 : -1) * root.confettiProgress * 30
    }
  }
  ParallelAnimation {
    id: reveal
    NumberAnimation { target: root; property: "revealProgress"; from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "confettiProgress"; from: 0; to: 1; duration: 1050; easing.type: Easing.OutQuad }
    SequentialAnimation {
      NumberAnimation { target: pet; property: "scale"; from: 0.82; to: 1.07; duration: 300; easing.type: Easing.OutCubic }
      NumberAnimation { target: pet; property: "scale"; to: 1; duration: 280; easing.type: Easing.InOutQuad }
    }
  }
}
