# Candle Revisit — improvement analysis

Independent analysis, requested 2026-08-16. **Proposals only.** Trading logic belongs to
the product owner; nothing here is implemented, and each item states what it would change,
what it would cost, and how to test whether it actually helps.

---

## The reframe that should drive everything

This strategy has **no stop loss**. The straddle recovery is the only risk control.

That changes what "a better entry" means. In a stopped strategy you optimise hit rate,
because losers are cut at a known size. Here every losing entry becomes a **recovery basket**,
and the size of that basket is set by how far price runs against you before resolving — the
**Maximum Adverse Excursion**.

> **Entry quality and recovery load are the same problem seen from two ends.**
> The objective is not a higher win rate. It is **lower MAE**.

A filter that raises win rate from 55% to 60% but leaves MAE unchanged has bought almost
nothing. A filter that leaves win rate flat but cuts average MAE by 30% reduces every
straddle by 30% and shrinks the worst basket the account will ever have to carry.

This is why the research script reports MFE and MAE alongside hit rate, and why I would
judge every proposal below on MAE first.

---

## What the engine currently ignores

Reading the classifier and signal code, the engine already *computes* several things it
then discards, and observes several more it never looks at:

| Available | Currently used? |
|---|---|
| `revisit_count` — how many times a level was tested | incremented, then **never read** (only the boolean `revisited`) |
| Bars between level creation and revisit | not tracked |
| Candle range — the size of the impulse | used only to compute ratios, then discarded |
| `tick_volume` | not read at all |
| Higher-timeframe trend | not read at all |
| Session / time of day | not read at all |
| ATR / volatility regime | not read in the entry path |

Several of these are free — the data is already in the `MqlRates` the engine is holding.

---

## Proposals, ranked by expected MAE reduction per unit of complexity

### 1. Trend alignment — flagged by the product owner, and I agree it ranks first

**The problem.** A `LEVEL_BREAKOUT_BULL` is treated identically whether price is trending
up or down. In a downtrend, bull breakout levels break out, then fail and continue down —
and with no stop, that failure runs. Counter-trend failures are exactly where the largest
MAE lives.

**Proposal.** Require the higher-timeframe bias to agree with the level's direction. The
level's own timeframe is M5; the natural context is M15 or M30 (M15 is already the canon's
confirmation timeframe for Jobbing).

**Cost.** Fewer entries — possibly far fewer. In a ranging market, roughly half the signals
disappear.

**Why it should help disproportionately here.** It does not remove random losers evenly. It
removes the specific losers that run furthest, because a counter-trend breakout failure has
a trend pushing it. Expected effect on MAE is larger than the effect on hit rate.

**How to test.** The research script already grades every signal. Add a trend filter and
compare *avg MAE*, not just hit rate. If MAE falls more than trade count, it is a win.

---

### 2. Volatility-relative tolerance instead of a fixed 30 points

**The problem.** `InpTolerancePoints = 30` is fixed. On gold, 30 points is a meaningful
distance during quiet Asian hours and noise during the London/New York overlap or around
CPI. The same number is simultaneously too tight and too loose depending on the hour.

Tolerance controls two different things at once — how close counts as a *revisit*, and how
far beyond counts as a *breakout*. A fixed value makes both wrong in some regimes.

**Proposal.** Express both as fractions of ATR on the signal timeframe. Same idea as D-006:
a fixed absolute number silently encodes an assumption about the conditions it was tuned in.

**Cost.** One indicator handle. Behaviour becomes regime-dependent, which is the point but
also makes results less directly comparable across periods.

**Note.** This is the same class of defect as the hard-coded lot cap. Worth fixing for the
same reason.

---

### 3. Use `revisit_count` — it is already being computed

**The problem.** The engine increments `revisit_count` and then only ever checks the
boolean. A level touched once and a level touched five times produce identical signals.

Those are not the same situation, and the direction of the effect is genuinely arguable:

- **First touch is best** — the level is fresh, resting orders are intact.
- **Repeated touches strengthen** — the level is being respected.
- **Repeated touches weaken** — liquidity there is exhausted, the next touch goes through.

I do not know which holds for this instrument, and neither does anyone else without
measuring. But the data is already in the struct.

**Proposal.** Measure outcome grouped by revisit count. Then either restrict entries to the
best bucket or drop the idea on evidence.

**Cost.** Near zero to measure. This is the cheapest experiment available.

---

### 4. Impulse strength — bigger wickless candles should not equal smaller ones

**The problem.** Classification is entirely ratio-based. A wickless candle spanning 2 points
and one spanning 40 points both create a level of identical standing. But the thesis is
about *conviction*, and a 2-point wickless candle in a dead market is not conviction — it is
a lack of activity.

**Proposal.** Require the candle's range to exceed some fraction of current ATR before it
creates a level. Optionally rank levels by impulse size and prefer the strongest when
several are in play.

**Cost.** Fewer levels. Removes the ones formed in dead conditions — which is likely where
false breakouts concentrate.

**Why I rank it high.** It attacks the same failure mode as trend alignment (entries taken
in conditions that cannot sustain a move) from a different direction, and it is cheaper.

---

### 5. Session awareness — gold is not one market

Already built and unused: `CORE/NeoFL_Session/NeoFL_GlobalSessions.mqh` knows the Asian,
London and New York windows and their overlap, with DST computed per region (D-003).

**The problem.** Asian-session gold is thin. Breakouts there fail more often and mean less.
The London/New York overlap is the deepest liquidity of the day. The engine cannot tell
them apart.

**Proposal.** Either restrict entries to chosen sessions, or — better — keep trading all
sessions but *measure separately*, then decide with evidence.

**Cost.** None to measure. The engine exists.

---

### 6. Tick volume on the breakout candle

**The problem.** A breakout close one point beyond tolerance on minimal activity is treated
the same as a decisive impulse.

**Proposal.** Require the breakout candle's `tick_volume` to exceed a recent median.

**Cost.** Free — the field is already in `MqlRates`.

**Caveat worth stating.** MT5 tick volume is tick *count*, not traded volume. On a CFD it
reflects broker feed activity, so it is a proxy for market interest rather than a measure of
it. Useful, but weaker evidence than the others, which is why it ranks last.

---

## What I would NOT do

**Add a stop loss.** Tempting, and wrong here. The whole architecture assumes positions
survive adverse movement so the straddle can recover the basket. Adding stops without
redesigning the recovery would cut positions the recovery mechanism was built to rescue,
and would change the strategy's identity rather than improve it. If stops are wanted, that
is a different strategy and should be built as one.

**Optimise the ratio thresholds first.** `0.15 / 0.70 / 0.40` are the most tempting knobs
because they are numbers sitting right there. They are also where curve-fitting is easiest
and least honest. Structural filters — trend, session, impulse size — should be settled
before anyone touches thresholds, or the thresholds will simply absorb the noise those
filters would have removed.

---

## Suggested order of work

1. **Run `NeoFL_WicklessResearch` unmodified.** Establish the baseline, and read the control
   column first. If THESIS ≈ CONTROL, the candle shape carries no directional information
   and every proposal above is decoration on a signal that does not exist. That result would
   be disappointing and extremely valuable.
2. **Bucket the same data** by revisit count, session, and impulse size. No new logic —
   grouping alone.
3. **Add trend alignment** and compare MAE.
4. Only then consider tolerance and volume.

Steps 1–2 need no trading-behaviour change at all, which is why they come first.
