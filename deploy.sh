#!/bin/bash
# Fichier: deploy.sh (Lancement sur le premier port libre, sans tuer de processus)

echo "--- Démarrage du processus de déploiement ---"

# --- NOUVELLE ÉTAPE 1 : NETTOYAGE ---
echo "1. Nettoyage des logs et des artefacts de build précédents..."

# Supprimer les fichiers de logs générés (si ils existent)
rm -f app.log server.log

# Supprimer le répertoire des dépendances installées localement (pour une réinstallation propre)
# Le dossier 'vendor/bundle' est là où 'bundle install' stocke les gems.
if [ -d "vendor/bundle" ]; then
    echo "Suppression du dossier 'vendor/bundle'..."
    rm -rf vendor/bundle
fi

# --- ÉTAPE 2 : VÉRIFICATION ET INSTALLATION DES DÉPENDANCES ---
echo "2. Vérification des dépendances Ruby (et réinstallation complète)..."
# Cette étape va réinstaller toutes les gems dans vendor/bundle/ car il a été supprimé.
bundle install 

# --- ÉTAPE 3 : RECHERCHE DE PORT LIBRE ---
START_PORT=3000
MAX_PORT=3010
FREE_PORT=""

echo "3. Recherche du premier port libre entre $START_PORT et $MAX_PORT..."

for (( PORT = $START_PORT; PORT <= $MAX_PORT; PORT++ )); do
    # Vérifie si le port est en écoute. On utilise 'ss' ou 'netstat'
    # Utiliser 'lsof' est plus fiable sur macOS
    if ! lsof -i :$PORT -P -n | grep -q LISTEN; then
        FREE_PORT=$PORT
        break
    fi
done

if [ -z "$FREE_PORT" ]; then
    echo "ERREUR: Aucun port libre trouvé entre $START_PORT et $MAX_PORT. Veuillez libérer un port manuellement."
    exit 1
fi

# --- ÉTAPE 4 : LANCEMENT DU SERVEUR ---
echo "4. Port libre trouvé: $FREE_PORT. Lancement du serveur Sinatra..."
echo "Vérifiez l'application sur http://localhost:$FREE_PORT"
echo "Presser CTRL+C pour arrêter le serveur."

# Lancement du serveur en premier plan, utilisant config.ru
bundle exec rackup -p $FREE_PORT

echo "--- Déploiement terminé. ---"