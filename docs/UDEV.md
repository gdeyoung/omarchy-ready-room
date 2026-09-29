# Optional udev rule

Two Xbox controls are owned by root, so Ready Room cannot touch them as your
user. Both are **optional** — the panel hides them rather than offering a
control that fails, and everything else works without this.

| Control | Why it needs the rule | What you lose without it |
|---|---|---|
| Guide-button light | `xone` registers it as an LED class device, root-owned, with no `uaccess` tag | Nothing you can't live without — the light stays at its default |
| Pair from the panel | The adapter's `pairing` attribute is a root-owned sysfs file | Nothing: press the button on the adapter, then on the controller |

If you want them, install the rule:

```bash
sudo install -m 644 udev/71-readyroom.rules /etc/udev/rules.d/71-readyroom.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=leds --subsystem-match=usb
```

Then reconnect the controller (and re-plug the adapter). The two controls appear
on their own — the panel checks writability each time it probes, so there is
nothing to switch on.

The rule grants access to the **input** group, not to everyone. You are already
in it if your controller works at all. Check with `id -nG`.

To undo it:

```bash
sudo rm /etc/udev/rules.d/71-readyroom.rules
sudo udevadm control --reload-rules
```

## Why the plugin doesn't install this for you

It needs root, and a plugin that asks for root during install is a plugin you
should be suspicious of. The rule is four lines; read them before you run the
command above.
