//+------------------------------------------------------------------+
//| NeoFL_LiveValidator.mq5                                          |
//|                                                                  |
//| READ-ONLY. This EA places NO orders, modifies NO positions, and  |
//| has no trading code path whatsoever. It runs every NeoFL Core    |
//| engine against live broker data and shows what each computes.    |
//|                                                                  |
//| Purpose: validate the Core against a real feed BEFORE any        |
//| execution engine exists. If the numbers here are wrong, they     |
//| would be wrong with money behind them.                           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "NeoFL Core live validator. READ-ONLY - places no orders. Validates data, session, calendar, risk and straddle engines against live market data."

#include "NeoFL_DataQuality.mqh"
#include "NeoFL_SymbolResolver.mqh"
#include "NeoFL_MarketData.mqh"
#include "NeoFL_Session.mqh"
#include "NeoFL_GlobalSessions.mqh"
#include "NeoFL_Calendar.mqh"
#include "NeoFL_Risk.mqh"
#include "NeoFL_Straddle.mqh"

//--- Risk parameters. UNCONFIRMED pending product approval; nothing here trades,
//    so these only affect what the panel reports.
input group                    "Risk (reporting only - nothing is traded)"
input ENUM_NEOFL_RISK_MODEL    InpRiskModel        = NEOFL_RISK_PERCENT_EQUITY;
input double                   InpRiskPercent      = 1.0;
input double                   InpFixedLot         = 0.01;
input double                   InpHardMaxLot       = 0.01;   // legacy v3.85 rail
input double                   InpStopDistance     = 5.0;    // price units, for the sizing example

input group                    "Straddle (reporting only)"
input ENUM_NEOFL_STRADDLE_MODE InpStraddleMode     = NEOFL_STRADDLE_RATIO;
input double                   InpRecoveryRatio    = 2.0;    // RATIO: Vs = Vm*(n+1)
input double                   InpRecoveryDistance = 10.0;   // FIXED_DISTANCE: units past entry
input double                   InpStraddleMaxLot   = 0.00;   // 0 = uncapped
input double                   InpExampleGap       = 20.0;   // hypothetical adverse move

input group                    "Display"
input int                      InpRefreshSeconds   = 2;
input bool                     InpLogDecisions     = false;  // also write provenance to Experts log

ulong  g_magic = 26081401;   // matches the legacy live build, for position observation only
datetime g_lastRefresh = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("=====================================================");
   Print(" NeoFL Live Validator - READ ONLY, PLACES NO ORDERS");
   Print("=====================================================");

   // A hedging account is required by D-005. Report it; do not fail, since this
   // EA cannot trade either way and the operator should still see the diagnosis.
   const ENUM_ACCOUNT_MARGIN_MODE mode =
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   const bool hedging = (mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   PrintFormat(" account margin mode: %s%s",
               hedging ? "HEDGING" : "NETTING",
               hedging ? " (required by D-005 - OK)"
                       : " *** straddle recovery CANNOT run on netting ***");

   NeoFLInstrument inst;
   if(NeoFLSym_Resolve(_Symbol, inst))
      PrintFormat(" symbol %s resolved -> %s (base=%s quote=%s)",
                  _Symbol, NeoFLSym_AssetName(inst.asset_class), inst.base, inst.quote);
   else
      PrintFormat(" symbol %s NOT a NeoFL instrument: %s", _Symbol, inst.reject_reason);

   EventSetTimer(MathMax(1, InpRefreshSeconds));
   Refresh();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
   PrintFormat("NeoFL Live Validator stopped. reason=%d", reason);
}

//--- Timer rather than OnTick so the panel updates even on a quiet symbol.
void OnTimer() { Refresh(); }
void OnTick()  { /* intentionally empty - this EA never acts on a tick */ }

//+------------------------------------------------------------------+
string Line(const string label, const string value)
{
   return StringFormat("%-22s %s\n", label + ":", value);
}

