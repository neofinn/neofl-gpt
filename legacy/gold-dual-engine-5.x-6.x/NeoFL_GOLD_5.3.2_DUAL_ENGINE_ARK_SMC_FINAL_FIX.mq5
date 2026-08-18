//+------------------------------------------------------------------+
// NeoFL 4.3 AUTO CAPITAL: standalone account = 100% strategy pool; dedicated-account mode = 100% strategy capital. No cross-bot capital sharing. terminals but the same login.
//| NeoFL_4_3_SegregatedCapital_GoldPriority_CandleTrail.mq5                                 |
//|                                                                  |
//| NeoFL GOLD 5.3 DUAL ENGINE - Dedicated Gold Active Scanner                     |
//|                                                                  |
//| PURPOSE                                                          |
//| 1. Scan multiple broker symbols from ONE EA/chart.               |
//| 2. Analyze M1/M5/M15/M30/H1/H4 independently per symbol.         |
//| 3. Rank markets by trend, agreement, momentum, volatility,       |
//|    spread and reward/time opportunity.                            |
//| 4. Maintain a live opportunity thesis for the selected market.  |
//| 5. Dedicated Gold account; Gold-only active scanner; no standalone market.                    |
//|                                                                  |
//| IMPORTANT                                                        |
//| The EA does NOT require separate charts for each market or TF.   |
//| MQL5 can request a symbol/timeframe series directly.             |
//|                                                                  |
//| This version combines the multi-market brain with execution,    |
//| Gold active scanning, liquidity-sweep defense and dedicated-account risk management.       |
//| MT5 remains one account; the separation is enforced internally.  |
//+------------------------------------------------------------------+
#property strict

// Dedicated standalone engine: this EA trades ONLY its own asset class.
#define NEOFL_BOT_MODE 1
#property version   "4.20"
#property description "NeoFL GOLD 5.3 DUAL ENGINE - Standalone GOLD Trading Bot"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS
//==================================================================

// NeoFL GOLD 5.3 DUAL ENGINE: GOLD uses the dedicated MT5 account as its full strategy pool. No cross-bot capital sharing.
input int    ScanSeconds = 5;
input int    BarsToRead = 120;
input int    MinBarsRequired = 60;

// Gold-only symbol discovery. The scanner maps only broker Gold/XAU symbols.
input bool AutoDetectBrokerSymbols = true;
input string MarketUniverse =
"XAUUSD;GOLD";

// When true, print the broker-symbol mapping on startup.
input bool PrintSymbolMapping = true;

// Timeframes are deliberately independent from the chart timeframe.
input ENUM_TIMEFRAMES TF1 = PERIOD_M1;
input ENUM_TIMEFRAMES TF2 = PERIOD_M5;
input ENUM_TIMEFRAMES TF3 = PERIOD_M15;
input ENUM_TIMEFRAMES TF4 = PERIOD_M30;
input ENUM_TIMEFRAMES TF5 = PERIOD_H1;
input ENUM_TIMEFRAMES TF6 = PERIOD_H4;

input int FastMAPeriod = 20;
input int SlowMAPeriod = 100;
// Stronger continuous trend confirmation used when SMC is absent.
input int TrendConfirmEMA1 = 50;
input int TrendConfirmEMA2 = 200;
input int TrendRSIPeriod = 14;
input int TrendADXPeriod = 14;
input int TrendMACDFast = 12;
input int TrendMACDSlow = 26;
input double TrendEMAStackWeight = 0.15;
input double TrendRSIWeight = 0.10;
input double TrendMACDWeight = 0.10;
input double TrendADXWeight = 0.10;

input int ATRPeriod = 14;
input int TrendLookback = 20;

input double StrongTrendScore = 0.55;
input double WeakTrendScore = 0.20;
input double HighVolatilityRatio = 1.80;
input double LowVolatilityRatio = 0.55;

input int MaxSpreadPoints = 0;
// 0 = don't use a hard spread filter; scoring still penalizes spread.

input double MinOpportunityScore = 55.0;
input double MinTrendScoreForTrendTrade = 0.45;
input double MinAgreementForTrendTrade = 0.50;

// GOLD trend hierarchy: M5 is the primary trend/execution anchor.
input bool   UseM5PrimaryTrendGate = true;
input double M5PrimaryTrendWeight = 0.30;
input double M5MinTrendScoreForTrade = 0.40;
input bool   RequireM5MomentumAlignment = true;
input bool   GoldTrendOnlyMode = true;
input double GoldM5TrendWeight = 0.40;
input double GoldM15TrendWeight = 0.20;
input double GoldM30TrendWeight = 0.10;
input double GoldH1TrendWeight = 0.15;
input double GoldH4TrendWeight = 0.15;
input double GoldMinimumDirectionalScore = 0.55;
input double GoldMinimumTrendAgreement = 0.60;
// M1 has no independent trend authority. It is used for liquidity sweeps,
// entry timing and position trailing/micro-exit management.
input bool   GoldM1TrailingOnly = true;
input bool   GoldM1LiquidityEnabled = true;
input int    GoldM1LiquidityLookback = 20;
input double GoldM1SweepATR = 1.20;
input double GoldM1ReclaimATR = 0.25;
input double GoldM1DisplacementATR = 1.50;
input double GoldM1LiquidityBufferATR = 0.05;
input bool   GoldM1RequireReclaim = true;
input bool   GoldM1UseForEntryTiming = true;
// Smart Money Concepts: market structure, liquidity imbalance and dealing range.
input bool   GoldSMCEnabled = true;
input int    GoldSMCSwingLookback = 60;
input double GoldSMCMinScore = 0.55;
input bool   GoldSMCRequireBOS = true;
input bool   GoldSMCRequiredForTrade = false;
input double GoldSMCBonusWeight = 0.15;
// Rare high-conviction SMC tier. Larger risk is earned only when
// SMC + M5 trend + M1 liquidity are aligned; still capped.
input double GoldSMCEventRiskPercent = 0.90;
input double GoldSMCExceptionalRiskPercent = 1.00;
input double GoldSMCEventMinScore = 0.70;
input double GoldSMCExceptionalMinScore = 0.85;
input bool   GoldSMCRequireM1ForEventTier = true;
input double GoldSMCEventRewardATRBoost = 0.50;
input double GoldSMCExceptionalRewardATRBoost = 0.85;
// Supply/Demand + M5 reversal engine.
// Zones are used as confluence and trade-location filters, not as standalone signals.
input bool   GoldSupplyDemandEnabled = true;
input int    GoldSDLookbackBars = 80;
input int    GoldSDImpulseBars = 3;
input double GoldSDImpulseATR = 1.20;
input double GoldSDZoneATR = 0.45;
input double GoldSDMinStrength = 0.55;
input double GoldSDNearZoneATR = 0.60;
input double GoldSDRejectionBonus = 0.15;
// ArkBot-style parallel SMC / Supply-Demand engine.
// It runs beside the normal NeoFL trend engine and competes for the best
// qualified trade; it does not replace the normal indicator engine.
input bool   GoldArkStyleEngineEnabled = true;
input double GoldArkMinScore = 0.68;
input int    GoldArkLookbackBars = 100;
input int    GoldArkBaseBars = 2;
input double GoldArkImpulseATR = 1.35;
input double GoldArkZoneATR = 0.50;
input double GoldArkFreshnessATR = 0.10;
input double GoldArkNearZoneATR = 0.25;
input double GoldArkLiquidityWeight = 0.30;
input double GoldArkSMCWeight = 0.30;
input double GoldArkZoneWeight = 0.25;
input double GoldArkM5Weight = 0.15;
input double GoldArkRiskPercent = 0.75;
input double GoldArkExceptionalRiskPercent = 1.00;
input double GoldArkExceptionalScore = 0.86;
input double GoldArkRewardATRBoost = 0.45;
input bool   GoldArkRequireFreshZone = true;
input bool   GoldArkRequireLiquidityConfirmation = true;
input bool   GoldArkRequireStructureConfirmation = true;


// M5 can lead a developing reversal; higher TFs provide context rather than a hard veto.
input bool   GoldM5ReversalEngine = true;
input double GoldM5ReversalMinScore = 0.58;
input double GoldM5ReversalTrendWeight = 0.45;
input double GoldM15ConfirmWeight = 0.25;
input double GoldHTFContextWeight = 0.15;
input double GoldM1LiquidityWeight = 0.15;


input bool   GoldSMCUseFVG = true;
input bool   GoldSMCUseOrderBlock = true;
input bool   GoldSMCUsePremiumDiscount = true;

// Reward-aware position sizing. Waiting time is only a bounded quality
// modifier; it can never create unlimited leverage or override risk caps.
input bool   GoldRewardAwareSizing = true;
input double GoldBaseRiskPercent = 0.50;
input double GoldMaxRiskPercent = 1.00;
input double GoldMinExpectedR = 1.50;
input double GoldQualityRiskFloor = 0.75;
input double GoldQualityRiskCeiling = 1.50;
input int    GoldMinMinutesBetweenTrades = 10;
input double GoldPatienceBoostMax = 1.15;




input bool PreferTrendMarkets = true;
input bool PreferBreakoutMarkets = true;
input bool AvoidExtremeVolatility = true;

// Optional: only scan symbols currently available in Market Watch.
input bool AutoSelectSymbols = true;

// Dashboard
input bool ShowDashboard = true;
input int DashboardTopN = 8;

//==================================================================
// GLOBAL MARKET SESSION ENGINE
//==================================================================
//
// NeoFL does not treat every market as equally attractive in every
// session. It uses UTC-based broad session windows so DST changes do
// not require a hard-coded broker server-time offset.
//
// Sydney/Australia : 21:00-07:00 UTC
// Tokyo/Asia       : 00:00-09:00 UTC
// London/Europe    : 07:00-17:00 UTC
// New York/US      : 12:00-22:00 UTC
//
// The windows deliberately overlap. The engine scores session
// relevance rather than blocking trading outside a single window.
// Crypto is treated as 24/7, while each traditional asset gets a
// market-specific session affinity.
//
// The UTC windows are broad by design. They tolerate normal DST
// shifts without making the scanner blind for an hour.
//==================================================================

input bool EnableSessionEngine = true;
input bool PreferActiveSessions = true;
input bool PenalizeDeadSessions = false;
input double ActiveSessionBonus = 8.0;
input double SessionOverlapBonus = 5.0;
input double DeadSessionPenalty = 5.0;
input int SessionRelevanceFloor = 25;

//==================================================================
// EXECUTION ENGINE
//==================================================================
// 3.5 is the first execution-enabled version. The scanner remains
// multi-market/multi-timeframe, but the best qualified market can
// now actually receive an order.
input bool EnableTrading = true;
input bool DryRun = false;
input bool AllowTrendTrading = true;
input bool AllowSidewaysStraddle = false;
input bool OneActiveMarketOnly = true;
input double FixedLots = 0.10;
input bool UseRiskBasedLots = false;
input double RiskPercent = 0.50;
input double MaxLots = 5.0;

input double EntryATRMultiplier = 0.35;
input double InitialSL_ATR = 1.20;
input double FixedTP_ATR = 2.20;
input double TrailingStart_ATR = 0.60;
input double TrailingDistance_ATR = 0.35;
input double TrailStep_ATR = 0.05;
// Profit protection: lock a winning trade before the full ATR trail starts.
// R = original risk from entry to the initial SL.
input bool   EnableBreakEvenLock = true;
input double BreakEvenTrigger_R = 0.15;
input double BreakEvenLock_R = 0.05;
input double ProfitTrailStart_R = 0.35;

// ------------------------------------------------------------
// CANDLE-STRUCTURE TRAILING
// The higher-timeframe brain decides the trade direction/thesis.
// A LOWER execution timeframe then trails only on CLOSED candles.
// For BUY: a favorable closed candle can move SL to candle LOW - buffer.
// For SELL: a favorable closed candle can move SL to candle HIGH + buffer.
// The SL can only ratchet in the profitable direction. Fixed TP never moves.
// ------------------------------------------------------------
input bool EnableCandleStructureTrail = true;
input ENUM_TIMEFRAMES CandleTrailTF = PERIOD_M1;
input double CandleTrailBufferATR = 0.05;
input double CandleTrailMinProfit_R = 0.05;
input bool CandleTrailRequireDirectionalClose = true;
input bool DisableATRProfitTrailWhenCandleTrail = true;
input double SidewaysRangeATR = 0.80;
input double SidewaysStopATR = 0.20;
input double SidewaysSL_ATR = 1.00;
input double SidewaysTP_ATR = 1.60;
input int PendingExpiryMinutes = 20;
input int ReentryCooldownSeconds = 15;
input int MaxCampaignReentries = 2;
input double TrendReentryMinScore = 60.0;
input double TrendReentryMinAgreement = 0.50;
input bool CancelStalePending = true;
input double PendingInvalidTrend = 0.20;
input double PendingOppositeTrend = 0.35;
input int PendingInvalidConfirmations = 2;
input double MaxPendingDistanceATR = 2.50;
input bool UseSessionFilterForExecution = false;
input bool PrintExecutionLog = true;
input bool GoldAlwaysOn = true;
input bool GoldIndependentOfBestMarket = true;
input bool GoldAllowTrendTrading = true;
input bool GoldAllowSidewaysStraddle = false;
input double GoldMinOpportunityScore = 45.0;
input double GoldMinTrendScore = 0.35;
input double GoldMinAgreement = 0.33;
input int GoldPendingExpiryMinutes = 30;
input int GoldReanalysisSeconds = 2;

// GOLD LIQUIDITY-SWEEP / WHIPSAW DEFENSE
input bool   EnableGoldLiquiditySweepDefense = true;
input int    GoldSweepLookbackBars = 20;
input double GoldSweepMinRangeATR = 1.50;
input double GoldSweepMinWickATR = 0.40;
input double GoldSweepLevelBufferATR = 0.05;
input double GoldSweepMaxSpreadATR = 0.35;
input int    GoldShockLockSeconds = 300;
input int    GoldPostSweepConfirmationBars = 2;
input double GoldEmergencyTrailATR = 0.20;
input int    GoldWhipsawWindowSeconds = 900;
input int    GoldMaxShockStopouts = 2;
input bool   GoldCancelPendingOnShock = true;
input bool   GoldProtectPositionOnShock = true;
input bool   GoldBlockOppositeAfterStop = true;
input bool   EnableGoldNewsEngine = false;
input bool   GoldNewsOnlyMajorUSD = true;
input int    GoldNewsPreparationMinutes = 5;
input int    GoldNewsStraddleSecondsBefore = 60;
input int    GoldNewsCampaignMinutes = 10;
input int    GoldNewsMaxReversals = 2;
input double GoldNewsEntryBufferATR = 0.10;
input double GoldNewsTrailBufferATR = 0.05;
input double GoldNewsInitialSL_ATR = 2.00;
input double GoldNewsMaxSpreadATR = 0.75;
input int    GoldNewsRecoveryMinutes = 5;
input bool   GoldNewsUseEconomicCalendar = true;

//==================================================================
// CAPITAL / RISK MANAGER
// Dedicated account: 100% of this account is this bot's strategy pool.
// No cross-bot buckets, no cross-bot reservation, no standalone market.
input bool EnableCapitalManager = true;
input bool ShowCapitalModeInDashboard = true;
input double MaxAccountCapitalUsePercent = 90.0;
input bool PrintRiskManagerLog = true;
input ulong BotMagicNumber = 42001001;

// Standalone position/OCO safety controls.
input int MaxBotPositions = 1;
input bool UseImmediateOCOOnFill = true;
input bool BlockDuplicateEntries = true;
input bool ManageAllBotPositions = true;



//==================================================================
// ENUMS / STRUCTS
//==================================================================

enum MARKET_REGIME
{
   MARKET_UNKNOWN = 0,
   MARKET_STRONG_UP,
   MARKET_STRONG_DOWN,
   MARKET_SIDEWAYS,
   MARKET_TRANSITION,
   MARKET_HIGH_VOL
};

struct TF_STATE
{
   ENUM_TIMEFRAMES tf;
   double trend;
   double momentum;
   double volatility;
   double rangeScore;
   double atrPoints;
   bool valid;
};

struct MARKET_STATE
{
   string symbol;

   TF_STATE tf[6];

   double trend;
   double momentum;
   double agreement;
   double volatility;
   double rangeScore;
   double spreadPoints;

   double atrPoints;
   double breakoutDistancePoints;
   double expectedPointsPerMinute;
   double expectedMinutes;
   double rewardTimeScore;

   double trendScore;
   double opportunityScore;

   double sessionScore;
   double sessionAffinity;
   bool sessionActive;
   bool sessionOverlap;

   int direction;
   MARKET_REGIME regime;

   bool tradable;
   bool dataReady;
};

struct CANDLE_TRAIL_STATE
{
   ulong ticket;
   datetime lastClosedBar;
};

string Symbols[];
MARKET_STATE Markets[];
int MarketCount = 0;
int BestIndex = -1;
datetime LastScan = 0;
CANDLE_TRAIL_STATE CandleTrailStates[];

// Execution state
string ActiveTradeSymbol = "";
int ActiveTradeDirection = 0;
double ActiveCampaignTP = 0.0;
double ActiveInitialEntry = 0.0;
double ActiveOppositeLevel = 0.0;
datetime CampaignStarted = 0;
datetime LastPositionClose = 0;
int CampaignReentries = 0;
int PendingInvalidCount = 0;
string PendingSymbol = "";
int PendingDirection = 0;
double PendingEntry = 0.0;
datetime PendingCreated = 0;
MARKET_REGIME PendingRegime = MARKET_UNKNOWN;

// Dedicated Gold anchor state. Gold is managed as its own strategy
// and does not depend on which market wins the global scanner.
string GoldSymbol = "";
string GoldPendingSymbol = "";
int GoldPendingDirection = 0;
double GoldPendingEntry = 0.0;
datetime GoldPendingCreated = 0;
datetime GoldLastTradeTime = 0;
int GoldPendingInvalidCount = 0;
datetime GoldLastAnalysis = 0;
// Parallel Ark-style execution state. This is transient and reset after
// every execution decision.
bool   GoldArkExecutionMode = false;
int    GoldArkExecutionDirection = 0;
double GoldArkExecutionScore = 0.0;


// Gold liquidity-event state.
bool     GoldShockActive = false;
datetime GoldShockUntil = 0;
datetime GoldShockEventBar = 0;
int      GoldShockDirection = 0;
datetime GoldShockLastStopout = 0;
int      GoldShockStopouts = 0;
datetime GoldShockStopoutWindowStart = 0;
bool     GoldNewsActive = false;
bool     GoldNewsStraddleArmed = false;
bool     GoldNewsPositionActive = false;
int      GoldNewsPositionDirection = 0;
int      GoldNewsReversals = 0;
ulong    GoldNewsEventId = 0;
datetime GoldNewsEventTime = 0;
datetime GoldNewsCampaignUntil = 0;
datetime GoldNewsRecoveryUntil = 0;
datetime GoldNewsLastCalendarScan = 0;
string   GoldNewsEventName = "";
double   GoldNewsUpperLevel = 0.0;
double   GoldNewsLowerLevel = 0.0;
double   GoldNewsTrailSL = 0.0;

// Segregated capital ledger baseline. The account is split virtually at
// startup; realized and floating P&L stay in the bucket that generated it.
double CapitalLedgerStartBalance = 0.0;
datetime CapitalLedgerStartTime = 0;

//==================================================================
// GLOBAL MARKET SESSION ENGINE
//==================================================================

enum MARKET_SESSION
{
   SESSION_SYDNEY = 0,
   SESSION_TOKYO,
   SESSION_LONDON,
   SESSION_NEW_YORK,
   SESSION_OVERLAP,
   SESSION_QUIET,
   SESSION_24H
};

