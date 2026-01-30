#!/bin/bash
# Script d'installation rapide - Mac Monitor
# Usage: curl -sSL https://raw.githubusercontent.com/USER/mac-monitor/main/install.sh | bash

set -e

echo "🚀 Installation de Mac Monitor"
echo "==============================="
echo ""

# Vérification de Git
if ! command -v git &> /dev/null; then
    echo "❌ Git n'est pas installé !"
    exit 1
fi

# Vérification de Ruby
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby n'est pas installé !"
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Installation recommandée:"
        echo "  brew install ruby"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Installation recommandée:"
        echo "  sudo apt install ruby ruby-dev build-essential"
    fi
    exit 1
fi

# Clone du repo
REPO_URL="${1:-https://github.com/LukaSalvo/mac-monitor.git}"
TARGET_DIR="${2:-mac-monitor}"

echo "📥 Clonage du repository..."
git clone "$REPO_URL" "$TARGET_DIR"
cd "$TARGET_DIR"

echo ""
echo "✅ Repository cloné !"
echo ""

# Lancer le déploiement
./deploy.sh
