#!/usr/bin/env bash
set -euo pipefail

echo "🍎 Running Mac Monitor NATIVELY on macOS"
echo "========================================"
echo ""

if ! command -v go >/dev/null 2>&1; then
    echo "❌ Go is not installed"
    echo ""
    echo "Install Go from: https://go.dev/dl/"
    echo "Or use: brew install go"
    exit 1
fi

echo "⏹️  Stopping any existing instances..."
# Arrêter Docker
docker-compose down 2>/dev/null || true

# Arrêter les processus mac-monitor existants
pkill -9 mac-monitor 2>/dev/null || true

# Libérer le port 3000 si occupé
echo "🔍 Checking if port 3000 is in use..."
PORT_PID=$(lsof -ti :3000 2>/dev/null || true)
if [ ! -z "$PORT_PID" ]; then
    echo "⚠️  Port 3000 is in use by process $PORT_PID"
    echo "🔪 Killing process..."
    kill -9 $PORT_PID 2>/dev/null || true
    sleep 1
fi

echo "📦 Installing Go dependencies..."
go mod download

echo "🔨 Building..."
go build -o mac-monitor main.go

echo "🚀 Starting Mac Monitor..."
echo "📊 Dashboard: http://localhost:3000"
echo "Press Ctrl+C to stop"
echo "========================================"
echo ""

# Lancer le serveur (SANS &, pour qu'il tourne au premier plan)
./mac-monitor