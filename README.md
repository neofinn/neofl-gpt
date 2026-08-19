# NeoFL

A modular algorithmic trading platform for MetaTrader 5 with one shared Body/Execution Fabric and seven independent strategy EAs.

NeoFL is not a collection of unrelated EAs. It is one shared framework with independent strategy signal engines, a canonical Body for account/state/risk/execution infrastructure, an Observer Network, and an external AI layer that analyzes and recommends without becoming an unbounded broker-order authority.

> **Don't duplicate infrastructure. Don't merge strategy logic.**

## Canon

| Document | What it is |
|---|---|
| [`docs/product/HANDOFF_DIRECTIVE.md`](docs/product/HANDOFF_DIRECTIVE.md) | Highest authority for version conflicts. |
| [`docs/product/MASTER_ARCHITECTURE_v2.md`](docs/product/MASTER_ARCHITECTURE_v2.md) | Current architecture canon — strategy family and core. |
| [`docs/product/NEOFL_BODY_EXECUTION_FABRIC_v1.md`](docs/product/NEOFL_BODY_EXECUTION_FABRIC_v1.md) | **Canonical Body / Execution Fabric v1 addendum.** |
| [`docs/product/ENGINE_OBSERVER_SCRIPTS_LAYER.md`](docs/product/ENGINE_OBSERVER_SCRIPTS_LAYER.md) | Engine, observer, and scripts layers. |
| [`docs/product/MASTER_UNIVERSE_CANON.md`](docs/product/MASTER_UNIVERSE_CANON.md) | Universe structure and documentation index. |
| [`docs/architecture/SOURCE_INVENTORY.md`](docs/architecture/SOURCE_INVENTORY.md) | What every legacy file is — and what it isn't. |
| [`CLAUDE.md`](CLAUDE.md) | Rules for AI agents working here. |

`MASTER_SPEC_v1.0.md` is superseded and retained as historical reference only.

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
          +--------------+--------------+
          |                             |
          v                             v
   Independent Strategy EAs       Observer Network
   ARK / Jobbing / PA / Gold      telemetry / diagnostics
   FX / BTC / Indices                    |
          |                              v
          +-----------> OrderIntent <--- Agentic Brain
                              |
                              v
                    EXECUTION FABRIC
                              |
                 +------------+------------+
                 |                         |
                 v                         v
            MT5 Adapter               Future Adapters
                 |
                 v
           MQL5 execution
                 |
                 v
          ExecutionReport
                 |
                 +-------> Body State
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
      -> Body State / Observer
```

The MT5 adapter is `mt5/NeoFL_Executioner.mq5`. It authenticates the runtime account, publishes telemetry, claims canonical OrderIntent records, respects the explicit `execution_enabled` gate, and returns execution reports. It contains no strategy signal generation.

## Explicit execution gate

Every account has an execution gate. The default is locked.

```text
execution_enabled = false -> NO broker execution
execution_enabled = true  -> authenticated adapter may execute
```

This keeps the system fail-closed and prevents AI or gateway services from silently becoming direct execution authorities.

## Ground rules

- Trading logic is decided by the human product owner, never silently by an AI.
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
python/         data pipeline, analytics, external APIs, MT5 bridge
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
