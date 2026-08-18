//+------------------------------------------------------------------+
//| Candle Level Revisit EA - Standalone Concept                     |
//| No NeoFL engine dependencies                                     |
//+------------------------------------------------------------------+
#property strict
#property version   "3.31"
#property description "Standalone M5 Bull/Bear candle-level strategy with CTrade execution, no initial SL, M1 trailing/reassessment and M5 fallback reassessment."

#include <Trade/Trade.mqh>

CTrade trade;

//--------------------------- Inputs ---------------------------------
input ENUM_TIMEFRAMES InpTimeframe          = PERIOD_M5;
input double          InpLots               = 0.10;
input ulong            InpMagic              = 26081401;
input int              InpDeviationPoints   = 20;
input ENUM_ORDER_TYPE_FILLING InpFillingMode = ORDER_FILLING_FOK;

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
// NOTE: Initial SL intentionally disabled. Risk/SL inputs are not used.
input double           InpRiskReward         = 2.0;
input int              InpSLBufferPoints     = 0; // UNUSED: SL removed by design
input int              InpExtremeBufferPts  = 0; // UNUSED: SL removed by design
input int              InpM5ATRPeriod        = 14;
input bool              InpAllowM1Origin        = true;
input double            InpM1OriginRiskFactor   = 0.50; // smaller lot than M5-origin trade
input int               InpM1OriginTolerancePts = 20;

input double           InpMinSL_ATR_Mult     = 0.00; // UNUSED: SL removed by design
input double           InpM1Trail_ATR_Mult   = 1.50;  // minimum M1 trailing distance


// Execution
input bool              InpOnePositionOnly   = true;
input bool              InpOneTradePerBar    = true;

input bool              InpUseMartingale        = true;
input double            InpMartingaleMultiplier = 2.0;
input int               InpMaxMartingaleSteps   = 5;
input double            InpMaxLot               = 10.0;

// M1 trailing / pullback reassessment
input bool              InpUseM1Trailing        = true;
input int               InpTrailingStartBarsM1  = 2;
input int               InpTrailingDistancePts  = 100;
input int               InpTrailingStepPts      = 20;
input bool              InpReassessAfterTrail   = true;
input int               InpM1ReassessWindowBars   = 5;
input int               InpM5ReassessWindowBars   = 10;


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

datetime g_m1_last_bar = 0;
ulong g_trailing_ticket = 0;
bool g_trailing_active = false;
double g_trailing_extreme = 0.0;
int g_martingale_step = 0;
LEVEL_TYPE g_last_trade_level_type = LEVEL_BREAKOUT_BULL;
double g_last_trade_level_price = 0.0;
bool g_last_trade_m1_origin = false;

bool g_m1_reassess_pending = false;
int g_m1_reassess_bars_left = 0;
bool g_m5_reassess_pending = false;
int g_m5_reassess_bars_left = 0;
ulong g_last_processed_exit_deal = 0;


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


double TradeLots()
{
   double lots = InpLots;
   if(InpUseMartingale && g_martingale_step > 0)
      lots *= MathPow(InpMartingaleMultiplier,
                      MathMin(g_martingale_step, InpMaxMartingaleSteps));

   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), InpMaxLot);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = vmin;

   lots = MathMax(vmin, MathMin(vmax, lots));
   lots = MathFloor(lots / step + 1e-9) * step;
   return NormalizeDouble(lots, 2);
}

bool SelectOurPosition(ulong &ticket)
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
      {
         ticket = t;
         return true;
      }
   }
   ticket = 0;
   return false;
}

void UpdateMartingale()
{
   if(!InpUseMartingale) return;
   if(!HistorySelect(TimeCurrent()-86400*30, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i=total-1; i>=0; --i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || deal == g_last_processed_exit_deal) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(deal, DEAL_SWAP)
                 + HistoryDealGetDouble(deal, DEAL_COMMISSION);

      if(pnl < 0.0)
         g_martingale_step = MathMin(g_martingale_step + 1, InpMaxMartingaleSteps);
      else if(pnl > 0.0)
         g_martingale_step = 0;

      g_last_processed_exit_deal = deal;
      break;
   }
}

