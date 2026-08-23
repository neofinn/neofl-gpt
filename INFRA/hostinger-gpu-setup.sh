#!/usr/bin/env bash
set -euo pipefail

# Hostinger GPU instance bootstrap for NeoFLGPT Parallel.
# Run from the repository root after Docker Engine + Compose are available.

: "${NEOFL_GATEWAY_TOKEN:?Export NEOFL_GATEWAY_TOKEN before running}"
export NEOFL_GATEWAY_TOKEN
export NEOFL_REASONER="${NEOFL_REASONER:-ollama}"
export NEOFL_REASONING_MODEL="${NEOFL_REASONING_MODEL:-qwen3:8b}"

command -v docker >/dev/null || { echo 'Docker is required.'; exit 1; }
docker compose version >/dev/null || { echo 'Docker Compose v2 is required.'; exit 1; }

if ! docker info >/dev/null 2>&1; then
  echo 'Docker daemon is not available.'
  exit 1
fi

if ! docker info 2>/dev/null | grep -qi 'nvidia'; then
  echo 'WARNING: NVIDIA container runtime was not detected. The stack can still boot, but Ollama will not use the GPU.'
fi

echo 'Starting PostgreSQL, Redis, Ollama and NeoFL gateway...'
docker compose -f INFRA/docker-compose.yml -f INFRA/docker-compose.gpu.yml up -d --build

echo 'Pulling the configured local model...'
docker compose -f INFRA/docker-compose.yml -f INFRA/docker-compose.gpu.yml --profile init run --rm model-init

echo 'Restarting gateway after model installation...'
docker compose -f INFRA/docker-compose.yml -f INFRA/docker-compose.gpu.yml up -d gateway

echo 'NeoFLGPT Parallel GPU stack is up.'
echo 'Check: docker compose -f INFRA/docker-compose.yml -f INFRA/docker-compose.gpu.yml ps'
echo 'Logs:  docker compose -f INFRA/docker-compose.yml -f INFRA/docker-compose.gpu.yml logs -f gateway'
