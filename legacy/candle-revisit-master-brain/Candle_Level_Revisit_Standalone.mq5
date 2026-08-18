//+------------------------------------------------------------------+
//| Candle Level Revisit EA - Standalone Concept                     |
//| No NeoFL engine dependencies                                     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Standalone candle-classification / level-revisit strategy."

#include <Trade/Trade.mqh>

CTrade trade;

//--------------------------- Inputs ---------------------------------
input ENUM_TIMEFRAMES InpTimeframe          = PERIOD_M1;
input double          InpLots               = 0.10;
input ulong            InpMagic              = 26081401;
input int              InpDeviationPoints   = 20;

// Candle classification
input double          InpWicklessRatio      = 0.15;  // total wick / range
input double          InpWickedEndRatio     = 0.40;  // one-side wick / range
input double          InpMinBodyRatio       = 0.70;  // wickless minimum body / range

// Level / revisit
input int             InpTolerancePoints    = 30;
input int             InpResetPoints        = 60;
input int             InpMaxLevelAgeBars    = 500;
input int             InpMaxLevels          = 200;

// Risk
enum ENUM_TP_MODE
{
   TP_FIXED_R = 0,
   TP_NEXT_OPPOSING_LEVEL = 1,
   TP_MIN_OF_BOTH = 2
};
input ENUM_TP_MODE     InpTPMode             = TP_FIXED_R;
input double           InpRiskReward         = 2.0;
input int              InpSLBufferPoints     = 10;
input int              InpExtremeBufferPts  = 10;

// Execution
input bool              InpOnePositionOnly   = true;
input bool              InpOneTradePerBar    = true;

//--------------------------- Data -----------------------------------
enum LEVEL_TYPE
{
   LEVEL_BREAKOUT_BULL = 0,
   LEVEL_BREAKOUT_BEAR = 1,
   LEVEL_REVERSAL_HIGH = 2,
   LEVEL_REVERSAL_LOW  = 3
};

struct Level
{
   bool       active;
   bool       revisited;
   bool       inside_zone;
   LEVEL_TYPE type;
   double     price;
   datetime   source_time;
   double     source_high;
   double     source_low;
   double     source_open;
   double     source_close;
   int        source_shift;
   int        revisit_count;
};

Level g_levels[];
datetime g_last_bar_time = 0;
datetime g_last_trade_bar = 0;

//--------------------------- Helpers --------------------------------
double PointValue()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

bool IsBullish(const double o, const double c) { return c > o; }
bool IsBearish(const double o, const double c) { return c < o; }

bool HasOpenPosition()
{
   if(!InpOnePositionOnly)
      return false;

   for(int i = PositionsTotal()-1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);

      if(sym == _Symbol && magic == InpMagic)
         return true;
   }
   return false;
}

bool SamePrice(const double a, const double b)
{
   return MathAbs(a-b) <= InpTolerancePoints * PointValue();
}

bool LevelTypeIsBullish(const LEVEL_TYPE t)
{
   return (t == LEVEL_BREAKOUT_BULL || t == LEVEL_REVERSAL_LOW);
}

bool LevelTypeIsBearish(const LEVEL_TYPE t)
{
   return (t == LEVEL_BREAKOUT_BEAR || t == LEVEL_REVERSAL_HIGH);
}

bool IsOpposing(const LEVEL_TYPE trade_type, const LEVEL_TYPE candidate)
{
   if(LevelTypeIsBullish(trade_type))
      return LevelTypeIsBearish(candidate);
   return LevelTypeIsBullish(candidate);
}

// Return nearest opposing level in the intended profit direction.
double FindNextOpposingLevel(const LEVEL_TYPE trade_type,
                              const double entry,
                              const double sl)
{
   bool buy = LevelTypeIsBullish(trade_type);
   double best = 0.0;
   bool found = false;

   for(int i=0; i<ArraySize(g_levels); ++i)
   {
      if(!g_levels[i].active)
         continue;

      if(!IsOpposing(trade_type, g_levels[i].type))
         continue;

      double p = g_levels[i].price;

      if(buy)
      {
         if(p <= entry)
            continue;
         if(!found || p < best)
         {
            best = p;
            found = true;
         }
      }
      else
      {
         if(p >= entry)
            continue;
         if(!found || p > best)
         {
            best = p;
            found = true;
         }
      }
   }

   if(!found)
      return 0.0;

   // Ensure target is actually on the profit side of the entry.
   if(buy && best <= entry)
      return 0.0;
   if(!buy && best >= entry)
      return 0.0;

   return best;
}

