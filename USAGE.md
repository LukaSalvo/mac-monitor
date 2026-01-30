# 📋 Guide d'Utilisation des Scripts

## 🎯 Pour un usage normal : `deploy.sh` UNIQUEMENT

**Commande** :
```bash
./deploy.sh
```

**Ce qu'il fait** :
- ✅ Détecte ton OS et Ruby
- ✅ Nettoie le cache si nécessaire
- ✅ Installe les dépendances
- ✅ Crée `config/email.yml` si manquant
- ✅ **Lance le serveur** sur `http://0.0.0.0:3000`

**C'est tout ce dont tu as besoin !** 🚀

---

## 🔧 Scripts avancés (optionnels)

### `install_service.sh` - Service système

**Usage** :
```bash
sudo ./install_service.sh
```

**Quand l'utiliser** :
- ❌ **PAS pour un usage normal !**
- ✅ Seulement si tu veux que l'app démarre **automatiquement au boot**
- ✅ Pour un serveur de production qui doit tourner 24/7

**Ce qu'il fait** :
- Crée un service système (launchd sur macOS, systemd sur Linux)
- L'app démarre automatiquement au démarrage de la machine
- Tourne en arrière-plan

**Contrôle du service** :
```bash
# macOS
launchctl list | grep macmonitor
launchctl unload ~/Library/LaunchAgents/com.*.macmonitor.plist

# Linux
sudo systemctl status mac-monitor
sudo systemctl stop mac-monitor
```

---

### `stop_service.sh` - Arrêter le service

**Usage** :
```bash
./stop_service.sh
```

**Quand l'utiliser** :
- ✅ Seulement si tu as installé le service avec `install_service.sh`
- ✅ Pour arrêter le service système

---

## 📊 Tableau récapitulatif

| Script | Quand l'utiliser | Ce qu'il fait |
|--------|------------------|---------------|
| **`deploy.sh`** | **Toujours** | Lance le serveur (usage normal) |
| `install_service.sh` | Optionnel | Installe service système (auto-start) |
| `stop_service.sh` | Optionnel | Arrête le service système |
| `install.sh` | Jamais directement | Appelé par curl (installation distante) |

---

## 🎓 Scénarios d'usage

### Scénario 1 : Développement / Test (recommandé)
```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
./deploy.sh
```
✅ Le serveur tourne tant que le terminal est ouvert  
✅ Ctrl+C pour arrêter  
✅ Facile à relancer

---

### Scénario 2 : Serveur de production
```bash
git clone https://github.com/LukaSalvo/mac-monitor.git
cd mac-monitor
sudo ./install_service.sh
```
✅ Le serveur démarre automatiquement au boot  
✅ Tourne en arrière-plan  
✅ Logs dans `server.log`

**Pour arrêter** :
```bash
./stop_service.sh
```

---

## ⚠️ Erreur commune

**Si tu lances `install_service.sh` puis `deploy.sh`** :
- Le service tourne déjà en arrière-plan
- `deploy.sh` va essayer de lancer un 2ème serveur
- ❌ Erreur : port 3000 déjà utilisé

**Solution** :
1. Soit utilise **uniquement `deploy.sh`** (recommandé pour dev)
2. Soit utilise **uniquement `install_service.sh`** (pour production)

---

## 🚀 Résumé

**Pour 99% des cas** :
```bash
./deploy.sh
```

**Pour un serveur qui doit tourner 24/7** :
```bash
sudo ./install_service.sh
```

**C'est tout !** 🎉
