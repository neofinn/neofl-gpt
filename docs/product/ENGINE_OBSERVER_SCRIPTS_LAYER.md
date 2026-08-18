> **Current architecture canon, engine/observer/scripts layer.** Captured verbatim from the
> NeoFL handoff session, 2026-08-16. Extends `MASTER_ARCHITECTURE_v2.md`.

---

Yes. We should extend the Claude handoff so it includes **the actual latest NeoFL engine/observer/script layer**, not just the strategy architecture.

The updated architecture should be treated as:

```text
                         NEOFL PLATFORM
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
   CORE ENGINES           OBSERVER NETWORK       SCRIPTS
        │                     │                     │
        │                     │                     ├─ Timing
        │                     │                     ├─ Backtest
        │                     │                     ├─ Data
        │                     │                     └─ Utility
        │                     │
        └──────────────┬──────┴──────────────┐
                       ▼                     ▼
                 STRATEGY EAs          EXTERNAL BRAIN
                       │                     │
       ┌───────────────┼─────────────┐       │
       ▼               ▼             ▼       ▼
      ARK           JOBBING       PRICE ACTION  AI
       │               │             │
       ├─ Gold         ├─ FX         ├─ BTC
       └─ Indices      └─ ...        └─ ...
```

# 1. Latest NeoFL Engine Layer

The **engine layer** is now the foundation underneath every EA.

```text
NeoFL Engine
│
├── Core Engine
│
├── Market Data Engine
│
├── Instrument / Symbol Engine
│
├── Session Engine
│
├── Calendar Engine
│
├── Market Structure Engine
│
├── Liquidity / Flow Engine
│
├── Signal Engine
│
├── Risk Engine
│
├── Auto-Capital Engine
│
├── Execution Engine
│
├── Position Engine
│
├── Bucket Engine
│
├── Straddle Engine
│
├── Stop Engine
│
├── Breakeven Engine
│
├── Trailing Engine
│
├── Trade-State Engine
│
├── Data Validation Engine
│
├── Telemetry Engine
│
├── Logging Engine
│
└── Observer Interface
```

The important architectural change is that **ARK, Jobbing, Price Action, Gold, FX, BTC and Indices all consume the same core engines**.

---

# 2. Market Data Engine

This becomes especially important for ARK and Indices.

```text
                    DATA SOURCES
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
         MT5       PineConnector    External API
          │              │              │
          └──────────────┼──────────────┘
                         ▼
                 DATA NORMALIZER
                         ▼
                DATA VALIDATION
                         ▼
                MARKET DATA ENGINE
                         ▼
              STRATEGY DATA OBJECT
```

The engine must know:

- source
- timestamp
- symbol
- timeframe
- OHLC
- tick data where available
- spread
- volume where available
- data freshness
- data quality
- external-feed status

This solves the earlier ARK/indices problem where **the CFD itself may not provide the underlying information required by the strategy**.

---

# 3. Latest Observer Network

The Observer Network should now be a first-class NeoFL subsystem.

The latest observer work discussed included:

```text
NeoFL_Observer_Network_v2_00.mq5
NeoFL_Observer_Core_v2_00.mqh
```

and the calendar component was also included in that observer architecture.

The architecture becomes:

```text
                    NEOFL EAs
                       │
                       ▼
                OBSERVER INTERFACE
                       │
                       ▼
              ┌──────────────────┐
              │ Observer Core     │
              │ v2.00             │
              └────────┬─────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   Market Observer  Trade Observer  System Observer
        │              │              │
        └──────────────┼──────────────┘
                       ▼
              Observer Network
                    v2.00
                       │
                       ▼
                External Brain
```

---

# 4. Observer Core

`NeoFL_Observer_Core_v2_00.mqh` should be treated as the **observer intelligence/collection core**, not as a trading strategy.

It should collect normalized state from the EA/engine:

```text
MARKET
├── Symbol
├── Price
├── Spread
├── Session
├── Volatility
├── Structure
├── Liquidity state
└── Data quality

TRADING
├── Open positions
├── Pending orders
├── Bucket state
├── Straddle state
├── SL state
├── BE state
├── Trailing state
└── Exposure

ACCOUNT
├── Balance
├── Equity
├── Margin
├── Free margin
├── Drawdown
└── Risk utilisation

SYSTEM
├── EA state
├── Engine state
├── Data-feed state
├── Execution errors
├── Connection
├── Calendar
└── External-data status
```

---

# 5. Observer Network

The Network is the aggregation layer.

```text
ARK EA ─────────────┐
Jobbing EA ─────────┤
Price Action EA ────┤
Gold EA ────────────┤
FX EA ──────────────┤
BTC EA ─────────────┤
Indices EA ─────────┤
                    ▼
          NeoFL Observer Network
                    │
          ┌─────────┼─────────┐
          ▼         ▼         ▼
       Market     Trade     System
       State      State     State
          │         │         │
          └─────────┼─────────┘
                    ▼
              Telemetry Bus
                    ▼
             External Brain
```

This allows the external brain to see **the whole NeoFL ecosystem without being responsible for executing trades**.

