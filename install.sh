#!/bin/sh
# Install touchmouse and start it at login (per-user LaunchAgent).
#   ./install.sh              install and start
#   ./install.sh --uninstall  stop and remove everything this script installed
#
# Uses the prebuilt ./touchmouse from a release zip. From a source checkout
# (touchmouse.swift present, Xcode command line tools installed) it builds one instead.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.touchmouse"
INSTALL_DIR="$HOME/Library/Application Support/touchmouse"
BIN="$INSTALL_DIR/touchmouse"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

# TOUCHMOUSE_NO_LOAD=1 skips launchctl (used for testing the script).
if [ -z "$TOUCHMOUSE_NO_LOAD" ]; then
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
fi

if [ "$1" = "--uninstall" ]; then
    rm -f "$PLIST"
    rm -rf "$INSTALL_DIR"
    echo "Removed $LABEL. You can also delete its entries under Privacy & Security."
    exit 0
fi

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents"

if [ -f "$DIR/touchmouse.swift" ] && command -v swiftc >/dev/null 2>&1; then
    echo "Building from source..."
    swiftc -O "$DIR/touchmouse.swift" -o "$BIN"
elif [ -f "$DIR/touchmouse" ]; then
    cp "$DIR/touchmouse" "$BIN"
else
    echo "No prebuilt ./touchmouse found and swiftc is not available." >&2
    echo "Download a release zip, or run: xcode-select --install" >&2
    exit 1
fi

# A browser-downloaded zip marks its contents as quarantined, which blocks unsigned tools.
xattr -dr com.apple.quarantine "$BIN" 2>/dev/null || true
codesign -v "$BIN" 2>/dev/null || codesign -s - -f --identifier "$LABEL" "$BIN"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>15</integer>
    <key>StandardOutPath</key><string>$INSTALL_DIR/touchmouse.log</string>
    <key>StandardErrorPath</key><string>$INSTALL_DIR/touchmouse.log</string>
</dict>
</plist>
PLIST

if [ -z "$TOUCHMOUSE_NO_LOAD" ]; then
    launchctl bootstrap "$DOMAIN" "$PLIST"
fi

cat <<MSG
Installed $LABEL.

Grant this binary Accessibility and Input Monitoring
(System Settings > Privacy & Security, click +, press Cmd+Shift+G, paste the path):
  $BIN
Then restart it:
  launchctl kickstart -k $DOMAIN/$LABEL
MSG
