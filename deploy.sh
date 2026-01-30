#!/bin/bash
# Script de déploiement automatique - Mac Monitor
# Compatible macOS & Linux, Ruby 2.6 à 4.0+

set -e  # Arrêt en cas d'erreur

echo "🚀 Mac Monitor - Déploiement automatique"
echo "=========================================="
echo ""

# Détection de l'OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="Linux"
else
    OS="Unknown"
fi

echo "📍 OS détecté: $OS"

# Au début de deploy.sh, après la détection de l'OS
if [ -d ".git" ]; then
    echo "🔄 Synchronisation des versions avec GitHub..."
    git fetch --tags --quiet
fi

# Vérification de Ruby
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby n'est pas installé !"
    echo ""
    if [[ "$OS" == "macOS" ]]; then
        echo "Installation recommandée:"
        echo "  brew install ruby"
    elif [[ "$OS" == "Linux" ]]; then
        echo "Installation recommandée:"
        echo "  sudo apt install ruby ruby-dev build-essential"
    fi
    exit 1
fi

RUBY_VERSION=$(ruby -v | awk '{print $2}')
echo "💎 Ruby version: $RUBY_VERSION"

# Extraction de la version majeure.mineure
RUBY_MAJOR=$(echo $RUBY_VERSION | cut -d. -f1)
RUBY_MINOR=$(echo $RUBY_VERSION | cut -d. -f2)

# Nettoyage si Ruby 3.2+ ou 4.0+
if [[ $RUBY_MAJOR -ge 4 ]] || [[ $RUBY_MAJOR -eq 3 && $RUBY_MINOR -ge 2 ]]; then
    echo "🧹 Nettoyage du cache vendor pour éviter les conflits..."
    rm -rf vendor/bundle .bundle
    rm -f Gemfile.lock
fi

# Installation/Mise à jour de Bundler
if ! command -v bundle &> /dev/null; then
    gem install bundler
else
    if [[ $RUBY_MAJOR -ge 4 ]]; then
        gem install bundler
    fi
fi

# Configuration email.yml
if [[ ! -f "config/email.yml" ]]; then
    if [[ -f "config/email.yml.example" ]]; then
        cp config/email.yml.example config/email.yml
    fi
fi

# Installation des dépendances
echo "📦 Installation des dépendances..."
bundle config set --local path 'vendor/bundle'
bundle install

echo ""
echo "✅ Installation terminée !"
echo ""

# --- BLOC CRITIQUE POUR LA PIPELINE ---
# Si nous sommes sur GitHub Actions, on s'arrête ici.
if [[ "$GITHUB_ACTIONS" == "true" ]]; then
    echo "✅ Test de déploiement réussi (Mode CI détecté)."
    exit 0
fi

# Démarrage du serveur (Uniquement en local sur ton Mac)
echo "🚀 Démarrage du serveur sur http://0.0.0.0:3000"
echo "Appuyez sur Ctrl+C pour arrêter"
echo ""

bundle exec rackup -p 3000 --host 0.0.0.0