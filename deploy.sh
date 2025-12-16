#!/bin/bash
# Fichier: deploy.sh

echo "--- Démarrage du processus de déploiement ---"

# 1. Vérification et installation des dépendances
echo "Vérification des dépendances Ruby..."
bundle check || { 
    echo "Dépendances manquantes ou non à jour. Exécution de 'bundle install'."
    bundle install
}

# 2. Arrêt du processus existant
PID=$(lsof -i :3000 -t)
if [ -n "$PID" ]; then
    echo "Arrêt de l'ancien processus sur le port 3000 (PID: $PID)"
    kill $PID
    sleep 2
fi

# 3. Lancement de la nouvelle version avec 'bundle exec' et en premier plan
# rackup va maintenant trouver et utiliser config.ru qui lance server.rb
echo "Lancement du nouveau serveur Sinatra (rackup) en PREMIER PLAN..."
echo "Presser CTRL+C pour arrêter le serveur."
bundle exec rackup -p 3000

echo "--- Déploiement terminé. Vérifiez l'application sur http://localhost:3000 ---"