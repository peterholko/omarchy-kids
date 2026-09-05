import QtQuick

// Original geometric characters, kept separate from the board and game rules.
Item {
  id: root
  property bool bug: false
  property bool shielded: false
  property bool animate: true
  property real bob: 0
  implicitWidth: 64
  implicitHeight: 68
  SequentialAnimation on bob {
    running: root.animate
    loops: Animation.Infinite
    NumberAnimation { to: -3; duration: 750; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 750; easing.type: Easing.InOutSine }
  }
  Rectangle {
    x: root.width * 0.16; y: root.height * 0.82
    width: root.width * 0.68; height: root.height * 0.12
    radius: width / 2; color: "#253E2E"; opacity: 0.23
  }
  Item {
    width: parent.width; height: parent.height; y: root.bob
    Rectangle {
      visible: root.shielded && !root.bug
      anchors.centerIn: parent; width: parent.width + 8; height: parent.height + 2
      radius: 25; color: "transparent"; border.color: "#F9E297"; border.width: 2
    }
    Rectangle {
      x: parent.width * 0.47; y: parent.height * 0.01
      width: 5; height: parent.height * 0.25; radius: 2
      rotation: root.bug ? 25 : -8; color: root.bug ? "#D5B4F5" : "#B7D879"
    }
    Rectangle {
      x: parent.width * 0.20; y: parent.height * 0.02
      width: parent.width * 0.33; height: parent.height * 0.17
      radius: 10; rotation: 25; color: root.bug ? "#BD96E7" : "#89C86C"
    }
    Rectangle {
      x: parent.width * 0.50; y: 0
      width: parent.width * 0.29; height: parent.height * 0.16
      radius: 10; rotation: -30; color: root.bug ? "#D4B7F2" : "#CDE793"
    }
    Rectangle {
      x: parent.width * 0.12; y: parent.height * 0.24
      width: parent.width * 0.76; height: parent.height * 0.60
      radius: root.bug ? 23 : 14
      color: root.bug ? "#9467B6" : "#F3C969"
      border.color: root.bug ? "#D5B4ED" : "#FFE8A4"; border.width: 2
      Rectangle {
        x: parent.width * 0.15; y: parent.height * 0.21
        width: parent.width * 0.70; height: parent.height * 0.47
        radius: root.bug ? 8 : 6; color: root.bug ? "#483054" : "#294E39"
        Row {
          anchors.centerIn: parent; spacing: 10
          Repeater { model: 2; Rectangle { width: 5; height: 8; radius: 2; color: "#FFF5CE" } }
        }
      }
    }
    Repeater {
      model: 2
      Rectangle {
        required property int index
        x: root.width * (index === 0 ? 0.23 : 0.60); y: root.height * 0.80
        width: root.width * 0.18; height: root.height * 0.12; radius: 4
        color: root.bug ? "#CFACED" : "#C49645"
      }
    }
  }
}
