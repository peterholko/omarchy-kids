import QtQuick
import QtQuick.Window
import Quickshell

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  readonly property var schoolService: shell && typeof shell.serviceFor === "function"
    ? shell.serviceFor("omarchy.school-mode") : null
  readonly property bool schoolAllowed: !schoolService || !schoolService.schoolMode
    || schoolService.isAllowed("omarchy-paw-post.desktop")

  function open(payloadJson) {
    opened = true
    game.reset()
    Qt.callLater(function() { game.forceActiveFocus() })
  }
  function close() { game.reset(); opened = false }
  FloatingWindow {
    visible: root.opened && root.schoolAllowed
    title: "Paw Post"
    color: "#FAF7F2"
    implicitWidth: 1080; implicitHeight: 820
    minimumSize: Qt.size(810, 615)
    onClosed: root.close()
    TypingView {
      id: game
      anchors.fill: parent
      windowActive: Window.active && root.opened
      onQuitRequested: root.close()
    }
  }
}
