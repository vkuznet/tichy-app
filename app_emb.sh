#!/bin/bash

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
mkdir -p $LDIR

# check existing process
if [ -f $LDIR/emb.pid ]; then
    PID=$(cat $LDIR/emb.pid)
    if ps -p $PID > /dev/null; then
        echo "LLM embeddings is running (PID $PID)"
        exit 1
    else
        echo "LLM embeddings is not running"
    fi
fi

# setup configuration parameters
IMAGE="ghcr.io/ggerganov/llama.cpp:server-cuda"
SIF_IMAGE="$DIR/images/llama_server_cuda.sif"
CONTAINER_NAME="tichy-embeddings"
HOST_PORT=8181
CONTAINER_PORT=8181
MODEL_VOLUME_HOST="$DIR/models/llama"
MODEL_VOLUME_CONTAINER="/mnt/models:ro"
MODEL="/mnt/models/nomic-embed-text-v1.5.Q8_0.gguf"
CTX_SIZE=2048

# Pull the Docker image into Apptainer SIF format (once)
if [ ! -f "$SIF_IMAGE" ]; then
    apptainer pull "$SIF_IMAGE" "docker://$IMAGE"
fi

# Run container with GPU support
echo "Start Embeddings apptainer..."
apptainer exec --nv \
  --bind "$MODEL_VOLUME_HOST:$MODEL_VOLUME_CONTAINER" \
  --env NVIDIA_VISIBLE_DEVICES=all \
  --env NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  --env LD_LIBRARY_PATH=/app:$LD_LIBRARY_PATH \
  "$SIF_IMAGE" \
  /app/llama-server \
  --model "$MODEL" \
  --host "0.0.0.0" \
  --port "$CONTAINER_PORT" \
  --ctx-size "$CTX_SIZE" \
  --embedding \
  > $LDIR/emb.log 2>&1 &

# Save the PID of the last backgrounded process
echo $! > $LDIR/emb.pid
echo "LLM embeddings is running with PID=`cat $LDIR/emb.pid`"
