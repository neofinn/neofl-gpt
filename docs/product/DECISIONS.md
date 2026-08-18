# Product Owner Decisions

Append-only record of decisions made in conversation rather than in the captured canon documents.

The canon files in this directory are verbatim transcripts and are never edited. Decisions taken
afterwards live here. Per `HANDOFF_DIRECTIVE.md`, a later decision supersedes an earlier one — so
entries below outrank the canon where they conflict, and the conflict must be stated explicitly.

Format: date, decision, rationale, and what it changes in practice.

---

## D-001 — AI processes data only; it holds no order authority

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active

### Decision

AI components process and analyze data. They do not place, modify, or close orders, and hold no
trade authority of any kind.

### Context

Raised after discovering that MetaTrader 5's built-in assistant was configured with
`PermissionsTrade = 1` — granting an AI trade authority through a third-party inference endpoint
(`api.inferdeck.net`). See `docs/testing/RUNNING.md`.

### Rationale

Confirms and sharpens what the canon already states in three places:

> Do NOT give an LLM unrestricted live order authority.
> No AI component should bypass risk controls or human live-deployment approval.
> External AI must not become a single point of failure.

Beyond principle, there is an evidence problem: if any AI can trade the account NeoFL trades, the
execution evidence NeoFL's own demo validation depends on becomes unattributable. NeoFL could not
prove which order came from which engine.

### What this changes in practice

**Permitted for AI — reading and analysis:**
- market data, symbols, contract specifications, history
- positions, orders, account state, logs
- telemetry and observer output
- diagnostics, research, backtest analysis, recommendations

**Not permitted for AI — any write that reaches the market:**
- opening, modifying, or closing positions
- placing, amending, or deleting pending orders
- changing SL/TP or trailing state on live positions
- altering live risk or capital parameters

Recommendations flow `AI → validation/policy → human approval → configuration → EA`. Never directly.

### Consequences

1. **MT5 MCP connection is aligned with this decision** when used for data access. Reading market
   data, symbols, positions, and history over the MetaTrader MCP server is explicitly in scope; using
   it to place orders is not. This makes the MCP route attractive rather than risky.
2. **`PermissionsTrade` should be `0`** in MT5's assistant configuration. It was `1` when discovered.
   Setting lives under Tools → Options. Owner action — NeoFL does not modify terminal settings.
3. The Agentic Brain (build step 17) remains advisory-only, as the canon already specifies.
4. Deterministic operation is unaffected: if every AI component is offline, NeoFL keeps trading.

---

## D-002 — The AI observes the data feed and verifies the engines process it correctly

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active
**Refines:** D-001

### Decision

The AI observes the data feed, and observes whether the engine scripts are processing that data as
they should. It is a correctness monitor, not merely a passive analyst.

### Why this is a sharpening, not a repetition

D-001 said what the AI may not do. D-002 says what it is *for*. The distinction matters because
"analyze the results" and "verify the processing was correct" demand different things of the system:

- Judging *results* needs outputs — P/L, trades taken, win rate.
- Judging *correctness* needs **inputs, the decision, and the reasoning** — enough to independently
  re-derive what the engine should have concluded and compare it against what it did conclude.

An engine that emits only `BUY XAUUSD 0.01` cannot be checked. An engine that emits *"M15 range
2412.30/2408.10, M5 close 2413.05 above range, CHOCH confirmed, therefore LONG"* can be, because a
verifier can evaluate whether that conclusion actually follows from those inputs.

### Engineering consequence: every Core engine emits decision provenance

This is now a design requirement for all Core modules, not something bolted on at build step 9.

On every meaningful decision, an engine emits:

| Field | Meaning |
|---|---|
| inputs | the data the decision was made from, with source and timestamp |
| data quality | `DATA_OK` / `DELAYED` / `INCOMPLETE` / `UNAVAILABLE` / `INVALID` |
| decision | what was concluded |
| reason | why — the rule or threshold that fired |
| rejections | what was considered and declined, **and why** |

The last row is the one most often skipped and the most valuable. Silence is ambiguous: an engine
emitting nothing might be correctly finding no setup, or might be broken and blind — and from the
outside those look identical. An engine that emits *"no trade: ATR 18 points, below minimum 50"* is
verifiably working.

**Absence of a signal must itself be an observable event.**

### The pattern already exists

`CORE/NeoFL_SymbolResolver` was built this way before this decision was recorded. It does not return
a bare boolean — it populates `reject_reason`:

```
BTCXAU -> rejected: "XAU present as quote currency, not base; not the gold instrument"
```

An observer reading that can confirm the resolver rejected `BTCXAU` for the *right* reason rather
than by accident. Had it merely returned `false`, a resolver that rejected everything would be
indistinguishable from a correct one.

This is the house pattern. Every subsequent Core engine follows it.

