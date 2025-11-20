# Deployment on VM

This document outlines all steps required to deploy the
[**tichy**](https://github.com/lechgu/tichy) service to a
stand-alone virtual machine.

---

## 1. Prepare Docker / Podman / Apptainer Images

Before pulling images from GitHub Container Registry (GHCR), you need a GitHub **Personal Access Token (PAT)**.

### Obtain a GitHub PAT

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**
2. Click **Generate new token**
3. Give it a name (e.g., *docker-ghcr-pull*)
4. Enable the **read:packages** permission
5. Generate and copy the token

### Authenticate

```bash
# Docker authentication with ghcr.io
docker login ghcr.io
# Enter username and PAT when prompted

# Podman authentication with ghcr.io
podman login ghcr.io -u USERNAME -p "$(cat github_token)"
```

You can now pull GHCR images.

---

## 2. Automated Installation (Recommended)

Run the installer:

```bash
bash installer.sh
```

This script downloads models, checks checksums, builds Apptainer images, compiles `tichy`, and generates the `.env` file.

---

## 3. Manual Installation (Alternative)

If not using `installer.sh`, follow these steps:

### Convert Docker images to Apptainer

```bash
apptainer pull pgvector_pg17.sif docker://pgvector/pgvector:pg17
apptainer pull llama_server.sif "docker://ghcr.io/ggerganov/llama.cpp:server"
apptainer pull llama_server_cuda.sif "docker://ghcr.io/ggerganov/llama.cpp:server-cuda"
```

---

### Start Services Using Shell Scripts

The repository provides helper scripts for starting services with either Apptainer or Docker/Podman:

### Apptainer-based scripts

* `app_pdb.sh` – start PostgreSQL
* `app_embeddings.sh` – start embeddings service
* `app_llm.sh` – start LLM service

---

### Start Tichy Services

Initialize the database:

```bash
./tichy db up
```

Ingest documents:

```bash
./tichy ingest --source ./examples/insurellm/knowledge-base/ --mode text
```

Start an interactive chat session:

```bash
./tichy chat
```

Or start the HTTP API server (port and configuration defined in `.env`):

```bash
./tichy serve
```
