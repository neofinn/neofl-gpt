//+------------------------------------------------------------------+
//| Candle Level Revisit EA - Standalone Concept                     |
//| No NeoFL engine dependencies                                     |
//+------------------------------------------------------------------+
#property strict
input double InpStraddleFixedLot = 0.03; // legacy fixed lot (unused when brain is external)

//============ v3.86: EA IS EXECUTION ONLY ===========================
// The EA executes. The MasterBrain SCRIPT decides. Attach both to the chart.
//
// v3.85 broke that separation: the EA also ran NeoFLObs_Update internally,
// so the EA and the MasterBrain script both wrote
//     NEOFL_OBS_<symbol>_<magic>_STRADDLE_LOTS
// the EA every tick, the script about once a second. The EA therefore
// overwrote the script's correct gap-based value before reading it back,
// and sized the straddle from whichever wrote last. The right number was
// computed and then clobbered, invisibly, because both looked plausible.
//
// With InpInternalBrain=false the EA writes nothing. One brain, one writer.
input bool   InpInternalBrain      = false; // false = MasterBrain script is authoritative
input int    InpBrainMaxAgeSeconds = 30;    // brain considered dead beyond this
//---- D-006: account-agnostic limits.
// A lot count means nothing on its own -- 0.30 lots is negligible on a cent account
// and 100x the exposure on a standard one. The same flaw affects absolute money
// inputs: 1.00 is a dollar on one account and a cent on another.
//
// Expressing limits as a fraction of the account removes the question entirely, with
// no need to detect the account type (detection is guesswork; currency naming is not
// standardised). The broker's own tick value carries the scaling.
//
//   cap (lots) = (balance x cap%) / (account currency per lot per unit of price)
//
// Set InpStraddleCapPctBalance to 0 to fall back to the fixed lot cap below.
input double InpStraddleCapPctBalance = 2.0;   // max % of balance risked per 1.0 price move
input double InpStraddleHardCap       = 0.30;  // fixed lot fallback when the % is 0
input bool   InpStraddleLogSizing  = true;
input bool   InpTelemetry          = true;  // write state to MQL5/Files/NeoFL for the bridge
input int    InpTelemetrySeconds   = 5;     // snapshot interval
#property version   "3.86"
// Single source of truth for the version shown in logs. #property takes a literal,
// so this constant must match it -- but every runtime message uses ONLY this, which
// is why the inherited source could print "v3.83" from a file marked 3.85.
#define NEOFL_VERSION "3.86"
#property description "NeoFL integrated M5 execution EA: CTrade is the only execution authority; live Observer/Straddle/Calendar/Fund-Risk state is supplied by one continuous data-feeder script."

#include <Trade/Trade.mqh>
#include "NeoFL_Observer_Core_v2_00.mqh"
#include "NeoFL_MasterBrain_v3_85.mqh"
#include "NeoFL_Telemetry.mqh"

// -----------------------------------------------------------------------------
// NeoFL architecture rule v3.66:
// M5 is the ONLY initial-entry engine.
// M1 has NO initial-entry pathway or initial-entry configuration.
// M1 is strictly a silent observer; it activates only after DD/adverse-distance thresholds.
// -----------------------------------------------------------------------------


CTrade trade;

//--------------------------- Inputs ---------------------------------
input ENUM_TIMEFRAMES InpTimeframe          = PERIOD_M5;
input double          InpLots               = 0.01;  // HARD START CEILING: main M5 entry can never exceed 0.01 lots
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
input double            InpMinLotM5             = 0.01;
input int               InpM1InsideM5TolerancePts = 20; // M1 protection must remain inside the last closed M5 range

// Emergency liquidity-sweep protection
input bool              InpEmergencyProtection   = false;
input int               InpEmergencyMinPoints    = 50;
input double            InpEmergencyDistanceATR  = 1.00;
input bool              InpEmergencyBrokerSL     = true;
input double            InpEmergencyMaxLossMoney = 0.0; // 0 = disabled; emergency breach remains active

input double           InpMinSL_ATR_Mult     = 0.00; // UNUSED: SL removed by design
input double           InpM1Trail_ATR_Mult   = 1.50;  // minimum M1 trailing distance


// Execution
input bool              InpOnePositionOnly   = true;
input bool              InpOneTradePerBar    = true;

input bool              InpUseMartingale        = false;
input double            InpMartingaleMultiplier = 2.0;
input int               InpMaxMartingaleSteps   = 5;
input double            InpMaxLot               = 10.0;
input bool              InpAllowOppositeRecovery = true;
input bool              InpAllowM1OppositeProtection = true; // M1 may protect an existing M5 trade
input double            InpRecoveryTargetATR     = 1.00;
input double            InpRecoveryExtraProfitMoney = 0.0; // basket must reach at least this combined profit before recovery basket closes
input double            InpProfitFarFromTPPct    = 0.35; // remaining TP distance / original TP distance
input double            InpOppositeNormalLotFactor = 1.0;
input bool              InpUseFundEngine          = true;
input double            InpSafetyReservePct       = 20.0;  // capital never allocated to new exposure
input double            InpM5FundAllocationPct     = 2.0;   // max margin budget for a fresh M5 trade
input double            InpRecoveryFundPct         = 8.0;   // max margin budget for recovery
input double            InpStraddleFundPct         = 10.0;  // reserved margin budget for future straddle
input double            InpMaxMarginUsedPct       = 35.0;  // block new exposure above this equity utilization
input double            InpMaxFloatingLossPct     = 12.0;  // block additional exposure; does not force-close
input double            InpMaxSpreadPoints        = 80.0;
input double            InpMinATRPoints           = 0.0;
input double            InpMaxATRPoints           = 0.0;   // 0 = disabled
input bool              InpUseSessionFilter       = false;
input int               InpSessionStartHour       = 0;
input int               InpSessionEndHour         = 23;
input bool              InpUseCalendarFilter      = true;  // integrated MT5 calendar governor
input int               InpCalendarBeforeMin      = 240; // HARD BLOCK: 4 hours before high-impact news
input int               InpCalendarAfterMin       = 30;  // keep new exposure blocked after release
input string            InpCalendarCurrency       = "USD"; // Gold/XAU primary macro currency
input ENUM_CALENDAR_EVENT_IMPORTANCE InpMinCalendarImportance = CALENDAR_IMPORTANCE_HIGH;
input bool              InpBlockRecoveryOnNews    = true;
input bool              InpBlockStraddleOnNews    = true;
input bool              InpCalendarFailClosed     = true; // if calendar cannot be read, block NEW exposure
input string            InpTesterCalendarFile     = "NeoFL_USD_Calendar.csv"; // tester fallback cache
input bool              InpUseExternalCalendarGovernor = false; // legacy external bus disabled in integrated mode
input string            InpExternalCalendarPrefix = "NEOFL_CAL";
input bool              InpEnableStraddle         = true; // arm only after production validation
input double            InpStraddleTriggerATR     = 3.0;
input double            InpStraddleFundUsePct     = 50.0;
input bool              InpUseObserverNetwork       = true;
input bool              InpUseExternalDataFeeder     = true;  // LIVE: external script supplies Observer/Fund/Calendar state
input string            InpDataFeederPrefix          = "NEOFL_FEED";
input string            InpObserverPrefix           = "NEOFL_OBS";
input int               InpObserverStaleSeconds     = 10;
input bool              InpObserverFailClosed       = true;
input bool              InpTesterObserverBridge     = true;
input int               InpObserverM1ConfirmBars    = 2;
input double             InpObserverProfitArmMoney  = 1.00;
input double             InpObserverRetracePct      = 35.0;
input double             InpObserverATRReversalMult = 0.35;
input int                InpObserverProbabilityTrades = 100;

// Institutional Observer / Straddle Risk Model
input double             InpObserverActivationDDPct   = 2.0;  // position loss as % of equity
input double             InpObserverActivationATR     = 2.0;  // M3 adverse distance trigger
input double             InpObserverHardDDPct         = 5.0;  // account/position DD threshold -> grace
input int                InpObserverGraceM3Bars       = 3;
input double             InpObserverRecoveryDDPct    = 0.50; // below this = recovering
input double             InpStraddleProjectionATR    = 1.0;
input double             InpStraddleProfitBufferMoney = 1.0;
input double             InpStraddleSafetyFactor     = 1.10;
input double             InpStraddleMaxLot           = 10.0; // CAP EXCEPTION: >0.01 allowed
input double             InpStraddleExitToleranceMoney = 0.50;
input bool               InpStraddleCloseOnBasketBE  = true;
input bool               InpStraddleAllowInGrace     = true;



