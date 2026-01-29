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
