import QtQuick
import qs.Commons
import qs.Ui

// The Session tab: one switch per thing Ready Room is allowed to touch, and
// an honest sub-label under each one saying who currently owns it.
//
// The sub-labels are the point. Every other tool that drives these switches
// does so silently, so when your screen sleeps mid-game you have no idea which
// of three plugins let it. Here, a switch Ready Room will not touch says so,
// and says why, before you start the session rather than after.
Column {
  id: root

  property var session: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  spacing: Style.spacing.md

  readonly property bool ready: session !== null

  // ------------------------------------------------------- rival warning

  Rectangle {
    width: parent.width
    visible: root.ready && root.session.rival !== ""
    height: visible ? rivalText.implicitHeight + Style.spacing.md * 2 : 0
    color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.12)
    radius: Style.cornerRadius

    Text {
      id: rivalText
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      wrapMode: Text.WordWrap
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      text: "Another gaming plugin is holding stay-awake. Ready Room will "
          + "leave it alone, so both tools won't fight over it."
    }
  }

  // ------------------------------------------------------- the switches

  PanelSectionHeader {
    width: parent.width
    text: "This session will"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Toggle {
    width: parent.width
    label: "Keep the screen awake"
    description: root.ready ? root.session.stayAwakeNote : ""
    checked: root.ready && root.session.wantIdle
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.session.wantIdle = !root.session.wantIdle
  }

  Toggle {
    width: parent.width
    label: "Silence notifications"
    description: {
      if (!root.ready) return ""
      if (root.session.dndState === "unknown") return "can't read do-not-disturb right now"
      return root.session.note(root.session.ownedDnd,
                               root.session.dndState === "on",
                               "on for this session — put back when it ends",
                               "already on — Ready Room won't change it")
    }
    checked: root.ready && root.session.wantDnd
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.session.wantDnd = !root.session.wantDnd
  }

  Toggle {
    width: parent.width
    label: "Turn off night light"
    description: {
      if (!root.ready) return ""
      if (root.session.engaged && root.session.ownedNightlight)
        return "off for this session — restored to the same temperature"
      return root.session.nightlightOn
        ? "on now — turned off for the session, restored to the same temperature"
        : "already off"
    }
    checked: root.ready && root.session.wantNightlight
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.session.wantNightlight = !root.session.wantNightlight
  }

  Toggle {
    width: parent.width
    // A machine with only balanced and power-saver gets told so, rather than a
    // switch that appears to work and silently does nothing.
    visible: root.ready && root.session.powerProfileAvailable
    label: "Performance power profile"
    description: root.ready ? "now: " + root.session.powerCurrent : ""
    checked: root.ready && root.session.wantPower
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.session.wantPower = !root.session.wantPower
  }

  Text {
    width: parent.width
    visible: root.ready && !root.session.powerProfileAvailable
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.55
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: root.ready
      ? "No performance power profile on this machine (offers "
        + (root.session.powerAvailable || []).join(", ") + ")."
      : ""
  }

  PanelSeparator { width: parent.width }

  // ------------------------------------------------------- state line

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: {
      if (!root.ready) return "starting…"
      if (root.session.lastError !== "") return root.session.lastError
      if (root.session.busy) return "working…"
      return root.session.engaged
        ? "Session on. Ending it puts back only what Ready Room changed."
        : "Nothing changed yet."
    }
  }
}