input bool              InpShowNeoFLDashboard   = true;
input ENUM_BASE_CORNER  InpDashboardCorner      = CORNER_LEFT_UPPER;
input int               InpDashboardX            = 12;
input int               InpDashboardY            = 24;
input int               InpDashboardWidth        = 430;
input int               InpDashboardHeight       = 760;
input double             InpCapitalBase           = 0.0;  // 0 = lock first-run account balance as protected capital



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
double   g_fund_equity = 0.0;
double   g_fund_free_margin = 0.0;
double   g_fund_margin_used = 0.0;
double   g_fund_margin_used_pct = 0.0;
double   g_fund_floating_loss = 0.0;
double   g_fund_floating_loss_pct = 0.0;
double   g_fund_deployable = 0.0;
double   g_fund_m5_budget = 0.0;
double   g_fund_recovery_budget = 0.0;
double   g_fund_straddle_budget = 0.0;
double   g_capital_base = 0.0;
double   g_realized_profit = 0.0;
double   g_safe_withdrawal = 0.0;
string   g_withdrawal_status = "HOLD";
string   g_risk_gate_state = "INIT";
string   g_risk_gate_reason = "";
bool     g_calendar_locked = false;
bool     g_volatility_locked = false;
bool     g_observer_ok = false;
datetime g_observer_update = 0;
string   g_observer_m1_state = "NO OBSERVER";
bool     g_observer_opposite = false;
bool     g_observer_exit = false;
double   g_observer_mfe_money = 0.0;
double   g_observer_mae_money = 0.0;
double   g_observer_win_prob = 0.0;
double   g_observer_loss_prob = 0.0;
double   g_observer_dd_pct = 0.0;
double   g_observer_recovery_coverage = 0.0;
double   g_observer_position_loss_pct = 0.0;
double   g_observer_straddle_lots = 0.0;
double   g_observer_straddle_required = 0.0;
double   g_observer_straddle_coverage = 0.0;
double   g_observer_straddle_start = 0.0;
int      g_observer_risk_state = 0; // 0 silent, 1 watch, 2 active, 3 grace, 4 terminate
bool     g_observer_straddle_arm = false;
bool     g_observer_straddle_exit = false;
bool     g_observer_basket_terminate = false;

double   g_emergency_sl = 0.0;
bool     g_emergency_active = false;
datetime g_emergency_structure_bar = 0;


datetime g_calendar_event_time = 0;
string   g_calendar_event_name = "";
string   g_calendar_event_currency = "";
int      g_calendar_event_importance = 0;
string   g_calendar_source = "LIVE MT5";
datetime g_calendar_last_check = 0;
bool     g_tester_calendar_loaded = false;
bool     g_tester_calendar_available = false;

struct TesterNewsEvent
{
   datetime time;
   string   currency;
   int      importance;
   string   name;
};
TesterNewsEvent g_tester_news[];

datetime g_m1_last_closed_scanned = 0;
ulong    g_m1_scan_count = 0;
string   g_m1_monitor_state = "IDLE";
datetime g_m1_last_opposite_signal = 0;

ulong g_trailing_ticket = 0;
bool g_trailing_active = false;
double g_trailing_extreme = 0.0;
int g_martingale_step = 0;
LEVEL_TYPE g_last_trade_level_type = LEVEL_BREAKOUT_BULL;
double g_last_trade_level_price = 0.0;
bool g_m1_reassess_pending = false;
int g_m1_reassess_bars_left = 0;
bool g_m5_reassess_pending = false;
int g_m5_reassess_bars_left = 0;
ulong g_last_processed_exit_deal = 0;


//--------------------------- Helpers --------------------------------
// Observer-driven straddle execution
bool IsHedgingAccount();
bool HasStraddlePosition(ulong &ticket);
double CalculateStraddleExecutableLots(const double requested);
bool OpenStraddle(const bool buy,const double lots,const double start_price);
bool CloseStraddle();
bool CloseMainAndStraddle();
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


double NormalizeRequestedLots(const double requested, const double configured_min)
{
   double broker_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double broker_max = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), InpMaxLot);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = broker_min;

   double minimum = MathMax(broker_min, configured_min);
   double lots = MathMax(minimum, requested);
   lots = MathMin(broker_max, lots);

   lots = MathCeil(lots / step - 1e-9) * step;
   lots = MathMax(minimum, lots);
   lots = MathMin(broker_max, lots);

   return NormalizeDouble(lots, 2);
}

double TradeLots()
{
   // ABSOLUTE INITIAL ENTRY CEILING. Fund size never increases this.
   double lots=MathMin(InpLots,0.01);
   if(InpUseMartingale && g_martingale_step>0)
      lots=0.01; // martingale cannot enlarge initial-entry lot

   return NormalizeRequestedLots(lots,0.01);
}





//+------------------------------------------------------------------+
//| NeoFL dashboard                                                   |
//+------------------------------------------------------------------+
string g_dash_prefix = "NeoFL_CLRV_DASH_";

void DashDelete()
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;--i)
   {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,g_dash_prefix)==0)
         ObjectDelete(0,name);
   }
}

void DashRect(const string id,const int x,const int y,const int w,const int h,
              const color bg,const color border)
{
   string n=g_dash_prefix+id;
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,InpDashboardCorner);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}

void DashText(const string id,const string text,const int x,const int y,
              const int size,const color clr,const string font="Arial")
{
   string n=g_dash_prefix+id;
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,InpDashboardCorner);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetString(0,n,OBJPROP_FONT,font);
   ObjectSetString(0,n,OBJPROP_TEXT,text);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}

string DashFmtMoney(const double v)
{
   return DoubleToString(v,2)+" "+AccountInfoString(ACCOUNT_CURRENCY);
}

string DashPositionText(double &profit,double &lots,bool &buy,double &entry,double &tp)
{
   profit=0; lots=0; buy=true; entry=0; tp=0;
   ulong ticket=0;
   if(!SelectOurPosition(ticket) || !PositionSelectByTicket(ticket))
      return "FLAT";

   buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   lots=PositionGetDouble(POSITION_VOLUME);
   entry=PositionGetDouble(POSITION_PRICE_OPEN);
   tp=PositionGetDouble(POSITION_TP);
   return buy ? "BUY" : "SELL";
}

