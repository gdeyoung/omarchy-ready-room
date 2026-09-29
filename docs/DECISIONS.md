# Decisions and verified behaviour

Facts established by running the thing, not by reading docs. Each one is load
bearing; if one turns out to be false later, the design above it changes.

## The replay buffer must rename its own argv[0]

`omarchy-capture-screenrecording` gates its **entire entry point** on
`pgrep -f "^gpu-screen-recorder"` and stops recording with
`pkill -SIGINT -f "^gpu-screen-recorder"`. An armed replay buffer running under
the default name therefore means the user's screenrecord keybinding **stops the
replay buffer instead of starting a recording**.

So the buffer is launched as:

```bash
setsid bash -c "exec -a omarchy-ready-room-replay gpu-screen-recorder …"
```

Verified 2026-09-20 against gpu-screen-recorder 6.1.0 on Omarchy (kernel
7.2.5-3-omarchy): with the rename in place, `pgrep -f '^gpu-screen-recorder'`
finds nothing while the buffer runs, and capture still works — a save produced a
6.0 s, 3440x1440, 60 fps h264 mp4. `tests/run.sh` pins this as a regression
test, because the mitigation dies silently if Omarchy ever un-anchors that
pattern.

## Talk to gsr over its own socket, not through a CLI

`-ipc <socket>` speaks newline-delimited JSON, and the reply to `save-replay`
**carries the saved file path**:

```
→ {"id":1,"name":"save-replay","data":{"seconds":5}}
← {"id":1,"result":"ok","data":"…/Replay_2026-09-20_13-04-48.mp4"}
```

That removes the "watch the directory and guess which file appeared" race.
Quickshell ships `Socket` in `Quickshell.Io`, so the QML side talks to gsr
directly. `gsr-cli -ipc <sock> save-replay` is the fallback, and `SIGUSR1` the
last resort (whole buffer, no path returned).

A save requested before the ring buffer holds a keyframe fails cleanly with
`{"result":"error","data":"failed to save the replay"}` — the UI must treat an
early save as a normal outcome, not an error state.

## Socket path

`$XDG_RUNTIME_DIR/omarchy-ready-room/gsr.sock` is 45 bytes here, well inside
the 108-byte `sun_path` limit. `omaclippr` hardcodes `/tmp` claiming the limit
forces it; that isn't true and `/tmp` is a shared namespace. The launcher still
asserts the length and falls back to `/tmp/omarchy-ready-room-$UID/`.

## Never identify our own process by `comm`

`/proc/<pid>/comm` truncates at 15 characters, so `pgrep -x
omarchy-ready-room-replay` matches nothing. Match on the full command line
(`pgrep -f "^omarchy-ready-room-replay "`) — and in the plugin itself, use the
recorded pid + start-time file rather than pattern matching at all.

`SIGTERM` did not stop the recorder within 2 s in testing. Stop it the way the
stock script does, with `SIGINT` (which finalizes the file properly), then
escalate.

## Newly created QML needs a full shell restart

Editing a file the shell has already loaded hot-reloads fine. A **newly created**
plugin or QML file is served from a stale compilation until
`omarchy-restart-shell` — a fixed error keeps being reported at the old line and
column, which is misleading while developing. Restart before believing an error
that no longer matches the source.

## `gc` is a reserved property name in QML

`readonly property var gc: …` fails with `Illegal property name`. The service
handle on the panel is called `gameCenter`.

## Replay buffer memory is mostly fixed cost, not payload

Measured RSS of the armed buffer against its nominal payload
(`kbps x seconds / 8`):

| capture | payload | RSS |
|---|---|---|
| 2560x1440, 26.7 Mbps, 30 s | 100 MB | 285 MB |
| 2560x1440, 53.3 Mbps, 30 s | 200 MB | 379 MB |
| 3440x1440, 35.8 Mbps, 30 s | 134 MB | 433 MB |

The encoder's working set is a large cost that tracks capture resolution, not
buffer length, so a multiplier badly under-counts short buffers — 15 s at
1080p would be quoted at ~50 MB while actually costing several hundred. Both
the preflight and the panel's estimate use **payload + 400 MB**.

## The buffer defaults to 60 fps on a 144 Hz monitor

Matching the monitor's refresh rate doubles the bitrate, and therefore the
memory held for the entire session, plus the encoder load while you are trying
to play. Clips get watched back, not competed in. 60 is the default and
anything up to 240 can be asked for explicitly.

## Restarting the shell twice in quick succession leaves it dead

`omarchy-restart-shell` kills the running instance and starts a new one. Issue
a second restart while the first is still coming up and the new instance exits
with "An instance of this configuration is already running", after which the
original is killed anyway — leaving no shell and no bar. Wait for
`omarchy-shell shell ping` to answer `ok` before restarting again.

