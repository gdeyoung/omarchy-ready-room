import QtQuick
import Quickshell.Io

// The save-clip keybind, managed by bin/gc-binds in ~/.config/hypr/bindings.lua.
//
// Same shape as ClipStore: a script does the work, this holds the state the
// panel shows. The script verifies the bind actually registered and rolls the
// config back if Hyprland refuses it, so an ok here means the key works.
QtObject {
  id: root

  property string pluginDir: ""
  property string combo: "" // "SUPER + ALT + R", or "" when unbound
  property bool busy: false
  property string error: ""

  function script(args) { return [root.pluginDir + "/bin/gc-binds"].concat(args) }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = script(["status"])
    statusProcess.running = true
  }

  function apply(next) {
    if (root.busy) return
    root.busy = true
    root.error = ""
    setProcess.command = script(["set", next])
    setProcess.running = true
  }

  function clear() {
    if (root.busy) return
    root.busy = true
    root.error = ""
    clearProcess.command = script(["clear"])
    clearProcess.running = true
  }

  property Process statusProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var out = JSON.parse(String(text))
          root.combo = out.bound && out.bound !== "none" ? out.bound : ""
        } catch (e) {
          // Leave whatever was there; the panel shows "not set".
        }
      }
    }
  }

  property Process setProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        try {
          var out = JSON.parse(String(text))
          if (out.ok) { root.combo = out.bind; root.error = "" }
          else root.error = out.error || "could not set the keybind"
        } catch (e) {
          root.error = "could not set the keybind"
        }
      }
    }
  }

  property Process clearProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        try {
          var out = JSON.parse(String(text))
          if (out.ok) { root.combo = ""; root.error = "" }
          else root.error = out.error || "could not clear the keybind"
        } catch (e) {
          root.error = "could not clear the keybind"
        }
      }
    }
  }
}
