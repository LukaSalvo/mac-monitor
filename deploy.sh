#!/bin/bash

OS="$(uname -s)"
# 1. RÉCUPÉRATION DE LA VERSION (Option ajoutée)
# Récupère le dernier tag git ou affiche v1.0.0-local si aucun tag n'existe
CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v1.0.0-local")

echo "--- Deployment ($OS) - Version: $CURRENT_VERSION ---"

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

# 2. GESTION DU REDÉMARRAGE (Option ajoutée)
# Si on est en local, on cherche si le port 3000 est déjà pris pour tuer l'ancienne version
if [ "$GITHUB_ACTIONS" != "true" ]; then
    OLD_PID=$(if [ "$OS" = "Darwin" ]; then lsof -i :3000 -t; else fuser 3000/tcp 2>/dev/null; fi)
    if [ -n "$OLD_PID" ]; then
        echo "Old version detected (PID $OLD_PID). Stopping it to deploy new version..."
        kill -9 $OLD_PID
        sleep 2
    fi
fi

# Recherche de port libre (Ta logique originale)
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
    # 3. LANCEMENT EN ARRIÈRE-PLAN (Option ajoutée pour le local)
    echo "Local Mode: Starting server on http://localhost:$FREE_PORT"
    # nohup et & permettent de fermer le terminal sans couper l'application
    nohup bundle exec rackup -p $FREE_PORT --host 0.0.0.0 > server.log 2>&1 &
    echo "Server launched in background (PID $!). Check server.log for logs."
fi