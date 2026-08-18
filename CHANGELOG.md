# Changelog

## 2026-08-16 (build step 6) — Bucket engine

A bucket is a portfolio of related positions, not one position. In this architecture the
basket mechanism **is** the risk control — the legacy analysis confirmed there are no broker
stops behind it — so bucket integrity is treated as a safety property.

### Added
- `python/neofl_core/bucket.py` — bucket composition, aggregate P/L, signed and gross
  exposure, state machine, and the zero-floating-price calculation.
- `tests/unit/test_bucket.py` — 15 tests including the delta-neutral trap.

### The finding that matters: delta-neutral buckets can never recover

The zero-floating price solves

```
P = ( Σ(dᵢ·vᵢ·kᵢ·eᵢ) − costs − realized ) / Σ(dᵢ·vᵢ·kᵢ)
```

**The denominator can be zero.** With a 0.01 long against a 0.01 short, the legs offset
exactly: price movement changes nothing and bucket P/L is frozen at whatever the costs make
it. There is no price at which it reaches zero, so a recovery system waiting for one waits
forever — silently, looking exactly like patience.

This is not contrived; it is what a same-size hedge produces. It is also why the legacy
design pairs **0.03 against 0.01** rather than 0.01 against 0.01. `zero_floating_price()`
returns `None` for these buckets rather than a plausible number, and `is_delta_neutral()`
names the condition.

### Verified
- Zero-floating price exact to 9 decimal places: 0.01 BUY @ 2400 + 0.03 SELL @ 2380 →
  2370.00, with bucket P/L confirmed 0.0 at that price.
- Costs and realized P/L both shift the zero point, and the shifted point still solves to
  exactly zero.
- 112 tests pass.

### Constraints honored from the legacy analysis
- Identity by explicit role, never by comment — `Position` has no comment field, and a test
  asserts it never gains one.
- One basket authority: this module alone computes bucket state.
- Costs included in every P/L figure.
- "No zero-floating price exists" is `None`, distinguishable from a price of zero.

Trading-behavior change: no (state computation only; places no orders)

## 2026-08-16 (build step 4) — Risk engine

Position sizing and risk validation. The strategy requests risk; Core computes size.

### Added
- `CORE/NeoFL_Risk/NeoFL_Risk.mqh` — three risk models (fixed lot, percent of equity,
  percent of balance), hard lot ceiling, exposure and position limits, full broker
  contract validation, and D-002 provenance on every outcome.
- `python/neofl_core/risk.py` + `tests/unit/test_risk.py` — reference mirror, 19 tests
  with hand-computable expected values.

### Three failure modes guarded explicitly
Each produces a plausible-looking number rather than an error, which is what makes them
dangerous:

1. **Bad broker metadata** — a zero `tick_value` or `volume_step` is a division waiting
   to happen. All contract fields are validated before any arithmetic touches them;
   failure BLOCKS with no size returned.
2. **Rounding up to the volume step** — volume is always *floored*, never rounded to
   nearest. A 0.149 requirement becoming 0.15 over-risks silently on every trade. A test
   asserts the floored size never exceeds the budget across a range of risk percentages.
3. **Minimum lot exceeding the risk budget** — routine on a small account with a wide
   stop, not an edge case. $200 equity at 1% is a $2 budget, but the 0.01 minimum over a
   $5 stop risks $5. The engine **DECLINES** rather than quietly trading the minimum,
   which would make "risk percent" meaningless. `allow_min_lot_override` exists, defaults
   to false, and says plainly that it knowingly exceeds the limit.

### Awaiting product approval
Defaults are marked UNCONFIRMED placeholders, not recommendations:
- **Risk model** — currently percent-of-equity.
- **`hard_max_lot = 0.01`** — mirrors the legacy v3.85 hard ceiling, which was a deliberate
  safety rail but appears nowhere in the v2 canon. Whether it carries forward is a product
  decision.