void RemoveOldestInactiveOrOldest()
{
   int n = ArraySize(g_levels);
   if(n <= 0)
      return;

   int idx = -1;
   datetime oldest = D'2099.01.01';

   // First remove inactive.
   for(int i=0; i<n; ++i)
   {
      if(!g_levels[i].active)
      {
         idx = i;
         break;
      }
   }

   // Otherwise remove oldest.
   if(idx < 0)
   {
      oldest = D'2099.01.01';
      for(int i=0; i<n; ++i)
      {
         if(g_levels[i].source_time < oldest)
         {
            oldest = g_levels[i].source_time;
            idx = i;
         }
      }
   }

   if(idx >= 0)
   {
      for(int j=idx; j<n-1; ++j)
         g_levels[j] = g_levels[j+1];

      ArrayResize(g_levels, n-1);
   }
}

void AddLevel(const LEVEL_TYPE type,
              const double price,
              const MqlRates &bar,
              const int source_shift)
{
   if(price <= 0.0)
      return;

   // Avoid duplicate active levels of the same type at essentially the same price.
   for(int i=0; i<ArraySize(g_levels); ++i)
   {
      if(g_levels[i].active &&
         g_levels[i].type == type &&
         SamePrice(g_levels[i].price, price))
         return;
   }

   if(ArraySize(g_levels) >= InpMaxLevels)
      RemoveOldestInactiveOrOldest();

   int n = ArraySize(g_levels);
   ArrayResize(g_levels, n+1);

   g_levels[n].active         = true;
   g_levels[n].revisited      = false;
   g_levels[n].inside_zone    = false;
   g_levels[n].type           = type;
   g_levels[n].price          = NormalizePrice(price);
   g_levels[n].source_time    = bar.time;
   g_levels[n].source_high    = bar.high;
   g_levels[n].source_low     = bar.low;
   g_levels[n].source_open    = bar.open;
   g_levels[n].source_close   = bar.close;
   g_levels[n].source_shift   = source_shift;
   g_levels[n].revisit_count  = 0;
}

void AgeAndInvalidateLevels(const int current_shift)
{
   double tol = InpTolerancePoints * PointValue();
   double reset = MathMax(InpResetPoints * PointValue(), tol);

   for(int i=0; i<ArraySize(g_levels); ++i)
   {
      if(!g_levels[i].active)
         continue;

      int age = current_shift - g_levels[i].source_shift;
      if(age > InpMaxLevelAgeBars)
      {
         g_levels[i].active = false;
         continue;
      }

      // Invalidation based on decisive close through the level against its
      // intended structure. This is intentionally conservative.
      double close1 = iClose(_Symbol, InpTimeframe, 1);
      if(close1 <= 0.0)
         continue;

      if(g_levels[i].type == LEVEL_REVERSAL_HIGH &&
         close1 > g_levels[i].price + tol)
      {
         g_levels[i].active = false;
         continue;
      }

      if(g_levels[i].type == LEVEL_REVERSAL_LOW &&
         close1 < g_levels[i].price - tol)
      {
         g_levels[i].active = false;
         continue;
      }

      if(g_levels[i].type == LEVEL_BREAKOUT_BULL &&
         close1 < g_levels[i].price - reset)
      {
         g_levels[i].active = false;
         continue;
      }

      if(g_levels[i].type == LEVEL_BREAKOUT_BEAR &&
         close1 > g_levels[i].price + reset)
      {
         g_levels[i].active = false;
         continue;
      }
   }
}

