# Adding a controller

This is the procedure for teaching Ready Room about a pad it doesn't know:
what it can do, what its buttons are called, and what it looks like.

It is written to be followed with the controller **in your hands and plugged
in**. Every step that involves the hardware says so, and none of the facts
below should be taken from a datasheet, a wiki, or a language model's memory
when the device itself is right there and can be asked.

Four things happen, in this order, and the order matters — each step's output
is the next step's input:

1. **Identify the driver** — what the kernel calls it.
2. **Measure the buttons and axes** — what codes it actually emits.
3. **Declare its capabilities** — what controls the panel should offer.
4. **Draw it** — the silhouette.

You can stop after step 3 and have a perfectly good result: the pad appears
with battery, rumble and a live chip grid. Step 4 is what makes it pretty.

---

## The rule this whole plugin is built on

**A control that cannot work is absent, not disabled. A number that cannot be
read honestly is not shown.**

Concretely: if a driver reports battery in five buckets, draw five segments —
do not scale it to a percentage. If it cannot report charging, do not show a
charging icon. If a feature needs a udev rule that isn't installed, hide the
control and offer the rule. The panel should never imply the hardware can do
something it can't.

This bites hardest on capability tables, because a wrong entry fails *closed*:
the pad quietly loses rumble and battery, everything still "works", and nobody
notices. `tests/run.sh` asserts that a connected pad carries a full capability
set for exactly this reason.

---

## 1. Identify the driver

Plug the controller in and ask the system, rather than assuming:

```bash
# Is it here at all, and what claimed it?
bin/gc-pad-probe | jq

# The raw view, if the probe doesn't see it
cat /proc/bus/input/devices          # look for your pad by name
lsusb | grep -i valve                # or whatever vendor
ls -l /sys/class/input/event*/device/device/driver   # who owns each node
```

Two spellings of the same driver exist and they are not interchangeable:

| Source | Spelling |
|---|---|
| `/sys/.../driver` | hyphens — `hid-steam`, `xone-gip-gamepad` |
| `/proc/modules`, `lsmod` | underscores — `hid_steam`, `xone_gip_gamepad` |

`gc-pad-probe` normalises to **underscores**, and every table in this codebase
is keyed that way. Keying on the hyphenated form silently drops the pad to the
default capability set — that bug shipped once already and made a working Xbox
controller report no rumble, no battery and no light.

**If the probe doesn't list your pad at all**, its detection needs widening
first: `is_gamepad()` in `bin/gc-pad-probe` accepts anything with a `js*`
handler, or a pad-like name from a vendor in `PAD_VENDORS`. Add the vendor id
there (Valve is `28de`) rather than loosening the name match — an MSI
motherboard exposes "MS MSI Gaming Controller" for its RGB lighting and must
not be offered a rumble test.

**Before widening anything, check the pad has not been taken.** Some drivers
hand the controller to whichever program opens its hidraw node first and
unregister the evdev node while that lasts — `hid-steam` does this by design,
for Steam and equally for Wine/Proton's HID service. A pad that is plugged in
with no `event*` node is a *claimed* pad, not an undetected one, and widening
`is_gamepad()` will not bring it back. `gc-pad-probe` reports these separately:

```bash
bin/gc-pad-probe | jq '.claimed'
# [ { "name": "Steam Controller", "holder": { "pid": 109162,
#     "name": "winedevice.exe" } } ]
```

If your driver behaves this way, add it to `CLAIMABLE_DRIVERS`. If it does not,
leave it out — the detection is deliberately narrow, and a driver listed there
that never actually yields its node can only produce false alarms.

---

## 2. Measure the buttons and axes

**Do not take button codes from a header file.** `input-event-codes.h` aliases
the letters to *positions* in a Nintendo-style layout — `BTN_X` is
`BTN_NORTH`, `BTN_Y` is `BTN_WEST` — while an Xbox pad has X in the west
position. Reason from where the buttons physically sit and you will transpose
them. That happened here, and the live view lit the wrong chip.

