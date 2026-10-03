#!/bin/bash
#
# Ready Room tests. Run from anywhere:  tests/run.sh
#
# These are not unit tests of pure functions — the things most likely to break
# this plugin are assumptions about *other* software, so that is what gets
# pinned. Anything requiring a live Wayland session is skipped when there
# isn't one, so this can also run in CI.
#
set -uo pipefail

PLUGIN_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
PASS=0; FAIL=0; SKIP=0

ok()   { printf '  \033[32mpass\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mskip\033[0m  %s (%s)\n' "$1" "$2"; SKIP=$((SKIP+1)); }

echo "Ready Room tests"
echo

# ---------------------------------------------------------------- static

echo "helpers"
# bin/ holds both bash and python; check each with its own parser rather than
# running bash -n over a python file and calling the syntax error a failure.
for f in "$PLUGIN_DIR"/bin/*; do
  name="$(basename "$f")"
  [[ -x $f ]] || bad "$name is executable"
  case "$(head -1 "$f")" in
    *python*)
      if python3 -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null
      then ok "$name parses (python)"; else bad "$name parses (python)"; fi
      ;;
    *)
      if bash -n "$f" 2>/dev/null; then ok "$name parses (bash)"; else bad "$name parses (bash)"; fi
      ;;
  esac
done

if command -v shellcheck >/dev/null; then
  for f in "$PLUGIN_DIR"/bin/*; do
    case "$(head -1 "$f")" in *python*) continue ;; esac
    name="$(basename "$f")"
    if shellcheck -S warning "$f" >/dev/null 2>&1; then ok "$name shellcheck"
    else bad "$name shellcheck ($(shellcheck -S warning -f gcc "$f" 2>/dev/null | head -1))"; fi
  done
else
  skip "shellcheck" "not installed"
fi

echo
echo "qml"
if command -v qmllint >/dev/null; then
  while IFS= read -r f; do
    name="${f#"$PLUGIN_DIR"/}"
    # qmllint cannot resolve the shell's qs.* modules, so only syntax errors
    # (which it reports with a line:col) count as failures here.
    out="$(qmllint "$f" 2>&1 | grep -E 'Syntax error|Illegal|Expected token' | head -1)"
    if [[ -z $out ]]; then ok "$name"; else bad "$name: $out"; fi
  done < <(find "$PLUGIN_DIR" -name '*.qml' -not -path '*/.git/*')
else
  skip "qmllint" "not installed"
fi

echo
echo "manifest"
if command -v omarchy-plugin-validate >/dev/null || command -v omarchy >/dev/null; then
  if omarchy plugin validate "$PLUGIN_DIR" >/dev/null 2>&1; then ok "validates"
  else bad "validates ($(omarchy plugin validate "$PLUGIN_DIR" 2>&1 | head -1))"; fi
else
  skip "manifest validation" "omarchy not installed"
fi
if jq -e '.barWidget.schema | length > 0' "$PLUGIN_DIR/manifest.json" >/dev/null 2>&1; then
  ok "settings schema present"
else
  bad "settings schema present"
fi

# ---------------------------------------------------------------- live

echo
echo "replay buffer (live)"
if [[ -z ${WAYLAND_DISPLAY:-} ]] || ! command -v gpu-screen-recorder >/dev/null; then
  skip "replay buffer" "needs a Wayland session with gpu-screen-recorder"
else
  # THE regression test.
  #
  # omarchy-capture-screenrecording gates its entry point on
  # `pgrep -f "^gpu-screen-recorder"` and stops with pkill -SIGINT on the same
  # pattern. Our buffer runs under a different argv[0] so the two do not see
  # each other. If Omarchy ever un-anchors that pattern, or our rename stops
  # working, this fails — which is the whole point. Silence here would mean the
  # user's screenrecord key quietly kills their replay buffer.
  if "$PLUGIN_DIR/bin/gc-replay" arm --seconds 5 --quality low >/dev/null 2>&1; then
    if pgrep -f '^gpu-screen-recorder' >/dev/null; then
      bad "armed buffer is invisible to Omarchy's recording detector"
    else
      ok "armed buffer is invisible to Omarchy's recording detector"
    fi

    pidfile="${XDG_RUNTIME_DIR}/gdeyoung-readyroom/replay.pid"
    read -r pid _ <"$pidfile" 2>/dev/null
    if [[ -n ${pid:-} && -d /proc/$pid ]]; then ok "buffer process is tracked by pid file"
    else bad "buffer process is tracked by pid file"; fi

    # comm is truncated to 15 chars by the kernel, so anything matching our
    # renamed process by name must use the full command line.
    if [[ "$(cat /proc/$pid/comm 2>/dev/null)" != "gdeyoung-readyroom-replay" ]]; then
      ok "process name is truncated in comm (pid file is the only safe identity)"
    else
      skip "comm truncation" "kernel no longer truncates comm"
    fi

    "$PLUGIN_DIR/bin/gc-replay" disarm >/dev/null 2>&1
    if ! pgrep -f '^gdeyoung-readyroom-replay ' >/dev/null; then ok "disarm stops the buffer"
    else bad "disarm stops the buffer"; fi
  else
    bad "buffer arms"
  fi
fi

echo
echo "session ownership (live)"
if ! command -v omarchy-toggle-idle >/dev/null; then
  skip "session ownership" "omarchy not installed"
else
  marker="$HOME/.local/state/omarchy/indicators/stay-awake"
  probe="$("$PLUGIN_DIR/bin/gc-session" probe 2>/dev/null)"
  state="$(jq -r '.stayAwake.state' <<<"$probe" 2>/dev/null)"

  case "$state" in
    free|manual|foreign|ours) ok "stay-awake state is one of free/manual/foreign/ours ($state)" ;;
    *) bad "stay-awake state is recognisable (got '$state')" ;;
  esac

  # The three-state rule: a marker with an empty body is the user's own doing
  # and must never be claimed.
  if [[ -f $marker && ! -s $marker ]]; then
    if [[ $state == "manual" ]]; then ok "empty marker reads as the user's manual setting"
    else bad "empty marker reads as manual (got '$state')"; fi
  else
    skip "empty marker case" "marker is not currently empty"
  fi

  if jq -e '.power.available | type == "array"' <<<"$probe" >/dev/null 2>&1; then
    ok "power profiles are enumerated"
  else
    bad "power profiles are enumerated"
  fi
fi

echo
echo "gear probe"
if python3 "$PLUGIN_DIR/tests/gear_probe_check.py" >/dev/null 2>&1; then
  ok "gear probe parser (tests/gear_probe_check.py)"
else
  bad "gear probe parser (tests/gear_probe_check.py)"
fi

echo
echo "controllers"
probe="$("$PLUGIN_DIR/bin/gc-pad-probe" 2>/dev/null)"
if jq -e '.pads | type == "array"' <<<"$probe" >/dev/null 2>&1; then
  ok "pad probe returns an inventory ($(jq '.pads | length' <<<"$probe") connected)"
else
  bad "pad probe returns an inventory"
fi

# Every pad must carry a full capability set, because the UI binds each control
# to one of these and an undefined capability renders as a control that lies.
if jq -e '[.pads[].caps | has("rumble") and has("batteryKind") and has("led")] | all' \
     <<<"$probe" >/dev/null 2>&1; then
  ok "every pad carries a full capability set"
else
  bad "every pad carries a full capability set"
fi

# The MSI motherboard exposes "MS MSI Gaming Controller" for its RGB lighting.
# It is not a gamepad and must never be offered a rumble test.
if jq -e '[.pads[].name | test("MSI"; "i")] | any' <<<"$probe" >/dev/null 2>&1; then
  bad "non-gamepad devices are excluded (MSI lighting matched)"
else
  ok "non-gamepad devices are excluded"
fi

# A controller that is plugged in but claimed by another program must be
# reported as claimed, not simply absent. hid-steam unregisters the evdev node
# whenever something opens the pad's hidraw node, so "no controllers connected"
# is what the panel would otherwise say about a pad sitting on the desk.
if jq -e '.claimed | type == "array"' <<<"$probe" >/dev/null 2>&1; then
  ok "claimed controllers enumerated ($(jq '.claimed | length' <<<"$probe") found)"
else
  bad "claimed controllers enumerated"
fi

# Every claimed entry must name the program holding it. The entry is only
# emitted when a holder was actually found, so a null here means the detection
# fired on something it could not explain — which is how a wireless adapter
# with no controller switched on would wrongly show up as "in use".
if jq -e '[.claimed[] | .holder.pid | type == "number"] | all' <<<"$probe" >/dev/null 2>&1; then
  ok "every claimed controller names the process holding it"
else
  bad "every claimed controller names the process holding it"
fi

# The two lists are disjoint by construction: anything in `claimed` has no
# input node, so a device in both would mean a pad is being offered controls
# and simultaneously reported as unreachable.
if jq -e '. as $d | [$d.claimed[] | .sysfs as $c
          | [$d.pads[] | select(.sysfs | startswith($c))] | length]
          | add // 0 | . == 0' <<<"$probe" >/dev/null 2>&1; then
  ok "claimed and connected controllers do not overlap"
else
  bad "claimed and connected controllers do not overlap"
fi

# The guard that actually matters, because its failure mode is loud and wrong:
# a controller with a working gamepad node must never also be reported as
# claimed. Exercised against this machine's real sysfs tree by handing
# claimed_devices() a pad that sits under the same USB device it found.
python3 - "$PLUGIN_DIR/bin/gc-pad-probe" <<'CLAIMEOF' >/dev/null 2>&1
import importlib.machinery, importlib.util, sys

# Importing the probe must not leave a bin/__pycache__ behind: the helper loop
# above walks bin/* and would try to parse the directory as a shell script.
sys.dont_write_bytecode = True

loader = importlib.machinery.SourceFileLoader("probe", sys.argv[1])
spec = importlib.util.spec_from_loader("probe", loader)
probe = importlib.util.module_from_spec(spec)
loader.exec_module(probe)          # __name__ != "__main__", so nothing runs

claimed = probe.claimed_devices([])
if not claimed:
    sys.exit(2)                    # nothing claimed here; nothing to check

# A pad node under the same USB device is what a working controller looks like.
working = [{"sysfs": c["sysfs"] + "/fake:1.0/input/input99"} for c in claimed]
sys.exit(0 if probe.claimed_devices(working) == [] else 1)
CLAIMEOF
case $? in
  0) ok "a controller with a working node is never reported as claimed" ;;
  2) skip "claimed-vs-working guard" "no claimed controller on this machine" ;;
  *) bad "a controller with a working node is never reported as claimed" ;;
esac

# Steam Input gives every pad it emulates Valve's vendor id, so the link from
# an emulated pad to a claimed controller must only be drawn when it is the
# one possible pairing, and only to a holder that can publish a pad at all.
# Pure logic, so it runs without any controller present.
python3 - "$PLUGIN_DIR/bin/gc-pad-probe" <<'EMUEOF' >/dev/null 2>&1
import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("probe", sys.argv[1])
spec = importlib.util.spec_from_loader("probe", loader)
probe = importlib.util.module_from_spec(spec)
loader.exec_module(probe)

steam = {"name": "Steam", "uinput": True}
wine = {"name": "winedevice.exe", "uinput": False}
sc = lambda holder: {"name": "Steam Controller", "vendor": "28de", "holder": holder}
vpad = lambda: {"virtual": True, "vendor": "28de"}

one = vpad()
assert probe.emulation_for(one, [sc(steam)], [one]) == {"name": "Steam Controller", "holder": "Steam"}
# Two stand-ins (the Steam Controller's and an Xbox pad's): ambiguous.
a, b = vpad(), vpad()
assert probe.emulation_for(a, [sc(steam)], [a, b]) is None
# Held by a process that publishes nothing: the stand-in is someone else's.
assert probe.emulation_for(one, [sc(wine)], [one]) is None
# Real hardware never emulates anything.
real = {"virtual": False, "vendor": "28de"}
assert probe.emulation_for(real, [sc(steam)], [real]) is None
EMUEOF
if [ $? -eq 0 ]; then
  ok "an emulated pad is linked to a controller only when unambiguous"
else
  bad "an emulated pad is linked to a controller only when unambiguous"
fi

# Steam Input takes the real controller over hidraw and publishes an emulated
# Xbox 360 pad in its place, under Valve's own vendor id. Left unlabelled, the
# panel calls a Steam Controller "Microsoft X-Box 360 pad" and looks broken.
if jq -e '[.pads[] | has("virtual")] | all' <<<"$probe" >/dev/null 2>&1; then
  ok "every pad says whether it is virtual ($(jq '[.pads[]|select(.virtual)]|length' <<<"$probe") emulated)"
else
  bad "every pad says whether it is virtual"
fi

# A uinput device is not plugged into anything, so reporting the bus it
# inherited would be a claim about a cable that does not exist.
if jq -e '[.pads[] | select(.virtual) | .connection == "virtual"] | all' \
     <<<"$probe" >/dev/null 2>&1; then
  ok "virtual pads report connection \"virtual\", not a bus"
else
  bad "virtual pads report connection \"virtual\", not a bus"
fi

# Only a virtual pad can stand in for something, and when it does it must name
# both halves — the panel builds a sentence out of them.
if jq -e '[.pads[] | select(.emulates != null)
          | .virtual == true and (.emulates.name | type == "string")] | all' \
     <<<"$probe" >/dev/null 2>&1; then
  ok "an emulated pad names the controller it stands in for"
else
  bad "an emulated pad names the controller it stands in for"
fi

# A pad with no driver row got every capability defaulted to false, including
# rumble on an emulated pad that really has FF_RUMBLE. The node is asked
# instead, so this must agree with the node's own bits.
python3 - "$probe" <<'VIRTEOF' >/dev/null 2>&1
import fcntl, json, os, sys
probe = json.loads(sys.argv[1])
checked = 0
for pad in probe.get("pads", []):
    node = pad.get("node")
    if pad.get("driver") != "unknown" or not node:
        continue
    try:
        fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        continue
    buf = bytearray(16)
    try:
        fcntl.ioctl(fd, (2 << 30) | (16 << 16) | (ord("E") << 8) | (0x20 + 0x15), buf)
    finally:
        os.close(fd)
    real = bool(buf[0x50 // 8] >> (0x50 % 8) & 1)
    if pad["caps"]["rumble"] != real:
        sys.exit(1)
    checked += 1
sys.exit(0 if checked else 2)
VIRTEOF
case $? in
  0) ok "a driverless pad's rumble capability matches its evdev FF bits" ;;
  2) skip "driverless rumble capability" "no driverless pad connected" ;;
  *) bad "a driverless pad's rumble capability matches its evdev FF bits" ;;
esac

if jq -e '.dongles | type == "array"' <<<"$probe" >/dev/null 2>&1; then
  ok "dongles enumerated ($(jq '.dongles | length' <<<"$probe") found)"
else
  bad "dongles enumerated"
fi

# The button map comes from xone's driver/gamepad.c, which emits the letter
# macros directly: BTN_A/BTN_B/BTN_X/BTN_Y = 0x130/0x131/0x133/0x134.
#
# input-event-codes.h aliases those letters to *positions* in a Nintendo-style
# layout (BTN_X is BTN_NORTH), and an Xbox pad has X in the west position — so
# reasoning from where the buttons physically sit transposes X and Y, which is
# exactly the bug this pins.
if python3 - "$PLUGIN_DIR/bin/gc-pads" <<'PYEOF' >/dev/null 2>&1
import sys, re
src = open(sys.argv[1]).read()
block = re.search(r"BUTTONS = \{(.*?)\}", src, re.S).group(1)
want = {"0x130": "a", "0x131": "b", "0x133": "x", "0x134": "y"}
got = dict(re.findall(r"(0x1[0-9a-f]{2}):\s*\"(\w+)\"", block))
sys.exit(0 if all(got.get(k) == v for k, v in want.items()) else 1)
PYEOF
then ok "button map matches the xone driver's BTN_A/B/X/Y"
else bad "button map matches the xone driver (X/Y likely transposed)"; fi

# ff_effect is 48 bytes on x86_64 and the ioctl number is derived from it, so a
# wrong struct means rumble silently does nothing on some machines.
size="$(python3 -c "
import ctypes, sys
sys.argv = ['x']
src = open('$PLUGIN_DIR/bin/gc-rumble').read().split('def clamp_percent')[0]
exec(src)
print(ctypes.sizeof(FFEffect))
" 2>/dev/null)"
if [[ "$size" == "48" ]]; then ok "ff_effect struct is 48 bytes"
else bad "ff_effect struct is 48 bytes (got '$size')"; fi

echo
echo "overlay"
stats="$("$PLUGIN_DIR/bin/gc-stats" --interval 0.3 2>/dev/null | head -2 | tail -1)"
if jq -e '.t == "stats"' <<<"$stats" >/dev/null 2>&1; then
  ok "stats helper emits a sample"
else
  bad "stats helper emits a sample"
fi

# A metric that cannot be read must be absent, not zero — the overlay leaves
# the row out rather than confidently showing 0%.
if jq -e 'has("cpu") and (.cpu.percent | type == "number")' <<<"$stats" >/dev/null 2>&1; then
  ok "cpu load is a number"
else
  bad "cpu load is a number"
fi
if jq -e 'has("ram") and (.ram.totalMb > 0)' <<<"$stats" >/dev/null 2>&1; then
  ok "memory is reported"
else
  bad "memory is reported"
fi

# MangoHud config writing, into a throwaway config dir.
tmp="$(mktemp -d)"
if XDG_CONFIG_HOME="$tmp" "$PLUGIN_DIR/bin/gc-mangohud" --position bottom-left \
     --metrics cpu,gpu,temps </dev/null >/dev/null 2>&1; then
  conf="$tmp/MangoHud/MangoHud.conf"
  if grep -q '^position=bottom-left' "$conf" 2>/dev/null && grep -q '^fps' "$conf" 2>/dev/null; then
    ok "mangohud config is written with the chosen corner"
  else
    bad "mangohud config is written with the chosen corner"
  fi
  # A second run must not duplicate the block.
  XDG_CONFIG_HOME="$tmp" "$PLUGIN_DIR/bin/gc-mangohud" --position top-left \
    --metrics cpu </dev/null >/dev/null 2>&1
  if [[ "$(grep -c 'begin ready-room' "$conf" 2>/dev/null)" == "1" ]]; then
    ok "rewriting mangohud config replaces its block rather than stacking"
  else
    bad "rewriting mangohud config replaces its block rather than stacking"
  fi
else
  bad "mangohud config is written"
fi
rm -rf "$tmp"

# Structural checks on every controller family in PadArt.js: parts inside the
# canvas, keys the streamer actually emits, and face buttons that agree with
# the button map. See tests/art_check.py — it runs standalone too, which is
# what you want while adding a family.
art_out="$(python3 "$PLUGIN_DIR/tests/art_check.py" 2>&1)"
if [[ $? -eq 0 ]]; then
  ok "controller art is structurally sound"
else
  while IFS= read -r line; do [[ -n $line ]] && bad "art: $line"; done <<<"$art_out"
fi

echo
printf 'pass %d · fail %d · skip %d\n' "$PASS" "$FAIL" "$SKIP"
[[ $FAIL -eq 0 ]]