string SessionName(
   MARKET_SESSION session)
{
   if(session==SESSION_SYDNEY)   return "AUSTRALIA/SYDNEY";
   if(session==SESSION_TOKYO)    return "ASIA/TOKYO";
   if(session==SESSION_LONDON)   return "EUROPE/LONDON";
   if(session==SESSION_NEW_YORK) return "AMERICA/NEW YORK";
   if(session==SESSION_OVERLAP)  return "MAJOR OVERLAP";
   if(session==SESSION_24H)      return "24H";
   return "QUIET";
}

bool HourInWindow(
   int hour,
   int startHour,
   int endHour)
{
   if(startHour<endHour)
      return hour>=startHour &&
             hour<endHour;

   // Overnight window, e.g. 21 -> 07.
   return hour>=startHour ||
          hour<endHour;
}

void GetUTCHourMinute(
   int &hour,
   int &minute)
{
   MqlDateTime dt;
   TimeToStruct(
      TimeGMT(),
      dt);

   hour=dt.hour;
   minute=dt.min;
}

MARKET_SESSION CurrentGlobalSession(
   bool &sydney,
   bool &tokyo,
   bool &london,
   bool &newyork,
   bool &overlap)
{
   sydney=false;
   tokyo=false;
   london=false;
   newyork=false;
   overlap=false;

   int hour=0;
   int minute=0;

   GetUTCHourMinute(
      hour,
      minute);

   sydney=
      HourInWindow(
         hour,
         21,
         7);

   tokyo=
      HourInWindow(
         hour,
         0,
         9);

   london=
      HourInWindow(
         hour,
         7,
         17);

   newyork=
      HourInWindow(
         hour,
         12,
         22);

   int activeCount=0;

   if(sydney) activeCount++;
   if(tokyo) activeCount++;
   if(london) activeCount++;
   if(newyork) activeCount++;

   // Two or more major sessions are active.
   overlap=
      activeCount>=2;

   if(overlap)
      return SESSION_OVERLAP;

   if(newyork)
      return SESSION_NEW_YORK;

   if(london)
      return SESSION_LONDON;

   if(tokyo)
      return SESSION_TOKYO;

   if(sydney)
      return SESSION_SYDNEY;

   return SESSION_QUIET;
}

// Returns a broad market-specific session affinity.
// 1.00 = highly relevant, 0.50 = useful, 0.25 = weak,
// 0.00 = not a preferred session.
double SessionAffinity(
   string symbol)
{
   string u=UpperSymbol(symbol);

   bool sydney;
   bool tokyo;
   bool london;
   bool newyork;
   bool overlap;

   CurrentGlobalSession(
      sydney,
      tokyo,
      london,
      newyork,
      overlap);

   if(StringFind(u,"BTC")>=0 ||
      StringFind(u,"XBT")>=0 ||
      StringFind(u,"BITCOIN")>=0)
      return 1.00;

   if(StringFind(u,"XAU")>=0 ||
      StringFind(u,"GOLD")>=0)
   {
      if(overlap) return 1.00;
      if(london || newyork) return 0.90;
      if(tokyo) return 0.55;
      if(sydney) return 0.35;
   }

   // US indices
   if(StringFind(u,"US30")>=0 ||
      StringFind(u,"DJ30")>=0 ||
      StringFind(u,"DJIA")>=0 ||
      StringFind(u,"DOW")>=0 ||
      StringFind(u,"NAS")>=0 ||
      StringFind(u,"USTEC")>=0 ||
      StringFind(u,"US100")>=0 ||
      StringFind(u,"NDX")>=0 ||
      StringFind(u,"SP500")>=0 ||
      StringFind(u,"US500")>=0 ||
      StringFind(u,"SPX")>=0 ||
      StringFind(u,"US2000")>=0 ||
      StringFind(u,"RUSSELL")>=0)
   {
      if(newyork || overlap) return 1.00;
      if(london) return 0.55;
      if(tokyo || sydney) return 0.25;
   }

   // European indices
   if(StringFind(u,"GER40")>=0 || StringFind(u,"GER30")>=0 ||
      StringFind(u,"DE40")>=0 || StringFind(u,"DAX")>=0 ||
      StringFind(u,"UK100")>=0 || StringFind(u,"FTSE")>=0 ||
      StringFind(u,"FRA40")>=0 || StringFind(u,"CAC40")>=0 ||
      StringFind(u,"FR40")>=0 || StringFind(u,"ESP35")>=0 ||
      StringFind(u,"IBEX35")>=0 || StringFind(u,"IT40")>=0 ||
      StringFind(u,"FTSEMIB")>=0 || StringFind(u,"NED25")>=0 ||
      StringFind(u,"AEX")>=0 || StringFind(u,"CH20")>=0 ||
      StringFind(u,"SMI")>=0 || StringFind(u,"SWE30")>=0 ||
      StringFind(u,"OMXS30")>=0 || StringFind(u,"NOR25")>=0)
   {
      if(london || overlap) return 1.00;
      if(newyork) return 0.65;
      if(tokyo || sydney) return 0.20;
   }

   // Asia-Pacific indices
   if(StringFind(u,"JP225")>=0 || StringFind(u,"JPN225")>=0 ||
      StringFind(u,"NIKKEI")>=0 || StringFind(u,"JAPAN225")>=0 ||
      StringFind(u,"HK50")>=0 || StringFind(u,"HSI")>=0 ||
      StringFind(u,"CHINA50")>=0 || StringFind(u,"A50")>=0 ||
      StringFind(u,"AUS200")>=0 || StringFind(u,"ASX200")>=0 ||
      StringFind(u,"INDIA50")>=0 || StringFind(u,"NIFTY")>=0 ||
      StringFind(u,"BANKNIFTY")>=0 || StringFind(u,"SENSEX")>=0 ||
      StringFind(u,"TAIWAN50")>=0 || StringFind(u,"KOSPI")>=0 ||
      StringFind(u,"CAN60")>=0 || StringFind(u,"TSX")>=0)
   {
      if(tokyo || sydney) return 1.00;
      if(overlap) return 0.55;
      if(london || newyork) return 0.45;
   }

   return overlap ? 0.50 : 0.25;
}

// Returns session state for a symbol in one call.
// The session engine is intentionally informational/ranking-oriented;
// execution filtering remains controlled by the dedicated input flags.
void GetSessionState(
   string symbol,
   double &affinity,
   bool &active,
   bool &overlap,
   string &sessionName)
{
   bool sydney=false;
   bool tokyo=false;
   bool london=false;
   bool newyork=false;
   overlap=false;

   MARKET_SESSION session=
      CurrentGlobalSession(
         sydney,
         tokyo,
         london,
         newyork,
         overlap);

   active=(sydney || tokyo || london || newyork);
   affinity=SessionAffinity(symbol);
   sessionName=SessionName(session);
}

//==================================================================
// UTILITIES
//==================================================================

double Clamp(double value,double low,double high)
{
   if(value<low) return low;
   if(value>high) return high;
   return value;
}

string RegimeName(MARKET_REGIME r)
{
   switch(r)
   {
      case MARKET_STRONG_UP:   return "STRONG UP";
      case MARKET_STRONG_DOWN: return "STRONG DOWN";
      case MARKET_SIDEWAYS:    return "SIDEWAYS";
      case MARKET_TRANSITION:  return "TRANSITION";
      case MARKET_HIGH_VOL:    return "HIGH VOL";
   }
   return "UNKNOWN";
}

string TFName(ENUM_TIMEFRAMES tf)
{
   return EnumToString(tf);
}

bool IsSymbolUsable(string symbol)
{
   if(symbol=="")
      return false;

   bool isCustom=false;
   bool exists=SymbolExist(symbol,isCustom);
   if(!exists)
      return false;

   if(AutoSelectSymbols)
   {
      if(!SymbolSelect(symbol,true))
         return false;
   }

   long tradeMode=
      SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);

   if(tradeMode==SYMBOL_TRADE_MODE_DISABLED)
      return false;

   return true;
}

double PointOf(string symbol)
{
   double p=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(p<=0.0) p=0.00001;
   return p;
}

