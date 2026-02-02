# Mac Monitor

Un moniteur systeme leger et cross-platform (macOS & Linux) avec interface web, alertes automatiques et gestion de tickets.

## Fonctions Cles
- **Monitoring Temps Reel** : CPU, RAM, Disque, Reseau (Upload/Download), Temperature.
- **Support Multi-OS** : Logique native pour macOS (`sysctl`, `vm_stat`) et Linux (`/proc`).
- **Scanner Reseau** : Decouverte des appareils connectes (Nmap ou ARP).
- **Automatisation Phase 2** :
    - **Tickets Incidents** : Creation automatique de tickets si erreur detectee dans les logs.
    - **Notifications** : Envoi d'emails pour les alertes critiques.
    - **Updates** : Verification des mises a jour systeme et Gems.

## Installation Rapide

### Methode 1 : Installation automatique (recommandee)

```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
./scripts/deploy.sh
```

Le script `deploy.sh` fait **tout automatiquement** :
- Detecte votre OS (macOS/Linux)
- Detecte votre version de Ruby
- Nettoie le cache si Ruby 4.0+ (evite les erreurs)
- Met a jour Bundler si necessaire
- Installe les dependances
- Cree `config/email.yml` depuis le template
- Lance le serveur sur `http://0.0.0.0:3000`

### Methode 2 : Installation manuelle

1. **Prerequis** : Avoir Ruby installe.
2. **Lancer le script de deploiement** :
   ```bash
   ./scripts/deploy.sh
   ```
   Ce script installe les dependances (gems) localement et lance le serveur sur le port 3000.

## Utilisation

Accedez a l'interface via votre navigateur :
- **Local** : `http://localhost:3000`
- **Reseau** : `http://<IP_DE_LA_MACHINE>:3000`

## Installation en Service (Demarrage Auto)

Pour lancer l'application automatiquement au demarrage du systeme :

```bash
sudo ./scripts/install_service.sh
```
- **Linux** : Cree un service `systemd`.
- **macOS** : Cree un agent `launchd`.

## Architecture

```
mac-monitor/
|-- app.rb              # Point d'entree serveur (Sinatra)
|-- config.ru           # Configuration Rack
|-- Gemfile             # Dependances Ruby
|-- lib/                # Logique modulaire (SystemMonitor, NetworkMonitor, etc.)
|-- public/             # Interface Frontend (HTML/JS/CSS)
|-- scripts/            # Scripts de deploiement et maintenance
|-- docs/               # Documentation detaillee
|-- bin/                # Scripts executables (cron)
|-- config/             # Fichiers de configuration
+-- test/               # Tests
```

Voir [docs/USAGE.md](docs/USAGE.md) pour plus de details sur les scripts.

---

## Automatisation Avancee (notifications Mail + Discord)

### Fonctionnalites
- **Notifications Email** : Envoi automatique via Gmail SMTP lors de creation de tickets
- **Notifications Discord** : Webhooks colores
- **Stress Test** : Simulation de charge systeme (CPU, RAM, logs) avec controles Start/Stop

### Configuration

1. **Copier le template de configuration** :
   ```bash
   cp config/email.yml.example config/email.yml
   ```

2. **Editer `config/email.yml`** avec vos credentials :
   - **Gmail** : Creer un App Password (https://myaccount.google.com/apppasswords)
   - **Discord** : Creer un webhook dans les parametres du channel

### Test rapide
```bash
bundle exec rackup -p 3000
# Aller dans Alertes -> Demarrer Stress Test
# Verifier Gmail et Discord
```
