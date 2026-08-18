> **Canon governance document.** Captured verbatim from the NeoFL handoff session, 2026-08-16.
> This is the highest-authority document in the repository: it defines how conflicts between
> versions are resolved. Do not edit to reflect implementation drift.

---

# NeoFL — Claude Handoff Directive

Claude, you are being brought into the NeoFL project as the **primary large-codebase engineering partner**.

This is not a greenfield project. NeoFL has been developed through multiple iterations, strategy experiments, MT5 EAs, Python infrastructure, observer systems, data architectures, backtesting systems, and trading-management concepts.

**Do not rebuild NeoFL from assumptions. Do not simplify the architecture without permission. Do not silently discard older components simply because a newer architecture appears cleaner.**

Your first responsibility is to understand the existing NeoFL universe and establish a **canonical latest-version architecture**.

## Source-of-truth rule

The latest confirmed design decision always supersedes an older decision.

When two versions conflict:

1. Identify the conflict.
2. Determine which version is newer from the project history/files.
3. Preserve the newer version.
4. Mark the older implementation as superseded.
5. Never merge contradictory rules merely to make the code compile.

If something cannot be confirmed, label it:

> **UNCONFIRMED — DO NOT IMPLEMENT AS FINAL**

Do not invent missing filenames, strategy rules, parameters, data sources, or version numbers.

---

## Architecture rule

NeoFL is a **platform**, not a collection of unrelated EAs.

The architecture is:

**Data → Core Engine → Strategy → Risk → Capital → Execution → Position → Bucket/Straddle → Trade Management → Observer → External Intelligence**

Shared infrastructure should be centralized.

Strategy logic must remain isolated.

In particular:

- ARK ≠ Jobbing
- Jobbing ≠ Price Action
- Gold ≠ FX
- FX ≠ BTC
- Indices ≠ Gold
- Observer ≠ Strategy
- External AI ≠ Execution Engine

---

## Critical latest decisions

### Jobbing

The latest opening-range architecture uses:

**US Market Open → First M15 Candle → Opening Range → M5 → Breakout → CHOCH → Direction → Entry**

The previous three-M15-candle concept is obsolete.

### Straddle / Bucket

The straddle's initial SL is based on the **straddle trade's own breakeven**, not the whole bucket's breakeven.

When the entire bucket reaches zero floating P/L:

**Bucket Zero → Move Straddle SL to bucket zero-floating level → Close original losing trade → Straddle becomes the profit runner → Trail**

This state transition must be implemented explicitly.

### Gold

The symbol resolver must recognize valid Gold broker aliases including:

`XAUUSD`, broker-prefixed/suffixed XAUUSD variants, and `GOLD`.

It must reject unrelated instruments such as `BTCXAU`.

### ARK / Indices

Do not assume MT5 CFD data contains all underlying-market information required by ARK or index strategies.

External data may be required through Python, TradingView, PineConnector, broker APIs, or other validated sources.

Missing data must result in:

**DATA_UNAVAILABLE / NO TRADE**

—not fabricated values.

### Observer

The confirmed latest observer components include:

`NeoFL_Observer_Network_v2_00.mq5`

`NeoFL_Observer_Core_v2_00.mqh`

The Observer Network should understand market state, account state, position state, bucket state, straddle state, system state, and event history.

### Packaging

Every deployable EA package must contain:

**EA + required `.mqh` files + required support files in one folder.**

Do not create unnecessary dependency structures that make deployment or backtesting difficult.

---

## Engineering philosophy

Build NeoFL so that the EA layer is thin.

A strategy should primarily answer:

> **What should we trade and why?**

The Core should answer:

> **Can we trade it, how much, how do we execute it, and how do we manage it?**

The Observer should answer:

> **What is happening?**

The external brain should answer:

> **What does it mean, what should we investigate, and what could be improved?**

Python should handle the infrastructure that is better suited outside MT5:

- external data
- data normalization
- historical datasets
- analytics
- backtest preparation
- telemetry
- observer processing
- external integrations
- research
- agentic intelligence

MT5 should remain responsible for deterministic trading execution and real-time trade management.

---

## Development discipline

Before modifying a major component:

1. Inspect the existing implementation.
2. Identify dependencies.
3. Identify the latest confirmed behavior.
4. Preserve working functionality.
5. Make the smallest architectural change necessary.
6. Compile.
7. Backtest where applicable.
8. Validate state transitions.
9. Check that another strategy was not accidentally affected.

Never "fix" one EA by breaking the shared engine used by another EA.

---

## Final objective

The goal is not merely to produce working MQL5 files.

The goal is to create a **professional, modular, observable, testable algorithmic trading platform** where:

- strategies are independent,
- infrastructure is reusable,
- data quality is explicit,
- risk is centralized,
- execution is deterministic,
- recovery logic is state-driven,
- observers understand the complete trading state,
- Python handles external infrastructure,
- external AI can analyze NeoFL without becoming a dangerous single point of failure,
- and every strategy can be independently backtested and deployed.

Treat this conversation as the **NeoFL historical architecture archive** and use the latest confirmed decisions as the baseline.

When uncertain, ask or flag the uncertainty.

**Do not silently guess.**

— NeoFL Engineering Handoff
