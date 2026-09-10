import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "omarchy.screen-time"
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("omarchy.screen-time") : null
  readonly property bool available: service && (service.connected || service.schoolService.schoolEnabled)
  visible: available
  implicitWidth: available ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight
  function open() { if (service) service.showControls() }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.service && root.service.schoolMode ? "School" : root.service ? Math.ceil(root.service.remainingSeconds / 60) + " min" : ""
    tooltipText: "School & Screen Time"
    onPressed: root.open()
  }
}
