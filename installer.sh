#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# Validate AI directory
# ------------------------------------------------------------
if [ -z "${AIDIR:-}" ]; then
    echo "[ERROR] AIDIR environment variable is not set."
    echo "        Please export AIDIR=/path/to/ai before running installer."
    exit 1
fi

DIR="$AIDIR"
USERNAME="${PDB_USERNAME:-tichy}"
PASSWORD="${PDB_PASSWORD:-xcvdfgoert}"

echo "[INFO] Using AIDIR = $DIR"

# ------------------------------------------------------------
# Required checksums files
# ------------------------------------------------------------
MODEL_CHECKSUMS="$PWD/checksums"
IMAGE_CHECKSUMS="$PWD/checksums"

if [ ! -f "$MODEL_CHECKSUMS" ]; then
    echo "[ERROR] Missing file: $MODEL_CHECKSUMS"
    exit 1
fi
if [ ! -f "$IMAGE_CHECKSUMS" ]; then
    echo "[ERROR] Missing file: $IMAGE_CHECKSUMS"
    exit 1
fi

# ------------------------------------------------------------
# Utility: verify checksum
# ------------------------------------------------------------
verify_checksum() {
    local file="$1"
    local checksum_file="$2"

    if [ ! -f "$file" ]; then
        echo "[ERROR] Missing file for checksum: $file"
        return 1
    fi

    echo "[CHECK] Verifying checksum for $(basename "$file") ..."
    (cd "$(dirname "$file")" && sha256sum -c "$checksum_file" --ignore-missing)
}

# ------------------------------------------------------------
# Utility: download file (curl or apptainer)
# ------------------------------------------------------------
download_if_missing() {
    local url="$1"
    local outfile="$2"
    local checksum_file="$3"
    local type="${4:-file}"  # "file" or "sif"

    if [ -f "$outfile" ]; then
        echo "[INFO] File exists: $(basename "$outfile")"
        if verify_checksum "$outfile" "$checksum_file"; then
            echo "[OK] Checksum valid. Skipping download."
            return 0
        else
            echo "[WARN] Checksum invalid — re-downloading..."
            rm -f "$outfile"
        fi
    fi

    echo "[DOWNLOAD] $(basename "$outfile")"

    if [[ "$type" == "file" ]]; then
        curl -L --progress-bar -o "$outfile" "$url"
    else
        apptainer pull "$outfile" "$url"
    fi

    echo "[VERIFY] Post-download checksum"
    verify_checksum "$outfile" "$checksum_file" || {
        echo "[ERROR] Checksum mismatch after download!"
        exit 1
    }
}

# ------------------------------------------------------------
# Create directory structure
# ------------------------------------------------------------
echo "[INFO] Preparing directory structure..."
mkdir -p "$DIR/logs"
mkdir -p "$DIR/images"
mkdir -p "$DIR/models/llama"
mkdir -p "$DIR/docs"

# ------------------------------------------------------------
# Model downloads (GGUF files)
# ------------------------------------------------------------
echo "[INFO] Processing GGUF models..."

download_if_missing \
    "https://huggingface.co/bartowski/google_gemma-3-12b-it-GGUF/resolve/main/google_gemma-3-12b-it-Q8_0.gguf" \
    "$DIR/models/llama/google_gemma-3-12b-it-Q8_0.gguf" \
    "$MODEL_CHECKSUMS" "file"

download_if_missing \
    "https://huggingface.co/bartowski/google_gemma-3-12b-it-GGUF/resolve/main/google_gemma-3-12b-it-IQ4_XS.gguf" \
    "$DIR/models/llama/google_gemma-3-12b-it-IQ4_XS.gguf" \
    "$MODEL_CHECKSUMS" "file"

download_if_missing \
    "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q8_0.gguf" \
    "$DIR/models/llama/nomic-embed-text-v1.5.Q8_0.gguf" \
    "$MODEL_CHECKSUMS" "file"

# ------------------------------------------------------------
# Apptainer images (.sif)
# ------------------------------------------------------------
echo "[INFO] Processing Apptainer images..."

download_if_missing \
    "docker://ghcr.io/ggerganov/llama.cpp:server-cuda" \
    "$DIR/images/llama_server_cuda.sif" \
    "$IMAGE_CHECKSUMS" "sif"

download_if_missing \
    "docker://ghcr.io/ggerganov/llama.cpp:server" \
    "$DIR/images/llama_server.sif" \
    "$IMAGE_CHECKSUMS" "sif"

download_if_missing \
    "docker://pgvector/pgvector:pg17" \
    "$DIR/images/pgvector_pg17.sif" \
    "$IMAGE_CHECKSUMS" "sif"

# ------------------------------------------------------------
# Clone and build tichy
# ------------------------------------------------------------
echo "[INFO] Installing Tichy tools..."

if [ ! -d "$DIR/tichy" ]; then
    git clone git@github.com:lechgu/tichy.git "$DIR/tichy"
else
    echo "[INFO] Tichy directory exists. Updating..."
    (cd "$DIR/tichy" && git pull)
fi

(cd "$DIR/tichy" && make)

# ------------------------------------------------------------
# Generate .env file
# ------------------------------------------------------------
echo "[INFO] Creating .env config..."

cat > "$DIR/.env" << EOF
PORT=7070
LOG_LEVEL=debug
DATABASE_URL=postgres://${USERNAME}:${PASSWORD}@localhost:5432/tichy?sslmode=disable
LLM_SERVER_URL=http://localhost:8180
EMBEDDING_SERVER_URL=http://localhost:8181
SYSTEM_PROMPT_TEMPLATE=$DIR/system_prompt_template.txt
CHUNK_SIZE=500
CHUNK_OVERLAP=100
TOP_K=10
EOF

# ------------------------------------------------------------
# PDB credentials
# ------------------------------------------------------------
echo "USERNAME:$USERNAME" > "$DIR/pdb_credentials"
echo "PASSWORD:$PASSWORD" >> "$DIR/pdb_credentials"

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
echo "================================================="
echo " Installation complete!"
echo "================================================="
echo "AI llama models     : $(ls $DIR/models/llama)"
echo "Apptainer images    : $(ls $DIR/images)"
echo "Tichy tool          : $(ls $DIR/tichy/tichy)"
echo ".env                : $DIR/.env"
echo "PDB credentials     : $DIR/pdb_credentials"
echo "AI prompt definition: $DIR/system_prompt_template.txt"
echo "Management script   : $DIR/app_manage.sh"
echo "Start AI services   : $DIR/app_manage.sh start"
echo "Follow up actions   : place your *.md or *.txt files into $DIR/docs and ingest them"
echo "  $DIR/tichy/tichy ingest --source $DIR/docs --mode text"
echo "================================================="
echo
echo "[OK] Everything is installed successfully."
