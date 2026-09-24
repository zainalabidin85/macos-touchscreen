# macos-touchscreen

Make a touchscreen monitor work on macOS when it does nothing out of the box.

macOS has no touch input pipeline for external HID touchscreens. This small Swift tool
reads the touch controller directly and turns touches into mouse events.

Developed and tested on an LG monitor with an **LGD AIT Touch Controller** (Melfas,
USB `1fd2:6103`) on an Apple Silicon Mac mini running macOS 26. There are no IDs to
configure: the tool finds any connected HID touchscreen by itself, so other monitors that
use the standard Windows touch HID layout should work too; see [Other monitors](#other-monitors).

## Gestures

| Touch | Result |
|---|---|
| Tap | Click |
| Two quick taps | Double-click |
| Drag one finger | Scroll, like a phone; a quick flick keeps coasting (`--invert-scroll` reverses the direction) |
| Hold one finger still for 0.6 s, then move | Click-and-drag (select text, move windows) |
| Hold one finger still for 0.6 s, then lift | Right-click |
| Drag two fingers | Scroll (same as one finger) |

No pinch, rotate or other multi-touch gestures.


## Install

### From a release (no Xcode needed)

1. Download `touchmouse-v1.2.0-macos.zip` from the
   [Releases page](https://github.com/zainalabidin85/macos-touchscreen/releases) and unzip it.
   It is a universal binary for Apple Silicon and Intel Macs, macOS 13 or later.
2. In Terminal, run the installer from the unzipped folder:
   ```sh
   ./install.sh
   ```
3. Grant permissions (see below), then restart it:
   ```sh
   launchctl kickstart -k gui/$(id -u)/com.touchmouse
   ```

The installer copies the binary to `~/Library/Application Support/touchmouse/`, removes the
download quarantine flag, and installs a LaunchAgent so it starts at every login.
The binary is ad-hoc signed, not notarized (no Apple Developer account), so macOS may refuse
to open it if you double-click it. Running `./install.sh` from Terminal avoids that.

Remove everything with `./install.sh --uninstall`.

### From source

Building needs only the **Xcode Command Line Tools** (`xcode-select --install`, about 1 GB),
not the full Xcode app.

```sh
./install.sh                       # build, install and start at login
# or just build and run once:
swiftc -O touchmouse.swift -o touchmouse
./touchmouse
```

`./package.sh 1.2.0` builds the universal release zip into `dist/`.

### Options

```
touchmouse --displays          list displays and their indexes
touchmouse --display N         map touches to display N (default: main display)
touchmouse --invert-scroll     reverse scroll direction
touchmouse --scroll-speed X    scroll speed relative to finger movement (default 0.5)
touchmouse --probe             print raw HID values while you touch (for debugging)
```

To pass options at login, add them to `ProgramArguments` in
`~/Library/LaunchAgents/com.touchmouse.plist` and restart the agent.

## Permissions

macOS needs two permissions for whichever app launches the tool:

- **Input Monitoring** to read the touch controller.
- **Accessibility** to post mouse events.

Under System Settings > Privacy & Security, click **+**, press Cmd+Shift+G and add:

- the login item: `~/Library/Application Support/touchmouse/touchmouse`
- or, when running by hand, the terminal app you launch it from (then restart that terminal).

The permissions are tied to the signed binary, so after updating it you may need to remove
the `touchmouse` entry (**−**) and add it again. Logs are in
`~/Library/Application Support/touchmouse/touchmouse.log`.

## Other monitors

Nothing needs configuring. At startup (and whenever a touchscreen is plugged in),
`touchmouse` finds every HID device that reports itself as a touch screen (Digitizer usage
page 0x0D, usage 0x04) and prints its name and `vendor:product` IDs. If the device has
the standard Device Mode feature (0x0D/0x52), it's set to 2 (multi-input), which is what
Windows does and what wakes up controllers that stay silent on macOS. Controllers without
it are used as they are.

If touches still don't work:

1. Run `touchmouse --probe` and touch the screen. No output means no touch data arrives;
   no "touch enabled" line means the screen wasn't recognised as a touchscreen.
2. Dump the report descriptor with `tools/desc.swift`. `touchmouse` expects a digitizer
   with per-finger collections containing Tip Switch (0x0D/0x42) and X/Y (0x01/0x30, 0x31).
3. `tools/mode.swift <mode>` sets the Device Mode by hand and prints raw reports.

## Files

- `touchmouse.swift` — the tool
- `install.sh` — install (prebuilt or built from source) and set up the LaunchAgent
- `package.sh` — build the universal release zip
- `tools/` — small diagnostics used to work this out (`desc`, `diag`, `mode`, `perm`)

## License

MIT