---

# 6. Observer Must Understand Buckets

This is important.

The observer shouldn't only report:

```text
BUY XAUUSD 0.10
```

It should understand:

```text
BUCKET #123
│
├── Original Trade
│     ├── Direction
│     ├── Entry
│     ├── SL
│     ├── Floating P/L
│     └── State
│
└── Straddle
      ├── Direction
      ├── Entry
      ├── Initial SL
      ├── Current SL
      ├── Floating P/L
      └── State

Bucket:
├── Aggregate P/L
├── Zero-floating level
├── Recovery state
└── Runner state
```

This is necessary for the latest straddle architecture.

---

# 7. Observer Trade Lifecycle

Observer events should be state based.

```text
SIGNAL_CREATED
      ↓
ORDER_SENT
      ↓
ORDER_FILLED
      ↓
POSITION_OPEN
      ↓
BUCKET_CREATED
      ↓
STRADDLE_CREATED
      ↓
RECOVERY
      ↓
BUCKET_ZERO
      ↓
ORIGINAL_CLOSED
      ↓
STRADDLE_RUNNER
      ↓
TRAILING
      ↓
POSITION_CLOSED
      ↓
BUCKET_CLOSED
```

This gives the external brain an actual **event history**, rather than only snapshots.

---

# 8. Calendar Engine + Observer

Calendar should be shared by both the trading engine and observer.

```text
Calendar
   │
   ├── Market open/close
   ├── Holidays
   ├── Session boundaries
   ├── Economic events
   └── Trading restrictions
          │
          ├──────────► Trading Engine
          │
          └──────────► Observer Network
```

So the observer can explain:

> Trade occurred during X session / around X event / outside restricted window.

---

# 9. Scripts Layer

Scripts should **not become hidden EAs**.

They are utilities around the platform.

```text
NEOFL SCRIPTS
│
├── Timing Scripts
│
├── Backtest Scripts
│
├── Data Scripts
│
├── Session Scripts
│
├── Symbol/Instrument Scripts
│
├── Diagnostics Scripts
│
└── Deployment/Utility Scripts
```

---

# 10. Latest Jobbing Timing Script

The latest Jobbing architecture specifically needs a **US-market timing component**.

The timing logic is:

```text
US SESSION
     │
     ▼
MARKET START
     │
     ▼
FIRST M15 CANDLE
     │
     ├── HIGH
     └── LOW
          │
          ▼
INITIAL RANGE
          │
          ▼
M5 EXECUTION
          │
          ▼
BREAKOUT
          │
          ▼
CHOCH
          │
          ▼
JOBBING DIRECTION
```

The old **three-M15-candle opening range is removed**.

The first M15 candle is the opening range.

---

# 11. Jobbing Script + EA Separation

For backtesting:

```text
NeoFL_Jobbing.mq5
       │
       ├── Jobbing Strategy
       ├── Timing Engine
       ├── Range Engine
       ├── CHOCH Engine
       └── Core Engines
```

The timing logic should be available to the EA for backtesting rather than relying on manually configured chart markings.

---

# 12. ARK Scripts

ARK needs a different script family because its problem is **data**, not simply timing.

```text
ARK
│
├── Data Input Script
├── External Data Adapter
├── Data Validation
├── Liquidity Observation
└── Backtest Data Preparation
```

The key design:

```text
External/Underlying Data
        ↓
ARK Data Script
        ↓
Normalized ARK Dataset
        ↓
ARK Engine
        ↓
ARK EA
```

This prevents the ARK EA from assuming that broker CFD candles contain unavailable information.

---

# 13. Indices Data Scripts

The same architecture applies to:

- US500
- US100
- US30

```text
Underlying / External Data
           ↓
     Indices Data Script
           ↓
     Data Normalization
           ↓
      Quality Validation
           ↓
      NeoFL Index Engine
           ↓
        Indices EA
```

---

# 14. Backtest Script Architecture

Backtesting should become a separate subsystem.

```text
                    BACKTEST
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
      ARK          JOBBING       PRICE ACTION
        │              │              │
        ├── Gold       ├── FX         ├── BTC
        └── Indices    └── ...
                       │
                       ▼
              SAME CORE ENGINE
                       │
                       ▼
               BACKTEST REPORT
```

The backtest environment should use the **same signal/risk/trade-management logic** as live wherever possible.

---

# 15. External Brain Architecture

The Observer Network becomes the bridge to the external AI.

```text
                 MT5
                  │
                  ▼
          NeoFL Observer Core
                  │
                  ▼
       NeoFL Observer Network
                  │
             Telemetry
                  │
                  ▼
        External Agentic Brain
                  │
       ┌──────────┼──────────┐
       ▼          ▼          ▼
   Analysis   Diagnostics  Research
       │          │          │
       └──────────┼──────────┘
                  ▼
          Recommendations
                  │
                  ▼
        Controlled Interface
                  │
                  ▼
             NeoFL Core
```

The **controlled interface** is important.

AI recommendation:

```text
"Reduce risk for this strategy"
```

