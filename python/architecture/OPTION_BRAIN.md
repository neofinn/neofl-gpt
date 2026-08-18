# NeoFL Option Brain

The Option Brain is a first-class specialist brain operating in parallel with Index Intelligence and Trader Brains.

## Two-way loop

1. Index/Trader brains may originate an underlying or index thesis.
2. Option Brain studies the complete tradable option surface for that underlying.
3. It evaluates Greeks, IV, skew, term structure, liquidity, expected move, expiry, strike and positioning.
4. It independently confirms or challenges the thesis.
5. It determines whether direct underlying exposure or an option expression is superior for the thesis, horizon and risk budget.
6. If Option Brain originates a signal from option-market evidence, Trader and Index brains independently analyze the underlying/index as a tradable asset and may confirm or disagree.
7. The Soul receives the complete cross-examination rather than using simple majority voting.

## Instrument selection

NeoFL separates:

`direction -> underlying asset -> instrument`

Possible instruments include direct shares/indexes/futures and appropriate option structures. The Option Brain must be able to conclude `DIRECT_ASSET_SUPERIOR`, `OPTION_SUPERIOR`, `OPTION_SPREAD_SUPERIOR`, or `NO_TRADE`.

A correct directional thesis does not imply that an option is the best instrument. Premium, IV, theta, liquidity, spread, expected move, expiry and risk must be evaluated.

## Greek intelligence

The Option Brain consumes Delta, Gamma, Theta, Vega and Rho alongside IV and option-chain state. Greeks are explanatory inputs, not standalone trade signals.

## Data requirements

The Data Fabric should eventually provide complete option chains with bid/ask, last, volume, open interest, IV, Greeks, underlying price, expiry, strike, option type, expected move and timestamps/quality. Historical chains are required for robust calibration.

## Production boundary

Option Brain is analytical. It does not directly execute. Its instrument recommendation passes through the Soul, Risk Brain, account/firm policy and platform-agnostic Execution Fabric.
