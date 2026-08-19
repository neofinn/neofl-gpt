# NeoFL Agentic Brain v1 — Parallel Build

## Purpose

Convert the existing parallel Body into a self-hosted agent runtime without removing the features already present in the build and without touching `main`.

The Body remains the runtime/execution fabric. The new Agent Runtime sits inside the Body process and hosts the Soul, planner, specialist council, critic/replanner, memory hooks and MCP client.

## Preserve first

The conversion must retain the existing:

- seven strategy families: ARK, Jobbing, Price Action, Gold, FX, BTC and Indices;
- shared Body/Core infrastructure;
- risk engine;
- Straddle/Bucket recovery logic;
- session/calendar logic;
- symbol resolution and Gold semantic validation;
- position/state models;
- execution fabric and MT5 adapter;
- Observer Network and telemetry;
- external event ingestion and evidence-quality rules;
- account-aware trade/request/decision records;
- Soul memory, specialist routing, critic and bounded replanning;
- existing MCP/MetaTrader configuration by secret binding;
- parallel-only development boundary.

No feature is deleted merely to make the agent runtime simpler.

## Roles

### Soul

The Soul is the cognitive authority. It owns:

1. goals;
2. evidence admission;
3. working/episodic memory;
4. specialist delegation;
5. criticism;
6. replanning;
7. final cognitive verdict.

### Agent Runtime

`python/neofl_gateway/agent_runtime.py` provides the persistent control loop:

```text
PERCEIVE
  -> PLAN
  -> SELECT / DISCOVER TOOLS
  -> OBSERVE
  -> SPECIALISTS
  -> CROSS-EXAMINE
  -> REPLAN if required
  -> SYNTHESIZE
  -> DECIDE
  -> REMEMBER
  -> OBSERVE AGAIN
```

The runtime owns lifecycle and scheduling, not strategy rules.

### MCP Client

`python/neofl_gateway/mcp_client.py` makes NeoFL itself the MCP client.

It is responsible for:

- authenticated HTTP transport;
- MCP initialization;
- session handling;
- tool discovery;
- tool invocation;
- response decoding for JSON or SSE;
- transport errors;
- status/introspection.

Credentials come only from environment/secret configuration.

### MT5 EA

The EA remains the fast terminal-side Body connection. It is responsible for native MT5 events, market/account telemetry, execution and execution reports.

### Script layer

Scripts remain appropriate for logging, diagnostics, reconciliation and audit work. They are not the persistent Brain connection.

## MCP tool policy

The agent runtime should discover capabilities dynamically instead of hard-coding one broker schema.

Observation calls are selected by capability hints and are read-only by default. Execution-capable tools are not called during passive observation.

The next phase adds explicit cognitive tool selection:

```text
Soul chooses tool
  -> policy checks tool capability
  -> MCP call
  -> evidence enters Soul
  -> result changes plan
```

The execution path remains explicit:

```text
Brain decision
  -> OrderIntent
  -> Body authority
  -> MT5 adapter
  -> broker
  -> ExecutionReport
  -> Soul observation
  -> reassessment
```

The MCP server must not become an accidental second execution authority.

## Agentic behaviour we want

The Brain must be able to maintain a goal and continue working without a new human prompt. For a live market goal, for example:

```text
Goal: Understand Gold and trade the active session.

1. Observe current Gold state.
2. Identify what information is missing.
3. Select tools to acquire that information.
4. Ask relevant specialist brains.
5. Form competing hypotheses.
6. Cross-examine them.
7. Re-plan when evidence conflicts or is incomplete.
8. Run risk/Straddle analysis against current exposure.
9. Produce an OrderIntent when the thesis is sufficiently supported.
10. Observe the fill and resulting P&L.
11. Reassess the thesis after execution.
12. Continue until the goal is complete or the market state invalidates it.
```

This is different from a keyword router because the next action is selected from the current state of the investigation.

## Memory

Memory is not a transcript dump. Store structured episodes:

- goal;
- market context;
- evidence used;
- hypotheses considered;
- specialist outputs;
- contradictions;
- decision;
- execution result;
- P&L outcome;
- lesson/invalidator.

Future cycles can retrieve these records as evidence, but stale memory must never override fresh market state.

## Execution and learning

After an execution report, the report becomes a new observation. The Brain must be able to distinguish:

- intended action;
- accepted order;
- broker execution result;
- realized P&L;
- unrealized P&L;
- rejection reason;
- slippage/latency;
- post-trade market state.

The Brain then reassesses rather than assuming the original thesis was correct.

## Rollout sequence

### Phase 1 — Native MCP host/client

- [x] Add MCP transport/client.
- [x] Initialize and discover tools.
- [x] Pull bounded live observations.
- [x] Feed observations into existing Soul.
- [x] Keep secrets outside Git.

### Phase 2 — Autonomous tool selection

- Add a tool capability model.
- Let Soul select the next MCP tool based on missing evidence.
- Add tool-result provenance to observations.
- Add bounded per-cycle tool budgets.

### Phase 3 — Agentic execution

- Convert cognitive verdicts into structured OrderIntent candidates.
- Send candidates through existing Body authority and risk/Straddle engines.
- Receive MT5 execution reports.
- Re-enter the result into Soul.

### Phase 4 — Continuous market agent

- Persistent market observation.
- Goal lifecycle.
- Session awareness.
- Position-aware planning.
- Re-entry/reassessment.
- Structured long-term learning.

## Non-negotiables

- `main` remains untouched.
- Existing strategy/core features are preserved.
- No secrets are committed.
- No fabricated market evidence.
- MCP is a tool interface, not the cognitive authority.
- The Soul remains the cognitive authority.
- The MT5 Body/adapter remains the physical execution path.
- The Brain must observe execution outcomes and reassess them.
