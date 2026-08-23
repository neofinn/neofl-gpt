# NeoFLGPT Parallel — Working Infrastructure

This directory defines the first runnable agent-server stack. It is deliberately provider-neutral:

- **Agent gateway:** existing `python/run_gateway.py`
- **Reasoner:** OpenAI Responses API or local Ollama, selected automatically
- **State:** SQLite bridge state for zero-friction boot
- **Durable memory:** existing Supabase adapter when configured
- **Optional infrastructure:** PostgreSQL and Redis containers for the next persistence/queue layer
- **Execution:** remains fail-closed until an authenticated MT5 execution adapter is explicitly wired and enabled

## Quick start

```bash
cd INFRA
docker compose up -d postgres redis
cd ../python
python -m pip install -r requirements.txt
python run_gateway.py --host 0.0.0.0 --port 8787 --token "$NEOFL_GATEWAY_TOKEN"
```

For local model reasoning, set:

```text
NEOFL_REASONER=ollama
NEOFL_OLLAMA_URL=http://127.0.0.1:11434
NEOFL_REASONING_MODEL=qwen3:8b
```

For hosted reasoning, set `NEOFL_REASONER=openai` and `OPENAI_API_KEY`.

## Production boundary

The gateway is the control/orchestration plane. MT5 remains the execution actuator. The agent service must never infer that an order was executed merely because an intent was created; execution state must come back through the authenticated MT5 bridge and be verified against broker telemetry.

PostgreSQL/Redis are included now as infrastructure dependencies, but no fake persistence or queue semantics are claimed until the corresponding adapters are enabled in code.
