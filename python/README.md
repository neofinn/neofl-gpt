# NeoFL Python Brain

This directory contains the Python side of NeoFL. The Python brain is an orchestration,
state, analytics, persistence, and integration layer. It is intentionally separated from
broker execution.

## Brain boundary

```text
Market/Data adapters
        ↓
   NeoFL Python Brain
        ↓
 strategy → risk → order intent
        ↓
 execution adapter (MT5, paper, backtest)
```

The engine never sends a broker request directly. It emits `OrderIntent` objects and calls
an injected `ExecutionPort` only after the injected `RiskPort` approves the intent.

## Current foundation

- `neofl_engine/models.py` — immutable engine/event/intention contracts
- `neofl_engine/ports.py` — adapter interfaces
- `neofl_engine/engine.py` — lifecycle and decision-cycle orchestrator
- existing `neofl_core/` — executable reference calculations for risk/bucket logic
- existing `neofl_gateway/` — read-only observer API primitives

## Next integrations

1. Supabase event/state persistence
2. MT5 market/account/execution adapter
3. recovery/straddle state machine
4. strategy registry and per-strategy signal adapters
5. backtest adapter using the same engine contracts
6. telemetry and external-brain read APIs

Trading parameters remain product-owner controlled. The Python layer must fail closed on
missing/invalid data and must never fabricate a market value.
