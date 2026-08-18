# Price Action — strategy room

```
Market structure -> swing detection -> BOS / CHOCH -> liquidity / zone detection
  -> entry model -> trade -> bucket management -> trailing / exit
```

## Status: no source exists

Nothing in `legacy/` implements this strategy. It is a clean build against the canon.

## Independence

Price Action is **independent of ARK**, even though both reason about market structure. Shared
candle, swing, and structure tooling belongs in CORE; **signal rules stay here.**

`Jobbing ≠ Price Action` — both use CHOCH, and that shared vocabulary is not shared logic.

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
