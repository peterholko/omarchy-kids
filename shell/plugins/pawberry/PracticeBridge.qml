import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string clientPath: omarchyPath + "/bin/omarchy-kids-pawberry-client"
  property bool optional: false
  property bool ready: false
  property bool managed: true
  property var status: ({})
  property var current: null
  signal reply(int token, var result)
  function cancel() {
    watchdog.stop()
    if (current) { var job = current; job.pendingPassword = ""; current = null; job.running = false; job.destroy() }
  }
  function finish(job, result) {
    if (current !== job) return
    var token = job.token
    cancel()
    if (result.ok) { ready = true; managed = !result.standalone; status = result }
    else if (token === -1) ready = false
    if (result.remaining) status = result
    reply(token, result)
  }
  function refresh() { if (!current) request(-1, {cmd: "status"}) }
  function launch(token, command, secret, sendPassword) {
    if (current && current.token === -1 && token !== -1) cancel()
    if (current) { reply(token, {ok: false, error: "busy"}); return }
    current = requestProcess.createObject(root, {token: token, command: command,
      pendingPassword: secret, sendPassword: sendPassword})
    watchdog.start(); current.running = true
  }
  function saveLimits(token, limits, password) {
    if (!ready || !managed) { reply(token, {ok: false, error: "unavailable"}); return }
    // The existing parent client reads this password from stdin, never argv.
    var command = [clientPath, "limits", "--password-stdin",
      "--addition", limits.add === null ? "unlimited" : String(limits.add),
      "--subtraction", limits.subtract === null ? "unlimited" : String(limits.subtract)]
    launch(token, command, password, true)
  }
  function request(token, payload) {
    var command = [clientPath, "request", JSON.stringify(payload)]
    if (optional) command = ["/bin/bash", "-c", "if [[ -x \"$1\" ]]; then exec \"$1\" request \"$2\"; else echo '{\"ok\":true,\"standalone\":true}'; fi", "pawberry-policy", clientPath, JSON.stringify(payload)]
    launch(token, command, "", false)
  }
  Timer { id: watchdog; interval: 30000; onTriggered: if (root.current) root.finish(root.current, {ok: false, error: "unavailable"}) }
  Timer { interval: 10000; repeat: true; running: true; onTriggered: root.refresh() }
  Component {
    id: requestProcess
    Process {
      id: job
      property int token: -1
      property bool launched: false
      property string pendingPassword: ""
      property bool sendPassword: false
      stdinEnabled: sendPassword
      stdout: StdioCollector { id: output; waitForEnd: true }
      onStarted: {
        launched = true
        if (sendPassword) { write(pendingPassword + "\n"); pendingPassword = "" }
      }
      onRunningChanged: if (!running && !launched) root.finish(job, {ok: false, error: "unavailable"})
      onExited: {
        var result
        try { result = JSON.parse(output.text) } catch (error) { result = {ok: false, error: "unavailable"} }
        root.finish(job, result)
      }
    }
  }
  Component.onCompleted: refresh()
  Component.onDestruction: cancel()
}
