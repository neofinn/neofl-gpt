# Candle Revisit — the strategy thesis

Stated by the product owner, 2026-08-16:

> Whenever a wickless candle is formed, when the price revisits the wickless end, a
> breakout comes.

This is the core intellectual property of the engine and it existed **only as code** until
now. Recorded here so it survives independently of any one source file.

Verified against `legacy/candle-revisit-master-brain/v3.85_LIVE_ENGINE/`.

---

## The idea

A wickless candle has no rejection at either end. Price opened, moved one direction with
conviction, and closed at the extreme without being pushed back. The **open is where that
conviction launched from**.

When price later returns to that origin, the same impulse is expected to reassert itself.
It is a continuation thesis, not a reversal one.

The engine reads two opposite meanings from candle shape:

| Shape | Meaning | Level placed at |
|---|---|---|
| **No wick** — conviction, no rejection | continuation from the origin | the **open** |
| **Large wick** — rejection at an extreme | reversal from that extreme | the **wick's high/low** |

---

## As implemented

### 1. Classification (closed candles only)

```mql5
range = high - low
body  = |close - open|
upper = high - max(open, close)
lower = min(open, close) - low
```

**Wickless** — creates a breakout level:

```
(upper + lower) / range  <=  InpWicklessRatio   (0.15)
body / range             >=  InpMinBodyRatio    (0.70)
```

Bull → `LEVEL_BREAKOUT_BULL` at `open`. Bear → `LEVEL_BREAKOUT_BEAR` at `open`.
Doji and neutral candles create nothing.

**Wicked** — creates a reversal level:

```
lower/range >= InpWickedEndRatio (0.40) AND lower > upper  ->  LEVEL_REVERSAL_LOW  at low
upper/range >= InpWickedEndRatio (0.40) AND upper > lower  ->  LEVEL_REVERSAL_HIGH at high
```

### 2. Revisit

A level is "revisited" when a candle's range touches within `InpTolerancePoints` (30) of it:

```mql5
touched = (bar.high >= level - tol && bar.low <= level + tol)
```

`inside_zone` latches so a single approach counts once; the level must be left and
re-entered to count again.

### 3. Breakout confirmation — the current rule

```mql5
if(!L.revisited) return false;
BULL: bar.close > L.price + tol
BEAR: bar.close < L.price - tol
```

**That is the entire confirmation.** Revisit, then one closed candle beyond the level by
more than tolerance. The level is consumed on entry.

Levels expire after `InpMaxLevelAgeBars` (500) and at most `InpMaxLevels` (200) are held.

---

## Open question: which end is "the wickless end"?

The owner's phrasing says *"the wickless end"*. The code always uses the **open**.

For a perfectly wickless candle both ends are clean, and the open is the origin — these
agree. But `InpWicklessRatio = 0.15` permits up to 15% total wick, so a qualifying candle
may have a small wick on one end and none on the other. The code takes the open regardless.

Two readings:

1. **Origin** — always the open. *(implemented)*
2. **Whichever end is actually clean** — could be the close on a partially-wicked candle.

**UNCONFIRMED — pending product owner clarification.** If (2) is intended, the
implementation diverges from the thesis and the levels are being placed at the wrong price
on a subset of candles.

---

## What is NOT confirmed today

The breakout rule uses no momentum, volume, structure, session, trend or volatility
context. A close one point beyond tolerance, in a dead market, at any hour, is treated
identically to a decisive impulse during the London/New York overlap.

This is worth stating plainly because it interacts with the risk design: the strategy
carries **no stop loss** and relies on the straddle recovery instead. A thin entry filter
produces more losing entries, and every losing entry becomes a recovery basket. Entry
quality and recovery load are the same problem viewed from two ends.

`SCRIPTS/RESEARCH/` contains a tool for measuring this empirically rather than arguing
about it.
