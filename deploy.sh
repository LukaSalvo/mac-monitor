#!/bin/bash

OS="$(uname -s)"
echo "--- Deployment ($OS) ---"

rm -f app.log server.log

bundle config set --local path 'vendor/bundle'
bundle config set --local disable_shared_gems true

bundle install

# --- CONFIGURATION ---
START_PORT=3000


MAX_PORT=3010
FREE_PORT=""

is_port_used() {
    local port=$1
    if [ "$OS" = "Darwin" ]; then
        lsof -i :$port -t >/dev/null 2>&1
    else
        ss -tuln | grep -q ":$port "
    fi
}

if is_port_used 3000; then
    echo "Port 3000 used. Stopping..."
    if [ "$OS" = "Darwin" ]; then
         PID=$(lsof -i :3000 -t)
    else
         PID=$(fuser 3000/tcp 2>/dev/null)
    fi
    
    if [ -n "$PID" ]; then
        kill -9 $PID 2>/dev/null
        sleep 1
    fi
fi

for (( PORT = $START_PORT; PORT <= $MAX_PORT; PORT++ )); do
    if ! is_port_used $PORT; then
        FREE_PORT=$PORT
        break
    fi
done

if [ -z "$FREE_PORT" ]; then
    echo "ERROR: No free port."
    exit 1
fi

echo "Starting server on port $FREE_PORT..."
echo "Local: http://localhost:$FREE_PORT"
echo "Network: http://$(hostname):$FREE_PORT"

bundle exec rackup -p $FREE_PORT --host 0.0.0.0