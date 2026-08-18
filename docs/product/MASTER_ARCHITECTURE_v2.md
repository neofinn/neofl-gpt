> **Current architecture canon.** Captured verbatim from the NeoFL handoff session, 2026-08-16.
> Supersedes `MASTER_SPEC_v1.0.md` where the two conflict. Records what the product owner
> specified; amendments belong in a dated addendum, not inline edits.

---

# NeoFL — Master Architecture Handoff to Claude

Below is the **current NeoFL architecture/source-of-truth** I would give Claude. The key principle is: **one common NeoFL framework, multiple independent strategy EAs, with shared infrastructure but no accidental strategy blending.**

---

## 1. Overall NeoFL Architecture

```text
                         ┌─────────────────────────┐
                         │     EXTERNAL DATA        │
                         │ TradingView / APIs       │
                         │ PineConnector            │
                         │ Broker / MT5 feeds       │
                         │ Calendar / News          │
                         └────────────┬────────────┘
                                      │
                                      ▼
┌────────────────────────────────────────────────────────────────┐
│                    NEOFL DATA ABSTRACTION LAYER                 │
│                                                                │
│  Symbol Resolver     Market Data      Session/Timing           │
│  OHLC / Tick Data    External Data    Calendar                │
│  Spread / Volume     Data Validation  Instrument Metadata      │
└────────────────────────────┬───────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────┐
│                    NEOFL CORE ENGINE                            │
│                                                                │
│  Signal Framework        Risk Engine                            │
│  Capital Engine          Position Manager                       │
│  Order Execution         Trade State Machine                    │
│  Bucket Manager          Straddle Manager                       │
│  SL/TP Manager           Trailing Engine                        │
│  Session Manager         Logging / Diagnostics                  │
└────────────────────────────┬───────────────────────────────────┘
                             │
              ┌──────────────┼────────────────┐
              │              │                │
              ▼              ▼                ▼
       ┌────────────┐ ┌────────────┐ ┌──────────────┐
       │   STRATEGY │ │  STRATEGY  │ │   STRATEGY   │
       │   MODULES  │ │   MODULES  │ │    MODULES   │
       └────────────┘ └────────────┘ └──────────────┘
              │              │                │
              ▼              ▼                ▼
          ARK EA        Jobbing EA       Price Action EA
          Gold EA       FX EA            BTC EA
          Indices EA    etc.
```

### Fundamental rule

**Strategy logic must never directly reinvent execution, risk, position, bucket, symbol, or capital-management code.**

The strategy produces:

```text
SIGNAL
   ↓
Signal Validator
   ↓
Risk / Capital Engine
   ↓
Order Intent
   ↓
Execution Engine
   ↓
Position State
   ↓
Trade Management
```

---

# 2. NeoFL Strategy Family

## A. NeoFL ARK / Liquid Flow

ARK is the **liquidity-flow / market-structure strategy**.

Core concepts:

```text
Market Data
    ↓
Liquidity Observation
    ↓
Flow Analysis
    ↓
Structure
    ↓
Liquidity Event
    ↓
Directional Bias
    ↓
Entry
    ↓
Bucket / Trade Management
```

ARK should be particularly suited to:

- SPX / US500
- NSX / US100
- US30
- other sufficiently liquid instruments

### Important ARK principle

ARK must **not assume that MT5 CFD data contains every data component required by the strategy**.

Where the broker's CFD feed cannot provide the required underlying-market information:

```text
MT5
 │
 ├── Local broker data
 │
 └── External data feed
          ↓
       ARK Data Adapter
          ↓
       ARK Engine
```

PineConnector/external feeds can therefore act as a **data bridge**, rather than forcing ARK to manufacture unavailable information from inadequate CFD candles.

---

# 3. NeoFL Jobbing

Jobbing remains **a separate EA from ARK**.

This is important for backtesting and strategy isolation.

### Current opening logic

At the relevant US market start:

```text
US Market Start
      ↓
First M15 Candle
      ↓
High / Low = Initial Range
      ↓
Range converted to M5 execution structure
      ↓
Breakout
      ↓
CHOCH confirmation
      ↓
Directional bias
      ↓
Jobbing entry
```

The previous concept of using three M15 candles has been replaced.

### Current rule

**The first M15 candle is the opening range.**

Not three candles.

### Direction

