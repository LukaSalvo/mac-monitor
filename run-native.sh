#!/usr/bin/env bash
set -euo pipefail

# run-native.sh - Run mac-monitor natively on macOS (not in Docker)
# This gives you real Mac metrics instead of Docker container metrics

echo "🍎 Running Mac Monitor NATIVELY on macOS"
echo "========================================"
echo ""

# Check if Go is installed
if ! command -v go >/dev/null 2>&1; then
    echo "❌ Go is not installed"
    echo ""
    echo "Install Go from: https://go.dev/dl/"
    echo "Or use Homebrew: brew install go"
    exit 1
fi

# Stop Docker version if running
echo "⏹️  Stopping Docker version..."
docker-compose down 2>/dev/null || true

# Install dependencies
echo "📦 Installing Go dependencies..."
go mod download

# Build
echo "🔨 Building..."
go build -o mac-monitor main.go

# Run
echo "🚀 Starting Mac Monitor..."
echo ""
echo "📊 Dashboard will be available at: http://localhost:3000"
echo "🛑 Press Ctrl+C to stop"
echo ""
echo "=========================================="
echo ""

# Run the app
./mac-monitor