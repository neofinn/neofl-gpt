NEOFL v3.85 BACKTEST — READY PACKAGE

This is the Strategy Tester build.

INSTALL
-------
Copy:
  Experts/  -> MT5 Data Folder/MQL5/Experts/
  Include/  -> MT5 Data Folder/MQL5/Include/
  Presets/  -> optional/reference

STRATEGY TESTER
---------------
Attach ONLY:
  NeoFL_Candle_Revisit_Engine_v3_85_BACKTEST.mq5

Do NOT attach the live Master Brain or live Straddle Observer scripts.
The backtest EA has the required observer, Master Brain, calendar/risk
and basket-straddle logic built internally.

STRADDLE RULES
--------------
- Main M5 entry is hard-capped at 0.01 lot.
- Straddle lot is dynamically calculated from the actual negative floating
  loss, the actual entry-distance gap and costs/profit buffer.
- Straddle can be greater than 0.01 when required.
- Straddle's own TP is NOT an independent exit authority.
- Basket P/L is the normal straddle exit authority.
- If the main trade closes first, the remaining straddle is still governed
  by the basket calculation and cannot simply remain stuck until test end.
- The engine publishes/uses the actual basket BE and target distances.

IMPORTANT TEST VARIABLES
------------------------
See Presets/INSTALL_INPUTS.txt.

Watch:
  STRADDLE_REQUIRED_MONEY
  STRADDLE_GAP_PRICE
  STRADDLE_GAP_MONEY_PER_LOT
  STRADDLE_REQUIRED_LOTS
  STRADDLE_LOTS
  STRADDLE_COVERAGE
  BASKET_PNL
  BASKET_BE_PRICE
  BASKET_TARGET_PRICE
  STRADDLE_BE_DISTANCE
  STRADDLE_TARGET_DISTANCE

This package is for Strategy Tester only.
