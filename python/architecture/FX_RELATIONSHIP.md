# NeoFL FX Relationship & Synthetic Cross Brain

The FX Relationship Brain studies mathematically linked currencies and cross instruments. It does not assume that correlation equals arbitrage.

## Examples

`XAU/EUR = XAU/USD / EUR/USD` when the quotes are consistently oriented.

Currency triangles can similarly derive an implied cross from two legs sharing a currency. The engine compares the synthetic value with the actual tradable cross.

## Intelligence

The brain tracks:

- synthetic cross value
- observed cross value
- residual and residual bps
- lead/lag relationships
- historical correlation
- directional consistency
- feed quality and timestamps

It should discover whether one pair systematically leads another rather than assuming a permanent relationship.

## Cross-examination

An FX relationship signal is sent to Trader Brains, Index Brain when relevant, Option Brain when options exist, and Data Arbitrage. Those specialists independently confirm or disagree. The Soul decides how the evidence should affect a thesis.

## Arbitrage discipline

A synthetic/observed discrepancy is only a candidate. The system must investigate spread, latency, liquidity, financing, market hours, quote quality, execution and broker/account policy before treating it as actionable.

## Predictive mode

Historical lead/lag testing can produce forward-looking hypotheses such as `PAIR_A_LEADING`, but only after statistical validation across regimes. No universal correlation threshold is assumed.