### Consequences

1. Engines are built observable from the first line, not instrumented afterwards.
2. The Observer Network (build step 9) becomes a consumer of a contract the engines already honor,
   instead of having to reverse-engineer intent from outputs.
3. Verification works offline: provenance records are replayable, so correctness can be checked
   against historical data without touching a live account — entirely within D-001.
4. This grants no authority to correct what it finds. Findings are reported; remediation still flows
   through human approval per D-001.

---

## D-003 — Sessions are global; gold's day spans Asian open to American close

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active
**Supersedes:** the US-only session assumption in the first Session engine build

### Decision

Session timing is a **global** concern, not a US one. The system must know the trading
hours of every market it touches.

- **Gold trades in every zone.** Its trading day **starts with the Asian session and ends
  with the American session.**
- **Global major indices each have their own hours** — the system must know each, not
  apply one schedule to all.

### Why the first build was wrong

`NeoFL_Session.mqh` modelled only the US cash session (09:30–16:00 ET). That is correct for
US indices and wrong for everything else:

- Gold would appear "closed" for the roughly 14 hours a day it is actively traded in Asia
  and Europe.
- DAX, FTSE and Nikkei would be evaluated against New York's clock.

### The hard part: DST is not one rule

Each region switches on different dates, and one does not switch at all. Applying US dates
globally is wrong for several weeks a year — precisely the weeks where a session boundary
silently shifts by an hour and nobody notices until a trade fires at the wrong time.

| Region | DST rule |
|---|---|
| US | second Sunday March → first Sunday November |
| EU / UK | last Sunday March → last Sunday October |
| Australia | first Sunday October → first Sunday April (southern hemisphere, inverted) |
| Japan | **no DST at all** |

There are also weeks where US and EU have switched but the other has not, so the
London–New York overlap moves. That overlap is the highest-liquidity window of the day, so
getting it wrong matters.

### What this changes in practice

1. Sessions are defined per market: local open/close, base UTC offset, and DST rule.
2. All comparisons happen in GMT. Broker server time remains untrusted.
3. The gold trading day is derived: **Asian session open → American session close.**
4. Session overlaps are exposed, because liquidity concentrates there.
5. Indices consult their own exchange's hours, never a shared default.

### Consequences

- The Jobbing strategy's US-open opening range is unaffected — it still keys off New York,
  which is now one market among several rather than the only one modelled.
- Strategies ask "is my market open?" rather than assuming. A strategy that cannot answer
  that for its instrument is not ready to trade it.

---

## D-004 — The NeoFL repository is public

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active
**Supersedes:** `MASTER_SPEC_v1.0.md` §5 ("Create a private GitHub repository: NeoFL")

### Decision

The NeoFL GitHub repository is **public**.

### Context

The canon specified a private repository. The product owner chose public after being shown
what becomes permanently visible: the `legacy/` tree of 37 MQL5 files (including
`NeoFL_MasterBrain_v3_85.mqh`, the straddle/bucket recovery engine, and the GOLD 5.x–6.6
dual-engine line), the full architecture canon, and the decision log.

Publication is effectively irreversible — forks, caches and indexes survive deletion of the
original. This was stated before the decision was taken.

### What does NOT change

The secrets rule is unaffected and becomes **more** load-bearing, not less:

- No broker credentials, API keys, exchange credentials, AI API keys, SSH keys or account
  passwords in the repository — ever.
- `.gitignore` excludes `.env*`, `*.key`, `*.pem`, `secrets/`, `accounts.ini` and
  `assistant.ini` (which holds the MT5 MCP API keys).
- Anything requiring a secret is supplied through environment variables or untracked local
  config.

In a private repository a leaked key is a mistake. In a public one it is a live incident
within minutes of the push. Every commit from here is subject to the same scan that was run
before the first push: tracked-file names, key-shaped strings, and high-entropy blobs.

### Consequences

1. Treat every commit message and comment as public writing.
2. Broker names, account numbers, and balances must not appear in commits, logs, or test
   fixtures.
3. Backtest reports and terminal logs may contain account identifiers — they are not
   committed, and `.gitignore` already excludes `logs/` and `*.log`.

---

## D-005 — NeoFL requires hedging accounts

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active

### Decision

NeoFL runs on **hedging** accounts, always.

### Why it matters

The bucket/straddle recovery architecture is only possible under hedging. A straddle
requires a long and a short open simultaneously on one symbol; on a **netting** account
the opposite order does not create a second position — it reduces or closes the first.

The legacy v3.85 engine guards this correctly (`if(!IsHedgingAccount()) return false;`)
but announces the refusal once and then falls silent, so on a netting account the entire
recovery system never engages while looking identical to a system that simply found no
setup.

### What this changes in practice

