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

# Vérification de Ruby
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby n'est pas installé !"
    echo ""
    if [[ "$OS" == "macOS" ]]; then
        echo "Installation recommandée:"
        echo "  brew install ruby"
    elif [[ "$OS" == "Linux" ]]; then
        echo "Installation recommandée:"
        echo "  sudo apt install ruby ruby-dev build-essential  # Ubuntu/Debian"
        echo "  sudo dnf install ruby ruby-devel gcc make       # Fedora/RHEL"
    fi
    exit 1
fi

RUBY_VERSION=$(ruby -v | awk '{print $2}')
echo "💎 Ruby version: $RUBY_VERSION"

# Extraction de la version majeure.mineure
RUBY_MAJOR=$(echo $RUBY_VERSION | cut -d. -f1)
RUBY_MINOR=$(echo $RUBY_VERSION | cut -d. -f2)

echo ""

# Nettoyage si Ruby 4.0+ ou si problème de bundler
if [[ $RUBY_MAJOR -ge 4 ]] || [[ $RUBY_MAJOR -eq 3 && $RUBY_MINOR -ge 2 ]]; then
    echo "⚠️  Ruby $RUBY_VERSION détecté (3.2+ ou 4.0+)"
    echo "🧹 Nettoyage du cache vendor pour éviter les conflits..."
    rm -rf vendor/bundle .bundle
    echo "✅ Cache nettoyé"
    echo ""
fi

# Installation/Mise à jour de Bundler
echo "📦 Vérification de Bundler..."
if ! command -v bundle &> /dev/null; then
    echo "Installation de Bundler..."
    gem install bundler
else
    BUNDLER_VERSION=$(bundle -v | awk '{print $3}')
    echo "Bundler version: $BUNDLER_VERSION"
    
    # Mise à jour si version trop ancienne
    if [[ $RUBY_MAJOR -ge 4 ]]; then
        echo "Mise à jour de Bundler pour Ruby 4.0+..."
        gem install bundler
    fi
fi

echo ""

# Configuration email.yml si manquant
if [[ ! -f "config/email.yml" ]]; then
    echo "⚠️  Fichier config/email.yml manquant"
    if [[ -f "config/email.yml.example" ]]; then
        echo "📋 Copie du template..."
        cp config/email.yml.example config/email.yml
        echo "✅ Fichier créé: config/email.yml"
        echo ""
        echo "⚠️  IMPORTANT: Éditez config/email.yml avec vos credentials !"
        echo "   - Gmail App Password: https://myaccount.google.com/apppasswords"
        echo "   - Discord Webhook: Paramètres du channel Discord"
        echo ""
    else
        echo "❌ Template config/email.yml.example introuvable !"
        exit 1
    fi
fi

# Installation des dépendances
echo "📦 Installation des dépendances..."
bundle config set --local path 'vendor/bundle'
bundle install

echo ""
echo "✅ Installation terminée !"
echo ""

# Démarrage du serveur
echo "🚀 Démarrage du serveur sur http://0.0.0.0:3000"
echo "   (Accessible depuis le réseau local)"
echo ""
echo "Appuyez sur Ctrl+C pour arrêter"
echo ""

bundle exec rackup -p 3000 --host 0.0.0.0