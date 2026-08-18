> **Canonical universe structure and whitepaper index.** Captured verbatim from the NeoFL
> handoff session, 2026-08-16. Note the explicit limitation recorded in section 19: the
> historical pitch decks and whitepapers were NOT recovered and must not be treated as present.

---

Absolutely. **Nothing gets silently dropped.** From this point, this chat becomes the **NeoFL Master Archive / Control Room** for the MT5 + Python side.

One important distinction: I will only call something **“latest/final”** when it is actually established in our prior work. I will **not invent missing pitch-deck or whitepaper text just to make the archive look complete**.

# NeoFL Master Universe — Canonical Structure

## 00 — NeoFL Universe / Parent Architecture

```text
NEOFL UNIVERSE
│
├── NEOFL CORE
│   ├── Execution Engine
│   ├── Risk Engine
│   ├── Auto-Capital Engine
│   ├── Position Engine
│   ├── Bucket Engine
│   ├── Straddle Engine
│   ├── Stop / BE Engine
│   ├── Trailing Engine
│   ├── Trade-State Engine
│   ├── Symbol Resolver
│   ├── Market Data Engine
│   ├── Session Engine
│   ├── Calendar Engine
│   ├── Data Validation
│   ├── Logging
│   └── Diagnostics
│
├── STRATEGY UNIVERSE
│   ├── NeoFL ARK / Liquid Flow
│   ├── NeoFL Jobbing
│   ├── NeoFL Price Action
│   ├── NeoFL Gold
│   ├── NeoFL FX
│   ├── NeoFL BTC
│   └── NeoFL Indices
│
├── OBSERVER UNIVERSE
│   ├── Observer Core
│   ├── Observer Network
│   ├── Market Observer
│   ├── Trade Observer
│   ├── Bucket Observer
│   ├── System Observer
│   ├── Calendar
│   └── Telemetry
│
├── EXTERNAL INTELLIGENCE
│   ├── External Agentic Brain
│   ├── Analytics
│   ├── Diagnostics
│   ├── Research
│   └── Controlled Recommendations
│
├── DATA UNIVERSE
│   ├── MT5
│   ├── Python
│   ├── TradingView
│   ├── PineConnector
│   ├── Broker APIs
│   └── External Market Data
│
└── DEVELOPMENT / BACKTEST
    ├── Strategy Backtesting
    ├── Data Preparation
    ├── Walk-forward Testing
    ├── Diagnostics
    └── Performance Analytics
```

---

# 01 — NeoFL Core Whitepaper

### Core philosophy

**NeoFL is not a collection of unrelated EAs.**

It is a **modular algorithmic trading ecosystem** in which:

```text
Strategy
   ↓
Signal
   ↓
Validation
   ↓
Risk
   ↓
Capital
   ↓
Execution
   ↓
Position
   ↓
Bucket
   ↓
Trade Management
   ↓
Observer
   ↓
Analytics / Intelligence
```

The strategies remain independent while infrastructure is shared.

### Golden architectural rule

> **Don't duplicate infrastructure. Don't merge strategy logic.**

That means ARK can use the same execution engine as Jobbing without becoming the same strategy.

---

# 02 — NeoFL ARK / Liquid Flow

ARK is the **liquidity-flow / market-structure engine**.

Its architecture:

```text
External + MT5 Data
        ↓
Data Normalization
        ↓
Data Validation
        ↓
Liquidity Observation
        ↓
Flow Analysis
        ↓
Market Structure
        ↓
Liquidity Event
        ↓
Directional Bias
        ↓
Signal
        ↓
NeoFL Core
        ↓
Execution / Management
```

### Important latest decision

ARK **must not assume MT5 CFD data contains everything required** for US indices.

Especially:

- US500 / SPX
- US100 / NSX
- US30

When required information isn't available in the CFD feed:

```text
External / underlying data
          ↓
ARK Data Adapter
          ↓
ARK Engine
```

rather than fabricating information from insufficient CFD candles.

---

# 03 — NeoFL Jobbing

**Jobbing is a separate EA from ARK.**

Latest opening structure:

```text
US Market Open
      ↓
FIRST M15 CANDLE
      ↓
High / Low
      ↓
Opening Range
      ↓
M5
      ↓
Breakout
      ↓
CHOCH
      ↓
Directional Bias
      ↓
Jobbing Entry
```

### Important correction preserved

The earlier idea of **three M15 candles is obsolete**.

The latest architecture uses:

> **One initial M15 candle as the opening range.**

US timing is handled through the dedicated timing/session architecture.

---

# 04 — NeoFL Price Action