void ManageM1Trailing()
{
   if(!InpUseM1Trailing) return;

   ulong ticket=0;
   if(!SelectOurPosition(ticket))
   {
      g_trailing_ticket=0;
      g_trailing_active=false;
      g_trailing_extreme=0.0;
      return;
   }

   if(ticket!=g_trailing_ticket)
   {
      g_trailing_ticket=ticket;
      g_trailing_active=false;
      g_trailing_extreme=0.0;
   }

   datetime open_time=(datetime)PositionGetInteger(POSITION_TIME);
   int bars_open=iBarShift(_Symbol,PERIOD_M1,open_time,false);

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double current=buy?bid:ask;
   double profit=PositionGetDouble(POSITION_PROFIT);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);

   // Activate only after the configured M1 bars and while profitable.
   if(!g_trailing_active && bars_open>=InpTrailingStartBarsM1 && profit>0.0)
   {
      g_trailing_active=true;
      g_trailing_extreme=current;
   }

   if(!g_trailing_active) return;

   double fixed_dist=InpTrailingDistancePts*PointValue();
   double m1_atr=GetATR(PERIOD_M1,InpM5ATRPeriod);
   double atr_dist=(m1_atr>0.0?m1_atr*InpM1Trail_ATR_Mult:0.0);
   double dist=MathMax(fixed_dist,atr_dist);
   double step=InpTrailingStepPts*PointValue();

   if(buy)
   {
      if(current>g_trailing_extreme) g_trailing_extreme=current;

      double trail=NormalizePrice(g_trailing_extreme-dist);

      // HARD RULE: BUY trailing SL can never be below entry.
      if(trail<entry) return;

      if(current<=trail)
      {
         if(trade.PositionClose(ticket))
         {
            g_m1_reassess_pending=InpReassessAfterTrail;
            g_m1_reassess_bars_left=InpM1ReassessWindowBars;
            g_m5_reassess_pending=false;
            g_m5_reassess_bars_left=0;
         }
         return;
      }

      if((sl==0.0 || trail>sl+step) && trail<current)
         trade.PositionModify(ticket,trail,tp);
   }
   else
   {
      if(g_trailing_extreme==0.0 || current<g_trailing_extreme)
         g_trailing_extreme=current;

      double trail=NormalizePrice(g_trailing_extreme+dist);

      // HARD RULE: SELL trailing SL can never be above entry.
      if(trail>entry) return;

      if(current>=trail)
      {
         if(trade.PositionClose(ticket))
         {
            g_m1_reassess_pending=InpReassessAfterTrail;
            g_m1_reassess_bars_left=InpM1ReassessWindowBars;
            g_m5_reassess_pending=false;
            g_m5_reassess_bars_left=0;
         }
         return;
      }

      if((sl==0.0 || trail<sl-step) && trail>current)
         trade.PositionModify(ticket,trail,tp);
   }
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
   // Only a fully CLOSED candle is ever passed here.
   double range=bar.high-bar.low;
   if(range<=0.0) return;

   double body=MathAbs(bar.close-bar.open);
   double upper=bar.high-MathMax(bar.open,bar.close);
   double lower=MathMin(bar.open,bar.close)-bar.low;

   double total=(upper+lower)/range;
   double upper_ratio=upper/range;
   double lower_ratio=lower/range;
   double body_ratio=body/range;

   bool bull=(bar.close>bar.open);
   bool bear=(bar.close<bar.open);
   bool neutral=(bar.close==bar.open);

   // Wickless: OPEN is the future breakout level; Bull/Bear sets direction.
   // Neutral/Doji candles never create breakout levels.
   if(body>0.0 && total<=InpWicklessRatio && body_ratio>=InpMinBodyRatio)
   {
      if(bull) AddLevel(LEVEL_BREAKOUT_BULL,bar.open,bar,shift);
      else if(bear) AddLevel(LEVEL_BREAKOUT_BEAR,bar.open,bar,shift);
      return;
   }

   // Wicked candles: Bull/Bear body + dominant wick define the rejection.
   // Neutral/Doji candles are ignored.
   if(neutral) return;

   if(lower_ratio>=InpWickedEndRatio && lower>upper)
      AddLevel(LEVEL_REVERSAL_LOW,bar.low,bar,shift);

   if(upper_ratio>=InpWickedEndRatio && upper>lower)
      AddLevel(LEVEL_REVERSAL_HIGH,bar.high,bar,shift);
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

