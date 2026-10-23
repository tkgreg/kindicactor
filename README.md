# KIndicator

**A macOS menu bar indicator for Keychron keyboards: see the active layer at a
glance, light the keyboard per layer, and launch apps in the right input language.**

![KIndicator settings: layers with names, icons and lighting](docs/layers.png)

Keychron's ZMK keyboards (like the V6 Ultra 8K) don't tell you which layer is on.
Hold Fn, lock a layer with a TG key or flip the Mac/Win switch, and you're guessing.
KIndicator reads the active layer from the keyboard and shows it in the menu bar.

[Download Latest Version 1.0](https://github.com/tkgreg/kindicactor/releases/tag/v1.0)

## Features

- **Active layer in the menu bar.** Each layer gets your own name and icon: an SF
  Symbol such as `sun.max`, or up to 3 letters in a box like **Fn** or **W**. Show
  the icon, the name, or both.
- **Lighting per layer.** Give a layer its own RGB effect and colour (pick one or
  type a hex value), so the keyboard itself shows which layer is on. Your saved
  lighting comes back when you return. Nothing is written to the keyboard's
  storage on each switch.
- **Lighting from the menu.** Switch the keyboard's effect (Breathing, Per-key RGB,
  Off, …) without opening Keychron Launcher.
- **Launch actions.** One global shortcut switches the input language, then opens
  an app. For example, switch to English, then open Launchpad, so typing to
  search always works even when Russian was selected. Put the shortcut on a
  keyboard key (e.g. F4) with a Keychron Launcher macro.
- **Keyboard info.** Model (also through the 2.4 GHz dongle), connection and
  firmware version.
- **Plays nice with Keychron Launcher.** Pauses automatically while Launcher is
  open, so the two apps don't confuse the keyboard.
- **Lightweight.** Starts at login, lives in the menu bar, needs no special
  permissions (no Input Monitoring, no Accessibility).

![Launch actions: shortcut, input source and app](docs/launch-actions.png)

## Download

Get the latest `KIndicator-<version>.dmg` from
[Releases](https://github.com/tkgreg/kindicactor/releases/latest), open it and drag
**KIndicator** to **Applications**. The app is signed and notarized by Apple.

On first launch KIndicator adds itself to **System Settings › General › Login
Items**; you can turn that off in **Settings › General**.

**Requirements:** macOS 15 or later, Apple silicon or Intel.

## Getting started

1. Connect the keyboard with the **USB cable** or the **2.4 GHz dongle**.
2. Open **Settings › Layers** and press Fn or flip the Mac/Win switch: the green dot
   follows the active layer, so you can see which row is which. Give each layer a
   name and an icon.
3. Optional: pick a lighting effect for a layer, e.g. red *Solid Color* for the Fn
   layer.
4. Optional: in **Settings › Launch Actions** add a shortcut, then in Keychron
   Launcher set a key's macro to press it.

## Compatibility

Tested with the **Keychron V6 Ultra 8K** (ANSI) on firmware 1.0.2. Other Keychron
boards running Keychron's ZMK firmware ("Ultra" / "8K" series) use the same
protocol and should work; their model name shows once they've been connected by
cable or Bluetooth.

| Connection | Layer | Lighting | Notes |
|---|---|---|---|
| USB cable | ✓ | ✓ | |
| 2.4 GHz dongle | ✓ | ✓ | Through the Keychron Ultra-Link 8K |
| Bluetooth | – | – | The firmware has no data channel over Bluetooth; KIndicator just shows that the keyboard is on Bluetooth |

### Limitations

- **KIndicator can't switch layers.** Keychron's firmware only reports the layer;
  use layer keys (MO, TG, TO) set in Keychron Launcher.
- **The `TT(layer)` keycode doesn't work on this firmware** (it does nothing; a
  Keychron bug). Use `MO(1)` on Fn plus `TG(1)` on another key instead.
- While Keychron Launcher is open, KIndicator is paused.

## Build from source

```bash
./build.sh --install     # build, sign with your Apple Development identity, install and launch
./release.sh             # universal build, Developer ID signing, notarized DMG in dist/
```

`release.sh` needs a *Developer ID Application* certificate and notarization
credentials stored with `xcrun notarytool store-credentials kindicator-notary`.

## How it works

Keychron's ZMK firmware exposes the same raw HID channel Keychron Launcher uses
(usage page `0xFF60`, usage `0x61`, 32-byte reports):

- `0xA3` returns the **highest active layer**, so momentary Fn layers show too.
  KIndicator asks every 250 ms by default (Settings › Connection).
- `0x07` / `0x08` / `0x09` on channel `3` set, get and save the RGB matrix effect,
  colour, brightness and speed. Per-layer lighting is applied without saving and
  the saved lighting is restored afterwards. Changes made with the keyboard's light
  keys in the meantime are kept.
- `0xB2`, answered by the 2.4 GHz dongle, lists the paired keyboard's vendor and
  product ID, which gives the model name.
- The keyboard answers every app that has the channel open and drops a request
  that arrives while it's busy. So KIndicator goes quiet whenever another process
  (e.g. Keychron Launcher in a browser) has the channel open.

Launch actions use Carbon hotkeys and the Text Input Sources API, which need no
permissions.

The app icon is generated by `Tools/make-icon.swift`:

```bash
swift Tools/make-icon.swift Resources/AppIcon.icns
```

Logs:

```bash
log stream --predicate 'subsystem == "local.kindicator"'
```

## License

[MIT](LICENSE)
