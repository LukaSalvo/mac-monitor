#!/bin/bash
# Fichier: deploy.sh

OS="$(uname -s)"
echo "--- Démarrage du processus de déploiement ($OS) ---"

# --- ÉTAPE 1 : NETTOYAGE & CONFIGURATION BUNDLER ---
echo "1. Nettoyage et configuration..."
rm -f app.log server.log

# Configuration de Bundler pour installer les gems localement dans le projet
# Cela évite les problèmes de permissions système et de sudo
echo "Configuration de Bundler (local path: vendor/bundle)..."
bundle config set --local path 'vendor/bundle'
bundle config set --local disable_shared_gems true

# --- ÉTAPE 2 : INSTALLATION DES DÉPENDANCES ---
echo "2. Installation des dépendances..."
bundle install

# --- ÉTAPE 3 : ARRÊT DU PROCESSUS EXISTANT ---
echo "3. Vérification des ports..."
START_PORT=3000
MAX_PORT=3010
FREE_PORT=""

# Fonction cross-platform pour vérifier si un port est utilisé
is_port_used() {
    local port=$1
    if [ "$OS" = "Darwin" ]; then
        lsof -i :$port -t >/dev/null 2>&1
    else
        # Linux: ss est plus standard que netstat sur les distros modernes
        ss -tuln | grep -q ":$port "
    fi
}

# Tuer les processus sur le port 3000 si existants
if is_port_used 3000; then
    echo "Port 3000 occupé. Tentative d'arrêt..."
    if [ "$OS" = "Darwin" ]; then
         PID=$(lsof -i :3000 -t)
    else
         PID=$(fuser 3000/tcp 2>/dev/null)
    fi
    
    if [ -n "$PID" ]; then
        kill -9 $PID 2>/dev/null
        sleep 1
    fi
fi

# --- ÉTAPE 4 : RECHERCHE PORT LIBRE ---
echo "4. Recherche du port libre..."
for (( PORT = $START_PORT; PORT <= $MAX_PORT; PORT++ )); do
    if ! is_port_used $PORT; then
        FREE_PORT=$PORT
        break
    fi
done

if [ -z "$FREE_PORT" ]; then
    echo "ERREUR: Aucun port libre trouvé entre $START_PORT et $MAX_PORT."
    exit 1
fi

# --- ÉTAPE 5 : LANCEMENT DU SERVEUR ---
echo "5. Lancement du serveur Sinatra sur le port $FREE_PORT..."
echo "URL Local: http://localhost:$FREE_PORT"
echo "URL Réseau: http://$(hostname):$FREE_PORT (si accessible)"
echo "Presser CTRL+C pour arrêter."

# Utilisation de 'bundle exec' pour garantir l'utilisation des gems du projet
bundle exec rackup -p $FREE_PORT --host 0.0.0.0