# Steam Controller (2015)

Ready Room ships support for the original Steam Controller — capabilities,
button map and silhouette. It was written from the kernel driver, and the
protocol half of it has since been checked against a device.

This document is what that support is based on, what to check first, and the
handful of places where this controller breaks assumptions that a two-stick pad
lets you get away with. Read `ADDING-A-CONTROLLER.md` for the general
procedure; this is the device-specific half.

> **Status: capabilities, buttons and axes verified** on a wired 28de:1102,
> kernel 7.2.3, by reading the evdev node's own capability bits. Every code and
> range in the tables below came back exactly as the driver predicted, so the
> tables are now descriptions rather than predictions.
>
> **Still unverified: the silhouette and the axis directions.** Those need
> someone to look at the pad and push the sticks, which reading capability bits
> cannot do. The art has never been compared to a real controller.
>
> If the hardware disagrees with this file, **the hardware is right** — fix the
> code and fix this file.

---

## Start here

```bash
# 1. Is it seen, and as what?
bin/gc-pad-probe | jq

# 2. Does live input work, and is every part mapped?
bin/gc-pads /dev/input/eventN --hz 30

# 3. Does the drawing match the hardware in your hands?
tools/pad-preview.py steam /tmp/steam.png
```

The first command answering with `"driver": "hid_steam"` and a sensible
capability set means steps 1–3 of the general procedure are already done. The
remaining work is confirming them and adjusting the art.

---

## What the driver exposes

Module `hid_steam` (sysfs: `hid-steam`). Valve's vendor id is `28de`; the wired
pad is `0x1102` and the wireless dongle is `0x1142`.

### Buttons

| Control | Macro | Code | Our name |
|---|---|---|---|
| A (bottom) | `BTN_A` | 0x130 | `a` |
| B (right) | `BTN_B` | 0x131 | `b` |
| X (left) | `BTN_X` | 0x133 | `x` |
| Y (top) | `BTN_Y` | 0x134 | `y` |
| Left bumper | `BTN_TL` | 0x136 | `lb` |
| Right bumper | `BTN_TR` | 0x137 | `rb` |
| Left trigger full-pull click | `BTN_TL2` | 0x138 | `lt2` |
| Right trigger full-pull click | `BTN_TR2` | 0x139 | `rt2` |
| Back | `BTN_SELECT` | 0x13a | `view` |
| Forward / Start | `BTN_START` | 0x13b | `menu` |
| Steam | `BTN_MODE` | 0x13c | `guide` |
| Stick click | `BTN_THUMBL` | 0x13d | `ls` |
| **Right pad click** | `BTN_THUMBR` | 0x13e | `rs` |
| Left pad touch | `BTN_THUMB` | 0x121 | `lpadtouch` |
| Right pad touch | `BTN_THUMB2` | 0x122 | `rpadtouch` |
| Left pad click, by quadrant | `BTN_DPAD_UP/DOWN/LEFT/RIGHT` | 0x220–0x223 | `padup`/`paddown`/`padleft`/`padright` |
| Left grip paddle | `BTN_GRIPL` (≥6.17) / `BTN_GEAR_DOWN` (≤6.16) | 0x224 / 0x150 | `lgrip` |
| Right grip paddle | `BTN_GRIPR` (≥6.17) / `BTN_GEAR_UP` (≤6.16) | 0x225 / 0x151 | `rgrip` |

Both grip spellings are in `bin/gc-pads`, so the kernel version doesn't matter.

Note `BTN_THUMBR` means "right stick click" on an Xbox pad and "right trackpad
click" here — same code, different thing. That is fine because the art decides
what a key lights, but it is why the art must be per family rather than the
button names being per family.

### Axes

| Control | Macro | Code | Range | Our name |
|---|---|---|---|---|
| Analog stick | `ABS_X` / `ABS_Y` | 0x00 / 0x01 | ±32767 | `lx` / `ly` |
| **Left trackpad** | `ABS_HAT0X` / `ABS_HAT0Y` | 0x10 / 0x11 | **±32767** | `hx` / `hy` |
| **Right trackpad** | `ABS_RX` / `ABS_RY` | 0x03 / 0x04 | ±32767 | `rx` / `ry` |
| Left analog trigger | `ABS_HAT2Y` | 0x15 | **0–255** | `lt` |
| Right analog trigger | `ABS_HAT2X` | 0x14 | **0–255** | `rt` |