## sysfs spells driver names with hyphens, /proc/modules with underscores

The same driver is `xone-gip-gamepad` in `/sys/.../driver` and
`xone_gip_gamepad` in `/proc/modules`. `gc-pad-probe` normalises to
underscores before looking up capabilities.

This is not cosmetic. Keyed on the wrong spelling, every pad falls through to
the default capability set, and the panel then reports a perfectly good Xbox
controller as having no rumble, no battery and no light — which is exactly what
it did until a real controller was connected. Capability tables that fail
*closed* hide their own bugs, so the test suite now asserts that a connected pad
carries a full capability set.

## What an Xbox pad actually reports (measured, dongle connection)

```
driver      xone_gip_gamepad        (sysfs: xone-gip-gamepad)
connection  dongle
battery     level "Full", status "Discharging", percent null
led         /sys/class/leds/gip0.0:white:status
            max_brightness 50, brightness 20, mode present, writable false
caps        rumble true, triggerRumble false, batteryKind level,
            charging false, led true, deadzone false
```

`percent` is null and `status` never says Charging, exactly as the driver's
property list implies. Five segments is the honest rendering.

Rumble over evdev works with no root and no udev rule: `sizeof(ff_effect)` is
48 bytes on x86_64, `EVIOCSFF` is `0x40304580`, and a 70/40 effect for 600ms
returns in 0.68s.

## The Xbox button codes come from the driver, not from the header names

```
A 0x130    B 0x131    X 0x133    Y 0x134
```

`input-event-codes.h` aliases the letters to *positions* using a Nintendo-style
face layout — `BTN_X` is `BTN_NORTH`, `BTN_Y` is `BTN_WEST` — while an Xbox pad
has X in the west position and Y in the north one. Read the positional names,
reason about where the buttons physically sit, and X and Y come out swapped.
That is what the first version of the table did, and the live view lit the
wrong chip.

`xone` settles it by emitting the letter macros directly
(`driver/gamepad.c:406-409`, `input_report_key(dev, BTN_X, ...)`), so the letter
is what the driver means and the position is a red herring. `hid_xpadneo` does
the same.

Worth recording how this was *actually* pinned down, because the first two
attempts were not sound. Asking a person to press A, B, X, Y in order and
reading back the codes only works if they press in that order — the first
capture turned out to be random presses, and the inference drawn from it
("B and Y are crossed") was nonsense built on bad data. The second capture was
in order and gave the right answer, but it was still an answer that depended on
someone else's care. Reading the driver source is independent of all that, and
should have been the first move rather than the third. `tests/run.sh` asserts
the table so the question stays settled.

## Live input reads evdev directly instead of using SDL

SDL's gamepad database normalises pads nobody has heard of, which is real
value. It also means `python-pysdl3`, which is not installed by default — and
on this machine `python-evdev` was installed but built for an older Python than
the running 3.14, so it would not import either. A controller tab whose first
act is to ask for a package install is a tab nobody uses.

Reading evdev directly is about sixty lines of stdlib, exact for anything
following the kernel's gamepad convention, and needs no root: gamepad event
nodes are uaccess-tagged for the logged-in seat. The NDJSON protocol carries a
`backend` field in its hello line, so an SDL backend can be added later without
the panel changing.

The streamer's lifetime is the subscription: the panel starts it when the live
view opens and kills it when the tab closes. No idle process, no stdin
protocol, and a crash costs nothing but the picture until the next open.

## Launch a terminal with execDetached, never with Process

`omarchy-launch-floating-terminal-with-presentation` exec's into a terminal
that has to outlive the call. Run through a Quickshell `Process`, it is a
tracked child and gets torn down with the Process object, so no window ever
appears and nothing is logged — the button simply does nothing.

`Quickshell.execDetached([...])` is the right call for anything whose whole
point is to outlive the widget that started it.

## `omarchy-restart-shell` must be run unconditionally, then verified

Guarding a restart on a ping —

```bash
[[ "$(omarchy-shell shell ping)" == "ok" ]] && omarchy-restart-shell   # WRONG
```

— silently skips the restart whenever the shell is briefly busy, which it often
is right after an edit triggers a plugin reload. The loop that then waits for
`ok` finds the *old* shell still answering and reports success, so the next
test runs against code that was never loaded. This masqueraded as Qt serving a
stale compile, and cost a round of "I fixed it" / "it still doesn't work".

Restart unconditionally and confirm the pid actually changed:

```bash
before=$(pgrep -f 'quickshell -n -p /usr/share/omarchy/shell' | head -1)
omarchy-restart-shell
# then poll until the pid differs and ping answers ok
```