int DigitsOf(string symbol)
{
   return (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
}

double NormalizePrice(string symbol,double p)
{
   return NormalizeDouble(p,DigitsOf(symbol));
}

double CurrentSpreadPoints(string symbol)
{
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
   double point=PointOf(symbol);

   if(ask<=0.0 || bid<=0.0)
      return 999999.0;

   return (ask-bid)/point;
}

double SafeSqrt(double x)
{
   if(x<=0.0) return 0.0;
   return MathSqrt(x);
}

//==================================================================
// DATA / INDICATORS
//==================================================================

bool GetRates(
   string symbol,
   ENUM_TIMEFRAMES tf,
   int count,
   MqlRates &rates[])
{
   ArraySetAsSeries(rates,true);

   int copied=CopyRates(
      symbol,
      tf,
      0,
      count,
      rates);

   return copied>=MinBarsRequired;
}

double CalcATRFromRates(
   string symbol,
   MqlRates &rates[],
   int period)
{
   int n=ArraySize(rates);
   if(n<period+2)
      return 0.0;

   double sum=0.0;
   int used=0;

   for(int i=0;i<period && i+1<n;i++)
   {
      double high=rates[i].high;
      double low=rates[i].low;
      double prevClose=rates[i+1].close;

      double tr=MathMax(
         high-low,
         MathMax(
            MathAbs(high-prevClose),
            MathAbs(low-prevClose)));

      sum+=tr;
      used++;
   }

   if(used==0)
      return 0.0;

   return sum/used;
}

double EMAFromRates(
   MqlRates &rates[],
   int period)
{
   int n=ArraySize(rates);
   if(n<period+5)
      return 0.0;

   // Calculate from oldest -> newest for a stable EMA.
   double alpha=2.0/(period+1.0);
   double ema=rates[n-1].close;

   for(int i=n-2;i>=0;i--)
      ema=alpha*rates[i].close+
          (1.0-alpha)*ema;

   return ema;
}

double PreviousEMAFromRates(
   MqlRates &rates[],
   int period)
{
   int n=ArraySize(rates);
   if(n<period+6)
      return 0.0;

   double alpha=2.0/(period+1.0);
   double ema=rates[n-1].close;

   // Stop before the current bar so this approximates the
   // immediately previous EMA state.
   for(int i=n-2;i>=1;i--)
      ema=alpha*rates[i].close+
          (1.0-alpha)*ema;

   return ema;
}

double MomentumScore(
   MqlRates &rates[],
   double atr)
{
   if(ArraySize(rates)<5 || atr<=0.0)
      return 0.0;

   double delta=rates[0].close-rates[4].close;

   return Clamp(
      delta/(atr*2.0),
      -1.0,
      1.0);
}

double RSIFromRates(MqlRates &rates[],int period)
{
   int n=ArraySize(rates);
   if(period<2 || n<period+2) return 50.0;
   double gain=0.0,loss=0.0;
   for(int i=0;i<period;i++)
   {
      double d=rates[i].close-rates[i+1].close;
      if(d>0.0) gain+=d; else loss-=d;
   }
   if(loss<=0.0) return 100.0;
   double rs=gain/loss;
   return 100.0-(100.0/(1.0+rs));
}

double ADXDirectionalScore(MqlRates &rates[],int period)
{
   int n=ArraySize(rates);
   if(period<2 || n<period+3) return 0.0;
   double plusDM=0.0,minusDM=0.0,trSum=0.0;
   for(int i=0;i<period;i++)
   {
      double up=rates[i].high-rates[i+1].high;
      double dn=rates[i+1].low-rates[i].low;
      if(up>dn && up>0.0) plusDM+=up;
      if(dn>up && dn>0.0) minusDM+=dn;
      double tr1=rates[i].high-rates[i].low;
      double tr2=MathAbs(rates[i].high-rates[i+1].close);
      double tr3=MathAbs(rates[i].low-rates[i+1].close);
      trSum+=MathMax(tr1,MathMax(tr2,tr3));
   }
   if(trSum<=0.0) return 0.0;
   double pdi=100.0*plusDM/trSum;
   double mdi=100.0*minusDM/trSum;
   double denom=pdi+mdi;
   if(denom<=0.0) return 0.0;
   double dx=100.0*MathAbs(pdi-mdi)/denom;
   double strength=Clamp(dx/50.0,0.0,1.0);
   double direction=(pdi>mdi?1.0:(mdi>pdi?-1.0:0.0));
   return Clamp(direction*strength,-1.0,1.0);
}


struct GOLD_SD_ZONE
{
   bool valid;
   int type;              // +1 demand, -1 supply
   double low;
   double high;
   double strength;
   int shift;
};

double GoldTrueRange(MqlRates &rates[],int i)
{
   double tr1=rates[i].high-rates[i].low;
   double tr2=MathAbs(rates[i].high-rates[i+1].close);
   double tr3=MathAbs(rates[i].low-rates[i+1].close);
   return MathMax(tr1,MathMax(tr2,tr3));
}

double GoldAverageATR(MqlRates &rates[],int period)
{
   int n=ArraySize(rates);
   if(period<2 || n<period+2) return 0.0;
   double sum=0.0;
   int used=MathMin(period,n-1);
   for(int i=1;i<=used;i++) sum+=GoldTrueRange(rates,i);
   return sum/(double)used;
}

bool DetectGoldSupplyDemand(MqlRates &rates[],int direction,GOLD_SD_ZONE &zone)
{
   zone.valid=false; zone.type=0; zone.low=0.0; zone.high=0.0;
   zone.strength=0.0; zone.shift=-1;

   if(!GoldSupplyDemandEnabled || direction==0) return false;
   int n=ArraySize(rates);
   if(n<GoldSDLookbackBars+GoldSDImpulseBars+5) return false;

   double atr=GoldAverageATR(rates,14);
   if(atr<=0.0) return false;

   int maxShift=MathMin(GoldSDLookbackBars,n-GoldSDImpulseBars-2);
   double best=-1.0;

   for(int s=GoldSDImpulseBars+1;s<=maxShift;s++)
   {
      double baseHigh=rates[s].high;
      double baseLow=rates[s].low;
      double impulseHigh=baseHigh;
      double impulseLow=baseLow;

      for(int j=1;j<=GoldSDImpulseBars;j++)
      {
         impulseHigh=MathMax(impulseHigh,rates[s-j].high);
         impulseLow=MathMin(impulseLow,rates[s-j].low);
      }

      double upMove=impulseHigh-baseHigh;
      double downMove=baseLow-impulseLow;

      int type=0;
      double impulse=0.0;
      if(upMove>=atr*GoldSDImpulseATR)
      {
         type=1; impulse=upMove;
      }
      else if(downMove>=atr*GoldSDImpulseATR)
      {
         type=-1; impulse=downMove;
      }

      if(type==0 || type!=direction) continue;

      double zoneLow=baseLow;
      double zoneHigh=baseHigh;
      double width=zoneHigh-zoneLow;
      if(width<=0.0) continue;

      // Keep the zone practical and volatility-normalized.
      if(width>atr*GoldSDZoneATR)
      {
         if(type>0) zoneHigh=zoneLow+atr*GoldSDZoneATR;
         else zoneLow=zoneHigh-atr*GoldSDZoneATR;
      }

      double strength=Clamp(impulse/(atr*3.0),0.0,1.0);
      double ageFactor=1.0-(double)(s-GoldSDImpulseBars-1)/
                       (double)MathMax(1,GoldSDLookbackBars);
      strength=Clamp(strength*0.75+ageFactor*0.25,0.0,1.0);

      double price=rates[0].close;
      bool near=(price>=zoneLow-atr*GoldSDNearZoneATR &&
                 price<=zoneHigh+atr*GoldSDNearZoneATR);
      if(!near) continue;

      if(strength>best)
      {
         best=strength;
         zone.valid=true;
         zone.type=type;
         zone.low=zoneLow;
         zone.high=zoneHigh;
         zone.strength=strength;
         zone.shift=s;
      }
   }
   return zone.valid && zone.strength>=GoldSDMinStrength;
}

bool GoldM5ReversalAllows(int direction,MqlRates &m5[],MqlRates &m15[],
                          MqlRates &htf[],bool m1Liquidity)
{
   if(!GoldM5ReversalEngine) return true;
   if(direction==0) return false;

   double atr=GoldAverageATR(m5,14);
   if(atr<=0.0) return false;

   double m5trend=TrendScore(m5,atr);
   double m15atr=GoldAverageATR(m15,14);
   double m15trend=(m15atr>0.0 ? TrendScore(m15,m15atr) : 0.0);
   double htfatr=GoldAverageATR(htf,14);
   double htftrend=(htfatr>0.0 ? TrendScore(htf,htfatr) : 0.0);

   double d=(double)direction;
   double alignedM5=Clamp(d*m5trend,0.0,1.0);
   double alignedM15=Clamp(d*m15trend,0.0,1.0);
   double alignedHTF=Clamp(d*htftrend,0.0,1.0);

   double score=alignedM5*GoldM5ReversalTrendWeight+
                alignedM15*GoldM15ConfirmWeight+
                alignedHTF*GoldHTFContextWeight+
                (m1Liquidity?1.0:0.0)*GoldM1LiquidityWeight;

   // M5 may lead the reversal. If M5 is very strong, M15/HTF do not veto it.
   bool strongM5=(alignedM5>=GoldM5ReversalMinScore);
   bool developing=(alignedM5>=GoldM5ReversalMinScore &&
                    alignedM15>=0.25);

   return (score>=GoldM5ReversalMinScore || strongM5 || developing);
}


bool GoldM5ReversalCandidate(MARKET_STATE &m,int &candidateDirection)
{
   candidateDirection=0;
   if(!GoldM5ReversalEngine) return false;

   double m5=m.tf[1].trend;
   double m15=m.tf[2].trend;
   double m30=m.tf[3].trend;
   double h1=m.tf[4].trend;
   double h4=m.tf[5].trend;

   double absM5=MathAbs(m5);
   if(absM5<GoldM5ReversalMinScore) return false;

   candidateDirection=(m5>0.0?1:-1);

   // M5 is the trigger. M15 validates persistence; M30/H1/H4 are context.
   bool m15Supports=(candidateDirection>0 ? m15>=-0.05 : m15<=0.05);
   bool m15Turning=(candidateDirection>0 ? m15>0.05 : m15<-0.05);

   // A strong M5 move can lead before higher TFs fully flip.
   bool persistent=(m15Supports || m15Turning);
   bool contextCompatible=(candidateDirection>0 ?
                            (h4>-0.75 && h1>-0.75 && m30>-0.65) :
                            (h4<0.75 && h1<0.75 && m30<0.65));

   return persistent && contextCompatible;
}

double TrendScore(
   MqlRates &rates[],
   double atr)
{
   if(atr<=0.0) return 0.0;

   double fast=EMAFromRates(rates,FastMAPeriod);
   double slow=EMAFromRates(rates,SlowMAPeriod);
   double slopeFast=fast-PreviousEMAFromRates(rates,FastMAPeriod);

   double maComponent=Clamp((fast-slow)/(atr*2.0),-1.0,1.0);
   double slopeComponent=Clamp(slopeFast/(atr*0.25),-1.0,1.0);

   // Original trend model remains the backbone.
   double core=maComponent*0.60+slopeComponent*0.20;

   // Stronger confirmations for the periods when SMC is absent.
   double ema50=EMAFromRates(rates,TrendConfirmEMA1);
   double ema200=EMAFromRates(rates,TrendConfirmEMA2);
   double stack=Clamp((ema50-ema200)/(atr*2.5),-1.0,1.0);

   double rsi=RSIFromRates(rates,TrendRSIPeriod);
   double rsiScore=Clamp((rsi-50.0)/25.0,-1.0,1.0);

   double macdFast=EMAFromRates(rates,TrendMACDFast);
   double macdSlow=EMAFromRates(rates,TrendMACDSlow);
   double macdScore=Clamp((macdFast-macdSlow)/(atr*2.0),-1.0,1.0);

   double adxScore=ADXDirectionalScore(rates,TrendADXPeriod);

   double totalWeight=0.80+TrendEMAStackWeight+TrendRSIWeight+
                      TrendMACDWeight+TrendADXWeight;

   return Clamp(
      (core+
       stack*TrendEMAStackWeight+
       rsiScore*TrendRSIWeight+
       macdScore*TrendMACDWeight+
       adxScore*TrendADXWeight)/totalWeight,
      -1.0,1.0);
}

double RangeScore(
   MqlRates &rates[],
   double atr)
{
   if(atr<=0.0 || ArraySize(rates)<20)
      return 0.0;

   double highest=rates[0].high;
   double lowest=rates[0].low;

   int n=MathMin(
      20,
      ArraySize(rates));

   for(int i=1;i<n;i++)
   {
      highest=MathMax(
         highest,
         rates[i].high);

      lowest=MathMin(
         lowest,
         rates[i].low);
   }

   double range=highest-lowest;

   if(range<=0.0)
      return 0.0;

   // Lower normalized range = more compressed/range-like.
   double normalized=
      range/(atr*20.0);

   return Clamp(
      1.0-normalized,
      0.0,
      1.0);
}

double ATRPoints(
   string symbol,
   MqlRates &rates[])
{
   double atr=
      CalcATRFromRates(
         symbol,
         rates,
         ATRPeriod);

   return atr/PointOf(symbol);
}

double AverageATRPoints(
   string symbol,
   ENUM_TIMEFRAMES tf,
   int period)
{
   MqlRates rates[];
   if(!GetRates(
         symbol,
         tf,
         period+20,
         rates))
      return 0.0;

   double sum=0.0;
   int count=0;

   for(int shift=0;
       shift<period &&
       shift+period+2<ArraySize(rates);
       shift++)
   {
      MqlRates local[];
      ArrayResize(
         local,
         ArraySize(rates)-shift);

      for(int j=shift;
          j<ArraySize(rates);
          j++)
      {
         local[j-shift]=rates[j];
      }

      double atr=
         CalcATRFromRates(
            symbol,
            local,
            ATRPeriod);

      if(atr>0.0)
      {
         sum+=atr/PointOf(symbol);
         count++;
      }

      if(shift>=4)
         break;
   }

   if(count==0)
      return 0.0;

   return sum/count;
}

bool AnalyzeTF(
   string symbol,
   ENUM_TIMEFRAMES tf,
   TF_STATE &state)
{
   state.tf=tf;
   state.valid=false;
   state.trend=0.0;
   state.momentum=0.0;
   state.volatility=1.0;
   state.rangeScore=0.0;
   state.atrPoints=0.0;

   MqlRates rates[];

   if(!GetRates(
         symbol,
         tf,
         BarsToRead,
         rates))
      return false;

   double atr=
      CalcATRFromRates(
         symbol,
         rates,
         ATRPeriod);

   if(atr<=0.0)
      return false;

   state.atrPoints=
      atr/PointOf(symbol);

   state.trend=
      TrendScore(
         rates,
         atr);

   state.momentum=
      MomentumScore(
         rates,
         atr);

   state.rangeScore=
      RangeScore(
         rates,
         atr);

   double avgATR=
      AverageATRPoints(
         symbol,
         tf,
         5);

   if(avgATR>0.0)
      state.volatility=
         state.atrPoints/avgATR;

   state.valid=true;

   return true;
}

//==================================================================
// MARKET ANALYSIS
//==================================================================

bool AnalyzeSymbol(
   string symbol,
   MARKET_STATE &m)
{
   m.symbol=symbol;
   m.dataReady=false;
   m.tradable=false;
   m.direction=0;
   m.regime=MARKET_UNKNOWN;
   m.sessionScore=0.0;
   m.sessionAffinity=0.0;
   m.sessionActive=false;
   m.sessionOverlap=false;

   string currentSessionName="";
   GetSessionState(
      symbol,
      m.sessionAffinity,
      m.sessionActive,
      m.sessionOverlap,
      currentSessionName);

   for(int i=0;i<6;i++)
   {
      ENUM_TIMEFRAMES tf=TF1;

      switch(i)
      {
         case 0: tf=TF1; break;
         case 1: tf=TF2; break;
         case 2: tf=TF3; break;
         case 3: tf=TF4; break;
         case 4: tf=TF5; break;
         case 5: tf=TF6; break;
      }

      if(!AnalyzeTF(
            symbol,
            tf,
            m.tf[i]))
         return false;
   }

   // GOLD hierarchy: M1 5%, M5 30% PRIMARY TREND, M15 20%, M30 15%, H1 15%, H4 15%.
    double weights[6] =
       {0.05,0.30,0.20,0.15,0.15,0.15};

   m.trend=0.0;
   m.momentum=0.0;
   m.volatility=0.0;
   m.rangeScore=0.0;

   int up=0;
   int down=0;
   int valid=0;

   for(int i=0;i<6;i++)
   {
      m.tf[i].tf=
         (i==0?TF1:
          i==1?TF2:
          i==2?TF3:
          i==3?TF4:
          i==4?TF5:TF6);

      m.trend+=
         m.tf[i].trend*
         weights[i];

      m.momentum+=
         m.tf[i].momentum*
         weights[i];

      m.volatility+=
         m.tf[i].volatility*
         weights[i];

      m.rangeScore+=
         m.tf[i].rangeScore*
         weights[i];

      if(m.tf[i].valid)
      {
         valid++;

         if(m.tf[i].trend>=StrongTrendScore)
            up++;

         if(m.tf[i].trend<=-StrongTrendScore)
            down++;
      }
   }

   if(valid<5)
      return false;

   int directional=
      MathMax(up,down);

   m.agreement=
      (double)directional/6.0;

   m.spreadPoints=
      CurrentSpreadPoints(symbol);

   if(m.spreadPoints>=999999.0)
      return false;

   // Direction
   if(m.trend>=StrongTrendScore)
      m.direction=1;
   else if(m.trend<=-StrongTrendScore)
      m.direction=-1;
   else
      m.direction=0;

   // Regime
   if(m.volatility>=HighVolatilityRatio)
      m.regime=MARKET_HIGH_VOL;
   else if(m.direction>0 &&
           m.agreement>=MinAgreementForTrendTrade)
      m.regime=MARKET_STRONG_UP;
   else if(m.direction<0 &&
           m.agreement>=MinAgreementForTrendTrade)
      m.regime=MARKET_STRONG_DOWN;
   else if(MathAbs(m.trend)<=WeakTrendScore &&
           m.rangeScore>=0.40)
      m.regime=MARKET_SIDEWAYS;
   else
      m.regime=MARKET_TRANSITION;

   // Average ATR / minute from the shortest useful timeframe.
   double atrM5=
      m.tf[1].atrPoints;

   if(atrM5<=0.0)
      atrM5=m.tf[0].atrPoints;

   // Conservative velocity estimate.
   // This is a ranking metric, not a price forecast.
   m.expectedPointsPerMinute=
      MathMax(
         atrM5/5.0*
         (1.0+
          MathAbs(m.trend)),
         0.01);

   // Breakout distance is tied to current ATR and trend strength.
   m.breakoutDistancePoints=
      MathMax(
         m.tf[1].atrPoints*
         (0.35+
          MathAbs(m.trend)*0.45),
         1.0);

   m.expectedMinutes=
      m.breakoutDistancePoints/
      m.expectedPointsPerMinute;

   double spreadPenalty=
      1.0;

   if(m.spreadPoints>0.0)
   {
      double spreadRatio=
         m.spreadPoints/
         MathMax(
            m.tf[1].atrPoints,
            1.0);

      spreadPenalty=
         Clamp(
            1.0-
            spreadRatio,
            0.0,
            1.0);
   }

   double trendComponent=
      MathAbs(m.trend);

   double momentumComponent=
      MathAbs(m.momentum);

   double agreementComponent=
      m.agreement;

   double volatilityComponent=
      1.0;

   if(AvoidExtremeVolatility)
   {
      if(m.volatility>=HighVolatilityRatio)
         volatilityComponent=0.25;
      else if(m.volatility<=LowVolatilityRatio)
         volatilityComponent=0.45;
      else
         volatilityComponent=
            Clamp(
               1.0-
               MathAbs(
                  m.volatility-1.0)/
               0.80,
               0.0,
               1.0);
   }

   double breakoutComponent=
      Clamp(
         MathAbs(m.trend)*0.65+
         MathAbs(m.momentum)*0.35,
         0.0,
         1.0);

   double rewardTimeComponent=
      Clamp(
         (m.breakoutDistancePoints/
          MathMax(m.expectedMinutes,0.1))/
         MathMax(m.tf[1].atrPoints/5.0,0.01),
         0.0,
         1.0);

   // Sideways is intentionally penalized when the scanner is looking
   // for trend campaigns, but it remains visible on the dashboard.
   double regimeBonus=0.0;

   if(m.regime==MARKET_STRONG_UP ||
      m.regime==MARKET_STRONG_DOWN)
      regimeBonus=10.0;

   if(m.regime==MARKET_SIDEWAYS &&
      PreferTrendMarkets)
      regimeBonus=-12.0;

   if(m.regime==MARKET_HIGH_VOL)
      regimeBonus=-15.0;

   // Session engine:
   // reward markets during their naturally active session and the
   // major overlaps, but do not make session alone sufficient for a
   // trade. Trend/structure remains dominant.
   if(EnableSessionEngine)
   {
      m.sessionScore=
         m.sessionAffinity*
         ActiveSessionBonus;

      if(m.sessionOverlap &&
         m.sessionAffinity>=0.75)
      {
         m.sessionScore+=
            SessionOverlapBonus;
      }

      if(!m.sessionActive &&
         PenalizeDeadSessions)
      {
         m.sessionScore-=
            DeadSessionPenalty;
      }
   }

   m.sessionScore=
      Clamp(
         m.sessionScore,
         -20.0,
         ActiveSessionBonus+
         SessionOverlapBonus);

   m.trendScore=
      trendComponent*25.0+
      momentumComponent*15.0+
      agreementComponent*25.0+
      volatilityComponent*10.0+
      spreadPenalty*10.0+
      breakoutComponent*10.0+
      rewardTimeComponent*5.0+
      regimeBonus+
      m.sessionScore;

   // Hard spread filter only if explicitly enabled.
   if(MaxSpreadPoints>0 &&
      m.spreadPoints>MaxSpreadPoints)
      m.tradable=false;
   else
      m.tradable=true;

   if(PreferBreakoutMarkets)
      m.opportunityScore=
         m.trendScore;
   else
      m.opportunityScore=
         m.trendScore+
         m.rangeScore*5.0;

   m.opportunityScore=
      Clamp(
         m.opportunityScore,
         0.0,
         100.0);

   m.dataReady=true;

   return true;
}

//==================================================================
// UNIVERSE
//==================================================================

string UpperSymbol(string symbol)
{
   StringToUpper(symbol);
   return symbol;
}

bool ContainsAnyAlias(
   string symbol,
   string &aliases[],
   int aliasCount,
   int &score)
{
   string u=UpperSymbol(symbol);
   score=0;

   for(int i=0;i<aliasCount;i++)
   {
      string a=UpperSymbol(aliases[i]);

      if(a=="")
         continue;

      int pos=StringFind(u,a);

      if(pos>=0)
      {
         int localScore=70;

         // Exact symbol is strongest.
         if(u==a)
            localScore=100;

         // Common broker prefix/suffix is still a very strong match.
         if(StringLen(u)==StringLen(a)+1 ||
            StringLen(u)==StringLen(a)+2 ||
            StringLen(u)==StringLen(a)+3)
            localScore=MathMax(localScore,90);

         if(localScore>score)
            score=localScore;
      }
   }

   return score>0;
}

int FindBestBrokerSymbol(
   string &aliases[],
   int aliasCount,
   string &bestSymbol)
{
   bestSymbol="";
   int bestScore=0;

   int total=SymbolsTotal(false);

   for(int i=0;i<total;i++)
   {
      string candidate=
         SymbolName(i,false);

      if(candidate=="")
         continue;

      int score=0;

      if(!ContainsAnyAlias(
            candidate,
            aliases,
            aliasCount,
            score))
         continue;

      if(!IsSymbolUsable(candidate))
         continue;

      // Prefer shorter names when scores are tied. This usually
      // selects the cleanest broker symbol instead of a duplicate
      // CFD/alternate contract.
      if(score>bestScore ||
         (score==bestScore &&
          (bestSymbol=="" ||
           StringLen(candidate)<
           StringLen(bestSymbol))))
      {
         bestScore=score;
         bestSymbol=candidate;
      }
   }

   return bestScore;
}

void AddDetectedSymbol(
   string canonical,
   string &aliases[],
   int aliasCount)
{
   string found="";
   int score=
      FindBestBrokerSymbol(
         aliases,
         aliasCount,
         found);

   if(found=="")
   {
      Print(
         "NeoFL GOLD 5.3 DUAL ENGINE | AUTO MAP | ",
         canonical,
         " -> NOT FOUND"
      );
      return;
   }

   int n=ArraySize(Symbols);

   // Avoid duplicates if two canonical names resolve to the same
   // broker symbol.
   for(int i=0;i<n;i++)
   {
      if(Symbols[i]==found)
         return;
   }

   ArrayResize(
      Symbols,
      n+1);

   Symbols[n]=found;

   if(PrintSymbolMapping)
   {
      Print(
         "NeoFL GOLD 5.3 DUAL ENGINE | AUTO MAP | ",
         canonical,
         " -> ",
         found,
         " | match=",
         score
      );
   }
}

void BuildAutoDetectedUniverse()
{
   ArrayResize(Symbols,0);

   // GOLD standalone: resolve ONLY Gold/XAU broker symbols.
   string XAU[]={"XAUUSD","XAU","GOLD","GOLDUSD","XAUUSDm","XAUUSD.a"};
   AddDetectedSymbol("XAUUSD",XAU,ArraySize(XAU));

   MarketCount=ArraySize(Symbols);
   ArrayResize(Markets,MarketCount);

   GoldSymbol="";
   for(int i=0;i<MarketCount;i++)
   {
      string u=UpperSymbol(Symbols[i]);
      if(StringFind(u,"XAU")>=0 || StringFind(u,"GOLD")>=0)
      {
         GoldSymbol=Symbols[i];
         break;
      }
   }

   Print("NeoFL GOLD 5.3 DUAL ENGINE | DEDICATED ACTIVE SCAN | GOLD symbols=",MarketCount);
   if(GoldSymbol!="")
      Print("NeoFL GOLD 5.3 DUAL ENGINE | ACTIVE SYMBOL=",GoldSymbol);
   else
      Print("NeoFL GOLD 5.3 DUAL ENGINE | GOLD/XAU SYMBOL NOT FOUND");
}

void BuildUniverse()
{
   if(AutoDetectBrokerSymbols)
   {
      BuildAutoDetectedUniverse();
      return;
   }

   ArrayResize(Symbols,0);
   string parts[];
   int n=StringSplit(MarketUniverse,';',parts);

   for(int i=0;i<n;i++)
   {
      string requested=parts[i];
      StringTrimLeft(requested);
      StringTrimRight(requested);
      if(requested=="") continue;

      string u=UpperSymbol(requested);
      if(StringFind(u,"XAU")<0 && StringFind(u,"GOLD")<0)
      {
         Print("NeoFL GOLD 5.3 DUAL ENGINE | MANUAL SYMBOL REJECTED (NOT GOLD): ",requested);
         continue;
      }

      if(IsSymbolUsable(requested))
      {
         int size=ArraySize(Symbols);
         ArrayResize(Symbols,size+1);
         Symbols[size]=requested;
      }
   }

   MarketCount=ArraySize(Symbols);
   ArrayResize(Markets,MarketCount);
   GoldSymbol=(MarketCount>0 ? Symbols[0] : "");
   Print("NeoFL GOLD 5.3 DUAL ENGINE | MANUAL GOLD UNIVERSE=",MarketCount);
}

//==================================================================
// SCANNER
//==================================================================

void ScanMarkets()
{
   BestIndex=-1;

   double bestScore=-1.0;

   for(int i=0;i<MarketCount;i++)
   {
      MARKET_STATE m;

      if(!AnalyzeSymbol(
            Symbols[i],
            m))
      {
         Markets[i]=m;
         continue;
      }

      Markets[i]=m;

      if(m.tradable &&
         m.opportunityScore>=
         GoldMinOpportunityScore &&
         m.opportunityScore>
         bestScore)
      {
         bestScore=
            m.opportunityScore;

         BestIndex=i;
      }
   }

   LastScan=TimeCurrent();

   PrintTopMarkets();
}

// Sort dashboard indexes without changing Markets.
void SortIndexes(
   int &indexes[])
{
   int n=ArraySize(indexes);

   for(int i=0;i<n-1;i++)
   {
      for(int j=i+1;j<n;j++)
      {
         if(Markets[indexes[j]].opportunityScore>
            Markets[indexes[i]].opportunityScore)
         {
            int t=indexes[i];
            indexes[i]=indexes[j];
            indexes[j]=t;
         }
      }
   }
}

void PrintTopMarkets()
{
   int indexes[];
   ArrayResize(
      indexes,
      MarketCount);

   int count=0;

   for(int i=0;i<MarketCount;i++)
   {
      if(Markets[i].dataReady)
      {
         indexes[count]=i;
         count++;
      }
   }

   ArrayResize(
      indexes,
      count);

   SortIndexes(indexes);

   Print(
      "================ NeoFL GOLD 5.3 DUAL ENGINE ACTIVE OPPORTUNITY SCAN ================"
   );

   int show=
      MathMin(
         count,
         DashboardTopN);

   for(int rank=0;
       rank<show;
       rank++)
   {
      int i=indexes[rank];

      MARKET_STATE m=
         Markets[i];

      Print(
         "#",
         rank+1,
         " ",
         m.symbol,
         " | Score=",
         DoubleToString(
            m.opportunityScore,
            1),
         " | ",
         RegimeName(
            m.regime),
         " | Trend=",
         DoubleToString(
            m.trend,
            2),
         " | Mom=",
         DoubleToString(
            m.momentum,
            2),
         " | Agree=",
         DoubleToString(
            m.agreement,
            2),
         " | SessAff=",
         DoubleToString(
            m.sessionAffinity,
            2),
         " | SessScore=",
         DoubleToString(
            m.sessionScore,
            1),
         " | Spread=",
         DoubleToString(
            m.spreadPoints,
            1)
      );
   }

   if(BestIndex>=0)
   {
      Print(
         "NeoFL GOLD 5.3 DUAL ENGINE | BEST OPPORTUNITY = ",
         Markets[BestIndex].symbol,
         " | SCORE=",
         DoubleToString(
            Markets[BestIndex].opportunityScore,
            1),
         " | ACTION=",
         (Markets[BestIndex].direction>0
          ?"BUY THESIS":
          Markets[BestIndex].direction<0
          ?"SELL THESIS":
          "WAIT")
      );
   }
   else
   {
      Print(
         "NeoFL GOLD 5.3 DUAL ENGINE | NO QUALIFIED OPPORTUNITY"
      );
   }

   Print(
      "========================================================="
   );
}

//==================================================================
// DASHBOARD
//==================================================================

void DisplayDashboard()
{
   if(!ShowDashboard)
      return;

   string currentSession="";
   bool sydney;
   bool tokyo;
   bool london;
   bool newyork;
   bool overlap;

   MARKET_SESSION globalSession=
      CurrentGlobalSession(
         sydney,
         tokyo,
         london,
         newyork,
         overlap);

   currentSession=
      SessionName(globalSession);

   string text=
      "NeoFL GOLD 5.3 DUAL ENGINE - STANDALONE ACTIVE SCANNER\n";
   text+=
      "GLOBAL SESSION: "+
      currentSession+
      "\n";
   text+=
      "UTC: "+
      TimeToString(
         TimeGMT(),
         TIME_DATE|TIME_SECONDS)+
      "\n";
   text+=
      "Scan: "+
      TimeToString(
         LastScan,
         TIME_SECONDS)+
      "\n";
   text+=
      "Dedicated universe: "+
      IntegerToString(
         MarketCount)+
      "\n\n";

   int indexes[];
   ArrayResize(
      indexes,
      MarketCount);

   int count=0;

   for(int i=0;i<MarketCount;i++)
   {
      if(Markets[i].dataReady)
      {
         indexes[count]=i;
         count++;
      }
   }

   ArrayResize(
      indexes,
      count);

   SortIndexes(indexes);

   int show=
      MathMin(
         count,
         DashboardTopN);

   for(int rank=0;
       rank<show;
       rank++)
   {
      MARKET_STATE m=
         Markets[indexes[rank]];

      text+=
         IntegerToString(rank+1)+
         ". "+
         m.symbol+
         "  "+
         DoubleToString(
            m.opportunityScore,
            1)+
         "  "+
         RegimeName(
            m.regime)+
         "  T:"+ 
         DoubleToString(
            m.trend,
            2)+
         " A:"+
         DoubleToString(
            m.agreement,
            2)+
         " S:"+
         DoubleToString(
            m.sessionAffinity,
            2)+
         "\n";
   }

   text+=
      "\n";

   if(BestIndex>=0)
   {
      MARKET_STATE best=
         Markets[BestIndex];

      text+=
         "BEST: "+
         best.symbol+
         "\n";

      text+=
         "DIRECTION: "+
         (best.direction>0
          ?"BUY":
          best.direction<0
          ?"SELL":
          "WAIT")+
         "\n";

      text+=
         "SESSION AFFINITY: "+
         DoubleToString(
            best.sessionAffinity,
            2)+
         "\n";

      text+=
         "SESSION SCORE: "+
         DoubleToString(
            best.sessionScore,
            1)+
         "\n";

      text+=
         "SCORE: "+
         DoubleToString(
            best.opportunityScore,
            1)+
         "\n";

      text+=
         "TREND: "+
         DoubleToString(
            best.trend,
            2)+
         "\n";

      text+=
         "AGREEMENT: "+
         DoubleToString(
            best.agreement,
            2)+
         "\n";

      text+=
         "MOMENTUM: "+
         DoubleToString(
            best.momentum,
            2)+
         "\n";

      text+=
         "SPREAD: "+
         DoubleToString(
            best.spreadPoints,
            1)+
         " pts\n";

      text+=
         "EXPECTED VELOCITY: "+
         DoubleToString(
            best.expectedPointsPerMinute,
            1)+
         " pts/min\n";

      text+=
         "EST. TIME: "+
         DoubleToString(
            best.expectedMinutes,
            1)+
         " min";
   }
   else
   {
      text+=
         "NO QUALIFIED OPPORTUNITY";
   }

   Comment(text);
}

//==================================================================
// EXECUTION ENGINE
//==================================================================

bool HasOurPosition(string symbol="")
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!IsNeoFLMagic((ulong)PositionGetInteger(POSITION_MAGIC))) continue;
      string ps=PositionGetString(POSITION_SYMBOL);
      if(symbol=="" || ps==symbol) return true;
   }
   return false;
}