### Verified
- MQL5 compile: 0 errors, 0 warnings. Python: 97 tests pass.
- Sizing checked against hand-computed values ($10,000 at 1% over a $5 stop = 0.20 lots).
- NOT verified: behavior against a live broker account.

Trading-behavior change: **yes — this module sizes positions.** No entry, exit or
direction logic. Risk parameters require product approval before live use.

## 2026-08-16 (D-003) — global sessions: gold spans Asian open to American close

Corrects a wrong assumption in the first Session build, which modelled only the US cash
session. That is right for US indices and wrong for gold and every non-US venue.

### Added
- `CORE/NeoFL_Session/NeoFL_GlobalSessions.mqh` — six venues (Sydney, Tokyo, Hong Kong,
  Frankfurt, London, New York), four DST rules, dealing-session windows, overlap detection,
  the gold trading day, and per-index venue lookup.
- `python/neofl_core/sessions_global.py` + `tests/unit/test_sessions_global.py` — reference
  mirror, 18 tests.

### Why this needed care
DST is not one rule, and one major market has none:

| Region | Rule |
|---|---|
| US | 2nd Sunday March → 1st Sunday November |
| EU / UK | last Sunday March → last Sunday October |
| Australia | 1st Sunday October → 1st Sunday April (inverted, southern hemisphere) |
| Japan | none |

For several weeks a year the regions are genuinely out of step — in mid-March the US has
switched and the EU has not; in late October the reverse. During those weeks London and
New York sit 4 hours apart instead of 5, so the **London/New York overlap moves**. That
overlap is the deepest liquidity window of the day, and a single-rule implementation
trades the wrong one without complaining. Tests assert both divergence windows explicitly.

### Also modelled
- **Tokyo and Hong Kong lunch breaks.** A venue model that ignores them reports liquidity
  that is not there.
- **Week boundaries in GMT** (Friday 22:00 → Sunday 22:00), because brokers disagree about
  when the week starts.
- **Unknown indices return "unknown", never "closed"** — an unrecognised symbol must not
  silently inherit New York's hours.

### Verified
- DST boundary dates asserted against the real calendar for 2025–2027, in both languages.
- MQL5 compile: 0 errors, 0 warnings. Python: 78 tests pass.
- NOT verified: behavior on a live terminal — run `NeoFL_CoreSelfTest` in MT5.

Trading-behavior change: no (reports session state; imposes no trading window)

## 2026-08-16 (build step 3 complete) — Calendar engine

### Added
- `CORE/NeoFL_Calendar/NeoFL_Calendar.mqh` — economic events and news proximity, normalized per
  canon (event id, name, country, currency, importance, scheduled time, forecast/previous/actual,
  seconds to event). Shared by the trading engine and the Observer Network rather than reimplemented
  per EA, so an observer can explain *"this trade occurred around event X"*.

### Design notes
- **"Cannot see the calendar" is never conflated with "nothing scheduled."** MT5's calendar API is
  absent in the Strategy Tester and returns nothing when disconnected; that is `DATA_UNAVAILABLE`,
  and an unreachable calendar can never report `PROCEED`. The self-test asserts this directly.
- `NeoFLCal_SecondsToNextHighImpact()` returns `-1` for "cannot tell" and `INT_MAX` for "nothing
  scheduled". Callers must distinguish them; treating `-1` as "far away" is the mistake the split
  return values exist to make obvious.
- The module reports proximity but does **not** impose a stand-aside window. How close is too close
  differs between a scalper and a swing engine, so that threshold belongs to the strategy.

### Verified
- MQL5 compile: 0 errors, 0 warnings. Both self-test packages rebuilt and redeployed to
  `MQL5/Scripts/NeoFL/`.
- Python suite: 38 tests pass.
- NOT verified: live calendar behavior against a connected terminal — needs a human to run the script.

Build step 3 (Market Data + Session + Calendar) is now complete. Next: step 4, Risk + Capital.

Trading-behavior change: no

## 2026-08-16 (build step 3) — Market Data, Session, Data Quality; rooms; packaging tool

