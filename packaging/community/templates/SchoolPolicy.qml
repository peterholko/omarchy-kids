import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string desktopId: ""
  property var status: ({})
  readonly property bool allowed: status.enabled !== true || status.mode !== "school"
    || (Array.isArray(status.schoolApps) && status.schoolApps.indexOf(desktopId.replace(/\.desktop$/, "")) !== -1)
  FileView {
    path: "/var/lib/omarchy-kids-controls/status/" + Quickshell.env("USER") + "/school-mode/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && parsed.schemaVersion === 1 && typeof parsed.enabled === "boolean") root.status = parsed
      } catch (error) {}
    }
  }
}
