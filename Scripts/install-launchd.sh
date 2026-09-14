#!/usr/bin/env bash
# Starts Cadence at login, and again on weekday mornings.
#
# The office-arrival notification and the block-start alerts come from the app's own 60s
# scheduler — nothing fires while Cadence is closed. This agent just makes sure it's open.
# RunAtLoad covers "I opened the lid at the office and logged in"; the 08:30 entries cover
# a Mac that was already logged in overnight.
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
    <string>/usr/bin/open</string>
    <string>-g</string>
    <string>-a</string>
    <string>Cadence</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>30</integer></dict>
  </array>
  <key>StandardErrorPath</key><string>/tmp/cadence-launchd.log</string>
  <key>StandardOutPath</key><string>/tmp/cadence-launchd.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Loaded: $PLIST"
echo "Cadence opens in the background at login and at 08:30 on weekdays."
echo "-g keeps it from stealing focus. Arrival fires once a day — ignoring it is enough to silence it."
