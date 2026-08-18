# NeoFL Architecture (v2)

Derived from the canon in `docs/product/`. Where this document and the canon disagree, the canon
wins and this document is the bug.

Canon, in authority order:
1. `HANDOFF_DIRECTIVE.md` — governs how version conflicts are resolved.
2. `MASTER_ARCHITECTURE_v2.md` — strategy family and core architecture.
3. `ENGINE_OBSERVER_SCRIPTS_LAYER.md` — engine, observer, and scripts layers.
4. `MASTER_UNIVERSE_CANON.md` — universe structure and documentation index.
5. `MASTER_SPEC_v1.0.md` — **superseded**, historical reference only.

## The central idea

NeoFL is a platform, not a collection of EAs. One shared engine; seven independent strategies that
consume it. The golden rule:

> **Don't duplicate infrastructure. Don't merge strategy logic.**

A strategy answers *what should we trade and why*. The Core answers *can we trade it, how much, how
do we execute it, how do we manage it*. The Observer answers *what is happening*. The external brain
answers *what does it mean and what could be improved*.

The EA layer is therefore **thin** — an EA wires a strategy to the Core and does little else.

## System shape

```
        EXTERNAL SOURCES  (MT5, TradingView, PineConnector, external APIs, Calendar)
                    |
            NEOFL DATA ENGINE
            normalization · validation · instrument resolver
            market data · session · calendar
                    |
            NEOFL CORE ENGINE
            signal · risk · auto-capital · execution · position
            bucket · straddle · stop/BE · trailing · trade state
            logging · diagnostics
                    |
      +-------------+--------------+
      |             |              |
 STRATEGY EAs   OBSERVER NETWORK  SCRIPTS
      |             |              (timing, data, backtest, diagnostics)
 ARK · JOBBING · PRICE ACTION      |
 GOLD · FX · BTC · INDICES    Telemetry / event bus
                                   |
                          EXTERNAL AGENTIC BRAIN
                          analysis · diagnostics · recommendations
                                   |
                          controlled interface -> config -> EA
```

## Strategy separation

Seven strategies, each its own EA with its own signal engine. They share Core, Risk, Execution,
Bucket, Straddle, Stops, Trailing, and Logging — never signal logic.

| Strategy | Nature | Notes |
|---|---|---|
| **ARK / Liquid Flow** | liquidity flow + market structure | Aimed at liquid indices (US500/SPX, US100/NSX, US30). Needs external data. |
| **Jobbing** | US-open opening-range breakout | First M15 candle is the range. Separate EA from ARK. |
| **Price Action** | structure / swings / BOS / CHOCH | Independent of ARK despite shared structure tooling. |
| **Gold** | standalone gold strategy | Symbol resolution is the critical piece. |
| **FX** | asset-specific | FX assumptions stay in the FX module. |
| **BTC** | asset-specific | Must not inherit FX/Gold session, spread, or tick assumptions. |
| **Indices** | US500 / US100 / US30 | CFD feed may be insufficient; external data is architectural. |

Identities that must never blur (handoff directive):
`ARK ≠ Jobbing · Jobbing ≠ Price Action · Gold ≠ FX · FX ≠ BTC · Indices ≠ Gold · Observer ≠ Strategy · External AI ≠ Execution Engine`

## Jobbing — current opening logic

```
US market open -> FIRST M15 candle -> high/low = opening range
    -> M5 execution structure -> breakout -> CHOCH confirmation -> direction -> entry
```

The earlier **three-M15-candle** concept is obsolete. One candle. Jobbing needs a dedicated
US-session timing module rather than broker/server time.

## Bucket and Straddle — the recovery architecture

This is the piece most easily got wrong, and the canon flags it as critical.

A **bucket** is a portfolio of related positions (original trade + straddle + any linked positions),
tracking aggregate floating P/L, breakeven, zero-floating level, recovery state, runner state.
Bucket P/L and individual trade P/L are different concepts.

The straddle's **initial SL is the straddle trade's own breakeven — not the bucket's breakeven.**
The transition at bucket zero must be explicit:

