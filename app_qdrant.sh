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

# check existing process
if [ -f $LDIR/qdrant.pid ]; then
    PID=$(cat $LDIR/qdrant.pid)
    if ps -p $PID > /dev/null; then
        echo "Qdrant is already running (PID $PID)"
        exit 1
    else
        echo "Qdrant is not running, removing stale pid file"
        rm -f $LDIR/qdrant.pid
    fi
fi

# Pull Docker image into Apptainer SIF format (only once)
IMAGE="qdrant/qdrant"
SIF_IMAGE="$DIR/images/qdrant.sif"
if [ ! -f "$SIF_IMAGE" ]; then
    apptainer pull "$SIF_IMAGE" "docker://$IMAGE"
fi

# remove previous databases
echo "remove and recreate $DIR/qdrant-storage"
rm -rf $DIR/qdrant-storage
mkdir -p $DIR/qdrant-storage
echo "remove and recreate $DIR/qdrant-snapshots"
rm -rf $DIR/qdrant-snapshots
mkdir -p $DIR/qdrant-snapshots

# Start Qdrant container
echo "starting Qdrant apptainer..."
apptainer exec \
  --bind $DIR/qdrant-storage:/qdrant/storage \
  --bind $DIR/qdrant-snaphots:/qdrant/snaphots \
  $DIR/images/qdrant.sif \
  /qdrant/qdrant \
  --disable-telemetry \
  > $LDIR/qdrant.log 2>&1 &

# wait for Qdrant to initialize
echo "wait for Qdrant to start..."
sleep 5
tail $LDIR/qdrant.log

# Optionally start tichy db migration/setup
echo "$DIR/tichy/tichy db up"
cd $DIR
$DIR/tichy/tichy db up
cd -

# Save PID of Qdrant
echo $! > $LDIR/qdrant.pid
echo "Qdrant started with PID=`cat $LDIR/qdrant.pid`"

