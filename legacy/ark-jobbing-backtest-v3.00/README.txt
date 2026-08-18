NeoFL ARK + Jobbing — SEPARATE BACKTEST v3.00

ARK and Jobbing are now independent Strategy Tester EAs.
Test them separately.

ARK:
- US 09:30-16:00 ET, automatic DST.
- First completed M15 candle (09:30-09:45) is opening range.
- First M5 close outside the range establishes direction.
- M5 EMA/RSI confirmation.
- Persistent ARK position; opposite breakout can reverse.

JOBBING:
- Independent of ARK.
- Tick/event driven, using M1 micro context.
- Maximum holding time 60 seconds.
- Cooldown after timeout.
- New micro-price event required before another entry.
- Does not recycle a persistent signal every tick.

For Jobbing, use "Every tick based on real ticks" in Strategy Tester where available.