## LED brightness is 0..max_brightness, and max is 50 — not 1

The guide ring on an Xbox pad reports `max_brightness` 50 and sits at 20 by
default. The first blink implementation treated it as a boolean: it blinked
between 0 and 1 and "restored" to 1, which is 2% of full and looks exactly like
a controller that has died. The light stayed like that until it was put back by
hand.

The level the pad had before the blink is now read first and restored at the
end, the blink uses `max_brightness` for the on phase so it is visible across a
desk, and closing the panel mid-blink restores the light rather than leaving it
wherever the timer stopped.

Any sysfs LED: read `max_brightness` before writing `brightness`, and put back
what was there rather than a value that merely means "on".

## The overlay cannot show FPS, and says so

Counting frames requires code inside the game's own process — that is what
MangoHud's Vulkan and OpenGL layers are. A layer-shell window on top of the
game sees compositor frames, not the game's, and any number derived from the
outside would be a guess presented as a measurement.

So the overlay shows what can be read honestly from /proc, /sys and nvidia-smi
(CPU, GPU, VRAM, memory, temperatures, power), and the FPS section explains the
limit and offers to install and configure MangoHud for the one thing it cannot
do. `bin/gc-mangohud` writes the same corner and metric choices into MangoHud's
config inside a marked block, so someone who has tuned their own config does
not lose it.

A metric that cannot be read is omitted from the JSON rather than sent as zero,
so the overlay leaves the row out instead of confidently displaying 0%.

## PathSvg coordinates are literal — the Shape must be scaled as a whole

Every element in `PadShape.qml` is placed by multiplying design coordinates by
`k = width / 300`. `PathSvg` is the exception: its `d` string is taken
literally, so a Shape filling the item drew the body at 1:1 while the buttons
sat `k` times further out. At panel width that put the face buttons outside the
silhouette entirely.

The Shape is therefore laid out at design size with
`transform: Scale { xScale: k; yScale: k }`, and its stroke width is divided by
`k` so the outline does not thicken as the panel widens.

This presented as "the geometry is wrong", which sent the first fix in the
wrong direction — the coordinates were fine. `tools/pad-preview.py` renders the
same data to a PNG through a plain SVG, which is the fastest way to tell a
geometry problem from a rendering one: if the PNG looks right and the panel
does not, the bug is in the QML.

## FileView watches a file, not a directory

Hotplug detection started as `FileView { path: "/dev/input"; watchChanges: true }`
and never fired once. Pointed at a directory, FileView silently does nothing —
`printErrors: false` hid whatever it made of that — so a controller switched on
while the panel was closed stayed invisible until the panel was next opened.

It now uses `inotifywait -m` over `/dev/input` and `/sys/class/power_supply`,
which is what the shell's own plugin registry uses for the same job. Events are
debounced by 400ms, because plugging in one pad creates several nodes in quick
succession. If inotify-tools is missing the process exits, and a 60s poll takes
over rather than the plugin silently never noticing a controller again.

## A service has to populate its own state at startup

The pad inventory was only refreshed when the panel opened, so
`omarchy-shell readyroom status` reported zero controllers while one was
plugged in, and the bar chip could not have shown a low-battery dot. The
service now probes in `Component.onCompleted` alongside session recovery.

The general shape of the bug: state that the *bar chip* depends on cannot be
refreshed only by opening the popout, because the chip is visible when the
popout is not.

## What a Steam Controller actually reports (measured, wired)

```
driver      hid_steam               (sysfs: hid-steam)
connection  usb                     (28de:1102, kernel 7.2.3)
battery     null                    — no power_supply node registered at all
led         null                    — no led_classdev in the driver
caps        rumble false, triggerRumble false, batteryKind none,
            charging false, led false, deadzone false
```

Read off the evdev node's own capability bits rather than by pressing buttons,
which settles the codes without depending on anyone's care with an instruction:

```
KEYS  0x121 0x122 0x130 0x131 0x133 0x134 0x136 0x137 0x138 0x139
      0x13a 0x13b 0x13c 0x13d 0x13e 0x220 0x221 0x222 0x223 0x224 0x225
AXES  0x00 0x01 0x03 0x04 0x10 0x11  ±32767
      0x14 0x15                      0–255
FF    none
```

Three things this confirms, each of which the code had only predicted:

- **`ABS_HAT0X/Y` really is ±32767**, not a −1..1 hat. Reading the range with
  `EVIOCGABS` instead of branching on the axis name is what makes the left
  trackpad work, and a d-pad assumption here would draw one permanently jammed.
