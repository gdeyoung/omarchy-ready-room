import QtQuick
import qs.Commons
import qs.Ui
import "../ui"

// The Overlay tab: what the in-game readout shows and which corner it sits in.
//
// The honest bit sits at the top of the FPS section rather than buried: this
// overlay cannot count frames. Nothing outside a game's own process can. What
// it can do is tell you whether the GPU is pinned, whether you are out of
// VRAM, and how hot things are — which is most of what the numbers are for.
Column {
  id: root

  property var overlay: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  spacing: Style.spacing.md

  readonly property bool ready: overlay !== null

  Toggle {
    width: parent.width
    label: "Show overlay"
    description: {
      if (!root.ready) return ""
      if (root.overlay.error !== "") return root.overlay.error
      if (!root.overlay.enabled) return "sits above fullscreen games, takes no clicks"
      return "updating every " + root.overlay.interval.toFixed(1) + "s"
    }
    checked: root.ready && root.overlay.enabled
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.overlay.toggle()
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.55
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Bind it to a key:\nomarchy-shell -q gamecenter overlayToggle"
  }

  PanelSeparator { width: parent.width }

  // --------------------------------------------------------- corner

  PanelSectionHeader {
    width: parent.width
    text: "Corner"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  ButtonGroup {
    options: [
      { value: "top-left", label: "↖" },
      { value: "top-right", label: "↗" },
      { value: "bottom-left", label: "↙" },
      { value: "bottom-right", label: "↘" }
    ]
    value: root.ready ? root.overlay.corner : "top-right"
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onChanged: function(v) { if (root.ready) root.overlay.corner = v }
  }

  // --------------------------------------------------------- metrics

  PanelSectionHeader {
    width: parent.width
    text: "Show"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Toggle {
    width: parent.width
    label: "CPU load"
    checked: root.ready && root.overlay.showCpu
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.overlay.showCpu = !root.overlay.showCpu
  }

  Toggle {
    width: parent.width
    label: "GPU load"
    description: root.ready && root.overlay.gpuKind === "none"
      ? "no utilization counters on this GPU — package power shown instead" : ""
    checked: root.ready && root.overlay.showGpu
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.overlay.showGpu = !root.overlay.showGpu
  }

  Toggle {
    width: parent.width
    label: "VRAM"
    checked: root.ready && root.overlay.showVram
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.overlay.showVram = !root.overlay.showVram
  }

  Toggle {
    width: parent.width
    label: "System memory"
    checked: root.ready && root.overlay.showRam
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.overlay.showRam = !root.overlay.showRam
  }

  Toggle {
    width: parent.width
    label: "Temperatures"
    description: "turns amber past 80°, red past 90°"
    checked: root.ready && root.overlay.showTemps
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.overlay.showTemps = !root.overlay.showTemps
  }

  Toggle {
    width: parent.width
    label: "GPU power draw"
    description: root.ready && root.overlay.gpuKind === "amd"
      ? "not reported by this driver" : ""
    visible: !root.ready || root.overlay.gpuKind !== "amd"
    checked: root.ready && root.overlay.showPower
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.overlay.showPower = !root.overlay.showPower
  }

  PanelSeparator { width: parent.width }

  // --------------------------------------------------------- fps

  PanelSectionHeader {
    width: parent.width
    text: "Frames per second"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "This overlay can't count frames — only something running inside the "
        + "game can do that. MangoHud is that something: it loads into the "
        + "game's Vulkan or OpenGL, so it sees every frame."
  }

  GcDegradedRow {
    width: parent.width
    visible: root.ready && !root.overlay.mangohudInstalled
    message: "MangoHud isn't installed. Without it, everything above still works — you just won't see FPS."
    actionText: "Install"
    foreground: root.foreground
    fontFamily: root.fontFamily
    onActivated: if (root.ready) root.overlay.installMangohud()
  }

  Button {
    width: parent.width
    visible: root.ready && root.overlay.mangohudInstalled
    text: "Match MangoHud to these settings"
    bordered: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.overlay.writeMangohudConfig()
  }

  Text {
    width: parent.width
    visible: root.ready && root.overlay.mangohudInstalled
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.5
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Writes the same corner and metrics into MangoHud's own config, "
        + "leaving anything else in it alone. Launch a game with "
        + "mangohud %command% to use it."
  }
}
