# ÉTAPE 1: Image de base pour la construction (Passage à Go 1.24-bullseye car 1.25 n'est pas encore disponible sur Docker Hub)
FROM golang:1.24-bullseye AS builder

# Installe les dépendances nécessaires pour SSH et les outils système
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-client iproute2 procps && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copie les fichiers nécessaires à la compilation
COPY main.go go.mod go.sum ./
# Copie les fichiers web statiques (votre dashboard)
COPY web /app/web

# Télécharge les dépendances Go et construit l'exécutable
RUN go mod download
# Construit le binaire statique
RUN CGO_ENABLED=0 go build -o monitor main.go

# ÉTAPE 2: Image finale légère (Exécution)
FROM debian:bullseye-slim

# Installe l'outil SSH dans l'image finale pour la connexion à l'hôte
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-client procps net-tools && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copie l'exécutable et le dossier web depuis l'étape de construction
COPY --from=builder /app/monitor /app/monitor
COPY --from=builder /app/web /app/web

# Crée le répertoire .ssh pour l'utilisateur root dans le conteneur.
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh

# Expose le port par défaut de votre application Go
EXPOSE 3000

# Commande de lancement: exécute l'application Go
ENTRYPOINT ["/app/monitor"]