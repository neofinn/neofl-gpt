//+------------------------------------------------------------------+
//| NeoFL_MarketData.mqh                                             |
//| Core module. Reads bars and ticks, and reports how trustworthy    |
//| the result is. Makes no trading decisions.                        |
//+------------------------------------------------------------------+
//
// Canon: the market data engine must know source, timestamp, symbol, timeframe,
// OHLC, spread, freshness and data quality -- so a strategy can decide whether it
// is able to act, rather than assuming the data it received is sound.
//
// The rule this module exists to enforce:
//
//     missing or stale data -> reported as such -> strategy declines
//     NOT: missing data -> silently return zeros -> strategy trades on nonsense
//
// Every accessor therefore returns a quality alongside the value. Callers that
// ignore quality will read zeros; callers that honour it cannot be fooled.
//
#ifndef __NEOFL_MARKET_DATA_MQH__
#define __NEOFL_MARKET_DATA_MQH__

#include "NeoFL_DataQuality.mqh"

//--- A closed bar plus the verdict on its trustworthiness.
struct NeoFLBar
{
   bool                     ok;
   datetime                 time;
   double                   open, high, low, close;
   long                     tick_volume;
   int                      shift;         // 1 = last closed bar
   ENUM_TIMEFRAMES          timeframe;
   ENUM_NEOFL_DATA_QUALITY  quality;
   string                   detail;        // why, when not OK
};

//--- Current market state.
struct NeoFLQuote
{
   bool                     ok;
   double                   bid, ask;
   double                   spread_points;
   datetime                 time;
   int                      age_seconds;   // how stale the tick is
   ENUM_NEOFL_DATA_QUALITY  quality;
   string                   detail;
};

//--- How old a tick may be before it is DELAYED rather than OK.
//    Deliberately generous: a quiet symbol legitimately goes seconds between ticks.
int NeoFLMD_FreshnessBudgetSeconds() { return 15; }

//+------------------------------------------------------------------+
//| Is a bar internally consistent? Catches broker/feed corruption    |
//| that would otherwise flow silently into strategy maths.           |
//+------------------------------------------------------------------+
bool NeoFLMD_BarIsSane(const MqlRates &r)
{
   if(r.time <= 0)                       return false;
   if(r.open <= 0.0 || r.close <= 0.0)   return false;
   if(r.high <= 0.0 || r.low   <= 0.0)   return false;
   if(r.high < r.low)                    return false;   // inverted range
   if(r.open > r.high || r.open < r.low) return false;   // open outside range
   if(r.close > r.high || r.close < r.low) return false; // close outside range
   return true;
}

