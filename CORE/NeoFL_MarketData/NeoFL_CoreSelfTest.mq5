//+------------------------------------------------------------------+
//| NeoFL_CoreSelfTest.mq5                                           |
//| SCRIPT: exercises the Core data/session engines on this terminal. |
//| Places NO orders. Read-only. Safe to run any time.               |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property script_show_inputs
#property description "Checks NeoFL market data, session timing and data quality against this broker. Places no orders."

#include "NeoFL_MarketData.mqh"
#include "../NeoFL_Session/NeoFL_Session.mqh"
#include "../NeoFL_SymbolResolver/NeoFL_SymbolResolver.mqh"
#include "../NeoFL_Calendar/NeoFL_Calendar.mqh"
#include "../NeoFL_Session/NeoFL_GlobalSessions.mqh"

input string InpTestSymbol = "";  // blank = use the chart symbol

int g_pass = 0;
int g_fail = 0;

void Check(const bool condition, const string label, const string detail = "")
{
   if(condition) { g_pass++; PrintFormat("  PASS  %s%s", label, detail == "" ? "" : "  " + detail); }
   else          { g_fail++; PrintFormat("  FAIL  %s%s", label, detail == "" ? "" : "  " + detail); }
}

void OnStart()
{
   const string symbol = (InpTestSymbol == "" ? _Symbol : InpTestSymbol);

   Print("=====================================================");
   Print("  NeoFL Core - self test on ", symbol);
   Print("=====================================================");

   //--------------------------------------------------------------
   Print("[1] Session engine - US timing derived from GMT, not server time");

   const datetime gmt     = TimeGMT();
   const datetime eastern = NeoFLSess_GmtToEastern(gmt);
   PrintFormat("  server=%s  gmt=%s  eastern=%s  dst=%s",
               TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
               TimeToString(gmt,           TIME_DATE | TIME_MINUTES),
               TimeToString(eastern,       TIME_DATE | TIME_MINUTES),
               NeoFLSess_IsUsDst(gmt) ? "yes" : "no");

   // DST boundaries are fixed calendar rules, so they can be asserted outright.
   // 2026: DST starts Sun 8 March, ends Sun 1 November.
   MqlDateTime t; ZeroMemory(t);
   t.year = 2026; t.mon = 7; t.day = 1; t.hour = 12;
   Check(NeoFLSess_IsUsDst(StructToTime(t)), "July is DST");

   ZeroMemory(t); t.year = 2026; t.mon = 1; t.day = 15; t.hour = 12;
   Check(!NeoFLSess_IsUsDst(StructToTime(t)), "January is not DST");

   Check(NeoFLSess_NthWeekdayOfMonth(2026, 3, 0, 2) == 8,
         "second Sunday of March 2026 is the 8th",
         StringFormat("got %d", NeoFLSess_NthWeekdayOfMonth(2026, 3, 0, 2)));
   Check(NeoFLSess_NthWeekdayOfMonth(2026, 11, 0, 1) == 1,
         "first Sunday of November 2026 is the 1st",
         StringFormat("got %d", NeoFLSess_NthWeekdayOfMonth(2026, 11, 0, 1)));

   // Opening range = the FIRST M15 candle only (canon: not three).
   ZeroMemory(t); t.year = 2026; t.mon = 6; t.day = 10; t.hour = 9; t.min = 40;
   Check(!NeoFLSess_OpeningRangeComplete(StructToTime(t)),
         "09:40 ET - opening range still forming");
   ZeroMemory(t); t.year = 2026; t.mon = 6; t.day = 10; t.hour = 9; t.min = 45;
   Check(NeoFLSess_OpeningRangeComplete(StructToTime(t)),
         "09:45 ET - opening range complete");
   ZeroMemory(t); t.year = 2026; t.mon = 6; t.day = 13; t.hour = 11; t.min = 0;
   Check(!NeoFLSess_IsUsSessionOpenAt(StructToTime(t)),
         "Saturday - session closed");

   Print("  live session verdict:");
   NeoFLDecision sess = NeoFLSess_AssessUsSession(symbol);
   Print("    ", NeoFLDecision_ToString(sess));

   //--------------------------------------------------------------
   Print("");
   Print("[2] Symbol resolver against this broker");

   NeoFLInstrument inst;
   if(NeoFLSym_Resolve(symbol, inst))
      PrintFormat("  %s -> %s  base=%s quote=%s digits=%d point=%.5f tick=%.5f contract=%.1f",
                  symbol, NeoFLSym_AssetName(inst.asset_class), inst.base, inst.quote,
                  inst.digits, inst.point, inst.tick_size, inst.contract_size);
   else
      PrintFormat("  %s -> not a NeoFL instrument  [%s]", symbol, inst.reject_reason);

   //--------------------------------------------------------------
   Print("");
   Print("[3] Market data - quality is reported, never assumed");

   const NeoFLQuote q = NeoFLMD_GetQuote(symbol);
   PrintFormat("  quote: ok=%s quality=%s bid=%.5f ask=%.5f spread=%.1fpts age=%ds %s",
               q.ok ? "yes" : "no", NeoFLData_QualityName(q.quality),
               q.bid, q.ask, q.spread_points, q.age_seconds, q.detail);

   const NeoFLBar m15 = NeoFLMD_GetBar(symbol, PERIOD_M15, 1);
   if(m15.ok)
      PrintFormat("  M15[1]: %s O=%.5f H=%.5f L=%.5f C=%.5f",
                  TimeToString(m15.time, TIME_DATE | TIME_MINUTES),
                  m15.open, m15.high, m15.low, m15.close);
   else
      PrintFormat("  M15[1]: unavailable [%s] %s",
                  NeoFLData_QualityName(m15.quality), m15.detail);

   // The forming bar must be refused: acting on a partial candle is almost never intended.
   const NeoFLBar forming = NeoFLMD_GetBar(symbol, PERIOD_M15, 0);
   Check(!forming.ok && forming.quality == NEOFL_DATA_INVALID,
         "shift=0 (forming bar) is refused", forming.detail);

   // A symbol that cannot exist must report UNAVAILABLE, not silently return zeros.
   const NeoFLBar bogus = NeoFLMD_GetBar("NOT_A_REAL_SYMBOL_XYZ", PERIOD_M15, 1);
   Check(!bogus.ok && bogus.quality == NEOFL_DATA_UNAVAILABLE,
         "nonexistent symbol reports DATA_UNAVAILABLE");
   Check(bogus.close == 0.0 && bogus.time == 0,
         "failed read returns zeroed values, never stale ones");

   // A lookback longer than available history must surface as INCOMPLETE.
   MqlRates deep[];
   string detail = "";
   const ENUM_NEOFL_DATA_QUALITY deepQ =
      NeoFLMD_GetBars(symbol, PERIOD_M15, 1, 500000, deep, detail);
   Check(deepQ != NEOFL_DATA_OK,
         "absurd lookback does not silently return fewer bars",
         StringFormat("%s: %s", NeoFLData_QualityName(deepQ), detail));

   Check(NeoFLData_IsTradable(NEOFL_DATA_OK) && NeoFLData_IsTradable(NEOFL_DATA_DELAYED),
         "OK and DELAYED are tradable");
   Check(!NeoFLData_IsTradable(NEOFL_DATA_UNAVAILABLE) &&
         !NeoFLData_IsTradable(NEOFL_DATA_INVALID) &&
         !NeoFLData_IsTradable(NEOFL_DATA_INCOMPLETE),
         "UNAVAILABLE, INVALID and INCOMPLETE are not tradable");

   //--------------------------------------------------------------
   Print("");
   Print("[4] Decision provenance (D-002) - what the AI observer reads");

   NeoFLDecision feed = NeoFLMD_AssessFeed(symbol, PERIOD_M15);
   Print("    ", NeoFLDecision_ToString(feed));

   NeoFLDecision blocked = NeoFLMD_AssessFeed("NOT_A_REAL_SYMBOL_XYZ", PERIOD_M15);
   Print("    ", NeoFLDecision_ToString(blocked));
   Check(blocked.verdict == NEOFL_VERDICT_BLOCKED,
         "unusable feed yields BLOCKED with a stated reason");
   Check(StringLen(blocked.reason) > 0,
         "every decision carries a reason - silence is not a valid outcome");

   //--------------------------------------------------------------
   Print("");
   Print("[5] Calendar - reachable, or knowingly blind?");

   string calDetail = "";
   const ENUM_NEOFL_DATA_QUALITY calQ = NeoFLCal_Probe(calDetail);
   PrintFormat("  probe: %s - %s", NeoFLData_QualityName(calQ), calDetail);

   NeoFLDecision cal = NeoFLCal_Assess(symbol);
   Print("    ", NeoFLDecision_ToString(cal));

   const int secs = NeoFLCal_SecondsToNextHighImpact();
   if(secs == -1)
      Print("  next high-impact: UNKNOWN - calendar not visible (expected in Strategy Tester)");
   else if(secs == INT_MAX)
      Print("  next high-impact: none scheduled in the lookahead window");
   else
      PrintFormat("  next high-impact: in %d seconds (%d minutes)", secs, secs / 60);

   // The distinction that matters: "cannot see" must never read as "all clear".
   Check(!(calQ == NEOFL_DATA_UNAVAILABLE && cal.verdict == NEOFL_VERDICT_PROCEED),
         "unreachable calendar never reports PROCEED");

   //--------------------------------------------------------------
   Print("");
   Print("[6] Global sessions (D-003) - gold trades Asian through American");

   const datetime nowGmt = TimeGMT();
   PrintFormat("  offsets now: Tokyo UTC%+.0f  London UTC%+.0f  NewYork UTC%+.0f",
               NeoFLGS_MarketOffset(NEOFL_MKT_TOKYO,   nowGmt),
               NeoFLGS_MarketOffset(NEOFL_MKT_LONDON,  nowGmt),
               NeoFLGS_MarketOffset(NEOFL_MKT_NEWYORK, nowGmt));
   PrintFormat("  gold phase now: %s", NeoFLGS_GoldDayPhase(nowGmt));
   Print("    ", NeoFLDecision_ToString(NeoFLGS_Assess(symbol)));

   // DST boundary dates are calendar facts; assert rather than recompute.
   Check(NeoFLGS_NthWeekday(2026, 3, 0, 2) == 8 && NeoFLGS_NthWeekday(2026, 11, 0, 1) == 1,
         "US DST 2026: 8 Mar -> 1 Nov");
   Check(NeoFLGS_LastWeekday(2026, 3, 0) == 29 && NeoFLGS_LastWeekday(2026, 10, 0) == 25,
         "EU DST 2026: 29 Mar -> 25 Oct");
   Check(NeoFLGS_LastWeekday(2027, 3, 0) == 28 && NeoFLGS_LastWeekday(2027, 10, 0) == 31,
         "EU DST 2027: 28 Mar -> 31 Oct");

   // The weeks a single-rule implementation gets wrong.
   const datetime mar20 = NeoFLGS_Gmt(2026, 3, 20, 12);
   Check(NeoFLGS_IsDst(NEOFL_DST_US, mar20) && !NeoFLGS_IsDst(NEOFL_DST_EU, mar20),
         "20 Mar 2026: US on DST, EU not yet - offsets diverge");
   const datetime oct28 = NeoFLGS_Gmt(2026, 10, 28, 12);
   Check(NeoFLGS_IsDst(NEOFL_DST_US, oct28) && !NeoFLGS_IsDst(NEOFL_DST_EU, oct28),
         "28 Oct 2026: EU back to standard, US not yet");

   Check(!NeoFLGS_IsDst(NEOFL_DST_NONE, NeoFLGS_Gmt(2026, 7, 1, 12)),
         "Japan never observes DST");
   Check(NeoFLGS_IsDst(NEOFL_DST_AU, NeoFLGS_Gmt(2026, 1, 15, 12)) &&
         !NeoFLGS_IsDst(NEOFL_DST_AU, NeoFLGS_Gmt(2026, 7, 15, 12)),
         "Australia DST is inverted (southern hemisphere)");

   // Gold's day must span all three regions.
   Check(NeoFLGS_IsSessionOpen(NEOFL_SESSION_ASIAN,   NeoFLGS_Gmt(2026, 6, 10, 23)),
         "23:00 GMT - Asian session opens gold's day");
   Check(NeoFLGS_InOverlap(NeoFLGS_Gmt(2026, 6, 10, 14)),
         "14:00 GMT - London/New York overlap (deepest liquidity)");
   Check(!NeoFLGS_GoldDayActive(NeoFLGS_Gmt(2026, 6, 13, 12)),
         "Saturday - gold day inactive");

   // Tokyo breaks for lunch; a venue model ignoring that reports absent liquidity.
   Check(!NeoFLGS_IsMarketOpen(NEOFL_MKT_TOKYO, NeoFLGS_Gmt(2026, 6, 10, 3)),
         "12:00 Tokyo - lunch break observed");

   // Each index consults its own venue, never New York's by default.
   ENUM_NEOFL_MARKET venue;
   Check(NeoFLGS_IndexVenue("GER40", venue) && venue == NEOFL_MKT_FRANKFURT,
         "GER40 -> Frankfurt");
   Check(NeoFLGS_IndexVenue("JP225", venue) && venue == NEOFL_MKT_TOKYO,
         "JP225 -> Tokyo");
   Check(!NeoFLGS_IndexVenue("WHATEVER99", venue),
         "unknown index does not inherit New York hours");

   //--------------------------------------------------------------
   Print("");
   Print("=====================================================");
   PrintFormat("  RESULT: %d passed, %d failed", g_pass, g_fail);
   Print(g_fail == 0 ? "  ALL TESTS PASSED" : "  *** FAILURES PRESENT - DO NOT SHIP ***");
   Print("=====================================================");
}
