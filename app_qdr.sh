#!/bin/bash

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
mkdir -p $LDIR
APID=$LDIR/qdr.pid
ALOG=$LDIR/qdr.log

# check existing process
if [ -f $LDIR/qdrant.pid ]; then
    PID=$(cat $APID)
    if ps -p $PID > /dev/null; then
        echo "Qdrant is already running (PID $PID)"
        exit 1
    else
        echo "Qdrant is not running, removing stale pid file"
        rm -f $APID
    fi
fi

# remove previous databases
echo "create $DIR/qdrant-storage"
#rm -rf $DIR/qdrant-storage
mkdir -p $DIR/qdrant-storage
echo "create $DIR/qdrant-snapshots"
#rm -rf $DIR/qdrant-snapshots
mkdir -p $DIR/qdrant-snapshots

# Start Qdrant container
echo "starting Qdrant..."
nohup $AIDIR/qdrant/qdrant --config-path $AIDIR/qdrant/config.yaml > $ALOG 2>&1 < /dev/null &

# wait for Qdrant to initialize
echo "wait for Qdrant to start..."
sleep 5
tail $ALOG

# Save PID of Qdrant
echo $! > $APID
echo "Qdrant started with PID=`cat $APID`"

