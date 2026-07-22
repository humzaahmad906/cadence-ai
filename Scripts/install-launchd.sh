#!/usr/bin/env bash
# Installs launchd agent that triggers the app at 09:00 / 13:45 / 14:00 via URL scheme.
set -euo pipefail

PLIST=~/Library/LaunchAgents/com.humza.cadence.scheduler.plist
mkdir -p ~/Library/LaunchAgents

cat > "$PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.humza.cadence.scheduler</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>open "cadence://$SPRINTDASH_KIND"</string>
  </array>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>45</integer></dict>
    <dict><key>Hour</key><integer>14</integer><key>Minute</key><integer>0</integer></dict>
  </array>
  <key>StandardErrorPath</key><string>/tmp/cadence-launchd.log</string>
  <key>StandardOutPath</key><string>/tmp/cadence-launchd.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Loaded: $PLIST"
echo "Note: the in-app Scheduler also fires at these times when the app is running — launchd is a safety net."