1. **Startup is a hard gate, not a warning.** An engine that cannot run its risk control
   must refuse to start, not run unprotected. Per D-002 this must be continuously
   observable, not a single log line.
2. Bucket and Straddle engines may assume multiple simultaneous positions per symbol.
3. Position identity cannot rely on "one position per symbol" — several coexist, which is
   precisely why identity must come from a magic number or a ticket registry rather than
   the symbol or a comment.

---

## D-006 — The product is account-agnostic; it adapts rather than being configured

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active

### Decision

NeoFL runs on cent accounts and standard accounts alike, and **the account type must not
change the outcome**. The product recognises its environment and adjusts itself. The
operator does not re-tune parameters when moving between accounts.

### Why the previous approach was wrong

`InpStraddleHardCap = 0.30` is a fixed lot count, and a lot count means nothing on its own.
On a cent account it is negligible; on a standard account it is 100× the exposure. The same
flaw ran through every absolute-money input — `InpStraddleProfitBufferMoney = 1.00` is one
US dollar on a standard account and one US **cent** on a cent account. Identical settings,
hundred-fold different behaviour.

Parameters expressed in lots or absolute money silently encode an assumption about the
account they were tuned on.

### The principle: relative, not absolute — and no detection

The instinct is to detect cent accounts and scale. That is the worse fix: detection is
guesswork (currency naming is not standardised), and it fails on any account type nobody
anticipated.

Express every limit as a **fraction of the account**, and the question disappears:

```
straddle cap (lots) = (balance x cap%) / (account currency per lot per unit of price)
```

The denominator comes from the broker's own `SYMBOL_TRADE_TICK_VALUE / SYMBOL_TRADE_TICK_SIZE`.
Cent accounts, standard accounts, exotic account currencies and different instruments all
resolve correctly, because the broker's own numbers carry the scaling. Nothing is inferred.

### What was already correct

The straddle sizing formula itself needed no change. It calls `OrderCalcProfit`, which
returns account currency, so it was already account-agnostic — the cent denomination
cancels between numerator and denominator. The defect was entirely in the *limits* wrapped
around it.

### What this changes in practice

1. Caps and buffers are configured as percentages of balance, not lots or money.
2. The EA derives the effective lot cap at runtime and **reports what it derived**, so the
   operator can see the inference rather than trust it (D-002).
3. Absolute inputs remain available for an operator who deliberately wants them, but are no
   longer the default path.
4. Moving an account, changing broker, or switching instrument requires no re-tuning.

---

## D-007 — The universe splits into MT5 development and Python development

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active

### Decision

Development divides into two rooms, both built on the same NeoFL infrastructure:

- **MT5 development** — everything that executes or runs inside MetaTrader.
- **Python development** — everything that ingests, analyses, or reasons about data outside it.

### The dividing line

The canon already sets it:

> MQL5 is responsible for market execution, broker interaction, final order handling,
> SL/TP, trailing, and execution safety.
> Python is responsible for external data, normalization, feature processing, databases,
> and agentic services.

Restated as a test — **does it need to be inside the terminal at the moment a decision
becomes an order?**

- Yes → MT5. Execution, live position management, anything on the tick path.
- No → Python. Analysis, research, external data, telemetry, anything that can be late
  without being wrong.

### Room boundaries

| | MT5 room | Python room |
|---|---|---|
| Owns | `CORE/`, `STRATEGIES/`, `OBSERVER/`, `SCRIPTS/`, `DEPLOYMENTS/`, `BACKTEST/` | `python/`, `DATA/`, `EXTERNAL_BRAIN/` |
| Language | MQL5 | Python |
| Verifies with | `tools/mql5_compile.sh`, MT5 Strategy Tester, demo | `python3 -m unittest` |
| Authority | **the only component that may place an order** | **may never place an order** (D-001) |

### Why this is not merely organisational

The two sides have different failure modes and different standards of proof.

MQL5 code runs on the tick path with real money behind it. A mistake there is an order.
It must compile, and it should be provable by demo execution before it is trusted.

Python code is analytical. A mistake there is a wrong conclusion, which is cheaper but
more insidious — it can be believed for a long time. Python work is proven by tests
against known-answer cases, which is why the reference mirrors exist.

Keeping them in separate rooms means neither borrows the other's standard of proof. A
Python session cannot conclude that "it compiles" is sufficient; an MQL5 session cannot
conclude that "the unit test passes" means it will execute.

### The shared contract

The two sides meet at the data schema, and it is maintained in both languages
deliberately:

```
CORE/NeoFL_DataValidation/NeoFL_DataQuality.mqh   <->   python/neofl_gateway/schema.py
```

Quality states, verdicts, and the decision-provenance record must mean the same thing on
both sides. If they drift, the MQL5 side will act on data the Python side already
considered unusable. **Either room may propose a schema change; neither changes it alone.**

