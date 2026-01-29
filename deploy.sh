#!/bin/bash

OS="$(uname -s)"
# Récupération du tag Git pour la version
CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v1.0.0-local")

echo "--- Deployment ($OS) - Version: $CURRENT_VERSION ---"

# Nettoyage des logs
rm -f server.log

# Configuration Bundler
bundle config set --local path 'vendor/bundle'
bundle config set --local disable_shared_gems true

echo "Installing dependencies..."
bundle install

# --- GESTION DU SERVICE LOCAL ---
# Si on n'est pas sur GitHub Actions, on met à jour le service système
if [ "$GITHUB_ACTIONS" != "true" ]; then
    if [ -f "./install_service.sh" ]; then
        echo "Updating system service..."
        chmod +x install_service.sh
        ./install_service.sh
    else
        echo "WARNING: install_service.sh not found. Skipping service update."
    fi
fi

# --- CONFIGURATION DU PORT (Principalement pour le mode TEST) ---
START_PORT=3000
MAX_PORT=3010
FREE_PORT=""

is_port_used() {
    local port=$1
    if [ "$OS" = "Darwin" ]; then
        lsof -i :$port -t >/dev/null 2>&1
    else
        ss -tuln | grep -q ":$port "
    fi
}

for (( PORT = $START_PORT; PORT <= $MAX_PORT; PORT++ )); do
    if ! is_port_used $PORT; then
        FREE_PORT=$PORT
        break
    fi
done

# --- LANCEMENT / TEST ---

if [ "$GITHUB_ACTIONS" == "true" ]; then
    if [ -z "$FREE_PORT" ]; then echo "ERROR: No free port."; exit 1; fi
    
    echo "CI Mode: Testing server on port $FREE_PORT..."
    bundle exec rackup -p $FREE_PORT --host 0.0.0.0 > server.log 2>&1 &
    SERVER_PID=$!
    
    sleep 5
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$FREE_PORT || echo "000")
    
    if [ "$HTTP_STATUS" == "200" ]; then
        echo "SUCCESS: Server is responding with HTTP 200"
        kill $SERVER_PID
        exit 0
    else
        echo "ERROR: HTTP $HTTP_STATUS"
        cat server.log
        kill $SERVER_PID 2>/dev/null
        exit 1
    fi
else
    # En local, le service a déjà été relancé par install_service.sh
    echo "Local Mode: Application is managed by system service."
    echo "Check status with: sudo systemctl status mac-monitor (Linux) or launchctl list (Mac)"
fi