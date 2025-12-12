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
DIR=$AIDIR
LDIR=$DIR/logs
MDIR=$AIDIR/tichy-app
if [ ! -d "$MDIR" ]; then
  echo "Directory $MDIR does not exist, please clone it as following"
  echo "cd $DIR"
  echo "git clone git@github.com:vkuznet/tichy-app.git"
  exit 1
fi

# use local .env file
AENV=$PWD/.env

# overwrite local .env if AIENV is set
if [ -n "$AIENV" ]; then
  AENV=$AIENV
fi
if [ -z "${AENV}" ] && [ ! -f ${AENV} ]; then
    echo "[ERROR] AIENV environment variable is not set and neither $PWD/.env file found"
    echo "        Please export AIENV=/path/.env before running services"
    exit 1
fi
echo "Using AIENV=$AENV environment file"
export TICHY_ENV=$AENV
if [ -z "$SYSTEM_PROMPT_TEMPLATE" ]; then
  export SYSTEM_PROMPT_TEMPLATE=$MDIR/system_prompt_template.txt
fi

SCRIPTS=(
    "app_emb.sh:emb.pid:Embeddings"
    "app_llm.sh:llm.pid:LLM"
    "app_pdb.sh:pdb.pid:Postgres"
    "app_qdr.sh:qdr.pid:Qdrant"
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

    echo "Starting $name via $MDIR/$script"
    bash "$MDIR/$script"

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

check_vdb() {
    # Check for AENV file
    if [[ ! -f "$AENV" ]]; then
        echo "ERROR: $AENV file not found. Cannot determine VECTORDB_BACKEND."
        exit 1
    fi

    # Get VECTORDB_BACKEND value (strip spaces and CRLF)
    VECTORDB_BACKEND=$(grep -E '^VECTORDB_BACKEND=' $AENV | cut -d '=' -f2 | tr -d ' \r')

    # check if VECTORDB_BACKEND is properly set
    if [[ -z "$VECTORDB_BACKEND" ]]; then
        echo "ERROR: VECTORDB_BACKEND is not set in $AENV (expected: qdrant or pgvector)."
        exit 1
    fi

    if [[ "$VECTORDB_BACKEND" != "qdrant" && "$VECTORDB_BACKEND" != "pgvector" ]]; then
        echo "ERROR: Invalid VECTORDB_BACKEND: $VECTORDB_BACKEND (expected: qdrant or pgvector)."
        exit 1
    fi

    echo "Using VECTORDB_BACKEND=$VECTORDB_BACKEND"
}

status_all() {
    echo "=== STATUS ==="
    check_vdb
    for item in "${SCRIPTS[@]}"; do
        IFS=":" read script pidfile name <<< "$item"
        # Database backend switch
        if [[ "$script" == "app_qdr.sh" && "$VECTORDB_BACKEND" != "qdrant" ]]; then
            echo "Skipping $name (not selected backend)"
            continue
        fi
        if [[ "$script" == "app_pdb.sh" && "$VECTORDB_BACKEND" != "pgvector" ]]; then
            echo "Skipping $name (not selected backend)"
            continue
        fi
        pid=$(get_pid "$LDIR/$pidfile")
        if is_running "$pid"; then
            echo "[RUNNING] $name (PID $pid)"
        else
            echo "[STOPPED] $name"
        fi
    done
}

start_all() {
    echo "=== Check VECTORDB_BACKEND ==="
    check_vdb
    VECTORDB_BACKEND=$(grep -E '^VECTORDB_BACKEND=' $AENV | cut -d '=' -f2 | tr -d ' \r')
    echo "=== STARTING ALL SERVICES ==="
    for item in "${SCRIPTS[@]}"; do
        IFS=":" read script pidfile name <<< "$item"
        # Database backend switch
        if [[ "$script" == "app_qdr.sh" && "$VECTORDB_BACKEND" != "qdrant" ]]; then
            echo "Skipping $name (not selected backend)"
            continue
        fi
        if [[ "$script" == "app_pdb.sh" && "$VECTORDB_BACKEND" != "pgvector" ]]; then
            echo "Skipping $name (not selected backend)"
            continue
        fi

        # start other services
        start_service "$script" "$LDIR/$pidfile" "$name"
    done
}

stop_all() {
    echo "=== Check VECTORDB_BACKEND ==="
    check_vdb
    VECTORDB_BACKEND=$(grep -E '^VECTORDB_BACKEND=' $AENV | cut -d '=' -f2 | tr -d ' \r')
    echo "=== STOPPING ALL SERVICES ==="
    # stop in reverse order
    for (( i=${#SCRIPTS[@]}-1; i>=0; i-- )); do
        IFS=":" read script pidfile name <<< "${SCRIPTS[$i]}"
        # Database backend switch
        if [[ "$script" == "app_qdr.sh" && "$VECTORDB_BACKEND" != "qdrant" ]]; then
            echo "Skipping $name (not selected backend)"
            continue
        fi
        if [[ "$script" == "app_pdb.sh" && "$VECTORDB_BACKEND" != "pgvector" ]]; then
            echo "Skipping $name (not selected backend)"
            continue
        fi

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

