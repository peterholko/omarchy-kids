import QtQuick
import "school" as School

// One plugin entry: ordinary summons open the controls; explicit menu
// payloads from the Omarchy button and shortcuts open the filtered app menu.
Item {
  id: root
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""
  readonly property var controller: shell ? shell.serviceFor("omarchy.screen-time") : null
  readonly property bool opened: (controller && controller.controlsOpen) || apps.opened || (controller && controller.mathOpen())

  School.Menu {
    id: apps
    shell: root.shell
    manifest: root.manifest
    omarchyPath: root.omarchyPath
  }
  function open(raw) {
    var payload
    try { payload = raw === "math" ? {math:true} : JSON.parse(raw || "{}") } catch (error) { payload = {} }
    if (payload && payload.math === true && controller) controller.showMath(raw === "math" ? "{}" : raw)
    else if (payload && (payload.menu !== undefined || payload.initialMenu !== undefined
        || payload.mode === "select" || payload.mode === "input")) apps.open(raw)
    else if (controller) controller.showControls()
  }
  function close() {
    apps.close()
    if (controller) { controller.closeControls(); controller.closeMath() }
  }
  function mathOpen() { return controller && controller.mathOpen() ? "true" : "false" }
  function removalReady() { return apps.removalReady() }
  function guardAppLaunch() { apps.guardAppLaunch() }
  function launchSchoolBrowser() { apps.launchSchoolBrowser() }
  function launchAllowedApp(payload) { apps.launchAllowedApp(payload) }
  function refresh() { apps.refresh() }
  function ping() { return "ready" }
}
