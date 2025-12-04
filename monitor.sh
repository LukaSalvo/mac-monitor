#!/usr/bin/env bash
set -euo pipefail

# Configuration
APP_NAME="mac-monitor"
PID_FILE="/tmp/${APP_NAME}.pid"
LOG_FILE="/tmp/${APP_NAME}.log"
PORT=3000

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
log_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

log_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

log_error() {
    echo -e "${RED}✗${NC}  $1"
}

# Vérifier si Go est installé
check_go() {
    if ! command -v go >/dev/null 2>&1; then
        log_error "Go is not installed"
        echo ""
        echo "Install Go from: https://go.dev/dl/"
        echo "Or use: brew install go"
        exit 1
    fi
}

# Vérifier si le processus tourne
is_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0
        else
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Obtenir le PID
get_pid() {
    if [ -f "$PID_FILE" ]; then
        cat "$PID_FILE"
    else
        echo "N/A"
    fi
}

# BUILD
build() {
    log_info "Building ${APP_NAME}..."
    check_go
    
    go mod download > /dev/null 2>&1
    
    if go build -o "${APP_NAME}" main.go 2>&1 | grep -v "warning:"; then
        log_success "Build successful"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

# START
start() {
    echo ""
    echo "🍎 Mac Monitor - Starting"
    echo "=========================================="
    
    if is_running; then
        log_warning "${APP_NAME} is already running (PID: $(get_pid))"
        echo "Use './monitor.sh stop' first, or './monitor.sh restart'"
        exit 1
    fi
    
    # Arrêter Docker si présent
    log_info "Stopping Docker version..."
    docker-compose down 2>/dev/null || true
    
    # Nettoyer les anciens processus orphelins
    pkill -9 "${APP_NAME}" 2>/dev/null || true
    sleep 1
    
    # Vérifier si le port est libre
    if lsof -i ":${PORT}" > /dev/null 2>&1; then
        log_warning "Port ${PORT} is in use, attempting to free it..."
        lsof -ti ":${PORT}" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
    
    # Build
    if ! build; then
        exit 1
    fi
    
    # Démarrer le serveur en arrière-plan
    log_info "Starting ${APP_NAME}..."
    nohup ./"${APP_NAME}" > "${LOG_FILE}" 2>&1 &
    echo $! > "${PID_FILE}"
    
    # Attendre que le serveur démarre
    sleep 2
    
    if is_running; then
        log_success "${APP_NAME} started successfully"
        echo ""
        echo "📊 Dashboard: http://localhost:${PORT}"
        echo "📝 Logs:      tail -f ${LOG_FILE}"
        echo "🔢 PID:       $(get_pid)"
        echo "=========================================="
    else
        log_error "Failed to start ${APP_NAME}"
        log_info "Check logs: cat ${LOG_FILE}"
        rm -f "${PID_FILE}"
        exit 1
    fi
}

# STOP
stop() {
    echo ""
    echo "⏹️  Mac Monitor - Stopping"
    echo "=========================================="
    
    if ! is_running; then
        log_warning "${APP_NAME} is not running"
        exit 1
    fi
    
    PID=$(get_pid)
    log_info "Stopping ${APP_NAME} (PID: ${PID})..."
    
    # Essayer d'abord un arrêt gracieux
    kill "$PID" 2>/dev/null || true
    sleep 2
    
    # Si toujours actif, forcer l'arrêt
    if ps -p "$PID" > /dev/null 2>&1; then
        log_warning "Forcing shutdown..."
        kill -9 "$PID" 2>/dev/null || true
        sleep 1
    fi
    
    # Nettoyer le fichier PID
    rm -f "${PID_FILE}"
    
    # Vérifier que c'est bien arrêté
    if ! is_running; then
        log_success "${APP_NAME} stopped successfully"
    else
        log_error "Failed to stop ${APP_NAME}"
        exit 1
    fi
    
    echo "=========================================="
}

# STATUS
status() {
    echo ""
    echo "📊 Mac Monitor - Status"
    echo "=========================================="
    
    if is_running; then
        PID=$(get_pid)
        log_success "${APP_NAME} is running"
        echo ""
        echo "  PID:        ${PID}"
        echo "  Port:       ${PORT}"
        echo "  Dashboard:  http://localhost:${PORT}"
        echo "  Log file:   ${LOG_FILE}"
        echo ""
        
        # Afficher l'utilisation mémoire
        if command -v ps >/dev/null 2>&1; then
            MEM=$(ps -o rss= -p "$PID" 2>/dev/null | awk '{print $1/1024 " MB"}' || echo "N/A")
            echo "  Memory:     ${MEM}"
        fi
        
        # Afficher depuis combien de temps il tourne
        if command -v ps >/dev/null 2>&1; then
            ELAPSED=$(ps -o etime= -p "$PID" 2>/dev/null | xargs || echo "N/A")
            echo "  Uptime:     ${ELAPSED}"
        fi
        
        # Vérifier si le port est accessible
        if curl -s "http://localhost:${PORT}/api/system" > /dev/null 2>&1; then
            log_success "API is responding"
        else
            log_warning "API is not responding"
        fi
    else
        log_error "${APP_NAME} is not running"
        
        # Vérifier si un build existe
        if [ -f "./${APP_NAME}" ]; then
            echo ""
            echo "  Binary:     exists"
        else
            echo ""
            echo "  Binary:     not found (run './monitor.sh start' to build)"
        fi
    fi
    
    echo "=========================================="
}

# RESTART
restart() {
    echo ""
    echo "🔄 Mac Monitor - Restarting"
    echo "=========================================="
    
    if is_running; then
        stop
        echo ""
    fi
    
    start
}

# LOGS
logs() {
    if [ ! -f "${LOG_FILE}" ]; then
        log_error "Log file not found: ${LOG_FILE}"
        exit 1
    fi
    
    echo ""
    echo "📝 Mac Monitor - Logs"
    echo "=========================================="
    echo "Press Ctrl+C to stop following logs"
    echo ""
    
    tail -f "${LOG_FILE}"
}

# CLEAN
clean() {
    echo ""
    echo "🧹 Mac Monitor - Cleaning"
    echo "=========================================="
    
    if is_running; then
        log_error "${APP_NAME} is still running. Stop it first."
        exit 1
    fi
    
    log_info "Removing build artifacts..."
    rm -f "./${APP_NAME}"
    rm -f "${PID_FILE}"
    rm -f "${LOG_FILE}"
    
    log_success "Cleanup complete"
    echo "=========================================="
}

# USAGE
usage() {
    cat << EOF

🍎 Mac Monitor Control Script
========================================

Usage: ./monitor.sh [command]

Commands:
  start      Start the monitor
  stop       Stop the monitor
  restart    Restart the monitor
  status     Check monitor status
  logs       View and follow logs
  build      Build the binary
  clean      Remove all generated files
  help       Show this help message

Examples:
  ./monitor.sh start
  ./monitor.sh status
  ./monitor.sh logs
  ./monitor.sh restart

========================================
EOF
}

# MAIN
case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    build)
        build
        ;;
    clean)
        clean
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: ${1:-}"
        usage
        exit 1
        ;;
esac