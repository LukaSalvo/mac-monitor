#!/bin/bash
set -euo pipefail

echo "=== DACS Supervision - Démarrage de l'Agent Docker ==="

# --- CONFIGURATION INITIALE ---
SUPERVISION_DIR="Supervision"
SSH_KEY="$HOME/.ssh/id_audit"
CONTAINER_NAME="system-monitor-agent"
DOCKER_IMAGE_TAG="dacs-monitor"
APP_PORT="3000"

# Détection utilisateur & IP
USER_NAME=$(whoami)

# Utilise une méthode de détection d'IP robuste
LOCAL_IP=$(
    if command -v ip >/dev/null 2>&1; then
        # Linux (méthode `ip route`)
        ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1
    elif command -v ifconfig >/dev/null 2>&1; then
        # macOS/BSD (méthode `ifconfig`)
        ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n1
    else
        # Tentative d'utilisation de `hostname -I` comme dernier recours
        hostname -I 2>/dev/null | awk '{print $1}' | head -n1
    fi
)

# Nettoyage de la variable au cas où elle contiendrait des espaces
LOCAL_IP=$(echo "$LOCAL_IP" | xargs)

if [ -z "$LOCAL_IP" ]; then
    echo "ERREUR: Impossible de détecter l'IP hôte. Veuillez vérifier votre connexion."
    exit 1
fi

echo "Utilisateur : $USER_NAME"
echo "IP hôte    : $LOCAL_IP"

# --- GESTION DE LA CLÉ SSH (Modèle fiable de votre ancien projet) ---
echo "--- 🔑 Vérification et configuration de la clé SSH ---"

if [ ! -f "$SSH_KEY" ]; then
  echo "Clé SSH d'audit introuvable. Génération de $SSH_KEY (sans passphrase)..."
  mkdir -p "${HOME}/.ssh"
  # Utilisation de rsa comme dans l'ancien projet (plus universel que ed25519 dans les vieux Dockerfiles)
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" >/dev/null
  chmod 600 "$SSH_KEY" 
  echo "Clé générée : $SSH_KEY"
else
  echo "Clé SSH trouvée : $SSH_KEY"
fi

# Assurer que la clé publique est dans authorized_keys pour autoriser la connexion locale
AUTH_FILE="${HOME}/.ssh/authorized_keys"
PUBKEY_CONTENT=$(cat "${SSH_KEY}.pub")

mkdir -p "${HOME}/.ssh"
touch "${AUTH_FILE}"
chmod 700 "${HOME}/.ssh"
chmod 600 "${AUTH_FILE}"

if ! grep -qxF "${PUBKEY_CONTENT}" "${AUTH_FILE}"; then
  echo "Ajout de la clé publique à ${AUTH_FILE} pour autoriser les connexions locales."
  cat "${SSH_KEY}.pub" >> "${AUTH_FILE}"
fi
echo "Configuration SSH pour l'hôte terminée."


# --- PRÉPARATION DOCKER ---
echo "--- 🐳 Construction et Lancement du Moniteur ---"
if [ ! -d "$SUPERVISION_DIR" ]; then
    echo "ERREUR: Le dossier '$SUPERVISION_DIR' est introuvable."
    exit 1
fi

# Rendre le script exécutable (en cas de recréation)
chmod +x "$0"

cd "$SUPERVISION_DIR"

echo "Arrêt et suppression du conteneur précédent ($CONTAINER_NAME)..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "Construction de l'image Docker ($DOCKER_IMAGE_TAG)..."
docker build -t "$DOCKER_IMAGE_TAG" .

echo "Démarrage du conteneur..."

# La commande docker run
# --network host: Permet au conteneur de voir l'hôte directement avec l'IP locale (crucial pour le SSH)
docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$APP_PORT:$APP_PORT" \
    --network host \
    -v "$SSH_KEY":/root/.ssh/id_audit:ro \
    -e REMOTE_USER="$USER_NAME" \
    -e REMOTE_HOST_AGENT="$LOCAL_IP" \
    -e SSH_KEY_PATH=/root/.ssh/id_audit \
    "$DOCKER_IMAGE_TAG"

echo "Attente du démarrage de l'application..."
sleep 5

# --- VÉRIFICATION ---
echo "--- ✅ Vérification finale ---"
if curl -s "http://localhost:$APP_PORT/api/system" | grep -q "cpu_usage"; then
    echo "Application OK : Dashboard accessible sur http://localhost:$APP_PORT"
else
    echo "Application KO : Le conteneur ne répond pas. Vérifiez les logs avec 'docker logs $CONTAINER_NAME'"
fi

echo ""
echo "TOUT EST PRÊT !"
echo "   Application : http://localhost:$APP_PORT"
echo "   Conteneur   : $CONTAINER_NAME"
echo ""
echo "Astuce : Pour voir les logs → docker logs -f $CONTAINER_NAME"
echo "Astuce : Pour l'arrêter → docker stop $CONTAINER_NAME"

