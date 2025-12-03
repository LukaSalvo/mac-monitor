
#!/usr/bin/env bash
set -euo pipefail

# setup.sh
# Stop and restart the docker-compose stack for this project.
# Usage: ./setup.sh

readonly PROGNAME=$(basename "$0")

err() { echo "$PROGNAME: $*" >&2; }

# Ensure Docker is installed
if ! command -v docker >/dev/null 2>&1; then
	err "Docker CLI not found. Please install Docker Desktop: https://www.docker.com/products/docker-desktop"
	exit 1
fi

# Choose compose command: prefer `docker compose` (v2+), fallback to `docker-compose`
COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
	COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
	COMPOSE_CMD="docker-compose"
else
	err "Docker Compose not available. Install docker-compose or use Docker v20.10+ (with 'docker compose')."
	exit 1
fi

# Change to repository root (script directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Using compose command: $COMPOSE_CMD"

echo "Stopping existing containers (this may take a few seconds)..."
# remove orphans to keep environment clean
eval "$COMPOSE_CMD" down --remove-orphans

echo "Building images and starting containers in detached mode..."
eval "$COMPOSE_CMD" up --build -d

echo "Stack restarted. Run '$COMPOSE_CMD ps' to list running services."

