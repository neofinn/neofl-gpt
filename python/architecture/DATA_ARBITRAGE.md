# NeoFL Data Arbitrage Brain

NeoFL compares authoritative/reference market feeds with the connected broker's live feed to detect timing and quote discrepancies. The purpose is to determine whether an apparent edge is genuine, executable, persistent and policy-permitted.

## Core loop

`reference feed -> timestamp normalization -> broker feed -> latency comparison -> bid/ask discrepancy -> executable-cost test -> historical validation -> demo validation -> Soul/Risk`

The brain must compare executable prices, not only last prices. It records reference/broker timestamps, bid/ask, sequence metadata, quote quality, latency, price residuals, edge duration and estimated costs.

## Interpretation

A quote discrepancy is not automatically an arbitrage opportunity. The system must investigate timestamp mismatch, stale data, spread, slippage, network latency, order-routing latency, execution latency, rejection and fill quality.

An edge becomes a candidate only when the observed timing advantage produces a positive executable edge after estimated costs. Historical and demo validation are required before any production consideration.

## Policy boundary

Some brokers, venues or account agreements may prohibit latency-sensitive or stale-quote strategies. Account/Firm Policy is authoritative. A mathematically positive edge can therefore be `POLICY_BLOCKED`.

## Integration

Data Arbitrage is a specialist brain. It can challenge or inform Trader, Index and Option brains. It can also supply lead/lag observations to the Experiment Brain. It never directly places an order.
