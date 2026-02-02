# Guide d'Utilisation des Scripts

## Pour un usage normal : `deploy.sh` UNIQUEMENT

**Commande** :
```bash
./deploy.sh
```

**Ce qu'il fait** :
- Detecte ton OS et Ruby
- Nettoie le cache si necessaire
- Installe les dependances
- Cree `config/email.yml` si manquant
- **Lance le serveur** sur `http://0.0.0.0:3000`

**C'est tout ce dont tu as besoin !**

---

## Scripts avances (optionnels)

### `install_service.sh` - Service systeme

**Usage** :
```bash
sudo ./install_service.sh
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
./stop_service.sh
```

**Quand l'utiliser** :
- Seulement si tu as installe le service avec `install_service.sh`
- Pour arreter le service systeme

---

## Tableau recapitulatif

| Script | Quand l'utiliser | Ce qu'il fait |
|--------|------------------|---------------|
| **`deploy.sh`** | **Toujours** | Lance le serveur (usage normal) |
| `install_service.sh` | Optionnel | Installe service systeme (auto-start) |
| `stop_service.sh` | Optionnel | Arrete le service systeme |

---

## Scenarios d'usage

### Scenario 1 : Developpement / Test (recommande)
```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
./deploy.sh
```
Le serveur tourne tant que le terminal est ouvert  
Ctrl+C pour arreter  
Facile a relancer

---

### Scenario 2 : Serveur de production
```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
./deploy.sh  # D'abord installer les dependances
sudo ./install_service.sh
```
Le serveur demarre automatiquement au boot  
Tourne en arriere-plan  
Logs dans `server.log`

**Pour arreter** :
```bash
./stop_service.sh
```

---

## Erreur commune

**Si tu lances `install_service.sh` puis `deploy.sh`** :
- Le service tourne deja en arriere-plan
- `deploy.sh` va essayer de lancer un 2eme serveur
- Erreur : port 3000 deja utilise

**Solution** :
1. Soit utilise **uniquement `deploy.sh`** (recommande pour dev)
2. Soit utilise **uniquement `install_service.sh`** (pour production)

---

## Resume

**Pour 99% des cas** :
```bash
./deploy.sh
```

**Pour un serveur qui doit tourner 24/7** :
```bash
./deploy.sh  # Installer les dependances d'abord
sudo ./install_service.sh
```

**C'est tout !**