bool ReversalSignal(const Level &L,const MqlRates &bar,const MqlRates &prev)
{
   // bar and prev are completed candles only.
   // MT5 terminology: Bull = Close > Open, Bear = Close < Open.
   double tol=InpTolerancePoints*PointValue();
   double range=bar.high-bar.low;
   if(range<=0.0) return false;

   double upper=bar.high-MathMax(bar.open,bar.close);
   double lower=MathMin(bar.open,bar.close)-bar.low;
   bool bull=(bar.close>bar.open);
   bool bear=(bar.close<bar.open);

   if(L.type==LEVEL_REVERSAL_HIGH)
   {
      bool approached=(prev.close<L.price-tol);
      bool touched=(bar.high>=L.price-tol);
      bool bearish_rejection=bear &&
                              upper/range>=InpWickedEndRatio &&
                              upper>lower;
      return approached && touched && bearish_rejection;
   }

   if(L.type==LEVEL_REVERSAL_LOW)
   {
      bool approached=(prev.close>L.price+tol);
      bool touched=(bar.low<=L.price+tol);
      bool bullish_rejection=bull &&
                              lower/range>=InpWickedEndRatio &&
                              lower>upper;
      return approached && touched && bullish_rejection;
   }
   return false;
}


double GetATR(const ENUM_TIMEFRAMES timeframe, const int period)
{
   if(period <= 0)
      return 0.0;

   int handle = iATR(_Symbol, timeframe, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buffer[];
   ArrayResize(buffer, 1);

   double value = 0.0;
   if(CopyBuffer(handle, 0, 1, 1, buffer) == 1)
      value = buffer[0];

   IndicatorRelease(handle);
   return value;
}

bool CalculateStopsAndTarget(const Level &L,
                             const bool buy,
                             const double entry,
                             double &sl,
                             double &tp)
{
   // NO STOP LOSS BY DESIGN.
   // The strategy trusts the candle/level thesis and allows the trade to
   // remain open until TP or the M1 trailing/pullback management closes it.

   sl = 0.0;

   double point = PointValue();

   // There is no SL, therefore there is no literal "R".
   // For the fixed-R mode, use the source M5 candle range as the
   // strategy's target-distance unit.
   double source_range = L.source_high - L.source_low;

   // Keep a volatility-aware minimum target distance so a tiny source
   // candle does not create an insignificant TP.
   double atr = GetATR(PERIOD_M5, InpM5ATRPeriod);
   double target_unit = source_range;

   if(atr > 0.0)
      target_unit = MathMax(target_unit, atr);

   if(target_unit <= 0.0)
      return false;

   double fixed_tp = buy
                   ? entry + InpRiskReward * target_unit
                   : entry - InpRiskReward * target_unit;

   // Opposing levels remain available as an alternative TP model.
   double opposing = FindNextOpposingLevel(L.type, entry, 0.0);

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

   // Broker minimum TP distance only; there is intentionally no SL.
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
   trade.SetTypeFilling(InpFillingMode);

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
      ok = trade.Buy(TradeLots(), _Symbol, 0.0, sl, tp, comment);
   else
      ok = trade.Sell(TradeLots(), _Symbol, 0.0, sl, tp, comment);

   if(ok)
   {
      g_last_trade_bar = bar_time;
      g_last_trade_level_type = L.type;
      g_last_trade_level_price = L.price;
      g_m1_reassess_pending = false;
      g_m5_reassess_pending = false;
      return true;
   }

   Print("Trade failed. Retcode=", trade.ResultRetcode(),
         " ", trade.ResultRetcodeDescription());
   return false;
}



bool M1PriceInsideM5Range(const double price, const MqlRates &m5)
{
   double tol = InpM1OriginTolerancePts * PointValue();
   return (price >= m5.low - tol && price <= m5.high + tol);
}

double M1OriginLots()
{
   double lots = TradeLots() * InpM1OriginRiskFactor;

   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), InpMaxLot);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = vmin;

   lots = MathMax(vmin, MathMin(vmax, lots));
   lots = MathFloor(lots / step + 1e-9) * step;
   return NormalizeDouble(lots, 2);
}