bool GetOurPosition(string &symbol, int &direction, ulong &ticket)
{
   symbol=""; direction=0; ticket=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(!IsNeoFLMagic((ulong)PositionGetInteger(POSITION_MAGIC))) continue;
      symbol=PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      direction=(pt==POSITION_TYPE_BUY)?1:-1;
      ticket=t;
      return true;
   }
   return false;
}

int CountOurPendingOrders()
{
   int c=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(!IsNeoFLMagic((ulong)OrderGetInteger(ORDER_MAGIC))) continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_SELL_STOP) c++;
   }
   return c;
}

void CancelOurPending(string symbol="")
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(!IsNeoFLMagic((ulong)OrderGetInteger(ORDER_MAGIC))) continue;
      string os=OrderGetString(ORDER_SYMBOL);
      if(symbol!="" && os!=symbol) continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_SELL_STOP)
      {
         if(!DryRun) trade.OrderDelete(ticket);
         if(PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | CANCEL PENDING | ",os," ticket=",ticket);
      }
   }
   if(symbol=="" || PendingSymbol==symbol)
   {
      PendingSymbol=""; PendingDirection=0; PendingEntry=0; PendingCreated=0;
      PendingInvalidCount=0;
   }
}

void ResetCampaignIfFlat()
{
   string ps; int dir; ulong ticket;
   if(GetOurPosition(ps,dir,ticket)) return;
   if(ActiveTradeSymbol!="" && LastPositionClose==0)
      LastPositionClose=TimeCurrent();
   ActiveTradeSymbol=""; ActiveTradeDirection=0; ActiveCampaignTP=0; ActiveInitialEntry=0; ActiveOppositeLevel=0;
}

int VolumeDigits(string symbol)
{
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) return 2;
   int digits=0;
   double scaled=step;
   while(digits<8 && MathAbs(scaled-MathRound(scaled))>1e-9)
   {
      scaled*=10.0;
      digits++;
   }
   return digits;
}

double NormalizeLots(string symbol,double lots)
{
   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=minLot;
   maxLot=MathMin(maxLot,MaxLots);
   lots=MathMax(minLot,MathMin(maxLot,lots));
   lots=MathFloor(lots/step+1e-9)*step;
   return NormalizeDouble(lots,VolumeDigits(symbol));
}

double EffectiveCapitalPercent();

double CalculateLots(string symbol,double slPoints)
{
   if(!UseRiskBasedLots) return NormalizeLots(symbol,FixedLots);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney=equity*RiskPercent/100.0*EffectiveCapitalPercent()/100.0;
   double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double point=PointOf(symbol);
   if(tickValue<=0 || tickSize<=0 || slPoints<=0) return NormalizeLots(symbol,FixedLots);
   double valuePerPointPerLot=tickValue*(point/tickSize);
   if(valuePerPointPerLot<=0) return NormalizeLots(symbol,FixedLots);
   return NormalizeLots(symbol,riskMoney/(slPoints*valuePerPointPerLot));
}

double MinStopDistance(string symbol)
{
   long stops=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   return (double)stops*PointOf(symbol);
}

double CurrentATRPoints(string symbol)
{
   MqlRates r[];
   if(!GetRates(symbol,TF2,MathMax(ATRPeriod+5,30),r)) return 0;
   double atr=CalcATRFromRates(symbol,r,ATRPeriod);
   return atr/PointOf(symbol);
}


bool IsNeoFLMagic(ulong magic)
{
   return magic==BotMagicNumber;
}

bool IsGoldMagic(ulong magic)
{
   return magic==BotMagicNumber;
}

ulong MagicForSymbol(string symbol)
{
   return BotMagicNumber;
}

//==================================================================
// DEDICATED ACCOUNT CAPITAL MANAGER
//==================================================================

bool IsSharedCapitalMode()
{
   return false;
}

double EffectiveCapitalPercent()
{
   return 100.0;
}

string CapitalModeName()
{
   return "DEDICATED_ACCOUNT";
}

void PrintCapitalMode()
{
   if(!PrintRiskManagerLog)
      return;

   Print("NeoFL 4.3 | CAPITAL MODE=DEDICATED_ACCOUNT",
         " | account=",IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)),
         " | strategy allocation=100.0%");
}

double EstimatePositionMargin(string symbol,
                              ENUM_POSITION_TYPE positionType,
                              double volume,
                              double price)
{
   ENUM_ORDER_TYPE orderType =
      (positionType==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   return EstimateOrderMargin(symbol,orderType,volume,price);
}

bool AccountCapitalAllowed(string symbol,
                           ENUM_ORDER_TYPE type,
                           double lots,
                           double entry)
{
   if(!EnableCapitalManager)
      return true;

   double required=EstimateOrderMargin(symbol,type,lots,entry);
   double accountFree=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double accountEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   double usable=accountEquity*Clamp(MaxAccountCapitalUsePercent,0.0,100.0)/100.0;

   bool ok=(required>0.0 &&
           required<=accountFree &&
           required<=usable);

   if(PrintRiskManagerLog)
      Print("NeoFL GOLD 5.3 DUAL ENGINE CAPITAL | DEDICATED ACCOUNT",
            " equity=",DoubleToString(accountEquity,2),
            " usable=",DoubleToString(usable,2),
            " required=",DoubleToString(required,2),
            " free=",DoubleToString(accountFree,2),
            " allowed=",(ok ? "YES" : "NO"));
   return ok;
}

bool AccountCapitalAllowsCombined(string symbol1,
                                  ENUM_ORDER_TYPE type1,
                                  double lots1,
                                  double entry1,
                                  string symbol2,
                                  ENUM_ORDER_TYPE type2,
                                  double lots2,
                                  double entry2)
{
   if(!EnableCapitalManager)
      return true;

   double required1=EstimateOrderMargin(symbol1,type1,lots1,entry1);
   double required2=EstimateOrderMargin(symbol2,type2,lots2,entry2);
   double required=required1+required2;
   double accountFree=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double accountEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   double usable=accountEquity*Clamp(MaxAccountCapitalUsePercent,0.0,100.0)/100.0;

   bool ok=(required1>0.0 && required2>0.0 &&
            required<=accountFree && required<=usable);

   if(PrintRiskManagerLog)
      Print("NeoFL GOLD 5.3 DUAL ENGINE CAPITAL | DEDICATED COMBINED",
            " equity=",DoubleToString(accountEquity,2),
            " usable=",DoubleToString(usable,2),
            " required=",DoubleToString(required,2),
            " free=",DoubleToString(accountFree,2),
            " allowed=",(ok ? "YES" : "NO"));
   return ok;
}

bool HasPendingForSymbol(string symbol)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      ulong om=(ulong)OrderGetInteger(ORDER_MAGIC);
      if(!IsNeoFLMagic(om)) continue;
      if(om!=MagicForSymbol(symbol)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=symbol) continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_SELL_STOP)
         return true;
   }
   return false;
}

bool GetGoldMarket(MARKET_STATE &m)
{
   if(GoldSymbol=="") return false;
   for(int i=0;i<MarketCount;i++)
   {
      if(Markets[i].symbol==GoldSymbol && Markets[i].dataReady)
      {
         m=Markets[i];
         return true;
      }
   }
   return false;
}

double EstimateOrderMargin(string symbol, ENUM_ORDER_TYPE type, double volume, double price)
{
   if(symbol=="" || volume<=0 || price<=0) return 0.0;
   double margin=0.0;
   if(!OrderCalcMargin(type,symbol,volume,price,margin))
      return 0.0;
   return margin;
}

int CountOurPositions(string symbol="")
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!IsNeoFLMagic((ulong)PositionGetInteger(POSITION_MAGIC))) continue;
      string ps=PositionGetString(POSITION_SYMBOL);
      if(symbol!="" && ps!=symbol) continue;
      count++;
   }
   return count;
}

bool HasDuplicateGoldExposure()
{
   if(GoldSymbol=="") return false;
   return CountOurPositions(GoldSymbol)>=MathMax(1,MaxBotPositions);
}

void ClearGoldPendingState()
{
   GoldPendingSymbol="";
   GoldPendingDirection=0;
   GoldPendingEntry=0.0;
   GoldPendingCreated=0;
   GoldPendingInvalidCount=0;
}

void ClearStandalonePendingState(string symbol="")
{
   if(symbol=="" || PendingSymbol==symbol)
   {
      PendingSymbol="";
      PendingDirection=0;
      PendingEntry=0.0;
      PendingCreated=0;
      PendingInvalidCount=0;
      PendingRegime=MARKET_UNKNOWN;
   }
}

// Delete every remaining NeoFL pending order for a symbol after a fill.
// This is the OCO mechanism for sideways/range straddles and stale duplicate orders.
void CancelPendingAfterFill(string symbol)
{

   if(symbol==GoldSymbol && GoldNewsActive && GoldNewsStraddleArmed)
   {
      if(PrintExecutionLog)
         Print("NeoFL GOLD 5.3 DUAL ENGINE | NEWS RIDER | opposite stop retained");
      return;
   }
   if(!UseImmediateOCOOnFill || symbol=="") return;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(!IsNeoFLMagic((ulong)OrderGetInteger(ORDER_MAGIC))) continue;
      if(OrderGetString(ORDER_SYMBOL)!=symbol) continue;

      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_SELL_STOP ||
         ot==ORDER_TYPE_BUY_LIMIT || ot==ORDER_TYPE_SELL_LIMIT)
      {
         if(!DryRun)
         {
            if(!trade.OrderDelete(ticket) && PrintExecutionLog)
               Print("NeoFL GOLD 5.3 DUAL ENGINE | OCO DELETE FAILED | ",symbol,
                     " ticket=",ticket," retcode=",trade.ResultRetcode(),
                     " ",trade.ResultRetcodeDescription());
         }
         else if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | DRY OCO DELETE | ",symbol," ticket=",ticket);
      }
   }

   if(symbol==GoldSymbol)
      ClearGoldPendingState();
   else
      ClearStandalonePendingState(symbol);
}


bool GetGoldClosedM1Rates(MqlRates &rates[])
{
   if(GoldSymbol=="") return false;
   ArrayResize(rates,GoldSweepLookbackBars+2);
   int copied=CopyRates(GoldSymbol,PERIOD_M1,1,GoldSweepLookbackBars+2,rates);
   return (copied>=GoldSweepLookbackBars+1);
}

bool DetectGoldLiquiditySweep(int &sweepDirection, datetime &eventBar,
                              double &sweepLevel, double &atrPrice)
{
   sweepDirection=0; eventBar=0; sweepLevel=0.0; atrPrice=0.0;
   if(!EnableGoldLiquiditySweepDefense || GoldSymbol=="") return false;

   MqlRates r[];
   if(!GetGoldClosedM1Rates(r)) return false;
   int n=ArraySize(r);
   if(n<GoldSweepLookbackBars+1) return false;

   MARKET_STATE g;
   if(!GetGoldMarket(g) || g.tf[0].atrPoints<=0) return false;

   double point=PointOf(GoldSymbol);
   if(point<=0) return false;
   atrPrice=g.tf[0].atrPoints*point;

   int last=n-1;
   double priorHigh=-DBL_MAX, priorLow=DBL_MAX;
   int first=MathMax(0,last-GoldSweepLookbackBars);
   for(int i=first;i<last;i++)
   {
      priorHigh=MathMax(priorHigh,r[i].high);
      priorLow=MathMin(priorLow,r[i].low);
   }

   double range=r[last].high-r[last].low;
   if(range<=0) return false;

   double spread=SymbolInfoDouble(GoldSymbol,SYMBOL_ASK)-
                 SymbolInfoDouble(GoldSymbol,SYMBOL_BID);
   if(spread>atrPrice*GoldSweepMaxSpreadATR) return false;

   double buffer=atrPrice*GoldSweepLevelBufferATR;
   bool bearish =
      r[last].high>priorHigh+buffer &&
      r[last].close<priorHigh &&
      range>=atrPrice*GoldSweepMinRangeATR &&
      (r[last].high-MathMax(r[last].open,r[last].close))
         >=atrPrice*GoldSweepMinWickATR;

   bool bullish =
      r[last].low<priorLow-buffer &&
      r[last].close>priorLow &&
      range>=atrPrice*GoldSweepMinRangeATR &&
      (MathMin(r[last].open,r[last].close)-r[last].low)
         >=atrPrice*GoldSweepMinWickATR;

   if(bearish==bullish) return false;

   sweepDirection=bearish ? -1 : 1;
   sweepLevel=bearish ? priorHigh : priorLow;
   eventBar=r[last].time;
   return true;
}

bool GoldShockConfirmationComplete()
{
   if(!GoldShockActive) return true;
   if(GoldShockEventBar<=0) return false;

   MqlRates r[];
   ArrayResize(r,GoldPostSweepConfirmationBars+2);
   int copied=CopyRates(GoldSymbol,PERIOD_M1,1,GoldPostSweepConfirmationBars+2,r);
   if(copied<GoldPostSweepConfirmationBars+1) return false;

   int after=0;
   for(int i=0;i<copied;i++)
      if(r[i].time>GoldShockEventBar) after++;

   return after>=GoldPostSweepConfirmationBars;
}

void ProtectGoldPositionOnLiquidityShock(int shockDirection,double atrPrice)
{
   if(!GoldProtectPositionOnShock || !HasOurPosition(GoldSymbol)) return;
   if(!PositionSelect(GoldSymbol)) return;

   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double oldSL=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double point=PointOf(GoldSymbol);
   if(point<=0 || atrPrice<=0) return;

   double bid=SymbolInfoDouble(GoldSymbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(GoldSymbol,SYMBOL_ASK);
   double minDist=MinStopDistance(GoldSymbol)+2*point;

   if(pt==POSITION_TYPE_BUY && shockDirection<0 && bid>0)
   {
      double newSL=NormalizePrice(GoldSymbol,
         bid-MathMax(atrPrice*GoldEmergencyTrailATR,minDist));
      if(oldSL<=0 || newSL>oldSL)
      {
         if(!DryRun) trade.PositionModify(GoldSymbol,newSL,tp);
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | SHOCK PROTECT BUY | SL ",
                  DoubleToString(oldSL,DigitsOf(GoldSymbol))," -> ",
                  DoubleToString(newSL,DigitsOf(GoldSymbol)));
      }
   }

   if(pt==POSITION_TYPE_SELL && shockDirection>0 && ask>0)
   {
      double newSL=NormalizePrice(GoldSymbol,
         ask+MathMax(atrPrice*GoldEmergencyTrailATR,minDist));
      if(oldSL<=0 || newSL<oldSL)
      {
         if(!DryRun) trade.PositionModify(GoldSymbol,newSL,tp);
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | SHOCK PROTECT SELL | SL ",
                  DoubleToString(oldSL,DigitsOf(GoldSymbol))," -> ",
                  DoubleToString(newSL,DigitsOf(GoldSymbol)));
      }
   }
}


bool IsMajorGoldNewsName(string name)
{
   string u=name;
   StringToUpper(u);
   string keys[]={"NONFARM","NON-FARM","PAYROLL","NFP","CONSUMER PRICE","CPI",
                  "INFLATION","CORE PCE","PCE PRICE","FOMC","FEDERAL FUNDS",
                  "FED INTEREST","INTEREST RATE","FED CHAIR","POWELL",
                  "RATE DECISION","RETAIL SALES","GDP","GROSS DOMESTIC",
                  "PRODUCER PRICE","PPI","ISM","UNEMPLOYMENT","JOBLESS CLAIMS"};
   for(int i=0;i<ArraySize(keys);i++)
      if(StringFind(u,keys[i])>=0) return true;
   return false;
}

bool FindNextMajorGoldNews(datetime now,datetime &eventTime,ulong &eventId,string &eventName)
{
   eventTime=0; eventId=0; eventName="";
   if(!EnableGoldNewsEngine || !GoldNewsUseEconomicCalendar) return false;
   MqlCalendarValue values[];
   datetime from=now-60;
   datetime to=now+(GoldNewsPreparationMinutes+GoldNewsCampaignMinutes+10)*60;
   int n=CalendarValueHistory(values,from,to,"USD");
   if(n<=0) return false;
   for(int i=0;i<n;i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id,ev)) continue;
      if(ev.importance!=CALENDAR_IMPORTANCE_HIGH) continue;
      if(GoldNewsOnlyMajorUSD && !IsMajorGoldNewsName(ev.name)) continue;
      datetime t=values[i].time;
      if(t<now-30) continue;
      if(eventTime==0 || t<eventTime)
      {
         eventTime=t; eventId=values[i].event_id; eventName=ev.name;
      }
   }
   return eventTime>0;
}

