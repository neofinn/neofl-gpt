# Legacy straddle observation — defect analysis

The product owner reported the straddle observation "wasn't working properly", then supplied
`NeoFL_v3_85_LIVE_ENGINE_ONE_FOLDER.zip` — the current LIVE build. This is the direct
ancestor of the v2 Straddle Engine (build step 7), so the causes matter before porting.

Package preserved at `legacy/candle-revisit-master-brain/v3.85_LIVE_ENGINE/`, unmodified.

**All three components compile cleanly** (0 errors). This is not a code fault. It is a
wiring fault, which is exactly why it fails silently.

---

## PRIMARY DEFECT — the straddle observer is orphaned

`NeoFL_Straddle_Observer_v3_85.mq5` works correctly. **Nothing reads its output.**

It publishes to global variables under one prefix, and the EA reads a different one:

```
Observer writes:   GV_PREFIX = "NEOFL_SB_"  + _Symbol + "_" + magic + "_"
                              └─ "NEOFL_SB_XAUUSD_26081401_BASKET_PNL"

EA reads:          ObserverKey = InpObserverPrefix + "_" + _Symbol + "_" + magic + "_"
                   InpObserverPrefix = "NEOFL_OBS"
                              └─ "NEOFL_OBS_XAUUSD_26081401_BASKET_PNL"
```

`NEOFL_SB_` ≠ `NEOFL_OBS_`. So in the EA:

```mql5
double basket = ReadObserverValue("BASKET_PNL", 0.0);
```

`GlobalVariableCheck()` fails and the fallback is returned. **`basket` is always exactly
0.0**, regardless of what the observer computed.

The intended connector exists — `NeoFL_Straddle_Observer_Bridge_v3_85.mqh`, whose header
says *"Include in the EXECUTION EA"* — but the EA's includes are:

```mql5
#include <Trade/Trade.mqh>
#include "NeoFL_Observer_Core_v2_00.mqh"
#include "NeoFL_MasterBrain_v3_85.mqh"
```

The bridge is included **nowhere in the package**. It is dead code. So the observer's
latched `CLOSE_COMMAND` is never consumed either.

### What is actually running

There are two independent basket calculations, and only one is connected:

| Component | Prefix | Consumed? |
|---|---|---|
| EA-internal, via `NeoFLObs_StraddleState` in Observer Core v2.00 | `NEOFL_OBS_` | ✅ yes — the EA reads its own writes |
| Standalone `NeoFL_Straddle_Observer_v3_85.mq5` | `NEOFL_SB_` | ❌ **no — nothing reads it** |

The README instructs the operator to attach the observer script. Doing so consumes CPU,
writes globals into the void, and has **zero effect on trading**. Which is precisely the
reported symptom: the script runs, logs plausibly, and changes nothing.

### ⚠️ The obvious fix is dangerous

Aligning the prefixes — making the observer write `NEOFL_OBS_` — would be **worse than the
bug**. Both the EA (via `NeoFLObs_Update`) and the script would then write `BASKET_PNL` to
the same key on different schedules. The EA would act on whichever wrote last, mixing two
basket figures computed at different instants. A racing basket calculation authorising
position closure is a considerably worse failure than one that does nothing.

### The two coherent fixes

**Option A — drop the standalone observer (simplest).**
The EA already computes and consumes basket P/L internally through Observer Core v2.00.
The standalone script is a disconnected duplicate. Stop attaching it; delete it from the
package so no operator is misled into running it.

**Option B — make the standalone observer authoritative.**
1. `#include "NeoFL_Straddle_Observer_Bridge_v3_85.mqh"` in the EA.
2. Call `NeoFL_StraddleObserver_Process(trade, InpMagic)` early on each tick.
3. **Disable the EA's internal basket path** so the two cannot both decide.
4. Add a heartbeat check — see below.

Option A is recommended unless the standalone observer exists for a reason not visible in
the code, such as surviving EA reloads.

---

## VERDICT — the live system works; the script is redundant

Call chain traced and confirmed:

```
EA line 2090:  NeoFLObs_Update(InpObserverPrefix="NEOFL_OBS", ...)
                 -> Observer Core line 400: NeoFLObs_StraddleState(prefix, ...)
                      -> line 326: NeoFLObs_Put(prefix, ..., "BASKET_PNL", basket)
                                   writes NEOFL_OBS_<sym>_<magic>_BASKET_PNL

EA line 1931:  ReadObserverValue("BASKET_PNL")
                 reads NEOFL_OBS_<sym>_<magic>_BASKET_PNL     <- same key. MATCHES.
```