// M1 is allowed to originate a trade ONLY when its signal level is
// physically inside the range of the last CLOSED M5 candle.
// It does not replace the M5 engine; it is a lower-risk sub-entry.
bool EvaluateM1Origin()
{
   if(!InpAllowM1Origin)
      return false;

   MqlRates m1[];
   ArrayResize(m1, 3);
   ArraySetAsSeries(m1, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 3, m1) < 3)
      return false;

   MqlRates m5[];
   ArrayResize(m5, 2);
   ArraySetAsSeries(m5, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, 2, m5) < 2)
      return false;

   // Only the LAST CLOSED M1 candle is analyzed.
   MqlRates c = m1[1];
   double range = c.high - c.low;
   if(range <= 0.0)
      return false;

   double body = MathAbs(c.close - c.open);
   double upper = c.high - MathMax(c.open, c.close);
   double lower = MathMin(c.open, c.close) - c.low;

   bool bull = c.close > c.open;
   bool bear = c.close < c.open;
   bool neutral = c.close == c.open;

   if(neutral)
      return false;

   // M1-origin signals must be wickless or a clean rejection, but their
   // level must remain inside the last CLOSED M5 range.
   bool wickless = (body > 0.0 &&
                    (upper + lower) / range <= InpWicklessRatio &&
                    body / range >= InpMinBodyRatio);

   if(wickless)
   {
      if(!M1PriceInsideM5Range(c.open, m5[1]))
         return false;

      Level temp;
      temp.type = bull ? LEVEL_BREAKOUT_BULL : LEVEL_BREAKOUT_BEAR;
      temp.price = c.open;
      temp.source_time = c.time;
      temp.source_high = c.high;
      temp.source_low = c.low;
      temp.active = true;

      double entry = bull ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // M1-origin entry is deliberately smaller risk.
      trade.SetExpertMagicNumber(InpMagic);
      trade.SetDeviationInPoints(InpDeviationPoints);
      trade.SetTypeFilling(InpFillingMode);

      double tp = 0.0;
      double m1_unit = MathMax(range, GetATR(PERIOD_M1, InpM5ATRPeriod));
      if(m1_unit <= 0.0)
         return false;

      tp = bull ? entry + InpRiskReward * m1_unit
                : entry - InpRiskReward * m1_unit;
      tp = NormalizePrice(tp);

      string comment = bull ? "CLVL M1-origin BUY" : "CLVL M1-origin SELL";

      bool ok = bull
                ? trade.Buy(M1OriginLots(), _Symbol, 0.0, 0.0, tp, comment)
                : trade.Sell(M1OriginLots(), _Symbol, 0.0, 0.0, tp, comment);

      if(!ok)
         return false;

      uint rc = trade.ResultRetcode();
      if(rc != TRADE_RETCODE_DONE &&
         rc != TRADE_RETCODE_DONE_PARTIAL &&
         rc != TRADE_RETCODE_PLACED)
         return false;

      g_last_trade_level_type = temp.type;
      g_last_trade_level_price = temp.price;
      g_last_trade_m1_origin = true;
      g_m1_reassess_pending = false;
      g_m5_reassess_pending = false;
      return true;
   }

   return false;
}

