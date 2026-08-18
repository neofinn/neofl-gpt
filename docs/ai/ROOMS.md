# Working rooms

NeoFL is developed across several sessions rather than one. This file says which room owns what, so
two sessions don't edit the same thing from different assumptions.

## The rooms

The universe divides by **language and authority** first (D-007), then by strategy.

| Room | Open a session in | Owns | May place orders? |
|---|---|---|---|
| **Infrastructure + MT5** | repository root | `CORE/`, `OBSERVER/`, `SCRIPTS/`, `DEPLOYMENTS/`, `BACKTEST/`, tooling, canon, tests | **yes — the only one** |
| **Python** | `python/` | `python/`, `DATA/`, `EXTERNAL_BRAIN/` | **never** (D-001) |
| ARK · Jobbing · Price Action · Gold · FX · BTC · Indices | `STRATEGIES/<NAME>/` | that strategy's signal logic only | via Core, from the MT5 room |

Each directory carries its own `CLAUDE.md`, loaded automatically when a session opens there.

### The dividing test

**Does it need to be inside the terminal at the moment a decision becomes an order?**

- **Yes → MT5 room.** Execution, live position management, anything on the tick path.
- **No → Python room.** Analysis, research, external data, telemetry — anything that can be
  late without being wrong.

### Different standards of proof

This is the substantive reason for the split, not tidiness.

MQL5 runs on the tick path with money behind it. A mistake is an order. It must compile, and
it is only really proven by demo execution.

Python is analytical. A mistake is a wrong conclusion — cheaper, but more insidious, because
a wrong conclusion can be believed for months. It is proven by tests against known-answer
cases.

Separate rooms stop either borrowing the other's standard. A Python session must not conclude
"it compiles" is enough; an MQL5 session must not conclude "the unit test passes" means it
will execute.

### The shared contract

```
CORE/NeoFL_DataValidation/NeoFL_DataQuality.mqh   <->   python/neofl_gateway/schema.py
```

Quality states, verdicts and the provenance record must mean the same thing on both sides, or
MQL5 will act on data Python already judged unusable. Either room may propose a change;
**neither changes it alone.**

## Why the split

The canon's golden rule is *don't duplicate infrastructure, don't merge strategy logic*. Rooms
enforce the second half structurally: a session scoped to one strategy is far less likely to reach
into another's signal engine, or to "fix" one EA by changing a shared engine six others depend on.

## The rule that keeps it safe

**Shared code changes in the infrastructure room. Only there.**

A strategy room that needs something from CORE — a new engine, a changed signature, a bug fix —
does not edit CORE. It writes down what it needs and hands it to the infrastructure room. That room
can see every consumer; a strategy room cannot.

If a strategy room finds itself editing outside its own directory, that is the signal it is doing
infrastructure work in the wrong place.

## Handing work between rooms

Sessions can message each other directly. From any room:

> "Send this to the infrastructure session: Jobbing needs a CHOCH detector in CORE — the legacy
> `RequireM5CHoCH` input was never implemented."

The message lands as a user turn in the target session, labelled with its origin. Use it for handoffs
and findings, not to run work remotely.

## Starting a strategy room

Open a new Claude Code session with its working directory set to that strategy folder, for example:

```bash
cd ~/Desktop/NeoFL/STRATEGIES/JOBBING
```

Then start there. The room's `CLAUDE.md` loads automatically. Worth saying in the first message which
strategy it is and what you want built, so the session's title reflects it.

## Build order still applies

Strategies are consumers of a stable engine. Steps 1–9 are Core, Observer, and Logging; strategies
begin at step 10. A strategy room opened before its dependencies exist will be blocked on CORE — which
is expected, and is a reason to keep the infrastructure room ahead of the others.

Current state: Symbol Resolver done (step 2). Market Data + Session + Calendar in progress (step 3).
ARK's signal rules remain unspecified and block step 10 regardless of Core progress.
