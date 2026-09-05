import QtQuick
import Quickshell
import Quickshell.Io

// Optional adapter. The game itself never imports screen-time UI or daemon code.
Item {
  id: root
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var status: ({})
  property var current: null
  readonly property bool available: status.enabled === true && status.earning === true
    && status.school !== true && Number(status.budget) > 0
  readonly property int grade: Number(String(status.level || "grade5").replace("grade", "")) || 5
  readonly property int questions: Number(status.questions) || 10
  readonly property int minutes: Number(status.sessionMinutes) || 30
  readonly property string note: !status.enabled
    ? "Practice is ready. Add Screen Time to enable parent-controlled rewards."
    : status.school ? "Practice is ready. Reward play returns in free time."
    : Number(status.budget) <= 0 ? "Use Math Time to earn time when your screen-time budget runs out."
    : "Practice is ready. Rewards are switched off or today's reward limit is reached."
  signal reply(int token, var result)

  function refresh() { statusFile.reload() }
  function cancel() {
    watchdog.stop()
    if (current) {
      var job = current
      current = null
      job.running = false
      job.destroy()
    }
  }
  function finish(job, result) {
    if (current !== job) return
    var token = job.token
    current = null
    watchdog.stop()
    job.running = false
    job.destroy()
    reply(token, result)
    refresh()
  }
  function request(token, kind, questionId, value) {
    if (current) { reply(token, {ok: false, error: "busy"}); return }
    if (!available) { reply(token, {ok: false, error: "earning_disabled"}); return }
    var args = kind === "next" ? ["next"] : ["answer", questionId, String(value)]
    current = requestProcess.createObject(root, {token: token,
      command: [omarchyPath + "/bin/omarchy-kids-grove-client"].concat(args)})
    watchdog.start()
    current.running = true
  }
  FileView {
    id: statusFile
    path: "/var/lib/omarchy/parent/" + (Quickshell.env("USER") || Quickshell.env("LOGNAME")) + "/time/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.status = JSON.parse(text()) || {} }
      catch (error) { root.status = {} }
    }
    onLoadFailed: root.status = ({})
  }
  Timer {
    id: watchdog
    interval: 8000
    onTriggered: if (root.current) root.finish(root.current, {ok: false, error: "timeout"})
  }
  Component {
    id: requestProcess
    Process {
      id: job
      property int token: -1
      property bool launched: false
      stdout: StdioCollector { id: output; waitForEnd: true }
      onStarted: launched = true
      onRunningChanged: {
        if (!running && !launched) root.finish(job, {ok: false, error: "unavailable"})
      }
      onExited: {
        var payload
        try { payload = JSON.parse(output.text) }
        catch (error) { payload = {ok: false, error: "unavailable"} }
        root.finish(job, payload)
      }
    }
  }
  Component.onDestruction: cancel()
}