void DashUpdate()
{
   if(!InpShowNeoFLDashboard)
      return;

   double p=0,lots=0,entry=0,tp=0; bool buy=true;
   string pos=DashPositionText(p,lots,buy,entry,tp);
   double atr=GetATR(PERIOD_M5,InpM5ATRPeriod);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   string regime="RANGE";
   color regimeClr=clrSilver;
   if(atr>0)
   {
      double m5range=0;
      MqlRates rr[];
      ArraySetAsSeries(rr,true);
      if(CopyRates(_Symbol,PERIOD_M5,1,10,rr)>=5)
      {
         for(int i=0;i<ArraySize(rr);++i) m5range+=rr[i].high-rr[i].low;
         m5range/=ArraySize(rr);
         if(atr>m5range*0.85) { regime="EXPANDING"; regimeClr=clrLime; }
         else if(atr<m5range*0.55) { regime="COMPRESSED"; regimeClr=clrGold; }
      }
   }

   int active=0,revisited=0;
   for(int i=0;i<ArraySize(g_levels);++i)
   {
      if(g_levels[i].active) active++;
      if(g_levels[i].active && g_levels[i].revisited) revisited++;
   }

   string scan=(active>0?"ACTIVE":"WAITING");
   color scanClr=(active>0?clrLime:clrSilver);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double fm=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double ddPct=(bal>0.0?MathMax(0.0,(bal-eq)/bal*100.0):0.0);

   int x=InpDashboardX,y=InpDashboardY,w=InpDashboardWidth;
   DashRect("BG",x,y,w,InpDashboardHeight,clrBlack,clrDarkSlateGray);

   // Compact, fixed rows: no overlapping sections.
   DashText("Brand","NeoFL",x+16,y+12,24,clrAqua,"Arial Bold");
   DashText("Tag","PRECISION. LOGIC. CONSISTENCY.",x+18,y+39,8,clrGold,"Arial Bold");
   DashText("Bot","NeoFL Candle Revisit Engine",x+16,y+58,13,clrWhite,"Arial Bold");
   DashText("Version","v3.73",x+w-58,y+60,9,clrLime,"Arial Bold");
   DashText("Desc","EXECUTION EA  |  EXTERNAL INTELLIGENCE  |  CTRADE",x+16,y+79,7,clrSilver);

   DashText("MarketH","MARKET",x+16,y+104,8,clrAqua,"Arial Bold");
   DashText("Market",_Symbol+"  |  M5 entry / M1 monitor",x+16,y+120,8,clrWhite);
   DashText("Bid","Bid  "+DoubleToString(bid,_Digits),x+16,y+138,8,clrSilver);
   DashText("Ask","Ask  "+DoubleToString(ask,_Digits),x+w/2,y+138,8,clrSilver);

   DashText("RegimeH","REGIME",x+16,y+162,8,clrAqua,"Arial Bold");
   DashText("Regime",regime,x+w-96,y+160,9,regimeClr,"Arial Bold");
   DashText("ATR","ATR("+IntegerToString(InpM5ATRPeriod)+")  "+DoubleToString(atr,_Digits),x+16,y+178,8,clrWhite);

   DashText("ScanH","LEVEL ENGINE",x+16,y+202,8,clrAqua,"Arial Bold");
   DashText("Scan",scan,x+w-74,y+200,9,scanClr,"Arial Bold");
   DashText("Levels","Open levels     "+IntegerToString(active),x+16,y+218,8,clrWhite);
   DashText("Revisit","Revisited       "+IntegerToString(revisited),x+16,y+234,8,clrSilver);

   DashText("PosH","POSITION",x+16,y+258,8,clrAqua,"Arial Bold");
   color pClr=(p>0?clrLime:(p<0?clrTomato:clrSilver));
   DashText("Pos",pos,x+w-70,y+256,9,pClr,"Arial Bold");
   DashText("Float","Floating P/L",x+16,y+275,8,clrSilver);
   DashText("FloatV",DashFmtMoney(p),x+w-142,y+275,8,pClr,"Arial Bold");
   DashText("Lots","Lots",x+16,y+291,8,clrSilver);
   DashText("LotsV",DoubleToString(lots,2),x+w-70,y+291,8,clrWhite,"Arial Bold");
   if(lots>0)
   {
      DashText("Entry","Entry",x+16,y+307,8,clrSilver);
      DashText("EntryV",DoubleToString(entry,_Digits),x+w-110,y+307,8,clrWhite);
      DashText("TP","TP",x+16,y+323,8,clrSilver);
      DashText("TPV",(tp>0?DoubleToString(tp,_Digits):"MONITORED"),x+w-110,y+323,8,clrWhite);
   }

   DashText("AcctH","ACCOUNT / CAPITAL",x+16,y+349,8,clrAqua,"Arial Bold");
   DashText("Bal","Balance",x+16,y+367,8,clrSilver); DashText("BalV",DashFmtMoney(bal),x+w-142,y+367,8,clrWhite,"Arial Bold");
   DashText("Eq","Equity",x+16,y+383,8,clrSilver); DashText("EqV",DashFmtMoney(eq),x+w-142,y+383,8,clrWhite,"Arial Bold");
   DashText("FM","Free margin",x+16,y+399,8,clrSilver); DashText("FMV",DashFmtMoney(fm),x+w-142,y+399,8,clrSilver);
   DashText("DD","Drawdown",x+16,y+415,8,clrSilver); DashText("DDV",DoubleToString(ddPct,2)+"%",x+w-70,y+415,8,ddPct>5.0?clrTomato:clrWhite,"Arial Bold");

   DashText("RealH","REALIZED / WITHDRAWAL",x+16,y+441,8,clrAqua,"Arial Bold");
   DashText("Real","Realized profit",x+16,y+459,8,clrSilver); DashText("RealV",DashFmtMoney(g_realized_profit),x+w-142,y+459,8,g_realized_profit>=0?clrLime:clrTomato,"Arial Bold");
   DashText("Base","Protected capital",x+16,y+475,8,clrSilver); DashText("BaseV",DashFmtMoney(g_capital_base),x+w-142,y+475,8,clrWhite);
   DashText("Safe","Safe to withdraw",x+16,y+493,8,clrSilver); DashText("SafeV",DashFmtMoney(g_safe_withdrawal),x+w-142,y+493,8,g_safe_withdrawal>0?clrLime:clrGold,"Arial Bold");
   color wdClr=(StringFind(g_withdrawal_status,"SAFE")>=0?clrLime:clrGold);
   DashText("WdStatus",g_withdrawal_status,x+16,y+511,8,wdClr,"Arial Bold");

   DashText("ObsH","OBSERVER / RISK",x+16,y+537,8,clrAqua,"Arial Bold");
   DashText("Observer","Observer  "+(g_observer_ok?"ONLINE":"STALE/WAITING"),x+16,y+555,8,g_observer_ok?clrLime:clrTomato,"Arial Bold");
   DashText("ObsM1","M1  "+g_observer_m1_state+"  | MFE "+DashFmtMoney(g_observer_mfe_money),x+16,y+571,7,clrSilver);
   DashText("ObsProb","WIN "+DoubleToString(g_observer_win_prob,1)+"%  LOSS "+DoubleToString(g_observer_loss_prob,1)+"%  REC "+DoubleToString(g_observer_recovery_coverage,1)+"%",x+16,y+586,7,clrSilver);
   DashText("ObsDD","Obs DD "+DoubleToString(g_observer_dd_pct,2)+"% | Pos "+DoubleToString(g_observer_position_loss_pct,2)+"% | MAE "+DashFmtMoney(g_observer_mae_money),x+16,y+601,7,clrSilver);
   DashText("ObsRisk","OBS RISK "+IntegerToString(g_observer_risk_state)+" | STRADDLE "+DoubleToString(g_observer_straddle_lots,2)+" / "+DoubleToString(g_observer_straddle_required,2),x+16,y+616,7,clrGold);

   DashText("GuardH","PROTECTION",x+16,y+625,8,clrAqua,"Arial Bold");
   DashText("Emergency","M1 EMERGENCY GUARD  "+(g_emergency_active?"ACTIVE":"ARMING"),x+16,y+643,8,g_emergency_active?clrGold:clrSilver,"Arial Bold");
   if(g_emergency_active)
      DashText("EmergencySL","Guard SL  "+DoubleToString(g_emergency_sl,_Digits),x+w-142,y+643,8,clrGold,"Arial Bold");
   DashText("Recovery","Opposite recovery  "+(InpAllowOppositeRecovery?"ON":"OFF"),x+16,y+660,8,InpAllowOppositeRecovery?clrLime:clrTomato,"Arial Bold");
   color monClr=(g_m1_monitor_state=="SCANNING" || g_m1_monitor_state=="MONITORING")?clrLime:clrSilver;
   DashText("M1Mon","M1 monitor  "+g_m1_monitor_state,x+16,y+677,8,monClr,"Arial Bold");

   UpdateCalendarGovernor(false);
   color newsClr=g_calendar_locked?clrTomato:clrLime;
   DashText("News","EVENT GOVERNOR  "+(g_calendar_locked?"BLOCKED":"CLEAR"),x+16,y+700,8,newsClr,"Arial Bold");
   DashText("NewsRule","NEW EXPOSURE BLOCK  4H BEFORE  |  30M AFTER",x+16,y+716,7,clrGold);
   DashText("Footer","NeoFL Trading Systems",x+16,y+738,8,clrAqua,"Arial Bold");
}

//+------------------------------------------------------------------+
//| Institutional-style capital / market risk gate                   |
//+------------------------------------------------------------------+
double EquityValue()
{
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

double CurrentMarginUsed()
{
   return AccountInfoDouble(ACCOUNT_MARGIN);
}

double CurrentFreeMargin()
{
   return AccountInfoDouble(ACCOUNT_MARGIN_FREE);
}

double CurrentFloatingLoss()
{
   double loss=0.0;
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic)
         continue;

      double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(p<0.0) loss += -p;
   }
   return loss;
}

string CapitalBaseKey()
{
   return "NEOFL_CAPITAL_BASE_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+_Symbol+"_"+(string)InpMagic;
}

void LoadCapitalBase()
{
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   if(InpCapitalBase>0.0)
   {
      g_capital_base=InpCapitalBase;
      GlobalVariableSet(CapitalBaseKey(),g_capital_base);
      return;
   }

   string key=CapitalBaseKey();
   if(GlobalVariableCheck(key))
      g_capital_base=GlobalVariableGet(key);
   else
   {
      g_capital_base=bal;
      GlobalVariableSet(key,g_capital_base);
   }
}

double CalculateRealizedProfit()
{
   double total=0.0;
   if(!HistorySelect(0,TimeCurrent()))
      return 0.0;

   int totalDeals=HistoryDealsTotal();
   for(int i=0;i<totalDeals;i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagic) continue;

      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;

      total += HistoryDealGetDouble(ticket,DEAL_PROFIT);
      total += HistoryDealGetDouble(ticket,DEAL_SWAP);
      total += HistoryDealGetDouble(ticket,DEAL_COMMISSION);
   }
   return total;
}

void UpdateWithdrawalMetrics()
{
   g_realized_profit=CalculateRealizedProfit();

   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double floatingLoss=CurrentFloatingLoss();
   double reserve=eq*MathMax(0.0,MathMin(100.0,InpSafetyReservePct))/100.0;

   // Conservative withdrawal amount: never withdraw protected capital,
   // currently committed margin, current floating loss, or safety reserve.
   g_safe_withdrawal=MathMax(0.0,
      bal-g_capital_base-margin-floatingLoss-reserve);

   ulong ticket=0;
   bool hasPosition=SelectOurPosition(ticket);
   if(g_safe_withdrawal<=0.0)
      g_withdrawal_status="HOLD / NO SAFE WITHDRAWAL";
   else if(hasPosition || floatingLoss>0.0)
      g_withdrawal_status="HOLD / OPEN RISK";
   else
      g_withdrawal_status="SAFE TO WITHDRAW";
}

void UpdateFundSnapshot()
{
   if(ExternalFeederActive())
   {
      g_fund_equity            = ReadFeederValue("EQUITY",AccountInfoDouble(ACCOUNT_EQUITY));
      g_fund_free_margin       = ReadFeederValue("FREE_MARGIN",AccountInfoDouble(ACCOUNT_FREEMARGIN));
      g_fund_margin_used       = ReadFeederValue("MARGIN_USED",AccountInfoDouble(ACCOUNT_MARGIN));
      g_fund_margin_used_pct   = ReadFeederValue("MARGIN_USED_PCT",0.0);
      g_fund_floating_loss     = ReadFeederValue("FLOATING_LOSS",0.0);
      g_fund_floating_loss_pct = ReadFeederValue("FLOATING_LOSS_PCT",0.0);
      g_fund_deployable        = ReadFeederValue("DEPLOYABLE",0.0);
      g_fund_m5_budget         = ReadFeederValue("M5_BUDGET",0.0);
      g_fund_recovery_budget   = ReadFeederValue("RECOVERY_BUDGET",0.0);
      g_fund_straddle_budget   = ReadFeederValue("STRADDLE_BUDGET",0.0);
      return;
   }

   g_fund_equity=EquityValue();
   g_fund_free_margin=CurrentFreeMargin();
   g_fund_margin_used=CurrentMarginUsed();
   g_fund_margin_used_pct=(g_fund_equity>0.0 ? 100.0*g_fund_margin_used/g_fund_equity : 100.0);

   g_fund_floating_loss=CurrentFloatingLoss();
   g_fund_floating_loss_pct=(g_fund_equity>0.0 ? 100.0*g_fund_floating_loss/g_fund_equity : 100.0);

   double reserve=g_fund_equity*MathMax(0.0,MathMin(100.0,InpSafetyReservePct))/100.0;
   g_fund_deployable=MathMax(0.0,g_fund_equity-reserve-g_fund_margin_used);

   g_fund_m5_budget=g_fund_equity*MathMax(0.0,InpM5FundAllocationPct)/100.0;
   g_fund_recovery_budget=g_fund_equity*MathMax(0.0,InpRecoveryFundPct)/100.0;
   g_fund_straddle_budget=g_fund_equity*MathMax(0.0,InpStraddleFundPct)/100.0;
}

