#!/usr/bin/env bash
set -euo pipefail

# NeoFLGPT Parallel - Hostinger GPU bootstrap
# Ubuntu 24.04 / NVIDIA GPU instance

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl git jq nvtop

# Docker
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

# NVIDIA container runtime (needed for GPU containers)
if ! command -v nvidia-ctk >/dev/null 2>&1; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update
  apt-get install -y nvidia-container-toolkit
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
fi

# Verify the host GPU before deploying anything.
nvidia-smi

echo 'Hostinger GPU bootstrap complete.'
echo 'Next: copy INFRA/.env.example to INFRA/.env, set real secrets, then run docker compose.'
