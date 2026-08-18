# NeoFL Strategy Engines

These modules are signal/evidence engines used by the Python brain. They do not bypass
NeoFL risk controls or place broker orders directly.

## Wickless v4.11

`wickless_v411.py` is a Python port of the supplied `NeoFL_v4_11_RECOVERY_BE_FIXED`
intelligence rules. The source build is v4.11 and its key signal contract is:

- M30 EMA12 trend + slope
- M15 EMA12 trend + slope
- M30/M15 agreement required
- M5 closed candle is the wickless recorder
- bullish/no-upper-wick -> long signal
- bearish/no-lower-wick -> short signal
- signal level = M5 high/low

Recovery, bucket-BE, Straddle protection and execution remain outside this signal module.

## Liquid Flow ARK

`liquid_ark.py` is the ARK 7.1 foundation currently defined for the project:
confirmed swings, BOS, value-area confluence and mitigation evidence. It intentionally
does not invent the still-unfinalized proprietary CHoCH/entry/reassessment rules.

ARK is isolated from Wickless; they are separate engines and can be registered or
backtested independently.