The breakout of the opening range establishes the initial directional context, with **CHOCH used to validate/confirm the direction**.

### Timing

Jobbing must have a dedicated **US-session timing module** rather than relying on arbitrary broker/server times.

---

# 4. NeoFL Price Action

Price Action is its own strategy module.

Its architecture should be:

```text
Market Structure
      ↓
Swing Detection
      ↓
BOS / CHOCH
      ↓
Liquidity / Zone Detection
      ↓
Entry Model
      ↓
Trade
      ↓
Bucket Management
      ↓
Trailing / Exit
```

The Price Action engine should be independent of ARK.

Shared infrastructure:

- candle engine
- swing engine
- structure engine
- risk engine
- execution engine

But **signal rules remain strategy-specific**.

---

# 5. NeoFL Gold

Gold is a standalone strategy/EA.

## Symbol resolution is critical.

Valid instruments include:

```text
XAUUSD
XAUUSDm
XAUUSD.a
XAUUSD.pro
PREFIX_XAUUSD_SUFFIX
GOLD
```

The resolver should identify the **base Gold instrument**, rather than requiring an exact symbol name.

### Validity concept

```text
Broker Symbol
      ↓
Normalize
      ↓
Remove broker prefix/suffix
      ↓
Check Gold aliases
      ↓
VALID GOLD
```

`GOLD` must also be recognized directly.

### Must reject

```text
BTCXAU
```

because it is not the Gold instrument merely because the string contains `XAU`.

The resolver therefore needs **semantic/base-symbol matching**, not naïve substring matching.

---

# 6. NeoFL FX

FX remains a separate asset-specific EA.

Architecture:

```text
FX Symbol
   ↓
FX Data Adapter
   ↓
FX Market Conditions
   ↓
NeoFL FX Signal Engine
   ↓
Risk Engine
   ↓
Execution
   ↓
Trade Management
```

FX-specific parameters should live inside the FX strategy configuration rather than being hard-coded into the NeoFL core.

---

# 7. NeoFL BTC

BTC is also a separate strategy/EA.

```text
BTC Market Data
      ↓
Crypto Data Adapter
      ↓
BTC Strategy
      ↓
Risk
      ↓
Execution
      ↓
Bucket / Straddle / Trailing
```

BTC should not inherit FX or Gold assumptions concerning:

- session structure
- spread
- volatility
- tick value
- contract specification
- market hours

Those must come from the instrument adapter.

---

# 8. NeoFL Indices

Indices require a dedicated data abstraction.

Primary targets discussed:

```text
US500 / SPX
US100 / NSX
US30
```

The critical issue is that **CFD data is not necessarily sufficient for all calculations**.

Therefore:

```text
                    INDEX DATA
                       │
           ┌───────────┴───────────┐
           ▼                       ▼
       MT5 CFD Feed          External Feed
           │                       │
           └───────────┬───────────┘
                       ▼
               Index Data Adapter
                       ↓
                Normalized Data
                       ↓
                Strategy Engine
```

The strategy must know the **data quality/source** being used.

It should never silently pretend that missing underlying data is valid.

---

# 9. Universal NeoFL Risk Engine

Every strategy feeds into the same risk architecture.

```text
Strategy Signal
      ↓
Risk Validation
      ↓
Account State
      ↓
Capital Allocation
      ↓
Position Size
      ↓
Maximum Exposure
      ↓
Order
```

The risk engine handles:

- account equity
- balance
- risk percentage
- lot calculation
- contract size
- tick value
- tick size
- SL distance
- maximum exposure
- maximum simultaneous trades
- daily limits
- strategy limits
- drawdown controls

The **strategy should request risk**, not calculate broker-specific position sizing itself.

---

# 10. Universal Trade State Machine

Every trade should have an explicit state.

```text
CREATED
   ↓
PENDING
   ↓
OPEN
   ↓
MANAGED
   ↓
BREAKEVEN
   ↓
TRAILING
   ↓
CLOSING
   ↓
CLOSED
```

For special recovery/straddle trades:

```text
ORIGINAL TRADE
       ↓
LOSS / ADVERSE MOVE
       ↓
STRADDLE ACTIVATED
       ↓
STRADDLE INITIAL SL
       ↓
BUCKET MANAGEMENT
       ↓
BUCKET FLOATING = 0
       ↓
MOVE STRADDLE SL
       ↓
CLOSE ORIGINAL LOSING TRADE
       ↓
STRADDLE BECOMES PROFIT RUNNER
       ↓
TRAIL
       ↓
EXIT
```