bool IsWithinSession()
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   int h=dt.hour;

   if(InpSessionStartHour==InpSessionEndHour)
      return true;

   if(InpSessionStartHour<InpSessionEndHour)
      return (h>=InpSessionStartHour && h<InpSessionEndHour);

   return (h>=InpSessionStartHour || h<InpSessionEndHour);
}

bool IsTesterMode()
{
   return (MQLInfoInteger(MQL_TESTER) != 0 || MQLInfoInteger(MQL_OPTIMIZATION) != 0);
}

bool LoadTesterCalendarCache()
{
   if(g_tester_calendar_loaded)
      return g_tester_calendar_available;

   g_tester_calendar_loaded=true;
   g_tester_calendar_available=false;
   ArrayResize(g_tester_news,0);

   int h=FileOpen(InpTesterCalendarFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,';');
   if(h==INVALID_HANDLE)
   {
      PrintFormat("NeoFL Calendar | tester cache not found: %s",InpTesterCalendarFile);
      return false;
   }

   while(!FileIsEnding(h))
   {
      string ts=FileReadString(h);
      string cur=FileReadString(h);
      string imp=FileReadString(h);
      string name=FileReadString(h);

      if(ts=="")
         continue;

      datetime t=StringToTime(ts);
      if(t<=0)
         continue;

      TesterNewsEvent e;
      e.time=t;
      e.currency=cur;
      e.importance=(int)StringToInteger(imp);
      e.name=name;

      int n=ArraySize(g_tester_news);
      ArrayResize(g_tester_news,n+1);
      g_tester_news[n]=e;
   }
   FileClose(h);

   g_tester_calendar_available=(ArraySize(g_tester_news)>0);
   PrintFormat("NeoFL Calendar | tester cache loaded: %s | events=%d",
               InpTesterCalendarFile,ArraySize(g_tester_news));
   return g_tester_calendar_available;
}

bool TesterCalendarHighImpactNear(const datetime now)
{
   if(!LoadTesterCalendarCache())
      return false;

   datetime from=now-InpCalendarAfterMin*60;
   datetime to=now+InpCalendarBeforeMin*60;
   datetime best_future=0;
   datetime best_past=0;
   string best_name="";
   string best_currency="";
   int best_importance=0;

   for(int i=0;i<ArraySize(g_tester_news);++i)
   {
      TesterNewsEvent e=g_tester_news[i];
      if(e.time<from || e.time>to)
         continue;
      if(InpCalendarCurrency!="" && StringFind(e.currency,InpCalendarCurrency)<0)
         continue;
      if(e.importance < (int)InpMinCalendarImportance)
         continue;

      if(e.time>=now)
      {
         if(best_future==0 || e.time<best_future)
         {
            best_future=e.time;
            best_name=e.name;
            best_currency=e.currency;
            best_importance=e.importance;
         }
      }
      else if(best_future==0 && (best_past==0 || e.time>best_past))
      {
         best_past=e.time;
         best_name=e.name;
         best_currency=e.currency;
         best_importance=e.importance;
      }
   }

   datetime selected=(best_future>0 ? best_future : best_past);
   if(selected<=0)
      return false;

   g_calendar_event_time=selected;
   g_calendar_event_name=best_name;
   g_calendar_event_currency=best_currency;
   g_calendar_event_importance=best_importance;
   g_calendar_source="TESTER CACHE";
   return true;
}

bool LiveCalendarHighImpactNear(const datetime now)
{
   datetime from=now-InpCalendarAfterMin*60;
   datetime to=now+InpCalendarBeforeMin*60;

   MqlCalendarValue values[];
   ResetLastError();
   int count=CalendarValueHistory(values,from,to,NULL,InpCalendarCurrency);
   if(count<0)
   {
      int err=GetLastError();
      PrintFormat("NeoFL Calendar | CalendarValueHistory failed err=%d",err);
      g_calendar_source="LIVE API ERROR";
      return false;
   }

   datetime best_future=0;
   datetime best_past=0;
   string best_name="";
   int best_importance=0;

   for(int i=0;i<count;i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id,ev))
         continue;
      if(ev.importance < InpMinCalendarImportance)
         continue;
      if(ev.time_mode!=CALENDAR_TIMEMODE_DATETIME)
         continue;

      datetime t=values[i].time;
      if(t>=now)
      {
         if(best_future==0 || t<best_future)
         {
            best_future=t;
            best_name=ev.name;
            best_importance=(int)ev.importance;
         }
      }
      else if(best_future==0 && (best_past==0 || t>best_past))
      {
         best_past=t;
         best_name=ev.name;
         best_importance=(int)ev.importance;
      }
   }

   datetime selected=(best_future>0 ? best_future : best_past);
   if(selected<=0)
   {
      g_calendar_source="LIVE MT5";
      return false;
   }

   g_calendar_event_time=selected;
   g_calendar_event_name=best_name;
   g_calendar_event_currency=InpCalendarCurrency;
   g_calendar_event_importance=best_importance;
   g_calendar_source="LIVE MT5";
   return true;
}

void UpdateCalendarGovernor(const bool force=false)
{
   if(ExternalFeederActive())
   {
      g_calendar_locked          = (ReadFeederValue("CALENDAR_LOCKED",0.0)>0.5);
      g_calendar_event_time     = (datetime)ReadFeederValue("CALENDAR_EVENT_TIME",0.0);
      g_calendar_event_importance = (int)ReadFeederValue("CALENDAR_IMPORTANCE",0.0);
      g_calendar_source         = "SCRIPT FEEDER";
      return;
   }

   if(!InpUseCalendarFilter)
   {
      g_calendar_locked=false;
      g_calendar_source="DISABLED";
      return;
   }

   datetime now=TimeTradeServer();
   if(now<=0) now=TimeCurrent();

   // Avoid hammering the calendar service on every tick.
   if(!force && g_calendar_last_check>0 && (now-g_calendar_last_check)<10)
      return;
   g_calendar_last_check=now;

   g_calendar_locked=false;
   g_calendar_event_time=0;
   g_calendar_event_name="";
   g_calendar_event_currency="";
   g_calendar_event_importance=0;

   if(IsTesterMode())
   {
      bool found=TesterCalendarHighImpactNear(now);
      if(!found && !g_tester_calendar_available && InpCalendarFailClosed)
      {
         g_calendar_locked=true;
         g_calendar_source="TESTER CACHE MISSING";
         g_risk_gate_reason="CALENDAR CACHE";
         return;
      }
      g_calendar_locked=found;
      if(!found) g_calendar_source="TESTER CACHE";
      return;
   }

   bool found=LiveCalendarHighImpactNear(now);
   if(g_calendar_source=="LIVE API ERROR")
   {
      g_calendar_locked=InpCalendarFailClosed;
      return;
   }
   g_calendar_locked=found;
}

bool CalendarHighImpactNear()
{
   UpdateCalendarGovernor(false);
   return g_calendar_locked;
}

bool MarketVolatilityOK()
{
   double atr=GetATR(PERIOD_M5,InpM5ATRPeriod);
   double points=(PointValue()>0.0 ? atr/PointValue() : 0.0);

   if(InpMinATRPoints>0.0 && points<InpMinATRPoints)
      return false;

   if(InpMaxATRPoints>0.0 && points>InpMaxATRPoints)
      return false;

   return true;
}

bool SpreadOK()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double point=PointValue();
   if(bid<=0.0 || ask<=0.0 || point<=0.0)
      return false;

   double spread=(ask-bid)/point;
   return (InpMaxSpreadPoints<=0.0 || spread<=InpMaxSpreadPoints);
}

bool MarginBudgetAllows(const bool recovery,const double lots)
{
   if(!InpUseFundEngine)
      return true;

   if(lots<=0.0 || g_fund_equity<=0.0)
      return false;

   double price=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)+SymbolInfoDouble(_Symbol,SYMBOL_BID))*0.5;
   if(price<=0.0) return false;

   double margin=0.0;
   ENUM_ORDER_TYPE type=ORDER_TYPE_BUY;
   if(!OrderCalcMargin(type,_Symbol,lots,price,margin))
      return false;

   double budget=recovery ? g_fund_recovery_budget : g_fund_m5_budget;
   double remaining=MathMax(0.0,budget);

   if(margin>remaining)
      return false;

   double projected=g_fund_margin_used+margin;
   if(g_fund_equity>0.0 &&
      projected/g_fund_equity*100.0>InpMaxMarginUsedPct)
      return false;

   if(InpMaxFloatingLossPct>0.0 &&
      g_fund_floating_loss/g_fund_equity*100.0>=InpMaxFloatingLossPct)
      return false;

   return (g_fund_free_margin>margin);
}