**The EA's internal basket path is complete and functional.** Basket P/L is computed and
consumed entirely inside the EA.

So the standalone observer is not a broken component — it is a **redundant second
implementation** of something the EA already does, publishing to a prefix nobody reads.

**Recommended action: stop attaching `NeoFL_Straddle_Observer_v3_85.mq5`. No code change
is required.** It consumes CPU and produces nothing. The EA is unaffected either way,
which is why the symptom was "it doesn't seem to do anything" rather than a malfunction.

---

## About the missing stop losses — deliberate, not an oversight

Neither the main entry nor the straddle carries a broker stop:

```mql5
trade.Buy (lots,      _Symbol, 0.0, 0.0, tp,  comment);            // main: TP only
trade.Buy (exec_lots, _Symbol, 0.0, 0.0, 0.0, "NEOFL STRADDLE BUY"); // straddle: neither
```

The only SL mechanism is gated behind `InpEmergencyProtection`, which defaults to **false**.

This is **by design**, not a bug. The v3.6x headers state it directly: *"no initial SL"*,
*"continuous monitoring, no SL orders, and opposite-entry recovery/reversal."* The strategy
manages risk by monitoring and by the recovery straddle rather than by broker stops.

That is a legitimate architecture, and it carries a specific consequence worth stating
plainly: **the basket/straddle mechanism is the risk control.** There is no second line of
defence behind it. Anything that degrades it — a disconnected observer, a netting account
that blocks the straddle, a stripped comment breaking position identity — does not merely
reduce performance. It removes the only protection.

That is the strongest argument for the six constraints below, and for why the v2 engine
should treat basket integrity as a safety property rather than a feature.

---

## SECONDARY OBSERVATION — the straddle has no stop loss

The README specifies three SL behaviors. **None are implemented.**

```
README: "Initial Straddle SL: Straddle's OWN breakeven."
README: "Move Straddle SL to the basket-neutral protection level."
README: "Trail the straddle SL only in the profitable direction."
```

The straddle opens with stop loss and take profit both zero:

```mql5
ok = trade.Buy (exec_lots, _Symbol, 0.0, 0.0, 0.0, "NEOFL STRADDLE BUY");
ok = trade.Sell(exec_lots, _Symbol, 0.0, 0.0, 0.0, "NEOFL STRADDLE SELL");
                                    ^^^  ^^^
                                    sl   tp
```

The only `PositionModify` calls in the entire EA are inside the `InpEmergencyBrokerSL`
block, applying a single global emergency stop to any position — not a per-straddle
breakeven, and not a trail.

So the recovery straddle — fixed at **0.03 lots**, three times the main entry's 0.01 hard
cap — runs entirely unprotected apart from that optional emergency stop. On a gap or a fast
adverse move, the leg intended to *rescue* the basket is the largest unhedged exposure in it.

---

## TERTIARY DEFECT — the bridge inverts the documented rule

Currently inert, but a trap if Option B is taken without reading it.

```
README:  3. Close the original losing main trade.
         4. Keep the 0.03 straddle running as the profit runner.
```

```mql5
// bridge
NeoFL_StraddleObserver_CloseStraddles(trade, magic);   // closes the STRADDLE
```

