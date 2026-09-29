import QtQuick
import qs.Commons
import qs.Ui
import "session"
import "replay"
import "controllers"
import "overlay"

// Bar chip plus popout. The panel owns view state only — which tab is
// showing, where the keyboard cursor is — while everything that outlives the
// popout belongs to Service.qml.
//
// The chip is deliberately quiet. One glyph, one state, picked by a strict
// priority ladder (recording > replay armed > session on > idle), because a
// gaming widget that stacks counts and badges into the bar is the fastest
// route to being uninstalled. The sentence goes in the tooltip.
Panel {
  id: root

  moduleName: "gdeyoung.readyroom"
  ipcTarget: "gdeyoung.readyroom"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color panelForeground: Color.popups.text
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // A service is mounted once per session and may not exist yet on the very
  // first paint, so every read goes through this null check.
  readonly property var gameCenter: bar && bar.shell ? bar.shell.serviceFor("gdeyoung.readyroom") : null
  readonly property bool serviceReady: gameCenter !== null
  readonly property var session: gameCenter ? gameCenter.session : null
  readonly property bool sessionOn: session ? session.engaged : false
  readonly property var replay: gameCenter ? gameCenter.replay : null
  readonly property bool replayArmed: replay ? replay.armed : false
  readonly property var clipStore: gameCenter ? gameCenter.clipStore : null
  readonly property var binds: gameCenter ? gameCenter.binds : null
  readonly property var padStore: gameCenter ? gameCenter.pads : null
  readonly property var overlayStore: gameCenter ? gameCenter.overlay : null

  // The probe costs four subprocesses, so it runs when the panel opens rather
  // than on a timer. While the panel is closed the marker watcher is the only
  // thing keeping state fresh, which is enough for the chip.
  onOpenedChanged: {
    if (!opened) {
      // Nothing keeps probing — or streaming — once the popout is gone.
      if (padStore) {
        padStore.watching = false
        padStore.stopStream()
        // A half-finished blink would otherwise leave the light off.
        padStore.endBlink()
      }
      return
    }
    if (session) session.refresh()
    if (replay) replay.refresh()
    if (binds) binds.refresh()
    // One find per open, not a watcher on the video folder: that can live on a
    // network mount and a FileView there would stall the event loop.
    if (clipStore) clipStore.refresh()
    if (padStore) {
      padStore.refresh()
      padStore.watching = (root.tab === "pads")
    }
  }

  // Battery level changes with no filesystem event behind it, so the pads tab
  // polls slowly — but only while it is the tab being looked at.
  onTabChanged: {
    if (!padStore) return
    padStore.watching = (tab === "pads" && opened)
    if (tab !== "pads") padStore.stopStream()
  }

  readonly property int panelWidth: setting("panelWidth", 380)

  // ------------------------------------------------------------- tabs

  readonly property var tabs: [
    { value: "session", label: "Session" },
    { value: "pads", label: "Pads" },
    { value: "clips", label: "Clips" },
    { value: "overlay", label: "Overlay" }
  ]

  property string tab: "session"
  property bool loading: false

  function loadSettings() {
    loading = true
    var wanted = String(setting("startTab", "session"))
    tab = tabs.some(function(t) { return t.value === wanted }) ? wanted : "session"
    if (session) {
      session.wantIdle = setting("keepAwake", true)
      session.wantDnd = setting("silenceNotifications", true)
      session.wantNightlight = setting("nightLightOff", true)
      session.wantPower = setting("performanceProfile", true)
    }
    if (overlayStore) {
      overlayStore.corner = setting("overlayCorner", "top-right")
      overlayStore.showCpu = setting("overlayCpu", true)
      overlayStore.showGpu = setting("overlayGpu", true)
      overlayStore.showRam = setting("overlayRam", true)
      overlayStore.showVram = setting("overlayVram", true)
      overlayStore.showTemps = setting("overlayTemps", true)
      overlayStore.showPower = setting("overlayPower", false)
    }
    if (replay) {
      replay.seconds = setting("replaySeconds", 300)
      replay.storage = setting("replayStorage", "disk")
      replay.quality = setting("replayQuality", "balanced")
      replay.audio = setting("replayAudio", "desktop")
      replay.clipDir = String(setting("replayDir", ""))
    }
    loading = false
  }

  // The service outlives the panel, so its controller may already exist when
  // this widget mounts — or arrive a moment later on a cold start.
  onSessionChanged: if (session) loadSettings()
  onReplayChanged: if (replay) loadSettings()
  onOverlayStoreChanged: if (overlayStore) loadSettings()

  Connections {
    target: root.session
    ignoreUnknownSignals: true
    function onWantIdleChanged() { root.persist() }
    function onWantDndChanged() { root.persist() }
    function onWantNightlightChanged() { root.persist() }
    function onWantPowerChanged() { root.persist() }
  }

  Connections {
    target: root.overlayStore
    ignoreUnknownSignals: true
    function onCornerChanged() { root.persist() }
    function onShowCpuChanged() { root.persist() }
    function onShowGpuChanged() { root.persist() }
    function onShowRamChanged() { root.persist() }
    function onShowVramChanged() { root.persist() }
    function onShowTempsChanged() { root.persist() }
    function onShowPowerChanged() { root.persist() }
  }

  Connections {
    target: root.replay
    ignoreUnknownSignals: true
    function onSecondsChanged() { root.persist() }
    function onStorageChanged() { root.persist() }
    function onQualityChanged() { root.persist() }
    function onAudioChanged() { root.persist() }
    function onClipDirChanged() { root.persist() }
  }

  function tabIndex(value) {
    for (var i = 0; i < tabs.length; i++) if (tabs[i].value === value) return i
    return 0
  }

  function moveTab(delta) {
    var next = tabIndex(root.tab) + delta
    if (next < 0) next = tabs.length - 1
    if (next >= tabs.length) next = 0
    setTab(tabs[next].value)
  }

  function setTab(value) {
    if (root.tab === value) return
    root.tab = value
    persist()
  }

  // Stepping through three tabs is three clicks, and each one would otherwise
  // be its own rewrite of shell.json.
  function persist() {
    if (loading) return
    persistTimer.restart()
  }

  function persistNow() {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.startTab = root.tab
    if (root.session) {
      entry.keepAwake = root.session.wantIdle
      entry.silenceNotifications = root.session.wantDnd
      entry.nightLightOff = root.session.wantNightlight
      entry.performanceProfile = root.session.wantPower
    }
    if (root.overlayStore) {
      entry.overlayCorner = root.overlayStore.corner
      entry.overlayCpu = root.overlayStore.showCpu
      entry.overlayGpu = root.overlayStore.showGpu
      entry.overlayRam = root.overlayStore.showRam
      entry.overlayVram = root.overlayStore.showVram
      entry.overlayTemps = root.overlayStore.showTemps
      entry.overlayPower = root.overlayStore.showPower
    }
    if (root.replay) {
      entry.replaySeconds = root.replay.seconds
      entry.replayStorage = root.replay.storage
      entry.replayQuality = root.replay.quality
      entry.replayAudio = root.replay.audio
      entry.replayDir = root.replay.clipDir
    }
    if (JSON.stringify(entry) === JSON.stringify(root.settings)) return
    root.settings = entry
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  Timer {
    id: persistTimer
    interval: 500
    onTriggered: root.persistNow()
  }

  Component.onCompleted: loadSettings()
  onSettingsChanged: if (!loading) loadSettings()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------- bar chip

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    // nf-md-microsoft_xbox_controller (U+F02B4): reads as "gamepad" at bar
    // size, where a more detailed glyph turns to mush.
    text: "󰊴"
    active: root.opened || root.sessionOn || root.replayArmed

    // One glyph, one state, in priority order. A bar widget that stacks
    // badges is the fastest route to being uninstalled, so the detail lives
    // in the tooltip.
    tooltipText: {
      if (!root.serviceReady) return "Ready Room (starting)"
      var parts = []
      if (root.replayArmed) parts.push("replay armed (" + root.replay.seconds + "s)")
      if (root.sessionOn) parts.push("session on")
      if (root.replay && root.replay.stockRecording) parts.push("screen recording")
      return parts.length ? "Ready Room — " + parts.join(" · ") : "Ready Room"
    }

    onPressed: function(b) { root.toggle() }
  }

  // ------------------------------------------------------------- popout

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: Math.round(Math.min(
      Math.max(popup.verticalContentInset, content.implicitHeight + popup.verticalContentInset),
      popup.availableCardHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.moveTab(dx) }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.md

        PanelHero {
          width: parent.width
          title: "Ready Room"
          meta: {
            if (!root.serviceReady) return "Starting…"
            if (root.session && root.session.busy) return "Working…"
            return root.sessionOn ? "Session on" : "Session off"
          }
          foreground: root.panelForeground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: "󰊴"
              color: root.sessionOn ? Color.accent : root.panelForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          // The master switch lives in the hero so it is reachable from every
          // tab without navigating back.
          trailingControl: Component {
            ToggleSwitch {
              checked: root.sessionOn
              busy: root.session ? root.session.busy : false
              interactive: root.serviceReady
              foreground: root.panelForeground
              accent: Color.accent
              onToggled: if (root.session) root.session.toggle()
            }
          }
        }

        ButtonGroup {
          options: root.tabs
          value: root.tab
          foreground: root.panelForeground
          accent: Color.accent
          fontFamily: root.fontFamily
          onChanged: function(value) { root.setTab(value) }
        }

        PanelSeparator { width: parent.width }

        SessionTab {
          width: parent.width
          visible: root.tab === "session"
          session: root.session
          foreground: root.panelForeground
          fontFamily: root.fontFamily
        }

        ReplayTab {
          width: parent.width
          visible: root.tab === "clips"
          replay: root.replay
          clips: root.clipStore
          binds: root.binds
          foreground: root.panelForeground
          fontFamily: root.fontFamily
        }

        PadsTab {
          width: parent.width
          visible: root.tab === "pads"
          pads: root.padStore
          foreground: root.panelForeground
          fontFamily: root.fontFamily
        }

        OverlayTab {
          width: parent.width
          visible: root.tab === "overlay"
          overlay: root.overlayStore
          foreground: root.panelForeground
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
