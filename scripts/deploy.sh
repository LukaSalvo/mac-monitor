#!/bin/bash
# Script de déploiement automatique - Mac Monitor
# Compatible macOS & Linux, Ruby 2.6 à 4.0+

set -e  # Arrêt en cas d'erreur
cd "$(dirname "$0")/.."
echo "[DIR] Dossier de travail : $(pwd)"
echo "=============================================="
echo "[START] Mac Monitor - Déploiement automatique"
echo "=============================================="
echo ""

# Détection de l'OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="Linux"
else
    OS="Unknown"
fi

echo "[INFO] OS détecté: $OS"

# Configuration automatique de Ruby (Homebrew si disponible)
if [[ "$OS" == "macOS" ]]; then
    # Vérifier si Homebrew Ruby est installé
    if [ -d "/opt/homebrew/opt/ruby" ]; then
        echo "[RUBY] Homebrew Ruby détecté, configuration du PATH..."
        export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
        export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
    elif [ -d "/usr/local/opt/ruby" ]; then
        echo "[RUBY] Homebrew Ruby détecté (Intel), configuration du PATH..."
        export PATH="/usr/local/opt/ruby/bin:$PATH"
        export PATH="/usr/local/lib/ruby/gems/4.0.0/bin:$PATH"
    else
        echo "[WARNING] Ruby système détecté. Pour de meilleures performances, installez:"
        echo "  brew install ruby"
    fi
fi

# Au début de deploy.sh, après la détection de l'OS
if [ -d ".git" ]; then
    echo "[SYNC] Synchronisation des versions avec GitHub..."
    git fetch --tags --quiet
fi

# Vérification de Ruby
if ! command -v ruby &> /dev/null; then
    echo "[ERROR] Ruby n'est pas installé !"
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
echo "[RUBY] Ruby version: $RUBY_VERSION"

# Extraction de la version majeure.mineure
RUBY_MAJOR=$(echo $RUBY_VERSION | cut -d. -f1)
RUBY_MINOR=$(echo $RUBY_VERSION | cut -d. -f2)

# Nettoyage si Ruby 3.2+ ou 4.0+
if [[ $RUBY_MAJOR -ge 4 ]] || [[ $RUBY_MAJOR -eq 3 && $RUBY_MINOR -ge 2 ]]; then
    echo "[CLEAN] Nettoyage du cache vendor pour éviter les conflits..."
    rm -rf vendor/bundle .bundle
    rm -f Gemfile.lock
fi

# Installation/Mise à jour de Bundler
if ! command -v bundle &> /dev/null; then
    echo "[BUNDLER] Installation de Bundler..."
    if [[ $RUBY_MAJOR -lt 3 ]] || [[ $RUBY_MAJOR -eq 3 && $RUBY_MINOR -lt 1 ]]; then
        # Ruby < 3.1 : utiliser Bundler 2.3.26 (dernière version compatible)
        gem install bundler -v 2.3.26 --user-install
    else
        # Ruby >= 3.1 : utiliser la dernière version
        gem install bundler
    fi
else
    echo "[BUNDLER] Bundler déjà installé"
    if [[ $RUBY_MAJOR -ge 4 ]]; then
        echo "[BUNDLER] Mise à jour pour Ruby 4.0+..."
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
echo "[INSTALL] Installation des dépendances..."
bundle config set --local path 'vendor/bundle'
bundle install

echo ""
echo "[OK] Installation terminée !"
echo ""

# --- BLOC CRITIQUE POUR LA PIPELINE ---
# Si nous sommes sur GitHub Actions, on s'arrête ici.
if [[ "$GITHUB_ACTIONS" == "true" ]]; then
    echo "[OK] Test de déploiement réussi (Mode CI détecté)."
    exit 0
fi

# Démarrage du serveur (Uniquement en local sur ton Mac)
echo "[START] Démarrage du serveur sur http://0.0.0.0:3000"
echo "Appuyez sur Ctrl+C pour arrêter"
echo ""

bundle exec rackup -p 3000 --host 0.0.0.0