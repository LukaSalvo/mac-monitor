#!/bin/bash
USER=$(whoami)

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo systemctl stop mac-monitor
    sudo systemctl disable mac-monitor
    echo "Service Linux arrêté et désactivé."
elif [[ "$OSTYPE" == "darwin"* ]]; then
    launchctl unload "$HOME/Library/LaunchAgents/com.$USER.macmonitor.plist"
    echo "Service macOS déchargé."
fi