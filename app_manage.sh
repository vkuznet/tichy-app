#!/bin/bash
#
# Unified manager for: app_pdb.sh, app_embeddings.sh, app_llm.sh
# Controls start/stop/restart/status in correct dependency order.
#

# ------------------------------------------------------------
# Validate AI directory
# ------------------------------------------------------------
if [ -z "${AIDIR:-}" ]; then
    echo "[ERROR] AIDIR environment variable is not set."
    echo "        Please export AIDIR=/path/to/ai before running services"
    exit 1
fi
DIR=$ADIR
LDIR=$DIR/logs

SCRIPTS=(
    "app_pdb.sh:pdb.pid:Postgres"
    "app_emb.sh:emb.pid:Embeddings"
    "app_llm.sh:llm.pid:LLM"
    "app_srv.sh:srv.pid:TichyServer"
)

mkdir -p "$LDIR"

get_pid() {
    local pidfile="$1"
    if [[ -f "$pidfile" ]]; then
        cat "$pidfile"
    else
        echo ""
    fi
}

is_running() {
    local pid="$1"
    if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

start_service() {
    local script="$1"
    local pidfile="$2"
    local name="$3"

    local pid=$(get_pid "$pidfile")
    if is_running "$pid"; then
        echo "[OK] $name already running (PID $pid)"
        return
    fi

    echo "Starting $name..."
    bash "$script"

    sleep 2

    pid=$(get_pid "$pidfile")
    if is_running "$pid"; then
        echo "[OK] $name started (PID $pid)"
    else
        echo "[ERROR] $name failed to start"
    fi
}

stop_service() {
    local pidfile="$1"
    local name="$2"

    local pid=$(get_pid "$pidfile")
    if ! is_running "$pid"; then
        echo "[OK] $name is not running"
        return
    fi

    echo "Stopping $name (PID $pid)..."
    kill "$pid"

    # Wait up to 10 seconds
    for i in {1..10}; do
        if ! is_running "$pid"; then
            echo "[OK] $name stopped"
            rm -f "$pidfile"
            return
        fi
        sleep 1
    done

    echo "[WARN] $name did not stop gracefully, killing..."
    kill -9 "$pid"
    rm -f "$pidfile"
    echo "[OK] $name force stopped"
}

status_all() {
    echo "=== STATUS ==="
    for item in "${SCRIPTS[@]}"; do
        IFS=":" read script pidfile name <<< "$item"
        pid=$(get_pid "$LDIR/$pidfile")
        if is_running "$pid"; then
            echo "[RUNNING] $name (PID $pid)"
        else
            echo "[STOPPED] $name"
        fi
    done
}

start_all() {
    echo "=== STARTING ALL SERVICES ==="
    for item in "${SCRIPTS[@]}"; do
        IFS=":" read script pidfile name <<< "$item"
        start_service "$script" "$LDIR/$pidfile" "$name"
    done
}

stop_all() {
    echo "=== STOPPING ALL SERVICES ==="
    # stop in reverse order
    for (( i=${#SCRIPTS[@]}-1; i>=0; i-- )); do
        IFS=":" read script pidfile name <<< "${SCRIPTS[$i]}"
        stop_service "$LDIR/$pidfile" "$name"
    done
}

restart_all() {
    stop_all
    sleep 2
    start_all
}

# -------------------
# MAIN LOGIC
# -------------------
case "$1" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        restart_all
        ;;
    status)
        status_all
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

