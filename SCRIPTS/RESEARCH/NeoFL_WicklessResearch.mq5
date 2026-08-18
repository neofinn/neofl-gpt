//+------------------------------------------------------------------+
//| NeoFL_WicklessResearch.mq5                                       |
//| SCRIPT: measures the wickless-revisit thesis on historical data.  |
//| Places NO orders. Reads history only.                            |
//+------------------------------------------------------------------+
//
// THESIS UNDER TEST
//   "Whenever a wickless candle is formed, when price revisits the wickless end,
//    a breakout comes."
//
// This script does not assume that. It measures it, using the SAME classification
// thresholds as the live engine, so the numbers describe the actual strategy rather
// than an idealised version of it.
//
// WHY A CONTROL MATTERS
//   A breakout rate of 60% sounds like an edge until you learn that entering the
//   OPPOSITE direction on the same signals also produces 60%, because price simply
//   leaves a level in one direction or the other. The control column below takes the
//   inverse trade on every identical signal. If both sides look the same, the shape of
//   the candle is telling you nothing and the apparent edge is the market's ordinary
//   two-sidedness.
//
// WHAT IS MEASURED
//   For every wickless level that gets revisited and then breaks out, the script walks
//   forward and records how far price travelled in favour (MFE) and against (MAE)
//   before the outcome resolved. Those two numbers, not the hit rate, decide whether a
//   strategy with no stop loss can survive on this signal.
//
#property strict
#property version   "1.00"
#property script_show_inputs
#property description "Measures the wickless-revisit thesis against historical data. Places no orders."

//--- Classification thresholds. Defaults mirror the live engine exactly.
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M5;
input int             InpBarsToScan       = 20000;
input double          InpWicklessRatio    = 0.15;  // (upper+lower)/range
input double          InpMinBodyRatio     = 0.70;  // body/range
input int             InpTolerancePoints  = 30;    // revisit zone and breakout margin
input int             InpMaxLevelAgeBars  = 500;   // level lifetime
//--- Outcome measurement
input int             InpForwardBars      = 60;    // how far forward to measure the result
input double          InpTargetR          = 1.0;   // "success" = MFE >= this x the breakout margin

//--- D-010: the level price is an UNRESOLVED Gold parameter. The engine uses the candle
//    OPEN. The owner's thesis says "the wickless END". For a perfectly clean candle these
//    are the same, but the 0.15 threshold permits a small wick on one end, so they can
//    differ. Both are measured here so the choice is made on evidence, not preference.
enum ENUM_LEVEL_BASIS
{
   LEVEL_BASIS_OPEN     = 0,  // candle open -- what the production engine uses today
   LEVEL_BASIS_CLEAN_END= 1,  // whichever end actually has no wick
   LEVEL_BASIS_BOTH     = 2   // run both and print them side by side
};
input ENUM_LEVEL_BASIS InpLevelBasis      = LEVEL_BASIS_BOTH;



struct Lvl
{
   double price;
   bool   bull;
   int    born;
   bool   revisited;
   bool   inside;
   bool   consumed;
};

double Pt() { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }

//+------------------------------------------------------------------+
//| The "actual wickless end" reading of the level.                   |
//|                                                                   |
//| A qualifying candle may still carry a small wick. The clean end is |
//| whichever side has less of one. On a perfectly clean candle this   |
//| returns the open, agreeing with production -- the two readings     |
//| only diverge on partially-wicked candles, which is exactly the     |
//| population worth measuring.                                        |
//+------------------------------------------------------------------+
double CleanEndPrice(const MqlRates &bar, const bool bull)
{
   const double upper = bar.high - MathMax(bar.open, bar.close);
   const double lower = MathMin(bar.open, bar.close) - bar.low;
   if(bull) return (lower <= upper) ? bar.open : bar.close;
   return (upper <= lower) ? bar.open : bar.close;
}

//--- Walk forward from a breakout and record excursion both ways.
void MeasureOutcome(const MqlRates &r[], const int at, const bool bull,
                    const double entry, double &mfe, double &mae)
{
   mfe = 0.0; mae = 0.0;
   // Series order: index 0 is newest, so forward in time is DECREASING index.
   const int stop = MathMax(0, at - InpForwardBars);
   for(int i = at - 1; i >= stop; i--)
   {
      const double fav = bull ? (r[i].high - entry) : (entry - r[i].low);
      const double adv = bull ? (entry - r[i].low)  : (r[i].high - entry);
      if(fav > mfe) mfe = fav;
      if(adv > mae) mae = adv;
   }
}

//--- One pass produces one of these.
struct RunResult
{
   string basis;
   int    wickless, revisited, broke, graded;
   int    win, ctl_win;
   double mfe, mae, ctl_mfe, ctl_mae;
};

