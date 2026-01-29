#!/bin/bash

OS="$(uname -s)"
echo "--- Deployment ($OS) ---"

# Nettoyage des logs
rm -f server.log

# Configuration Bundler
bundle config set --local path 'vendor/bundle'
bundle config set --local disable_shared_gems true

echo "Installing dependencies..."
bundle install

# --- CONFIGURATION ---
START_PORT=3000
MAX_PORT=3010
FREE_PORT=""

# Fonction de détection de port (Mac vs Linux)
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

if [ -z "$FREE_PORT" ]; then
    echo "ERROR: No free port found."
    exit 1
fi

# --- LANCEMENT ---

if [ "$GITHUB_ACTIONS" == "true" ]; then
    echo "CI Mode: Testing server on port $FREE_PORT..."
    bundle exec rackup -p $FREE_PORT --host 0.0.0.0 > server.log 2>&1 &
    SERVER_PID=$!
    
    # Attente du démarrage
    sleep 5
    
    # Vérification Healthcheck (curl)
    # -s : silencieux, -o /dev/null : ignore le corps, -w : affiche le code HTTP
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$FREE_PORT || echo "000")
    
    if [ "$HTTP_STATUS" == "200" ]; then
        echo "SUCCESS: Server is responding with HTTP 200"
        kill $SERVER_PID
        exit 0
    else
        echo "ERROR: Server started but returned HTTP $HTTP_STATUS"
        echo "--- Server Logs ---"
        cat server.log
        kill $SERVER_PID 2>/dev/null
        exit 1
    fi
else
    echo "Local Mode: Starting server on http://localhost:$FREE_PORT"
    bundle exec rackup -p $FREE_PORT --host 0.0.0.0
fi