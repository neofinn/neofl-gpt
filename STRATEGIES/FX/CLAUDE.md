# FX — strategy room

## Status: no source exists

Clean build against the canon.

## Boundaries

FX-specific parameters and market assumptions live **here**, never in CORE. The shared engine
supplies execution, risk, capital, positions, bucket, straddle, stops, and trailing.

`Gold ≠ FX` and `FX ≠ BTC`. Session structure, spread behavior, and tick semantics differ; each
belongs to its own instrument adapter.

## Inherited rules — non-negotiable

The repository root `CLAUDE.md` applies in full. Most important here:

- **Trading logic belongs to the product owner.** Propose and ask; never silently change a rule.
- **Never fabricate.** Compile with `tools/mql5_compile.sh`; never claim a backtest or trade you
  did not run. Missing data means `DATA_UNAVAILABLE → NO TRADE`.
- **Don't duplicate infrastructure. Don't merge strategy logic.** This strategy consumes CORE;
  it never reimplements execution, risk, position, bucket, symbol, or capital code.
- **Emit decision provenance** (D-002): inputs, data quality, decision, reason, and what was
  rejected and why. Absence of a signal must itself be an observable event.
- **AI holds no order authority** (D-001).
- Ships as one self-contained folder: the `.mq5` plus every `.mqh` it needs.

## Scope of this room

Work here stays inside this strategy's signal logic and its own tests. Changes to CORE, OBSERVER,
or another strategy belong in the infrastructure room (repository root) — a change to a shared
engine can break six other strategies, and this room cannot see whether it did.