//+------------------------------------------------------------------+
//| One full pass over history for a given level basis.               |
//+------------------------------------------------------------------+
RunResult RunPass(const MqlRates &r[], const int copied,
                  const ENUM_LEVEL_BASIS basis, const string label)
{
   RunResult R;
   R.basis = label;
   R.wickless = R.revisited = R.broke = R.graded = 0;
   R.win = R.ctl_win = 0;
   R.mfe = R.mae = R.ctl_mfe = R.ctl_mae = 0.0;

   const double tol = InpTolerancePoints * Pt();
   Lvl levels[];
   ArrayResize(levels, 0);

   for(int i = copied - 2; i >= 1; i--)
   {
      const MqlRates bar = r[i];
      const double range = bar.high - bar.low;
      if(range <= 0.0) continue;

      const double body  = MathAbs(bar.close - bar.open);
      const double upper = bar.high - MathMax(bar.open, bar.close);
      const double lower = MathMin(bar.open, bar.close) - bar.low;
      const bool   bull  = (bar.close > bar.open);
      const bool   bear  = (bar.close < bar.open);

      if(body > 0.0 && (upper + lower)/range <= InpWicklessRatio
         && body/range >= InpMinBodyRatio && (bull || bear))
      {
         Lvl L;
         L.price = (basis == LEVEL_BASIS_CLEAN_END) ? CleanEndPrice(bar, bull) : bar.open;
         L.bull = bull; L.born = i;
         L.revisited = false; L.inside = false; L.consumed = false;
         const int n = ArraySize(levels);
         ArrayResize(levels, n+1);
         levels[n] = L;
         R.wickless++;
      }

      for(int k = 0; k < ArraySize(levels); k++)
      {
         if(levels[k].consumed) continue;
         if(levels[k].born <= i) continue;
         if(levels[k].born - i > InpMaxLevelAgeBars) { levels[k].consumed = true; continue; }

         const bool touched = (bar.high >= levels[k].price - tol &&
                               bar.low  <= levels[k].price + tol);
         if(touched)
         {
            if(!levels[k].inside)
            {
               if(!levels[k].revisited) R.revisited++;
               levels[k].revisited = true;
               levels[k].inside = true;
            }
            continue;   // a bar inside the zone cannot also be the breakout bar
         }
         levels[k].inside = false;
         if(!levels[k].revisited) continue;

         const bool broke = levels[k].bull ? (bar.close > levels[k].price + tol)
                                           : (bar.close < levels[k].price - tol);
         if(!broke) continue;

         R.broke++;
         levels[k].consumed = true;

         double mfe = 0.0, mae = 0.0;
         MeasureOutcome(r, i, levels[k].bull, bar.close, mfe, mae);
         R.mfe += mfe; R.mae += mae; R.graded++;
         if(mfe >= tol * InpTargetR) R.win++;

         double cf = 0.0, ca = 0.0;
         MeasureOutcome(r, i, !levels[k].bull, bar.close, cf, ca);
         R.ctl_mfe += cf; R.ctl_mae += ca;
         if(cf >= tol * InpTargetR) R.ctl_win++;
      }
   }
   return R;
}

void Report(const RunResult &R)
{
   const double p = Pt();
   Print("");
   PrintFormat("  ---- LEVEL BASIS: %s ----", R.basis);
   PrintFormat("  wickless candles    %d", R.wickless);
   PrintFormat("  revisited           %d  (%.1f%%)", R.revisited,
               R.wickless>0 ? 100.0*R.revisited/R.wickless : 0.0);
   PrintFormat("  broke out           %d  (%.1f%% of revisits)", R.broke,
               R.revisited>0 ? 100.0*R.broke/R.revisited : 0.0);
   if(R.graded == 0) { Print("  no graded signals"); return; }
   PrintFormat("  %-20s %12s %14s", "", "THESIS", "CONTROL");
   PrintFormat("  %-20s %11.1f%% %13.1f%%", "reached target",
               100.0*R.win/R.graded, 100.0*R.ctl_win/R.graded);
   PrintFormat("  %-20s %12.1f %14.1f", "avg MFE (points)",
               R.mfe/R.graded/p, R.ctl_mfe/R.graded/p);
   PrintFormat("  %-20s %12.1f %14.1f", "avg MAE (points)",
               R.mae/R.graded/p, R.ctl_mae/R.graded/p);
   PrintFormat("  %-20s %12.2f %14.2f", "MFE/MAE",
               R.mae>0.0 ? R.mfe/R.mae : 0.0, R.ctl_mae>0.0 ? R.ctl_mfe/R.ctl_mae : 0.0);
}

void OnStart()
{
   Print("=====================================================");
   Print("  NeoFL wickless-revisit research  (no orders placed)");
   Print("=====================================================");

   MqlRates r[];
   ArraySetAsSeries(r, true);
   const int copied = CopyRates(_Symbol, InpTimeframe, 0, InpBarsToScan, r);
   if(copied < 200)
   {
      PrintFormat("  insufficient history: CopyRates returned %d. Download more bars first.", copied);
      return;
   }

   PrintFormat("  %s %s | %d bars | wick<=%.2f body>=%.2f tol=%dpts forward=%d",
               _Symbol, EnumToString(InpTimeframe), copied,
               InpWicklessRatio, InpMinBodyRatio, InpTolerancePoints, InpForwardBars);

   if(InpLevelBasis == LEVEL_BASIS_OPEN || InpLevelBasis == LEVEL_BASIS_BOTH)
      Report(RunPass(r, copied, LEVEL_BASIS_OPEN, "candle OPEN (production)"));
   if(InpLevelBasis == LEVEL_BASIS_CLEAN_END || InpLevelBasis == LEVEL_BASIS_BOTH)
      Report(RunPass(r, copied, LEVEL_BASIS_CLEAN_END, "actual WICKLESS END"));

   Print("");
   Print("  HOW TO READ THIS");
   Print("   - THESIS close to CONTROL means candle shape carries no directional");
   Print("     information; price simply leaves a level in one direction or the other.");
   Print("   - Compare the two BASIS blocks to settle open-vs-wickless-end on evidence.");
   Print("   - avg MAE matters more than hit rate: there is no stop loss, so MAE is");
   Print("     exactly what the recovery straddle must absorb.");
   Print("   - Research only. Per D-010 this must not silently change the production EA.");
   Print("=====================================================");
}
