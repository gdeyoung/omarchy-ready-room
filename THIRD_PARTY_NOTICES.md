# Third-party notices

Ready Room contains **no third-party code**. It depends on no other plugin at
runtime, and nothing here was copied from one. What follows is credit for ideas
and for the research that saved a great deal of time, since several of these
plugins solved a problem first and solved it well.

All are MIT licensed.

| Plugin | What was learned from it |
|---|---|
| [nathanp/omarchy-game-awake](https://github.com/nathanp/omarchy-game-awake) | That `omarchy-toggle-idle` is the right way to drive stay-awake — going through Omarchy's own CLI, so the stock indicator stays in sync — and that Hyprland's `openwindow`/`closewindow` events make game detection need no polling at all. The clearest architecture of the six. |
| [silvaio/gamemode-switcher](https://github.com/silvaio/gamemode-switcher) | The shape of a "game mode" as a snapshot-and-restore of several system toggles at once. |
| [Dooooooks/omaclippr](https://github.com/Dooooooks/omaclippr) | That gpu-screen-recorder's replay buffer is the right engine for instant replay, and that its `-ipc` socket is how to drive it. |
| [LightQv/omarchy-gamepads](https://github.com/LightQv/omarchy-gamepads) | Its NDJSON helper protocol and supervisor discipline — versioned messages, bounded buffers, a terminal `dependency_missing` state that never restarts. The protocol in `bin/gc-pads` is an independent implementation of the same good idea. |
| [atoslins/omarchy-plugin-dualsense](https://github.com/atoslins/omarchy-plugin-dualsense) | That evdev force feedback is the portable way to rumble any pad, and how a hardened, user-consented udev-rule installer should read. Its DualSense artwork is MIT © 2024 the_al and is **not** used here; Ready Room draws no controller silhouette. |
| [MatyiFKBT/omarchy-steamguard](https://github.com/MatyiFKBT/omarchy-steamguard) | The pattern of delegating entirely to a CLI and keeping the plugin a thin, honest wrapper. |

The hardware facts this plugin relies on — what `xone` and `hid_xpadneo`
actually expose for battery, rumble, LEDs and pairing — were read from the
drivers themselves and then verified against real hardware. Those measurements
are in `docs/DECISIONS.md`.
