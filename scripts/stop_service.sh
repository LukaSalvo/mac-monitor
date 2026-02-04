#!/usr/bin/env bash
set -euo pipefail

USER="$(whoami)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[STOP] Mac Monitor — arrêt"

# 1) Si on a des PID files (mode deploy.sh avec background jobs)
if [[ -f "tmp/monitor.pid" ]]; then
  PID="$(cat tmp/monitor.pid)"
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    echo "[STOP] monitor_tickets stoppé (pid=$PID)"
  else
    echo "[STOP] monitor_tickets pid file présent mais process absent (pid=$PID)"
  fi
  rm -f tmp/monitor.pid
fi

if [[ -f "tmp/app.pid" ]]; then
  PID="$(cat tmp/app.pid)"
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    echo "[STOP] app stoppée (pid=$PID)"
  else
    echo "[STOP] app pid file présent mais process absent (pid=$PID)"
  fi
  rm -f tmp/app.pid
fi

# 2) Stop “service” si installé (Linux/systemd)
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files | grep -q "^mac-monitor\\.service"; then
      sudo systemctl stop mac-monitor || true
      sudo systemctl disable mac-monitor || true
      echo "[STOP] Service Linux mac-monitor arrêté/désactivé"
    else
      echo "[STOP] Aucun service systemd mac-monitor détecté"
    fi
  fi
fi

# 3) Stop “service” si installé (macOS/launchctl)
if [[ "$OSTYPE" == "darwin"* ]]; then
  PLIST="$HOME/Library/LaunchAgents/com.$USER.macmonitor.plist"
  if [[ -f "$PLIST" ]]; then
    launchctl unload "$PLIST" || true
    echo "[STOP] LaunchAgent macOS déchargé"
  else
    echo "[STOP] Aucun LaunchAgent trouvé ($PLIST)"
  fi
fi

# 4) Filet de sécurité: kill ce qui traîne (optionnel)
# Décommente si tu veux être agressif.
# pkill -f "bin/monitor_tickets" 2>/dev/null || true
# pkill -f "rackup" 2>/dev/null || true

echo "[STOP] Terminé"