Two traps here, both already handled:

- **`ABS_HAT0` is not a d-pad on this controller.** On most pads it is a
  three-position hat with a −1..1 range; here it is the left trackpad with a
  ±32767 range. `bin/gc-pads` reads each axis's real range with `EVIOCGABS` and
  normalises from that, rather than from the axis's name, so both work with no
  per-family branch. Any code you add that assumes HAT0 is a d-pad will draw a
  permanently jammed one.
- **The trigger axes are `ABS_HAT2Y`/`ABS_HAT2X`, not `ABS_Z`/`ABS_RZ`**, and
  the pairing is **Y = left, X = right**, which is the opposite of what the
  names suggest. Both codes map to `lt`/`rt`, and an axis whose reported range
  is empty is ignored so the Xbox codes don't collide with these.

### Battery

Only over the **wireless dongle** — a wired pad registers no `power_supply` at
all, and the probe correctly reports no battery for it.

When present it is a **real percentage** (`POWER_SUPPLY_PROP_CAPACITY`), unlike
an Xbox pad's five buckets, so the panel shows a number. The node is named
`steam-controller-<serial>-battery`.

There is **no charging state** — `POWER_SUPPLY_PROP_STATUS` is registered only
for the 2026 controller. The pad runs on two AA cells and doesn't charge, so
`"charging": false` is correct rather than conservative.

### Rumble — there isn't any

`CONFIG_STEAM_FF` is gated on the Deck and the 2026 controller:

```c
if (steam->quirks & (STEAM_QUIRK_DECK | STEAM_QUIRK_IBEX)) {
        input_set_capability(input, EV_FF, FF_RUMBLE);
        ...
}
```

So the 2015 pad has no `EV_FF` bit and `EVIOCSFF` fails. Its haptics are the
two trackpad actuators, driven over hidraw by the driver's internal
`steam_haptic_pulse()` — nothing exposes that to userspace.

