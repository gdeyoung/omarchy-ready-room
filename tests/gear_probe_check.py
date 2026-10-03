#!/usr/bin/env python3
"""Unit tests for bin/gc-gear-probe.parse_dump — synthetic upower dumps.

Run: python3 tests/gear_probe_check.py
Exits non-zero on the first failure. Pure stdlib, no live UPower needed.
"""
import importlib.machinery
import importlib.util
import json
import os
import sys

sys.dont_write_bytecode = True  # keep bin/ free of __pycache__ for run.sh's walker

HERE = os.path.dirname(os.path.realpath(__file__))
PROBE = os.path.join(HERE, "..", "bin", "gc-gear-probe")

loader = importlib.machinery.SourceFileLoader("gear_probe", PROBE)
spec = importlib.util.spec_from_loader("gear_probe", loader)
probe = importlib.util.module_from_spec(spec)
loader.exec_module(probe)  # __name__ != "__main__", so nothing executes

failures = []


def check(name, cond, extra=""):
    if cond:
        print(f"  pass  {name}")
    else:
        print(f"  FAIL  {name}  {extra}")
        failures.append(name)


def rows_of(text):
    return probe.parse_dump(text)


# ---------------------------------------------------------------- fixtures

LAPTOP = """Device: /org/freedesktop/UPower/devices/battery_BAT1
  native-path:          BAT1
  model:                SR Real Battery
  state:               fully-charged
  percentage:          99%
"""
LINE = """Device: /org/freedesktop/UPower/devices/line_power_ADP1
  native-path:          ADP1
"""
DISPLAY = """Device: /org/freedesktop/UPower/devices/DisplayDevice
  native-path:          display-device
  percentage:          99%
"""
MOUSE = """Device: /org/freedesktop/UPower/devices/mouse_hidpp_battery_0
  native-path:          hidpp_battery_0
  model:                MX Master 3S
  state:               discharging
  percentage:          87%
"""
MOUSE_CHARGING = """Device: /org/freedesktop/UPower/devices/mouse_hidpp_battery_1
  native-path:          hidpp_battery_1
  model:                MX Master 3S
  state:               unknown
  percentage:          62%
"""
HEADSET = """Device: /org/freedesktop/UPower/devices/headset_dev_1_1
  native-path:          dev_1_1
  model:                Arctis Nova 7
  state:               charging
  percentage:          45%
"""
GAMEPAD = """Device: /org/freedesktop/UPower/devices/gaming_input_dualsense
  native-path:          dualsense_battery
  model:                DualSense wireless controller
  state:               discharging
  percentage:          30%
"""
NOPCT = """Device: /org/freedesktop/UPower/devices/mouse_generic_battery
  native-path:          generic_battery
  model:                Cheap Mouse
  state:               discharging
  capacity-level:      low
"""
UPS = """Device: /org/freedesktop/UPower/devices/ups_backups
  native-path:          backups
  model:                Back-UPS
  percentage:          100%
"""

ALL = LAPTOP + "\n" + LINE + "\n" + DISPLAY + "\n" + MOUSE + "\n" + \
    MOUSE_CHARGING + "\n" + HEADSET + "\n" + GAMEPAD + "\n" + NOPCT + "\n" + UPS

print("gear probe parser")

rows = rows_of(ALL)
check("9 inputs -> 5 gear rows (laptop/line/display/ups filtered)", len(rows) == 5,
      f"got {len(rows)}: {[r['name'] for r in rows]}")

mouse = next((r for r in rows if r["name"] == "MX Master 3S" and r["level"] == 87), None)
check("mouse parsed with level 87", mouse is not None)
check("mouse kind is mouse", mouse and mouse["kind"] == "mouse", str(mouse))
check("mouse discharging -> charging false", mouse and mouse["charging"] is False)

m2 = next((r for r in rows if r["name"] == "MX Master 3S" and r["level"] == 62), None)
check("unknown state -> charging null (tri-state)", m2 is not None and m2["charging"] is None)

hs = next((r for r in rows if "Arctis" in r["name"]), None)
check("headset kind from dbus path", hs and hs["kind"] == "headset", str(hs))
check("headset charging true", hs and hs["charging"] is True)

pad = next((r for r in rows if "DualSense" in r["name"]), None)
check("gamepad kept (gaming_input_ prefix)", pad and pad["kind"] == "gamepad", str(pad))

cheap = next((r for r in rows if "Cheap" in r["name"]), None)
check("no percentage -> level null, row kept", cheap is not None and cheap["level"] is None)

kinds = [r["kind"] for r in rows]
check("ups filtered by kind", "ups" not in json.dumps(rows))

check("empty input -> empty rows", rows_of("") == [])
check("garbage input -> empty rows", rows_of("random text\nno devices here") == [])

# kind_for matrix
kf = probe.kind_for
check("kind_for dbus mouse prefix", kf("hidpp_battery_0", "Logitech", "", "/org/.../mouse_hidpp_battery_0") == "mouse")
check("kind_for model match", kf("bogus", "MX Keys Keyboard", "") == "keyboard")
check("kind_for upower gaminginput", kf("x", "Wireless Controller", "gaminginput") == "gamepad")
check("kind_for unknown -> other", kf("zzz", "Mystery", "") == "other")

print()
if failures:
    print(f"FAILED: {len(failures)}")
    sys.exit(1)
print("all pass")
