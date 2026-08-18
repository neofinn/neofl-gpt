# NeoFL — Master Product & Engineering Specification (v1.0)

> ## ⚠️ SUPERSEDED — retained as historical reference
>
> Superseded on 2026-08-16 by `MASTER_ARCHITECTURE_v2.md` and its companion canon documents.
> Per `HANDOFF_DIRECTIVE.md`, the latest confirmed decision always supersedes an older one, and
> superseded work is preserved rather than deleted. **Do not implement from this document.**
>
> What changed, in short:
>
> | v1.0 (this document) | v2 canon (current) |
> |---|---|
> | Gold/XAUUSD platform | Multi-asset platform; Gold is one of seven strategies |
> | Two engines: Trend EA + ARK EA | Seven strategies over one shared Core Engine |
> | "Trend Engine" as a first-class engine | **No Trend Engine.** Its role is absorbed by Price Action and per-asset strategies |
> | ARK = gold liquidity/SMC engine | ARK = Liquid Flow, aimed at indices (US500/US100/US30) |
> | ARK/Trend coordinate via `ARK_STATE` lock | Strategies are independent EAs; no cross-strategy lock |
> | No bucket or straddle concept | **Bucket Engine + Straddle Engine are core**, with explicit state machines |
> | 12 phases, starting with repo scaffolding | 17 phases, starting with NeoFL Core |
>
> Still valid and carried forward: gold symbol resolution rules (reject `BTCXAU`), never fabricating
> market data, MQL5 as the execution boundary, AI never holding live order authority, human approval
> gates, and the AI engineering rules.
>
> Sections 8, 9, 12, and 13 (Trend Engine, Trend entry sequence, ARK/Trend coordination, continuous
> trading objective) describe an architecture that is **no longer the target**.

---

> Captured verbatim from the originating ChatGPT design session (share link provided 2026-08-16).
> Records what the product owner specified at that time. Do not edit to reflect implementation drift.

---

