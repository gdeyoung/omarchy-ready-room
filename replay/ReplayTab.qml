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
  property var binds: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  spacing: Style.spacing.md

  readonly property bool ready: replay !== null
  readonly property bool armed: ready && replay.armed
  readonly property int clipCount: clips && clips.clips ? clips.clips.length : 0

  // Transient capture coaching shown under the keybind row.
  property string _bindHint: ""

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

  // --------------------------------------------------------- keybind

  // The whole point of a replay buffer is never opening the panel mid-game,
  // so the bind is set here rather than left to a manual bindings.lua edit.
  // Click the pill → press a combo (a modifier is required — a bare key
  // would be swallowed by the game) → gc-binds writes the managed block,
  // reloads, and verifies registration; a refusal (collision, bad combo)
  // shows under the row instead of failing silently.
  Column {
    width: parent.width
    spacing: Style.spacing.xxs

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        id: bindLabelText
        anchors.verticalCenter: parent.verticalCenter
        color: root.foreground
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        text: "Save-clip key"
      }

      // Flexible spacer pushing the pill to the right edge. Must reserve
      // room for the clear button too, or it overflows the panel.
      Item {
        height: 1
        width: parent.width - bindLabelText.width - bindPill.width
             - (clearBind.visible ? clearBind.width + Style.spacing.sm : 0)
             - Style.spacing.sm
      }

      // The pill: shows the combo, or "not set", or "press keys…" while
      // capturing. It is itself the button — one target, no separate Set.
      Rectangle {
        id: bindPill
        property bool capture: false
        radius: Style.cornerRadius
        implicitWidth: pillText.implicitWidth + Style.spacing.md * 2
        implicitHeight: Style.space(24)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, capture ? 0.16 : 0.06)
        border.width: 1
        border.color: capture ? Color.accent
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

        Text {
          id: pillText
          anchors.centerIn: parent
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          text: {
            if (!root.binds) return "…"
            if (root.binds.busy) return "working…"
            if (bindPill.capture) return "press keys…"
            return root.binds.combo !== "" ? root.binds.combo : "not set"
          }
        }

        MouseArea {
          anchors.fill: parent
            // Clicking mid-capture cancels; otherwise starts capture and
            // takes focus so Keys below receives the combo.
          onClicked: {
            if (!root.binds || root.binds.busy) return
            bindPill.capture = !bindPill.capture
            if (bindPill.capture) bindPill.forceActiveFocus()
          }
        }

        // Only meaningful while the pill holds focus, which is exactly the
        // capture window. Modifier-only presses (text == "" and no F-key)
        // are ignored so the user can press the modifiers first.
        Keys.onPressed: function(event) {
          if (!bindPill.capture) return
          event.accepted = true
          if (event.key === Qt.Key_Escape) { bindPill.capture = false; return }
          var mods = []
          if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
          if (event.modifiers & Qt.AltModifier) mods.push("ALT")
          if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
          if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
          // F-keys produce no event.text, so derive them from the keycode
          // BEFORE reading text — and anything that is not a letter, digit
          // or F1–F12 (Tab, arrows, punctuation with mods held) is ignored
          // so the press is never mistaken for a captured combo.
          var keyText = ""
          if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
            keyText = "F" + (event.key - Qt.Key_F1 + 1)
          } else {
            keyText = String(event.text).toUpperCase()
          }
          if (!/^[A-Z0-9]$|^F([1-9]|1[0-2])$/.test(keyText)) return
          if (mods.length === 0) {
            root._bindHint = "add a modifier (e.g. SUPER) — a bare key would be eaten by the game"
            return
          }
          root._bindHint = ""
          bindPill.capture = false
          root.binds.apply(mods.join(" + ") + " + " + keyText)
        }
      }

      // Clear — only when something is set.
      PanelActionButton {
        id: clearBind
        anchors.verticalCenter: parent.verticalCenter
        visible: root.binds && root.binds.combo !== "" && !root.binds.busy
        iconText: "✕"
        tooltipText: "Remove keybind"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: if (root.binds) root.binds.clear()
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      wrapMode: Text.WordWrap
      color: root.binds && root.binds.error !== "" ? Color.urgent : root.foreground
      opacity: root.binds && root.binds.error !== "" ? 1.0 : 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      text: {
        if (!root.binds) return ""
        if (root.binds.error !== "") return root.binds.error
        return root._bindHint
      }
    }
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
