#!/bin/bash
# Scripts/install_launch_agent.sh
set -euo pipefail
mkdir -p ~/Library/LaunchAgents
cp Resources/com.oktally.app.plist ~/Library/LaunchAgents/com.oktally.app.plist
launchctl unload ~/Library/LaunchAgents/com.oktally.app.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.oktally.app.plist
echo "LaunchAgent installed — OkTally will now start on login."
