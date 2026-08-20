# NeoFL Parallel Long-Term Memory

The Brain owns long-term memory semantics. Storage is an implementation detail.

## Memory layers

- **Episodic:** trade theses, fills, exits, failures, and post-trade outcomes.
- **Strategy:** reusable observations about strategy behavior and regime fit.
- **Knowledge:** instrument/rule/MCP-derived durable facts.
- **Market:** durable regime and structural observations.
- **Execution:** broker/MT5 execution behavior and reconciliation events.

## Retrieval rule

A cognitive cycle retrieves a small relevant set using account, symbol, phase, query terms, importance and recency. The full history is never injected into the Soul.

## Trading-machine loop

`observe -> retrieve relevant memory -> reason -> decide -> execute -> reconcile -> record outcome -> reassess`.

Trade outcomes should be recorded with the original thesis and actual outcome so future decisions can compare belief against reality.

The current implementation is storage-neutral. The next persistence adapter should use the existing NeoFL database and retain append-only records with indexed account/symbol/trade identifiers.
