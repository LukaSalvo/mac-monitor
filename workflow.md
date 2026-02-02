# GitHub Actions Workflow: Mac-Monitor CI/CD

Ce depot utilise un workflow automatise pour garantir la stabilite de l'application et gerer intelligemment les versions du logiciel tournant en local.

## Cycle de Vie de la Pipeline

La pipeline se declenche a chaque **Push** ou **Pull Request** sur la branche principale `main`. Elle est divisee en trois etapes cles :

### 1. Audit de Securite (`security-audit`)
* Utilise `bundler-audit` pour scanner les dependances Ruby (Gems).
* Verifie la presence de vulnerabilites connues dans les bibliotheques utilisees.
* Bloque la suite du processus si une faille critique est detectee.

### 2. Test de Deploiement (`deploy-test`)
* Simule l'execution du script `deploy.sh` sur deux environnements : **Ubuntu** et **macOS**.
* Verifie que le serveur Sinatra demarre correctement et repond avec un code `HTTP 200`.
* Utilise un filtre (`paths-filter`) pour detecter si des fichiers importants ont ete modifies (`app.rb`, `deploy.sh`, `install_service.sh` ou le dossier `/public`).

### 3. Creation Automatique de Tag (`create-tag`)
* Cette etape s'active uniquement si les tests precedents reussissent et que des fichiers importants ont ete touches.
* **Logique de Versioning** : 
    * Recupere le dernier tag existant (ex: `v1.0.4`).
    * Incremente automatiquement le numero de correctif (Patch) pour creer la version suivante (ex: `v1.0.5`).
    * Pousse le nouveau tag sur le depot GitHub.

## Avantages pour l'Utilisateur
* **Alerte de Mise a jour** : L'application locale compare son tag Git avec le dernier tag publie sur GitHub via l'API.
* **Transparence** : Chaque modification du code genere un point de restauration officiel (Tag).
* **Fiabilite** : Impossible de pousser un code qui ne demarre pas sur macOS ou Linux.

---
*Note : Le workflow necessite les permissions "Read and Write" activees dans les reglages du depot pour pouvoir creer les tags automatiquement.*