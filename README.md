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


## Install

### From a release (no Xcode needed)

1. Download `touchmouse-vX.Y.Z-macos.zip` from the
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

`./package.sh 1.0.0` builds the universal release zip into `dist/`.

### Options

```
touchmouse --displays          list displays and their indexes
touchmouse --display N         map touches to display N (default: main display)
touchmouse --invert-scroll     reverse scroll direction
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
- `install.sh` — install (prebuilt or built from source) and set up the LaunchAgent
- `package.sh` — build the universal release zip
- `tools/` — small diagnostics used to work this out (`desc`, `diag`, `mode`, `perm`)

## License

MIT
