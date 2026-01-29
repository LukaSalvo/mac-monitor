#!/bin/bash

OS="$(uname -s)"
echo "--- Deployment ($OS) ---"

# Nettoyage des anciens logs
rm -f server.log

# Configuration locale des gems
bundle config set --local path 'vendor/bundle'
bundle config set --local disable_shared_gems true

echo "Installing dependencies..."
bundle install

# --- CONFIGURATION DES PORTS ---
START_PORT=3000
MAX_PORT=3010
FREE_PORT=""

# Fonction pour vérifier si un port est utilisé selon l'OS
is_port_used() {
    local port=$1
    if [ "$OS" = "Darwin" ]; then
        lsof -i :$port -t >/dev/null 2>&1
    else
        ss -tuln | grep -q ":$port "
    fi
}

# Recherche d'un port libre
for (( PORT = $START_PORT; PORT <= $MAX_PORT; PORT++ )); do
    if ! is_port_used $PORT; then
        FREE_PORT=$PORT
        break
    fi
done

if [ -z "$FREE_PORT" ]; then
    echo "ERROR: No free port found between $START_PORT and $MAX_PORT."
    exit 1
fi

echo "Starting server on port $FREE_PORT..."

# LANCEMENT EN ARRIÈRE-PLAN
# On redirige la sortie vers server.log pour pouvoir debugger en cas d'erreur
bundle exec rackup -p $FREE_PORT --host 0.0.0.0 > server.log 2>&1 &
SERVER_PID=$!

# Attendre que le serveur démarre (5 secondes)
sleep 5

# VÉRIFICATION
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "SUCCESS: Server is running on PID $SERVER_PID"
    echo "Local: http://localhost:$FREE_PORT"
    
    # Dans un contexte CI, on arrête le serveur après avoir confirmé qu'il marche
    echo "Stopping server for CI completion..."
    kill $SERVER_PID
    exit 0
else
    echo "ERROR: Server failed to start. Last logs:"
    cat server.log
    exit 1
fi