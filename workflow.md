#  GitHub Actions Workflow: Mac-Monitor CI/CD

Ce dépôt utilise un workflow automatisé pour garantir la stabilité de l'application et gérer intelligemment les versions du logiciel tournant en local.

##  Cycle de Vie de la Pipeline

La pipeline se déclenche à chaque **Push** ou **Pull Request** sur la branche principale `main`. Elle est divisée en trois étapes clés :

### 1. Audit de Sécurité (`security-audit`)
* Utilise `bundler-audit` pour scanner les dépendances Ruby (Gems).
* Vérifie la présence de vulnérabilités connues dans les bibliothèques utilisées.
* Bloque la suite du processus si une faille critique est détectée.

### 2. Test de Déploiement (`deploy-test`)
* Simule l'exécution du script `deploy.sh` sur deux environnements : **Ubuntu** et **macOS**.
* Vérifie que le serveur Sinatra démarre correctement et répond avec un code `HTTP 200`.
* Utilise un filtre (`paths-filter`) pour détecter si des fichiers importants ont été modifiés (`app.rb`, `deploy.sh`, `install_service.sh` ou le dossier `/public`).

### 3. Création Automatique de Tag (`create-tag`)
* Cette étape s'active uniquement si les tests précédents réussissent et que des fichiers importants ont été touchés.
* **Logique de Versioning** : 
    * Récupère le dernier tag existant (ex: `v1.0.4`).
    * Incrémente automatiquement le numéro de correctif (Patch) pour créer la version suivante (ex: `v1.0.5`).
    * Pousse le nouveau tag sur le dépôt GitHub.

## 📊 Avantages pour l'Utilisateur
* **Alerte de Mise à jour** : L'application locale compare son tag Git avec le dernier tag publié sur GitHub via l'API.
* **Transparence** : Chaque modification du code génère un point de restauration officiel (Tag).
* **Fiabilité** : Impossible de pousser un code qui ne démarre pas sur macOS ou Linux.

---
*Note : Le workflow nécessite les permissions "Read and Write" activées dans les réglages du dépôt pour pouvoir créer les tags automatiquement.*