```text
NEOFL — MASTER PRODUCT & ENGINEERING SPECIFICATION
VERSION: 1.0
STATUS: DEVELOPMENT / ARCHITECTURE DEFINITION

============================================================
1. PROJECT OBJECTIVE
============================================================

We are building NeoFL, an AI-native algorithmic trading platform.

The initial target is GOLD / XAUUSD on MT5.

The system will eventually combine:

1. Trend Engine
2. ARK Engine
3. External market-data gateway
4. CME futures/order-flow data
5. TradingView supplemental signals
6. Economic calendar/news data
7. M1/M5/M15/M30 price-action analysis
8. Supply/Demand and Smart Money Concepts
9. External Agentic AI Brain
10. Historical-data replay/backtesting
11. Risk/execution engine
12. Monitoring and observability

The objective is NOT merely to create an EA.

The objective is to create an extensible trading platform in which AI agents can continuously develop, test, debug, analyze and improve the system under human approval.

============================================================
2. HUMAN VS AI RESPONSIBILITIES
============================================================

HUMANS:
- Product decisions
- Trading-rule decisions
- Strategy approval
- Code review
- Live deployment approval
- Live-trading authorization

AI:
- Architecture
- Coding
- Refactoring
- Testing
- Debugging
- Documentation
- Data engineering
- API integration
- Database design
- DevOps
- CI/CD
- Backtesting infrastructure
- Log analysis
- Error diagnosis
- Regression testing
- Monitoring
- Technical implementation

The AI must NOT silently alter trading logic because it believes a different strategy is more profitable.

If the AI identifies a strategy problem, it must:
1. Identify the problem
2. Provide evidence
3. Propose a change
4. Explain expected effect
5. Explain risk
6. Request product approval

Trading logic is controlled by the human product owner.

============================================================
3. AI DEVELOPMENT WORKFLOW
============================================================

Preferred development model:

USER + DEVELOPER
        |
        | Product decisions / code review
        v
AI DEVELOPMENT WORKFLOW
        |
        +-- Architecture
        +-- Coding
        +-- Testing
        +-- Debugging
        +-- Data Engineering
        +-- DevOps
        +-- Documentation
        +-- Backtesting
        |
        v
GitHub
        |
        v
Automated Tests
        |
        v
Human Code Review
        |
        v
Demo
        |
        v
Human Live Approval

Use Git as the source of truth.

Every meaningful change should be committed.

Every trading-behavior change must clearly state:
- What changed
- Why
- Expected effect
- Risk
- Tests performed
- Whether product approval is required

============================================================
4. INITIAL DEVELOPMENT ENVIRONMENT
============================================================

The user's primary development workstation is:

- MacBook Air
- Apple M5
- 16 GB RAM
- macOS Tahoe 26.5.2

The Mac is the AI/software-development workstation.

MT5 execution will eventually run on Windows VPS/RDP.

Initial development tools:

- Homebrew
- Git
- GitHub CLI
- Python 3.12+
- Node.js LTS
- Docker Desktop
- VS Code
- Claude Code
- Codex

Do not install or purchase unnecessary infrastructure before the architecture requires it.

Do not require the user to manually perform technical work that an AI agent can safely perform.

macOS administrator/security prompts must remain human-approved.

Never request or expose:
- Apple password
- GitHub password
- Broker password
- API secret
- Private SSH key
- Trading credentials

============================================================
5. REPOSITORY
============================================================

Create a private GitHub repository:

NeoFL

The repository should eventually contain:

NeoFL/
|
+-- docs/
|   +-- product/
|   +-- architecture/
|   +-- strategies/
|   +-- data/
|   +-- execution/
|   +-- testing/
|   +-- ai/
|
+-- strategies/
|   +-- trend/
|   +-- ark/
|
+-- mt5/
|   +-- TrendEA/
|   +-- ARKEA/
|   +-- DataBridge/
|
+-- external-data/
|   +-- CME/
|   +-- TradingView/
|   +-- Calendar/
|   +-- News/
|
+-- agentic-brain/
|
+-- backtesting/
|   +-- replay/
|   +-- historical-data/
|
+-- tests/
|
+-- infrastructure/
|
+-- scripts/
|
+-- monitoring/
|
+-- legacy/
|
+-- README.md

Never store secrets/API keys/broker credentials in Git.

============================================================
6. CURRENT SOURCE CODE
============================================================

Existing NeoFL source code exists in prior development conversations.

Important builds include:

- NeoFL GOLD 6.x combined Trend + ARK builds
- NeoFL GOLD 6.6 ARK pre-execution lock build
- NeoFL GOLD 7.0 Trend Engine
- NeoFL GOLD 7.0 ARK Engine
- Other NeoFL Indices/BTC/FX source may also exist

A legacy source file currently available is:

NeoFL_ARK_Backtest_v3_00.mq5

This legacy file must NOT be treated as the current production ARK architecture.

It is a reference/backtest artifact.

Preserve old source instead of overwriting it.

The AI must first inventory all available NeoFL .mq5 and .mqh files before redesigning anything.

============================================================
7. CORE ARCHITECTURE
============================================================

TREND and ARK must be separate EAs.

Do NOT return to a monolithic dual-engine EA unless explicitly requested.

Architecture:

                    XAUUSD
                       |
             +---------+---------+
             |                   |
         TREND EA             ARK EA
             |                   |
       M5 + M15 + M30      M15 ARK Event Engine
             |                   |
            M1                  M1
             |                   |
       Trend Trades          ARK Trades
             |                   |
             +---------+---------+
                       |
                Shared State
                       |
                    MT5

Trend and ARK may independently analyze the same market.

They must not continuously fight for control.

============================================================
8. TREND ENGINE
============================================================

Trend Engine is for short-term intraday trading.

Timeframe roles:

M5:
- Primary intraday trend identification
- Highest priority short-term trend timeframe
- Entry sequence

M15:
- Trend confirmation
- Confirms M5 directional bias
- NOT removed from Trend

M30:
- Trend survival / continuation evaluation
- Determines whether current trend should survive further
- Should not unnecessarily prevent valid short-term M5/M15 entries

M1:
- Execution timing
- Entry confirmation
- Trailing management

Trend identification should prioritize short-term intraday indicators.

Potential inputs include:
- EMA structure
- RSI
- MACD momentum
- ADX / trend strength
- candle direction
- price relative to moving averages
- momentum/displacement

Do not create an arbitrary slow "trend score" that prevents trading unnecessarily.

The engine should produce an actionable state such as:

TREND = BULLISH
TREND = BEARISH
TREND = NEUTRAL

and confidence/strength.

M5 + M15 must establish directional agreement.

M30 evaluates whether that direction is likely to survive.

============================================================
9. TREND ENTRY SEQUENCE
============================================================

Current desired sequence:

Two M5 candles in the same direction
        |
        v
Third M5 candle becomes execution candle
        |
        v
Split the third M5 candle into M1
        |
        v
M1 confirms entry
        |
        v
Enter in same direction
        |
        v
M1 trailing
        |
        v
M5 candle closes
        |
        v
Fourth M5 candle determines continuation
        |
        v
Continuation depends on whether trailing has reached profitable protection

The objective is short-term intraday execution rather than waiting for excessively slow confirmation.

Do not require excessive confirmation layers that cause the EA to remain idle.

============================================================
10. ARK ENGINE
============================================================

ARK is an independent event-based engine.

ARK should scan for high-quality market-structure/liquidity events.

Core concepts:

- Liquidity
- Liquidity sweeps
- BOS
- CHOCH
- Smart Money Concepts
- Supply/Demand
- Displacement
- Order-block style areas where appropriate
- Price-action events
- M15 event context
- M1 execution

Supply/Demand is explicitly considered an important ARK component.

ARK should be capable of identifying situations where supply/demand zones combine with liquidity events to produce high-quality setups.

ARK is NOT required to agree with Trend.

ARK can take an independent trade if its own conditions qualify.

============================================================
11. ARK TIMEFRAME
============================================================

M15 is important to ARK as its event/context timeframe.

ARK should not be confused with Trend's M15 confirmation role.

Trend M15:
- Trend confirmation

ARK M15:
- ARK event/context detection

Both can use M15 independently.

============================================================
12. ARK / TREND COORDINATION
============================================================

There must be NO strategy conflict engine.

Instead use a lightweight shared execution-state protocol.

ARK has priority when it is actually preparing to execute.

State model:

ARK_STATE:

0 = IDLE
1 = EVENT_DETECTED
2 = PRE_EXECUTION_LOCK
3 = POSITION_ACTIVE
4 = EXITING
5 = ERROR

ARK_DIRECTION:

-1 = SHORT
0 = NONE
+1 = LONG

Flow:

ARK detects qualified event
        |
        v
ARK_STATE = PRE_EXECUTION_LOCK
        |
        v
TREND blocks NEW entries
        |
        v
ARK sends order
        |
        +--> success -> ARK_STATE = POSITION_ACTIVE
        |
        +--> failure -> appropriate error/release state
        |
        v
ARK manages position
        |
        v
ARK position closes
        |
        v
ARK_STATE = IDLE
        |
        v
TREND can resume NEW entries

IMPORTANT:

Trend positions should not automatically be closed merely because ARK detects an event.

The lock primarily prevents a new Trend entry from racing an ARK entry.

ARK must reserve the execution slot BEFORE sending the order.

This solves the previous problem where Trend and ARK could both attempt execution at the same time.

============================================================
13. CONTINUOUS TRADING OBJECTIVE
============================================================

The system should not become permanently inactive because Trend and ARK disagree.

The desired behavior is:

- Trend continuously scans
- ARK continuously scans
- ARK may temporarily pause NEW Trend entries when executing
- Trend resumes after ARK is finished
- No permanent deadlock
- No unnecessary strategy conflict

The earlier desired target was approximately at least one opportunity every ~15 minutes under suitable market conditions.

This is an objective, not a guarantee.

Do NOT force trades merely to hit a trade-count target.

============================================================
14. SYMBOL HANDLING
============================================================

The system targets GOLD/XAUUSD.

Different brokers may use:

- XAUUSD
- XAUUSD.a
- XAUUSDm
- GOLD
- GOLDm
- other suffixes/extensions

These should be supported through configurable symbol mapping.

Do NOT accidentally trade unrelated instruments such as:

- BTCXAU
- crypto/gold synthetic pairs
- ETHXAU

unless explicitly configured.

External symbol:
GC/MGC/etc.

may map to:

XAUUSD / broker-specific Gold symbol.

Symbol mapping must be configuration-driven, not hard-coded into strategy logic.

============================================================
15. EXTERNAL DATA ARCHITECTURE
============================================================

Do NOT make Trend or ARK directly connect to every external API.

Use:

                 EXTERNAL DATA SOURCES
                         |
                 DATA GATEWAY
                         |
              NORMALIZATION LAYER
                         |
                  REAL-TIME STATE
                         |
                    MT5 BRIDGE
                         |
              +----------+----------+
              |                     |
          TREND EA               ARK EA

External sources may include:

1. CME futures/order-flow
2. TradingView
3. Economic calendar
4. News
5. Future data providers

============================================================
16. CME DATA
============================================================

CME Gold futures data is the primary external order-flow candidate for ARK.

Potential data:

- Bid
- Ask
- Last
- Trade size
- Volume
- Delta
- Bid depth
- Ask depth
- Order-book depth
- Imbalance
- Liquidity concentration
- Sweeps
- Timestamp

CME contract rollover must be handled.

Do not hard-code one futures contract forever.

Use reference/product information to manage:
- product code
- contract
- expiry
- rollover
- trading schedule

The exact CME subscription/API should be selected only after determining the precise fields required.

============================================================
17. TRADINGVIEW
============================================================

TradingView is supplemental.

Use it for:

- Pine calculations
- custom indicators
- alerts
- custom pattern detection
- supplemental confirmation

Do NOT assume TradingView is the primary raw order-book source.

TradingView webhooks should feed the external gateway.

Webhook payloads must be normalized.

============================================================
18. ECONOMIC CALENDAR / NEWS
============================================================

Use a proper API provider rather than website scraping.

Important events include:

- NFP
- CPI
- Core CPI
- FOMC
- Fed rate decision
- Fed speeches
- PCE
- GDP
- employment data
- Retail Sales
- ISM
- PPI
- Jobless Claims
- major PMI data
- other high-impact US events

Normalize:

- event ID
- event name
- country
- currency
- importance
- scheduled time
- forecast
- previous
- actual
- revision
- release status
- timestamp
- seconds to event
- seconds since release
- actual vs forecast

============================================================
19. DATA GATEWAY
============================================================

Build an independent external-data gateway.

Preferred initial technology:

Python

Potential components:

- FastAPI
- WebSockets
- asyncio
- Pydantic
- httpx
- pandas
- NumPy
- Redis
- PostgreSQL

Potential structure:

gateway/
    cme/
    tradingview/
    calendar/
    news/
    api/
    normalizers/

The gateway must:
- ingest external data
- validate
- timestamp
- normalize
- map symbols
- publish real-time state
- log events
- reconnect automatically
- reject stale/invalid data

============================================================
20. COMMON DATA SCHEMA
============================================================

All external data must be normalized to a common schema.

Example:

{
  "timestamp": 0,
  "source": "CME",
  "instrument": "GC",
  "mapped_symbol": "XAUUSD",
  "bid": 0,
  "ask": 0,
  "last": 0,
  "volume": 0,
  "delta": 0,
  "bid_depth": 0,
  "ask_depth": 0,
  "imbalance": 0,
  "liquidity_sweep": false,
  "event": null,
  "confidence": 0
}

Do not create source-specific strategy logic inside the EAs.

============================================================
21. MT5 DATA BRIDGE
============================================================

Build a dedicated:

NeoFL_MT5_DataBridge.mq5

Its responsibility:

External Gateway
    |
    v
MT5 Bridge
    |
    +-- validate
    +-- timestamp
    +-- symbol mapping
    +-- store state
    +-- expose normalized data
    |
    +--> Trend
    +--> ARK

The bridge must NOT make trading decisions.

MQL5 remains the final execution layer.

External AI/data systems must not bypass execution/risk controls.

============================================================
22. MT5 / PYTHON
============================================================

MT5 may communicate with Python through supported interfaces.

Python is responsible for:
- external data
- normalization
- feature processing
- databases
- agentic services

MQL5 is responsible for:
- market execution
- broker interaction
- final order handling
- SL/TP
- trailing
- execution safety

The architecture must support both live mode and backtest/replay mode.

============================================================
23. BACKTESTING
============================================================

External live APIs cannot simply be assumed available inside the MT5 Strategy Tester.

Therefore build a separate replay architecture:

Historical external data
        |
        v
Replay Engine
        |
        v
Normalized data stream
        |
        v
EA/backtest environment

The replay system should reproduce:
- CME/order-flow
- TradingView events
- news/calendar events
- normalized market state

This allows testing the same strategy logic with historical external information.

============================================================
24. DATABASE
============================================================

Eventually use:

PostgreSQL:
- historical data
- events
- trades
- logs
- strategy states
- external data

Redis:
- real-time state
- current market state
- ARK_STATE
- TREND_STATE
- news state
- CME state

Potential tables:

market_ticks
market_bars
orderbook_snapshots
orderbook_events
liquidity_events
ark_events
trend_states
news_events
calendar_events
tradingview_events
mt5_orders
mt5_positions
system_events

============================================================
25. AGENTIC BRAIN
============================================================

The Agentic Brain is NOT the first thing to build.

First build:
1. Reliable data
2. Normalization
3. MT5 bridge
4. Trend/ARK
5. Testing/replay

Then add the Agentic Brain.

Architecture:

Data
 |
 v
Feature Engine
 |
 v
Agentic Brain
 |
 v
Decision/Explanation
 |
 v
Risk Engine
 |
 v
EA
 |
 v
MT5

Initially the Agentic Brain should be advisory.

It may produce:

TREND = SHORT
CONFIDENCE = 87%

ARK = SHORT EVENT
CONFIDENCE = 94%

NEWS = CPI
TIME_TO_RELEASE = 48 seconds

LIQUIDITY = BUY-SIDE SWEEP

ACTION = ARK PRIORITY

Do NOT give an LLM unrestricted live order authority.

============================================================
26. SECURITY
============================================================

Requirements:

- HTTPS
- API authentication
- secret management
- environment variables
- request timestamps
- nonces/request IDs
- replay protection
- rate limiting
- firewall
- database authentication
- Redis authentication
- logging
- backup
- recovery procedures

Never store:
- broker password
- API secret
- exchange credential
- AI API key

in source code or GitHub.

============================================================
27. MONITORING
============================================================

Eventually create monitoring showing:

SYSTEM:
Gateway
CME
TradingView
Calendar
MT5
Trend
ARK

DATA:
CME latency
MT5 latency
last tick
last orderbook
data freshness

ENGINES:
Trend state
Trend confidence
ARK state
ARK confidence

NEWS:
next high-impact event
time to event
importance

============================================================
28. LOGGING
============================================================

Every important event should include:

- timestamp
- source
- symbol
- event
- input
- decision
- confidence
- order
- execution result
- latency
- error

Example:

04:30:00.124
CME
BUY-SIDE LIQUIDITY SWEEP

04:30:00.127
ARK
EVENT_SCORE = 8.7

04:30:00.129
ARK_STATE = PRE_EXECUTION

04:30:00.131
TREND = LOCKED

04:30:00.145
ORDER SENT

04:30:00.192
ORDER FILLED

============================================================
29. TESTING
============================================================

AI must automatically create and maintain:

Unit tests:
- symbol mapping
- parsers
- timestamps
- risk calculations
- ARK calculations
- Trend calculations

Integration tests:
- CME -> gateway
- TradingView -> gateway
- calendar -> gateway
- gateway -> MT5
- ARK -> shared state
- Trend -> shared state

Failure tests:
- CME disconnect
- TradingView failure
- internet failure
- MT5 disconnect
- API timeout
- stale data
- duplicate event
- invalid symbol
- spread explosion
- market closed

Regression tests must protect approved trading behavior.

============================================================
30. LIVE TRADING SAFETY
============================================================

Development and live trading must remain separate.

Initial objective:
PROVE EXECUTION, NOT PROFITABILITY.

The current testing account is primarily intended to determine:
- whether Trend generates orders
- whether ARK generates orders
- whether orders reach MT5
- whether broker accepts them
- whether SL/TP are placed
- whether trailing works
- whether ARK pre-execution locking works
- whether Trend resumes after ARK

Profitability will be evaluated separately on dedicated accounts.

No strategy change should be justified solely because the test account made/lost money.

============================================================
31. DEVELOPMENT PHASES
============================================================

PHASE 0:
Development workstation

PHASE 1:
GitHub + repository + AI instructions + source inventory

PHASE 2:
Formal Trend/ARK specifications

PHASE 3:
Standalone Trend + ARK architecture

PHASE 4:
MT5 bridge

PHASE 5:
External data gateway

PHASE 6:
CME + TradingView + calendar/news

PHASE 7:
Historical/replay engine

PHASE 8:
Agentic Brain

PHASE 9:
Automated research/testing

PHASE 10:
Demo execution

PHASE 11:
Human approval

PHASE 12:
Controlled live deployment

Do NOT skip directly to the Agentic Brain.

============================================================
32. AI ENGINEERING RULES
============================================================

The AI must:

- inspect existing code before rewriting
- preserve working behavior unless explicitly changing it
- maintain backward compatibility where practical
- write tests for new functionality
- never silently change product logic
- document architecture changes
- maintain changelog
- use Git branches for significant changes
- produce reviewable diffs
- identify risks
- run tests before declaring completion
- report failures honestly
- never claim code compiled if it was not actually compiled
- never claim a trade executed if it was not verified
- never fabricate market data
- never fabricate broker/API behavior

When uncertain, ask for clarification rather than inventing requirements.

============================================================
33. HUMAN APPROVAL GATES
============================================================

Human approval required for:

GATE 1:
Product behavior

GATE 2:
Code review

GATE 3:
Demo execution validation

GATE 4:
Live deployment

Everything else should be automated where safely possible.

============================================================
34. IMMEDIATE TASK
============================================================

DO NOT start by rewriting the trading system.

First:

1. Inspect the current NeoFL source inventory.
2. Identify all .mq5 and .mqh files available.
3. Classify them:
   - current
   - legacy
   - backtest
   - Trend
   - ARK
   - Indices
   - BTC
   - FX
4. Preserve legacy files.
5. Create the NeoFL repository structure.
6. Create architecture documentation.
7. Create AI development instructions.
8. Establish Git workflow.
9. Create tests/framework.
10. Only then begin implementing the new architecture.

The current legacy file:

NeoFL_ARK_Backtest_v3_00.mq5

must be preserved as legacy/reference and must not automatically be treated as the current ARK strategy.

============================================================
35. FINAL DEVELOPMENT PRINCIPLE
============================================================

NeoFL is not just an EA.

It is an AI-native trading platform.

The long-term system should be capable of:

- receiving multi-source market data
- understanding market structure
- detecting Trend
- detecting ARK events
- analyzing liquidity
- incorporating supply/demand
- incorporating CME order flow
- incorporating TradingView signals
- understanding macro events
- executing through MT5
- replaying historical data
- testing strategies automatically
- analyzing failures
- proposing improvements
- generating code
- testing code
- maintaining documentation
- continuously improving under human approval

The AI is the engineering workforce.

The human product owner controls what the system should do.

The developer validates implementation.

MT5 remains the execution boundary.

No AI component should bypass risk controls or human live-deployment approval.
```