//+------------------------------------------------------------------+
//| Read one closed bar. shift=1 is the most recent CLOSED bar;       |
//| shift=0 is the forming bar and is refused, because acting on a    |
//| partial candle is a decision the caller almost never means.       |
//+------------------------------------------------------------------+
NeoFLBar NeoFLMD_GetBar(const string symbol, const ENUM_TIMEFRAMES tf, const int shift)
{
   NeoFLBar b;
   b.ok          = false;
   b.time        = 0;
   b.open = b.high = b.low = b.close = 0.0;
   b.tick_volume = 0;
   b.shift       = shift;
   b.timeframe   = tf;
   b.quality     = NEOFL_DATA_UNAVAILABLE;
   b.detail      = "";

   if(shift < 1)
   {
      b.quality = NEOFL_DATA_INVALID;
      b.detail  = "shift 0 is the forming bar; ask for shift>=1 (closed bars only)";
      return b;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ResetLastError();
   const int copied = CopyRates(symbol, tf, shift, 1, rates);

   if(copied != 1)
   {
      b.quality = NEOFL_DATA_UNAVAILABLE;
      b.detail  = StringFormat("CopyRates returned %d for %s %s shift=%d (error %d); history may not be downloaded",
                               copied, symbol, EnumToString(tf), shift, GetLastError());
      return b;
   }

   if(!NeoFLMD_BarIsSane(rates[0]))
   {
      b.quality = NEOFL_DATA_INVALID;
      b.detail  = StringFormat("inconsistent bar O=%.5f H=%.5f L=%.5f C=%.5f",
                               rates[0].open, rates[0].high, rates[0].low, rates[0].close);
      return b;
   }

   b.ok          = true;
   b.time        = rates[0].time;
   b.open        = rates[0].open;
   b.high        = rates[0].high;
   b.low         = rates[0].low;
   b.close       = rates[0].close;
   b.tick_volume = rates[0].tick_volume;
   b.quality     = NEOFL_DATA_OK;
   b.detail      = "";
   return b;
}

//+------------------------------------------------------------------+
//| Read `count` consecutive closed bars starting at `shift`.         |
//| Reports INCOMPLETE rather than quietly returning fewer, so a      |
//| lookback that cannot be satisfied is visible instead of silently  |
//| shortened.                                                        |
//+------------------------------------------------------------------+
ENUM_NEOFL_DATA_QUALITY NeoFLMD_GetBars(const string symbol,
                                        const ENUM_TIMEFRAMES tf,
                                        const int shift,
                                        const int count,
                                        MqlRates &out[],
                                        string &detail)
{
   detail = "";

   if(shift < 1 || count < 1)
   {
      detail = "shift must be >=1 and count >=1";
      return NEOFL_DATA_INVALID;
   }

   ArraySetAsSeries(out, true);
   ResetLastError();
   const int copied = CopyRates(symbol, tf, shift, count, out);

   if(copied <= 0)
   {
      detail = StringFormat("CopyRates returned %d for %s %s (error %d)",
                            copied, symbol, EnumToString(tf), GetLastError());
      return NEOFL_DATA_UNAVAILABLE;
   }

   if(copied < count)
   {
      detail = StringFormat("requested %d bars, got %d for %s %s; insufficient history",
                            count, copied, symbol, EnumToString(tf));
      return NEOFL_DATA_INCOMPLETE;
   }

   for(int i = 0; i < copied; i++)
   {
      if(!NeoFLMD_BarIsSane(out[i]))
      {
         detail = StringFormat("inconsistent bar at index %d (time %s)",
                               i, TimeToString(out[i].time));
         return NEOFL_DATA_INVALID;
      }
   }

   return NEOFL_DATA_OK;
}

//+------------------------------------------------------------------+
//| Current quote, with staleness assessed rather than assumed.       |
//+------------------------------------------------------------------+
NeoFLQuote NeoFLMD_GetQuote(const string symbol)
{
   NeoFLQuote q;
   q.ok            = false;
   q.bid = q.ask   = 0.0;
   q.spread_points = 0.0;
   q.time          = 0;
   q.age_seconds   = 0;
   q.quality       = NEOFL_DATA_UNAVAILABLE;
   q.detail        = "";

   MqlTick tick;
   ResetLastError();
   if(!SymbolInfoTick(symbol, tick))
   {
      q.detail = StringFormat("SymbolInfoTick failed for %s (error %d)", symbol, GetLastError());
      return q;
   }

   if(tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid)
   {
      q.quality = NEOFL_DATA_INVALID;
      q.detail  = StringFormat("implausible quote bid=%.5f ask=%.5f", tick.bid, tick.ask);
      return q;
   }

   const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
   {
      q.quality = NEOFL_DATA_INVALID;
      q.detail  = "broker reports point size 0; cannot express spread in points";
      return q;
   }

   q.bid           = tick.bid;
   q.ask           = tick.ask;
   q.spread_points = (tick.ask - tick.bid) / point;
   q.time          = tick.time;
   q.age_seconds   = (int)(TimeCurrent() - tick.time);

   if(q.age_seconds > NeoFLMD_FreshnessBudgetSeconds())
   {
      q.ok      = true;   // usable, but the caller must decide
      q.quality = NEOFL_DATA_DELAYED;
      q.detail  = StringFormat("last tick %ds old, budget %ds",
                               q.age_seconds, NeoFLMD_FreshnessBudgetSeconds());
      return q;
   }

   q.ok      = true;
   q.quality = NEOFL_DATA_OK;
   return q;
}

//+------------------------------------------------------------------+
//| Assess the feed for a symbol and return a provenance record.      |
//| This is what an observer reads to answer "is the data feed        |
//| healthy and is this engine seeing it correctly?" (D-002).         |
//+------------------------------------------------------------------+
NeoFLDecision NeoFLMD_AssessFeed(const string symbol, const ENUM_TIMEFRAMES tf)
{
   NeoFLDecision d;
   NeoFLDecision_Begin(d, "MarketData", symbol);

   const NeoFLQuote q = NeoFLMD_GetQuote(symbol);
   if(!q.ok)
   {
      NeoFLDecision_Set(d, NEOFL_VERDICT_BLOCKED, q.quality,
                        "no usable quote: " + q.detail);
      return d;
   }

   const NeoFLBar b = NeoFLMD_GetBar(symbol, tf, 1);
   if(!b.ok)
   {
      NeoFLDecision_Set(d, NEOFL_VERDICT_BLOCKED, b.quality,
                        "no usable bar: " + b.detail,
                        StringFormat("bid=%.5f ask=%.5f", q.bid, q.ask));
      return d;
   }

   const string inputs = StringFormat("bid=%.5f ask=%.5f spread=%.1fpts tick_age=%ds %s_close=%.5f bar_time=%s",
                                      q.bid, q.ask, q.spread_points, q.age_seconds,
                                      EnumToString(tf), b.close,
                                      TimeToString(b.time, TIME_DATE | TIME_MINUTES));

   // Worst of the two qualities governs; a fresh bar does not redeem a stale tick.
   const ENUM_NEOFL_DATA_QUALITY worst = (q.quality > b.quality) ? q.quality : b.quality;

   if(worst == NEOFL_DATA_DELAYED)
      NeoFLDecision_Set(d, NEOFL_VERDICT_PROCEED, worst,
                        "feed usable but delayed: " + q.detail, inputs);
   else
      NeoFLDecision_Set(d, NEOFL_VERDICT_PROCEED, worst, "feed healthy", inputs);

   return d;
}

#endif // __NEOFL_MARKET_DATA_MQH__