bool BuildGoldNewsLevels(double &upper,double &lower,double &atrPrice)
{
   upper=0; lower=0; atrPrice=0;
   if(GoldSymbol=="") return false;
   MqlRates r[];
   ArraySetAsSeries(r,true);
   int copied=CopyRates(GoldSymbol,PERIOD_M1,1,12,r);
   if(copied<6) return false;

   double sum=0; int count=0;
   for(int i=0;i<copied;i++)
   {
      if(r[i].high>r[i].low){ sum+=r[i].high-r[i].low; count++; }
   }
   if(count<=0) return false;
   atrPrice=sum/count;

   upper=r[0].high; lower=r[0].low;
   for(int i=1;i<MathMin(copied,6);i++)
   {
      upper=MathMax(upper,r[i].high);
      lower=MathMin(lower,r[i].low);
   }

   double point=PointOf(GoldSymbol);
   double buffer=MathMax(atrPrice*GoldNewsEntryBufferATR,
                         MinStopDistance(GoldSymbol)+2*point);
   upper=NormalizePrice(GoldSymbol,upper+buffer);
   lower=NormalizePrice(GoldSymbol,lower-buffer);
   return upper>lower;
}

bool GoldNewsSpreadOK(double atrPrice)
{
   if(atrPrice<=0) return false;
   double ask=SymbolInfoDouble(GoldSymbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(GoldSymbol,SYMBOL_BID);
   if(ask<=0 || bid<=0) return false;
   return GoldNewsMaxSpreadATR<=0 || (ask-bid)<=atrPrice*GoldNewsMaxSpreadATR;
}

bool PlaceGoldNewsStraddle()
{
   if(!EnableTrading || GoldSymbol=="" || HasOurPosition(GoldSymbol) ||
      HasPendingForSymbol(GoldSymbol)) return false;

   double upper,lower,atrPrice;
   if(!BuildGoldNewsLevels(upper,lower,atrPrice) || !GoldNewsSpreadOK(atrPrice))
      return false;

   double point=PointOf(GoldSymbol);
   double minDist=MinStopDistance(GoldSymbol)+2*point;
   double initialSL=MathMax(atrPrice*GoldNewsInitialSL_ATR,minDist);
   double buffer=MathMax(atrPrice*GoldNewsTrailBufferATR,minDist);
   double buySL=NormalizePrice(GoldSymbol,lower-buffer);
   double sellSL=NormalizePrice(GoldSymbol,upper+buffer);
   double lots=CalculateLots(GoldSymbol,initialSL/point);
   if(lots<=0) return false;

   if(!AccountCapitalAllowsCombined(GoldSymbol,ORDER_TYPE_BUY_STOP,lots,upper,
                                    GoldSymbol,ORDER_TYPE_SELL_STOP,lots,lower))
      return false;

   trade.SetExpertMagicNumber(BotMagicNumber);
   bool a=true,b=true;
   if(!DryRun)
   {
      a=trade.BuyStop(lots,upper,GoldSymbol,buySL,0,ORDER_TIME_GTC,0,"NeoFL GOLD NEWS BUY");
      if(a) b=trade.SellStop(lots,lower,GoldSymbol,sellSL,0,ORDER_TIME_GTC,0,"NeoFL GOLD NEWS SELL");
      else b=false;
   }
   if(a && b)
   {
      GoldNewsUpperLevel=upper; GoldNewsLowerLevel=lower; GoldNewsTrailSL=0;
      GoldNewsStraddleArmed=true; GoldNewsActive=true;
      if(PrintExecutionLog)
         Print("NeoFL GOLD 5.3 DUAL ENGINE | NEWS STRADDLE ARMED | ",GoldNewsEventName,
               " | BUY=",DoubleToString(upper,DigitsOf(GoldSymbol)),
               " | SELL=",DoubleToString(lower,DigitsOf(GoldSymbol)));
      return true;
   }
   if(!DryRun) CancelOurPending(GoldSymbol);
   return false;
}

bool ModifyGoldNewsPending(ulong ticket,double newPrice,double newSL)
{
   if(ticket==0 || !OrderSelect(ticket)) return false;
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action=TRADE_ACTION_MODIFY;
   req.order=ticket;
   req.symbol=OrderGetString(ORDER_SYMBOL);
   req.price=NormalizePrice(req.symbol,newPrice);
   req.sl=(newSL>0 ? NormalizePrice(req.symbol,newSL) : 0.0);
   req.tp=OrderGetDouble(ORDER_TP);
   req.type_time=(ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
   req.expiration=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
   if(DryRun) return true;
   return OrderSend(req,res);
}

void CloseGoldOppositePositions(int keepDirection)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsNeoFLMagic((ulong)PositionGetInteger(POSITION_MAGIC))) continue;
      if(PositionGetString(POSITION_SYMBOL)!=GoldSymbol) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int d=(pt==POSITION_TYPE_BUY ? 1 : -1);
      if(d!=keepDirection && !DryRun) trade.PositionClose(ticket);
   }
}

void TrailGoldNewsRider()
{
   if(!GoldNewsActive || !GoldNewsStraddleArmed || GoldSymbol=="") return;
   if(!PositionSelect(GoldSymbol)) return;

   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   int dir=(pt==POSITION_TYPE_BUY ? 1 : -1);

   if(!GoldNewsPositionActive)
   {
      GoldNewsPositionActive=true;
      GoldNewsPositionDirection=dir;
   }
   else if(dir!=GoldNewsPositionDirection)
   {
      GoldNewsReversals++;
      GoldNewsPositionDirection=dir;
      CloseGoldOppositePositions(dir);
      if(PrintExecutionLog)
         Print("NeoFL GOLD 5.3 DUAL ENGINE | NEWS RIDER REVERSAL | direction=",dir,
               " reversals=",GoldNewsReversals);
   }

   if(GoldNewsReversals>=GoldNewsMaxReversals)
   {
      CancelOurPending(GoldSymbol);
      GoldNewsCampaignUntil=TimeCurrent();
      return;
   }

   MARKET_STATE m;
   if(!GetGoldMarket(m)) return;
   double atr=m.tf[1].atrPoints*PointOf(GoldSymbol);
   if(atr<=0) return;

   double bid=SymbolInfoDouble(GoldSymbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(GoldSymbol,SYMBOL_ASK);
   double point=PointOf(GoldSymbol);
   double minDist=MinStopDistance(GoldSymbol)+2*point;
   double trail=MathMax(atr*GoldNewsTrailBufferATR,minDist);

   double oldSL=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double newSL=(dir>0 ? NormalizePrice(GoldSymbol,bid-trail)
                        : NormalizePrice(GoldSymbol,ask+trail));

   bool moved=false;
   if(dir>0 && (oldSL<=0 || newSL>oldSL))
   {
      if(!DryRun) trade.PositionModify(GoldSymbol,newSL,tp);
      moved=true;
   }
   if(dir<0 && (oldSL<=0 || newSL<oldSL))
   {
      if(!DryRun) trade.PositionModify(GoldSymbol,newSL,tp);
      moved=true;
   }
   if(!moved && oldSL>0) newSL=oldSL;
   GoldNewsTrailSL=newSL;

   // Opposite stop rides just beyond the current protective SL.
   double activation=MathMax(point,atr*GoldNewsTrailBufferATR);
   double oppositePrice=NormalizePrice(GoldSymbol,
                        dir>0 ? newSL-activation : newSL+activation);

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || !IsNeoFLMagic((ulong)OrderGetInteger(ORDER_MAGIC))) continue;
      if(OrderGetString(ORDER_SYMBOL)!=GoldSymbol) continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool opposite=(dir>0 ? ot==ORDER_TYPE_SELL_STOP : ot==ORDER_TYPE_BUY_STOP);
      if(!opposite) continue;

      double reversalSL=(dir>0
                         ? oppositePrice+MathMax(activation,atr*GoldNewsInitialSL_ATR)
                         : oppositePrice-MathMax(activation,atr*GoldNewsInitialSL_ATR));
      ModifyGoldNewsPending(ticket,oppositePrice,reversalSL);
      if(PrintExecutionLog && moved)
         Print("NeoFL GOLD 5.3 DUAL ENGINE | NEWS RIDER TRAIL | posSL=",
               DoubleToString(newSL,DigitsOf(GoldSymbol)),
               " oppositeStop=",DoubleToString(oppositePrice,DigitsOf(GoldSymbol)));
   }
}

bool GoldNewsTradingLock()
{
   return false;
}

void UpdateGoldNewsEngine()
{
   if(!EnableGoldNewsEngine || GoldSymbol=="") return;
   datetime now=TimeCurrent();

   if(now-GoldNewsLastCalendarScan>=15)
   {
      GoldNewsLastCalendarScan=now;
      datetime et; ulong eid; string en;
      if(FindNextMajorGoldNews(now,et,eid,en))
      {
         GoldNewsEventTime=et; GoldNewsEventId=eid; GoldNewsEventName=en;
      }
   }
   if(GoldNewsEventTime<=0) return;

   int secondsTo=(int)(GoldNewsEventTime-now);

   if(secondsTo>GoldNewsStraddleSecondsBefore &&
      secondsTo<=GoldNewsPreparationMinutes*60)
   {
      CancelOurPending(GoldSymbol);
      return;
   }

   if(!GoldNewsStraddleArmed &&
      secondsTo<=GoldNewsStraddleSecondsBefore && secondsTo>=-5)
   {
      CancelOurPending(GoldSymbol);
      if(PlaceGoldNewsStraddle())
         GoldNewsCampaignUntil=GoldNewsEventTime+GoldNewsCampaignMinutes*60;
      return;
   }

   if(GoldNewsStraddleArmed)
   {
      if(now<=GoldNewsCampaignUntil)
      {
         if(PositionSelect(GoldSymbol))
            TrailGoldNewsRider();
         return;
      }

      CancelOurPending(GoldSymbol);
      if(!PositionSelect(GoldSymbol))
      {
         GoldNewsStraddleArmed=false;
         GoldNewsActive=false;
         GoldNewsRecoveryUntil=now+GoldNewsRecoveryMinutes*60;
         GoldNewsEventTime=0; GoldNewsEventId=0; GoldNewsEventName="";
         GoldNewsPositionActive=false; GoldNewsPositionDirection=0; GoldNewsReversals=0;
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | NEWS CAMPAIGN COMPLETE | recovery lock started");
      }
   }
}

void UpdateGoldLiquidityDefense()
{
   if(!EnableGoldLiquiditySweepDefense || GoldSymbol=="") return;

   if(GoldShockStopouts>=MathMax(2,GoldMaxShockStopouts) &&
      GoldShockStopoutWindowStart>0 &&
      TimeCurrent()-GoldShockStopoutWindowStart<=GoldWhipsawWindowSeconds)
   {
      GoldShockActive=true;
      if(GoldShockUntil < GoldShockStopoutWindowStart+GoldWhipsawWindowSeconds)
         GoldShockUntil=GoldShockStopoutWindowStart+GoldWhipsawWindowSeconds;
   }

   if(GoldShockActive)
   {
      if(TimeCurrent()>=GoldShockUntil && GoldShockConfirmationComplete())
      {
         GoldShockActive=false;
         GoldShockDirection=0;
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | SHOCK LOCK CLEARED | scanning resumed");
      }
      return;
   }

   int dir=0; datetime bar=0; double level=0.0; double atrPrice=0.0;
   if(!DetectGoldLiquiditySweep(dir,bar,level,atrPrice)) return;
   if(bar==GoldShockEventBar) return;

   GoldShockActive=true;
   GoldShockUntil=TimeCurrent()+MathMax(60,GoldShockLockSeconds);
   GoldShockEventBar=bar;
   GoldShockDirection=dir;

   if(GoldCancelPendingOnShock) CancelOurPending(GoldSymbol);
   ClearGoldPendingState();
   ProtectGoldPositionOnLiquidityShock(dir,atrPrice);

   if(PrintExecutionLog)
      Print("NeoFL GOLD 5.3 DUAL ENGINE | LIQUIDITY SWEEP | ",
            dir>0?"BULLISH RECLAIM":"BEARISH RECLAIM",
            " | level=",DoubleToString(level,DigitsOf(GoldSymbol)),
            " | NEW ENTRY LOCKED");
}

bool GoldTradingLockedByShock()
{
   if(!EnableGoldLiquiditySweepDefense) return false;
   if(GoldShockActive) return true;
   if(GoldBlockOppositeAfterStop && GoldShockLastStopout>0 &&
      TimeCurrent()-GoldShockLastStopout<MathMax(60,GoldShockLockSeconds))
      return true;
   return false;
}