bool ExternalCalendarLocked()
{
   if(!InpUseExternalCalendarGovernor) return false;
   string key=InpExternalCalendarPrefix+"_"+_Symbol+"_"+(string)InpMagic+"_BLOCK";
   if(!GlobalVariableCheck(key)) return false;
   return GlobalVariableGet(key)>0.5;
}

bool PreTradeRiskGate(const bool recovery,const double lots,const string context)
{
   UpdateFundSnapshot();

   if(!ObserverAllowsNewExposure())
   {
      g_risk_gate_state="LOCKED";
      g_risk_gate_reason="OBSERVER";
      return false;
   }

   if(!IsWithinSession())
   {
      g_risk_gate_state="LOCKED";
      g_risk_gate_reason="SESSION";
      return false;
   }

   if(!SpreadOK())
   {
      g_risk_gate_state="LOCKED";
      g_risk_gate_reason="SPREAD";
      return false;
   }

   g_volatility_locked=!MarketVolatilityOK();
   if(g_volatility_locked)
   {
      g_risk_gate_state="LOCKED";
      g_risk_gate_reason="VOLATILITY";
      return false;
   }

   g_calendar_locked=ExternalCalendarLocked();
   if(g_calendar_locked)
   {
      g_risk_gate_state="LOCKED";
      g_risk_gate_reason="EXTERNAL CALENDAR";
      return false;
   }
   if(InpUseCalendarFilter)
   {
      g_calendar_locked=CalendarHighImpactNear();
      if(g_calendar_locked)
      {
         g_risk_gate_state="LOCKED";
         g_risk_gate_reason=(g_calendar_source=="TESTER CACHE MISSING" ? "CALENDAR CACHE" : "NEWS 4H");
         return false;
      }
   }

   if(!MarginBudgetAllows(recovery,lots))
   {
      g_risk_gate_state="LOCKED";
      g_risk_gate_reason="FUND";
      return false;
   }

   g_risk_gate_state="CLEAR";
   g_risk_gate_reason=context;
   return true;
}

double FundConstrainedLots(const bool recovery,const double requested)
{
   double broker_min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double broker_max=MathMin(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),InpMaxLot);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=broker_min;

   if(!InpUseFundEngine)
      return NormalizeRequestedLots(requested,recovery ? InpMinLotM5 : InpMinLotM5);

   double price=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)+SymbolInfoDouble(_Symbol,SYMBOL_BID))*0.5;
   double margin_one=0.0;
   if(price<=0.0 || !OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,1.0,price,margin_one) || margin_one<=0.0)
      return 0.0;

   double budget=recovery ? g_fund_recovery_budget : g_fund_m5_budget;
   double margin_cap=MathMax(0.0,budget);
   double max_by_margin=margin_cap/margin_one;

   double lots=MathMin(requested,MathMin(broker_max,max_by_margin));
   // Initial entry hard cap: recovery/straddle have their own sizing path.
   if(!recovery)
      lots=MathMin(lots,0.01);
   if(lots<broker_min)
      return 0.0;

   lots=MathCeil(lots/step-1e-9)*step;
   lots=MathMin(lots,broker_max);
   return NormalizeDouble(lots,2);
}

bool SelectOurPosition(ulong &ticket)
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(StringFind(c,"NEOFL STRADDLE")>=0) continue;
      ticket=t;
      return true;
   }
   ticket=0;
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

bool IsRecoveryPositionSelected()
{
   string c=PositionGetString(POSITION_COMMENT);
   return (StringFind(c,"CLVL Opposite Recovery")>=0);
}

void ManageRecoveryBasket()
{
   if(!InpAllowOppositeRecovery)
      return;

   ulong tickets[32];
   int count=0;
   double basket=0.0;
   bool has_recovery=false;

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic)
         continue;

      if(count<32)
         tickets[count++]=ticket;

      basket += PositionGetDouble(POSITION_PROFIT)
             +  PositionGetDouble(POSITION_SWAP);

      if(IsRecoveryPositionSelected())
         has_recovery=true;
   }

   // Only a genuine recovery basket is managed here. A normal single trade
   // remains governed by its broker TP / profit-only M1 monitoring.
   if(!has_recovery || count<2)
      return;

   double target=InpRecoveryExtraProfitMoney;
   if(basket < target)
      return;

   PrintFormat("NeoFL recovery basket target reached: combined P/L %.2f >= %.2f. Closing %d positions.",
               basket,target,count);

   // Close every position in the basket. We never close the original leg
   // merely because it is losing; the basket condition must be satisfied.
   for(int i=0;i<count;i++)
   {
      if(!PositionSelectByTicket(tickets[i]))
         continue;

      double leg_profit=PositionGetDouble(POSITION_PROFIT)
                      + PositionGetDouble(POSITION_SWAP);
      if(!trade.PositionClose(tickets[i]))
      {
         PrintFormat("NeoFL recovery basket close failed ticket=%I64u legP/L=%.2f ret=%d %s",
                     tickets[i],leg_profit,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      }
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

   double lots=FundConstrainedLots(false,TradeLots());
   if(lots<=0.0)
   {
      g_risk_gate_state="LOCKED";
      g_risk_gate_reason="M5 FUND SIZE";
      return false;
   }

   if(!PreTradeRiskGate(false,lots,"M5 ENTRY"))
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
      ok = trade.Buy(lots, _Symbol, 0.0, 0.0, tp, comment);
   else
      ok = trade.Sell(lots, _Symbol, 0.0, 0.0, tp, comment);

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
   double tol = InpM1InsideM5TolerancePts * PointValue();
   return (price >= m5.low - tol && price <= m5.high + tol);
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

bool FindM5OppositeSignal(const bool current_buy,
                          const MqlRates &bar,
                          const MqlRates &prev,
                          bool &opposite_buy,
                          double &signal_level)
{
   for(int i=0; i<ArraySize(g_levels); ++i)
   {
      if(!g_levels[i].active || !g_levels[i].revisited)
         continue;

      bool signal=false;
      bool buy=false;

      if(g_levels[i].type==LEVEL_BREAKOUT_BULL ||
         g_levels[i].type==LEVEL_BREAKOUT_BEAR)
      {
         signal=BreakoutSignal(g_levels[i],bar);
         buy=(g_levels[i].type==LEVEL_BREAKOUT_BULL);
      }
      else
      {
         signal=ReversalSignal(g_levels[i],bar,prev);
         buy=(g_levels[i].type==LEVEL_REVERSAL_LOW);
      }

      if(signal && buy!=current_buy)
      {
         opposite_buy=buy;
         signal_level=g_levels[i].price;
         return true;
      }
   }
   return false;
}




bool IsHedgingAccount()
{
   long mode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return (mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}

bool HasStraddlePosition(ulong &ticket)
{
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(StringFind(c,"NEOFL STRADDLE")>=0)
      {
         ticket=t;
         return true;
      }
   }
   ticket=0;
   return false;
}

//+------------------------------------------------------------------+
//| v3.86: is the external brain alive?                               |
//|                                                                   |
//| D-002 -- absence of a signal must itself be observable. With the  |
//| brain external, a script that is not attached, has been stopped,  |
//| or has crashed leaves stale global variables behind. Those look   |
//| exactly like a brain that is deliberately saying "do nothing".    |
//|                                                                   |
//| MT5 global variables persist across terminal restarts, so a stale |
//| STRADDLE_ARM from a previous session could arm a straddle sized   |
//| from a position that no longer exists.                            |
//+------------------------------------------------------------------+
bool IsBrainAlive()
{
   if(InpInternalBrain) return true;   // the EA is its own brain

   const double hb = ReadObserverValue("HEARTBEAT", 0.0);
   if(hb <= 0.0)
   {
      static datetime warned_never = 0;
      if(TimeCurrent() - warned_never > 60)
      {
         warned_never = TimeCurrent();
         Print("NeoFL: BRAIN NOT DETECTED. Attach NeoFL_MasterBrain_Script_v3_85 "
               "to this chart. No straddle will be armed until it is running.");
      }
      return false;
   }

   const int age = (int)(TimeCurrent() - (datetime)hb);
   if(age > InpBrainMaxAgeSeconds)
   {
      static datetime warned_stale = 0;
      if(TimeCurrent() - warned_stale > 60)
      {
         warned_stale = TimeCurrent();
         PrintFormat("NeoFL: BRAIN STALE - last heartbeat %ds ago (limit %ds). "
                     "Treating its state as DATA_UNAVAILABLE; no straddle will be armed.",
                     age, InpBrainMaxAgeSeconds);
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| v3.86: validate what the brain asked for before executing it.     |
//|                                                                   |
//| The EA does not size the straddle -- that is the script's job.    |
//| But an executor should still refuse an instruction that cannot    |
//| work, rather than placing a position that can never recover.      |
//+------------------------------------------------------------------+
double ValidateStraddleLots(const double requested, const ulong main_ticket)
{
   if(requested <= 0.0)
   {
      if(InpStraddleLogSizing)
         Print("NeoFL STRADDLE: refused - brain requested zero lots");
      return 0.0;
   }

   if(main_ticket == 0 || !PositionSelectByTicket(main_ticket))
      return 0.0;

   const double main_lot = PositionGetDouble(POSITION_VOLUME);

   const double step = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 0.01);
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   // CEIL, never floor: flooring under-covers the gap, so the basket stops short
   // of zero and the handover never fires.
   double lots = NormalizeDouble(MathCeil(MathMax(requested, vmin)/step - 1e-9)*step, 2);

   const double cap = EffectiveStraddleCap();
   if(cap > 0.0 && lots > cap)
   {
      if(InpStraddleLogSizing)
         PrintFormat("NeoFL STRADDLE: REFUSED - brain asked %.2f, cap is %.2f (%s). "
                     "Capping would under-cover the gap, so the basket could never "
                     "reach zero.",
                     lots, cap,
                     InpStraddleCapPctBalance > 0.0
                        ? StringFormat("%.1f%% of balance", InpStraddleCapPctBalance)
                        : "fixed lots");
      return 0.0;
   }

   // Delta-neutral guard: equal and opposite legs offset exactly, so basket P/L
   // freezes and NO price ever brings it to zero. Waiting would wait forever.
   if(lots <= main_lot)
   {
      if(InpStraddleLogSizing)
         PrintFormat("NeoFL STRADDLE: REFUSED - %.2f is not larger than main %.2f. "
                     "The basket would be delta-neutral and could never reach zero.",
                     lots, main_lot);
      return 0.0;
   }

   if(InpStraddleLogSizing)
   {
      const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      const bool   isbuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      const double now   = isbuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      PrintFormat("NeoFL STRADDLE: brain requested %.4f -> executing %.2f | "
                  "main %.2f @ %.5f, now %.5f, gap %.5f | brain P/L %.2f",
                  requested, lots, main_lot, entry, now, MathAbs(entry-now),
                  ReadObserverValue("BASKET_PNL", 0.0));
   }
   return lots;
}

//+------------------------------------------------------------------+
//| D-006: derive the straddle cap from the account, not from a       |
//| hard-coded lot count.                                             |
//|                                                                   |
//| per_lot_per_unit = tick_value / tick_size                         |
//|   = account currency earned by 1.00 lot per 1.0 of price movement |
//|                                                                   |
//| It comes from the broker, so cent accounts, standard accounts,    |
//| any account currency and any instrument all resolve correctly     |
//| without inferring anything.                                       |
//+------------------------------------------------------------------+
double AccountCurrencyPerLotPerUnit()
{
   const double tickval  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   const double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickval <= 0.0 || ticksize <= 0.0) return 0.0;
   return tickval / ticksize;
}

double EffectiveStraddleCap()
{
   if(InpStraddleCapPctBalance <= 0.0)
      return InpStraddleHardCap;              // operator chose a fixed lot cap

   const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   const double per = AccountCurrencyPerLotPerUnit();
   if(bal <= 0.0 || per <= 0.0)
   {
      // Cannot price the instrument against the account. Fall back rather than
      // guess -- an unpriceable cap is not a safe cap.
      static datetime warned = 0;
      if(TimeCurrent() - warned > 300)
      {
         warned = TimeCurrent();
         PrintFormat("NeoFL: cannot derive cap from account (balance=%.2f, per-lot=%.5f); "
                     "using fixed %.2f lots", bal, per, InpStraddleHardCap);
      }
      return InpStraddleHardCap;
   }
   return (bal * InpStraddleCapPctBalance / 100.0) / per;
}

double CalculateStraddleExecutableLots(const double requested)
{
   double broker_min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double broker_max=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=broker_min;
   double cap=MathMin(broker_max,InpStraddleMaxLot);
   if(cap<broker_min) return 0.0;

   // Straddle CAP EXCEPTION: it is intentionally NOT constrained to 0.01.
   double budget=g_fund_straddle_budget;
   if(InpUseFundEngine && budget>0.0)
   {
      double price=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)+SymbolInfoDouble(_Symbol,SYMBOL_BID))*0.5;
      double margin_one=0.0;
      if(OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,1.0,price,margin_one) && margin_one>0.0)
         cap=MathMin(cap,budget/margin_one);
   }

   double lots=MathMin(MathMax(requested,broker_min),cap);
   if(lots<broker_min) return 0.0;
   lots=MathCeil(lots/step-1e-9)*step;
   return NormalizeDouble(MathMin(lots,cap),2);
}

