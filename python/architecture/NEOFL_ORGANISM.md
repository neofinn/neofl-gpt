# NeoFL Organism Architecture

NeoFL-GPT is designed as **one body, one soul, multiple specialist brains**.

## Body

The body is the shared Python platform:

- data fabric and data-quality controls
- shared market/world state
- event bus
- persistent memory
- tools and adapters
- risk controls
- recovery management
- execution
- monitoring

The body owns infrastructure and state. Specialist brains do not create their own competing infrastructure.

## Soul

The Soul is the central NeoFL intelligence/orchestrator. It coordinates the specialist brains and owns the reasoning loop:

`Observe -> Analyze -> Synthesize -> Decide -> Verify -> Act -> Observe outcome -> Learn`

The Soul does not bypass risk or execution authority.

## Specialist brains

Specialists independently analyze domains and return standardized evidence/theses. Initial specialists include:

- Liquid Flow ARK
- Wickless v4.11
- Godfather 3.0
- future liquidity, ICT/SMC, volume, statistical, session, price-action and other theories

A specialist advises. The Soul synthesizes.

## Memory

Supabase is the planned long-term memory layer. Memory is separated into:

- episodic: individual observations/decisions/trades
- semantic: generalized market/theory knowledge
- procedural: validated behaviors/rules

## Nervous system

A shared event bus and world-state model connect data, specialists, Soul, risk, learning and execution.

## Risk and execution authority

Risk is a hard gate. Execution is a controlled actuator. The Soul can request an action, but it cannot bypass a risk veto or invent an execution result.

## Learning

Every important decision is journaled. Outcomes are analyzed for decision quality, not just profit/loss. Improvements become hypotheses, are tested historically/walk-forward, and only validated candidates can be promoted.

## Constitution

The following boundaries are intended to be immutable safety rules:

1. Never bypass risk controls.
2. Never trade when required data is missing or stale.
3. Never fabricate market information.
4. Never equate confidence with probability without validation.
5. Never rewrite production behavior from a single outcome.
6. Preserve the decision and evidence history.
7. Reconcile broker state before acting.
8. Risk authority may veto the Soul.
9. Execution may not invent a trade.
10. Learning must be validated before promotion.
