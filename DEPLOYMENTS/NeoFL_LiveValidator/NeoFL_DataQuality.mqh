//+------------------------------------------------------------------+
//| NeoFL_DataQuality.mqh                                            |
//| Core module. Data quality states and the decision-provenance      |
//| record every engine emits. No trading logic.                     |
//+------------------------------------------------------------------+
//
// Canon: every data source carries an explicit quality state, and missing data
// must never be silently fabricated.
//
//     DATA_UNAVAILABLE -> NO SIGNAL / NO TRADE      not:   missing -> guess -> trade
//
// Decision D-002: the AI's job is to verify the engines are processing data
// correctly. That is only possible if a decision carries enough to re-derive it --
// its inputs, the data quality behind them, the conclusion, and the reason.
//
// A bare boolean is not verifiable. An engine that returns false when it should
// and an engine that returns false always look identical from outside. So every
// engine records WHY, including why it declined to act.
//
//     "no trade: ATR 18 points, below minimum 50"   verifiable
//     (silence)                                      indistinguishable from broken
//
#ifndef __NEOFL_DATA_QUALITY_MQH__
#define __NEOFL_DATA_QUALITY_MQH__

//--- Quality of a data source at the moment it was read.
enum ENUM_NEOFL_DATA_QUALITY
{
   NEOFL_DATA_OK          = 0,  // fresh, complete, usable
   NEOFL_DATA_DELAYED     = 1,  // usable but older than the freshness budget
   NEOFL_DATA_INCOMPLETE  = 2,  // fewer bars/fields than required
   NEOFL_DATA_UNAVAILABLE = 3,  // source returned nothing
   NEOFL_DATA_INVALID     = 4   // present but self-inconsistent (bad OHLC, zero point, ...)
};

//--- Whether a strategy may act on data of a given quality.
//    DELAYED is deliberately permitted: a slightly stale quote is a judgement call
//    for the consuming engine, which knows its own tolerance. Everything worse is
//    categorically unusable.
bool NeoFLData_IsTradable(const ENUM_NEOFL_DATA_QUALITY q)
{
   return q == NEOFL_DATA_OK || q == NEOFL_DATA_DELAYED;
}

string NeoFLData_QualityName(const ENUM_NEOFL_DATA_QUALITY q)
{
   switch(q)
   {
      case NEOFL_DATA_OK:          return "DATA_OK";
      case NEOFL_DATA_DELAYED:     return "DATA_DELAYED";
      case NEOFL_DATA_INCOMPLETE:  return "DATA_INCOMPLETE";
      case NEOFL_DATA_UNAVAILABLE: return "DATA_UNAVAILABLE";
      case NEOFL_DATA_INVALID:     return "DATA_INVALID";
   }
   return "DATA_UNKNOWN";
}

//--- What an engine concluded.
enum ENUM_NEOFL_VERDICT
{
   NEOFL_VERDICT_NONE     = 0,  // no conclusion reached yet
   NEOFL_VERDICT_PROCEED  = 1,  // conditions met
   NEOFL_VERDICT_DECLINE  = 2,  // conditions evaluated and not met -- normal, not an error
   NEOFL_VERDICT_BLOCKED  = 3,  // could not evaluate: data quality, session, or permission
   NEOFL_VERDICT_ERROR    = 4   // something genuinely went wrong
};

string NeoFLData_VerdictName(const ENUM_NEOFL_VERDICT v)
{
   switch(v)
   {
      case NEOFL_VERDICT_NONE:    return "NONE";
      case NEOFL_VERDICT_PROCEED: return "PROCEED";
      case NEOFL_VERDICT_DECLINE: return "DECLINE";
      case NEOFL_VERDICT_BLOCKED: return "BLOCKED";
      case NEOFL_VERDICT_ERROR:   return "ERROR";
   }
   return "UNKNOWN";
}

//+------------------------------------------------------------------+
//| Decision provenance (D-002).                                      |
//|                                                                   |
//| Every engine fills one of these on every meaningful decision --   |
//| including decisions to do nothing. This is what makes external    |
//| verification possible.                                            |
//+------------------------------------------------------------------+
struct NeoFLDecision
{
   string                   engine;      // which engine decided, e.g. "MarketData"
   string                   symbol;
   datetime                 at;          // when the decision was taken (server time)
   ENUM_NEOFL_VERDICT       verdict;
   ENUM_NEOFL_DATA_QUALITY  quality;     // quality of the data behind it
   string                   inputs;      // what it looked at, with values
   string                   reason;      // which rule or threshold fired
};

//--- Initialise a decision record. Call before filling it in.
void NeoFLDecision_Begin(NeoFLDecision &d, const string engine, const string symbol)
{
   d.engine  = engine;
   d.symbol  = symbol;
   d.at      = TimeCurrent();
   d.verdict = NEOFL_VERDICT_NONE;
   d.quality = NEOFL_DATA_UNAVAILABLE;
   d.inputs  = "";
   d.reason  = "";
}

//--- Record the outcome.
void NeoFLDecision_Set(NeoFLDecision &d,
                       const ENUM_NEOFL_VERDICT verdict,
                       const ENUM_NEOFL_DATA_QUALITY quality,
                       const string reason,
                       const string inputs = "")
{
   d.verdict = verdict;
   d.quality = quality;
   d.reason  = reason;
   if(inputs != "")
      d.inputs = inputs;
}

//--- One-line rendering, stable enough to parse downstream.
//    Deliberately includes DECLINE outcomes: an engine that never reports declining
//    is indistinguishable from an engine that has stopped working.
string NeoFLDecision_ToString(const NeoFLDecision &d)
{
   return StringFormat("[%s] %s %s quality=%s reason=\"%s\" inputs=\"%s\" at=%s",
                       d.engine,
                       d.symbol,
                       NeoFLData_VerdictName(d.verdict),
                       NeoFLData_QualityName(d.quality),
                       d.reason,
                       d.inputs,
                       TimeToString(d.at, TIME_DATE | TIME_SECONDS));
}

//--- Emit to the terminal log. The Observer Network (build step 9) will consume
//    these records; until it exists, the log is the transport.
void NeoFLDecision_Emit(const NeoFLDecision &d)
{
   Print(NeoFLDecision_ToString(d));
}

#endif // __NEOFL_DATA_QUALITY_MQH__
