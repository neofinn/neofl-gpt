# OrderIntent Lifecycle

```text
Agentic Brain
  -> OrderIntent
  -> Body queue
  -> MT5 Executioner claims intent
  -> broker execution
  -> confirmed ExecutionFill
  -> Body position lifecycle
  -> Risk
  -> Straddle
  -> Bucket/recovery
  -> ExecutionReport / P&L
  -> Brain reassessment
```

An `OrderIntent` is not a broker order. It is a structured request produced by the Brain and queued for the MT5 execution adapter. The queue state is `QUEUED -> CLAIMED -> FILLED/REJECTED/CANCELLED`.

Risk, Straddle and Bucket management do not activate when an intent is merely queued. They activate from the confirmed fill and therefore operate on the position that actually exists at the broker.

The parallel build exposes the queue as an internal Body surface for the MT5 bridge. The execution adapter remains the only broker authority.