Two sources are trustworthy, in this order:

**a. The driver source.** Authoritative, and doesn't depend on anyone pressing
the right button:

```bash
# The driver names the buttons it reports
curl -s https://raw.githubusercontent.com/torvalds/linux/master/drivers/hid/hid-steam.c |
  grep -nE 'input_report_key|input_set_capability|input_set_abs_params'
```

**b. The hardware.** Confirms the source and catches per-device surprises:

```bash
# Print the raw code of each button as it is pressed
python3 - /dev/input/eventN <<'EOF'
import os, struct, select, sys, time
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NONBLOCK)
end = time.monotonic() + 30
while time.monotonic() < end:
    r, _, _ = select.select([fd], [], [], 0.2)
    if not r: continue
    data = os.read(fd, 24 * 64)
    for off in range(0, len(data) - 23, 24):
        _, _, t, c, v = struct.unpack_from("qqHHi", data, off)
        if t == 1 and v == 1:
            print("button 0x%03x (%d)" % (c, c), flush=True)
        elif t == 3 and abs(v) > 3000:
            print("axis    0x%02x = %d" % (c, v), flush=True)
EOF
```

Press one button at a time, slowly, and write down which is which. A caution
learned the hard way: asking someone else to "press A, B, X, Y in order" and
reading back the codes is only as good as their care with the instruction — the
first attempt here was random presses, and the conclusion drawn from it was
nonsense. Prefer the driver source; use the hardware to confirm it.

Then add what you measured to `bin/gc-pads`:

- `BUTTONS` maps code → name. The names are yours to choose, but they have to
  match the `key` values your art uses, and `tests/art_check.py` enforces that.
- `AXES` maps code → name. Sticks normalise to −1..1, triggers to 0..1.
- `abs_info()` reads each axis's real range with `EVIOCGABS`, so you do not
  need to hardcode ranges — but do check the values that come out make sense.

Verify by watching it:

```bash
bin/gc-pads /dev/input/eventN --hz 30 | head -20
```

Every press should flip exactly the field you expect, and nothing else.

---

## 3. Declare its capabilities

In `bin/gc-pad-probe`, add an entry to `DRIVER_CAPS` keyed by the underscored
driver name:

```python
"hid_steam": {
    "rumble": True,            # FF_RUMBLE through evdev — check the driver
    "triggerRumble": False,    # separate trigger motors, reachable via evdev
    "batteryKind": "level",    # "percent" | "level" | "none"
    "charging": False,         # does STATUS ever say Charging?
    "led": False,              # an LED class device we can write
    "deadzone": False,         # keep False: no Linux driver exposes this
},
```

Each field is a promise the UI relies on, so check each one against the driver
rather than guessing:

- **rumble** — does the driver call `input_set_capability(dev, EV_FF, FF_RUMBLE)`?
  If yes, `bin/gc-rumble` already works unmodified; it is plain evdev and needs
  no root, because gamepad nodes are uaccess-tagged for the logged-in seat.
- **batteryKind** — `percent` only if the driver registers
  `POWER_SUPPLY_PROP_CAPACITY`. If it registers only
  `POWER_SUPPLY_PROP_CAPACITY_LEVEL`, it is `level` and gets five segments. A
  wired pad usually has no battery at all; the probe already forces `none` when
  no `power_supply` node is found.
- **charging** — only if `STATUS` can actually say `Charging`. `xone` never
  does, so an Xbox pad on the dongle shows no charging state.
- **led** — only for an LED class device we can write. The probe checks
  writability separately and the panel hides the control until a udev rule
  makes it writable, so `True` here means "it exists", not "we can use it".

Also update `connection_for()` if the pad reports over something the existing
mapping doesn't cover, and add the driver to the `drivers` list near the bottom
of `gc-pad-probe` so it shows in the empty state ("Drivers loaded: …").

Check your work:

