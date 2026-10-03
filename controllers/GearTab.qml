import QtQuick
import qs.Commons
import qs.Ui
import "../ui"

// The Gear tab: batteries for everything on the desk that is not a gamepad —
// mice, keyboards, headsets, earbuds, Bluetooth pads all show here with a
// real percentage when the device reports one.
//
// Same rules as the rest of the plugin: absent, not zero. A device that is
// asleep reports nothing and is skipped by the probe; a device whose driver
// gives no percentage shows a dash, never a made-up number.
Column {
  id: root

  property var gear: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  spacing: Style.spacing.md

  readonly property bool ready: gear !== null
  readonly property int count: ready ? gear.count : 0

  // --------------------------------------------------------- empty state

  GcEmptyState {
    width: parent.width
    visible: root.count === 0
    glyph: "󰁹"
    title: root.ready && root.gear.probing ? "Reading gear…" : "No battery gear found"
    detail: root.ready && root.gear.error !== ""
      ? root.gear.error
      : "Mice, keyboards and headsets with batteries appear here when paired."
  }

  // -------------------------------------------------------------- rows

  Repeater {
    model: root.count
    delegate: Row {
      id: row
      required property int index
      readonly property var device: root.ready ? root.gear.gear[index] || null : null
      width: parent.width
      spacing: Style.spacing.sm

      readonly property bool low: device
        && device.level !== null && device.level !== undefined && device.level <= 20
      readonly property string levelText: {
        if (!device) return ""
        if (device.level === null || device.level === undefined)
          return device.charging === true ? "charging" : "—"
        var suffix = device.charging === true ? " ⚡" : ""
        return device.level + "%" + suffix
      }
      readonly property string kindGlyph: {
        if (!device) return ""
        var map = {
          mouse: "󰍽", keyboard: "󰌌", headset: "󰋋", earbuds: "󰥉",
          gamepad: "󰊴", phone: "󰄛", tablet: "󰄜", watch: "󰥚"
        }
        return map[device.kind] || "󰚗"
      }

      Text {
        id: kindText
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.kindGlyph
        color: root.foreground
        opacity: 0.75
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - levelText.implicitWidth - kindText.implicitWidth
               - 2 * Style.spacing.sm
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: row.device ? row.device.name : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Item { height: 1; width: Style.spacing.md }

      Text {
        id: levelText
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.levelText
        color: row.low ? Color.urgent : root.foreground
        opacity: row.low ? 1.0 : 0.8
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
