import QtQuick
import qs.Ui

// The stock menu button's look, on this plugin's own id. Service.qml moves
// this widget into the stock menu's bar slot on a child install; the menu it
// opens is the stock menu in free time and the filtered one in school mode.
BarWidget {
  id: root
  moduleName: "omarchy.screen-time.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\ue900"
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    tooltipText: "Omarchy menu"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton && root.bar)
        root.bar.run("omarchy-shell shell toggle omarchy.screen-time '{\"menu\":\"root\"}'")
    }
  }
}
