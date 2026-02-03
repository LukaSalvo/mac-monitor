#!/bin/bash

# Configuration
# Detecter le dossier racine du projet (parent du dossier scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CURRENT_USER=$(whoami)
RUBY_BIN=$(which ruby)
BUNDLE_BIN=$(which bundle)
PORT=3000

echo "--- Installing Mac-Monitor Service ---"
echo "App Directory: $APP_DIR"
echo "User: $CURRENT_USER"
echo "Bundle: $BUNDLE_BIN"

# Verification des dependances avant installation du service
if [ ! -d "vendor/bundle" ]; then
    echo "[WARNING] Dependencies not installed. Running bundle install..."
    bundle config set --local path 'vendor/bundle'
    bundle install
fi

# Configuration email.yml si manquant
if [[ ! -f "config/email.yml" ]]; then
    if [[ -f "config/email.yml.example" ]]; then
        cp config/email.yml.example config/email.yml
        echo "[INFO] Created config/email.yml from template"
    fi
fi


if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    SERVICE_FILE="/etc/systemd/system/mac-monitor.service"
    echo "Detected Linux. Creating systemd service at $SERVICE_FILE..."
    
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Mac Monitor Web Dashboard
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
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
    echo "Starting/Restarting service..."
    sudo systemctl restart mac-monitor
    echo "Status:"
    sudo systemctl status mac-monitor --no-pager

elif [[ "$OSTYPE" == "darwin"* ]]; then
    # Creer le dossier LaunchAgents si necessaire
    mkdir -p "$HOME/Library/LaunchAgents"
    
    PLIST_FILE="$HOME/Library/LaunchAgents/com.macmonitor.plist"
    echo "Detected macOS. Creating LaunchAgent at $PLIST_FILE..."
    
    # Creer le plist avec les variables expandues
    cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.macmonitor</string>
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
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.rbenv/shims:$HOME/.rvm/bin</string>
        <key>RACK_ENV</key>
        <string>production</string>
    </dict>
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

    echo "Plist file created."
    
    # Decharger l'ancien service si existe
    echo "Unloading previous service (if exists)..."
    launchctl bootout gui/$(id -u) "$PLIST_FILE" 2>/dev/null || true
    
    sleep 1
    
    # Charger le nouveau service
    echo "Loading new service..."
    launchctl bootstrap gui/$(id -u) "$PLIST_FILE"
    
    echo ""
    echo "[OK] Service installed!"
    echo "Logs at: $APP_DIR/server.log"
    echo ""
    echo "Commands:"
    echo "  Stop:    launchctl bootout gui/$(id -u) $PLIST_FILE"
    echo "  Start:   launchctl bootstrap gui/$(id -u) $PLIST_FILE"
    echo "  Status:  launchctl list | grep macmonitor"
    
else
    echo "Unsupported OS for auto-install."
    exit 1
fi

echo ""
echo "--- Installation Complete ---"