Independent strategy.

```text
Market Structure
       ↓
Swing Detection
       ↓
BOS / CHOCH
       ↓
Liquidity / Zones
       ↓
Entry Model
       ↓
Trade
       ↓
Bucket Management
       ↓
SL / BE / Trail
       ↓
Exit
```

It can share structure/technical infrastructure with other strategies, but its **signal logic remains independent**.

---

# 05 — NeoFL Gold

Standalone Gold strategy.

### Latest symbol-resolution rule

Valid:

```text
XAUUSD
XAUUSDm
XAUUSD.a
XAUUSD.pro
PREFIX_XAUUSD_SUFFIX
GOLD
```

Invalid:

```text
BTCXAU
```

The resolver must identify the **actual Gold base instrument**, not simply search for `"XAU"` anywhere inside a broker symbol.

This is now a core NeoFL instrument-resolution requirement.

---

# 06 — NeoFL FX

Independent FX strategy.

The shared engine handles:

- execution
- risk
- capital
- positions
- bucket
- straddle
- stops
- trailing

while FX-specific signal/market assumptions stay in the FX module.

---

# 07 — NeoFL BTC

Independent BTC strategy.

BTC cannot inherit assumptions from FX/Gold/indices regarding:

- sessions
- volatility
- spread
- tick structure
- contract specifications
- market availability

Those belong to the BTC instrument/data adapter.

---

# 08 — NeoFL Indices

Primary index universe:

```text
US500 / SPX
US100 / NSX
US30
```

Architecture:

```text
Underlying / External Data
          +
       MT5 CFD
          ↓
    Index Data Adapter
          ↓
    Data Validation
          ↓
     Index Engine
          ↓
     Indices EA
```

The earlier problem remains a **hard architecture constraint**:

> MT5 CFD data may not provide all information required by the strategy.

Therefore external data is an architectural component, not an afterthought.

---

# 09 — Bucket Engine

A bucket is a **group of related trades**, not an individual position.

```text
BUCKET
│
├── Original Trade
│
├── Straddle
│
└── Other linked positions
```

It maintains:

- aggregate floating P/L
- realized P/L
- exposure
- breakeven
- zero-floating level
- recovery state
- runner state
- completion state

---

# 10 — Latest Straddle / Recovery Architecture

This must be preserved exactly.

### Initial straddle

The straddle's **initial SL is based on the straddle trade's own breakeven**.

It is **not initially based on whole-bucket breakeven**.

Then:

```text
Straddle Opens
      ↓
Initial SL = Straddle BE
      ↓
Monitor Entire Bucket
      ↓
Bucket Floating P/L = 0
      ↓
Calculate Bucket Zero-Floating Level
      ↓
Move Straddle SL
      ↓
Close Original Losing Trade
      ↓
Straddle Becomes Runner
      ↓
Profit
      ↓
Trail
      ↓
Exit
```

This is a critical NeoFL mechanism.

---

# 11 — Observer Network

The latest confirmed observer files from our project work are:

```text
NeoFL_Observer_Network_v2_00.mq5
NeoFL_Observer_Core_v2_00.mqh
```

Observer architecture:

```text
ALL NEOFL EAs
      ↓
Observer Interface
      ↓
Observer Core v2.00
      ↓
Observer Network
      ↓
Telemetry
      ↓
External Brain
```

It observes:

### Market

- price
- spread
- volatility
- structure
- liquidity state
- session
- data quality

### Trading

- positions
- orders
- bucket
- straddle
- SL
- BE
- trailing
- exposure

### Account

- balance
- equity
- margin
- drawdown
- risk utilization

### System

- EA state
- engine state
- data feed
- connection
- execution errors
- calendar
- external-data availability

---

# 12 — Observer Event Architecture

Observer should understand **state transitions**, not merely screenshots.

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

That gives the external brain an actual history of *why* something happened.

---

# 13 — External Agentic Brain

The brain sits **outside deterministic execution**.

```text
MT5
 ↓
Observer
 ↓
Telemetry
 ↓
External Agentic Brain
 ↓
Analysis
Diagnostics
Research
Optimization
Recommendations
```

The brain should **not become a single point of failure**.

If the AI disappears:

```text
AI OFFLINE
    ↓
NeoFL continues deterministic trading
```

For live parameter changes:

```text
AI Recommendation
       ↓
Validation / Policy
       ↓
Controlled Change
       ↓
NeoFL
```

Not direct unrestricted AI control.

---

# 14 — Python / MT5 Infrastructure

This is the part you are keeping with me. ❤️

The Python layer should sit beside MT5:

