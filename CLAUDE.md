# NeoFL — instructions for AI agents

> **This is the INFRASTRUCTURE + MT5 room.** The MQL5 tree lives here: CORE, STRATEGIES,
> OBSERVER, SCRIPTS, DEPLOYMENTS, BACKTEST, plus build tooling, canon, decisions and tests.
> **This room holds the only code permitted to place an order.**
>
> Two other rooms exist (D-007): `python/` for analysis, data and the gateway, and one per
> strategy under `STRATEGIES/<NAME>/`. Shared-code changes happen **here only** — another
> room cannot see whether a CORE change broke its six siblings. See `docs/ai/ROOMS.md`.

NeoFL is a modular algorithmic trading platform for MetaTrader 5: one shared Core engine, seven
independent strategies. Real money is the eventual endpoint, so the constraints below are hard rules.

**Read first, in this order:**
1. `docs/product/HANDOFF_DIRECTIVE.md` — highest authority; governs version conflicts.
2. `docs/product/MASTER_ARCHITECTURE_v2.md` + `ENGINE_OBSERVER_SCRIPTS_LAYER.md` — current canon.
3. `docs/architecture/ARCHITECTURE.md` — derived summary.
4. `docs/architecture/SOURCE_INVENTORY.md` — what the legacy source is, and what it is not.

`docs/product/MASTER_SPEC_v1.0.md` is **superseded**. Do not implement from it.

## This is not a greenfield project

NeoFL has been through many iterations. Do **not** rebuild from assumptions, simplify the
architecture without permission, or silently discard older components because a newer design looks
cleaner.

When two versions conflict: identify the conflict, determine which is newer, preserve the newer, mark
the older superseded. **Never merge contradictory rules just to make code compile.**

If something cannot be confirmed, label it `UNCONFIRMED — DO NOT IMPLEMENT AS FINAL`.

Never invent filenames, strategy rules, parameters, data sources, or version numbers.

## The line you do not cross

**Trading logic belongs to the human product owner.** You may not add, remove, or alter an entry
rule, exit rule, filter, threshold, or risk parameter because you believe it performs better.

If you think a strategy is wrong: state the problem, give evidence, propose the change, explain the
expected effect and the risk, and **ask**. Then wait.

Implementation detail — data structures, refactors, tests, tooling, docs — is yours to decide.

## Do not fabricate

- Never say code compiled unless you actually compiled it. **You can compile on this Mac** —
  `tools/mql5_compile.sh` drives MetaEditor through MetaTrader 5.app's bundled Wine. So compile;
  don't guess, and don't claim it either way without running it.
- Never say a backtest ran unless it ran, or a trade executed unless you verified it.
- Never invent market data, broker behavior, or API responses.
- Missing data means `DATA_UNAVAILABLE → NO TRADE`, never a guessed value.
- Report failures honestly, including your own.

Know what each signal proves: a passing Python test means the **logic** is right; a clean compile
means the code is **valid MQL5**. Neither says the strategy works or is profitable. Static text
checks over `.mq5` verify contract presence only — never describe them as compilation.

See `docs/testing/RUNNING.md` for the four verification loops and their limits.

## Architecture rules

1. **Don't duplicate infrastructure. Don't merge strategy logic.** The golden rule.
2. Strategies never reimplement execution, risk, position, bucket, symbol, or capital code — they
   request it from Core.
3. The EA layer is thin. Strategy says *what and why*; Core says *whether, how much, how*.
4. These identities never blur: `ARK ≠ Jobbing`, `Jobbing ≠ Price Action`, `Gold ≠ FX`, `FX ≠ BTC`,
   `Indices ≠ Gold`, `Observer ≠ Strategy`, `External AI ≠ Execution Engine`.
5. Never fix one EA by breaking a shared engine another EA depends on.
6. Asset-specific assumptions live in adapters and configuration, never in Core.
7. **Packaging:** every deployable EA ships as one folder containing the `.mq5` and every `.mqh` and
   support file it needs.
8. **AI processes data only — it holds no order authority** (decision D-001). AI may read market
   data, positions, history, logs, and telemetry, and may analyze and recommend. It may never place,
   modify, or close an order, or change live risk parameters. Recommendations flow through
   validation → human approval → configuration, never directly into live logic. And external AI must
   never be a single point of failure: if every AI component is offline, NeoFL keeps trading.
9. **Every engine emits decision provenance** (decision D-002). The AI's job is to verify engines
   process data correctly, which is only possible if each decision carries its inputs, data quality,
   the decision, the reason, and what was rejected and why. A bare `true`/`false` or a bare order is
   not verifiable. **Absence of a signal must itself be an observable event** — "no trade: ATR 18
   below minimum 50" is verifiable; silence is not. See `CORE/NeoFL_SymbolResolver` (`reject_reason`)
   for the house pattern.
