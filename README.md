# macos-touchscreen

Make a USB touchscreen monitor work on macOS when it does nothing out of the box.

macOS has no touch input pipeline for external HID touchscreens. This small Swift tool
reads the touch controller directly and turns touches into mouse events.

Developed and tested on an LG monitor with an **LGD AIT Touch Controller** (Melfas,
USB `1fd2:6103`) on an Apple Silicon Mac mini running macOS 26. Other monitors that use
the same Windows Precision Touch style HID layout may work after changing the two IDs at
the top of `touchmouse.swift`; see [Other monitors](#other-monitors).

## Gestures

| Touch | Result |
|---|---|
| Tap | Click |
| Two quick taps | Double-click |
| Drag one finger | Click-and-drag (after a 12 pt movement threshold) |
| Hold one finger still for 0.6 s | Right-click |
| Drag two fingers | Scroll (`--invert-scroll` reverses the direction) |

No pinch, rotate or other multi-touch gestures.

## Why the screen does nothing on macOS

Two separate problems:

1. **The controller stays silent until the host enables it.** Its HID descriptor has a
   Device Mode feature report (report ID 7, usages 0x52/0x53). Windows sets it
   automatically; macOS never does, so no touch reports are sent at all. `touchmouse`
   writes `[7, 2, 0]` (multi-input mode) at startup, and again after wake or replug.
2. **Even with reports flowing, macOS ignores them.** The controller shows up as a
   digitizer (usage page 0x0D, usage 4), but nothing turns that into pointer events.
   `touchmouse` reads the finger contacts (tip switch, X, Y) and posts mouse events.

## Build and run

Requires the Xcode command line tools (`xcode-select --install`).

```sh
swiftc -O touchmouse.swift -o touchmouse
./touchmouse
```

Options:

```
touchmouse --displays          list displays and their indexes
touchmouse --display N         map touches to display N (default: main display)
touchmouse --invert-scroll     reverse scroll direction
touchmouse --probe             print raw HID values while you touch (for debugging)
```

## Permissions

macOS needs two permissions for whichever app launches the tool:

- **Input Monitoring** to read the touch controller.
- **Accessibility** to post mouse events.

Both are under System Settings > Privacy & Security. When run from a terminal, grant them
to that terminal app (then restart it).

## Start at login

```sh
./install.sh
```

This builds and ad-hoc signs the binary, and installs a LaunchAgent
(`~/Library/LaunchAgents/com.touchmouse.plist`). When launchd starts it, the binary itself
is the app macOS checks, so add `touchmouse` to **both** privacy panes (click **+**, press
Cmd+Shift+G, paste the path printed by the script), then restart it:

```sh
launchctl kickstart -k gui/$(id -u)/com.touchmouse
```

The permissions are tied to the signed binary, so rebuilding it means adding it again.
Remove everything with `./install.sh --uninstall`. Logs go to `agent.log`.

## Other monitors

1. Find the controller's IDs: `system_profiler SPUSBDataType` or
   `ioreg -p IOUSB -l | grep -B2 -A10 -i touch`. Convert vendor/product IDs to decimal.
2. Set `vendorID` and `productID` at the top of `touchmouse.swift`.
3. Dump the report descriptor with `tools/desc.swift`. `touchmouse` expects a digitizer
   with per-finger collections containing Tip Switch (0x0D/0x42) and X/Y (0x01/0x30, 0x31).
   If the descriptor has a Device Mode feature report, try other values than 2 in
   `enableTouchMode()`.
4. `tools/mode.swift <mode>` sets the mode and prints raw reports, and `--probe` shows
   parsed values, which is how you check that touches arrive at all.

Controllers that already send touch reports on macOS just need Input Monitoring and won't
need the mode report; it's harmless to leave in, but check that the write doesn't fail.

## Files

- `touchmouse.swift` — the tool
- `install.sh` — build, sign and install the LaunchAgent
- `tools/` — small diagnostics used to work this out (`desc`, `diag`, `mode`, `perm`)

## License

MIT
