#!/bin/bash
#
# Manager for Apptainer-based apps:
#   app_pdb.sh
#   app_embeddings.sh
#   app_llm.sh
#
# Usage:
#   ./manage.sh start <app>
#   ./manage.sh stop <app>
#   ./manage.sh restart <app>
#   ./manage.sh status <app>
#   ./manage.sh list
#
# Apps must write PID to logs/<name>.pid
#

BASE_DIR="/mnt/data1/vk/AI"
LOG_DIR="${BASE_DIR}/logs"
APP_DIR="$(dirname "$0")"      # directory where app scripts live

APPS=("pdb" "emb" "llm")

mkdir -p "$LOG_DIR"

# ------------------------------
# helper: check if app exists
# ------------------------------
app_exists() {
    local app="$1"
    for a in "${APPS[@]}"; do
        if [[ "$a" == "$app" ]]; then
            return 0
        fi
    done
    return 1
}

# ------------------------------
# helper: get pid file path
# ------------------------------
pidfile() {
    echo "$LOG_DIR/$1.pid"
}

# ------------------------------
# helper: get log file path
# ------------------------------
logfile() {
    echo "$LOG_DIR/$1.log"
}

# ------------------------------
# status
# ------------------------------
status_app() {
    local app="$1"
    local pf
    pf="$(pidfile "$app")"

    if [[ ! -f "$pf" ]]; then
        echo "$app: not running (no pid file)"
        return
    fi

    local pid
    pid=$(cat "$pf")

    if ps -p "$pid" > /dev/null 2>&1; then
        echo "$app: running (PID $pid)"
    else
        echo "$app: NOT running (stale pid file)"
    fi
}

# ------------------------------
# stop
# ------------------------------
stop_app() {
    local app="$1"
    local pf pid

    pf="$(pidfile "$app")"
    if [[ ! -f "$pf" ]]; then
        echo "$app: not running"
        return
    fi

    pid=$(cat "$pf")

    if ps -p "$pid" > /dev/null 2>&1; then
        echo "$app: stopping (PID $pid)..."
        kill "$pid"
        sleep 1
        if ps -p "$pid" > /dev/null; then
            echo "$app: force killing..."
            kill -9 "$pid"
        fi
    else
        echo "$app: not running but pid file existed"
    fi

    rm -f "$pf"
}

# ------------------------------
# start
# ------------------------------
start_app() {
    local app="$1"
    local script="${APP_DIR}/app_${app}.sh"
    local pf logfile

    if [[ ! -x "$script" ]]; then
        echo "Error: script $script not found or not executable"
        exit 1
    fi

    pf="$(pidfile "$app")"
    logfile="$(logfile "$app")"

    # is already running?
    if [[ -f "$pf" ]]; then
        local pid
        pid=$(cat "$pf")
        if ps -p "$pid" > /dev/null; then
            echo "$app: already running (PID $pid)"
            exit 1
        fi
    fi

    echo "Starting $app..."
    nohup "$script" > "$logfile" 2>&1 &
    echo $! > "$pf"
    echo "$app started (PID $(cat "$pf"))"
}

# ------------------------------
# restart
# ------------------------------
restart_app() {
    local app="$1"
    stop_app "$app"
    start_app "$app"
}

# ------------------------------
# list apps
# ------------------------------
list_apps() {
    echo "Available apps:"
    for a in "${APPS[@]}"; do
        echo "  - $a"
    done
}

# ------------------------------
# main
# ------------------------------
action="$1"
app="$2"

case "$action" in
    list)
        list_apps
        ;;
    status)
        if ! app_exists "$app"; then echo "Unknown app: $app"; exit 1; fi
        status_app "$app"
        ;;
    start)
        if ! app_exists "$app"; then echo "Unknown app: $app"; exit 1; fi
        start_app "$app"
        ;;
    stop)
        if ! app_exists "$app"; then echo "Unknown app: $app"; exit 1; fi
        stop_app "$app"
        ;;
    restart)
        if ! app_exists "$app"; then echo "Unknown app: $app"; exit 1; fi
        restart_app "$app"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|list} <app>"
        exit 1
        ;;
esac
