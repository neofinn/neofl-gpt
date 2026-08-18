//+------------------------------------------------------------------+
//| NeoFL_Telemetry.mqh                                              |
//| Core module. Writes engine state out of MT5 so it can be observed.|
//| Writes files. Never reads commands. Never places orders.         |
//+------------------------------------------------------------------+
//
// This is the MT5 half of the bridge. Without it the terminal is opaque: the EA knows
// its own state and nothing outside can see it, which makes D-002 impossible -- an AI
// cannot verify engines are processing correctly if their processing never leaves the
// terminal.
//
// DIRECTION IS ONE-WAY, DELIBERATELY
// This module writes. It has no read path and no command path. Telemetry flowing out
// cannot become instructions flowing in, so connecting an observer can never grant it
// order authority (D-001). The absence of a read function here is the enforcement.
//
// WHY FILES RATHER THAN WebRequest
// WebRequest needs each URL allow-listed by hand in Tools -> Options, and it BLOCKS the
// calling thread. On the tick path that is a latency risk for no benefit. Files in the
// MQL5/Files sandbox need no permission, never block meaningfully, and survive the
// consumer being offline -- the reader catches up later instead of losing the window.
//
// FAILURE MUST NOT REACH TRADING
// Every function returns void or bool and swallows its own errors. If telemetry cannot
// be written, trading continues unaffected. Observation is not permitted to become a
// dependency of execution.
//
#ifndef __NEOFL_TELEMETRY_MQH__
#define __NEOFL_TELEMETRY_MQH__

#include "../NeoFL_DataValidation/NeoFL_DataQuality.mqh"

//--- Files land in <terminal>/MQL5/Files/NeoFL/ (or Common/Files with FILE_COMMON).
string NeoFLTel_Dir()          { return "NeoFL"; }
string NeoFLTel_EventFile()    { return NeoFLTel_Dir() + "\\events.jsonl"; }
string NeoFLTel_StateFile()    { return NeoFLTel_Dir() + "\\state.json"; }
string NeoFLTel_StateTmpFile() { return NeoFLTel_Dir() + "\\state.json.tmp"; }

//--- Minimal JSON string escaping. Reasons and symbols can contain quotes.
string NeoFLTel_Esc(const string s)
{
   string out = "";
   const int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      const ushort c = StringGetCharacter(s, i);
      if(c == '"')       out += "\\\"";
      else if(c == '\\') out += "\\\\";
      else if(c == '\n') out += "\\n";
      else if(c == '\r') out += "\\r";
      else if(c == '\t') out += "\\t";
      else if(c < 32)    out += " ";
      else               out += ShortToString(c);
   }
   return out;
}

string NeoFLTel_Kv(const string k, const string v)  { return "\"" + k + "\":\"" + NeoFLTel_Esc(v) + "\""; }
string NeoFLTel_Kn(const string k, const double v, const int d = 5)
{
   return "\"" + k + "\":" + DoubleToString(v, d);
}
string NeoFLTel_Ki(const string k, const long v)    { return "\"" + k + "\":" + IntegerToString(v); }