void Refresh()
{
   const datetime gmt = TimeGMT();
   string s = "";

   s += "NeoFL LIVE VALIDATOR   (read-only - places no orders)\n";
   s += "-----------------------------------------------------\n";

   //--- Instrument -------------------------------------------------
   NeoFLInstrument inst;
   const bool resolved = NeoFLSym_Resolve(_Symbol, inst);
   s += Line("symbol", StringFormat("%s -> %s", _Symbol,
             resolved ? NeoFLSym_AssetName(inst.asset_class) : "REJECTED"));
   if(!resolved)
      s += Line("  reject reason", inst.reject_reason);

   //--- Market data ------------------------------------------------
   const NeoFLQuote q = NeoFLMD_GetQuote(_Symbol);
   s += Line("quote", q.ok
        ? StringFormat("%.*f / %.*f  spread %.1f pts  age %ds  [%s]",
                       inst.digits, q.bid, inst.digits, q.ask,
                       q.spread_points, q.age_seconds, NeoFLData_QualityName(q.quality))
        : StringFormat("UNAVAILABLE - %s", q.detail));

   const NeoFLBar m15 = NeoFLMD_GetBar(_Symbol, PERIOD_M15, 1);
   s += Line("M15[1] closed", m15.ok
        ? StringFormat("%s  C=%.*f", TimeToString(m15.time, TIME_MINUTES), inst.digits, m15.close)
        : StringFormat("[%s] %s", NeoFLData_QualityName(m15.quality), m15.detail));

   //--- Sessions ---------------------------------------------------
   s += "\n";
   s += Line("gold day phase", NeoFLGS_GoldDayPhase(gmt));
   s += Line("active sessions", NeoFLGS_ActiveSessions(gmt) == ""
             ? "(none)" : NeoFLGS_ActiveSessions(gmt));
   s += Line("offsets", StringFormat("Tokyo UTC%+.0f  London UTC%+.0f  NY UTC%+.0f",
             NeoFLGS_MarketOffset(NEOFL_MKT_TOKYO, gmt),
             NeoFLGS_MarketOffset(NEOFL_MKT_LONDON, gmt),
             NeoFLGS_MarketOffset(NEOFL_MKT_NEWYORK, gmt)));
   s += Line("US cash session", NeoFLSess_IsUsSessionOpenNow() ? "OPEN" : "closed");
   s += Line("opening range", NeoFLSess_OpeningRangeComplete(NeoFLSess_NowEastern())
             ? "complete (first M15 closed)" : "not yet");

   //--- Calendar ---------------------------------------------------
   const int secs = NeoFLCal_SecondsToNextHighImpact();
   s += Line("next high-impact",
        secs == -1     ? "UNKNOWN - calendar not visible"
      : secs == INT_MAX ? "none in lookahead window"
      : StringFormat("in %d min", secs / 60));

   //--- Risk sizing (reporting only) -------------------------------
   s += "\n";
   NeoFLRiskConfig rc;
   NeoFLRisk_Defaults(rc);
   rc.model        = InpRiskModel;
   rc.risk_percent = InpRiskPercent;
   rc.fixed_lot    = InpFixedLot;
   rc.hard_max_lot = InpHardMaxLot;

   const NeoFLRiskResult rr = NeoFLRisk_Size(_Symbol, InpStopDistance, rc, g_magic);
   s += Line("risk sizing", rr.approved
        ? StringFormat("%.2f lots, risking %.2f (%.2f%%)  [stop %.2f]",
                       rr.volume, rr.risk_money, rr.risk_percent, InpStopDistance)
        : StringFormat("%s - %s",
                       NeoFLData_VerdictName(rr.decision.verdict), rr.decision.reason));

   //--- Straddle sizing (reporting only) ---------------------------
   const double mainVol   = rr.approved ? rr.volume : InpFixedLot;
   const double mainEntry = q.ok ? q.ask : 0.0;
   const double strEntry  = mainEntry - InpExampleGap;

   if(mainEntry > 0.0)
   {
      const NeoFLStraddleSizing ss = NeoFLStr_Size(
         _Symbol, mainVol, mainEntry, strEntry, true,
         InpStraddleMode, InpRecoveryRatio, InpRecoveryDistance,
         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
         InpStraddleMaxLot);

      s += Line("straddle example",
           StringFormat("main %.2f @ %.*f, gap %.1f", mainVol, inst.digits, mainEntry, InpExampleGap));
      s += Line("  -> straddle", ss.approved
           ? StringFormat("%.2f lots, bucket zero @ %.*f (%.1f away)",
                          ss.volume, inst.digits, ss.zero_price, ss.recovery_distance)
           : StringFormat("%s - %s",
                          NeoFLData_VerdictName(ss.decision.verdict), ss.decision.reason));

      if(InpLogDecisions)
         NeoFLDecision_Emit(ss.decision);
   }

   //--- Live positions under this magic (observed, never touched) --
   s += "\n";
   int n = 0; double vol = 0.0, pl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_magic) continue;
      n++;
      vol += PositionGetDouble(POSITION_VOLUME);
      pl  += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   s += Line(StringFormat("positions (magic %I64u)", g_magic),
             StringFormat("%d open, %.2f lots, floating %.2f", n, vol, pl));

   s += "\n-----------------------------------------------------\n";
   s += StringFormat("updated %s GMT   |   NO ORDERS ARE PLACED BY THIS EA\n",
                     TimeToString(gmt, TIME_SECONDS));

   Comment(s);

   if(InpLogDecisions)
   {
      NeoFLDecision_Emit(NeoFLMD_AssessFeed(_Symbol, PERIOD_M15));
      NeoFLDecision_Emit(NeoFLGS_Assess(_Symbol));
      NeoFLDecision_Emit(NeoFLCal_Assess(_Symbol));
   }
}
