import QtQuick
import Quickshell.Io

// Desk-gear battery inventory (mice, keyboards, headsets, Bluetooth pads).
//
// The probe is a one-shot subprocess over `upower --dump`, run when the Gear
// tab opens and every 60s while someone is looking — battery levels drift,
// they do not event. Nothing runs while the tab is closed (same watching
// contract as PadController).
QtObject {
  id: root

  property string pluginDir: ""

  property var gear: []
  property string error: ""
  property bool probing: false
  property bool watching: false

  readonly property int count: gear.length

  // Any device at or under 20% (or reporting low) earns a row highlight.
  readonly property bool anyLow: {
    for (var i = 0; i < gear.length; i++) {
      var g = gear[i]
      if (g.level !== null && g.level <= 20) return true
    }
    return false
  }

  function refresh() {
    if (probeProcess.running) return
    root.probing = true
    probeProcess.running = true
  }

  function applyProbe(json) {
    root.probing = false
    try {
      var parsed = JSON.parse(json)
      root.gear = parsed.gear || []
      root.error = ""
    } catch (err) {
      root.gear = []
      root.error = "could not read gear state"
    }
  }

  property Process probeProcess: Process {
    command: [root.pluginDir + "/bin/gc-gear-probe"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProbe(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text).trim() !== "") root.error = String(text).trim()
    }
  }

  // Slow poll, alive only while the tab is visible.
  property Timer pollTimer: Timer {
    interval: 60000
    running: root.watching
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  property Connections panelLink: Connections {
    target: null
    function onOpenedChanged() {}
  }
}