void ReassessTrailingSetupM1(const MqlRates &bar)
{
   // First stage: after an M1 trailing pullback, look only for the
   // original opportunity on M1. Do NOT immediately reassess the M5 level.
   if(!g_m1_reassess_pending || g_m1_reassess_bars_left <= 0)
      return;

   g_m1_reassess_bars_left--;

   // The original M5 level is still the structural anchor, but the
   // confirmation/re-entry test here is deliberately M1.
   MqlRates m1[];
   ArrayResize(m1, 3);
   ArraySetAsSeries(m1, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 3, m1) < 3)
      return;

   for(int i=0; i<ArraySize(g_levels); ++i)
   {
      if(!g_levels[i].active) continue;
      if(g_levels[i].type != g_last_trade_level_type) continue;
      if(!SamePrice(g_levels[i].price, g_last_trade_level_price)) continue;

      bool signal = false;
      bool buy = LevelTypeIsBullish(g_levels[i].type);

      if(g_levels[i].type == LEVEL_BREAKOUT_BULL ||
         g_levels[i].type == LEVEL_BREAKOUT_BEAR)
      {
         signal = BreakoutSignal(g_levels[i], m1[1]);
      }
      else
      {
         signal = ReversalSignal(g_levels[i], m1[1], m1[2]);
      }

      if(signal && ExecuteSignal(g_levels[i], buy))
      {
         g_levels[i].active = false;
         g_m1_reassess_pending = false;
         return;
      }
   }

   // The fast M1 opportunity window is now gone.
   if(g_m1_reassess_bars_left <= 0)
   {
      g_m1_reassess_pending = false;
      if(InpM5ReassessWindowBars > 0)
      {
         g_m5_reassess_pending = true;
         g_m5_reassess_bars_left = InpM5ReassessWindowBars;
      }
   }
}

void ReassessTrailingSetupM5(const MqlRates &bar, const MqlRates &prev)
{
   // Second stage only: M5 reassessment is allowed AFTER the M1
   // opportunity window has expired.
   if(!g_m5_reassess_pending || g_m5_reassess_bars_left <= 0)
      return;

   g_m5_reassess_bars_left--;

   for(int i=0; i<ArraySize(g_levels); ++i)
   {
      if(!g_levels[i].active) continue;
      if(g_levels[i].type != g_last_trade_level_type) continue;
      if(!SamePrice(g_levels[i].price, g_last_trade_level_price)) continue;

      bool signal = false;
      bool buy = LevelTypeIsBullish(g_levels[i].type);

      if(g_levels[i].type == LEVEL_BREAKOUT_BULL ||
         g_levels[i].type == LEVEL_BREAKOUT_BEAR)
      {
         signal = BreakoutSignal(g_levels[i], bar);
      }
      else
      {
         signal = ReversalSignal(g_levels[i], bar, prev);
      }

      if(signal && ExecuteSignal(g_levels[i], buy))
      {
         g_levels[i].active = false;
         g_m5_reassess_pending = false;
         return;
      }
   }

   if(g_m5_reassess_bars_left <= 0)
      g_m5_reassess_pending = false;
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
   // Signal engine: M5. Trade management and post-trail reassessment: M1.
   ManageM1Trailing();

   // M1 opportunity-window reassessment has priority.
   datetime m1_bar = iTime(_Symbol, PERIOD_M1, 0);
   if(m1_bar != 0 && m1_bar != g_m1_last_bar)
   {
      g_m1_last_bar = m1_bar;

      MqlRates m1rates[];
      ArrayResize(m1rates, 3);
      ArraySetAsSeries(m1rates, true);
      if(CopyRates(_Symbol, PERIOD_M1, 0, 3, m1rates) >= 3)
      {
         if(!HasOpenPosition())
            EvaluateM1Origin();

         ReassessTrailingSetupM1(m1rates[1]);
      }
   }

   // Normal strategy and slower fallback reassessment remain M5.
   datetime current_bar = iTime(_Symbol, InpTimeframe, 0);
   if(current_bar == 0 || current_bar == g_last_bar_time)
      return;

   g_last_bar_time = current_bar;

   MqlRates rates[];
   ArrayResize(rates, 3);
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTimeframe, 0, 3, rates) < 3)
      return;

   UpdateMartingale();
   AgeAndInvalidateLevels(1);
   UpdateRevisitState(rates[1]);

   EvaluateSignals(rates[1], rates[2]);

   // M5 reassessment is ONLY the fallback after the M1 opportunity window.
   ReassessTrailingSetupM5(rates[1], rates[2]);

   // The completed M5 candle creates levels only after existing levels are evaluated.
   ClassifyAndCreateLevels(rates[1], 1);
}