```
Straddle opens -> initial SL = straddle's own BE
    -> monitor whole bucket
    -> bucket floating P/L reaches 0          <- trigger
    -> compute bucket zero-floating price
    -> move straddle SL to that level
    -> close the original losing trade
    -> straddle survives as the profit runner
    -> trail -> exit
```

State machines, to be implemented explicitly rather than as scattered booleans:

```
Trade:     CREATED -> PENDING -> OPEN -> MANAGED -> BREAKEVEN -> TRAILING -> CLOSING -> CLOSED

Straddle:  STRADDLE_NONE -> STRADDLE_PENDING -> STRADDLE_OPEN -> STRADDLE_RECOVERY
           -> BUCKET_ZERO_REACHED -> STRADDLE_PROTECTED -> ORIGINAL_CLOSED
           -> STRADDLE_RUNNER -> TRAILING -> STRADDLE_CLOSED
```

Explicit states prevent closing the original too early, moving SL prematurely, reopening the straddle
repeatedly, treating a closed straddle as active, or miscomputing the zero-floating level.

## Data quality is explicit

Every data source carries a quality state:

```
DATA_OK · DATA_DELAYED · DATA_INCOMPLETE · DATA_UNAVAILABLE · DATA_INVALID
```

MT5 CFD data does **not** necessarily contain everything ARK and the index strategies need. When
required data is missing the answer is `DATA_UNAVAILABLE → NO TRADE`. Never guess, never fabricate,
never trade on manufactured values.

## Symbol resolution

Semantic base-symbol matching, not substring search.

```
XAUUSD · XAUUSDm · XAUUSD.a · XAUUSD.pro · PREFIX_XAUUSD_SUFFIX · GOLD   -> GOLD
BTCXAU                                                                   -> INVALID GOLD
```

`BTCXAU` contains `XAU` and is not gold. The resolver returns an `InstrumentDescriptor`
(asset class, base symbol, broker symbol, tick size, tick value, point, contract size, digits,
trading sessions).

## Observer Network

A monitoring and intelligence layer — never a replacement for deterministic execution. It observes
market, trading, account, and system state, and emits **state transitions**, not just snapshots:

```
SIGNAL_CREATED -> ORDER_SENT -> ORDER_FILLED -> POSITION_OPEN -> BUCKET_CREATED
-> STRADDLE_CREATED -> RECOVERY -> BUCKET_ZERO -> ORIGINAL_CLOSED -> STRADDLE_RUNNER
-> TRAILING -> POSITION_CLOSED -> BUCKET_CLOSED
```

The observer must understand buckets, not merely report `BUY XAUUSD 0.10`.

Confirmed latest components: `NeoFL_Observer_Network_v2_00.mq5`, `NeoFL_Observer_Core_v2_00.mqh`.

## External Agentic Brain

Sits outside deterministic execution and must never become a single point of failure:

```
AI offline -> NeoFL continues deterministic trading
```

Recommendations flow `AI → validation/policy → approval → configuration → EA`. The AI never modifies
live trading logic directly.

## Packaging — hard rule

Every deployable EA ships as one self-contained folder: the `.mq5` plus every `.mqh` and support file
it requires. No dependency hunts across unrelated folders.

```
DEPLOYMENTS/NeoFL_ARK/  ->  NeoFL_ARK.mq5 + required .mqh + support files
```

## Build order

The canon's implementation sequence. Strategies are consumers of a stable engine, so the engine
comes first:

```
1  Core                    7  Straddle Engine        13  Gold
2  Symbol/Instrument       8  Stop / BE / Trailing   14  FX
3  Market Data + Session   9  Observer / Logging     15  BTC
   + Calendar             10  ARK                    16  Indices
4  Risk + Capital         11  Jobbing                17  External Data / Agentic Brain
5  Execution + Position   12  Price Action
6  Bucket Engine
```

## Current state

Repository scaffolding, preserved legacy source, and canon documentation only. **No Core engine
module has been written yet.** Everything under `legacy/` is historical reference — see
`SOURCE_INVENTORY.md` for what each family is and, importantly, what it is not.
