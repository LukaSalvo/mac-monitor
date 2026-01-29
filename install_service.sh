#!/bin/bash

# Configuration
APP_DIR=$(pwd)
USER=$(whoami)
RUBY_BIN=$(which ruby)
BUNDLE_BIN=$(which bundle)
PORT=3000

echo "--- Installing Mac-Monitor Service ---"
echo "App Directory: $APP_DIR"
echo "User: $USER"



if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    SERVICE_FILE="/etc/systemd/system/mac-monitor.service"
    echo "Detected Linux. Creating systemd service at $SERVICE_FILE..."
    
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Mac Monitor Web Dashboard
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=$BUNDLE_BIN exec rackup -p $PORT --host 0.0.0.0
Restart=always
Environment=RACK_ENV=production


[Install]
WantedBy=multi-user.target
EOF

    echo "Reloading systemd..."
    sudo systemctl daemon-reload
    echo "Enabling service..."
    sudo systemctl enable mac-monitor
    echo "Starting service..."
    sudo systemctl start mac-monitor
    echo "Status:"
    sudo systemctl status mac-monitor --no-pager

elif [[ "$OSTYPE" == "darwin"* ]]; then
    PLIST_FILE="$HOME/Library/LaunchAgents/com.$USER.macmonitor.plist"
    echo "Detected macOS. Creating LaunchAgent at $PLIST_FILE..."
    
    cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.$USER.macmonitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BUNDLE_BIN</string>
        <string>exec</string>
        <string>rackup</string>
        <string>-p</string>
        <string>$PORT</string>
        <string>--host</string>
        <string>0.0.0.0</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$APP_DIR</string>

    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$APP_DIR/server.log</string>
    <key>StandardErrorPath</key>
    <string>$APP_DIR/server.log</string>
</dict>
</plist>
EOF

    echo "Loading LaunchAgent..."
    launchctl unload "$PLIST_FILE" 2>/dev/null
    launchctl load "$PLIST_FILE"
    echo "Service installed and loaded. Logs at $APP_DIR/server.log"
else
    echo "Unsupported OS for auto-install."
    exit 1
fi

echo "--- Installation Complete ---"