### Added — Core
- `CORE/NeoFL_DataValidation/NeoFL_DataQuality.mqh` — the five data-quality states and the
  `NeoFLDecision` provenance record every engine emits (D-002). Verdicts distinguish DECLINE
  (evaluated, conditions not met — normal) from BLOCKED (could not evaluate) and ERROR.
- `CORE/NeoFL_MarketData/NeoFL_MarketData.mqh` — bars and quotes that report quality instead of
  assuming it. Refuses shift=0 (the forming bar), validates OHLC consistency, reports INCOMPLETE
  rather than silently returning fewer bars, and assesses tick staleness against a freshness budget.
- `CORE/NeoFL_Session/NeoFL_Session.mqh` — US session timing derived from GMT with DST computed,
  never from broker server time. Opening range = the first M15 candle (09:45 ET), per canon.
- `CORE/NeoFL_MarketData/NeoFL_CoreSelfTest.mq5` — MT5 Script, places no orders, exercises all three
  against the live broker.
- `python/neofl_core/session.py` + `tests/unit/test_session.py` — DST and session-window mirror.

### Added — tooling
- `tools/mql5_package.sh` — builds a self-contained deployment package per the canon's hard
  single-folder rule: walks the include graph from an entry `.mq5`, copies every dependency flat,
  rewrites include paths, detects basename collisions, then compiles to prove it deploys.
- `tools/mql5_compile.sh` now stages the parent tree when cross-directory `../` includes are present,
  so CORE modules compile in place during development.

### Added — workspace
- Per-strategy `CLAUDE.md` in all seven `STRATEGIES/*` directories, so a session opened in a
  strategy room arrives knowing that strategy's rules, ancestors and traps.
- `docs/ai/ROOMS.md` — which room owns what. Shared code changes in the infrastructure room only.

### Verified
- MQL5 compile: 0 errors, 0 warnings, both self-tests packaged and deployed.
- Python suite: 38 tests pass.
- DST boundaries asserted against the real calendar for 2024–2027, not recomputed by the logic
  under test.
- NOT verified: behavior against live broker data — needs a human to run the script in MT5.

Trading-behavior change: no (data access, timing, and observability only; no entry/exit/risk rule)

## 2026-08-16 (later still) — first Core module: Symbol Resolver

First NeoFL source code. Build step 2 of the canon order (Symbol / Instrument Resolver).

### Added
- `CORE/NeoFL_SymbolResolver/NeoFL_SymbolResolver.mqh` — resolves a broker symbol to an
  `NeoFLInstrument` descriptor. Semantic base-symbol matching, not substring: XAU counts as gold
  only when it is the BASE, i.e. immediately followed by a recognized quote currency. This is what
  makes `BTCXAU` reject (XAU there is the quote of a crypto cross) while `PREFIX_XAUUSD_SUFFIX`
  resolves.
- `CORE/NeoFL_SymbolResolver/NeoFL_SymbolResolver_SelfTest.mq5` — MT5 Script, places no orders,
  prints PASS/FAIL for every canon case. Deployed to `MQL5/Scripts/NeoFL/`.
- `python/neofl_core/symbol_resolver.py` — reference mirror of the same rules, so the logic is
  testable in milliseconds rather than only inside MetaTrader.
- `tests/unit/test_symbol_resolver.py` — 11 tests covering valid variants, rejections, normalization,
  and mirror consistency with the MQL5 module.

### Fixed
- The repository's gold-only guard flagged the resolver itself, since the resolver must name
  `BTCXAU`/`ETHXAU` to reject them. Exempted the resolver in both languages as the designated
  rejection authority; its own tests assert the rejection behavior.

### Verified
- MQL5 compile: 0 errors, 0 warnings.
- Python suite: 26 tests pass.
- Logic checked case by case; `BTCXAU`, `ETHXAU`, `BTCXAU.pro` all correctly rejected.
- NOT verified: runtime behavior in MT5 against a live broker symbol. The self-test's live-resolve
  section needs a human to run it on a chart.

Trading-behavior change: no (no entry, exit, filter, or risk rule; classification only)