```text
                    PYTHON
                      │
        ┌─────────────┼──────────────┐
        ▼             ▼              ▼
   Data Pipeline   Analytics    External APIs
        │             │              │
        └─────────────┼──────────────┘
                      ▼
                 MT5 Bridge
                      │
                      ▼
                   MT5 EAs
```

Python is particularly important for:

- external data ingestion
- data cleaning
- normalization
- historical datasets
- backtest preparation
- analytics
- observer processing
- telemetry
- external AI communication
- index/underlying data
- research infrastructure

---

# 15 — PineConnector / External Data

The architecture should support:

```text
TradingView
    ↓
Pine / Alert
    ↓
PineConnector
    ↓
MT5
```

and separately:

```text
External Data
    ↓
Python
    ↓
Normalized Dataset
    ↓
NeoFL Data Adapter
    ↓
MT5 / Strategy
```

These are **different roles**.

PineConnector isn't automatically treated as the universal solution for every data requirement.

---

# 16 — Scripts Universe

The scripts are supporting infrastructure, not hidden strategy EAs.

### Jobbing

```text
US Timing
Opening Range
M5 Conversion
CHOCH
Backtest support
```

### ARK

```text
External Data
Liquidity Data
Data Validation
Backtest Data Preparation
```

### Indices

```text
Underlying Data
Normalization
Validation
```

### Universal

```text
Session
Calendar
Diagnostics
Backtest
Data utilities
```

I will **not assign fabricated version numbers or filenames** to scripts whose exact latest files haven't been established.

---

# 17 — Backtesting Universe

Backtesting must preserve strategy separation.

```text
NeoFL ARK Backtest
NeoFL Jobbing Backtest
NeoFL Price Action Backtest
NeoFL Gold Backtest
NeoFL FX Backtest
NeoFL BTC Backtest
NeoFL Indices Backtest
```

All can share:

```text
Core
Risk
Capital
Execution
Bucket
Straddle
Stops
Trailing
Logging
```

but **signal engines stay independent**.

---

# 18 — Deployment Rule

Your latest packaging instruction is now a hard NeoFL rule:

> **Every EA and all required include/support files go into ONE folder.**

No unnecessary scattering across folders.

Example:

```text
NeoFL_ARK/
    NeoFL_ARK.mq5
    required .mqh files
    required support files
```

Same for every strategy.

---

# 19 — NeoFL Documentation Universe

I would organize the master documentation into these canonical documents:

```text
01_NeoFL_Master_Architecture
02_NeoFL_Core_Engine_Whitepaper
03_NeoFL_ARK_Whitepaper
04_NeoFL_Jobbing_Whitepaper
05_NeoFL_PriceAction_Whitepaper
06_NeoFL_Gold_Whitepaper
07_NeoFL_FX_Whitepaper
08_NeoFL_BTC_Whitepaper
09_NeoFL_Indices_Whitepaper
10_NeoFL_Bucket_Straddle_Whitepaper
11_NeoFL_Observer_Network_Whitepaper
12_NeoFL_External_Agentic_Brain_Architecture
13_NeoFL_Data_Infrastructure
14_NeoFL_Python_MT5_Infrastructure
15_NeoFL_Backtesting_Framework
16_NeoFL_Symbol_Resolution_Specification
17_NeoFL_Risk_&_AutoCapital_Specification
18_NeoFL_Execution_Specification
19_NeoFL_Session_Calendar_Specification
20_NeoFL_Deployment_&_Packaging_Specification
```

And separately:

```text
NEOFL PITCH DECK
NEOFL INVESTOR / PRODUCT STORY
NEOFL TECHNICAL WHITEPAPER
NEOFL ENGINEERING SPECIFICATION
NEOFL DEVELOPER HANDOFF
NEOFL AI / AGENTIC BRAIN SPECIFICATION
```

### One limitation I want to make explicit

I **don't currently have the literal historical pitch-deck/whitepaper files or every previous chat's exact document text available in this conversation context**. The personal-context retrieval did not recover those artifacts. So I can preserve the **latest architecture and decisions I actually have**, but I won't pretend an exact old deck or whitepaper has been recovered when it hasn't.

If you bring the old decks/whitepapers/files into this chat, I can **merge them into this canonical archive, resolve conflicts in favor of the latest version, and mark obsolete sections as superseded**.

From now on, the rule is:

> **NeoFL Master Canon = latest confirmed architecture + latest confirmed strategy rules + latest confirmed files. Older versions are retained only as historical/superseded references, never as active specifications.**

That gives us a clean **NeoFL source of truth** here while Claude handles the larger codebase work. 