bool PlaceGoldTrendPending(MARKET_STATE &m)
{
   if(GoldSymbol=="" || m.symbol!=GoldSymbol) return false;
   if(GoldTradingLockedByShock()) return false;
   if(HasOurPosition(GoldSymbol) || HasPendingForSymbol(GoldSymbol)) return false;
   int tradeDirection=(GoldArkExecutionMode ?
                        GoldArkExecutionDirection : m.direction);
   if(!GoldArkExecutionMode && tradeDirection==0 && GoldEarlyTrendCandidate(m))
      tradeDirection=(m.tf[1].trend>0.0 ? 1 : -1);
   bool m5Reversal=false;
   int reversalDirection=0;

   if(!GoldArkExecutionMode && GoldM5ReversalCandidate(m,reversalDirection))
   {
      // M5 can lead a reversal. Do not let the weighted aggregate veto it.
      tradeDirection=reversalDirection;
      m5Reversal=(tradeDirection!=m.direction || MathAbs(m.trend)<GoldMinTrendScore);
   }

   if(!GoldArkExecutionMode)
   {
      if(!m5Reversal)
      {
         if(m.opportunityScore<GoldMinOpportunityScore) return false;
         if(MathAbs(m.trend)<GoldMinTrendScore || m.agreement<GoldMinAgreement) return false;
      }
      else
      {
         // Reversal candidates still need a meaningful M5 move.
         if(MathAbs(m.tf[1].trend)<GoldM5ReversalMinScore) return false;
      }
   }
   else
   {
      // Ark-style entry has already passed its independent zone/SMC/liquidity
      // gate. M5 remains a scoring input, not a hard veto.
      if(MathAbs(m.tf[1].trend)<0.15) return false;
   }

   double smcScore=0.0;
   bool smcConfirmed=GoldSMCSupportsDirection(tradeDirection,smcScore);

   // Supply/Demand is a trade-location confluence layer.
   GOLD_SD_ZONE sdZone;
   sdZone.valid=false;
   sdZone.type=0;
   sdZone.low=0.0;
   sdZone.high=0.0;
   sdZone.strength=0.0;
   sdZone.shift=-1;
   bool sdConfirmed=false;
   if(GoldSupplyDemandEnabled)
   {
      MqlRates sdRates[];
      ArraySetAsSeries(sdRates,true);
      int sdCopied=CopyRates(_Symbol,PERIOD_M5,0,GoldSDLookbackBars+GoldSDImpulseBars+20,sdRates);
      if(sdCopied>GoldSDImpulseBars+20)
         sdConfirmed=DetectGoldSupplyDemand(sdRates,tradeDirection,sdZone);
   }

   // Supply/Demand can upgrade a borderline M5 reversal, but never acts alone.
   if(!m5Reversal && GoldSupplyDemandEnabled)
   {
      if(sdConfirmed && sdZone.strength>=GoldSDMinStrength &&
         MathAbs(m.tf[1].trend)>=GoldM5ReversalMinScore)
         m5Reversal=true;
   }

   // Re-check M1 liquidity at execution decision so the larger SMC tier
   // cannot be granted from SMC alone.
   bool m1LiquidityConfirmed=true;
   if(GoldSMCRequireM1ForEventTier)
   {
      GOLD_M1_LIQUIDITY_STATE m1ls;
      m1ls.valid=false;
      m1ls.bullishSweep=false;
      m1ls.bearishSweep=false;
      m1ls.bullishReclaim=false;
      m1ls.bearishReclaim=false;
      m1ls.displacement=false;
      m1ls.score=0.0;
      m1ls.rangeATR=0.0;
      m1ls.sweptLow=0.0;
      m1ls.sweptHigh=0.0;
      m1ls.barTime=0;
      m1LiquidityConfirmed=DetectGoldM1Liquidity(m1ls);
      if(m1LiquidityConfirmed)
      {
         if(tradeDirection>0) m1LiquidityConfirmed=m1ls.bullishReclaim;
         else if(tradeDirection<0) m1LiquidityConfirmed=m1ls.bearishReclaim;
         else m1LiquidityConfirmed=false;
      }
   }

   if(GoldSMCRequiredForTrade && !smcConfirmed)
   {
      if(PrintExecutionLog)
         Print("NeoFL GOLD 5.3 DUAL ENGINE | SMC REQUIRED BLOCK | dir=",tradeDirection,
               " score=",DoubleToString(smcScore,2));
      return false;
   }

   double point=PointOf(GoldSymbol);
   double atrPts=m.tf[1].atrPoints;
   if(atrPts<=0.0) return false;

   double ask=SymbolInfoDouble(GoldSymbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(GoldSymbol,SYMBOL_BID);
   if(ask<=0.0 || bid<=0.0) return false;

   double minDist=MinStopDistance(GoldSymbol)+2.0*point;
   double entryDist=MathMax(atrPts*EntryATRMultiplier*point,minDist);
   double slDist=MathMax(atrPts*InitialSL_ATR*point,minDist);

   // Give high-quality SMC setups a larger, but bounded, reward target.
   double rewardATR=FixedTP_ATR;
   double rewardScore=(GoldArkExecutionMode ?
                       MathMax(smcScore,GoldArkExecutionScore) :
                       smcScore);
   if(GoldArkExecutionMode && GoldArkExecutionScore>=GoldArkExceptionalScore)
      rewardATR+=GoldArkRewardATRBoost;
   if(smcScore>=GoldSMCExceptionalMinScore)
      rewardATR+=GoldSMCExceptionalRewardATRBoost;
   else if(smcScore>=GoldSMCEventMinScore)
      rewardATR+=GoldSMCEventRewardATRBoost;
   else if(GoldSMCEnabled)
      rewardATR+=smcScore*0.35;
   rewardATR=MathMin(3.75,rewardATR);
   double tpDist=MathMax(atrPts*rewardATR*point,minDist);

   double entry=(tradeDirection>0)?ask+entryDist:bid-entryDist;
   double sl=(tradeDirection>0)?entry-slDist:entry+slDist;
   double tp=(tradeDirection>0)?entry+tpDist:entry-tpDist;

   entry=NormalizePrice(GoldSymbol,entry);
   sl=NormalizePrice(GoldSymbol,sl);
   tp=NormalizePrice(GoldSymbol,tp);

   double expectedR=(slDist>0.0 ? tpDist/slDist : 0.0);
   double waitMinutes=0.0;
   if(GoldLastTradeTime>0)
      waitMinutes=MathMax(0.0,(double)(TimeCurrent()-GoldLastTradeTime)/60.0);

   double effectiveSMCScore=smcScore;
   if(GoldArkExecutionMode)
      effectiveSMCScore=MathMax(effectiveSMCScore,
                                MathMin(1.0,GoldArkExecutionScore));

   double lots=CalculateGoldRewardAwareLots(slDist/point,effectiveSMCScore,
                                             MathMax(MathAbs(m.trend),
                                                     MathAbs(m.tf[1].trend)),
                                             expectedR,waitMinutes,
                                             m1LiquidityConfirmed);
   if(lots<=0.0) return false;

   if(!AccountCapitalAllowed(GoldSymbol,
                             (tradeDirection>0?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP),
                             lots,entry))
   {
      if(PrintRiskManagerLog)
         Print("NeoFL GOLD 5.3 DUAL ENGINE CAPITAL | GOLD ORDER BLOCKED | bucket limit");
      return false;
   }

   bool ok=false;
   if(PrintExecutionLog)
      Print("NeoFL GOLD 5.3 DUAL ENGINE | SMC TREND | dir=",tradeDirection,
            " trend=",DoubleToString(m.trend,2),
            " SMC=",DoubleToString(smcScore,2),
            " ARK=",GoldArkExecutionMode,
            " ARKscore=",DoubleToString(GoldArkExecutionScore,2),
            " R=",DoubleToString(expectedR,2),
            " waitMin=",DoubleToString(waitMinutes,1),
            " M1Liquidity=",m1LiquidityConfirmed,
            " SD=",sdConfirmed,
            " SDstrength=",DoubleToString(sdZone.strength,2),
            " riskPct=",DoubleToString(
               GoldRewardAwareRiskPercent(smcScore,MathAbs(m.trend),
                                           expectedR,waitMinutes,
                                           m1LiquidityConfirmed),2),
            " lots=",DoubleToString(lots,2));

   if(!DryRun)
   {
      trade.SetExpertMagicNumber(BotMagicNumber);
      if(tradeDirection>0)
         ok=trade.BuyStop(lots,entry,GoldSymbol,sl,tp,ORDER_TIME_GTC,0,
                          "NeoFL4.7 GOLD SMC BUY");
      else
         ok=trade.SellStop(lots,entry,GoldSymbol,sl,tp,ORDER_TIME_GTC,0,
                           "NeoFL4.7 GOLD SMC SELL");

      if(!ok && PrintExecutionLog)
         Print("NeoFL GOLD 5.3 DUAL ENGINE | ORDER FAILED | retcode=",
               trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   }
   else ok=true;

   if(ok)
   {
      GoldPendingSymbol=GoldSymbol;
      GoldPendingDirection=tradeDirection;
      GoldPendingEntry=entry;
      GoldPendingCreated=TimeCurrent();
      GoldPendingInvalidCount=0;
      GoldLastTradeTime=TimeCurrent();
      return true;
   }

   return false;
}

bool PlaceGoldSidewaysStraddle(MARKET_STATE &m)
{
   if(GoldSymbol=="" || m.symbol!=GoldSymbol) return false;
   if(GoldTradingLockedByShock()) return false;
   if(HasOurPosition(GoldSymbol) || HasPendingForSymbol(GoldSymbol)) return false;
   double point=PointOf(GoldSymbol);
   double atrPts=m.tf[1].atrPoints;
   if(atrPts<=0) return false;
   double ask=SymbolInfoDouble(GoldSymbol,SYMBOL_ASK), bid=SymbolInfoDouble(GoldSymbol,SYMBOL_BID);
   if(ask<=0 || bid<=0) return false;
   double minDist=MinStopDistance(GoldSymbol)+2*point;
   double dist=MathMax(atrPts*SidewaysStopATR*point,minDist);
   double slDist=MathMax(atrPts*SidewaysSL_ATR*point,minDist);
   double tpDist=MathMax(atrPts*SidewaysTP_ATR*point,minDist);
   double buy=NormalizePrice(GoldSymbol,ask+dist), sell=NormalizePrice(GoldSymbol,bid-dist);
   double buySL=NormalizePrice(GoldSymbol,buy-slDist), buyTP=NormalizePrice(GoldSymbol,buy+tpDist);
   double sellSL=NormalizePrice(GoldSymbol,sell+slDist), sellTP=NormalizePrice(GoldSymbol,sell-tpDist);
   double lots=CalculateLots(GoldSymbol,slDist/point);    if(!AccountCapitalAllowsCombined(GoldSymbol,ORDER_TYPE_BUY_STOP,lots,buy,GoldSymbol,ORDER_TYPE_SELL_STOP,lots,sell))
    {
       if(PrintRiskManagerLog)
          Print("NeoFL GOLD 5.3 DUAL ENGINE CAPITAL | GOLD RANGE BLOCKED | bucket limit");
       return false;
    }

    bool ok1=true,ok2=true;
   if(PrintExecutionLog)
      Print("NeoFL GOLD 5.3 DUAL ENGINE | GOLD SIDEWAYS STRADDLE | ",GoldSymbol," buy=",DoubleToString(buy,DigitsOf(GoldSymbol))," sell=",DoubleToString(sell,DigitsOf(GoldSymbol)));
   if(!DryRun)
   {
             trade.SetExpertMagicNumber(BotMagicNumber);
ok1=trade.BuyStop(lots,buy,GoldSymbol,buySL,buyTP,ORDER_TIME_GTC,0,"NeoFL4.2 GOLD RANGE BUY");
      if(!ok1 && PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | GOLD BUY STOP FAILED | ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      ok2=trade.SellStop(lots,sell,GoldSymbol,sellSL,sellTP,ORDER_TIME_GTC,0,"NeoFL4.2 GOLD RANGE SELL");
      if(!ok2 && PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | GOLD SELL STOP FAILED | ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   }
   if(ok1||ok2)
   {
      GoldPendingSymbol=GoldSymbol;
      GoldPendingDirection=0;
      GoldPendingEntry=0;
      GoldPendingCreated=TimeCurrent();
      GoldPendingInvalidCount=0;
      return true;
   }
   return false;
}


struct GOLD_ARK_SIGNAL
{
   bool valid;
   int direction;
   double score;
   double zoneStrength;
   double smcScore;
   double liquidityScore;
   double m5Score;
   double zoneLow;
   double zoneHigh;
   datetime zoneTime;
   bool freshZone;
   bool liquidityConfirmed;
   bool structureConfirmed;
};

bool DetectGoldArkFreshZone(int direction,GOLD_ARK_SIGNAL &a)
{
   a.freshZone=false;
   a.zoneStrength=0.0;
   a.zoneLow=0.0;
   a.zoneHigh=0.0;
   a.zoneTime=0;

   if(!GoldArkStyleEngineEnabled || GoldSymbol=="" || direction==0)
      return false;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   int need=MathMax(GoldArkLookbackBars+GoldArkBaseBars+20,80);
   int copied=CopyRates(GoldSymbol,PERIOD_M5,1,need,r);
   if(copied<30) return false;

   double atr=GoldAverageATR(r,14);
   if(atr<=0.0) return false;

   double price=SymbolInfoDouble(GoldSymbol,SYMBOL_BID);
   if(price<=0.0) price=r[0].close;

   double best=-1.0;
   int maxShift=MathMin(GoldArkLookbackBars,copied-GoldArkBaseBars-2);

   for(int s=GoldArkBaseBars+2;s<=maxShift;s++)
   {
      double baseHigh=r[s].high;
      double baseLow=r[s].low;
      for(int b=1;b<GoldArkBaseBars;b++)
      {
         baseHigh=MathMax(baseHigh,r[s+b].high);
         baseLow=MathMin(baseLow,r[s+b].low);
      }

      double impulseHigh=baseHigh;
      double impulseLow=baseLow;
      for(int j=1;j<=GoldArkBaseBars;j++)
      {
         impulseHigh=MathMax(impulseHigh,r[s-j].high);
         impulseLow=MathMin(impulseLow,r[s-j].low);
      }

      double up=impulseHigh-baseHigh;
      double down=baseLow-impulseLow;
      int type=0;
      double impulse=0.0;

      if(direction>0 && up>=atr*GoldArkImpulseATR)
      {
         type=1;
         impulse=up;
      }
      if(direction<0 && down>=atr*GoldArkImpulseATR)
      {
         type=-1;
         impulse=down;
      }
      if(type!=direction) continue;

      double zl=baseLow;
      double zh=baseHigh;
      double width=zh-zl;
      if(width<=0.0) continue;

      if(width>atr*GoldArkZoneATR)
      {
         if(direction>0) zh=zl+atr*GoldArkZoneATR;
         else zl=zh-atr*GoldArkZoneATR;
      }

      // Freshness / mitigation test: after the impulse, price must not have
      // materially revisited the zone. This is the Ark-style "untested zone"
      // rule and is intentionally stricter than the ordinary SD confluence.
      bool mitigated=false;
      // Do not count the displacement candles themselves as a mitigation.
      // Only price action AFTER the impulse can invalidate freshness.
      int postImpulseStart=s-GoldArkBaseBars-1;
      for(int q=postImpulseStart;q>=1;q--)
      {
         if(direction>0 && r[q].low<=zh+atr*GoldArkFreshnessATR)
         {
            mitigated=true;
            break;
         }
         if(direction<0 && r[q].high>=zl-atr*GoldArkFreshnessATR)
         {
            mitigated=true;
            break;
         }
      }

      if(GoldArkRequireFreshZone && mitigated) continue;

      bool near=(price>=zl-atr*GoldArkNearZoneATR &&
                 price<=zh+atr*GoldArkNearZoneATR);
      if(!near) continue;

      double impulseScore=Clamp(impulse/(atr*3.0),0.0,1.0);
      double ageScore=1.0-(double)(s-1)/(double)MathMax(1,GoldArkLookbackBars);
      double strength=Clamp(0.70*impulseScore+0.30*ageScore,0.0,1.0);

      if(strength>best)
      {
         best=strength;
         a.freshZone=true;
         a.zoneStrength=strength;
         a.zoneLow=zl;
         a.zoneHigh=zh;
         a.zoneTime=r[s].time;
      }
   }

   return a.freshZone;
}

bool EvaluateGoldArkStyle(GOLD_ARK_SIGNAL &a,MARKET_STATE &m)
{
   a.valid=false;
   a.direction=0;
   a.score=0.0;
   a.zoneStrength=0.0;
   a.smcScore=0.0;
   a.liquidityScore=0.0;
   a.m5Score=0.0;
   a.zoneLow=0.0;
   a.zoneHigh=0.0;
   a.zoneTime=0;
   a.freshZone=false;
   a.liquidityConfirmed=false;
   a.structureConfirmed=false;

   if(!GoldArkStyleEngineEnabled || GoldSymbol=="" || !m.dataReady)
      return false;

   if(GoldTradingLockedByShock() || GoldNewsTradingLock())
      return false;

   // The Ark-style engine evaluates BOTH directions independently. It does
   // not inherit the global aggregate direction as a hard veto.
   int candidates[2]={1,-1};

   double best=-1.0;
   GOLD_ARK_SIGNAL bestSignal=a;

   for(int k=0;k<2;k++)
   {
      int dir=candidates[k];
      GOLD_ARK_SIGNAL c=a;
      c.direction=dir;

      if(!DetectGoldArkFreshZone(dir,c))
         continue;

      double smc=0.0;
      bool smcOk=GoldSMCSupportsDirection(dir,smc);
      c.smcScore=smc;

      GOLD_M1_LIQUIDITY_STATE ls;
      bool liq=DetectGoldM1Liquidity(ls);
      c.liquidityConfirmed=false;
      c.liquidityScore=0.0;

      if(liq)
      {
         if(dir>0 && ls.bullishReclaim)
         {
            c.liquidityConfirmed=true;
            c.liquidityScore=MathAbs(ls.score);
         }
         else if(dir<0 && ls.bearishReclaim)
         {
            c.liquidityConfirmed=true;
            c.liquidityScore=MathAbs(ls.score);
         }
         else if((dir>0 && ls.bullishSweep) ||
                 (dir<0 && ls.bearishSweep))
         {
            c.liquidityScore=0.25;
         }
      }

      c.structureConfirmed=smcOk;
      c.m5Score=Clamp(dir*m.tf[1].trend,0.0,1.0);

      if(GoldArkRequireLiquidityConfirmation && !c.liquidityConfirmed)
         continue;
      if(GoldArkRequireStructureConfirmation && !c.structureConfirmed)
         continue;

      c.score=
         c.zoneStrength*GoldArkZoneWeight+
         c.smcScore*GoldArkSMCWeight+
         c.liquidityScore*GoldArkLiquidityWeight+
         c.m5Score*GoldArkM5Weight;

      // A strong M5 move aligned with the zone gets a small quality boost.
      if(c.m5Score>=GoldM5ReversalMinScore)
         c.score=MathMin(1.0,c.score+0.05);

      if(c.score>best)
      {
         best=c.score;
         bestSignal=c;
         bestSignal.valid=true;
      }
   }

   if(!bestSignal.valid || best<GoldArkMinScore)
      return false;

   a=bestSignal;
   return true;
}

bool PlaceGoldArkPending(MARKET_STATE &m,GOLD_ARK_SIGNAL &a)
{
   if(!a.valid || a.direction==0) return false;
   if(HasOurPosition(GoldSymbol) || HasPendingForSymbol(GoldSymbol)) return false;

   GoldArkExecutionMode=true;
   GoldArkExecutionDirection=a.direction;
   GoldArkExecutionScore=a.score;

   bool ok=PlaceGoldTrendPending(m);

   GoldArkExecutionMode=false;
   GoldArkExecutionDirection=0;
   GoldArkExecutionScore=0.0;

   return ok;
}

bool GoldEarlyTrendCandidate(MARKET_STATE &m)
{
   // M5 leads the normal trend engine. M15 confirms persistence while
   // M30/H1/H4 provide context and may lag without vetoing a real M5 move.
   double m5=m.tf[1].trend;
   double m15=m.tf[2].trend;
   double m30=m.tf[3].trend;
   double h1=m.tf[4].trend;
   double h4=m.tf[5].trend;

   if(MathAbs(m5)<0.28) return false;

   int d=(m5>0.0 ? 1 : -1);

   double weighted =
      d*(m5*GoldM5TrendWeight+
         m15*GoldM15TrendWeight+
         m30*GoldM30TrendWeight+
         h1*GoldH1TrendWeight+
         h4*GoldH4TrendWeight);

   if(d>0 && m15<-0.35) return false;
   if(d<0 && m15>0.35) return false;
   if(d>0 && h1<-0.55) return false;
   if(d<0 && h1>0.55) return false;
   if(weighted<0.22) return false;

   if(RequireM5MomentumAlignment)
   {
      if(d>0 && m.tf[1].momentum<-0.10) return false;
      if(d<0 && m.tf[1].momentum>0.10) return false;
   }

   return true;
}

void ManageGoldAnchor()
{
   if(!GoldAlwaysOn || GoldSymbol=="") return;
   if(GoldTradingLockedByShock()) return;
   if(GoldNewsTradingLock()) return;

   MARKET_STATE g;
   if(!GetGoldMarket(g)) return;
   if(HasOurPosition(GoldSymbol)) return;

   if(GoldM1LiquidityEnabled && PrintExecutionLog)
   {
      GOLD_M1_LIQUIDITY_STATE ls;
      if(DetectGoldM1Liquidity(ls) &&
         (ls.bullishSweep || ls.bearishSweep || ls.displacement))
         Print("NeoFL GOLD 5.3 DUAL ENGINE | M1 LIQUIDITY | sweepUp=",ls.bearishSweep,
               " sweepDown=",ls.bullishSweep,
               " reclaimUp=",ls.bearishReclaim,
               " reclaimDown=",ls.bullishReclaim,
               " rangeATR=",DoubleToString(ls.rangeATR,2));
   }

   if(HasPendingForSymbol(GoldSymbol))
   {
      if(TimeCurrent()-GoldPendingCreated>GoldPendingExpiryMinutes*60)
      {
         CancelOurPending(GoldSymbol);
         GoldPendingSymbol="";
      }
      return;
   }

   if(TimeCurrent()-GoldLastAnalysis<GoldReanalysisSeconds) return;
   GoldLastAnalysis=TimeCurrent();

   // ================================================================
   // TWO ENGINES RUN ON EVERY ANALYSIS CYCLE:
   // A) NeoFL trend/indicator engine
   // B) Ark-style SMC + fresh Supply/Demand + liquidity engine
   // They share execution/risk/trailing infrastructure but maintain
   // independent signal logic.
   // ================================================================

   GOLD_ARK_SIGNAL ark;
   bool arkReady=EvaluateGoldArkStyle(ark,g);

   bool normalReady=false;
   int normalDirection=0;
   double normalScore=0.0;

   if(GoldTrendOnlyMode &&
      GoldAllowTrendTrading)
   {
      bool confirmedTrend=M5TrendGatePasses(g);
      bool earlyTrend=GoldEarlyTrendCandidate(g);

      // M5 may establish direction before the aggregate regime reaches
      // MARKET_STRONG_*. The full M5/M15/M30/H1/H4 model remains in scoring.
      normalDirection=g.direction;
      if(normalDirection==0 && earlyTrend)
         normalDirection=(g.tf[1].trend>0.0 ? 1 : -1);

      normalReady=(normalDirection!=0 && (confirmedTrend || earlyTrend));

      double smcPreview=0.0;
      bool smcPreviewOK=GoldSMCSupportsDirection(normalDirection,smcPreview);
      bool m1OK=GoldM1LiquiditySupportsDirection(normalDirection);

      normalScore=
         Clamp(g.opportunityScore/100.0,0.0,1.0)*0.40+
         Clamp(MathAbs(g.tf[1].trend),0.0,1.0)*0.35+
         Clamp(g.agreement,0.0,1.0)*0.15+
         (smcPreviewOK ? 0.10 : 0.0);

      if(!m1OK || (GoldSMCRequiredForTrade && !smcPreviewOK))
         normalReady=false;

      if(PrintExecutionLog)
         Print("NeoFL GOLD 5.3 DUAL ENGINE | NORMAL ENGINE | ready=",normalReady,
               " dir=",normalDirection,
               " score=",DoubleToString(normalScore,2),
               " M5=",DoubleToString(g.tf[1].trend,2),
               " M15=",DoubleToString(g.tf[2].trend,2),
               " M30=",DoubleToString(g.tf[3].trend,2),
               " H1=",DoubleToString(g.tf[4].trend,2),
               " H4=",DoubleToString(g.tf[5].trend,2));
   }

   if(PrintExecutionLog)
      Print("NeoFL GOLD 5.3 DUAL ENGINE | ARK ENGINE | ready=",arkReady,
            " dir=",ark.direction,
            " score=",DoubleToString(ark.score,2),
            " zone=",DoubleToString(ark.zoneStrength,2),
            " SMC=",DoubleToString(ark.smcScore,2),
            " liquidity=",DoubleToString(ark.liquidityScore,2),
            " M5=",DoubleToString(ark.m5Score,2),
            " fresh=",ark.freshZone);

   // Choose the strongest qualified engine. The engines are evaluated
   // simultaneously; only one position is allowed by account policy.
   if(arkReady && (!normalReady || ark.score>=normalScore))
   {
      if(PlaceGoldArkPending(g,ark))
      {
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | ENGINE WINNER = ARK | score=",
                  DoubleToString(ark.score,2),
                  " dir=",ark.direction);
      }
      return;
   }

   if(normalReady)
   {
      if(PlaceGoldTrendPending(g))
      {
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | ENGINE WINNER = NORMAL TREND | score=",
                  DoubleToString(normalScore,2),
                  " dir=",normalDirection);
      }
      return;
   }

   if(PrintExecutionLog)
      Print("NeoFL GOLD 5.3 DUAL ENGINE | BOTH ENGINES WAIT | M5=",
            DoubleToString(g.tf[1].trend,2),
            " M15=",DoubleToString(g.tf[2].trend,2),
            " M30=",DoubleToString(g.tf[3].trend,2),
            " H1=",DoubleToString(g.tf[4].trend,2),
            " H4=",DoubleToString(g.tf[5].trend,2),
            " ARKscore=",DoubleToString(ark.score,2),
            " NORMALscore=",DoubleToString(normalScore,2));
}

bool GoldM1TrailingAllowed()
{
   return GoldM1TrailingOnly;
}


struct GOLD_M1_LIQUIDITY_STATE
{
   bool     valid;
   bool     bullishSweep;
   bool     bearishSweep;
   bool     bullishReclaim;
   bool     bearishReclaim;
   bool     displacement;
   double   sweptHigh;
   double   sweptLow;
   double   rangeATR;
   double   score;
   datetime barTime;
};

bool DetectGoldM1Liquidity(GOLD_M1_LIQUIDITY_STATE &s)
{
   s.valid=false;
   s.bullishSweep=false;
   s.bearishSweep=false;
   s.bullishReclaim=false;
   s.bearishReclaim=false;
   s.displacement=false;
   s.sweptHigh=0;
   s.sweptLow=0;
   s.rangeATR=0;
   s.score=0;
   s.barTime=0;

   if(!GoldM1LiquidityEnabled || GoldSymbol=="") return false;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   int need=MathMax(GoldM1LiquidityLookback+3,8);
   int copied=CopyRates(GoldSymbol,PERIOD_M1,1,need,r);
   if(copied<8) return false;

   double sum=0;
   int n=0;
   for(int i=1;i<MathMin(copied,GoldM1LiquidityLookback+1);i++)
   {
      if(r[i].high>r[i].low)
      {
         sum += r[i].high-r[i].low;
         n++;
      }
   }
   if(n<=0) return false;

   double atr=sum/n;
   double range=r[0].high-r[0].low;
   if(atr<=0 || range<=0) return false;

   double priorHigh=r[1].high;
   double priorLow=r[1].low;
   int look=MathMin(copied,GoldM1LiquidityLookback+1);

   for(int i=1;i<look;i++)
   {
      priorHigh=MathMax(priorHigh,r[i].high);
      priorLow=MathMin(priorLow,r[i].low);
   }

   double buffer=atr*GoldM1LiquidityBufferATR;
   double close=r[0].close;

   bool sweptLow=(r[0].low < priorLow-buffer);
   bool sweptHigh=(r[0].high > priorHigh+buffer);

   bool reclaimLow=(close > priorLow+atr*GoldM1ReclaimATR);
   bool reclaimHigh=(close < priorHigh-atr*GoldM1ReclaimATR);

   s.bullishSweep=sweptLow;
   s.bearishSweep=sweptHigh;
   s.bullishReclaim=(sweptLow && reclaimLow);
   s.bearishReclaim=(sweptHigh && reclaimHigh);
   s.displacement=(range >= atr*GoldM1DisplacementATR);
   s.rangeATR=range/atr;
   s.sweptLow=priorLow;
   s.sweptHigh=priorHigh;
   s.barTime=r[0].time;

   if(s.bullishReclaim)
      s.score=MathMin(1.0,0.55+0.20*s.rangeATR+
                      (s.displacement ? 0.20 : 0.0));
   else if(s.bearishReclaim)
      s.score=-MathMin(1.0,0.55+0.20*s.rangeATR+
                       (s.displacement ? 0.20 : 0.0));
   else if(s.bullishSweep)
      s.score=0.25;
   else if(s.bearishSweep)
      s.score=-0.25;

   s.valid=true;
   return true;
}


struct GOLD_SMC_STATE
{
   bool valid;
   bool bullishBOS;
   bool bearishBOS;
   bool bullishCHOCH;
   bool bearishCHOCH;
   bool bullishFVG;
   bool bearishFVG;
   bool bullishOB;
   bool bearishOB;
   bool premium;
   bool discount;
   double score;
   double swingHigh;
   double swingLow;
   double fvgSizeATR;
};

bool DetectGoldSMC(GOLD_SMC_STATE &s)
{
   s.valid=false;
   s.bullishBOS=false; s.bearishBOS=false;
   s.bullishCHOCH=false; s.bearishCHOCH=false;
   s.bullishFVG=false; s.bearishFVG=false;
   s.bullishOB=false; s.bearishOB=false;
   s.premium=false; s.discount=false;
   s.score=0.0; s.swingHigh=0.0; s.swingLow=0.0; s.fvgSizeATR=0.0;

   if(!GoldSMCEnabled || GoldSymbol=="") return false;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   int need=MathMax(GoldSMCSwingLookback+10,80);
   int copied=CopyRates(GoldSymbol,PERIOD_M5,1,need,r);
   if(copied<20) return false;

   double hi=r[1].high, lo=r[1].low;
   for(int i=2;i<MathMin(copied,GoldSMCSwingLookback);i++)
   {
      hi=MathMax(hi,r[i].high);
      lo=MathMin(lo,r[i].low);
   }
   s.swingHigh=hi;
   s.swingLow=lo;

   double atr=0.0;
   int n=MathMin(copied-1,14);
   for(int i=1;i<=n;i++) atr+=r[i].high-r[i].low;
   if(n<=0) return false;
   atr/=n;
   if(atr<=0.0) return false;

   double close=r[0].close;
   s.bullishBOS=(close>hi);
   s.bearishBOS=(close<lo);

   double localHigh=r[1].high, localLow=r[1].low;
   for(int i=2;i<MathMin(copied,8);i++)
   {
      localHigh=MathMax(localHigh,r[i].high);
      localLow=MathMin(localLow,r[i].low);
   }
   s.bullishCHOCH=(r[0].low<localLow && close>localLow);
   s.bearishCHOCH=(r[0].high>localHigh && close<localHigh);

   // M5 three-candle fair-value gap.
   if(copied>=3)
   {
      double bullGap=r[0].low-r[2].high;
      double bearGap=r[2].low-r[0].high;
      if(bullGap>atr*0.05)
      {
         s.bullishFVG=true;
         s.fvgSizeATR=bullGap/atr;
      }
      if(bearGap>atr*0.05)
      {
         s.bearishFVG=true;
         s.fvgSizeATR=MathMax(s.fvgSizeATR,bearGap/atr);
      }
   }

   // Practical order-block proxy: opposite candle immediately before
   // strong displacement on the completed M5 bar.
   double disp=(r[0].high-r[0].low)/atr;
   if(disp>=1.25 && copied>=2)
   {
      if(r[0].close>r[0].open && r[1].close<r[1].open)
         s.bullishOB=true;
      if(r[0].close<r[0].open && r[1].close>r[1].open)
         s.bearishOB=true;
   }

   double mid=(hi+lo)*0.5;
   s.discount=(close<mid);
   s.premium=(close>mid);

   double bull=0.0,bear=0.0;
   if(s.bullishBOS) bull+=0.35;
   if(s.bearishBOS) bear+=0.35;
   if(s.bullishCHOCH) bull+=0.20;
   if(s.bearishCHOCH) bear+=0.20;
   if(GoldSMCUseFVG)
   {
      if(s.bullishFVG) bull+=0.15;
      if(s.bearishFVG) bear+=0.15;
   }
   if(GoldSMCUseOrderBlock)
   {
      if(s.bullishOB) bull+=0.15;
      if(s.bearishOB) bear+=0.15;
   }
   if(GoldSMCUsePremiumDiscount)
   {
      if(s.discount) bull+=0.10;
      if(s.premium) bear+=0.10;
   }

   s.score=MathMax(bull,bear);
   s.valid=true;
   return true;
}

bool GoldSMCSupportsDirection(int direction,double &score)
{
   score=0.0;
   if(!GoldSMCEnabled) return true;

   GOLD_SMC_STATE s;
   if(!DetectGoldSMC(s)) return false;

   if(direction>0)
   {
      if(GoldSMCRequireBOS && !(s.bullishBOS || s.bullishCHOCH))
         return false;
      if(s.bullishBOS) score+=0.35;
      if(s.bullishCHOCH) score+=0.20;
      if(GoldSMCUseFVG && s.bullishFVG) score+=0.15;
      if(GoldSMCUseOrderBlock && s.bullishOB) score+=0.15;
      if(GoldSMCUsePremiumDiscount && s.discount) score+=0.10;
      return score>=GoldSMCMinScore;
   }

   if(direction<0)
   {
      if(GoldSMCRequireBOS && !(s.bearishBOS || s.bearishCHOCH))
         return false;
      if(s.bearishBOS) score+=0.35;
      if(s.bearishCHOCH) score+=0.20;
      if(GoldSMCUseFVG && s.bearishFVG) score+=0.15;
      if(GoldSMCUseOrderBlock && s.bearishOB) score+=0.15;
      if(GoldSMCUsePremiumDiscount && s.premium) score+=0.10;
      return score>=GoldSMCMinScore;
   }

   return false;
}

double GoldRewardAwareRiskPercent(double smcScore,double trendScore,
                                  double expectedR,double waitMinutes,
                                  bool m1LiquidityConfirmed=false)
{
   if(!GoldRewardAwareSizing)
      return GoldBaseRiskPercent;

   double trendQuality=MathMin(1.0,MathAbs(trendScore));
   double smcQuality=MathMin(1.0,smcScore);
   double quality=MathMin(1.0,trendQuality+
                          (smcQuality>0.0 ? smcQuality*GoldSMCBonusWeight : 0.0));

   // Base tier for ordinary trend setups.
   double risk=GoldBaseRiskPercent;

   // SMC event tier: rare, high-information setup.
   bool smcEvent=(smcQuality>=GoldSMCEventMinScore &&
                  trendQuality>=GoldMinimumDirectionalScore);

   bool exceptional=(smcQuality>=GoldSMCExceptionalMinScore &&
                     trendQuality>=MathMin(1.0,
                        GoldMinimumDirectionalScore+0.15) &&
                     expectedR>=GoldMinExpectedR);

   if(smcEvent && (!GoldSMCRequireM1ForEventTier || m1LiquidityConfirmed))
      risk=MathMax(risk,GoldSMCEventRiskPercent);

   if(exceptional && (!GoldSMCRequireM1ForEventTier || m1LiquidityConfirmed))
      risk=MathMax(risk,GoldSMCExceptionalRiskPercent);

   // Reward quality can modestly increase normal setups, but never above cap.
   double rFactor=1.0;
   if(expectedR>=GoldMinExpectedR)
      rFactor=1.0+MathMin(0.15,
                          (expectedR-GoldMinExpectedR)*0.08);

   double qFactor=GoldQualityRiskFloor+
                  quality*(GoldQualityRiskCeiling-GoldQualityRiskFloor);

   // Only apply quality scaling below the SMC event tier.
   if(!(smcEvent && (!GoldSMCRequireM1ForEventTier || m1LiquidityConfirmed)))
      risk*=qFactor;

   // Patience is a small bounded modifier, never a recovery mechanism.
   double patience=1.0;
   if(waitMinutes>=GoldMinMinutesBetweenTrades)
      patience=1.0+MathMin(GoldPatienceBoostMax-1.0,
                           ((waitMinutes-GoldMinMinutesBetweenTrades)/60.0)*
                           (GoldPatienceBoostMax-1.0));

   risk*=rFactor*patience;

   // Hard account-risk ceiling.
   return MathMin(GoldMaxRiskPercent,MathMax(0.0,risk));
}

double CalculateGoldRewardAwareLots(double slPoints,double smcScore,
                                    double trendScore,double expectedR,
                                    double waitMinutes,
                                    bool m1LiquidityConfirmed=false)
{
   if(!UseRiskBasedLots) return NormalizeLots(GoldSymbol,FixedLots);

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskPct=GoldRewardAwareRiskPercent(smcScore,trendScore,
                                             expectedR,waitMinutes,
                                             m1LiquidityConfirmed);
   double riskMoney=equity*riskPct/100.0*
                    EffectiveCapitalPercent()/100.0;

   double tickValue=SymbolInfoDouble(GoldSymbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(GoldSymbol,SYMBOL_TRADE_TICK_SIZE);
   double point=PointOf(GoldSymbol);
   if(tickValue<=0 || tickSize<=0 || slPoints<=0)
      return NormalizeLots(GoldSymbol,FixedLots);

   double valuePerPointPerLot=tickValue*(point/tickSize);
   if(valuePerPointPerLot<=0)
      return NormalizeLots(GoldSymbol,FixedLots);

   return NormalizeLots(GoldSymbol,
                        riskMoney/(slPoints*valuePerPointPerLot));
}

bool GoldM1LiquiditySupportsDirection(int direction)
{
   if(!GoldM1LiquidityEnabled || !GoldM1UseForEntryTiming)
      return true;

   GOLD_M1_LIQUIDITY_STATE s;
   if(!DetectGoldM1Liquidity(s))
      return true;

   if(direction>0)
   {
      // Bullish trend can use a bullish sweep/reclaim as an entry trigger.
      // A bearish M1 sweep is NOT allowed to reverse the M5 trend.
      if(s.bullishReclaim) return true;
      if(s.bearishReclaim) return false;
      return !GoldM1RequireReclaim;
   }

   if(direction<0)
   {
      if(s.bearishReclaim) return true;
      if(s.bullishReclaim) return false;
      return !GoldM1RequireReclaim;
   }

   return false;
}

bool M5TrendGatePasses(MARKET_STATE &m)
{
   if(!UseM5PrimaryTrendGate)
      return true;

   // TF[0] = M1 is deliberately excluded from trend analysis.
   double m5=m.tf[1].trend;
   double m15=m.tf[2].trend;
   double m30=m.tf[3].trend;
   double h1=m.tf[4].trend;
   double h4=m.tf[5].trend;

   double score =
      m5  * GoldM5TrendWeight +
      m15 * GoldM15TrendWeight +
      m30 * GoldM30TrendWeight +
      h1  * GoldH1TrendWeight +
      h4  * GoldH4TrendWeight;

   if(m.direction>0)
   {
      if(m5<M5MinTrendScoreForTrade || m15<0.0 || h1<-0.15) return false;
      if(score<GoldMinimumDirectionalScore) return false;
      if(m.agreement<GoldMinimumTrendAgreement) return false;
      if(RequireM5MomentumAlignment && m.tf[1].momentum<=0.0) return false;
   }
   else if(m.direction<0)
   {
      if(m5>-M5MinTrendScoreForTrade || m15>0.0 || h1>0.15) return false;
      if(score>-GoldMinimumDirectionalScore) return false;
      if(m.agreement<GoldMinimumTrendAgreement) return false;
      if(RequireM5MomentumAlignment && m.tf[1].momentum>=0.0) return false;
   }
   else return false;

   return true;
}

bool PlaceTrendPending(MARKET_STATE &m)
{
   string symbol=m.symbol;
   double point=PointOf(symbol);
   double atrPts=m.tf[1].atrPoints;
   if(atrPts<=0) return false;
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK), bid=SymbolInfoDouble(symbol,SYMBOL_BID);
   if(ask<=0 || bid<=0) return false;
   double minDist=MinStopDistance(symbol)+2*point;
   double entryDist=MathMax(atrPts*EntryATRMultiplier*point,minDist);
   double slDist=MathMax(atrPts*InitialSL_ATR*point,minDist);
   double tpDist=MathMax(atrPts*FixedTP_ATR*point,minDist);
   double entry=(m.direction>0)?ask+entryDist:bid-entryDist;
   double sl=(m.direction>0)?entry-slDist:entry+slDist;
   double tp=(m.direction>0)?entry+tpDist:entry-tpDist;
   entry=NormalizePrice(symbol,entry); sl=NormalizePrice(symbol,sl); tp=NormalizePrice(symbol,tp);
   double lots=CalculateLots(symbol,slDist/point);
   if(!AccountCapitalAllowed(symbol,(m.direction>0?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP),lots,entry))
   {
      if(PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | ACCOUNT MARGIN BLOCK | ",symbol," | dedicated-account margin protection");
      return false;
   }
   bool ok=false;
   if(PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | TREND THESIS | ",symbol," dir=",m.direction," score=",DoubleToString(m.opportunityScore,1)," entry=",DoubleToString(entry,DigitsOf(symbol))," tp=",DoubleToString(tp,DigitsOf(symbol)));
   if(!DryRun)
   {
             trade.SetExpertMagicNumber(BotMagicNumber);
if(m.direction>0) ok=trade.BuyStop(lots,entry,symbol,sl,tp,ORDER_TIME_GTC,0,"NeoFL4.2 TREND BUY");
      else ok=trade.SellStop(lots,entry,symbol,sl,tp,ORDER_TIME_GTC,0,"NeoFL4.2 TREND SELL");
      if(!ok && PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | ORDER FAILED | retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   }
   else ok=true;
   if(ok)
   {
      PendingSymbol=symbol; PendingDirection=m.direction; PendingEntry=entry; PendingCreated=TimeCurrent(); PendingRegime=m.regime; PendingInvalidCount=0;
      return true;
   }
   return false;
}

bool PlaceSidewaysStraddle(MARKET_STATE &m)
{
   string symbol=m.symbol; double point=PointOf(symbol); double atrPts=m.tf[1].atrPoints;
   if(atrPts<=0) return false;
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK), bid=SymbolInfoDouble(symbol,SYMBOL_BID);
   if(ask<=0 || bid<=0) return false;
   double minDist=MinStopDistance(symbol)+2*point;
   double dist=MathMax(atrPts*SidewaysStopATR*point,minDist);
   double slDist=MathMax(atrPts*SidewaysSL_ATR*point,minDist);
   double tpDist=MathMax(atrPts*SidewaysTP_ATR*point,minDist);
   double buy=NormalizePrice(symbol,ask+dist), sell=NormalizePrice(symbol,bid-dist);
   double buySL=NormalizePrice(symbol,buy-slDist), buyTP=NormalizePrice(symbol,buy+tpDist);
   double sellSL=NormalizePrice(symbol,sell+slDist), sellTP=NormalizePrice(symbol,sell-tpDist);
   double lots=CalculateLots(symbol,slDist/point);
    if(!AccountCapitalAllowsCombined(symbol,ORDER_TYPE_BUY_STOP,lots,buy,symbol,ORDER_TYPE_SELL_STOP,lots,sell))
    {
       if(PrintRiskManagerLog)
          Print("NeoFL GOLD 5.3 DUAL ENGINE CAPITAL | ACCOUNT MARGIN BLOCK | ",symbol,
                " | dedicated-account margin protection");
       return false;
    }

    bool ok1=true,ok2=true;
   if(PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | SIDEWAYS STRADDLE | ",symbol," buy=",DoubleToString(buy,DigitsOf(symbol))," sell=",DoubleToString(sell,DigitsOf(symbol)));
   if(!DryRun)
   {
             trade.SetExpertMagicNumber(BotMagicNumber);
ok1=trade.BuyStop(lots,buy,symbol,buySL,buyTP,ORDER_TIME_GTC,0,"NeoFL4.2 RANGE BUY");
      if(!ok1 && PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | BUY STOP FAILED | ",trade.ResultRetcodeDescription());
      ok2=trade.SellStop(lots,sell,symbol,sellSL,sellTP,ORDER_TIME_GTC,0,"NeoFL4.2 RANGE SELL");
      if(!ok2 && PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | SELL STOP FAILED | ",trade.ResultRetcodeDescription());
   }
   if(ok1||ok2)
   {
      PendingSymbol=symbol; PendingDirection=0; PendingEntry=0; PendingCreated=TimeCurrent(); PendingRegime=MARKET_SIDEWAYS; PendingInvalidCount=0;
      return true;
   }
   return false;
}

int FindCandleTrailState(ulong ticket)
{
   for(int i=0;i<ArraySize(CandleTrailStates);i++)
      if(CandleTrailStates[i].ticket==ticket) return i;
   return -1;
}

datetime GetLastCandleTrailBar(ulong ticket)
{
   int idx=FindCandleTrailState(ticket);
   if(idx<0) return 0;
   return CandleTrailStates[idx].lastClosedBar;
}

void SetLastCandleTrailBar(ulong ticket, datetime barTime)
{
   int idx=FindCandleTrailState(ticket);
   if(idx<0)
   {
      int n=ArraySize(CandleTrailStates);
      ArrayResize(CandleTrailStates,n+1);
      CandleTrailStates[n].ticket=ticket;
      CandleTrailStates[n].lastClosedBar=barTime;
      return;
   }
   CandleTrailStates[idx].lastClosedBar=barTime;
}

void CleanupCandleTrailStates()
{
   for(int i=ArraySize(CandleTrailStates)-1;i>=0;i--)
   {
      ulong ticket=CandleTrailStates[i].ticket;
      if(ticket==0) continue;
      bool exists=false;
      for(int p=PositionsTotal()-1;p>=0;p--)
      {
         ulong pt=PositionGetTicket(p);
         if(pt==ticket)
         {
            exists=true;
            break;
         }
      }
      if(!exists)
      {
         int last=ArraySize(CandleTrailStates)-1;
         if(i!=last) CandleTrailStates[i]=CandleTrailStates[last];
         ArrayResize(CandleTrailStates,last);
      }
   }
}

bool ManageCandleStructureTrail()
{
   if(!EnableCandleStructureTrail) return false;

   bool any=false;
   CleanupCandleTrailStates();

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!IsNeoFLMagic((ulong)PositionGetInteger(POSITION_MAGIC))) continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol=="") continue;

      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int dir=(pt==POSITION_TYPE_BUY ? 1 : -1);
      double point=PointOf(symbol);
      double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
      if(point<=0 || bid<=0 || ask<=0) continue;

      MqlRates r[];
      ArraySetAsSeries(r,true);
      if(CopyRates(symbol,CandleTrailTF,0,3,r)<3) continue;

      // r[0] = current/open candle, r[1] = most recently CLOSED candle.
      datetime closedBar=r[1].time;
      if(closedBar<=0) continue;
      if(GetLastCandleTrailBar(ticket)==closedBar) continue;

      // Mark the bar processed even if it is not a favorable candle. This
      // guarantees that one closed candle can cause at most one SL decision.
      SetLastCandleTrailBar(ticket,closedBar);

      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double atrPts=CurrentATRPoints(symbol);
      double atrPrice=(atrPts>0 ? atrPts*point : 0.0);

      double profitPrice=(dir>0 ? bid-open : open-ask);
      if(profitPrice<=0) continue;

      // Require the trade itself to be in profit by a small R amount.
      double initialRisk=0.0;
      if(tp>0.0)
      {
         double tpDistance=MathAbs(tp-open);
         double slTpRatio=((FixedTP_ATR>0.0) ? (InitialSL_ATR/FixedTP_ATR) : 0.0);
         if(slTpRatio>0.0) initialRisk=tpDistance*slTpRatio;
      }
      if(initialRisk<=0.0 && atrPrice>0.0)
         initialRisk=atrPrice*InitialSL_ATR;
      if(initialRisk<=0.0) continue;

      double profitR=profitPrice/initialRisk;
      if(profitR<CandleTrailMinProfit_R) continue;

      bool favorable=(dir>0 ? r[1].close>r[1].open : r[1].close<r[1].open);
      if(CandleTrailRequireDirectionalClose && !favorable) continue;

      // The candle must close in the profitable side of the entry. This
      // prevents a green candle whose low is still below entry from creating
      // a meaningless "profit" stop.
      if(dir>0 && r[1].close<=open) continue;
      if(dir<0 && r[1].close>=open) continue;

      double buffer=(atrPrice>0.0 ? atrPrice*CandleTrailBufferATR : point*2.0);
      double desiredSL=(dir>0 ? r[1].low-buffer : r[1].high+buffer);

      // Broker stop/freeze constraints.
      double minDist=MinStopDistance(symbol)+2.0*point;
      if(dir>0) desiredSL=MathMin(desiredSL,bid-minDist);
      else      desiredSL=MathMax(desiredSL,ask+minDist);
      desiredSL=NormalizePrice(symbol,desiredSL);

      // Critical rule: candle trail ONLY RATchets. Never loosen protection.
      bool improve=false;
      if(dir>0)
         improve=(sl<=0.0 || desiredSL>sl+point);
      else
         improve=(sl<=0.0 || desiredSL<sl-point);

      if(!improve) continue;

      bool ok=true;
      if(!DryRun)
         ok=trade.PositionModify(ticket,desiredSL,tp);

      if(!ok)
      {
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | CANDLE TRAIL FAILED | ",symbol,
                  " ticket=",ticket,
                  " bar=",TimeToString(closedBar,TIME_DATE|TIME_MINUTES),
                  " retcode=",trade.ResultRetcode(),
                  " ",trade.ResultRetcodeDescription(),
                  " oldSL=",DoubleToString(sl,DigitsOf(symbol)),
                  " newSL=",DoubleToString(desiredSL,DigitsOf(symbol)),
                  " profitR=",DoubleToString(profitR,2));
      }
      else
      {
         any=true;
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | CANDLE TRAIL | ",symbol,
                  " ticket=",ticket,
                  " TF=",EnumToString(CandleTrailTF),
                  " closed=",TimeToString(closedBar,TIME_DATE|TIME_MINUTES),
                  " candleO=",DoubleToString(r[1].open,DigitsOf(symbol)),
                  " candleH=",DoubleToString(r[1].high,DigitsOf(symbol)),
                  " candleL=",DoubleToString(r[1].low,DigitsOf(symbol)),
                  " candleC=",DoubleToString(r[1].close,DigitsOf(symbol)),
                  " profitR=",DoubleToString(profitR,2),
                  " NEW_SL=",DoubleToString(desiredSL,DigitsOf(symbol)),
                  " TP=",DoubleToString(tp,DigitsOf(symbol)));
      }
   }
   return any;
}

bool ManageAllPositions()
{
   bool any=false;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!IsNeoFLMagic((ulong)PositionGetInteger(POSITION_MAGIC))) continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol=="") continue;
      any=true;

      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int dir=(pt==POSITION_TYPE_BUY ? 1 : -1);

      double point=PointOf(symbol);
      double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
      if(point<=0 || bid<=0 || ask<=0) continue;

      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      string comment=PositionGetString(POSITION_COMMENT);

      double atrPts=CurrentATRPoints(symbol);
      if(atrPts<=0) continue;
      double atrPrice=atrPts*point;

      double profitPrice=(dir>0 ? bid-open : open-ask);
      if(profitPrice<=0) continue;

      // Recover the original R from the fixed TP and the strategy's
      // original SL/TP ratio. This remains stable even after SL moves.
      double initialRisk=0.0;
      bool rangeTrade=(StringFind(comment,"RANGE")>=0);
      if(tp>0.0)
      {
         double tpDistance=MathAbs(tp-open);
         double slTpRatio=(rangeTrade && SidewaysTP_ATR>0.0)
                           ? (SidewaysSL_ATR/SidewaysTP_ATR)
                           : ((FixedTP_ATR>0.0) ? (InitialSL_ATR/FixedTP_ATR) : 0.0);
         if(slTpRatio>0.0) initialRisk=tpDistance*slTpRatio;
      }
      if(initialRisk<=0.0)
         initialRisk=atrPrice*InitialSL_ATR;
      if(initialRisk<=0.0) continue;

      double profitR=profitPrice/initialRisk;
      double desiredSL=sl;
      bool shouldModify=false;
      string reason="";

      // ------------------------------------------------------------
      // STAGE 1: EARLY PROFIT LOCK / BREAK-EVEN
      // This is the protection that was missing in 3.8. A trade no
      // longer has to reach +1 ATR before its winning state is protected.
      // ------------------------------------------------------------
      if(EnableBreakEvenLock && profitR>=BreakEvenTrigger_R && !(EnableCandleStructureTrail && DisableATRProfitTrailWhenCandleTrail))
      {
         double lockDistance=initialRisk*BreakEvenLock_R;
         double beSL=(dir>0 ? open+lockDistance : open-lockDistance);
         desiredSL=beSL;
         shouldModify=true;
         reason="BE_LOCK";
      }

      // ------------------------------------------------------------
      // STAGE 2: PROFIT TRAIL
      // Fixed TP remains unchanged. The trailing SL only ratchets in
      // the profitable direction and can never loosen an existing SL.
      // ------------------------------------------------------------
      if(profitR>=ProfitTrailStart_R && !(EnableCandleStructureTrail && DisableATRProfitTrailWhenCandleTrail))
      {
         double trailDist=atrPrice*TrailingDistance_ATR;
         double trailSL=(dir>0 ? bid-trailDist : ask+trailDist);

         if(dir>0)
            desiredSL=MathMax(desiredSL,trailSL);
         else
            desiredSL=(desiredSL<=0.0 ? trailSL : MathMin(desiredSL,trailSL));

         shouldModify=true;
         reason="TRAIL";
      }

      if(!shouldModify) continue;

      // Respect broker minimum stop distance.
      double minDist=MinStopDistance(symbol)+2.0*point;
      if(dir>0)
         desiredSL=MathMin(desiredSL,bid-minDist);
      else
         desiredSL=MathMax(desiredSL,ask+minDist);

      desiredSL=NormalizePrice(symbol,desiredSL);

      // Never loosen the current SL. The BE stage can create the first
      // protected stop; later stages can only improve it.
      double step=MathMax(atrPrice*TrailStep_ATR,point);
      bool improve=false;
      if(dir>0)
         improve=(sl<=0.0 || desiredSL>sl+step);
      else
         improve=(sl<=0.0 || desiredSL<sl-step);

      if(!improve) continue;

      bool ok=true;
      if(!DryRun)
         ok=trade.PositionModify(ticket,desiredSL,tp);

      if(!ok)
      {
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | ",reason," FAILED | ",symbol,
                  " ticket=",ticket,
                  " retcode=",trade.ResultRetcode(),
                  " ",trade.ResultRetcodeDescription(),
                  " oldSL=",DoubleToString(sl,DigitsOf(symbol)),
                  " newSL=",DoubleToString(desiredSL,DigitsOf(symbol)),
                  " profitR=",DoubleToString(profitR,2));
      }
      else if(PrintExecutionLog)
      {
         Print("NeoFL GOLD 5.3 DUAL ENGINE | ",reason," | ",symbol,
               " ticket=",ticket,
               " profitR=",DoubleToString(profitR,2),
               " profitPts=",DoubleToString(profitPrice/point,1),
               " SL=",DoubleToString(desiredSL,DigitsOf(symbol)),
               " TP=",DoubleToString(tp,DigitsOf(symbol)));
      }
   }

   return any;
}

