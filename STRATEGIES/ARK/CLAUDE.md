# ARK / Liquid Flow — strategy room

Liquidity-flow and market-structure engine. Per canon it suits liquid indices —
US500/SPX, US100/NSX, US30 — rather than being a gold strategy.

```
Market data -> liquidity observation -> flow analysis -> structure
  -> liquidity event -> directional bias -> entry -> bucket/trade management
```

## ⚠️ BLOCKED — do not invent the signal rules

**The ARK detection mathematics exist in no file and in no document in this repository.**
Legacy `NeoFL_ARK_7_1_MT5.mq5` states outright that the proprietary rules are to be inserted into
`ARKSignal()`, and that function is an empty stub.

Do not derive ARK rules from a legacy file, from the name, or from what seems reasonable.
Ask the product owner. This is the critical-path question for the whole strategy.

## ⚠️ The name trap

`legacy/ark-jobbing-backtest-v3.00/ARK/NeoFL_ARK_Backtest_v3_00.mq5` is **named ARK and is not
ARK.** It implements an opening-range breakout — which is today's **Jobbing** strategy. The name
migrated between strategies. Reading it as ARK is the single most likely mistake in this repo.

`ARK ≠ Jobbing.` Separate EAs, separate signal logic, separate backtests.

## Data constraint — architectural, not incidental

ARK must **not** assume MT5 CFD data contains everything it needs. Where the broker feed cannot
supply the required underlying information, the answer is an external data adapter, never
manufacturing values from insufficient CFD candles.

```
Missing data -> DATA_UNAVAILABLE -> NO SIGNAL / NO TRADE
```

## Legacy reference

- `legacy/ark-7.1-standalone/` — harness only, empty signal. Its multi-asset input list
  (`BTCUSD,XAUUSD,NAS100,...`) conflicts with strategy separation; do not carry it forward.

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
