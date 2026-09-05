import QtQuick
import QtQuick.Window
import Quickshell
import qs.Ui

ShellRoot {
  Window {
    visible: true
    width: 640
    height: 390
    color: "#171a23"
    title: "Parent password field verification"
    Column {
      anchors.centerIn: parent
      spacing: 16
      Text { text: "School / Free Time — Parent password"; color: "white"; font.pixelSize: 21 }
      Text { text: "Ready"; color: "white" }
      ParentPasswordField { id: ready; width: 420 }
      Text { text: "Checking"; color: "white" }
      ParentPasswordField { id: pending; width: 420; checking: true }
      Text { text: "Incorrect password. Try again."; color: "#ff9c9c" }
      ParentPasswordField { id: retry; width: 420 }
    }
    Timer {
      interval: 1000
      running: true
      onTriggered: {
        if (!pending.readOnly || ready.readOnly || retry.readOnly || pending.placeholderText !== "Checking password…") {
          console.log("RESULT fail password field state")
          Qt.quit()
        } else {
          retry.forceActiveFocus()
          console.log("RESULT pass password field states")
        }
      }
    }
  }
}