// Process one completed candle and create new levels from it.
void ClassifyAndCreateLevels(const MqlRates &bar, const int shift)
{
   double range = bar.high - bar.low;
   if(range <= 0.0)
      return;

   double body = MathAbs(bar.close - bar.open);
   double upper = bar.high - MathMax(bar.open, bar.close);
   double lower = MathMin(bar.open, bar.close) - bar.low;

   double total_wick_ratio = (upper + lower) / range;
   double upper_ratio = upper / range;
   double lower_ratio = lower / range;
   double body_ratio = body / range;

   // Wickless candle: use OPEN as breakout level.
   if(body > 0.0 &&
      total_wick_ratio <= InpWicklessRatio &&
      body_ratio >= InpMinBodyRatio)
   {
      if(IsBullish(bar.open, bar.close))
         AddLevel(LEVEL_BREAKOUT_BULL, bar.open, bar, shift);
      else if(IsBearish(bar.open, bar.close))
         AddLevel(LEVEL_BREAKOUT_BEAR, bar.open, bar, shift);
   }

   // Wicked candle: use the dominant wick extreme as reversal level.
   // "At one end specifically" means the qualifying wick must dominate.
   if(upper_ratio >= InpWickedEndRatio && upper > lower)
      AddLevel(LEVEL_REVERSAL_HIGH, bar.high, bar, shift);

   if(lower_ratio >= InpWickedEndRatio && lower > upper)
      AddLevel(LEVEL_REVERSAL_LOW, bar.low, bar, shift);
}

bool PriceInZone(const double price, const double level)
{
   return MathAbs(price-level) <= InpTolerancePoints * PointValue();
}

void UpdateRevisitState(const MqlRates &bar)
{
   double tol = InpTolerancePoints * PointValue();
   double reset = MathMax(InpResetPoints * PointValue(), tol);

   for(int i=0; i<ArraySize(g_levels); ++i)
   {
      if(!g_levels[i].active)
         continue;

      bool touched = (bar.high >= g_levels[i].price - tol &&
                      bar.low  <= g_levels[i].price + tol);

      if(touched)
      {
         if(!g_levels[i].inside_zone)
         {
            g_levels[i].revisit_count++;
            g_levels[i].revisited = true;
            g_levels[i].inside_zone = true;
         }
      }
      else
      {
         double dist = MathAbs(bar.close - g_levels[i].price);
         if(dist > reset)
            g_levels[i].inside_zone = false;
      }
   }
}

bool BreakoutSignal(const Level &L, const MqlRates &bar)
{
   if(!L.revisited)
      return false;

   double tol = InpTolerancePoints * PointValue();

   if(L.type == LEVEL_BREAKOUT_BULL)
      return (bar.close > L.price + tol);

   if(L.type == LEVEL_BREAKOUT_BEAR)
      return (bar.close < L.price - tol);

   return false;
}

bool ReversalSignal(const Level &L,
                    const MqlRates &bar,
                    const MqlRates &prev)
{
   double tol = InpTolerancePoints * PointValue();

   double range = bar.high - bar.low;
   if(range <= 0.0)
      return false;

   double body = MathAbs(bar.close - bar.open);
   double upper = bar.high - MathMax(bar.open, bar.close);
   double lower = MathMin(bar.open, bar.close) - bar.low;

   // Upper rejection: approach from below, trade into high, close bearish.
   if(L.type == LEVEL_REVERSAL_HIGH)
   {
      bool approached = (prev.close < L.price - tol);
      bool touched = (bar.high >= L.price - tol);
      bool rejection = (bar.close < bar.open &&
                        upper / range >= InpWickedEndRatio &&
                        upper > lower);

      return approached && touched && rejection;
   }

   // Lower rejection: approach from above, trade into low, close bullish.
   if(L.type == LEVEL_REVERSAL_LOW)
   {
      bool approached = (prev.close > L.price + tol);
      bool touched = (bar.low <= L.price + tol);
      bool rejection = (bar.close > bar.open &&
                        lower / range >= InpWickedEndRatio &&
                        lower > upper);

      return approached && touched && rejection;
   }

   return false;
}

bool CalculateStopsAndTarget(const Level &L,
                             const bool buy,
                             const double entry,
                             double &sl,
                             double &tp)
{
   double point = PointValue();
   double slbuf = InpSLBufferPoints * point;
   double exbuf = InpExtremeBufferPts * point;

   if(buy)
   {
      if(L.type == LEVEL_REVERSAL_LOW)
         sl = L.source_low - exbuf;
      else
         sl = MathMin(L.price - slbuf, L.source_low - exbuf);

      if(sl >= entry)
         return false;
   }
   else
   {
      if(L.type == LEVEL_REVERSAL_HIGH)
         sl = L.source_high + exbuf;
      else
         sl = MathMax(L.price + slbuf, L.source_high + exbuf);

      if(sl <= entry)
         return false;
   }

   sl = NormalizePrice(sl);

   double risk = MathAbs(entry-sl);
   if(risk <= 0.0)
      return false;

   double fixed_tp = buy ? entry + InpRiskReward*risk
                         : entry - InpRiskReward*risk;

   double opposing = FindNextOpposingLevel(L.type, entry, sl);

   if(InpTPMode == TP_FIXED_R || opposing <= 0.0)
   {
      tp = fixed_tp;
   }
   else if(InpTPMode == TP_NEXT_OPPOSING_LEVEL)
   {
      tp = opposing;
   }
   else
   {
      tp = buy ? MathMin(fixed_tp, opposing)
               : MathMax(fixed_tp, opposing);
   }

   // Make sure TP remains profitable and respects broker minimum distance.
   double stops_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   if(buy)
   {
      if(tp <= entry + stops_level)
         return false;
   }
   else
   {
      if(tp >= entry - stops_level)
         return false;
   }

   tp = NormalizePrice(tp);
   return true;
}

