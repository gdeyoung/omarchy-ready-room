import QtQuick
import Quickshell
import Quickshell.Io

// Owns the replay buffer process and the socket we talk to it through.
//
// Saving goes over gpu-screen-recorder's own -ipc socket rather than through
// gsr-cli, because the reply to save-replay carries the path of the file that
// was written. Watching the output directory and guessing which file appeared
// is the alternative, and it is wrong the moment two saves land in the same
// second.
QtObject {
  id: root

  property string pluginDir: ""
  property string runtimeDir: ""

  readonly property string socketPath: runtimeDir + "/gsr.sock"

  property bool armed: false
  property bool busy: false
  property string error: ""
  property string lastClip: ""
  property bool stockRecording: false

  // Config, mirrored from the widget's inline settings.
  property int seconds: 300
  property string storage: "disk"
  property string quality: "balanced"
  property string audio: "desktop"
  // Empty means the launcher's default (Videos/Clips, or
  // $OMARCHY_SCREENRECORD_DIR). Set from the panel's clip-folder row.
  property string clipDir: ""

  // Filled in from the running buffer, so the UI can say what it is actually
  // capturing rather than what was asked for.
  property string activeMonitor: ""
  property int activeKbps: 0
  property int activeFps: 0

  signal clipSaved(string path)

  function script(args) { return [root.pluginDir + "/bin/gc-replay"].concat(args) }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = script(["status"])
    statusProcess.running = true
  }

  function arm() {
    if (busy) return
    busy = true
    error = ""
    var args = ["arm",
      "--seconds", String(seconds),
      "--storage", storage,
      "--quality", quality,
      "--audio", audio]
    if (clipDir !== "") args = args.concat(["--dir", clipDir])
    actionProcess.command = script(args)
    actionProcess.running = true
  }

  function disarm() {
    if (busy) return
    busy = true
    actionProcess.command = script(["disarm"])
    actionProcess.running = true
  }

  function toggle() { armed ? disarm() : arm() }

  // `seconds` of 0 means "whatever the buffer holds".
  property int _requestId: 0
  function save(secs) {
    if (!armed) { error = "nothing is being recorded"; return }
    if (gsr.connected) {
      root._requestId++
      var req = { id: root._requestId, name: "save-replay" }
      if (secs && secs > 0) req.data = { seconds: secs }
      gsr.write(JSON.stringify(req) + "\n")
      gsr.flush()
      return
    }
    // The socket is only connected while the panel has the controller alive;
    // a keybinding save with no connection falls back to the CLI.
    saveProcess.command = script(secs && secs > 0 ? ["save", String(secs)] : ["save"])
    saveProcess.running = true
  }

  function applyStatus(json) {
    try {
      var s = JSON.parse(json)
      root.armed = !!s.armed
      root.stockRecording = !!s.stockRecording
      if (s.lastClip) root.lastClip = String(s.lastClip)
      if (s.config) {
        root.activeMonitor = String(s.config.monitor || "")
        root.activeKbps = Number(s.config.kbps || 0)
        root.activeFps = Number(s.config.fps || 0)
      } else {
        root.activeMonitor = ""
        root.activeKbps = 0
        root.activeFps = 0
      }
    } catch (e) {
      root.error = "could not read replay state"
    }
  }

  property Process statusProcess: Process {
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }

  property Process actionProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text).trim()
        if (t !== "") {
          try {
            var r = JSON.parse(t)
            // arm/disarm answer with a status object; a refusal answers with
            // {ok:false,error:…} and the reason is worth showing verbatim,
            // since it is usually "not enough memory for a 60s buffer".
            if (r.ok === false) root.error = String(r.error || "could not arm")
            else { root.error = ""; root.applyStatus(t) }
          } catch (e) { root.error = t }
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text).trim()
        if (t === "") return
        try { root.error = String(JSON.parse(t).error || t) } catch (e) { root.error = t }
      }
    }
    onExited: { root.busy = false; root.refresh() }
  }

  property Process saveProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var r = JSON.parse(String(text))
          if (r.ok && r.detail) root.noteSaved(String(r.detail).trim())
          else if (r.ok === false) root.error = String(r.error || "save failed")
        } catch (e) { /* the -sc hook will surface the path */ }
      }
    }
  }

  function noteSaved(path) {
    if (!path) return
    root.lastClip = path
    root.error = ""
    root.clipSaved(path)
  }

  // gsr's IPC is newline-delimited JSON, one reply per request.
  property Socket gsr: Socket {
    path: root.socketPath
    connected: root.armed
    parser: SplitParser {
      onRead: function(line) {
        var t = String(line).trim()
        if (t === "") return
        try {
          var r = JSON.parse(t)
          if (r.result === "ok") root.noteSaved(String(r.data || ""))
          else if (r.result === "error") {
            // Asking for a clip before the buffer holds a keyframe is normal,
            // not a fault — it happens if you hit save a second after arming.
            var msg = String(r.data || "save failed")
            root.error = msg.indexOf("keyframe") >= 0
              ? "buffer is still filling — try again in a moment"
              : msg
          }
        } catch (e) { /* not our line */ }
      }
    }
  }

  // The -sc hook writes every saved path here, so a clip saved by a keybinding
  // while the panel is closed still registers.
  property FileView lastClipWatch: FileView {
    path: root.runtimeDir + "/last-clip"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var p = String(text()).trim()
      if (p !== "" && p !== root.lastClip) root.noteSaved(p)
    }
  }
}
