# NeoFL Candle Revisit v3.86

**The EA executes. The script decides.** Attach both to the same chart.

```
NeoFL_MasterBrain_Script_v3_85.mq5   the brain — decides, writes state, never trades
NeoFL_CandleRevisit_v3_86.mq5   the executor — reads state, places orders
```

## What was wrong in v3.85

That separation existed on paper but not in practice. The EA **also** ran the brain
internally (`NeoFLObs_Update`), so two components wrote the same global variable:

| Writer | Cadence | Value |
|---|---|---|
| MasterBrain script | ~1/second | gap-based — **correct** |
| EA, internally | **every tick** | ATR projection; reset to 0 when flat |

Both resolve to `NEOFL_OBS_<symbol>_26081401_STRADDLE_LOTS`.

The EA writes far more often, so it usually overwrote the script's correct value before
reading it back — then sized the straddle from whichever wrote last. **The right number
was computed and then clobbered**, invisibly, because both values look plausible.

## What v3.86 changes

**`InpInternalBrain = false`** (default). The EA writes nothing. One brain, one writer,
no race. The straddle sizing formula is untouched — it stays in the MasterBrain, where it
already implemented your rule correctly:

```
need = (|main floating loss| + commission + swap + buffer) × safety
per  = what 1.0 lot earns travelling from straddle entry back to main entry
lots = ceil(need / per)
```

**Brain liveness is checked.** With the brain external, a script that was never attached
or has stopped leaves stale globals behind that look exactly like "do nothing". MT5
globals survive terminal restarts, so a stale `STRADDLE_ARM` could arm a straddle sized
for a position that no longer exists. If the heartbeat is older than
`InpBrainMaxAgeSeconds` (30), the EA treats brain state as unavailable and arms nothing —
and says so in the log.

**The executor validates before executing.** It does not size the straddle, but it refuses
an instruction that cannot work:

- **straddle ≤ main** → refused. Equal and opposite legs offset exactly, so basket P/L
  freezes and *no* price ever brings it to zero. Waiting would wait forever.
- **above `InpStraddleHardCap`** (0.30) → refused, **not capped**. A capped straddle
  under-covers the gap, so the basket could never reach zero.
- Rounding is **ceil**, never floor, for the same reason.

## Install

1. MT5 → File → Open Data Folder → `MQL5/Experts/`
2. Copy this whole folder in
3. Compile **both** `.mq5` files in MetaEditor
4. On an **XAUUSD** chart: attach the **EA**, then attach the **MasterBrain script**
5. Enable AutoTrading

Magic `26081401`, unchanged.

**Do not attach `NeoFL_Straddle_Observer_v3_85`.** It writes `NEOFL_SB_*`, which nothing
reads, and duplicates the MasterBrain's work. It is excluded from this package.

## What to watch

```
NeoFL v3.86 | DEMO | HEDGING | brain=EXTERNAL SCRIPT | cap=0.30
  EA IS EXECUTION ONLY. Attach NeoFL_MasterBrain_Script_v3_85 to this chart.

NeoFL STRADDLE: brain requested 0.0213 -> executing 0.03 | main 0.01 @ 2400.00,
  now 2380.00, gap 20.00 | brain P/L -20.70
```

If you see `BRAIN NOT DETECTED` or `BRAIN STALE`, the script isn't running — the EA will
trade the main entry but arm no straddle. That is deliberate: without the brain there is
no recovery mechanism, and in this strategy the basket *is* the risk control.

## Honest limits

- **Not backtested by me.** The Strategy Tester needs broker credentials I will not handle.
- Entry logic, basket management and exits are **unchanged from v3.85**.
- The straddle still carries no stop loss — that is the v3.85 design (`"no SL orders"`),
  not something introduced here.
- **Refuses to start on a netting account.** The straddle needs a long and short open at
  once; without it the basket — the only risk control here — cannot function.
- The demo-account gate was removed at the product owner's instruction (2026-08-16). This
  build runs on real accounts.

## Before the first live straddle

The straddle instruction path is new in this build and has never placed an order — not in
a backtest, not on demo. What still protects you:

- **`InpStraddleCapPctBalance = 2.0`** — the circuit breaker, expressed as a percentage of
  balance rather than a lot count. The EA derives the lot cap at runtime from the broker's
  own tick value, so it is correct on cent and standard accounts alike with no re-tuning
  (D-006). If the brain asks for more, the straddle is *refused*, not capped — a capped
  straddle under-covers the gap and the basket could never reach zero.
  Set `InpStraddleCapPctBalance = 0` to use the fixed `InpStraddleHardCap` instead.
- **Delta-neutral refusal** — a straddle no larger than the main can never bring the basket
  to zero, so it is refused rather than opened.
- **Brain liveness** — if the MasterBrain script stops, no straddle is armed.

Worth doing once: when the first straddle arms, check the `NeoFL STRADDLE:` line in the
Experts log against the chart before leaving it unattended. It prints the requested lots,
the executed lots, the main entry, the current price and the gap — enough to verify the
arithmetic by hand.
