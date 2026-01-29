# Documentation CI/CD - Mac Monitor

Ce document detaille le fonctionnement de la pipeline d'integration et de deploiement continu mise en place pour le projet.

## Architecture du Workflow

Le fichier de configuration se trouve dans .github/workflows/ci.yml. Il automatise la surveillance du code via deux etapes distinctes.

### 1. Audit de Securite (Job: security-audit)
Ce job s'execute sur Ubuntu (Linux). Il utilise l'outil bundler-audit pour :
- Mettre a jour la base de donnees des vulnerabilites CVE (Common Vulnerabilities and Exposures).
- Analyser le fichier Gemfile.lock.
- Bloquer la suite du workflow si une dependance presente une faille critique.

### 2. Test de Deploiement (Job: deploy-test)
Ce job utilise une strategie de matrice pour tester l'application simultanement sur :
- Ubuntu (Linux)
- macOS (Darwin)

Il ne s'execute que sur les branches main ou master et necessite la reussite de l'audit de securite.



## Fonctionnement du script deploy.sh

Le script deploy.sh contient la logique de gestion du serveur. Il est conçu pour etre compatible avec les deux systemes d'exploitation et distingue l'environnement local de l'environnement GitHub Actions.

### Logique de detection du systeme
- Sur macOS : Utilise la commande lsof pour verifier la disponibilite des ports.
- Sur Linux : Utilise la commande ss pour verifier la disponibilite des ports.

### Logique d'environnement (Variable GITHUB_ACTIONS)
- Mode CI : Le serveur est lance en arriere-plan. Un test de connectivite via curl est effectue. Si l'application repond avec un code HTTP 200, le serveur est eteint et le test est valide.
- Mode Local : Le serveur est lance au premier plan de maniere persistante pour permettre le developpement.

## Installation et Utilisation

### Prerequis
- Ruby 3.2
- Bundler
- Permissions d'execution sur le script

### Commandes
Pour initialiser les permissions du script :
chmod +x deploy.sh

Pour executer le script localement :
./deploy.sh

## Maintenance et Debugging

En cas d'echec du workflow sur GitHub Actions :
1. Consulter l'onglet Actions du depot.
2. Si le job deploy-test echoue, les logs du serveur sont affiches dans la console via la lecture du fichier server.log.
3. Verifier la compatibilite des Gems natives (extensions C) entre Linux et macOS.







