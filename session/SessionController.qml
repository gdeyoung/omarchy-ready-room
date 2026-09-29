import QtQuick
import Quickshell
import Quickshell.Io

// The QML face of bin/gc-session.
//
// All the ownership logic lives in the script, deliberately: it has to work
// when the shell is dead, and a user with a stranded DND should be able to run
// `gc-session release` from a terminal without Quickshell being involved. This
// object runs it, parses it, and watches for the state drifting underneath us.
QtObject {
  id: root

  property string pluginDir: ""
  property string runtimeDir: ""

  // Mirrors of the probe, refreshed on open and whenever the marker changes.
  property bool engaged: false
  property string stayAwakeState: "free"   // free | manual | foreign | ours
  property string dndState: "unknown"      // on | off | unknown
  property bool nightlightOn: false
  property string powerCurrent: ""
  property var powerAvailable: []
  property string rival: ""
  property bool busy: false
  property string lastError: ""

  // Which switches the session is allowed to touch. Persisted inline on the
  // widget entry, so a user who never wants Ready Room near their night light
  // says so once.
  property bool wantIdle: true
  property bool wantDnd: true
  property bool wantNightlight: true
  property bool wantPower: true
  property string powerProfile: "performance"

  readonly property bool powerProfileAvailable:
    powerAvailable.indexOf(powerProfile) >= 0

  // What the Session tab explains about stay-awake, in the user's terms.
  readonly property string stayAwakeNote: {
    switch (stayAwakeState) {
      case "ours": return "on for this session — released when it ends"
      case "manual": return "already on — you set this, Ready Room won't change it"
      case "foreign": return "held by another tool — Ready Room won't change it"
      default: return engaged ? "left off" : "off now — turned on for the session"
    }
  }

  // The same three-way distinction for the switches that have no marker file:
  // ours for this session / already yours / not readable.
  function note(owned, isOn, whenEngaging, whenAlready) {
    if (engaged && owned) return isOn ? whenEngaging : "you changed this — Ready Room won't put it back"
    if (isOn) return whenAlready
    return engaged ? "left as it was" : whenEngaging
  }

  signal probed()

  function script(args) {
    return [root.pluginDir + "/bin/gc-session"].concat(args)
  }

  // `status` rather than `probe`: it carries the snapshot too, and without the
  // snapshot the tab can only report what a switch *is*, not who set it. "DND
  // is on" and "Ready Room turned DND on" need to read differently, or the
  // panel looks like it is refusing to manage something it is managing.
  function refresh() {
    if (probeProcess.running) return
    probeProcess.command = script(["status"])
    probeProcess.running = true
  }

  function engage() {
    if (busy) return
    var args = ["engage", "--owner-pid", String(Quickshell.processId)]
    if (!wantIdle) args.push("--no-idle")
    if (!wantDnd) args.push("--no-dnd")
    if (!wantNightlight) args.push("--no-nightlight")
    if (!wantPower || !powerProfileAvailable) args.push("--no-power")
    else { args.push("--profile"); args.push(powerProfile) }
    run(args)
  }

  function release() {
    if (busy) return
    run(["release"])
  }

  function toggle() { engaged ? release() : engage() }

  function run(args) {
    busy = true
    actionProcess.command = script(args)
    actionProcess.running = true
  }

  // Which switches this session actually took, as recorded at engage time.
  property bool ownedIdle: false
  property bool ownedDnd: false
  property bool ownedNightlight: false
  property bool ownedPower: false

  function applyProbe(json) {
    try {
      var s = JSON.parse(json)
      var p = s.probe
      root.engaged = !!s.engaged
      root.stayAwakeState = String(p.stayAwake.state)
      root.dndState = String(p.dnd.state)
      root.nightlightOn = !!p.nightlight.enabled
      root.powerCurrent = String(p.power.current || "")
      root.powerAvailable = p.power.available || []
      root.rival = String(p.rival || "")

      var items = s.snapshot && s.snapshot.items ? s.snapshot.items : null
      root.ownedIdle = !!(items && items.idle.owned)
      root.ownedDnd = !!(items && items.dnd.owned)
      root.ownedNightlight = !!(items && items.nightlight.owned)
      root.ownedPower = !!(items && items.power.owned)

      root.lastError = ""
    } catch (e) {
      root.lastError = "could not read session state"
    }
    root.probed()
  }

  property Process probeProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProbe(text)
    }
  }

  property Process actionProcess: Process {
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text).trim() !== "") root.lastError = String(text).trim()
    }
    onExited: function(code) {
      root.busy = false
      root.refresh()
    }
  }

  // Recovery runs once at mount, before any UI exists. A session whose owner
  // died — shell killed, crash, `pkill quickshell` — is put back here, and the
  // user is told rather than left to wonder why their DND came back.
  property Process recoverProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var restored = []
        var deferred = false
        try {
          var r = JSON.parse(text)
          restored = r.restored || []
          deferred = !!r.deferred
        } catch (e) { /* nothing to report */ }
        // The shell was still coming up and a switch could not be read. The
        // claim is still on disk, so try again shortly rather than leaving the
        // user's setting stranded.
        if (deferred) retryTimer.restart()
        if (restored.length > 0) {
          notify.command = ["omarchy-notification-send", "-g", "󰊴", "-u", "normal", "-t", "6000",
                            "Ready Room",
                            "Restored " + restored.join(", ") + " after the shell restarted"]
          notify.running = true
        }
        root.refresh()
      }
    }
  }

  property Process notify: Process {}

  // Backs off rather than hammering: a shell that is not answering yet needs
  // seconds, not milliseconds, and the claim on disk is safe in the meantime.
  property int retryAttempt: 0
  property Timer retryTimer: Timer {
    interval: 5000
    onTriggered: {
      if (root.retryAttempt >= 5) return
      root.retryAttempt++
      root.recoverProcess.command = root.script(["recover"])
      root.recoverProcess.running = true
    }
  }

  // The stay-awake marker is shared state: the stock indicator, game-awake and
  // gamemode-switcher all write it. Watching the directory means a manual
  // "allow idle" mid-session is noticed immediately instead of at the next
  // panel open, so the tab never shows a claim we no longer hold.
  property FileView awakeWatch: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/indicators"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  function start() {
    recoverProcess.command = script(["recover"])
    recoverProcess.running = true
  }
}
