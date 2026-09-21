#!/bin/sh
# Build touchmouse, sign it, and install a LaunchAgent so it starts at login.
#   ./install.sh             build + install + start
#   ./install.sh --uninstall stop and remove the LaunchAgent
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.touchmouse"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [ "$1" = "--uninstall" ]; then
    rm -f "$PLIST"
    echo "Removed $LABEL."
    exit 0
fi

swiftc -O "$DIR/touchmouse.swift" -o "$DIR/touchmouse"
codesign -s - -f --identifier "$LABEL" "$DIR/touchmouse"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$DIR/touchmouse</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>15</integer>
    <key>StandardOutPath</key><string>$DIR/agent.log</string>
    <key>StandardErrorPath</key><string>$DIR/agent.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "$DOMAIN" "$PLIST"
cat <<MSG
Installed and started $LABEL.

Grant this binary Accessibility and Input Monitoring
(System Settings > Privacy & Security, click +, add):
  $DIR/touchmouse
Then restart it:  launchctl kickstart -k $DOMAIN/$LABEL
MSG