10. Gold symbol resolution is semantic, not substring: `GOLD` and XAUUSD broker variants are valid;
    `BTCXAU` is rejected.

## Critical latest decisions

- **Jobbing:** the opening range is the **first M15 candle**. The three-M15-candle concept is
  obsolete. Then M5 → breakout → CHOCH → direction → entry.
- **Straddle initial SL is the straddle trade's own breakeven — NOT the bucket's breakeven.**
- **At bucket zero floating:** move straddle SL to the bucket zero-floating level, close the original
  losing trade, and the straddle becomes the profit runner, then trails. Implement as an explicit
  state transition.
- **Bucket P/L ≠ individual trade P/L.** Different concepts.
- **ARK / Indices:** do not assume MT5 CFD data contains everything the strategy needs.

## Legacy code

`legacy/` is **read-only reference**. Preserve it; never edit or delete it.

Filenames there are unreliable — read the code:

- `NeoFL_ARK_Backtest_v3_00.mq5` is named ARK but implements today's **Jobbing** (opening range).
- `NeoFL_Jobbing_Backtest_v3_00.mq5` is micro-scalping, not today's Jobbing.
- The GOLD 5.x/6.x dual-engine line implements a **Trend Engine that no longer exists** in v2.

The genuinely valuable ancestors: `NeoFL_MasterBrain_v3_85.mqh` (straddle/recovery) and
`NeoFL_Observer_Core_v2_00.mqh` (confirmed-latest observer core).

## Secrets

Never request, log, echo, commit, or place in code: broker credentials, API keys or secrets, exchange
credentials, AI API keys, SSH keys, or account passwords. Environment variables and untracked local
config only. Do not work around `.gitignore`.

## The standard of proof here

MQL5 runs on the tick path with real money behind it. A mistake is an order, not a wrong
answer.

```bash
tools/mql5_compile.sh <dir-or-file.mq5>     # must be 0 errors, always
tools/mql5_package.sh <entry.mq5> <outdir>  # self-contained package, canon rule 7
```

**Compiling proves the code is valid MQL5. Nothing more.** It does not prove the strategy
works, that the numbers are right, or that the broker will accept the order. Say so when
reporting.

The Strategy Tester needs broker credentials, so an agent cannot run it. Backtests and demo
results are human-observed evidence and must be reported as such.

## Rules specific to this room

1. **Identity by magic number or ticket registry — never by comment.** Comments are not
   reliable broker state. See `docs/architecture/LEGACY_STRADDLE_DEFECTS.md` for what went
   wrong when this was violated.
2. **One writer per piece of shared state.** Two components writing the same global variable
   is the defect that silently broke v3.85 straddle sizing.
3. **No absolute lot or money constants.** Derive from the account (D-006) — a number tuned
   on one account is wrong on another by up to 100×.
4. **Refuse rather than degrade.** A capped straddle under-covers its gap; a delta-neutral
   basket can never reach zero. Refusing and saying why beats acting on something that
   cannot work.
5. **Emit decision provenance** (D-002) — including refusals. Silence is indistinguishable
   from a broken engine.
6. **`legacy/` is read-only.** Preserve it; never edit or delete.

## Handing work to the Python room

Anything analytical — measuring whether a rule helps, processing history, external data,
telemetry — belongs in the Python room. Write down what you need and hand it over rather
than building an analysis engine inside an EA.

## Workflow

- Git is the source of truth; commit meaningful changes; branch for significant work.
- Before modifying a major component: inspect the existing implementation, identify dependencies,
  identify the latest confirmed behavior, preserve working functionality, make the smallest
  architectural change necessary, then verify — and check you did not affect another strategy.
- Write tests for new functionality; run them before claiming completion.
- Keep `CHANGELOG.md` current.
- Any trading-behavior change must state: what changed, why, expected effect, risk, tests performed,
  and whether product approval is required.

## Build order

Core first — strategies are consumers of a stable engine, not their own mini-frameworks.

```
1 Core · 2 Symbol/Instrument · 3 Market Data+Session+Calendar · 4 Risk+Capital
5 Execution+Position · 6 Bucket · 7 Straddle · 8 Stop/BE/Trailing · 9 Observer/Logging
10 ARK · 11 Jobbing · 12 Price Action · 13 Gold · 14 FX · 15 BTC · 16 Indices
17 External Data / Agentic Brain
```

## Current state

Scaffolding, preserved legacy source, and canon documentation. **No Core module written yet.**
Next step is Phase 1 (NeoFL Core) — but note the ARK signal rules are still unspecified and block
Phase 10. See the open questions in `SOURCE_INVENTORY.md`.

**When uncertain, ask or flag it. Do not silently guess.**