void DetectNewFillAndManage()
{
   // Find all NeoFL positions. A fill immediately cancels any remaining
   // same-symbol pending orders, preventing both sides of a straddle
   // from becoming positions.
   bool found=false;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!IsNeoFLMagic((ulong)PositionGetInteger(POSITION_MAGIC))) continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol=="") continue;

      found=true;

      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ActiveTradeSymbol=symbol;
      ActiveTradeDirection=(pt==POSITION_TYPE_BUY ? 1 : -1);

      if(CampaignStarted==0)
         CampaignStarted=TimeCurrent();

      if(ActiveCampaignTP==0)
         ActiveCampaignTP=PositionGetDouble(POSITION_TP);

      if(ActiveInitialEntry==0)
         ActiveInitialEntry=PositionGetDouble(POSITION_PRICE_OPEN);

      CancelPendingAfterFill(symbol);

      if(symbol==GoldSymbol)
         ClearGoldPendingState();
      else
         ClearStandalonePendingState(symbol);
   }

   if(!found)
      return;
}


void EvaluatePendingThesis()
{
   if(!CancelStalePending || PendingSymbol=="") return;
   if(HasOurPosition(PendingSymbol)) return;
   if(TimeCurrent()-PendingCreated>PendingExpiryMinutes*60)
   {
      if(PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | THESIS EXPIRED | ",PendingSymbol);
      CancelOurPending(PendingSymbol); return;
   }
   int idx=-1;
   for(int i=0;i<MarketCount;i++) if(Markets[i].symbol==PendingSymbol) {idx=i;break;}
   if(idx<0 || !Markets[idx].dataReady) return;
   MARKET_STATE m=Markets[idx];
   double distPts=MathAbs(PendingEntry-(m.direction>0?SymbolInfoDouble(PendingSymbol,SYMBOL_ASK):SymbolInfoDouble(PendingSymbol,SYMBOL_BID)))/PointOf(PendingSymbol);
   bool invalid=false;
   if(PendingDirection>0 && m.trend<PendingInvalidTrend) invalid=true;
   if(PendingDirection<0 && m.trend>-PendingInvalidTrend) invalid=true;

    // M5 is the primary Gold trend timeframe.
    if(UseM5PrimaryTrendGate)
    {
       if(PendingDirection>0 && m.tf[1].trend<-M5MinTrendScoreForTrade)
          invalid=true;
       if(PendingDirection<0 && m.tf[1].trend>M5MinTrendScoreForTrade)
          invalid=true;
    }
   if(PendingDirection>0 && m.trend<=-PendingOppositeTrend) invalid=true;
   if(PendingDirection<0 && m.trend>=PendingOppositeTrend) invalid=true;
   if(PendingDirection!=0 && distPts>m.tf[1].atrPoints*MaxPendingDistanceATR) invalid=true;
   if(m.regime==MARKET_HIGH_VOL) invalid=true;
   if(invalid) PendingInvalidCount++; else PendingInvalidCount=0;
   if(PendingInvalidCount>=PendingInvalidConfirmations)
   {
      if(PrintExecutionLog) Print("NeoFL GOLD 5.3 DUAL ENGINE | THESIS INVALIDATED | ",PendingSymbol," trend=",DoubleToString(m.trend,2));
      CancelOurPending(PendingSymbol);
   }
}

void FindAndExecuteBest()
{
   if(!EnableTrading) return;
   if(TimeCurrent()-LastPositionClose<ReentryCooldownSeconds) return;

   // Dedicated bot: scan only this bot's own universe and select the best
   // currently qualified opportunity. There is NO standalone market.
   if(OneActiveMarketOnly && CountOurPositions()>0)
      return;

   if(BestIndex<0 || BestIndex>=MarketCount) return;
   MARKET_STATE m=Markets[BestIndex];
   if(!m.dataReady || m.opportunityScore<MinOpportunityScore) return;
   if(UseSessionFilterForExecution && !m.sessionActive) return;
   if(m.regime==MARKET_HIGH_VOL) return;

   if(m.regime==MARKET_STRONG_UP || m.regime==MARKET_STRONG_DOWN)
   {
      if(!AllowTrendTrading) return;
      if(MathAbs(m.trend)<MinTrendScoreForTrendTrade ||
         m.agreement<MinAgreementForTrendTrade) return;

      // M5 is the primary Gold trend gate. M1 cannot flip direction alone.
      if(!M5TrendGatePasses(m))
      {
         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | M5 PRIMARY TREND GATE BLOCK | symbol=",m.symbol,
                  " M5 trend=",DoubleToString(m.tf[1].trend,2),
                  " M5 momentum=",DoubleToString(m.tf[1].momentum,2),
                  " aggregate=",DoubleToString(m.trend,2));
         return;
      }

      PlaceTrendPending(m);
      return;
   }

   if(m.regime==MARKET_SIDEWAYS && AllowSidewaysStraddle)
   {
      if(m.rangeScore<0.40) return;
      PlaceSidewaysStraddle(m);
      return;
   }
}