```bash
bin/gc-pad-probe | jq '.pads[0] | {driver, connection, battery, caps}'
```

Everything in `caps` should be defensible by pointing at a line in the driver.

---

## 4. Draw it

Art lives in `controllers/PadArt.js` as one entry per family. **The renderer
draws whichever parts a family declares**, so a pad with two trackpads and one
stick needs no QML changes:

```js
steam: {
  label: "Steam Controller",
  drivers: ["hid_steam"],
  body: "M ... Z",              // outline in a 300x200 design space
  elements: {
    trackpads: [ { key: "lpadclick", axisX: "lpx", axisY: "lpy", x: 80, y: 80, r: 26 } ],
    sticks:    [ { key: "ls", axisX: "lx", axisY: "ly", x: 96, y: 132, r: 18, travel: 8 } ],
    faceButtons: [ /* A/B/X/Y with x,y,r,label */ ],
    grips:     [ { key: "lgrip", x: 40, y: 168, w: 26, h: 10 } ],
    bumpers:   [ ... ], triggers: [ ... ], smallButtons: [ ... ]
  }
}
```

Supported kinds: `sticks`, `trackpads`, `dpad`, `faceButtons`, `bumpers`,
`triggers`, `grips`, `smallButtons`. A trackpad takes an optional
`round: false` for a squarer pad and an optional `touchKey` so the finger dot
only appears while a finger is actually on it.

### Render it — do not place parts by eye in code

```bash
tools/pad-preview.py steam /tmp/steam.png
```

That reads the same `PadArt.js` the plugin does and draws it through a plain
SVG, in about a second. Iterate there until it looks right, *then* restart the
shell. The first version of the Xbox art was placed by eye and had the d-pad
straddling the bottom edge and the right stick under the X button; both were
obvious in the PNG and invisible in the source.

This also separates the two failure modes cleanly:

> If the PNG looks right and the panel looks wrong, the bug is in the
> rendering, not the coordinates.

That exact case has happened: `PathSvg` takes its coordinates literally while
every other element is multiplied by `k = width / 300`, so the body drew at 1:1
and the buttons landed outside it. The Shape is now scaled as a whole.

### Then check it structurally

```bash
python3 tests/art_check.py
```

This catches what the eye doesn't: a part outside the canvas, a driver name
with hyphens, face buttons transposed against the button map, and — the useful
one — **art that lights a key `gc-pads` never emits**. If you draw a grip with
`key: "lgrip"` and the streamer has no `lgrip`, that part can never light up,
and this test says so.

---

## 5. Verify on the hardware

```bash
omarchy plugin validate ~/.config/omarchy/plugins/gdeyoung.readyroom
tests/run.sh
omarchy-restart-shell            # new QML files need a full restart
```

Then, with the controller connected:

| | |
|---|---|
| Pads tab lists it | name, connection and driver all correct |
| Battery | matches reality — and is absent if the pad has none |
| `Test rumble` | present only if the driver has FF_RUMBLE, and actually buzzes |
| `Show live input` | every button lights the right part; no part lights on its own |
| Sticks and pads | rest at centre, reach the edges, return to centre |
| Triggers | fill smoothly from 0 to full |
| Unplug it mid-stream | the pad disappears and the panel says so, rather than freezing |

A note on restarting: `omarchy-restart-shell` takes ~15s to answer IPC again,
and issuing a second restart while the first is still coming up leaves you with
**no shell and no bar**. Run it once, then wait for
`omarchy-shell shell ping` to answer `ok`.

---

## Notes for specific families

### Steam Controller (Valve, 2015)

See `docs/STEAM-CONTROLLER.md` for what the `hid-steam` driver exposes, the
layout, and the parts of this plugin that assume a two-stick pad.

Its capabilities, button codes and axis ranges are confirmed against hardware;
its silhouette and axis directions are not. It is also the reason
`CLAIMABLE_DRIVERS` exists: this pad disappears whenever a game is running, and
the empty state names the program holding it.
