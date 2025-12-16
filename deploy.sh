#!/bin/bash
# Fichier: deploy.sh (Lancement sur le premier port libre, sans tuer de processus)

echo "--- Démarrage du processus de déploiement ---"

# --- ÉTAPE 1 : NETTOYAGE & DÉSACTIVATION INSTALLATION LOCALE ---
echo "1. Nettoyage des logs et des anciens artefacts..."

# Supprimer les fichiers de logs générés (si ils existent)
rm -f app.log server.log

# Supprimer le répertoire des dépendances installées localement pour libérer de l'espace disque.
if [ -d "vendor/bundle" ]; then
    echo "Suppression du dossier 'vendor/bundle' pour économiser de la mémoire..."
    rm -rf vendor/bundle
fi

# DÉSACTIVATION DE L'INSTALLATION LOCALE : 
# Cela garantit que les prochaines dépendances seront installées dans l'emplacement système
# par défaut (ex: /opt/homebrew/lib/ruby/gems/...).
echo "Configuration de Bundler pour utiliser l'emplacement système (résoud le problème de mémoire disque)..."
bundle config unset path

# --- ÉTAPE 2 : VÉRIFICATION ET INSTALLATION DES DÉPENDANCES ---
echo "2. Vérification et installation des dépendances Ruby (dans l'emplacement système)..."
# 'bundle install' utilisera maintenant l'emplacement système.
bundle install 

# --- ÉTAPE 3 : RECHERCHE DE PORT LIBRE ---
START_PORT=3000
MAX_PORT=3010
FREE_PORT=""

echo "3. Recherche du premier port libre entre $START_PORT et $MAX_PORT..."

for (( PORT = $START_PORT; PORT <= $MAX_PORT; PORT++ )); do
    # Utiliser 'lsof' est plus fiable sur macOS pour vérifier si un port est en écoute.
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