void ExecutionCycle()
{
   UpdateGoldLiquidityDefense();
   DetectNewFillAndManage();
   ManageAllPositions();
   // M1 is reserved for trailing/exit management only.
       ManageCandleStructureTrail();
   EvaluatePendingThesis();
   ResetCampaignIfFlat();

if(NEOFL_BOT_MODE==1)
   {
      // Gold standalone bot: Gold is the ONLY traded market.
      ManageGoldAnchor();
   }
   else
   {
      // Index/BTC standalone bots: the global brain is restricted to
      // the universe built specifically for this bot.
      FindAndExecuteBest();
   }
}

//==================================================================
// INITIALIZATION
//==================================================================

int OnInit()
{
   CapitalLedgerStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   CapitalLedgerStartTime=TimeCurrent();
   PrintCapitalMode();

   trade.SetExpertMagicNumber(BotMagicNumber);
   trade.SetDeviationInPoints(20);

   BuildUniverse();

   Print("NeoFL GOLD 5.3 DUAL ENGINE | DEDICATED ACCOUNT | "
         "STRATEGY CAPITAL=100% | NO STANDALONE MARKET | BASE BALANCE=",
         DoubleToString(CapitalLedgerStartBalance,2));

   if(MarketCount==0)
   {
      Print("NeoFL GOLD 5.3 DUAL ENGINE | NO USABLE "
            "GOLD/XAU SYMBOL FOUND");
      return INIT_FAILED;
   }

   ScanMarkets();
   ExecutionCycle();

   EventSetTimer(MathMax(1,ScanSeconds));
   DisplayDashboard();

   Print("NeoFL GOLD 5.3 DUAL ENGINE STARTED | "
         "DEDICATED ACTIVE SCANNER | symbols=",MarketCount,
         " | scan=",ScanSeconds,"s | host=",_Symbol);

   Print("NeoFL GOLD 5.3 DUAL ENGINE | Scanner reads only the "
         "dedicated Gold/XAU universe across ",
         TFName(TF1)," / ",TFName(TF2)," / ",TFName(TF3)," / ",
         TFName(TF4)," / ",TFName(TF5)," / ",TFName(TF6));

   return INIT_SUCCEEDED;
}

//==================================================================
// TIMER
//==================================================================

void OnTimer()
{
   ScanMarkets();
   ExecutionCycle();
   DisplayDashboard();
}

//==================================================================
// TRADE TRANSACTION / IMMEDIATE OCO
//==================================================================

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal=trans.deal;
   if(deal==0) return;

   if(!HistoryDealSelect(deal))
      return;

   long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
   if(!IsNeoFLMagic((ulong)magic))
      return;

   string symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
   if(symbol=="") return;

   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   ENUM_DEAL_REASON reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON);

   if(symbol==GoldSymbol && entry==DEAL_ENTRY_OUT &&
      reason==DEAL_REASON_SL && EnableGoldLiquiditySweepDefense &&
      GoldBlockOppositeAfterStop)
   {
      int sweepDir=0; datetime sweepBar=0; double sweepLevel=0.0; double sweepATR=0.0;
      bool sweepNow=DetectGoldLiquiditySweep(sweepDir,sweepBar,sweepLevel,sweepATR);

      if(GoldShockActive || sweepNow ||
         (GoldShockEventBar>0 && TimeCurrent()-GoldShockEventBar<=GoldShockLockSeconds))
      {
         if(sweepNow)
         {
            GoldShockEventBar=sweepBar;
            GoldShockDirection=sweepDir;
         }

         if(GoldShockStopoutWindowStart==0 ||
            TimeCurrent()-GoldShockStopoutWindowStart>GoldWhipsawWindowSeconds)
         {
            GoldShockStopoutWindowStart=TimeCurrent();
            GoldShockStopouts=0;
         }

         GoldShockStopouts++;
         GoldShockLastStopout=TimeCurrent();
         GoldShockActive=true;
         GoldShockUntil=TimeCurrent()+MathMax(60,GoldShockLockSeconds);

         if(PrintExecutionLog)
            Print("NeoFL GOLD 5.3 DUAL ENGINE | STOP DURING/AT LIQUIDITY EVENT | ",
                  "opposite entry LOCKED | stopouts=",GoldShockStopouts);
         return;
      }
   }

   if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT)
      return;

   if(PrintExecutionLog)
      Print("NeoFL GOLD 5.3 DUAL ENGINE | FILL DETECTED | ",symbol,
            " deal=",deal," -> immediate OCO");

   // The transaction callback is the fastest protection against both
   // sides of a range straddle filling before the timer cycle runs.
   CancelPendingAfterFill(symbol);
}

//==================================================================
// TICK
//==================================================================

void OnTick()
{
   // Position trailing/invalidation should react to ticks, not only the timer.
   if(EnableTrading)
   {
      ManageAllPositions();
      ManageCandleStructureTrail();
   }
}

//==================================================================
// DEINITIALIZATION
//==================================================================

void OnDeinit(
   const int reason)
{
   EventKillTimer();
   Comment("");
}
//+------------------------------------------------------------------+