### Rules

1. Shared Core changes happen in the **infrastructure room** (repository root), not in a
   strategy or language room — a change there can break consumers the room cannot see.
2. Neither room edits the other's tree. Cross-boundary needs are handed over, not reached
   across.
3. The schema is a joint contract; changes are coordinated.
4. D-001 holds absolutely: no Python component ever places, modifies, or closes an order.

---

## D-008 — AutoCapital sizing, and 1R is the straddle trigger distance

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active
**Supersedes:** the `0.01` hard cap as a sizing rule (it survives only as an exposure limit)

### Decision

Position sizing is computed by an **instrument-aware AutoCapital engine**, from:

```
account balance / equity        instrument specification
available funds                 contract size
strategy risk configuration     tick size / tick value
current price                   broker volume min / max / step
required recovery economics     exposure limits
straddle trigger distance
```

Sizing is **configured per strategy**. No single lot size is hard-coded across the NeoFL
universe.

### The rule that changes the Risk engine: 1R is not a stop

Target reward:risk is **1:2**. But:

> **1R = the distance from the main trade entry to the straddle recovery trigger.**

Not an ordinary initial stop loss. This strategy family has no stops (see
`LEGACY_STRADDLE_DEFECTS.md`) — the straddle *is* the risk event, so the distance to it is
what "risk" means here.

The consequence is that sizing and recovery are one calculation, not two. The engine must
derive, together:

- the **straddle trigger distance** (which defines 1R), and
- the **straddle lot size** needed to make recovery work at that distance

from live market, instrument and account conditions. Sizing the main trade without knowing
where recovery triggers would be sizing against an undefined risk.

### What happens to `0.01`

It becomes, at most, a **configurable maximum lot / exposure limit**. It is no longer the
sizing algorithm.

The ability to impose a maximum must not be removed — capping exposure is a legitimate
safety control. What is removed is treating one number as the universal answer, which is
the same defect D-006 identified for account types.

### Consequences

1. `CORE/NeoFL_Risk` gains an AutoCapital layer; the current percent/fixed models become
   inputs to it rather than the whole engine.
2. The Straddle Engine and the Risk engine share a calculation and cannot be finished
   independently.
3. Strategy configuration becomes a first-class object — per-strategy risk, not global.

---

## D-009 — ARK's signal layer is blocked; infrastructure proceeds regardless

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active

### Decision

**ARK is blocked at the signal layer** until the exact trading rules are supplied.

- Do **not** invent `ARKSignal()`.
- Do **not** substitute Jobbing logic for ARK. The backtest file named ARK containing
  Jobbing is a naming and history problem, not evidence the two are the same strategy.
- The architectural description ("liquidity flow and market structure") is **not**
  sufficient to derive deterministic entry rules, and must not be treated as if it were.

### The part that unblocks everything else

**Infrastructure may be built before the strategy signal is finalised.**

When ARK's rules arrive they plug into the existing strategy interface. They must not
require another Core rewrite — which is the actual test of whether the interface was
designed properly.

### Status

**Unblocked and buildable now:** Core, AutoCapital, Execution abstraction, Position
Manager, Bucket, Straddle, Stop/BE/Trailing, Observer Network, data layer, Python/MT5
bridge, calendar and session, backtest framework, symbol resolver.

**Blocked:** `ARKSignal()` only.

---

## D-010 — Research discipline: evidence before implementation

**Date:** 2026-08-16
**Decided by:** product owner
**Status:** active

### Decision

```
Research  ->  evidence  ->  decision  ->  implementation
```

A research result **never silently changes a production EA**.

### Applied to the open Gold questions

These belong to the **Gold wickless strategy**, not ARK, and are research questions rather
than blockers:

| Question | Position until evidence arrives |
|---|---|
| Does the wickless thesis hold? | run `NeoFL_WicklessResearch` on Gold |
| Wickless *end* vs candle *open*? | **keep `open`.** Flag as an unresolved Gold parameter; the research script must report **both** interpretations for comparison |
| Straddle 0.02 vs 0.03? | **keep 0.02.** Do not silently change it. The Straddle Engine computes dynamically where configured to |
| Broker contract and tick values? | verify empirically on the real account; never assume |

### Validation sequence — no stage may be skipped

```
compile -> unit / state validation -> historical backtest
        -> forward / demo validation -> controlled live deployment
```

No claim of profitability follows from compiling, from correct arithmetic, or from having
traded live. Those establish validity, not edge.

### Instrument specification must be read, never assumed

The startup diagnostic exposes, at minimum: symbol, contract size, tick size, tick value,
point, digits, volume min/max/step, account currency, current price.

Assumptions such as "0.01 lot = 1 cent per dollar of movement" are forbidden — that figure
was inferred during analysis and must come from the broker instead.