bool ExecuteSignal(const Level &L, const bool buy)
{
   if(InpOnePositionOnly && HasOpenPosition())
      return false;

   datetime bar_time = iTime(_Symbol, InpTimeframe, 1);
   if(InpOneTradePerBar && bar_time == g_last_trade_bar)
      return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0.0 || bid <= 0.0)
      return false;

   double entry = buy ? ask : bid;
   double sl = 0.0;
   double tp = 0.0;

   if(!CalculateStopsAndTarget(L, buy, entry, sl, tp))
      return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);

   string comment = "";
   switch(L.type)
   {
      case LEVEL_BREAKOUT_BULL: comment = "CLVL Breakout BUY"; break;
      case LEVEL_BREAKOUT_BEAR: comment = "CLVL Breakout SELL"; break;
      case LEVEL_REVERSAL_HIGH: comment = "CLVL Reversal SELL"; break;
      case LEVEL_REVERSAL_LOW:  comment = "CLVL Reversal BUY"; break;
   }

   bool ok = false;

   if(buy)
      ok = trade.Buy(InpLots, _Symbol, 0.0, sl, tp, comment);
   else
      ok = trade.Sell(InpLots, _Symbol, 0.0, sl, tp, comment);

   if(ok)
   {
      g_last_trade_bar = bar_time;
      return true;
   }

   Print("Trade failed. Retcode=", trade.ResultRetcode(),
         " ", trade.ResultRetcodeDescription());
   return false;
}

// Find and execute at most one signal on the completed candle.
void EvaluateSignals(const MqlRates &bar, const MqlRates &prev)
{
   for(int i=0; i<ArraySize(g_levels); ++i)
   {
      if(!g_levels[i].active)
         continue;

      bool signal = false;
      bool buy = false;

      if(g_levels[i].type == LEVEL_BREAKOUT_BULL ||
         g_levels[i].type == LEVEL_BREAKOUT_BEAR)
      {
         signal = BreakoutSignal(g_levels[i], bar);
         buy = (g_levels[i].type == LEVEL_BREAKOUT_BULL);
      }
      else
      {
         signal = ReversalSignal(g_levels[i], bar, prev);
         buy = (g_levels[i].type == LEVEL_REVERSAL_LOW);
      }

      if(signal)
      {
         if(ExecuteSignal(g_levels[i], buy))
         {
            // Consume the level after a successful entry.
            g_levels[i].active = false;
            return;
         }
      }
   }
}

//--------------------------- MT5 Events -------------------------------
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   ArrayResize(g_levels, 0);
   g_last_bar_time = iTime(_Symbol, InpTimeframe, 0);

   Print("Candle Level Revisit EA initialized. Standalone engine.");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   datetime current_bar = iTime(_Symbol, InpTimeframe, 0);
   if(current_bar == 0)
      return;

   if(current_bar == g_last_bar_time)
      return;

   g_last_bar_time = current_bar;

   MqlRates rates[3];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, InpTimeframe, 0, 3, rates) < 3)
      return;

   // rates[1] is the newly completed candle.
   // rates[2] is the candle before it.
   int current_shift = 1;

   AgeAndInvalidateLevels(current_shift);

   // First evaluate existing levels against the newly completed candle.
   UpdateRevisitState(rates[1]);
   EvaluateSignals(rates[1], rates[2]);

   // Only after evaluation do we create a level from this candle.
   // This guarantees a candle cannot revisit its own freshly-created level.
   ClassifyAndCreateLevels(rates[1], current_shift);
}