---

# 11. Bucket Engine

The bucket is a **portfolio of related positions**, not merely one position.

Example:

```text
BUCKET #001

Original Trade
      +
Straddle Trade
      +
Other linked positions
      ↓
Aggregate Floating P/L
```

The bucket manager tracks:

- bucket ID
- strategy
- direction
- positions
- entry prices
- volume
- realized P/L
- floating P/L
- aggregate exposure
- bucket breakeven
- bucket zero-floating level
- recovery status
- completion status

---

# 12. Latest Straddle Architecture

This is one of the most important pieces to preserve accurately.

### Initial condition

The straddle trade is opened with its **initial SL at the breakeven point of the straddle trade itself**.

It is **not initially placed at the whole bucket's breakeven**.

Then:

```text
Straddle opened
      ↓
Initial SL = Straddle Trade BE
      ↓
Monitor whole bucket
      ↓
Bucket floating P/L reaches zero
      ↓
Calculate bucket zero-floating price
      ↓
Move Straddle SL to that point
      ↓
Close original losing trade
      ↓
Straddle remains
      ↓
Profit develops
      ↓
Trail
```

This distinction must be explicit in Claude's implementation.

### Conceptual example

```text
Original Trade: LOSS
Straddle Trade: PROFIT

Bucket P/L:
-150
-100
 -50
   0  ← trigger
 +25
 +50
```

At bucket `0`:

```text
Original losing trade → CLOSE

Straddle:
SL → bucket zero-floating level
      ↓
continues toward profit
      ↓
trailing begins
```

The straddle is therefore transformed from a **recovery hedge** into the **profit runner**.

---

# 13. Straddle State Machine

Claude should implement this explicitly rather than using scattered boolean flags.

```text
STRADDLE_NONE
      ↓
STRADDLE_PENDING
      ↓
STRADDLE_OPEN
      ↓
STRADDLE_RECOVERY
      ↓
BUCKET_ZERO_REACHED
      ↓
STRADDLE_PROTECTED
      ↓
ORIGINAL_CLOSED
      ↓
STRADDLE_RUNNER
      ↓
TRAILING
      ↓
STRADDLE_CLOSED
```

This prevents contradictory conditions such as:

- closing the original trade too early
- moving SL prematurely
- reopening the straddle repeatedly
- treating a closed straddle as active
- recalculating the zero-floating level incorrectly

---

# 14. External Observer Network

The Observer Network should be treated as a **monitoring/intelligence layer**, not as a replacement for deterministic execution.

```text
MT5
 │
 ├── Market State
 ├── Trades
 ├── Errors
 ├── Performance
 └── Strategy State
        ↓
NeoFL Observer
        ↓
External Agentic Brain
        ↓
Analysis / Diagnostics / Recommendations
```

The core EA must remain operational even if the external AI is unavailable.

### Hard principle

```text
AI unavailable
     ↓
NeoFL continues deterministic operation
```

AI should not become a single point of failure for trade execution.

---

# 15. External Agentic Brain

The external brain can eventually handle:

- strategy diagnostics
- anomaly detection
- performance analysis
- market-regime classification
- parameter recommendations
- log analysis
- backtest analysis
- cross-strategy correlation
- risk warnings
- development assistance

But the architecture should distinguish:

### Deterministic layer

```text
MT5
Risk
Execution
Stops
Position management
Bucket management
```

### Intelligence layer

```text
AI
Analytics
Research
Optimization
Observations
Recommendations
```

The AI should **not arbitrarily modify live trading logic** without a controlled configuration/approval mechanism.

---

# 16. Common NeoFL Modules

Recommended shared architecture:

```text
NeoFL_Core.mqh

NeoFL_Config.mqh
NeoFL_SymbolResolver.mqh
NeoFL_MarketData.mqh
NeoFL_Session.mqh
NeoFL_Calendar.mqh

NeoFL_Signal.mqh
NeoFL_Risk.mqh
NeoFL_Capital.mqh
NeoFL_Position.mqh
NeoFL_Execution.mqh

NeoFL_Bucket.mqh
NeoFL_Straddle.mqh
NeoFL_StopManager.mqh
NeoFL_Trailing.mqh

NeoFL_Logger.mqh
NeoFL_Diagnostics.mqh
NeoFL_Observer.mqh
NeoFL_ExternalData.mqh
```

