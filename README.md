# NeoFL

A modular algorithmic trading platform for MetaTrader 5 with one shared Body/Execution Fabric and seven independent strategy EAs.

NeoFL is not a collection of unrelated EAs. It is one shared framework with independent strategy signal engines, a canonical Body for account/state/risk/execution infrastructure, an Observer Network, and an agentic Brain that can acquire evidence through MCP, reason through the Soul, and feed decisions back through the Body.

> **Don't duplicate infrastructure. Don't merge strategy logic.**

## Parallel Agentic Build

This branch (`neoflgpt-parallel`) is the isolated development line for converting the existing Body into a self-hosted agentic runtime. `main` is not modified by this work.

The current build preserves the existing strategy/core/observer/execution features and adds a NeoFL-native MCP client plus a persistent agent runtime. ChatGPT/Codex remains a development/orchestration surface; it is not the permanent host of the trading Brain.

### Target runtime

```text
                 NEOFL SOUL
                     |
              NEOFL AGENT RUNTIME
          observe -> plan -> investigate
          -> specialists -> critic -> replan
          -> decide -> remember -> repeat
                     |
                MCP CLIENT
              /      |       \
             /       |        \
     MetaTrader MCP  other MCPs  Body/EA
             |                    |
             +-------- MT5 ------+
```

`python/neofl_gateway/mcp_client.py` is the transport/client layer. It handles MCP initialization, session state, tool discovery and tool calls without storing credentials.

`python/neofl_gateway/agent_runtime.py` is the persistent agent host. It discovers MCP capabilities, pulls bounded live observations, feeds them to the existing CognitiveSoul, and provides a repeatable observe/reason/reassess loop.

The first agentic stage is intentionally additive. It does not replace the existing specialist brains, risk, straddle, bucket, session, symbol, observer, Body, or execution fabric. Execution-capable MCP tools are excluded from the observation pass; the existing execution contract remains the route for broker actions while the Brain is being converted to autonomous tool use.

## Canon

| Document | What it is |
|---|---|
| [`docs/product/HANDOFF_DIRECTIVE.md`](docs/product/HANDOFF_DIRECTIVE.md) | Highest authority for version conflicts. |
| [`docs/product/MASTER_ARCHITECTURE_v2.md`](docs/product/MASTER_ARCHITECTURE_v2.md) | Current architecture canon — strategy family and core. |
| [`docs/product/NEOFL_BODY_EXECUTION_FABRIC_v1.md`](docs/product/NEOFL_BODY_EXECUTION_FABRIC_v1.md) | **Canonical Body / Execution Fabric v1 addendum.** |
| [`docs/product/ENGINE_OBSERVER_SCRIPTS_LAYER.md`](docs/product/ENGINE_OBSERVER_SCRIPTS_LAYER.md) | Engine, observer, and scripts layers. |
| [`docs/product/MASTER_UNIVERSE_CANON.md`](docs/product/MASTER_UNIVERSE_CANON.md) | Universe structure and documentation index. |
| [`docs/architecture/SOURCE_INVENTORY.md`](docs/architecture/SOURCE_INVENTORY.md) | What every legacy file is — and what it isn't. |
| [`docs/architecture/AGENTIC_BRAIN_V1.md`](docs/architecture/AGENTIC_BRAIN_V1.md) | Parallel agentic Brain conversion plan. |
| [`CLAUDE.md`](CLAUDE.md) | Rules for AI agents working here. |

`MASTER_SPEC_v1.0.md` is superseded and retained as historical reference only.

## Agentic Soul

The Python AI layer is now an agentic loop rather than a keyword-only router:

```text
GOAL
  -> PLAN
  -> OBSERVE
  -> SPECIALIST BRAINS
  -> CROSS-EXAMINE
  -> REPLAN when evidence is missing/conflicted
  -> RISK GATE
  -> DECIDE
  -> REMEMBER / LEARN
```

`python/neofl_gateway/agentic.py` provides the bounded planner, task graph, tool registry, working memory, specialist passes, critic/replanning cycle, and fail-closed decision policy. `python/neofl_gateway/soul.py` owns goals, memory, specialist delegation, criticism, replanning and learning.

`python/neofl_gateway/agent_runtime.py` now wraps that cognition in a long-lived runtime and `python/neofl_gateway/mcp_client.py` lets NeoFL itself act as the MCP client. `python/neofl_gateway/llm_reasoner.py` optionally connects final synthesis to the configured reasoning model.

The agent exposes `GET /agent/status` so the Control Room can see whether the LLM reasoner is enabled, which tools are registered, and whether execution authority is present. The agentic cognition layer does not silently become broker authority.

