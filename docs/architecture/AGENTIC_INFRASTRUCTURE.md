# NeoFL Parallel agentic infrastructure decision

## Decision

Use **LangGraph v1 as the durable orchestration runtime**, while keeping the existing NeoFL Soul/Body, Brain Registry, MCP client, OrderIntent and execution gateway as NeoFL-owned domain components.

Do not replace the existing Soul with a framework agent. The framework should orchestrate cognition; NeoFL remains authoritative over market state, intent identity, risk/straddle state, execution routing and post-fill reconciliation.

## Why LangGraph

NeoFL Parallel is a long-running, stateful trading agent rather than a conversational bot. It needs durable state, explicit transitions, resumable execution, parallel specialist work, replay/debugging and a persistent per-account cognition thread. LangGraph provides durable execution, checkpoint persistence, streaming, human-in-the-loop interrupts and state inspection/time-travel at the orchestration layer.

OpenAI Agents SDK remains a useful optional specialist runtime because it provides native MCP tool integration, handoffs, guardrails, sessions and tracing. It should be used inside a graph node/subagent only where those primitives materially help; it should not become the authority for execution.

Microsoft Agent Framework is a viable alternative, especially for Microsoft/.NET-heavy deployments, but adds unnecessary platform weight for the current Python NeoFL gateway. CrewAI is not the preferred core because NeoFL needs explicit state transitions and durable recovery rather than role-based crew abstraction.

## Target graph

INGEST → NORMALIZE → MCP_PULL → MARKET_STATE → SPECIALIST_FANOUT → SOUL_CROSS_EXAMINATION → THESIS → RISK/STRADDLE → ORDER_INTENT → EXECUTION_GATEWAY → MT5_FILL → POST_FILL_REASSESSMENT → MEMORY/CHECKPOINT → NEXT_CYCLE

Each account receives its own persistent graph thread. The global Brain routing selects MAIN/PARALLEL by default; an account override takes precedence.

## Non-negotiable boundaries

- MT5 never selects a Git branch.
- The Execution Gateway resolves Brain deployment.
- Brain/Soul owns execution authority and creates OrderIntent.
- The gateway/MT5 adapter executes the intent; it does not invent strategy.
- Risk/straddle state begins from confirmed execution/fill events.
- Every intent, execution report and reassessment carries account, Brain, branch and build identity.
- MCP is an evidence/tool source, not an execution authority.
- Replay and retries must be idempotent around side effects.

## Migration strategy

1. Keep the current custom agent loop as the compatibility path.
2. Introduce LangGraph behind `NeoFLAgentRuntime`.
3. First graph only wraps existing MCP pull, Soul cognition and post-fill reassessment.
4. Add durable PostgreSQL checkpointing and per-account thread IDs.
5. Add specialist fan-out as graph subgraphs.
6. Move OrderIntent lifecycle and execution-result reconciliation into explicit graph states.
7. Expose graph state/heartbeat to the Admin Dock.
8. Keep MAIN and the current execution gateway contract intact while PARALLEL is migrated incrementally.
