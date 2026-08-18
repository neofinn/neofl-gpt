# Python development room

> **Open a session with `python/` as the working directory for Python work.**
> Read `CLAUDE.md` in the repository root first — it applies in full.

## What this room owns

```
python/neofl_core/      reference implementations mirroring the MQL5 engines
python/neofl_gateway/   webhooks, API, normalization, common schema
DATA/                   MT5, external, PineConnector, validation
EXTERNAL_BRAIN/         telemetry, event stream, analytics, recommendations
tests/                  the whole suite
```

## The hard boundary

**Nothing in this room may place, modify, or close an order** (D-001). Not through MT5's
Python package, not through a broker API, not through a file the EA reads as a command.

This is enforced structurally, not by convention: `ApiRegistry` in `neofl_gateway/api.py`
has no way to express a side effect, and a test asserts no command surface exists. Keep it
that way — if a change would make an order reachable from here, it belongs in the MT5 room.

## The standard of proof here

Python is analytical. A mistake is a wrong conclusion — cheaper than a bad order, but more
insidious, because a wrong conclusion can be believed for months.

```bash
python3 -m unittest discover -s tests -t .
```

Prove logic against **known-answer cases**, not against the implementation. The session and
risk tests assert real calendar dates and hand-computed sizing precisely so a bug in the code
cannot make its own test pass. Follow that pattern.

## Why the mirrors exist

`python/neofl_core/` reimplements MQL5 logic — symbol resolution, sessions, risk, bucket,
straddle. This is deliberate duplication:

- MQL5 logic can only be exercised inside MetaTrader, which is slow and needs a terminal.
- The rules are pure computation, so they can be tested in milliseconds here.
- Two independent derivations agreeing is real evidence. The bucket zero-floating price and
  the straddle sizer were built from different formulas and agree to six decimals — that
  cross-check found more than either test alone would have.

If the two ever disagree, **MQL5 is authoritative for runtime behaviour** — but the
disagreement itself means one of them is wrong, and it must be resolved rather than papered
over.

## The shared contract

```
python/neofl_gateway/schema.py   <->   CORE/NeoFL_DataValidation/NeoFL_DataQuality.mqh
```

Quality states, verdicts and the provenance record must mean the same thing on both sides.
If they drift, MQL5 will act on data this side already judged unusable. Either room may
propose a change; **neither changes it alone** (D-007).

## Rules specific to this room

1. **`None` is not zero.** A source that does not supply a field must say so. `0.0` means
   measured-as-zero. Conflating them is how fabricated data reaches a strategy — a missing
   depth side read as 0 invents an order-book imbalance.
2. **Transport validity is not content validity.** A correctly signed, fresh, non-replayed
   payload can still carry an unusable instrument. Both are checked separately; this was a
   real defect.
3. **Treat every inbound payload as hostile.** Signature, replay, freshness, shape, size.
4. **No secrets in the repository.** This repo is public (D-004).

## Current state

The gateway runs on the standard library — no install needed:

```bash
python3 python/run_gateway.py --port 8787 --token YOUR_TOKEN
```

124 tests passing. FastAPI can replace `server.py` later without touching the registries;
transport is deliberately separated from logic.
