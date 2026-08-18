# NeoFL Legacy Source Inventory

Audit date: 2026-08-16. Reclassified the same day against the v2 canon.
Covers every `.mq5` / `.mqh` found on this workstation. Originals remain in `~/Downloads`;
`legacy/` holds a deduplicated, classified copy.

Per `HANDOFF_DIRECTIVE.md`, superseded work is **preserved, never deleted**. Nothing here is an
active specification. But — corrected from the first pass — several of these files are the direct
ancestors of current architecture, not dead ends.

## Reclassification notice

An earlier version of this document assessed the legacy source against the now-superseded
`MASTER_SPEC_v1.0.md`. Three of its conclusions were wrong under the v2 canon and are corrected below.

| First assessment | Corrected under v2 canon |
|---|---|
| `NeoFL_ARK_Backtest_v3_00.mq5` is "an unrelated opening-range strategy" | It **is** the direct ancestor of today's **Jobbing** strategy. Right about the strategy, wrong about the relevance — the name moved, the strategy did not. |
| Candle Revisit / Master Brain family is "a different strategy, not in spec" | Its **straddle/recovery machinery is now a core platform engine**. The most valuable legacy asset in the repo. |
| `NeoFL_GOLD_6.6_ARK_PREEXECUTION_LOCK.mq5` is "the primary reference for Phase 3" | Demoted. The Trend/ARK execution lock it implements belongs to an architecture that **no longer exists** — there is no Trend Engine in v2 and strategies no longer share an execution lock. |

## Headline finding

The legacy source is **five unrelated strategy families**. Under the v2 canon their value is very
uneven:

| Family | Files | Status under v2 canon |
|---|---|---|
| A. GOLD dual-engine 5.2→6.6 | 15 | **Largely obsolete.** Monolithic Trend+ARK; v2 has no Trend Engine and forbids monoliths. |
| B. ARK 7.1 standalone | 2 | Harness only. ARK signal is an empty stub. Multi-asset input list conflicts with v2. |
| C. Candle Revisit / Master Brain | 17 | **Most valuable.** Contains the straddle/recovery ancestor and Observer Core v2.00. |
| D. ARK + Jobbing backtest v3.00 | 6 | **Ancestor of current Jobbing.** Despite the ARK filename. |
| E. Observer Network v1.20 | 2 | Superseded by v2.00, but v2.00's `.mq5` is missing — see Not Found. |

## Family D — the naming migration (`legacy/ark-jobbing-backtest-v3.00/`)

**The most important finding of this audit.**

`NeoFL_ARK_Backtest_v3_00.mq5` is named ARK but implements what the v2 canon calls **Jobbing**.
Verified by reading the source:

- US session 09:30–16:00 ET with automatic DST calculation
- First completed M15 candle after the open taken as the opening range (`hi`/`lo`)
- First M5 close outside that range establishes direction
- M5 EMA(20/50) and RSI(14) confirmation
- Opposite breakout can reverse the position

Compare the v2 Jobbing definition: *US market open → first M15 candle → opening range → M5 →
breakout → CHOCH → direction → entry.* Same strategy.

So the historical "ARK" name migrated to a different strategy. In v2, **ARK is Liquid Flow** — a
liquidity/market-structure engine aimed at indices. The file is therefore the Jobbing ancestor and
should be read that way.

Two concrete gaps versus the v2 Jobbing spec:

1. **CHOCH is not implemented.** The input `RequireM5CHoCH` is declared and *never referenced
   anywhere else in the file* — a dead input. The v2 architecture requires CHOCH confirmation. It
   must be built, not ported.
2. Direction currently comes from breakout plus EMA/RSI, with CHOCH absent from the decision path.

The sibling `NeoFL_Jobbing_Backtest_v3_00.mq5` is a *different* concept again — tick-driven micro
scalping, 60-second max hold, cooldown. It is not the v2 Jobbing strategy despite the filename.
Both files' names are unreliable; read the code.

## Family C — Candle Revisit / Master Brain (`legacy/candle-revisit-master-brain/`)

The longest lineage (v1.00 → v3.85, 2026-08-13→16) and the most actively developed. Its *entry*
strategy (M5 candle-level classification and revisit) is not a v2 strategy — but its **recovery
machinery is now core platform architecture**.

`NeoFL_MasterBrain_v3_85.mqh` is the direct ancestor of the v2 **Straddle Engine**: dynamic straddle
lot sizing from actual floating loss and entry gap, basket P/L as exit authority, explicit basket
breakeven and target levels, published diagnostic values (`STRADDLE_REQUIRED_LOTS`, `BASKET_PNL`,
`BASKET_BE_PRICE`, `STRADDLE_COVERAGE`, and others).

Note the vocabulary shift: the legacy code says **basket**, the v2 canon says **bucket**. Same
concept. When porting, confirm whether legacy "basket" semantics match the v2 bucket definition
exactly — particularly the zero-floating trigger and the *straddle-BE-not-bucket-BE* initial SL rule,
which is the single most emphasized detail in the canon.

`NeoFL_Observer_Core_v2_00.mqh` lives in this family's v3.85 package. **This is one of the two
confirmed-latest Observer components named in the canon** — it is present and preserved.

Also carried here: the decision/execution split (MasterBrain decides, `CTrade` alone executes),
matching v2's thin-EA principle; the hard 0.01 lot ceiling; the account risk governor; MT5 calendar
integration.

Architectural rule in these headers since v3.66, worth recording because it constrains M1 usage:

