NEOFL v3.85 LIVE ENGINE — ONE FOLDER

This is the LIVE build corresponding to the current Basket Runner design.

FILES
-----
NeoFL_Candle_Revisit_Engine_v3_85_LIVE.mq5
  ONLY execution authority.

NeoFL_MasterBrain_Script_v3_85.mq5
  Continuous live observation / decision brain.

NeoFL_Straddle_Observer_v3_85.mq5
  Continuous straddle basket observer and BE latch.

Required .mqh files are in this SAME folder.

LATEST STRADDLE RULES
---------------------
Main entry:
  HARD MAX = 0.01 lot

Recovery straddle:
  FIXED = 0.03 lot

Initial Straddle SL:
  Straddle's OWN breakeven.

Basket monitoring:
  Continuously calculate main floating P/L + straddle floating P/L
  minus applicable costs.

When basket floating reaches >= 0:
  1. Move Straddle SL to the basket-neutral protection level.
  2. Confirm the SL modification.
  3. Close the original losing main trade.
  4. Keep the 0.03 straddle running as the profit runner.
  5. Trail the straddle SL only in the profitable direction.

The straddle's own profit must NOT independently close the recovery
while the basket remains negative.

LIVE SETUP
----------
Copy ALL files in this folder to:
  <MT5 Data Folder>/MQL5/Experts/

Then compile the EA and required scripts.

Attach the LIVE EA and the live brain/observer scripts according to
the README/inputs of the source. Scripts make decisions/data only;
the EA is the only trade execution authority.

Magic:
  26081401

Do NOT use this build in Strategy Tester. Use the separate backtest build.