- **There are no `EV_FF` bits at all**, so `"rumble": false` is a fact about
  the device rather than caution. A rumble button would fail on every press.
- **The grip paddles arrive as `BTN_GRIPL`/`BTN_GRIPR` (0x224/0x225)** on
  7.2.3, and the older `BTN_GEAR_*` codes are absent. Both spellings stay in
  the map because the kernel version decides which one appears.

The device presents three interfaces and `hid-steam` binds all of them; only
one reports absolute axes. That check is what keeps the emulated mouse and
keyboard out of the inventory, and it held: the probe lists exactly one pad.

## A Steam Controller is taken by whatever opens its hidraw node — usually not Steam

`hid-steam` unregisters the gamepad's evdev node as soon as a program opens the
controller over hidraw, so the pad vanishes from the inventory while remaining
plugged in. This was known. What was wrong was the assumed culprit: the plan
was an empty state reading "Steam is using this controller".

Measured on a machine running a game:

```
lsusb                28de:1102 present
hid_steam            loaded, bound to all four HID interfaces
0003:28DE:1102.000F  input34 + hidraw14      (emulated mouse)
0003:28DE:1102.0010  input35 + hidraw15      (emulated keyboard)
0003:28DE:1102.0011  no input, no hidraw     ← the gamepad, unregistered
0003:28DE:1102.0012  hidraw16, no input
holder of 14/15/16   pid 109162  winedevice.exe
steam client         not running
```

The holder was **Wine's HID service inside a Proton prefix** — Battle.net
launched through `umu-run` — with Steam closed. "Steam is using this
controller" would have been a confident lie on the first machine that ran it.

So the probe reports a `claimed` list and the panel names the process. Finding
it means walking `/proc/*/fd` for the device's hidraw nodes, which costs ~70ms
for ~14k descriptors — affordable once per probe, and the only way to say
something true instead of something plausible.

The detection needs all three of: a HID interface on a claimable driver with no
input node; no pad in the inventory under that USB device; and a process
actually holding one of its hidraw nodes. The third rules out a device nobody
has open, but it does not rule out an idle wireless adapter: the Steam client
holds the adapter for as long as it runs, controller on or not, and hid-steam
registers no input node until one connects. So an adapter entry is worded as
the adapter being in use, never as a controller being on. When no holder can be
identified the panel says nothing extra.

## Steam does not remove the controller, it swaps in an emulated one

The hidraw-claim note above is only half the story. When the holder is a bare
Wine prefix the pad simply vanishes. When it is **Steam**, Steam Input takes
the controller and publishes a uinput Xbox 360 pad in its place, carrying
Valve's own vendor id:

```
pads     Microsoft X-Box 360 pad 0   28de:11ff
         /devices/virtual/input/input51    driver unknown, FF_RUMBLE present
claimed  Steam Controller            28de:1102    holder: steam
```

Both lines come out of the same probe. Connecting them is the whole fix: until
it did, the panel listed a Steam Controller as "Microsoft X-Box 360 pad 0",
subtitled "wired · unknown" — a cable it does not have and a driver it does not
have, about hardware that does not exist.

So a pad under `/devices/virtual/` is flagged `virtual`, reports its connection
as `virtual` rather than the bus it inherited, and gains an `emulates` block
when it can be tied to a claimed device. Vendor alone is not enough: Steam
Input gives *every* pad it emulates Valve's vendor id, an Xbox pad included, so
matching on it would label an Xbox pad's stand-in as the Steam Controller. The
link is drawn only when the holder has `/dev/uinput` open (a uinput device
lives as long as the fd that made it, so a holder without one is publishing
nothing — `winedevice.exe` never is) and exactly one virtual pad and one such
claimed device share the vendor. Otherwise the pad reads "emulated", which is
true, and names nothing.

Two things follow that look like bugs and are not:

- **No silhouette.** `driver` is `unknown`, `familyFor()` returns "", and it
  falls back to the chip grid. That is correct — a drawn pad is a claim about
  what you are holding, and an Xbox outline would be wrong twice over.
- **It rumbles.** The emulated node has `FF_RUMBLE` even though the 2015 pad
  has no `EV_FF` at all. Capabilities come from `DRIVER_CAPS`, a device with no
  driver has no row, and everything defaulted to false — hiding a control that
  works. A driverless pad now has its rumble read from the node's own FF bits.
  The driver table stays authoritative for real hardware, where it encodes
  things a capability bit cannot tell you.

The practical warning: this device reports **Steam's mapping**, not the
driver's — a digital hat at −1..1 where the real pad has a trackpad at ±32767,
no trigger clicks, no pad-touch, no grips. Measuring the Steam Controller
through it documents Steam Input and calls it `hid-steam`. Close Steam first.
