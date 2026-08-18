# Gold — strategy room

Standalone gold strategy. One of seven, not the whole platform — that was the superseded v1.0
architecture.

## Symbol resolution: already built, in CORE

`CORE/NeoFL_SymbolResolver` handles this and is done. Use it; do not reimplement matching here.

```
XAUUSD · XAUUSDm · XAUUSD.a · XAUUSD.pro · PREFIX_XAUUSD_SUFFIX · GOLD  -> GOLD
BTCXAU                                                                 -> REJECTED
```

Matching is semantic: XAU counts as gold only when it is the **base**, i.e. immediately followed
by a quote currency. In `BTCXAU`, XAU is the quote of a crypto cross. A naive `StringFind("XAU")`
would wrongly accept it.

Run `NeoFL_SymbolResolver_SelfTest` in MT5 to confirm what this broker actually calls gold.

## Status: no source exists for the strategy itself

The GOLD 5.x/6.x legacy line is **not** this strategy — it is a monolithic Trend+ARK dual engine
built for an architecture that no longer exists (there is no Trend Engine in v2). Reference only.

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
