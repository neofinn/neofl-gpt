# Jobbing — strategy room

US-open opening-range breakout. A separate EA from ARK, deliberately, so the two can be
backtested independently.

```
US market open -> FIRST M15 candle -> high/low = opening range
  -> M5 execution structure -> breakout -> CHOCH confirmation -> direction -> entry
```

## Current rules

- **The opening range is the first M15 candle.** The earlier three-M15-candle concept is
  **obsolete** — do not reintroduce it.
- Breakout of that range sets initial directional context.
- **CHOCH validates the direction.**
- Timing comes from a dedicated US-session module, not arbitrary broker/server time.

## Ancestor — misleadingly named

`legacy/ark-jobbing-backtest-v3.00/ARK/NeoFL_ARK_Backtest_v3_00.mq5` is named ARK but **is this
strategy's direct ancestor.** Verified: US 09:30–16:00 ET with DST, first M15 candle as the range,
first M5 close outside it sets direction, M5 EMA(20/50) + RSI(14) confirmation.

Two gaps against the current spec:

1. **CHOCH is not implemented.** `RequireM5CHoCH` is declared and never referenced anywhere else
   in the file — a dead input. CHOCH must be **built**, not ported.
2. Direction currently comes from breakout + EMA/RSI, with CHOCH absent from the decision path.

Also note `NeoFL_Jobbing_Backtest_v3_00.mq5` in the same folder is **not** this strategy — it is
tick-driven micro-scalping with a 60-second max hold. Both filenames are unreliable; read the code.

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