bool OpenStraddle(const bool buy,const double lots,const double start_price)
{
   if(!InpEnableStraddle || !InpStraddleAllowInGrace)
   {
      // In normal ACTIVE state this is still allowed; the grace flag only
      // controls whether straddles may be initiated once grace begins.
   }

   if(!IsHedgingAccount())
   {
      Print("NeoFL STRADDLE skipped: account is not hedging mode.");
      return false;
   }

   ulong existing=0;
   if(HasStraddlePosition(existing))
      return false;

   double exec_lots=CalculateStraddleExecutableLots(lots);
   if(exec_lots<=0.0)
      return false;

   if(!PreTradeRiskGate(true,exec_lots,"M3 STRADDLE"))
      return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFilling(InpFillingMode);

   bool ok=false;
   if(buy)
      ok=trade.Buy(exec_lots,_Symbol,0.0,0.0,0.0,"NEOFL STRADDLE BUY");
   else
      ok=trade.Sell(exec_lots,_Symbol,0.0,0.0,0.0,"NEOFL STRADDLE SELL");

   if(ok)
   {
      PrintFormat("NeoFL STRADDLE opened: %s %.2f lots at %.2f",
                  buy?"BUY":"SELL",exec_lots,start_price);
      return true;
   }

   Print("NeoFL STRADDLE failed. Retcode=",trade.ResultRetcode(),
         " ",trade.ResultRetcodeDescription());
   return false;
}

bool CloseStraddle()
{
   ulong ticket=0;
   if(!HasStraddlePosition(ticket))
      return false;

   if(trade.PositionClose(ticket))
   {
      Print("NeoFL STRADDLE closed by basket observer.");
      return true;
   }
   return false;
}

bool CloseMainAndStraddle()
{
   bool ok=true;
   ulong straddle=0;
   if(HasStraddlePosition(straddle))
      ok=trade.PositionClose(straddle) && ok;

   ulong main_ticket=0;
   if(SelectOurPosition(main_ticket) && PositionSelectByTicket(main_ticket))
   {
      string c=PositionGetString(POSITION_COMMENT);
      if(StringFind(c,"NEOFL STRADDLE")<0)
         ok=trade.PositionClose(main_ticket) && ok;
   }
   return ok;
}

bool ManageOrphanStraddle()
{
   ulong st=0;
   if(!HasStraddlePosition(st))
      return false;

   ulong main_ticket=0;
   bool has_main=SelectOurPosition(main_ticket);
   if(has_main)
      return false;

   // Main trade is already gone.  The remaining straddle is part of the
   // SAME basket and must not be closed merely because the straddle itself
   // is profitable.  Only the Master Brain's combined basket target can
   // authorize the residual-leg exit.
   if(!InpStraddleCloseOnBasketBE)
      return false;

   double basket=ReadObserverValue("BASKET_PNL",0.0);
   double target=ReadObserverValue("DESIRED_BASKET_PROFIT",InpStraddleProfitBufferMoney);
   double tolerance=InpStraddleExitToleranceMoney;

   if(basket >= target-tolerance)
   {
      trade.SetExpertMagicNumber(InpMagic);
      if(trade.PositionClose(st))
      {
         PrintFormat("NeoFL STRADDLE residual closed: basket P/L %.2f reached target %.2f",
                     basket,target);
         return true;
      }
   }
   return false;
}

bool EnforceMasterBrainBasketGuard()
{
   double emergency=ReadObserverValue("BASKET_EMERGENCY",0.0);
   double terminate=ReadObserverValue("BASKET_TERMINATE",0.0);
   if(emergency>0.5 || terminate>0.5)
   {
      if(CloseMainAndStraddle())
      {
         GlobalVariableSet(ObserverKey("BASKET_EMERGENCY"),0.0);
         GlobalVariableSet(ObserverKey("BASKET_TERMINATE"),0.0);
         Print("NeoFL MASTER BRAIN: basket termination executed.");
         return true;
      }
   }
   return false;
}

bool ExecuteObserverStraddleState()
{
   if(!g_observer_ok)
      return false;

   if(g_observer_basket_terminate)
   {
      if(CloseMainAndStraddle())
      {
         g_observer_basket_terminate=false;
         GlobalVariableSet(ObserverKey("BASKET_TERMINATE"),0.0);
         return true;
      }
   }

   if(g_observer_straddle_exit)
   {
      if(CloseStraddle())
      {
         g_observer_straddle_exit=false;
         GlobalVariableSet(ObserverKey("STRADDLE_EXIT"),0.0);
         return true;
      }
   }

   if(g_observer_straddle_arm && IsBrainAlive())
   {
      ulong st=0;
      if(HasStraddlePosition(st))
         return false;

      bool main_buy=false;
      ulong main_ticket=0;
      if(SelectOurPosition(main_ticket) && PositionSelectByTicket(main_ticket))
      {
         main_buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         bool straddle_buy=!main_buy;
         double px=straddle_buy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
         const double str_lots=ValidateStraddleLots(g_observer_straddle_lots,main_ticket);
         if(str_lots<=0.0)
            return false;   // refused: unusable instruction

         if(OpenStraddle(straddle_buy,str_lots,px))
         {
            g_observer_straddle_arm=false;
            GlobalVariableSet(ObserverKey("STRADDLE_ARM"),0.0);
            return true;
         }
      }
   }
   return false;
}

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

