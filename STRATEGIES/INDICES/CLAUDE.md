# Indices — strategy room

Primary universe: **US500 / SPX**, **US100 / NSX**, **US30**.

## Status: no source exists

Clean build against the canon.

## The hard architectural constraint

> MT5 CFD data may not provide all information required by the strategy.

External data is therefore an architectural component, not an afterthought:

```
Underlying / external data + MT5 CFD -> Index Data Adapter
  -> data validation -> Index Engine -> Indices EA
```

The strategy must **know which source and quality** it is operating on, and must never pretend
missing underlying data is valid.

```
DATA_OK · DATA_DELAYED · DATA_INCOMPLETE · DATA_UNAVAILABLE · DATA_INVALID
```

## Relationship to ARK

ARK also targets these instruments and shares the external-data problem — but `Indices ≠ ARK`.
Separate signal engines. Data adapters may be shared through CORE; signal logic may not.

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