Then strategy-specific components:

```text
ARK/
    NeoFL_ARK_Signal.mqh
    NeoFL_ARK_Flow.mqh
    NeoFL_ARK_Liquidity.mqh

JOBBING/
    NeoFL_Jobbing_Signal.mqh
    NeoFL_Jobbing_Range.mqh
    NeoFL_Jobbing_CHOCH.mqh

PRICE_ACTION/
    NeoFL_PA_Signal.mqh
    NeoFL_PA_Structure.mqh

GOLD/
    NeoFL_Gold_Signal.mqh

FX/
    NeoFL_FX_Signal.mqh

BTC/
    NeoFL_BTC_Signal.mqh

INDICES/
    NeoFL_Indices_Signal.mqh
```

---

# 17. EA Layer

Each EA becomes very thin.

### Example

```text
NeoFL_ARK.mq5
        ↓
NeoFL Core
        ↓
ARK Strategy
        ↓
Signal
        ↓
Risk
        ↓
Execution
```

Same architecture for:

```text
NeoFL_Jobbing.mq5
NeoFL_PriceAction.mq5
NeoFL_Gold.mq5
NeoFL_FX.mq5
NeoFL_BTC.mq5
NeoFL_Indices.mq5
```

This is preferable to having thousands of lines of duplicated execution code inside every EA.

---

# 18. Backtesting Architecture

**ARK and Jobbing must remain separate EAs for backtesting.**

For example:

```text
Backtest
 ├── NeoFL_ARK.mq5
 │      └── ARK strategy
 │
 └── NeoFL_Jobbing.mq5
        └── Jobbing strategy
```

They may share:

```text
Core
Risk
Execution
Bucket
Straddle
Logging
```

but their signal engines remain independent.

---

# 19. Single-Folder Packaging Rule

This is now a hard packaging rule for NeoFL.

Each deliverable should be self-contained:

```text
NeoFL_ARK/
    NeoFL_ARK.mq5
    NeoFL_Core.mqh
    NeoFL_Config.mqh
    NeoFL_Risk.mqh
    ...
```

Likewise:

```text
NeoFL_Jobbing/
NeoFL_PriceAction/
NeoFL_Gold/
NeoFL_FX/
NeoFL_BTC/
NeoFL_Indices/
```

**EA + all required include files/support files must be in one folder.**

No unnecessary dependency hunt across unrelated folders.

---

# 20. Configuration Architecture

Strategy parameters should be separated into:

### Core parameters

```text
Risk %
Capital mode
Magic number
Execution settings
Maximum spread
Trading permissions
```

### Strategy parameters

```text
ARK parameters
Jobbing parameters
Price Action parameters
Gold parameters
FX parameters
BTC parameters
Indices parameters
```

### Asset parameters

```text
Contract specification
Tick size
Tick value
Point size
Trading session
Symbol aliases
```

### Management parameters

```text
Bucket rules
Straddle rules
BE rules
Trailing rules
Daily limits
Drawdown limits
```

This prevents the classic problem where changing one strategy accidentally changes another.

---

# 21. Symbol Resolver

The resolver should be universal:

```text
Broker Symbol
      ↓
Normalize
      ↓
Identify asset
      ↓
Identify base symbol
      ↓
Validate strategy compatibility
      ↓
Return InstrumentDescriptor
```

Example:

```text
XAUUSD       → GOLD
XAUUSDm      → GOLD
XAUUSD.pro   → GOLD
GOLD         → GOLD
BTCXAU       → INVALID GOLD
```

Then:

```text
InstrumentDescriptor
{
    asset_class
    base_symbol
    broker_symbol
    tick_size
    tick_value
    point
    contract_size
    digits
    trading_sessions
}
```

---

# 22. Calendar / Session Engine

Calendar should be a **shared service**, not duplicated in every EA.

```text
Calendar
   +
Trading Sessions
   +
Market Holidays
   +
Strategy Session Rules
        ↓
Trading Permission
```

Jobbing's US timing is one consumer.

Indices can have their own session configuration.

Gold/FX/BTC can have their own trading windows.

---

# 23. Data Quality Layer

Every external/internal data source should receive a quality state:

