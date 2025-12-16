#!/bin/bash
# Fichier: deploy.sh

echo "--- Démarrage du processus de déploiement ---"

# --- ÉTAPE 1 : NETTOYAGE & DÉSACTIVATION INSTALLATION LOCALE ---
echo "1. Nettoyage des logs et des anciens artefacts..."

rm -f app.log server.log

if [ -d "vendor/bundle" ]; then
    echo "Suppression du dossier 'vendor/bundle'..."
    rm -rf vendor/bundle
fi

echo "Configuration de Bundler pour utiliser l'emplacement système..."
bundle config set path '~/.bundle/gems'

# --- ÉTAPE 2 : VÉRIFICATION ET INSTALLATION DES DÉPENDANCES ---
echo "2. Vérification et installation des dépendances Ruby (dans l'emplacement utilisateur)..."
bundle install 

# --- ÉTAPE 3 : ARRÊT DU PROCESSUS EXISTANT ---
# Nous arrêtons tous les processus qui écoutent sur le port 3000 ou qui sont Puma/Rackup pour garantir la libération.
echo "3. Vérification et arrêt des anciens processus serveur..."
# Trouver les PIDs écoutant sur 3000
PID_3000=$(lsof -i :3000 -t)

if [ -n "$PID_3000" ]; then
    echo "Ancien processus trouvé sur le port 3000 (PID: $PID_3000). Arrêt forcé..."
    kill -9 $PID_3000
    sleep 1
fi

# Reste de la recherche du port libre
START_PORT=3000
MAX_PORT=3010
FREE_PORT=""

echo "4. Recherche du premier port libre entre $START_PORT et $MAX_PORT..."

for (( PORT = $START_PORT; PORT <= $MAX_PORT; PORT++ )); do
    # Vérifie si le port est en écoute. Utiliser netstat ou ss est parfois plus direct sur Debian.
    # Alternative 1 (plus portable sur Linux) :
    if ! ss -tuln | grep -q ":$PORT\s"; then
        FREE_PORT=$PORT
        break
    fi
done

# Si la recherche a trouvé un port libre (ce qui devrait être 3000 après le kill)
if [ -z "$FREE_PORT" ]; then
    echo "ERREUR: Aucun port libre trouvé entre $START_PORT et $MAX_PORT."
    exit 1
fi

# --- ÉTAPE 5 : LANCEMENT DU SERVEUR ---
echo "5. Lancement du serveur Sinatra sur le port $FREE_PORT..."
echo "Vérifiez l'application sur http://localhost:$FREE_PORT"
echo "Presser CTRL+C pour arrêter le serveur."

# Lancement du serveur en premier plan, utilisant config.ru
bundle exec rackup -p $FREE_PORT

echo "--- Déploiement terminé. ---"