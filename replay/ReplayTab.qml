import QtQuick
import qs.Commons
import qs.Ui

// The Clips tab: arm the buffer, then save the last N seconds of it.
//
// The buffer's cost is stated up front — memory, bitrate, monitor — because
// arming one is a decision with a price, and a widget that quietly holds
// 300MB of your RAM for a whole evening should say so.
Column {
  id: root

  property var replay: null
  property var clips: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  spacing: Style.spacing.md

  readonly property bool ready: replay !== null
  readonly property bool armed: ready && replay.armed
  readonly property int clipCount: clips && clips.clips ? clips.clips.length : 0

  // Deleting a clip is not undoable, so it goes through a confirmation naming
  // the file — the delete button sits next to three harmless ones.
  property var pendingDelete: null
  function confirmDelete(clip) {
    root.pendingDelete = clip
    deleteDialog.opened = true
  }

  ConfirmDialog {
    id: deleteDialog
    message: root.pendingDelete
      ? "Delete " + root.pendingDelete.name + " permanently?"
      : ""
    confirmText: "Delete"
    cancelText: "Keep"
    onConfirmed: {
      if (root.pendingDelete && root.clips) root.clips.remove(root.pendingDelete.path)
      root.pendingDelete = null
    }
    onCanceled: root.pendingDelete = null
  }

  // kbps × seconds ÷ 8 is the payload. The encoder's working set is a large
  // fixed cost on top of it (measured 180–300MB depending on capture
  // resolution), so quoting the payload alone would understate a 15s buffer by
  // a factor of five. Same arithmetic as the launcher's preflight.
  readonly property int estimateMb: {
    if (!ready) return 0
    var kbps = replay.activeKbps > 0 ? replay.activeKbps : 26000
    return Math.round(kbps * replay.seconds / 8 / 1024) + 400
  }

  // --------------------------------------------------------- state row

  Toggle {
    width: parent.width
    label: root.armed ? "Replay buffer running" : "Replay buffer"
    description: {
      if (!root.ready) return ""
      if (root.replay.busy) return "working…"
      if (root.armed)
        return "holding the last " + root.replay.seconds + "s of "
             + root.replay.activeMonitor + " · ~" + root.estimateMb + "MB"
      return "keeps the last " + root.replay.seconds + "s so you can save it after it happens"
    }
    checked: root.armed
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.ready) root.replay.toggle()
  }

  // --------------------------------------------------------- save

  Button {
    width: parent.width
    text: "Save the last " + (root.ready ? root.replay.seconds : 30) + " seconds"
    enabled: root.armed
    opacity: root.armed ? 1.0 : 0.4
    bordered: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: if (root.armed) root.replay.save(root.ready ? root.replay.seconds : 0)
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.55
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Bind this to a key so you don't have to open the panel:\n"
        + "omarchy-shell -q gamecenter saveClip"
  }

  PanelSeparator { width: parent.width }

  // --------------------------------------------------------- settings

  PanelSectionHeader {
    width: parent.width
    text: "Buffer length"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  ButtonGroup {
    options: [
      { value: "60", label: "1m" },
      { value: "300", label: "5m" },
      { value: "600", label: "10m" },
      { value: "900", label: "15m" }
    ]
    value: root.ready ? String(root.replay.seconds) : "300"
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    // Changing length means restarting the capture, so it only takes effect on
    // the next arm — said plainly below rather than silently ignored.
    onChanged: function(v) { if (root.ready) root.replay.seconds = parseInt(v) }
  }

  Text {
    width: parent.width
    visible: root.ready && root.replay.seconds >= 600 && root.replay.storage === "ram"
    wrapMode: Text.WordWrap
    color: Color.urgent
    opacity: 0.9
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "A " + (root.replay.seconds / 60) + "-minute buffer in RAM costs "
        + Math.round(root.estimateMb / 1024) + "GB held for the whole session. "
        + "Set storage to disk below unless you have headroom to burn."
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md

    Dropdown {
      label: "Quality"
      width: (parent.width - Style.spacing.md) / 2
      options: ["low", "balanced", "high", "ultra"]
      value: root.ready ? root.replay.quality : "balanced"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(v) { if (root.ready) root.replay.quality = v }
    }

    Dropdown {
      label: "Audio"
      width: (parent.width - Style.spacing.md) / 2
      options: ["desktop", "both", "none"]
      value: root.ready ? root.replay.audio : "desktop"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(v) { if (root.ready) root.replay.audio = v }
    }
  }

  Dropdown {
    width: parent.width
    label: "Buffer storage"
    options: ["disk", "ram"]
    value: root.ready ? root.replay.storage : "disk"
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(v) { if (root.ready) root.replay.storage = v }
  }

  // Where dumps land. Empty = Videos/Clips (or $OMARCHY_SCREENRECORD_DIR).
  // Plain QtQuick TextInput: the shell's widget set has no text field, and a
  // folder picker would need a portal dialog we don't want to spawn from a
  // layer-shell panel. A path is pasteable; that is enough.
  Column {
    width: parent.width
    spacing: Style.spacing.xxs

    Text {
      text: "Clip folder"
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      width: parent.width
      height: Math.max(Style.space(22), folderInput.implicitHeight + Style.space(6))
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

      TextInput {
        id: folderInput
        anchors.fill: parent
        anchors.margins: Style.space(3)
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        text: root.ready ? root.replay.clipDir : ""
        onTextChanged: if (root.ready && text !== root.replay.clipDir) root.replay.clipDir = text
      }
    }

    Text {
      width: parent.width
      visible: root.ready && root.replay.clipDir === ""
      wrapMode: Text.WordWrap
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      text: "Empty = Videos/Clips"
    }
  }

  Text {
    width: parent.width
    visible: root.armed
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.55
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Changes apply the next time the buffer starts."
  }

  // --------------------------------------------------------- clips

  PanelSeparator { width: parent.width }

  PanelSectionHeader {
    width: parent.width
    text: "Recent clips"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    visible: root.clipCount === 0
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.55
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: root.clips && root.clips.loading ? "looking…" : "No clips yet."
  }

  Column {
    width: parent.width
    spacing: Style.spacing.xxs

    Repeater {
      model: root.clips ? root.clips.clips : []

      ClipRow {
        width: parent.width
        clip: modelData
        // ClipStore replaces the whole map on each arrival, so this binding
        // re-evaluates when a thumbnail lands.
        thumb: {
          if (!root.clips) return ""
          var t = root.clips.thumbs[modelData.path]
          return t === undefined ? "" : t
        }
        foreground: root.foreground
        fontFamily: root.fontFamily

        onThumbNeeded: if (root.clips) root.clips.requestThumb(modelData.path)
        onOpenRequested: if (root.clips) root.clips.open(modelData.path)
        onRevealRequested: if (root.clips) root.clips.reveal(modelData.path)
        onCopyRequested: if (root.clips) root.clips.copyPath(modelData.path)
        onDeleteRequested: root.confirmDelete(modelData)
      }
    }
  }

  // --------------------------------------------------------- footer

  PanelSeparator { width: parent.width }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    color: root.ready && root.replay.error !== "" ? Color.urgent : root.foreground
    opacity: root.ready && root.replay.error !== "" ? 1.0 : 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: {
      if (!root.ready) return "starting…"
      if (root.replay.error !== "") return root.replay.error
      if (root.replay.stockRecording) return "A screen recording is also running — both share the GPU encoder."
      if (root.clips && root.clips.error !== "") return root.clips.error
      return root.armed ? "Buffer running." : ""
    }
  }
}