doesn't mean:

```text
AI directly changes live EA
```

Instead:

```text
Recommendation
     ↓
Validation
     ↓
Approval / Policy
     ↓
Configuration
     ↓
EA
```

---

# 16. Latest Complete NeoFL Architecture

Putting everything together:

```text
                         ┌──────────────────────┐
                         │   EXTERNAL SOURCES   │
                         │                      │
                         │ MT5                  │
                         │ TradingView          │
                         │ PineConnector        │
                         │ External APIs        │
                         │ Calendar             │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │ NEOFL DATA ENGINE     │
                         │                      │
                         │ Normalization        │
                         │ Validation            │
                         │ Instrument Resolver  │
                         │ Market Data          │
                         │ Session               │
                         │ Calendar              │
                         └──────────┬───────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │       NEOFL CORE ENGINE       │
                    │                               │
                    │ Signal                        │
                    │ Risk                          │
                    │ Auto Capital                  │
                    │ Execution                     │
                    │ Position                      │
                    │ Bucket                        │
                    │ Straddle                      │
                    │ Stop / BE                     │
                    │ Trailing                      │
                    │ Trade State                   │
                    │ Logging                       │
                    │ Diagnostics                   │
                    └──────────────┬────────────────┘
                                   │
             ┌─────────────────────┼──────────────────────┐
             │                     │                      │
             ▼                     ▼                      ▼
        STRATEGY EAs          OBSERVER NETWORK          SCRIPTS
             │                     │                      │
       ┌─────┼──────┐              │              ┌───────┼────────┐
       ▼     ▼      ▼              ▼              ▼       ▼        ▼
      ARK  JOBBING  PA       Observer Core     Timing  Data    Backtest
       │     │      │              │
       ├─────┼──────┤              ▼
       ▼     ▼      ▼        Telemetry/Event Bus
     GOLD   FX     BTC             │
       │     │      │              ▼
       └─────┴──────┘       EXTERNAL AGENTIC
             │                   BRAIN
             ▼                     │
          INDICES                  ▼
                              Analysis /
                              Diagnostics /
                              Recommendations
```

---

# 17. Recommended Claude Folder Structure

```text
NEOFL/
│
├── CORE/
│   ├── NeoFL_Core
│   ├── NeoFL_Engine
│   ├── NeoFL_Risk
│   ├── NeoFL_AutoCapital
│   ├── NeoFL_Execution
│   ├── NeoFL_Position
│   ├── NeoFL_Bucket
│   ├── NeoFL_Straddle
│   ├── NeoFL_Stop
│   ├── NeoFL_Breakeven
│   ├── NeoFL_Trailing
│   ├── NeoFL_TradeState
│   ├── NeoFL_SymbolResolver
│   ├── NeoFL_MarketData
│   ├── NeoFL_Session
│   ├── NeoFL_Calendar
│   ├── NeoFL_DataValidation
│   ├── NeoFL_Logger
│   └── NeoFL_Diagnostics
│
├── STRATEGIES/
│   ├── ARK/
│   ├── JOBBING/
│   ├── PRICE_ACTION/
│   ├── GOLD/
│   ├── FX/
│   ├── BTC/
│   └── INDICES/
│
├── OBSERVER/
│   ├── NeoFL_Observer_Network_v2_00.mq5
│   ├── NeoFL_Observer_Core_v2_00.mqh
│   ├── Calendar
│   ├── MarketObserver
│   ├── TradeObserver
│   ├── BucketObserver
│   ├── SystemObserver
│   └── Telemetry
│
├── SCRIPTS/
│   ├── JOBBING/
│   │   ├── US_Timing
│   │   ├── OpeningRange
│   │   └── CHOCH
│   │
│   ├── ARK/
│   │   ├── ExternalData
│   │   ├── LiquidityData
│   │   └── DataValidation
│   │
│   ├── INDICES/
│   │   └── ExternalData
│   │
│   ├── BACKTEST/
│   ├── SESSION/
│   └── DIAGNOSTICS/
│
├── EXTERNAL_BRAIN/
│   ├── Telemetry
│   ├── EventStream
│   ├── MarketState
│   ├── TradeState
│   ├── Analytics
│   └── RecommendationInterface
│
└── DEPLOYMENTS/
    ├── NeoFL_ARK/
    ├── NeoFL_Jobbing/
    ├── NeoFL_PriceAction/
    ├── NeoFL_Gold/
    ├── NeoFL_FX/
    ├── NeoFL_BTC/
    └── NeoFL_Indices/
```

### One correction to the previous handoff

I would **not invent filenames for scripts that we haven't explicitly established**. The confirmed observer filenames I have from the latest project work are:

- `NeoFL_Observer_Network_v2_00.mq5`
- `NeoFL_Observer_Core_v2_00.mqh`

The **US timing/opening-range/CHOCH components, ARK external-data components, index data components, and backtest components should be represented as architectural modules until their exact latest filenames/versions are recovered from the actual files.**

That keeps the Claude handoff technically honest instead of giving Claude fabricated file names. 
