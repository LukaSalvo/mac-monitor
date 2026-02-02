# Guide d'Utilisation des Scripts

Tous les scripts sont dans le dossier `scripts/`.

## Pour un usage normal : `deploy.sh` UNIQUEMENT

**Commande** :
```bash
./scripts/deploy.sh
```

**Ce qu'il fait** :
- Detecte ton OS et Ruby
- Nettoie le cache si necessaire
- Installe les dependances
- Cree `config/email.yml` si manquant
- **Lance le serveur** sur `http://0.0.0.0:3000`

---

## Scripts avances (optionnels)

### `install_service.sh` - Service systeme

**Usage** :
```bash
sudo ./scripts/install_service.sh
```

**Quand l'utiliser** :
- **PAS pour un usage normal !**
- Seulement si tu veux que l'app demarre **automatiquement au boot**
- Pour un serveur de production qui doit tourner 24/7

**Ce qu'il fait** :
- Cree un service systeme (launchd sur macOS, systemd sur Linux)
- L'app demarre automatiquement au demarrage de la machine
- Tourne en arriere-plan

**Controle du service** :
```bash
# macOS
launchctl list | grep macmonitor
launchctl unload ~/Library/LaunchAgents/com.*.macmonitor.plist

# Linux
sudo systemctl status mac-monitor
sudo systemctl stop mac-monitor
```

---

### `stop_service.sh` - Arreter le service

**Usage** :
```bash
./scripts/stop_service.sh
```

---

## Tableau recapitulatif

| Script | Quand l'utiliser | Ce qu'il fait |
|--------|------------------|---------------|
| **`scripts/deploy.sh`** | **Toujours** | Lance le serveur (usage normal) |
| `scripts/install_service.sh` | Optionnel | Installe service systeme (auto-start) |
| `scripts/stop_service.sh` | Optionnel | Arrete le service systeme |
| `scripts/check_dep.sh` | Optionnel | Verifie les mises a jour |

---

## Scenarios d'usage

### Scenario 1 : Developpement / Test (recommande)
```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
./scripts/deploy.sh
```
Le serveur tourne tant que le terminal est ouvert  
Ctrl+C pour arreter

---

### Scenario 2 : Serveur de production
```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
sudo ./scripts/install_service.sh
```
Le serveur demarre automatiquement au boot  
Logs dans `server.log`

**Pour arreter** :
```bash
./scripts/stop_service.sh
```

---

## Resume

**Pour 99% des cas** :
```bash
./scripts/deploy.sh
```

**Pour un serveur 24/7** :
```bash
sudo ./scripts/install_service.sh
```