// Validate configured lot floors against the broker's symbol constraints.
bool ValidateConfiguredLotFloors()
{
   double broker_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double broker_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double broker_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(broker_min <= 0.0)
      broker_min = 0.01;
   if(broker_max <= 0.0)
      broker_max = 100.0;
   if(broker_step <= 0.0)
      broker_step = broker_min;

   if(InpMinLotM5 < broker_min)
   {
      PrintFormat("NeoFL: InpMinLotM5 %.4f is below broker minimum %.4f.", InpMinLotM5, broker_min);
      return false;
   }

   if(InpMinLotM5 > broker_max)
   {
      PrintFormat("NeoFL: InpMinLotM5 %.4f exceeds broker maximum %.4f.", InpMinLotM5, broker_max);
      return false;
   }
   PrintFormat("NeoFL lot validation: broker min=%.4f max=%.4f step=%.4f | M5 floor=%.4f",
               broker_min, broker_max, broker_step, InpMinLotM5);
   return true;
}



void UpdateIntegratedObserver()
{
   // LIVE feeder mode: the attached data-feeder script is the observation
   // authority. TESTER mode retains the internal observer because scripts
   // are not part of Strategy Tester execution.
   if(!InpUseObserverNetwork) return;
   if(ExternalFeederActive()) return;

   // v3.86: the EA is EXECUTION ONLY. When the MasterBrain script is the brain,
   // the EA must not write the shared state -- doing so on every tick is what
   // overwrote the script's correct straddle size in v3.85.
   if(InpInternalBrain)
   NeoFLObs_Update(InpObserverPrefix,_Symbol,InpMagic,
                   InpObserverActivationDDPct,InpObserverActivationATR,
                   InpObserverHardDDPct,InpObserverGraceM3Bars,
                   InpObserverRecoveryDDPct,InpStraddleProjectionATR,
                   InpStraddleProfitBufferMoney,
                   InpStraddleSafetyFactor,InpStraddleMaxLot,
                   InpStraddleExitToleranceMoney,InpObserverProbabilityTrades);
}

double EmergencyATR_M1()
{
   int h=iATR(_Symbol,PERIOD_M1,14);
   if(h==INVALID_HANDLE) return 0.0;
   double b[];
   ArraySetAsSeries(b,true);
   double v=0.0;
   if(CopyBuffer(h,0,1,1,b)==1) v=b[0];
   IndicatorRelease(h);
   return v;
}

double NormalizePriceToTick(const double price)
{
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0.0) tick=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(tick<=0.0) return NormalizeDouble(price,_Digits);
   return NormalizeDouble(MathRound(price/tick)*tick,_Digits);
}

bool EmergencySLAllowedByLoss(const bool buy,const double lots,const double sl)
{
   if(InpEmergencyMaxLossMoney<=0.0)
      return true;

   double price=buy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(price<=0.0) return false;

   double pnl=0.0;
   ENUM_ORDER_TYPE type=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,lots,price,sl,pnl))
      return false;

   return (MathAbs(pnl)<=InpEmergencyMaxLossMoney);
}

// Calculates protection from the last CLOSED M1 structure, while live ticks
// are used only to detect an actual breach.
bool UpdateEmergencyProtection(const ulong ticket)
{
   if(!InpEmergencyProtection || ticket==0 || !PositionSelectByTicket(ticket))
   {
      g_emergency_active=false;
      return false;
   }

   bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double lots=PositionGetDouble(POSITION_VOLUME);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(bid<=0.0 || ask<=0.0 || lots<=0.0) return false;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   ArrayResize(r,3);
   if(CopyRates(_Symbol,PERIOD_M1,0,3,r)<3)
      return false;

   // Only closed M1 candle can update the structural protection level.
   if(r[1].time==g_emergency_structure_bar && g_emergency_sl>0.0)
      return true;

   double atr=EmergencyATR_M1();
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double distance=MathMax(InpEmergencyMinPoints*point,
                           atr*InpEmergencyDistanceATR);
   if(distance<=0.0) return false;

   double candidate=buy ? bid-distance : ask+distance;

   // Use the last CLOSED M1 candle extreme as a secondary structural anchor.
   // Never move protection farther from the current market than the dynamic
   // distance; and never loosen an already tighter protection level.
   if(buy)
   {
      double structural=r[1].low-distance*0.15;
      candidate=MathMax(candidate,structural);

      if(g_emergency_sl<=0.0)
         g_emergency_sl=candidate;
      else
         g_emergency_sl=MathMax(g_emergency_sl,candidate);
   }
   else
   {
      double structural=r[1].high+distance*0.15;
      candidate=MathMin(candidate,structural);

      if(g_emergency_sl<=0.0)
         g_emergency_sl=candidate;
      else
         g_emergency_sl=MathMin(g_emergency_sl,candidate);
   }

   g_emergency_sl=NormalizePriceToTick(g_emergency_sl);

   if(buy && g_emergency_sl>=bid)
      g_emergency_sl=NormalizePriceToTick(bid-distance);
   if(!buy && g_emergency_sl<=ask)
      g_emergency_sl=NormalizePriceToTick(ask+distance);

   g_emergency_active=true;
   g_emergency_structure_bar=r[1].time;

   if(!EmergencySLAllowedByLoss(buy,lots,g_emergency_sl))
   {
      g_emergency_active=false;
      return false;
   }

   // Broker-side SL is the catastrophe layer. It is NOT the original entry SL.
   if(InpEmergencyBrokerSL)
   {
      double tp=PositionGetDouble(POSITION_TP);
      if(buy)
      {
         if(g_emergency_sl<bid)
            trade.PositionModify(ticket,g_emergency_sl,tp);
      }
      else
      {
         if(g_emergency_sl>ask)
            trade.PositionModify(ticket,g_emergency_sl,tp);
      }
   }

   return true;
}

// Tick-level breach detector. Do NOT wait for M1 close here.
bool EmergencySLBreached(const ulong ticket)
{
   if(!InpEmergencyProtection || !g_emergency_active || g_emergency_sl<=0.0)
      return false;
   if(!PositionSelectByTicket(ticket))
      return false;

   bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(buy)
      return (bid<=g_emergency_sl);
   return (ask>=g_emergency_sl);
}

void ResetEmergencyState()
{
   g_emergency_sl=0.0;
   g_emergency_active=false;
   g_emergency_structure_bar=0;
}

string ObserverKey(const string suffix)
{
   return InpObserverPrefix+"_"+_Symbol+"_"+(string)InpMagic+"_"+suffix;
}

double ReadObserverValue(const string suffix,const double fallback=0.0)
{
   string key=ObserverKey(suffix);
   if(!GlobalVariableCheck(key))
      return fallback;
   return GlobalVariableGet(key);
}

string FeederKey(const string suffix)
{
   return InpDataFeederPrefix+"_"+_Symbol+"_"+(string)InpMagic+"_"+suffix;
}

double ReadFeederValue(const string suffix,const double fallback=0.0)
{
   string key=FeederKey(suffix);
   if(!GlobalVariableCheck(key))
      return fallback;
   return GlobalVariableGet(key);
}

bool ExternalFeederActive()
{
   return (InpUseExternalDataFeeder && !IsTesterMode());
}

bool ReadObserverNetwork()
{
   // In live feeder mode, read the shared observer bus produced by the
   // continuous data-feeder script. In tester mode, update internally.
   UpdateIntegratedObserver();
   if(!InpUseObserverNetwork)
   {
      g_observer_ok=true;
      g_observer_m1_state="DISABLED";
      return true;
   }
   g_observer_ok=true;
   g_observer_update=TimeCurrent();
   int st=(int)ReadObserverValue("M1_STATE",0.0);
   if(st==4) g_observer_m1_state="THESIS INVALID";
   else if(st==3) g_observer_m1_state="THESIS DECAY";
   else if(st==2) g_observer_m1_state="PROFIT LOCK";
   else if(st==1) g_observer_m1_state="WAITING";
   else g_observer_m1_state="SILENT";
   g_observer_opposite=(ReadObserverValue("M1_OPPOSITE",0.0)>0.5);
   g_observer_exit=(ReadObserverValue("M1_EXIT",0.0)>0.5);
   g_observer_mfe_money=ReadObserverValue("MFE_MONEY",0.0);
   g_observer_mae_money=ReadObserverValue("MAE_MONEY",0.0);
   g_observer_win_prob=ReadObserverValue("WIN_PROB",0.0);
   g_observer_loss_prob=ReadObserverValue("LOSS_PROB",0.0);
   g_observer_dd_pct=ReadObserverValue("DD_PCT",0.0);
   g_observer_recovery_coverage=ReadObserverValue("RECOVERY_COVERAGE",0.0);
   g_observer_position_loss_pct=ReadObserverValue("POSITION_LOSS_PCT",0.0);
   g_observer_straddle_lots=ReadObserverValue("STRADDLE_LOTS",0.0);
   g_observer_straddle_required=ReadObserverValue("STRADDLE_REQUIRED_LOTS",0.0);
   g_observer_straddle_coverage=ReadObserverValue("STRADDLE_COVERAGE",0.0);
   g_observer_straddle_start=ReadObserverValue("STRADDLE_START",0.0);
   g_observer_risk_state=(int)ReadObserverValue("RISK_STATE",0.0);
   g_observer_straddle_arm=(ReadObserverValue("STRADDLE_ARM",0.0)>0.5);
   g_observer_straddle_exit=(ReadObserverValue("STRADDLE_EXIT",0.0)>0.5);
   g_observer_basket_terminate=(ReadObserverValue("BASKET_TERMINATE",0.0)>0.5);
   return true;
}

