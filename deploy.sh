#!/bin/bash
# Fichier: deploy.sh (Lancement sur le premier port libre, sans tuer de processus)

echo "--- Démarrage du processus de déploiement ---"

# 1. Vérification des dépendances
echo "Vérification des dépendances Ruby..."
# S'assurer que 'rexml' et autres sont installés localement
bundle check || { 
    echo "Dépendances manquantes ou non à jour. Exécution de 'bundle install'."
    bundle install
}

# 2. Trouver un port libre (en commençant par 3000)
START_PORT=3000
MAX_PORT=3010
FREE_PORT=""

echo "Recherche du premier port libre entre $START_PORT et $MAX_PORT..."

for (( PORT = $START_PORT; PORT <= $MAX_PORT; PORT++ )); do
    # Vérifie si le port est en écoute. On utilise 'ss' (ou netstat si ss n'est pas là)
    if ! ss -tuln | grep -q ":$PORT\s"; then
        FREE_PORT=$PORT
        break
    fi
done

if [ -z "$FREE_PORT" ]; then
    echo "ERREUR: Aucun port libre trouvé entre $START_PORT et $MAX_PORT. Veuillez libérer un port manuellement."
    exit 1
fi

# 3. Lancement de la nouvelle version avec 'bundle exec'
echo "Port libre trouvé: $FREE_PORT. Lancement du serveur Sinatra..."
echo "Presser CTRL+C pour arrêter le serveur."
bundle exec rackup -p $FREE_PORT

echo "--- Déploiement terminé. Vérifiez l'application sur http://localhost:$FREE_PORT ---"