//+------------------------------------------------------------------+
//| Append one event as a JSON line.                                  |
//|                                                                   |
//| JSONL rather than a JSON array: appending is a single open/seek/  |
//| write, the file is never in a syntactically broken intermediate   |
//| state, and a reader can consume it line by line while it grows.   |
//+------------------------------------------------------------------+
bool NeoFLTel_Event(const string engine, const string symbol,
                    const string kind, const string detail,
                    const double value = 0.0)
{
   const int h = FileOpen(NeoFLTel_EventFile(),
                          FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
      return false;               // silent: telemetry never blocks trading

   FileSeek(h, 0, SEEK_END);
   const string line = "{"
      + NeoFLTel_Ki("ts", (long)TimeCurrent())            + ","
      + NeoFLTel_Ki("ts_gmt", (long)TimeGMT())            + ","
      + NeoFLTel_Kv("engine", engine)                     + ","
      + NeoFLTel_Kv("symbol", symbol)                     + ","
      + NeoFLTel_Kv("kind", kind)                         + ","
      + NeoFLTel_Kv("detail", detail)                     + ","
      + NeoFLTel_Kn("value", value, 5)
      + "}";
   FileWriteString(h, line + "\r\n");
   FileClose(h);
   return true;
}

//--- Emit a decision record (D-002) as an event.
bool NeoFLTel_Decision(const NeoFLDecision &d)
{
   const string detail = StringFormat("verdict=%s quality=%s reason=%s | inputs=%s",
                                      NeoFLData_VerdictName(d.verdict),
                                      NeoFLData_QualityName(d.quality),
                                      d.reason, d.inputs);
   return NeoFLTel_Event(d.engine, d.symbol, "DECISION", detail);
}

//+------------------------------------------------------------------+
//| Write a full state snapshot.                                      |
//|                                                                   |
//| Written to a temp file then renamed. A reader polling the real    |
//| file therefore sees either the previous complete snapshot or the  |
//| new complete one -- never a half-written file. Without this the   |
//| consumer would occasionally parse truncated JSON and, worse,      |
//| might treat the failure as "no data" rather than "bad read".      |
//+------------------------------------------------------------------+
bool NeoFLTel_State(const string symbol, const ulong magic)
{
   const int h = FileOpen(NeoFLTel_StateTmpFile(),
                          FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   //--- account
   string s = "{";
   s += NeoFLTel_Ki("ts", (long)TimeCurrent())                                   + ",";
   s += NeoFLTel_Kv("symbol", symbol)                                            + ",";
   s += NeoFLTel_Ki("magic", (long)magic)                                        + ",";
   s += "\"account\":{";
   s +=   NeoFLTel_Kv("currency", AccountInfoString(ACCOUNT_CURRENCY))           + ",";
   s +=   NeoFLTel_Kv("server", AccountInfoString(ACCOUNT_SERVER))               + ",";
   s +=   NeoFLTel_Ki("mode", AccountInfoInteger(ACCOUNT_TRADE_MODE))            + ",";
   s +=   NeoFLTel_Ki("margin_mode", AccountInfoInteger(ACCOUNT_MARGIN_MODE))    + ",";
   s +=   NeoFLTel_Kn("balance", AccountInfoDouble(ACCOUNT_BALANCE), 2)          + ",";
   s +=   NeoFLTel_Kn("equity", AccountInfoDouble(ACCOUNT_EQUITY), 2)            + ",";
   s +=   NeoFLTel_Kn("margin_free", AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2);
   s += "},";

   //--- market
   MqlTick tick;
   const bool got = SymbolInfoTick(symbol, tick);
   s += "\"market\":{";
   s +=   NeoFLTel_Kn("bid", got ? tick.bid : 0.0)                               + ",";
   s +=   NeoFLTel_Kn("ask", got ? tick.ask : 0.0)                               + ",";
   s +=   NeoFLTel_Ki("tick_time", got ? (long)tick.time : 0)                    + ",";
   s +=   NeoFLTel_Kn("contract", SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE), 2) + ",";
   s +=   NeoFLTel_Kn("tick_value", SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE))     + ",";
   s +=   NeoFLTel_Kn("tick_size", SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE));
   s += "},";

   //--- positions under this magic
   s += "\"positions\":[";
   int written = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;

      if(written > 0) s += ",";
      s += "{";
      s +=   NeoFLTel_Ki("ticket", (long)t)                                       + ",";
      s +=   NeoFLTel_Kv("type", PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL") + ",";
      s +=   NeoFLTel_Kn("volume", PositionGetDouble(POSITION_VOLUME), 2)         + ",";
      s +=   NeoFLTel_Kn("open", PositionGetDouble(POSITION_PRICE_OPEN))          + ",";
      s +=   NeoFLTel_Kn("sl", PositionGetDouble(POSITION_SL))                    + ",";
      s +=   NeoFLTel_Kn("tp", PositionGetDouble(POSITION_TP))                    + ",";
      s +=   NeoFLTel_Kn("profit", PositionGetDouble(POSITION_PROFIT), 2)         + ",";
      s +=   NeoFLTel_Kn("swap", PositionGetDouble(POSITION_SWAP), 2)             + ",";
      s +=   NeoFLTel_Kv("comment", PositionGetString(POSITION_COMMENT));
      s += "}";
      written++;
   }
   s += "]";
   s += "}";

   FileWriteString(h, s);
   FileClose(h);

   // Replace atomically. FileMove needs the destination gone first on some builds.
   FileDelete(NeoFLTel_StateFile());
   if(!FileMove(NeoFLTel_StateTmpFile(), 0, NeoFLTel_StateFile(), FILE_REWRITE))
      return false;
   return true;
}

#endif // __NEOFL_TELEMETRY_MQH__
