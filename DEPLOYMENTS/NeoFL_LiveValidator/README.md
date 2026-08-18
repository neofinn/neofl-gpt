# NeoFL Live Validator

**READ-ONLY. This EA places no orders.** It has no execution call anywhere in the package
and never includes `CTrade`, so there is no trading object to misuse. Verified by grep over
every file: no `OrderSend`, `PositionClose`, `PositionModify`, `PositionOpen`, or
`TRADE_ACTION_*`. `OnTick()` is deliberately empty.

## What it is for

Validating the NeoFL Core against a live broker feed **before** an execution engine exists.
If these numbers are wrong, they would be wrong later with money behind them — and a wrong
number is far cheaper to find now.

## Install

1. MT5 → File → Open Data Folder
2. Copy this whole folder into `MQL5/Experts/`
3. MetaEditor → compile `NeoFL_LiveValidator.mq5`
4. Attach to an **XAUUSD** chart (any timeframe — it reads M15 itself)

AutoTrading may stay **off**. The EA does not need it, which is itself a useful check: if
anything ever tries to trade, MT5 will refuse and log it.

## What the panel shows

| Row | Question it answers |
|---|---|
| symbol | Does the resolver recognise *your broker's* gold symbol? |
| quote | Live bid/ask, spread, tick age, and the data-quality verdict |
| M15[1] closed | Is closed-bar history actually readable? |
| gold day phase | Asian / London / New York / overlap / between-sessions / weekend |
| active sessions | Which dealing sessions are open right now |
| offsets | Live UTC offsets — confirms DST is computed per region |
| US cash session | Open or closed, derived from GMT not broker time |
| opening range | Has the first M15 candle closed (Jobbing's range)? |
| next high-impact | Calendar reachable, and what's coming |
| risk sizing | What the Risk engine *would* size, and why |
| straddle example | What the Straddle engine *would* size for a hypothetical gap |
| positions | Open positions under magic 26081401 — observed, never touched |

## What to check on the first run

1. **Account margin mode** — printed at startup. Must say `HEADING` … i.e. `HEDGING`.
   Netting means the straddle recovery cannot run at all (D-005).
2. **Does your broker's gold symbol resolve?** If it says `REJECTED`, tell me the exact
   symbol string and I will extend the resolver.
3. **Data quality** — anything other than `DATA_OK` on a live session is worth reporting.
4. **Gold day phase** — should track the real session you are in.

## Key inputs

Everything is reporting-only; changing them changes the panel, not the market.

- `InpRiskModel`, `InpRiskPercent`, `InpHardMaxLot` — risk parameters to preview
- `InpStraddleMode` — `RATIO` (size fixed, distance follows gap) or `FIXED_DISTANCE`
  (distance fixed, size follows gap). See `docs/product/DECISIONS.md`.
- `InpExampleGap` — the hypothetical adverse move used for the straddle preview
- `InpLogDecisions` — also write full D-002 provenance records to the Experts log

## What this does NOT do

- No entry logic. No strategy exists yet; ARK's rules remain unspecified.
- No orders, no position management, no basket handling on live positions.
- It does not replace or interfere with your existing v3.85 LIVE engine. It only reads.
