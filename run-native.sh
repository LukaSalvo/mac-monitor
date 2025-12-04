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

echo "⏹️  Stopping Docker version..."
docker-compose down 2>/dev/null || true

echo "📦 Installing Go dependencies..."
go mod download

echo "🔨 Building..."
go build -o mac-monitor main.go

echo "🚀 Starting Mac Monitor in background..."
./mac-monitor &

echo ""
echo "✔ mac-monitor is running in background (PID: $!)"
echo "📊 Dashboard: http://localhost:3000"
echo "========================================"