`"rumble": false` is therefore the honest answer, and the Pads tab will show no
rumble button for this controller. **Do not "fix" this by adding one.** If you
want buzz, that is a hidraw project (the driver itself points at
[steamctrl](https://github.com/rodrigorc/steamctrl)), and it belongs behind its
own capability flag.

### No LEDs

No `led_classdev` anywhere in the driver. The guide-button-light section of the
Pads tab will not appear, and the udev rule is irrelevant to this pad.

---

## Three things that will bite

### 1. The gamepad node is one of three, all on `hid-steam`

The controller presents emulated mouse and keyboard interfaces alongside the
real pad, and the driver binds all of them. **`driver == hid_steam` is not
enough to identify the gamepad.** `bin/gc-pad-probe` also requires the node to
report absolute axes, which the mouse and keyboard nodes don't.

If the probe ever lists a Steam Controller twice, or offers a rumble test for
something that isn't a pad, this is why.

### 2. The stick and the left pad are multiplexed

They share one pair of fields in the HID report, and a bit selects which is
being reported:

```c
input_report_abs(input, lpad_touched ? ABS_HAT0X : ABS_X, x);
if (lpad_touched && !lpad_and_joy) { /* stick forced to centre */ }
```

So **touching the left pad zeroes the stick readout**, and lifting off snaps the
pad back to centre. The live view cannot show both moving at once — that is the
hardware's report format, not a bug in the plugin. If you see the stick jump to
centre when a thumb lands on the pad, that is correct behaviour.

This is also why the left pad's art uses `touchKey: "lpadtouch"`: the finger dot
only appears while a finger is actually down, instead of sitting at the centre
pretending to be a reading.

### 3. Any hidraw client takes the controller away — not just Steam

When something opens the device through hidraw, the driver **unregisters the
evdev node entirely** so that program can drive the pad itself. The controller
vanishes from the Pads tab and comes back when the program exits.

Steam is the obvious culprit and the one this section used to name. It is not
the only one, and on a machine that is actually gaming it is often not the one:

> Observed on a wired pad, kernel 7.2.3: the holder was **`winedevice.exe`**,
> Wine's HID service inside a Proton prefix, with the Steam client not running
> at all. Battle.net had been launched through `umu-run`, and Wine enumerated
> the controller and opened its hidraw nodes so the Windows game could see it.

This is why the Pads tab **names the program** rather than asserting Steam. The
probe reports a `claimed` list alongside `pads`, and the empty state reads
"Steam Controller is in use — it is open in winedevice.exe". Hardcoding "Steam
is using this controller" would have been wrong on the first machine that ran
it.

#### The pad does not always vanish — sometimes it is replaced

When the holder is **Steam** rather than a bare Wine prefix, the Pads tab does
not empty. Steam Input publishes a **uinput virtual Xbox 360 pad** in the real
controller's place, under Valve's own vendor id:

```
pads     Microsoft X-Box 360 pad 0   28de:11ff
         /devices/virtual/input/input51   driver: unknown
claimed  Steam Controller            28de:1102   holder: steam
```

Both facts are in the same probe output and the panel used to connect neither,
so a Steam Controller appeared in the list calling itself an Xbox 360 pad —
"wired · unknown" underneath it, both halves of which are untrue of a device
with no cable and no driver.

A pad on `/devices/virtual/` is now flagged `virtual`, its connection reads
`virtual` rather than a bus it merely inherited, and when a claimed device
can be tied to it the pad carries an `emulates` block naming it. The row then
reads "emulated by Steam" and explains itself in place. The tie needs more
than a shared vendor id, since Steam Input stamps Valve's on every pad it
emulates: the holder must have `/dev/uinput` open and the pairing must be the
only one possible. See `docs/DECISIONS.md`.

Two consequences worth knowing:

- **It gets no silhouette, deliberately.** Its driver is `unknown`, so
  `familyFor()` returns nothing and it falls back to the chip grid. Drawing an
  Xbox outline would be a claim about what is in your hands, and what is in
  your hands is a Steam Controller.
- **It really does rumble**, even though the 2015 pad does not. The emulated
  node carries `FF_RUMBLE`; Steam Input translates it to the trackpad
  actuators. A pad with no row in `DRIVER_CAPS` now has its rumble read from
  the node's own FF bits rather than defaulted to false.

The buttons it reports are Steam Input's translation, not the hardware: a
digital hat on `ABS_HAT0X/Y` at −1..1 where the real pad has a trackpad at
±32767, no trigger clicks, no pad-touch bits and no grip paddles. **Do not
measure the Steam Controller through this device** — close Steam first, or you
will be documenting Steam's mapping and calling it the driver's.

The detection requires three things to agree, because the expensive failure is
a confident wrong answer rather than silence:

| Signal | Why |
|---|---|
| A HID interface on a claimable driver with **no input node** | Necessary, but weak on its own — `hid-steam` leaves one behind even while the pad works |
| **No pad in the live inventory** under that USB device | What actually stops a working controller being called claimed |
| A process **actually holding** one of its hidraw nodes | Rules out a device nobody has open. Not an idle adapter, though: Steam holds the wireless adapter whether or not a controller is on, so an adapter entry only ever says the adapter is in use |

The third is what keeps the message honest, and it is why the holder is found
by walking `/proc/*/fd` (about 70ms for ~14k descriptors) rather than guessed
at. If the holder belongs to another user we cannot read its `comm`, so the
panel falls back to "another program" rather than inventing a name.

A related note: opening the gamepad node disables "lizard mode", the
controller's built-in mouse/keyboard emulation. So while the live input view is
open, the right pad stops acting as a mouse. Closing the view restores it. That
is the driver's behaviour, not something the plugin chose, but it is worth
knowing before someone reports it as a bug.

---

## The silhouette

`controllers/PadArt.js` has a `steam` family, drawn from Valve's documented
layout: two large circular trackpads across the top, the single analog stick
low on the left, the ABXY diamond low on the right, Steam button centred with
Back and Forward flanking it, bumpers and triggers on the shoulders, and the
two rear paddles marked on the handles.

**It has never been compared to a real controller.** Render it and hold the pad
next to it:

```bash
tools/pad-preview.py steam /tmp/steam.png
```

Things most likely to need nudging, in rough order of likelihood:

1. **Back and Forward** — their vertical offset relative to the Steam button
   came from product photos, not documentation.
2. **Trackpad size relative to the body.** The pads are 40 mm on a ~152 mm wide
   controller; if they look too small or too large next to the real thing, scale
   `r` rather than moving things around it.
3. **Handle splay.** The real handles are longer and angled further out than an
   Xbox pad's. The outline may be too timid.
4. **Grip paddle markers** are a convention, not a likeness — they are on the
   back of the handles and invisible from the front. They exist so a press
   lights something.

After editing, `python3 tests/art_check.py` verifies the parts stay on the
canvas and that every key the art lights is one `gc-pads` actually emits.

---

## Checklist for the first run on hardware

Plug it in wired first, then try the dongle. Ticked boxes were confirmed on a
wired 28de:1102 on kernel 7.2.3; unticked ones still need someone holding the
pad.

- [x] `bin/gc-pad-probe` lists exactly **one** pad, named "Steam Controller"
      (wired) — not three. The mouse and keyboard interfaces are correctly
      filtered out by the "reports absolute axes" check
- [x] `driver` reads `hid_steam`, `connection` reads `usb` wired
- [ ] Dongle: `connection` reads `dongle`, a battery percentage, no charging icon
- [x] Wired: no battery shown (`hid-steam` registers no `power_supply` for it)
- [x] No rumble button — the evdev node carries **no `EV_FF` bits at all**,
      confirming the driver gates force feedback on Deck/Ibex
- [x] No LED section
- [x] Every button and axis in the tables above is present on the node, with the
      ranges claimed: `ABS_HAT0X/Y` at ±32767 (the left trackpad, **not** a
      d-pad) and the triggers at 0–255
- [x] Grip paddles report as `BTN_GRIPL`/`BTN_GRIPR` (0x224/0x225) on 7.2.3, as
      expected for ≥6.17. The `BTN_GEAR_*` codes are absent, which is why both
      spellings stay in the map
- [x] A program opening the pad over hidraw makes it vanish, and the Pads tab
      names that program instead of saying "no controllers connected"
- [x] Unplug (or lose the node) mid-stream: `gc-pads` emits
      `{"t":"error","code":"gone"}` and exits rather than hanging
- [ ] Live input: every button lights the right part. Check ABXY especially,
      and confirm **X is the left button and Y is the top one**
- [ ] Both trackpads: the dot follows your finger and disappears when you lift
      off, rather than sitting at centre
- [ ] The stick reads centre while the left pad is touched (expected — see above)
- [ ] Triggers fill smoothly 0→full, and the full-pull click lights separately
- [ ] The silhouette matches the pad held next to it

If any of these fail, `docs/ADDING-A-CONTROLLER.md` §2 shows how to dump raw
codes from the device — and the driver source is the tiebreaker.

---

## What could not be confirmed from source

Carried over from the research honestly, so nobody takes them as settled:

- The exact kernel version that adds gyro/accel for the 2015 pad. It is absent
  through 7.2 and present on master, so a motion panel should detect the
  "Steam Controller Motion Sensors" node rather than assume a version.
  (7.2.3 confirmed absent: no motion node appears.)
- The sign convention of the Y axes against real hardware. The driver negates
  raw Y; nobody has watched a stick move. **If up and down are inverted in the
  live view, this is the first place to look** — `normalise()` in `bin/gc-pads`
  negates `ly`/`ry`, and the trackpad axes may need the same treatment or may
  already be correct. Reading capability bits cannot settle this; it needs a
  thumb on the stick.
- Whether the silhouette resembles the hardware at all.
- How granular the wireless battery percentage actually is, and whether the
  dongle's `connection` really reports as `dongle` — neither has been seen.
- Whether a dongle with **no controller switched on** presents HID interfaces
  without input nodes, the way a claimed wired pad does. If it does, the
  `claimed` detection's third signal (a process holding hidraw) is the only
  thing stopping it being announced as "in use", and that signal is load
  bearing rather than belt-and-braces. Worth checking with a dongle in hand.
- Behaviour over Bluetooth — `hid-steam` has no BLE id for the 2015 pad, so it
  is probably not handled by this driver at all.
