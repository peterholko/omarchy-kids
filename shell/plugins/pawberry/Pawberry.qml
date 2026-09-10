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
  readonly property var schoolService: shell && typeof shell.serviceFor === "function" ? (shell.serviceFor("omarchy.screen-time") || {}).schoolService : null
  readonly property bool schoolAllowed: !schoolService || !schoolService.schoolMode || schoolService.isAllowed("omarchy-pawberry.desktop")
  function open(payloadJson) { opened = true; game.reset(); Qt.callLater(function() { game.forceActiveFocus() }) }
  function close() { game.reset(); opened = false }
  FloatingWindow {
    visible: root.opened && root.schoolAllowed
    title: "Pawberry Pet Hotel"; color: "#FAF5F2"
    implicitWidth: 1120; implicitHeight: 800; minimumSize: Qt.size(840, 600)
    onClosed: root.close()
    HotelView { id: game; anchors.fill: parent; windowActive: Window.active && root.opened && root.schoolAllowed; onQuitRequested: root.close() }
  }
}