### Agentic evidence contract

- `OK` / `DATA_OK` and `DELAYED` / `DATA_DELAYED` can be analyzed.
- `UNKNOWN`, `UNAVAILABLE`, and `INVALID` evidence cannot be silently converted into facts.
- Contradictions trigger a bounded re-plan before the final verdict.
- The LLM is a reasoning/synthesis layer, not the broker authority.
- A final recommendation never directly places an order.
- MCP credentials are environment/secret configuration only; they are never committed to Git.

## Canonical architecture

```text
External Data / Broker / TradingView / APIs / Calendar
                         |
                         v
                  NEOFL DATA LAYER
          normalization · validation · resolver
                         |
                         v
                  NEOFL BODY / CORE
     state · risk · capital · bucket · straddle
     position · stops · trailing · session
                         |
             +-----------+-----------+
             |                       |
             v                       v
      AGENTIC BRAIN              Observer Network
      Soul + Runtime             telemetry / diagnostics
             |                       |
             v                       v
        MCP CLIENT              Body State / Events
             |
       MetaTrader MCP
             |
             v
        MT5 Body / EA
             |
             v
      EXECUTION FABRIC
             |
             v
           Broker
             |
             +-------> ExecutionReport -> Brain / Memory
```

## Seven independent strategies

**ARK / Liquid Flow** · **Jobbing** · **Price Action** · **Gold** · **FX** · **BTC** · **Indices**.

Each strategy owns its own signal rules while consuming shared Body infrastructure.

## Canonical execution contract

```text
Strategy / Brain
      -> OrderIntent
      -> Execution Fabric
      -> Platform Adapter
      -> MQL5 / platform execution
      -> ExecutionReport
      -> Body State / Observer / Brain memory
```

The MT5 adapter is `mt5/NeoFL_Executioner.mq5`. It authenticates the runtime account, publishes telemetry, claims canonical OrderIntent records, respects the explicit `execution_enabled` gate, and returns execution reports. It contains no strategy signal generation.

## Explicit execution gate

Every account has an execution gate. The default remains locked in the canonical repository contract; deployment configuration may explicitly enable it for an authorized account.

```text
execution_enabled = false -> NO broker execution
execution_enabled = true  -> authenticated adapter may execute
```

This keeps execution authority in the Body/MT5 adapter rather than in an arbitrary MCP tool or external chat surface.

## Ground rules

- Trading logic is decided by the product owner and the agentic Brain implementation; changes to strategy rules are explicit, never silently invented.
- MQL5/platform adapters are the actual execution authority.
- If the AI is offline, deterministic NeoFL infrastructure remains operational.
- Missing data means `DATA_UNAVAILABLE → NO TRADE` — never a fabricated value.
- Gold resolution is semantic: `GOLD` and XAUUSD variants valid, `BTCXAU` rejected.
- Every deployable EA ships as one self-contained folder.
- Binding credentials are never embedded in generated account URLs.
- No secrets in Git, ever — this repository is public.

## Layout

```text
CORE/           shared engines — risk, execution, bucket, straddle, symbol, session, ...
STRATEGIES/     ARK, JOBBING, PRICE_ACTION, GOLD, FX, BTC, INDICES
OBSERVER/       observer core/network, telemetry, market/trade/bucket/system observers
SCRIPTS/        timing, data, backtest, session, diagnostics utilities
DATA/           MT5, External, PineConnector, validation
EXTERNAL_BRAIN/ telemetry, event stream, analytics, recommendation interface
BACKTEST/       per-strategy backtests sharing the same core engine
DEPLOYMENTS/    self-contained per-EA packages
python/         agentic runtime, MCP client, data pipeline, analytics, external APIs, MT5 bridge
legacy/         preserved prior source — read-only reference

tests/          unit, integration, failure, regression
docs/           product canon and architecture
```

## Build and test

```bash
python3 -m unittest discover -s tests -t .
tools/mql5_compile.sh <dir-or-file.mq5>
```

MQL5 compilation is supported on the development Mac through the MetaEditor/Wine toolchain. Strategy Tester execution remains human-initiated because it requires a broker account configuration.

## Environment

Development and compilation on macOS (Apple Silicon). Live MT5 execution targets a Windows VPS/RDP host.

MCP configuration is supplied through environment/secret bindings. Example names are documented in `.mcp.json.example`:

```bash
export NEOFL_MARKETDATA_MCP_URL="https://www.metatrader.com/mcp"
export NEOFL_MARKETDATA_MCP_TOKEN="..."
```

Optional AI reasoning:

```bash
export OPENAI_API_KEY="..."
export NEOFL_REASONING_MODEL="gpt-5.6-luna"
```
