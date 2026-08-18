# AI Development Workflow

Operational detail behind `CLAUDE.md`. Applies to any AI agent working in this repo (Claude Code,
Codex, or otherwise).

## Flow

```
Product owner decision
        |
        v
AI: architecture / code / tests / docs
        |
        v
Git branch + reviewable diff
        |
        v
Automated tests
        |
        v
Human code review          [GATE 2]
        |
        v
Demo execution             [GATE 3]
        |
        v
Human live approval        [GATE 4]
```

## Branches

- `main` — reviewed work. Never commit trading-behavior changes directly.
- `feature/<short-name>` — new capability.
- `fix/<short-name>` — defect repair.
- `spec/<short-name>` — documentation and specification work.

## Commits

Explain why, not what — the diff already shows what. Any commit touching trading behavior must carry
this trailer block:

```
Trading-behavior change: yes
What changed:      ...
Why:               ...
Expected effect:   ...
Risk:              ...
Tests performed:   ...
Product approval:  required | granted <date> | not required
```

Absent that block, a trading-behavior commit is not reviewable and should be rejected at GATE 2.

## Testing

Layers, per master spec §29:

- `tests/unit/` — symbol mapping, parsers, timestamps, risk math, Trend/ARK calculations.
- `tests/integration/` — CME→gateway, TradingView→gateway, calendar→gateway, gateway→MT5,
  ARK→shared state, Trend→shared state.
- `tests/failure/` — CME disconnect, TradingView failure, internet loss, MT5 disconnect, API timeout,
  stale data, duplicate event, invalid symbol, spread explosion, market closed.
- `tests/regression/` — protects approved trading behavior. Adding a regression test is how an
  approved behavior becomes permanent.

Run before claiming completion:

```bash
python3 -m unittest discover -s tests
```

### What each signal actually proves

MQL5 **compiles on this Mac** via `tools/mql5_compile.sh` (MetaEditor under MetaTrader 5.app's
bundled Wine). Compile every change — it takes about a second.

- Python tests prove the **logic** is right. Not that the EA works.
- A clean compile proves the code is **valid MQL5** and links with its includes. Not that the
  strategy is correct.
- A Strategy Tester run proves **behavior against historical data**. Not live broker behavior.
- Only a demo account proves **real execution** — fills, slippage, rejections.

Never blur these in a status report. The Strategy Tester requires a broker account in its config, so
it is human-initiated; report backtest results as human-observed evidence.

See `docs/testing/RUNNING.md`.

## Definition of done

1. Code written and self-reviewed.
2. Tests written and passing.
3. Docs updated where behavior or architecture changed.
4. `CHANGELOG.md` updated.
5. Risks stated explicitly, including what was *not* verified.
6. Product approval requested if trading behavior changed.

An honest "implemented, tests pass, compilation unverified — needs a Windows MetaEditor run" is a
complete report. A confident claim that outruns the evidence is not.