```text
DATA_OK
DATA_DELAYED
DATA_INCOMPLETE
DATA_UNAVAILABLE
DATA_INVALID
```

Then the strategy decides whether it can trade.

For example:

```text
ARK requires external liquidity data
             ↓
DATA_UNAVAILABLE
             ↓
NO SIGNAL / NO TRADE
```

Not:

```text
Missing data
   ↓
Guess
   ↓
Trade
```

---

# 24. NeoFL Development Philosophy

The entire project should follow:

```text
                    NEOFL
                      │
             ┌────────┴────────┐
             │                 │
       SHARED ENGINE       STRATEGIES
             │                 │
     ┌───────┼───────┐    ┌────┼─────┐
     │       │       │    │    │     │
   Risk   Execution Bucket ARK Jobbing PA
     │       │       │         │
     └───────┼───────┘         │
             │                 │
        Trade State       Asset-specific
        Management          adaptations
```

### The golden rule

**Don't duplicate infrastructure. Don't merge strategy logic.**

---

# 25. Claude's Implementation Order

I would have Claude build it in this sequence:

```text
PHASE 1
NeoFL Core
        ↓
PHASE 2
Symbol / Instrument Resolver
        ↓
PHASE 3
Market Data + Session + Calendar
        ↓
PHASE 4
Risk + Capital Engine
        ↓
PHASE 5
Execution + Position Manager
        ↓
PHASE 6
Bucket Engine
        ↓
PHASE 7
Straddle Engine
        ↓
PHASE 8
Stop / BE / Trailing Engine
        ↓
PHASE 9
Observer / Logging
        ↓
PHASE 10
ARK
        ↓
PHASE 11
Jobbing
        ↓
PHASE 12
Price Action
        ↓
PHASE 13
Gold
        ↓
PHASE 14
FX
        ↓
PHASE 15
BTC
        ↓
PHASE 16
Indices
        ↓
PHASE 17
External Data / Agentic Brain
```

This order is important because **the strategy EAs should be consumers of a stable trading engine**, not each become their own mini-framework.

---

## 26. The Most Important Rules Claude Must Not Break

**1. ARK ≠ Jobbing.**  
Separate EAs and separate strategy logic.

**2. Strategy ≠ execution.**  
Strategies generate signals; Core executes them.

**3. Bucket ≠ individual trade.**  
Bucket P/L and trade P/L are different concepts.

**4. Straddle initial SL ≠ bucket BE.**  
Initial SL is based on the **straddle trade's own breakeven**.

**5. Bucket zero-floating triggers the transition.**  
At bucket zero floating, move the straddle SL to the appropriate zero-floating level and close the original losing trade.

**6. The surviving straddle becomes the runner.**

**7. Gold symbol matching must recognize `GOLD` and XAUUSD broker variants but reject `BTCXAU`.**

**8. Missing market data must never be silently fabricated.**

**9. External AI must not be a single point of failure.**

**10. Every EA package contains the EA and its required `.mqh` files in the same folder.**

**11. Asset-specific assumptions belong in asset adapters/configuration, not the Core.**

**12. Backtesting and live execution use the same deterministic strategy engine wherever possible.**

---

### Final Claude project structure

```text
NEOFL/
│
├── CORE/
│   ├── Engine
│   ├── Risk
│   ├── Capital
│   ├── Execution
│   ├── Position
│   ├── Bucket
│   ├── Straddle
│   ├── Stops
│   ├── Trailing
│   ├── Symbol
│   ├── MarketData
│   ├── Session
│   ├── Calendar
│   ├── Logging
│   └── Diagnostics
│
├── STRATEGIES/
│   ├── ARK
│   ├── JOBBING
│   ├── PRICE_ACTION
│   ├── GOLD
│   ├── FX
│   ├── BTC
│   └── INDICES
│
├── DATA/
│   ├── MT5
│   ├── External
│   ├── PineConnector
│   └── DataValidation
│
├── OBSERVER/
│   ├── ObserverNetwork
│   ├── Telemetry
│   └── AgenticBrain
│
├── BACKTEST/
│   ├── ARK
│   ├── JOBBING
│   ├── PRICE_ACTION
│   ├── GOLD
│   ├── FX
│   ├── BTC
│   └── INDICES
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

This is the architecture I would use as the **baseline NeoFL v5-era rebuild specification for Claude**, with the existing strategy decisions preserved rather than starting the project from scratch. 
