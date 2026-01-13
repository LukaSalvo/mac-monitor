#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="maintenance_check.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
OS_TYPE=$(uname -s)

echo "--- Maintenance Check Start: $DATE ---" | tee -a "$LOG_FILE"

# 1. VÉRIFICATION DES DÉPENDANCES SYSTÈME
echo "[1/3] Checking System Packages..." | tee -a "$LOG_FILE"

if [ "$OS_TYPE" == "Linux" ]; then
    # Mise à jour silencieuse du cache (nécessite souvent sudo)
    sudo apt-get update -qq
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
    echo "Linux: $UPDATES packages can be upgraded." | tee -a "$LOG_FILE"
    
elif [ "$OS_TYPE" == "Darwin" ]; then
    brew update > /dev/null
    UPDATES=$(brew outdated | wc -l)
    echo "macOS: $UPDATES brew formulae can be upgraded." | tee -a "$LOG_FILE"
fi

# 2. VÉRIFICATION DES GEMS RUBY (Projet)
echo "[2/3] Checking Ruby Gems (Bundler)..." | tee -a "$LOG_FILE"
if [ -f "Gemfile" ]; then
    # 'bundle outdated' renvoie un code erreur si des gems sont à jour
    OUTDATED_GEMS=$(bundle outdated --parseable 2>/dev/null)
    GEM_COUNT=$(echo "$OUTDATED_GEMS" | grep -v '^$' | wc -l)
    echo "Project: $GEM_COUNT gems are outdated." | tee -a "$LOG_FILE"
    if [ "$GEM_COUNT" -gt 0 ]; then
        echo "$OUTDATED_GEMS" >> "$LOG_FILE"
    fi
else
    echo "Error: Gemfile not found in current directory." | tee -a "$LOG_FILE"
fi

# 3. VÉRIFICATION DES OUTILS CRITIQUES
echo "[3/3] Checking Core Tools..." | tee -a "$LOG_FILE"
for tool in ruby nmap git; do
    if command -v $tool >/dev/null 2>&1; then
        echo "OK: $tool is installed ($($tool --version | head -n 1))" | tee -a "$LOG_FILE"
    else
        echo "WARNING: $tool is MISSING!" | tee -a "$LOG_FILE"
    fi
done

echo "--- Check Finished ---" | tee -a "$LOG_FILE"