bool ObserverAllowsNewExposure()
{
   if(!InpUseObserverNetwork)
      return true;
   if(ReadObserverNetwork())
      return true;
   return !InpObserverFailClosed;
}

int OnInit()
{
   //--- v3.86 startup guards ---------------------------------------------------
   // Every refusal states what MT5 actually reported, and goes to the chart as
   // well as the log -- a refusal nobody can see is the same as a silent failure.
   const ENUM_ACCOUNT_TRADE_MODE  acct=
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   const ENUM_ACCOUNT_MARGIN_MODE mm=
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);

   const string acct_name = acct==ACCOUNT_TRADE_MODE_DEMO    ? "DEMO"
                          : acct==ACCOUNT_TRADE_MODE_CONTEST ? "CONTEST"
                          : acct==ACCOUNT_TRADE_MODE_REAL    ? "REAL"
                          : "UNKNOWN("+IntegerToString((int)acct)+")";
   const string mm_name   = mm==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "HEDGING"
                          : mm==ACCOUNT_MARGIN_MODE_RETAIL_NETTING ? "NETTING"
                          : mm==ACCOUNT_MARGIN_MODE_EXCHANGE       ? "EXCHANGE"
                          : "UNKNOWN("+IntegerToString((int)mm)+")";

   PrintFormat("NeoFL v%s startup check | account=%s | margin=%s | server=%s | symbol=%s",
               NEOFL_VERSION, acct_name, mm_name, AccountInfoString(ACCOUNT_SERVER), _Symbol);

   // D-005: the straddle cannot exist on a netting account, and in this strategy
   // the basket IS the risk control -- so running there would trade unprotected.
   if(mm!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      const string why=StringFormat(
         "NeoFL v" NEOFL_VERSION " REFUSED TO START\n"
         "Account margin mode is %s, not HEDGING.\n"
         "The recovery straddle needs a long and a short open at once, which this\n"
         "account cannot do. Since the basket is the only risk control in this\n"
         "strategy, running here would trade unprotected.",
         mm_name);
      Print(why);
      Comment(why);
      return INIT_FAILED;
   }
   Comment("");

   Print("=====================================================");
   PrintFormat("NeoFL v%s | %s ACCOUNT | HEDGING | brain=%s | cap=%.2f",
               NEOFL_VERSION, acct_name,
               InpInternalBrain?"INTERNAL (EA writes state)":"EXTERNAL SCRIPT",
               InpStraddleHardCap);
   if(!InpInternalBrain)
   {
      Print("  EA IS EXECUTION ONLY. Attach NeoFL_MasterBrain_Script_v3_85 to this chart.");
      Print("  Without it, no straddle will be armed - by design, not by failure.");
   }
   // D-006: report what the account actually is and what was derived from it, for
   // every account type -- not only real ones. An inference the operator cannot see
   // is an inference they have to trust (D-002).
   {
      const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      const string ccy = AccountInfoString(ACCOUNT_CURRENCY);
      const double per = AccountCurrencyPerLotPerUnit();
      const double cap = EffectiveStraddleCap();

      // D-010: the full instrument specification, read from the broker. Nothing about
      // contract economics may be assumed -- "0.01 lot = 1 cent per dollar" was an
      // inference during analysis and must come from these numbers instead.
      Print("  ---- INSTRUMENT SPECIFICATION (from broker) ----");
      PrintFormat("    symbol        %s", _Symbol);
      PrintFormat("    contract size %.2f", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
      PrintFormat("    tick size     %.8f", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
      PrintFormat("    tick value    %.8f %s", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ccy);
      PrintFormat("    point         %.8f", SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      PrintFormat("    digits        %d", (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      PrintFormat("    volume min    %.4f", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
      PrintFormat("    volume max    %.4f", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
      PrintFormat("    volume step   %.4f", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
      PrintFormat("    currency      %s", ccy);
      PrintFormat("    price now     bid %.*f  ask %.*f",
                  (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
                  SymbolInfoDouble(_Symbol, SYMBOL_BID),
                  (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      PrintFormat("    balance       %.2f %s", bal, ccy);
      Print("  -----------------------------------------------");

      if(per > 0.0)
      {
         PrintFormat("  a 1.00 price move costs %.2f %s per lot", per, ccy);
         PrintFormat("    main  %.2f lots -> %.2f %s (%.2f%% of balance)",
                     InpLots, per*InpLots, ccy, bal>0.0 ? per*InpLots/bal*100.0 : 0.0);
         PrintFormat("    cap   %.2f lots -> %.2f %s (%.2f%% of balance)  [%s]",
                     cap, per*cap, ccy, bal>0.0 ? per*cap/bal*100.0 : 0.0,
                     InpStraddleCapPctBalance > 0.0
                        ? StringFormat("derived from %.1f%% of balance", InpStraddleCapPctBalance)
                        : "fixed lot cap");
         if(per*cap > 0.0 && bal > 0.0)
            PrintFormat("  at the cap, a %.2f move would exhaust the balance", bal/(per*cap));
      }
      else
      {
         Print("  WARNING: broker did not supply usable tick value/size; cap could not be");
         PrintFormat("  derived from the account and falls back to %.2f lots.", cap);
      }
   }

   if(acct==ACCOUNT_TRADE_MODE_REAL)
   {
      Print("  Straddle sizing path is new in this build. Verify the first straddle's");
      Print("  arithmetic in the Experts log before leaving this unattended.");
   }
   Print("  Do NOT attach NeoFL_Straddle_Observer_v3_85 - it writes NEOFL_SB_*,");
   Print("  which nothing reads, and duplicates the MasterBrain's work.");
   Print("=====================================================");
   //--- end guards -------------------------------------------------------------

   if(!ValidateConfiguredLotFloors())
      return(INIT_PARAMETERS_INCORRECT);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   ArrayResize(g_levels, 0);
   g_last_bar_time = iTime(_Symbol, InpTimeframe, 0);

   PrintFormat("NeoFL Candle Revisit Engine v%s initialized. EA is the only execution authority; the MasterBrain script is the decision authority.", NEOFL_VERSION);
   UpdateCalendarGovernor(true);
   DashUpdate();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DashDelete();
   ChartRedraw();
}

void OnTick()
{
   // Telemetry: write-only, throttled, and failure-tolerant. If this cannot write,
   // trading is unaffected -- observation must never become a dependency of execution.
   if(InpTelemetry)
   {
      static datetime last_tel = 0;
      if(TimeCurrent() - last_tel >= InpTelemetrySeconds)
      {
         last_tel = TimeCurrent();
         NeoFLTel_State(_Symbol, InpMagic);
      }
   }

   UpdateCalendarGovernor(false);
   UpdateFundSnapshot();
   UpdateWithdrawalMetrics();
   ReadObserverNetwork();

   if(EnforceMasterBrainBasketGuard())
      return;

   // Execution EA consumes observer decisions. Observers never trade.
   ManageRecoveryBasket();

   // IMPORTANT: straddle lifecycle must continue even after the main
   // position has already closed. This prevents a profitable residual
   // straddle from being stranded until the end of a backtest.
   ManageOrphanStraddle();
   ExecuteObserverStraddleState();

   DashUpdate();

   ulong ticket=0;
   if(SelectOurPosition(ticket))
   {
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);

      // Update protection only from the last CLOSED M1 candle.
      UpdateEmergencyProtection(ticket);

      // But breach detection is tick-level: a fast liquidity sweep must
      // close immediately rather than waiting for the M1 candle to finish.
      if(EmergencySLBreached(ticket))
      {
         Print("NeoFL EMERGENCY EXIT: price crossed dynamic M1 protection level. Ticket=",ticket,
               " SL=",DoubleToString(g_emergency_sl,_Digits));
         if(trade.PositionClose(ticket))
         {
            ResetEmergencyState();
            return;
         }
      }
      double profit=PositionGetDouble(POSITION_PROFIT);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double tp=PositionGetDouble(POSITION_TP);
      double current=buy
                    ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                    : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      // M1 Observer is SILENT until its DD activation threshold.
      // It never closes a normal trade merely because of an M1 reversal.
      ExecuteObserverStraddleState();
   }

   // M5 is the only initial-entry engine.
   if(!PositionSelectByTicket(ticket))
      ResetEmergencyState();

   datetime bar=iTime(_Symbol,InpTimeframe,0);
   if(bar==0 || bar==g_last_bar_time)
      return;

   g_last_bar_time=bar;

   MqlRates rates[];
   ArrayResize(rates,3);
   ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,InpTimeframe,0,3,rates)<3)
      return;

   // Level creation and M5 signal evaluation only.
   ClassifyAndCreateLevels(rates[1],1);
   EvaluateSignals(rates[1],rates[2]);
}