## 2026-08-16 (later) — v2 canon: platform architecture supersedes v1.0

The product owner supplied a revised handoff defining NeoFL as a multi-strategy platform. This
supersedes the v1.0 gold/Trend+ARK specification. No trading code; canon, structure, and docs only.

### Added
- `docs/product/HANDOFF_DIRECTIVE.md` — canon governance; highest-authority document.
- `docs/product/MASTER_ARCHITECTURE_v2.md` — current architecture canon.
- `docs/product/ENGINE_OBSERVER_SCRIPTS_LAYER.md` — engine/observer/scripts layers.
- `docs/product/MASTER_UNIVERSE_CANON.md` — universe structure and whitepaper index.
- v2 directory structure: `CORE/` (19 engines), `STRATEGIES/` (7), `OBSERVER/`, `SCRIPTS/`,
  `DATA/`, `EXTERNAL_BRAIN/`, `BACKTEST/`, `DEPLOYMENTS/`, `python/`.

### Changed
- `MASTER_SPEC_v1.0.md` marked **SUPERSEDED** with a documented v1→v2 diff. Retained per the
  handoff directive's preserve-don't-delete rule.
- `ARCHITECTURE.md`, `CLAUDE.md`, `README.md` rewritten for the platform architecture.
- Tests updated: 12 checks covering core engines, per-strategy isolation, canon presence,
  supersession marking, and the gold-only instrument rule.

### Removed
- Empty v1-only scaffolding (`mt5/`, `external-data/`, `agentic-brain/`, `monitoring/`,
  `infrastructure/`, `backtesting/`). No files lost — all were empty.

### Architecture changes (v1.0 → v2)
- Gold-only platform → multi-asset platform; Gold is one of seven strategies.
- Trend EA + ARK EA → seven independent strategies over one shared Core Engine.
- **Trend Engine removed** from the architecture entirely.
- ARK redefined: gold liquidity/SMC engine → Liquid Flow aimed at indices, requiring external data.
- **Bucket Engine and Straddle Engine added as core** with explicit state machines.
- `ARK_STATE` cross-engine execution lock removed; strategies are independent.
- Build order: 12 phases starting at repo scaffolding → 17 phases starting at NeoFL Core.
- Hard packaging rule: every EA ships with its includes in one folder.

### Findings — legacy reclassified
- `NeoFL_ARK_Backtest_v3_00.mq5` is named ARK but **implements today's Jobbing** (US open, first M15
  candle as opening range, M5 breakout, EMA/RSI). Verified by reading the source. The name moved
  between strategies; the earlier "unrelated strategy" assessment was wrong.
- Its `RequireM5CHoCH` input is **declared and never referenced** — CHOCH is not implemented despite
  being required by the v2 Jobbing architecture. Must be built, not ported.
- `NeoFL_MasterBrain_v3_85.mqh` is the **ancestor of the v2 Straddle Engine** — the most valuable
  legacy asset. Legacy calls it "basket"; v2 calls it "bucket".
- `NeoFL_Observer_Core_v2_00.mqh` is present and is one of the two canon-confirmed latest observer
  components. Its companion `NeoFL_Observer_Network_v2_00.mq5` is **missing**.
- GOLD 5.x/6.x dual-engine line demoted: it implements a Trend Engine that no longer exists.

### Blocked
- ARK / Liquid Flow signal rules remain unspecified in every file and document. Blocks build step 10.
- Four of seven strategies (Price Action, FX, BTC, Indices) have no source at all.

Trading-behavior change: no

## 2026-08-16 — Phase 1: repository foundation

Initial NeoFL repository. No trading code; scaffolding, preservation, and documentation only.

### Added
- Repository structure, master specification, source inventory, architecture and AI docs.
- `tests/` framework with structural and legacy-preservation guards.
- `.gitignore` covering secrets, market data, and MQL5 build output.

### Preserved
- 42 legacy source files copied into `legacy/`, deduplicated and classified into five families.
  Originals untouched in `~/Downloads`.

Trading-behavior change: no
