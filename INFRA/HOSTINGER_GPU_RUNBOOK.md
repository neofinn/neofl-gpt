# Hostinger GPU test deployment

## What you need to buy

Use a Hostinger GPU instance for the test period. Do not provision a normal VPS if GPU inference is the goal.

## What the instance runs

- NeoFLGPT Parallel gateway
- Ollama with GPU access
- qwen3:8b by default (configurable)
- PostgreSQL
- Redis
- authenticated gateway token
- optional Supabase durable memory

## Security defaults

Ollama, PostgreSQL and Redis bind to localhost. The gateway also binds to localhost by default. Put an authenticated reverse proxy in front of the gateway only when an external client needs access.

Never commit `.env`, model credentials, Supabase service-role keys, MT5 credentials, or gateway tokens.

## Bootstrap

1. Create the Hostinger GPU instance.
2. Install Docker Engine, Docker Compose v2 and the NVIDIA Container Toolkit according to the Hostinger image/OS documentation.
3. Clone `neofl-gpt` and checkout `neoflgpt-parallel`.
4. Copy `INFRA/hostinger-gpu.env.example` to `INFRA/.env` and set strong secrets.
5. Export the gateway token and run `bash INFRA/hostinger-gpu-setup.sh`.
6. Verify `docker compose ... ps` shows postgres, redis, ollama and gateway healthy/running.
7. Verify Ollama sees the GPU before accepting live workloads.

## Important

This deployment provides model inference and agent infrastructure. It does not grant the Brain automatic broker execution authority. MT5 execution remains behind the authenticated execution gateway and must be explicitly verified before live trading.