The bridge closes the straddle — the intended profit runner — and leaves the losing main
trade open. That is the inverse of the documented architecture and of
`MASTER_ARCHITECTURE_v2.md` §12 ("the straddle is transformed from a recovery hedge into the
profit runner"). Wiring the bridge in as-is would bank the winner and keep the loser.

---

## MINOR — commission is excluded from floating basket P/L

```mql5
input bool InpIncludeSwapCommission = true;   // name promises commission
...
if(InpIncludeSwapCommission)
   p += PositionGetDouble(POSITION_SWAP);     // only swap is added
```

MT5 does not expose commission on an open position — it lives on the deal. The closed-P/L
path does include `DEAL_COMMISSION`, but the floating path cannot, so basket P/L is
overstated by the round-turn commission while positions are open.

Consequence: "basket reached breakeven" fires slightly **before** true breakeven. On
0.01 + 0.03 lots of gold this is small, but it biases every recovery exit the same
direction, and the whole mechanism keys off crossing zero.

---

## MINOR — no liveness check on the observer

The observer publishes `HEARTBEAT`; **nothing reads it**. Under Option B the EA would have
no way to distinguish "observer says hold" from "observer is dead". Per **D-002**, absence
of a signal must be an observable event: the EA must treat a stale heartbeat as
`DATA_UNAVAILABLE` and refuse to depend on basket state, rather than silently continuing.

---

## Carried forward from the earlier analysis

Still present in the LIVE build:

- **Comment-based identity.** Main and straddle share magic `26081401`; the only
  discriminator is `StringFind(comment, "NEOFL STRADDLE")`. Comments are not reliable
  broker state. Worse, the main-position scan uses the same test inverted, so a stripped
  comment makes the straddle be mistaken *for* the main trade.
- **Hedging requirement.** A straddle needs simultaneous long and short, so a netting
  account cannot run this at all — announced once in the log, then silence.

---

## Binding constraints for the v2 Straddle Engine (step 7)

1. **One basket authority.** Exactly one component computes basket P/L and exactly one
   consumes it. Never two writers to the same state.
2. **No cross-component state via string-keyed globals without a contract.** If global
   variables are the transport, the key prefix is defined in one shared header that both
   sides include — never typed twice.
3. **Identity by magic number or a persisted ticket registry**, never by comment.
4. **The straddle carries a stop from the moment it opens.** An unprotected recovery leg
   larger than the position it rescues is not a hedge.
5. **Consumers verify liveness.** A stale heartbeat is `DATA_UNAVAILABLE`, and the engine
   declines rather than assuming.
6. **At basket zero: close the main, keep the straddle.** As the canon states, and as the
   bridge currently does not.


---

# CORRECTION — the real defect, found after reading the MasterBrain in full

Two earlier conclusions in this document were wrong. Both are corrected here; the
originals are left above so the reasoning trail is visible.

## Wrong: "the straddle is sized from an ATR projection"

`NeoFL_MasterBrain_v3_85.mqh` already implements the product owner's gap rule, and its
own comment says so:

```mql5
// The coverage distance is the actual entry gap back to the main entry,
// not an arbitrary ATR projection.
double entry_gap    = MathAbs(entry-current);
double required_money = MathAbs(raw_profit)+recovery_cost+cfg.profit_buffer_money;
required_money       *= MathMax(1.0,cfg.safety_factor);
double one_lot_gap  = NeoFLMB_MoneyPerLot(symbol,str_ot,current,entry);
double required     = required_money/one_lot_gap;
double lots         = NeoFLMB_RoundUpLots(symbol,required,cfg.max_straddle_lot);
```

That is exactly "how many lots are needed to cover the loss between the main entry and
the straddle entry". It also does it better than a purely geometric formula, because
`OrderCalcProfit` uses the broker's own contract size, tick value and currency
conversion instead of assumed constants, and it includes commission, swap and a buffer.

The ATR projection is in `NeoFL_Observer_Core_v2_00.mqh` — a **different file**.

## The actual defect: two writers, one variable

Both components write the **same global variable**:

| Writer | Cadence | Value written |
|---|---|---|
| `NeoFL_MasterBrain_Script_v3_85.mq5` (`InpObserverPrefix="NEOFL_OBS"`) | ~1/second | gap-based — **correct** |
| EA's internal `NeoFLObs_Update` (`InpObserverPrefix="NEOFL_OBS"`) | **every tick** | ATR projection, and `NeoFLObs_ResetPositionState` writes **0** whenever no main position exists |

Both key resolvers produce the identical string:

```
NEOFL_OBS_<symbol>_26081401_STRADDLE_LOTS
```

The EA writes on every tick; the script writes about once a second. **The EA therefore
overwrites the MasterBrain's correct value far more often than it is written.** The EA
then reads that key back at `g_observer_straddle_lots=ReadObserverValue("STRADDLE_LOTS")`
and sizes the straddle from whichever component happened to write last.

The correct number is computed and then clobbered. This is the defect behind the reported
symptom, and it is invisible in the logs because both values are plausible.

It is also the exact hazard flagged earlier in this document as the reason not to "just
align the prefixes" — except it was already happening between two components that were
never meant to share a key.

## The fix applied in v3.86

`DEPLOYMENTS/NeoFL_CandleRevisit_v3_86_DEMO/` moves the MasterBrain formula **into the
EA**, evaluated from the live position at the moment the straddle arms. The formula is
unchanged. What changes is that the contested global variable is no longer consulted, so
there is nothing left to race.

Two refusals were added where the legacy proceeded silently: a straddle no larger than the
main is delta-neutral and is refused; and a straddle exceeding the hard cap is refused
rather than capped, since a capped straddle under-covers the gap and the basket would
never reach zero.
