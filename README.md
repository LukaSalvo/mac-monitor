# Mac Monitor 🖥️

Un moniteur système léger et cross-platform (macOS & Linux) avec interface web, alertes automatiques et gestion de tickets.

## 🚀 Fonctions Clés
- **Monitoring Temps Réel** : CPU, RAM, Disque, Réseau (Upload/Download), Température.
- **Support Multi-OS** : Logique native pour macOS (`sysctl`, `vm_stat`) et Linux (`/proc`).
- **Scanner Réseau** : Découverte des appareils connectés (Nmap ou ARP).
- **Automatisation Phase 2** :
    - **Tickets Incidents** : Création automatique de tickets si erreur détectée dans les logs.
    - **Notifications** : Envoi d'emails pour les alertes critiques.
    - **Updates** : Vérification des mises à jour système et Gems.

## 🛠️ Installation Rapide

### Méthode 1 : Installation automatique (recommandée)

```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
./deploy.sh
```

Le script `deploy.sh` fait **tout automatiquement** :
- ✅ Détecte votre OS (macOS/Linux)
- ✅ Détecte votre version de Ruby
- ✅ Nettoie le cache si Ruby 4.0+ (évite les erreurs)
- ✅ Met à jour Bundler si nécessaire
- ✅ Installe les dépendances
- ✅ Crée `config/email.yml` depuis le template
- ✅ Lance le serveur sur `http://0.0.0.0:3000`

### Méthode 2 : Installation manuelle

1. **Prérequis** : Avoir Ruby installé.
2. **Lancer le script de déploiement** :
   ```bash
   ./deploy.sh
   ```
   Ce script installe les dépendances (gems) localement et lance le serveur sur le port 3000.



## 🖥️ Utilisation

Accédez à l'interface via votre navigateur :
- **Local** : `http://localhost:3000`
- **Réseau** : `http://<IP_DE_LA_MACHINE>:3000`

## 📦 Installation en Service (Démarrage Auto)

Pour lancer l'application automatiquement au démarrage du système :

```bash
sudo ./install_service.sh
```
- **Linux** : Crée un service `systemd`.
- **macOS** : Crée un agent `launchd`.

## 📂 Architecture
- `app.rb` : Point d'entrée serveur (Sinatra).
- `lib/` : Logique modulaire (`SystemMonitor`, `NetworkMonitor`, `AlertManager`).
- `public/` : Interface Frontend (HTML/JS).
- `deploy.sh` : Script d'installation et lancement.

---

## 🤖 Automatisation Avancée (notifications Mail + Discord)

### Fonctionnalités
- **Notifications Email** : Envoi automatique via Gmail SMTP lors de création de tickets
- **Notifications Discord** : Webhooks colorés
- **Stress Test** : Simulation de charge système (CPU, RAM, logs) avec contrôles Start/Stop

### Configuration

1. **Copier le template de configuration** :
   ```bash
   cp config/email.yml.example config/email.yml
   ```

2. **Éditer `config/email.yml`** avec vos credentials :
   - **Gmail** : Créer un App Password (https://myaccount.google.com/apppasswords)
   - **Discord** : Créer un webhook dans les paramètres du channel

### Fichiers créés
- `lib/notifier.rb` : Module Email + Discord
- `lib/stress_tester.rb` : Simulation de charge
- `config/email.yml.example` : Template de configuration
- `test/test_email.rb` / `test/test_discord.rb` : Scripts de test

### Fichiers modifiés
- `Gemfile` : Ajout gem `mail`
- `lib/ticket_store.rb` : Hook notifications automatiques
- `app.rb` : API stress test (`/api/stress-test/*`)
- `public/index.html` : Boutons stress test
- `public/app.js` : Logique frontend

### Test rapide
```bash
bundle exec rackup -p 3000
# Aller dans Alertes → Démarrer Stress Test
# Vérifier Gmail et Discord
```
