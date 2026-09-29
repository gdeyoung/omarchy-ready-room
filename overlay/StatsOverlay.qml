import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The in-game stats overlay.
//
// A layer-shell window on the overlay layer, so it sits above a fullscreen
// game without taking focus or input — `exclusiveZone: 0` and no keyboard
// focus mean it never steals a click or reserves screen space.
//
// What it cannot show is frames per second. Only code inside the game's own
// process can count its frames; that is what MangoHud's Vulkan/OpenGL layers
// do. Everything here is read from /proc, /sys and nvidia-smi, which is plenty
// for "is my GPU the bottleneck" but is honest about not being a frame timer.
PanelWindow {
  id: root

  property var stats: null
  property string corner: "top-right"     // top-left | top-right | bottom-left | bottom-right
  property bool showCpu: true
  property bool showGpu: true
  property bool showRam: true
  property bool showVram: true
  property bool showTemps: true
  property bool showPower: false
  property real scale: 1.0

  visible: false
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "readyroom-stats"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusiveZone: 0

  anchors.top: corner.indexOf("top") === 0
  anchors.bottom: corner.indexOf("bottom") === 0
  anchors.left: corner.indexOf("left") > 0
  anchors.right: corner.indexOf("right") > 0

  margins.top: Style.space(12)
  margins.bottom: Style.space(12)
  margins.left: Style.space(12)
  margins.right: Style.space(12)

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight

  readonly property real fontSize: Math.round(Style.font.caption * root.scale)

  function pct(value) { return value === undefined || value === null ? "—" : value + "%" }
  function deg(value) { return value === undefined || value === null ? "" : value + "°" }
  function gb(mb) { return mb === undefined || mb === null ? "—" : (mb / 1024).toFixed(1) + "G" }

  // Warm above 80°C, hot above 90 — the point where a number is worth looking
  // at rather than just being present.
  function tempColor(value) {
    if (value === undefined || value === null) return Color.foreground
    if (value >= 90) return Color.urgent
    if (value >= 80) return Color.accent
    return Color.foreground
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    implicitWidth: column.implicitWidth + Style.space(16) * root.scale
    implicitHeight: column.implicitHeight + Style.space(10) * root.scale
    radius: Style.cornerRadius
    // Dark enough to read over any game, light enough not to block it.
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.72)
    border.width: 1
    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

    Column {
      id: column
      anchors.centerIn: parent
      spacing: Style.space(2) * root.scale

      Repeater {
        model: root.rows

        Row {
          spacing: Style.space(6) * root.scale

          Text {
            width: Style.space(30) * root.scale
            text: modelData.label
            color: Color.foreground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: root.fontSize
          }

          Text {
            text: modelData.value
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: root.fontSize
          }

          Text {
            visible: modelData.temp !== ""
            text: modelData.temp
            color: root.tempColor(modelData.tempValue)
            font.family: Style.font.family
            font.pixelSize: root.fontSize
          }
        }
      }
    }
  }

  // Built as one list so the card sizes itself and rows never jump around as
  // values change width.
  readonly property var rows: {
    var out = []
    var s = root.stats
    if (!s) return [{ label: "", value: "starting…", temp: "", tempValue: null }]

    if (root.showCpu && s.cpu) {
      out.push({
        label: "CPU",
        value: root.pct(s.cpu.percent),
        temp: root.showTemps ? root.deg(s.cpu.temp) : "",
        tempValue: s.cpu.temp
      })
    }
    if (root.showGpu && s.gpu) {
      out.push({
        label: "GPU",
        value: root.pct(s.gpu.percent)
             + (root.showPower && s.gpu.watts !== null && s.gpu.watts !== undefined
                ? "  " + s.gpu.watts + "W" : ""),
        temp: root.showTemps ? root.deg(s.gpu.temp) : "",
        tempValue: s.gpu.temp
      })
    }
    // xe-driven Intel machines report no utilization counters, so package
    // watts (GPU + CPU on one die) is the honest activity signal there.
    if (root.showGpu && !s.gpu && s.packageWatts !== undefined && s.packageWatts !== null) {
      out.push({ label: "SoC", value: s.packageWatts + "W", temp: "", tempValue: null })
    }
    if (root.showVram && s.gpu && s.gpu.vramTotalMb) {
      out.push({
        label: "VRAM",
        value: root.gb(s.gpu.vramUsedMb) + " / " + root.gb(s.gpu.vramTotalMb),
        temp: "", tempValue: null
      })
    }
    if (root.showRam && s.ram) {
      out.push({
        label: "RAM",
        value: root.gb(s.ram.usedMb) + " / " + root.gb(s.ram.totalMb),
        temp: "", tempValue: null
      })
    }
    if (out.length === 0)
      out.push({ label: "", value: "nothing selected", temp: "", tempValue: null })
    return out
  }
}