> M5 is the ONLY initial-entry engine. M1 has NO initial-entry pathway. M1 is strictly an
> existing-trade monitor/protection/reassessment engine.

Under v1.0 this contradicted the Trend entry sequence. Under v2 there is no Trend Engine, so the
contradiction is moot — but the rule should be confirmed as still-current before it is carried into
any new strategy.

## Family A — GOLD dual-engine (`legacy/gold-dual-engine-5.x-6.x/`)

Lineage 5.2 → 6.6, dated 2026-08-13. Two structural generations:

- **5.2 – 6.3** (~140–155 KB): multi-symbol scanner heritage carrying a NeoFL 4.3 "segregated
  capital" preamble. Large and accreted.
- **6.4 – 6.6** (~25–31 KB): deliberate rewrite. Trend on M5 + synthetic/actual M15 + M30 survival;
  M1 liquidity-sweep entry and trailing; ARK as an independent M15 event engine. Separate magic
  numbers (`InpMagicTrend=64001`, `InpMagicARK=64002`).

`NeoFL_GOLD_6.6_ARK_PREEXECUTION_LOCK.mq5` implements a pre-execution lock so Trend and ARK could not
execute simultaneously. **Under v2 this problem no longer exists** — strategies are independent EAs
without a shared execution lock, and there is no Trend Engine. Retained as historical reference for
how cross-engine arbitration was approached, not as a template.

Caveat: 6.5 and 6.6 carry stale internal version strings (`#property version "6.40"`). Filenames are
the reliable ordering.

## Family B — ARK 7.1 standalone (`legacy/ark-7.1-standalone/`)

`NeoFL_ARK_7_1_MT5.mq5` plus a `_CTrade` variant, ~11 KB. Multi-asset scanner with M1 execution and
re-entry.

The header states that the proprietary ARK rules are to be inserted into `ARKSignal()`. **The ARK
mathematics are not in this file** — it is a harness. Combined with the v2 canon's description of ARK
as Liquid Flow requiring external data, the ARK signal logic remains genuinely unspecified anywhere
in this repository.

Its default symbol list (`BTCUSD,XAUUSD,NAS100,US30,GER40,ETHUSD`) conflicts with v2 strategy
separation — one EA scanning many assets is exactly what the v2 architecture splits apart. Do not
carry that input list forward.

## Family E — Observer Network (`legacy/observer-network/`)

`NeoFL_Observer_Network_v1_20_Institutional.mq5` + `NeoFL_Observer_Core.mqh` (v1.x). A script that
never trades: M1 observation, drawdown, realized P&L, win/loss probability, safe-withdrawal
monitoring, published through MT5 global variables.

Superseded by the v2.00 components. The "observe and publish, never execute" split is exactly the v2
Observer principle and carries forward.

## Duplicates

Byte-identical browser re-downloads were dropped: three copies of Candle Revisit v3.67, three of
v3.80 Institutional, three of `M1WithinM5_v3_31`, two of `StopAndReverse_EA`. Originals untouched in
`~/Downloads`.

`StopAndReverse_EA.mq5` and the pre-NeoFL-prefix `Candle_Level_Revisit_*` files are kept for lineage.
`StopAndReverse_EA` was separately reimplemented in the unrelated Neokart repo at
`~/Documents/New project/mt5_stop_reverse_ea/` — not part of NeoFL.

## Not found

Named in canon but **absent from this machine**:

- `NeoFL_Observer_Network_v2_00.mq5` — the canon names it as confirmed-latest. Only v1.20 is present.
  Its companion `NeoFL_Observer_Core_v2_00.mqh` **is** present (in the v3.85 package), so the pair is
  split. Recovering the v2.00 network file is worth doing before Phase 9.
- NeoFL GOLD 7.0 Trend / ARK Engine builds (cited in superseded v1.0 spec §6). Lower priority now
  that the Trend Engine is out of the architecture.
- Price Action, FX, BTC, and Indices strategy source — no files for four of the seven v2 strategies.
- Any implementation of Bucket, Risk, Auto-Capital, Execution, Symbol Resolver, or Session as
  standalone shared modules. The v2 Core does not exist in any form.

## Classification summary

| Label | Files |
|---|---|
| current architecture | **none** — no file implements the v2 platform |
| ancestor of current | Family D ARK file (→ Jobbing); Family C MasterBrain (→ Straddle); Observer Core v2.00 |
| superseded | Family A (all), Family B, Family E v1.20 |
| backtest artifacts | Family D; Family C v3.85 package |
| name-collision hazards | Family D "ARK" (is Jobbing); Family D "Jobbing" (is micro-scalping) |

## Open questions for the product owner

These block the build order. None can be answered by reading code.

1. **What are the ARK / Liquid Flow rules?** Still the critical path. `ARKSignal()` is empty; no file
   implements liquidity-flow detection. v2 adds that ARK targets indices and needs external data,
   which sharpens the question but does not answer it.
2. **Does legacy "basket" equal v2 "bucket" exactly?** Determines whether the v3.85 MasterBrain
   straddle logic can be ported or must be rewritten against the canon's state machine.
3. **Where is `NeoFL_Observer_Network_v2_00.mq5`?** Confirmed-latest by canon, missing here.
4. **Is the v3.66 "M1 never initiates entry" rule still current** for the v2 strategies?
5. **Which external data source is intended for ARK/Indices** — PineConnector, a broker API, or a
   Python-fed dataset? The canon presents all three as possible and explicitly declines to choose.
6. **Which broker/symbol is authoritative for the demo account?** Needed for the symbol resolver.
