# Mac Monitor

Un moniteur systeme leger et cross-platform (macOS & Linux) avec interface web, alertes automatiques et gestion de tickets.

**Projet realise par :** Doryan, Amin, Luka et Leo

---

## Automatisations Implementees

Ce projet implemente plusieurs automatisations pour la surveillance et la maintenance du systeme :

### 1. Tickets d'Incidents Automatiques (Leo)

**Fichiers :** `lib/ticket_engine.rb`, `lib/ticket_store.rb`

Le systeme cree automatiquement des tickets lorsque certains seuils sont depasses :

| Metrique | Seuil Critique | Seuil Retour Normal |
|----------|----------------|---------------------|
| CPU | > 85% | < 70% |
| Disque | > 90% | < 85% |
| RAM libre | < 800 MB | > 1200 MB |

**Fonctionnalites :**
- Hystérésis pour eviter les faux positifs (open/close en boucle)
- Fusion automatique des tickets dupliques (occurrences++)
- Fingerprint pour identifier les incidents recurrents

---

### 2. Surveillance des Logs en Temps Reel (Leo)

**Fichiers :** `lib/log_watcher.rb`, `lib/fatal_detector.rb`

- Detection des patterns `FATAL`, `ERROR`, `CRITICAL` dans les logs
- Creation automatique de tickets lors de la detection
- Scan des fichiers de log pour les erreurs fatales

---

### 3. Notifications Email (Doryan)

**Fichiers :** `lib/notifier.rb`, `config/email.yml.example`

- Envoi automatique d'emails via Gmail SMTP lors de la creation de tickets
- Configuration SMTP personnalisable
- Support App Password pour Gmail

**Configuration :**
```bash
cp config/email.yml.example config/email.yml
# Editer avec vos credentials Gmail
```

---

### 4. Notifications Discord (Doryan)

**Fichier :** `lib/notifier.rb`

- Webhooks Discord avec embeds colores selon la gravite
- Couleurs : bleu (info), jaune (warning), rouge (critical)
- Affichage des details du ticket (ID, niveau, description, occurrences)

---

### 5. Deploiement Automatique (Luka, Amin)

**Fichier :** `scripts/deploy.sh`

Le script fait tout automatiquement :
- Detection de l'OS (macOS/Linux)
- Detection de la version Ruby
- Nettoyage du cache si Ruby 3.2+ (evite les conflits)
- Installation des dependances via Bundler
- Creation du fichier de config email
- Lancement du serveur

```bash
./scripts/deploy.sh
```

---

### 6. CI/CD GitHub Actions (Luka)

**Fichiers :** `.github/workflows/ci.yml`, `.github/dependabot.yml`

Pipeline automatisee en 3 etapes :

1. **Audit de Securite** : Scan des vulnerabilites avec `bundler-audit`
2. **Tests de Deploiement** : Execution sur Ubuntu ET macOS en parallele
3. **Creation de Tags** : Increment automatique de version (v1.0.X)

**Fonctionnalites :**
- Declenchement sur push/PR vers `main`
- Detection des fichiers critiques modifies (`app.rb`, `deploy.sh`, `public/`)
- Versioning semantique automatique

---

### 7. Services Systeme (Amin)

**Fichiers :** `scripts/install_service.sh`, `scripts/stop_service.sh`

Installation en tant que service pour demarrage automatique au boot :

| OS | Type de Service | Fichier cree |
|----|-----------------|--------------|
| Linux | systemd | `/etc/systemd/system/mac-monitor.service` |
| macOS | launchd | `~/Library/LaunchAgents/com.*.macmonitor.plist` |

```bash
sudo ./scripts/install_service.sh  # Installer
./scripts/stop_service.sh          # Arreter
```

---

### 8. Verification des Dependances (Amin)

**Fichier :** `scripts/check_dep.sh`

- Verification des mises a jour systeme (apt/brew)
- Verification des gems Ruby outdated
- Verification des outils critiques (ruby, nmap, git)

---

### 9. Stress Test Systeme (Doryan)

**Fichier :** `lib/stress_tester.rb`

Simulation de charge pour tester le systeme d'alertes :
- Stress CPU (calculs de nombres premiers)
- Stress RAM (allocation temporaire ~100MB)
- Generation de logs d'erreur

Accessible via l'interface web : Alertes > Demarrer Stress Test

---

### 11. Scanner Reseau Avance & Controle a Distance

**Fichiers :** `lib/network_monitor.rb`, `lib/network_actions.rb`

Le scanner reseau (`Outils > Scanner Reseau`) decouvre les appareils du LAN et remonte
desormais davantage d'informations, plus des actions de controle a distance :

**Decouverte enrichie :**
- Adresse MAC + fabricant (vendor) via nmap, avec repli ARP (`arp -a` / `ip neigh`)
- Latence (ping ICMP) mesuree pour chaque appareil
- Detection de la machine locale

**Actions sur les appareils :**

| Action | Methode | Pre-requis |
|--------|---------|------------|
| Allumer (Wake-on-LAN) | Paquet magique UDP (ports 9/7, broadcast) | Carte reseau cible avec WoL active |
| Eteindre / Redemarrer (Linux/macOS) | SSH (`sudo shutdown`) | Cle SSH autorisee ou `sshpass`, sudo sans mdp |
| Eteindre / Redemarrer (Windows) | Samba `net rpc shutdown` | `net` installe cote serveur, compte admin distant |

**Endpoints API :**
- `GET  /api/network/scan` — scan complet (MAC, vendor, latence)
- `GET  /api/network` — details des interfaces reseau locales
- `GET  /api/network/ping/:ip` — ping d'un appareil
- `POST /api/network/wake` — `{ "mac": "aa:bb:cc:dd:ee:ff" }`
- `POST /api/network/shutdown` — `{ "ip", "os": "linux|mac|windows", "user", "password", "reboot" }`

> ⚠️ Les actions d'arret/redemarrage exigent des identifiants valides sur la machine cible.
> Aucun mot de passe n'est stocke : il est transmis a la demande pour executer la commande.

---

### 10. Scripts Cron (Léo)

**Fichiers :** `bin/monitor_tickets`, `bin/daily_report`

Scripts executables pour planification cron :
- `monitor_tickets` : Collecte des metriques et creation de tickets
- `daily_report` : Rapport quotidien avec statistiques (min/max/avg)

---

## Installation

```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
./scripts/deploy.sh
```

Accedez a `http://localhost:3000`

---

## Architecture

```
mac-monitor/
|-- app.rb              # Serveur Sinatra
|-- lib/                # Modules Ruby
|   |-- system_monitor.rb
|   |-- network_monitor.rb   # Scan reseau + MAC/vendor/latence + interfaces
|   |-- network_actions.rb   # Wake-on-LAN + arret distant (SSH/SMB)
|   |-- ticket_store.rb
|   |-- ticket_engine.rb
|   |-- notifier.rb
|   |-- log_watcher.rb
|   |-- fatal_detector.rb
|   +-- stress_tester.rb
|-- scripts/            # Scripts d'automatisation
|-- public/             # Frontend
|-- docs/               # Documentation
+-- .github/workflows/  # CI/CD
```

---

## Equipe

| Membre | Contributions |
|--------|---------------|
| **Doryan** | Notifications Email, Notifications Discord, Fermeture automatique des tickets après stress test |
| **Leo** | Tickets automatiques, Surveillance logs, Moteur d'alertes,  |
| **Luka** | CI/CD GitHub Actions, Deploiement automatique |
| **Amin** | Services systeme, Stress test, Scripts cron, Organisation repo |
