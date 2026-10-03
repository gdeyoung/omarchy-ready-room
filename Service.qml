import QtQuick
import Quickshell
import Quickshell.Io
import "session"
import "replay"
import "controllers"
import "overlay"

// Owner of everything that has to stay correct while nobody is looking.
//
// A `service` is mounted once per session; a `bar-widget` is mounted once per
// monitor. So session ownership, the replay process and the pad inventory live
// here, and the panel reaches them through
// `bar.shell.serviceFor("gdeyoung.readyroom")`.
//
// The rule this plugin is built around: the authoritative state is never in
// this process. Tokens, pid files and sockets live under $XDG_RUNTIME_DIR, so
// a shell restart mid-session recovers by reading the filesystem rather than
// by remembering anything. M1 builds the recovery path on top of this; M0 just
// establishes the directory and the IPC surface.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/gdeyoung.readyroom"

  // /run/user/1000/gdeyoung-readyroom. Wiped at logout, which is exactly the
  // staleness boundary we want: anything found here belongs to this login.
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || ("/tmp/gdeyoung-readyroom-" + Quickshell.env("UID"))) + "/gdeyoung-readyroom"

  // Distinguishes "this boot's leftovers" from "a token that survived a
  // reboot" without trusting timestamps. Read once; it cannot change.
  property string bootId: ""

  // M1. Owns the session toggles and their recovery.
  property SessionController session: SessionController {
    pluginDir: root.pluginDir
    runtimeDir: root.runtimeDir
  }

  readonly property bool sessionActive: session.engaged

  // M2. Owns the replay buffer process and its socket.
  property ReplayController replay: ReplayController {
    pluginDir: root.pluginDir
    runtimeDir: root.runtimeDir
  }

  readonly property bool replayArmed: replay.armed

  // The save-clip keybind in ~/.config/hypr/bindings.lua. State only lives
  // in the file (via gc-binds), so this reads, never remembers.
  property BindController binds: BindController { pluginDir: root.pluginDir }

  // M3. The saved-clip list, refreshed when a clip lands rather than polled.
  property ClipStore clipStore: ClipStore { pluginDir: root.pluginDir }

  property Connections clipRefresh: Connections {
    target: root.replay
    function onClipSaved(path) { root.clipStore.refresh() }
  }

  // M4. Controller inventory: probed on hotplug, not polled.
  property PadController pads: PadController { pluginDir: root.pluginDir }

  readonly property int padCount: pads.padCount

  // M7. Desk-gear batteries (mice, keyboards, headsets): slow-polled only
  // while the Gear tab is visible.
  property GearController gear: GearController { pluginDir: root.pluginDir }

  // M6. The in-game stats overlay and its MangoHud bridge.
  property OverlayController overlay: OverlayController { pluginDir: root.pluginDir }

  function statusJson() {
    return JSON.stringify({
      version: "1.0.0",
      session: root.sessionActive,
      replay: root.replayArmed,
      pads: root.padCount,
      padsClaimed: root.pads.claimedCount,
      overlay: root.overlay.enabled,
      runtimeDir: root.runtimeDir,
      bootId: root.bootId
    })
  }

  // FileView will not create a parent directory, so the runtime dir is made
  // once at mount rather than lazily inside a save path.
  property Process runtimeDirProcess: Process {
    command: ["mkdir", "-p", root.runtimeDir]
  }

  property Process bootIdProcess: Process {
    command: ["cat", "/proc/sys/kernel/random/boot_id"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.bootId = String(text).trim()
    }
  }

  // Commands the panel does not need: these exist so a keybinding or a script
  // can drive Ready Room without opening it.
  //
  //   omarchy-shell readyroom status
  //
  // The panel's own open/close/toggle lives on the `gdeyoung.readyroom`
  // target, which Ui.Panel provides for free from `ipcTarget`.
  property IpcHandler ipc: IpcHandler {
    target: "readyroom"

    function status(): string {
      return root.statusJson()
    }

    // Bindable without opening the panel:
    //   bind = SUPER ALT, G, exec, omarchy-shell -q readyroom sessionToggle
    function sessionOn(): string { root.session.engage(); return "engaging" }
    function sessionOff(): string { root.session.release(); return "releasing" }
    function sessionToggle(): string { root.session.toggle(); return "toggling" }

    // The one worth binding to a key:
    //   bind = SUPER ALT, R, exec, omarchy-shell -q readyroom saveClip
    // A quiet no-op when nothing is armed: a keybind that fires with no
    // buffer must not raise an error surface — the game is what matters.
    function saveClip(): string {
      if (!root.replayArmed) return "buffer not armed"
      root.replay.save(root.replay.seconds); return "saving"
    }
    function replayArm(): string { root.replay.arm(); return "arming" }
    function replayDisarm(): string { root.replay.disarm(); return "disarming" }
    function replayToggle(): string { root.replay.toggle(); return "toggling" }

    // Also reachable from the Pads tab; exposed here so it can be tested and
    // so anyone can reach the rule walkthrough without hunting for the button.
    function udevHelp(): string { root.pads.openUdevHelp(); return "opening" }

    // The other one worth binding to a key:
    //   bind = SUPER ALT, O, exec, omarchy-shell -q readyroom overlayToggle
    function overlayToggle(): string { root.overlay.toggle(); return "toggling" }
    function overlayOn(): string { root.overlay.enabled = true; return "on" }
    function overlayOff(): string { root.overlay.enabled = false; return "off" }

    // Live input for the first connected pad, without reaching for the panel.
    function padsLive(): string {
      if (root.pads.streamNode !== "") { root.pads.stopStream(); return "off" }
      if (root.pads.padCount === 0) {
        // Say which program has it rather than "nothing here", for the same
        // reason the Pads tab does.
        var c = root.pads.claimed
        if (c.length > 0) {
          var who = (c[0].holder && c[0].holder.name) ? c[0].holder.name : "another program"
          return c[0].name + (c[0].connection === "dongle" ? " adapter" : "")
               + " is open in " + who
        }
        return "no controller connected"
      }
      root.pads.startStream(root.pads.pads[0].node)
      return "on"
    }
  }

  Component.onCompleted: {
    runtimeDirProcess.running = true
    bootIdProcess.running = true
    // Recovery first: a session orphaned by a shell restart is put back before
    // any UI exists to show a stale claim.
    session.start()
    replay.refresh()
    // The inventory has to be right before anyone opens the panel: the bar
    // chip reports low battery from it, and a controller switched on before
    // the shell started would otherwise stay invisible until first open.
    pads.refresh()
  }
}
