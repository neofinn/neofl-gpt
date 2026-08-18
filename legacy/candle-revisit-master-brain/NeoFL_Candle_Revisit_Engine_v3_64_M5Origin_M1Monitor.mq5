//+------------------------------------------------------------------+
//| Candle Level Revisit EA - Standalone Concept                     |
//| No NeoFL engine dependencies                                     |
//+------------------------------------------------------------------+
#property strict
#property version   "3.64"
#property description "Standalone M5 Bull/Bear candle-level strategy with M1-in-M5 entries, continuous monitoring, no SL orders, and opposite-entry recovery/reversal."

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
input bool              InpAllowM1Origin        = false; // M1 is MONITOR/REASSESS only; no independent origin entry
input double            InpM1OriginRiskFactor   = 0.50; // smaller lot than M5-origin trade
input double            InpMinLotM5             = 0.10;
input double            InpMinLotM1             = 0.05; // retained for compatibility; M1-origin entries disabled
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
input bool              InpAllowOppositeRecovery = true;
input double            InpRecoveryTargetATR     = 1.00;
input double            InpRecoveryExtraProfitMoney = 0.0;
input double            InpProfitFarFromTPPct    = 0.35; // remaining TP distance / original TP distance
input double            InpOppositeNormalLotFactor = 1.0;
input bool              InpShowNeoFLDashboard   = true;
input ENUM_BASE_CORNER  InpDashboardCorner      = CORNER_LEFT_UPPER;
input int               InpDashboardX            = 12;
input int               InpDashboardY            = 24;
input int               InpDashboardWidth        = 300;
input int               InpDashboardHeight       = 560;



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
   double lots = InpLots;
   if(InpUseMartingale && g_martingale_step > 0)
      lots *= MathPow(InpMartingaleMultiplier,
                      MathMin(g_martingale_step, InpMaxMartingaleSteps));

   return NormalizeRequestedLots(lots, InpMinLotM5);
}

double M1OriginLots()
{
   return NormalizeRequestedLots(TradeLots() * InpM1OriginRiskFactor, InpMinLotM1);
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
         for(int i=0;i<ArraySize(rr);++i)
            m5range+=rr[i].high-rr[i].low;
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

   string scan = (active>0 ? "ACTIVE" : "WAITING");
   color scanClr = (active>0 ? clrLime : clrSilver);

   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double fm=AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   int x=InpDashboardX, y=InpDashboardY, w=InpDashboardWidth;
   DashRect("BG",x,y,w,InpDashboardHeight,clrBlack,clrDarkSlateGray);

   DashText("Brand","NeoFL",x+20,y+18,30,clrAqua,"Arial Bold");
   DashText("Tag","PRECISION. LOGIC. CONSISTENCY.",x+22,y+52,9,clrGold,"Arial Bold");
   DashText("Bot","NeoFL Candle Revisit Engine",x+20,y+78,18,clrWhite,"Arial Bold");
   DashText("Version","v3.62",x+w-62,y+82,12,clrLime,"Arial Bold");
   DashText("Desc","M5 origin • M1 monitor • CTrade",x+20,y+104,9,clrSilver);

   DashText("MarketH","MARKET",x+20,y+132,10,clrAqua,"Arial Bold");
   DashText("Market",_Symbol+" • M5 origin / M1 monitor",x+20,y+150,11,clrWhite);
   DashText("Bid","Bid  "+DoubleToString(bid,_Digits),x+20,y+170,10,clrSilver);
   DashText("Ask","Ask  "+DoubleToString(ask,_Digits),x+w/2,y+170,10,clrSilver);

   DashText("RegimeH","REGIME",x+20,y+198,10,clrAqua,"Arial Bold");
   DashText("Regime",regime,x+w-110,y+196,11,regimeClr,"Arial Bold");
   DashText("ATR","ATR("+IntegerToString(InpM5ATRPeriod)+")  "+DoubleToString(atr,_Digits),x+20,y+218,10,clrWhite);

   DashText("ScanH","LEVEL ENGINE",x+20,y+246,10,clrAqua,"Arial Bold");
   DashText("Scan",scan,x+w-85,y+244,11,scanClr,"Arial Bold");
   DashText("Levels","Open levels  "+IntegerToString(active),x+20,y+266,10,clrWhite);
   DashText("Revisit","Revisited     "+IntegerToString(revisited),x+20,y+284,10,clrSilver);

   DashText("PosH","POSITION",x+20,y+312,10,clrAqua,"Arial Bold");
   color pClr=(p>0 ? clrLime : (p<0 ? clrTomato : clrSilver));
   DashText("Pos",pos,x+w-85,y+310,11,pClr,"Arial Bold");
   DashText("Float","Floating P/L  "+DashFmtMoney(p),x+20,y+332,10,pClr);
   DashText("Lots","Lots           "+DoubleToString(lots,2),x+20,y+350,10,clrWhite);
   if(lots>0)
   {
      DashText("Entry","Entry          "+DoubleToString(entry,_Digits),x+20,y+368,10,clrSilver);
      DashText("TP","TP             "+(tp>0?DoubleToString(tp,_Digits):"MONITORED"),x+20,y+386,10,clrSilver);
   }

   DashText("AcctH","ACCOUNT",x+20,y+414,10,clrAqua,"Arial Bold");
   DashText("Bal","Balance        "+DashFmtMoney(bal),x+20,y+434,10,clrWhite);
   DashText("Eq","Equity         "+DashFmtMoney(eq),x+20,y+452,10,clrWhite);
   DashText("FM","Free Margin    "+DashFmtMoney(fm),x+20,y+470,10,clrSilver);

   DashText("Rules","NO INITIAL SL  •  PROFIT-ONLY EARLY EXIT",x+20,y+498,9,clrGold,"Arial Bold");
   DashText("Recovery","M1 ORIGIN: DISABLED  •  OPPOSITE RECOVERY: "+(InpAllowOppositeRecovery?"ON":"OFF"),
            x+20,y+516,9,InpAllowOppositeRecovery?clrLime:clrTomato,"Arial Bold");
   DashText("Footer","NeoFL Trading Systems",x+20,y+538,12,clrAqua,"Arial Bold");

   ChartRedraw();
}

bool IsHedgingAccount()
{
   ENUM_ACCOUNT_MARGIN_MODE mode =
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return (mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}

double MoneyPerLotAtDistance(const double distance)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0 || distance <= 0.0)
      return 0.0;

   return (distance / tick_size) * tick_value;
}

double RecoveryLots(const double loss_money, const double target_distance)
{
   double money_per_lot = MoneyPerLotAtDistance(target_distance);
   if(money_per_lot <= 0.0)
      return 0.0;

   double required = loss_money + InpRecoveryExtraProfitMoney;
   double requested = required / money_per_lot;

   double broker_max = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), InpMaxLot);
   if(requested > broker_max + 1e-9)
   {
      PrintFormat("Opposite recovery skipped: required %.2f lots exceeds max %.2f; "
                  "loss %.2f cannot be covered at target distance %.2f.",
                  requested, broker_max, loss_money, target_distance);
      return 0.0;
   }

   return NormalizeRequestedLots(requested, InpMinLotM5);
}

bool ProfitIsFarFromTP(const bool buy, const double entry, const double tp,
                       const double current_price)
{
   if(tp <= 0.0)
      return false;

   double total_distance = MathAbs(tp - entry);
   if(total_distance <= 0.0)
      return false;

   double remaining = buy ? (tp - current_price) : (current_price - tp);
   if(remaining < 0.0)
      remaining = 0.0;

   return (remaining / total_distance >= InpProfitFarFromTPPct);
}

bool ClosePositionProfitOnly(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   double profit = PositionGetDouble(POSITION_PROFIT)
                 + PositionGetDouble(POSITION_SWAP);
   if(profit <= 0.0)
      return false;

   return trade.PositionClose(ticket);
}

// Opens the opposite position as a true hedge on a losing trade.
// Its TP is deliberately placed in the opposite direction and the lot
// size is calculated so that the projected TP profit covers the current
// floating loss plus the configured recovery amount.
bool HasOppositePosition(const bool current_buy)
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t))
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic)
         continue;

      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      if(buy!=current_buy)
         return true;
   }
   return false;
}

bool OpenOppositeRecovery(const bool opposite_buy,
                           const double current_loss,
                           const double target_distance)
{
   if(!InpAllowOppositeRecovery || !IsHedgingAccount())
      return false;

   if(current_loss <= 0.0 || target_distance <= 0.0)
      return false;

   double lots = RecoveryLots(current_loss, target_distance);
   if(lots <= 0.0)
      return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return false;

   double entry = opposite_buy ? ask : bid;
   double tp = opposite_buy
             ? entry + target_distance
             : entry - target_distance;
   tp = NormalizePrice(tp);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFilling(InpFillingMode);

   bool ok = opposite_buy
           ? trade.Buy(lots, _Symbol, 0.0, 0.0, tp, "CLVL Opposite Recovery")
           : trade.Sell(lots, _Symbol, 0.0, 0.0, tp, "CLVL Opposite Recovery");

   if(!ok)
   {
      Print("Opposite recovery failed. Retcode=", trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription());
      return false;
   }

   PrintFormat("Opposite recovery opened: %s %.2f lots, target %.2f, loss covered %.2f",
               opposite_buy ? "BUY" : "SELL", lots, tp, current_loss);
   return true;
}

bool OpenOppositeNormal(const bool opposite_buy)
{
   double lots = NormalizeRequestedLots(TradeLots() * InpOppositeNormalLotFactor,
                                        InpMinLotM5);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return false;

   double entry = opposite_buy ? ask : bid;

   // Normal opposite target uses current M5 ATR as its structural unit.
   double unit = MathMax(GetATR(PERIOD_M5, InpM5ATRPeriod),
                         GetATR(PERIOD_M1, InpM5ATRPeriod));
   if(unit <= 0.0)
      return false;

   double tp = opposite_buy
             ? entry + InpRiskReward * unit
             : entry - InpRiskReward * unit;
   tp = NormalizePrice(tp);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFilling(InpFillingMode);

   return opposite_buy
        ? trade.Buy(lots, _Symbol, 0.0, 0.0, tp, "CLVL Opposite Normal")
        : trade.Sell(lots, _Symbol, 0.0, 0.0, tp, "CLVL Opposite Normal");
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
   // CONTINUOUS TRADE MONITOR
   //
   // No initial SL is placed.
   // No trailing SL order is placed.
   // The EA continuously evaluates the open trade.
   //
   // The trade may:
   //   1) remain open until broker TP is hit, or
   //   2) be closed early by the management engine ONLY while profitable.
   //
   // HARD SAFETY RULE:
   // Never voluntarily close a position while POSITION_PROFIT <= 0.

   ulong ticket=0;
   if(!SelectOurPosition(ticket))
   {
      g_trailing_ticket=0;
      g_trailing_active=false;
      g_trailing_extreme=0.0;
      return;
   }

   double profit=PositionGetDouble(POSITION_PROFIT);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double tp=PositionGetDouble(POSITION_TP);
   bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);

   // Broker-side TP remains the hard profit objective.
   // If TP is hit, the broker closes the position; the EA does not need
   // to manufacture an SL order.
   if(tp > 0.0)
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      bool tp_reached = buy ? (bid >= tp) : (ask <= tp);
      if(tp_reached)
         return;
   }

   // We intentionally do NOT create/modify any SL here.
   // Early exit decisions must be made by the closed-M1/M5 thesis
   // reassessment logic and are permitted only in profit.

   MqlRates m1[];
   ArrayResize(m1,3);
   ArraySetAsSeries(m1,true);

   if(CopyRates(_Symbol,PERIOD_M1,0,3,m1) < 3)
      return;

   // Only a newly CLOSED M1 candle can trigger an early-exit assessment.
   static datetime last_monitor_m1=0;
   datetime closed_m1=m1[1].time;

   if(closed_m1 == last_monitor_m1)
      return;

   last_monitor_m1=closed_m1;

   // Do not close a losing or non-profitable trade.
   if(profit <= 0.0)
      return;

   // M1 management is allowed to decide that the original opportunity
   // has failed / reversed, but it can only close the trade while profitable.
   //
   // Existing reassessment function sets the pending state. We use that
   // state as the early-exit trigger rather than placing an SL.
   bool early_exit = false;

   if(InpReassessAfterTrail && g_m1_reassess_pending)
      early_exit = true;

   if(early_exit && profit > 0.0)
   {
      if(trade.PositionClose(ticket))
      {
         g_m1_reassess_pending=false;
         g_m5_reassess_pending=false;
         g_m1_reassess_bars_left=0;
         g_m5_reassess_bars_left=0;
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
      ok = trade.Buy(TradeLots(), _Symbol, 0.0, 0.0, tp, comment);
   else
      ok = trade.Sell(TradeLots(), _Symbol, 0.0, 0.0, tp, comment);

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

// M1 is allowed to originate a trade ONLY when its signal level is
// physically inside the range of the last CLOSED M5 candle.
// It does not replace the M5 engine; it is a lower-risk sub-entry.
bool EvaluateM1Origin()
{
   // M1 origin is intentionally disabled. M1 may monitor/reassess an
   // existing M5-origin trade, but it must never create the initial trade.
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

bool FindM1OppositeSignal(const bool current_buy, bool &opposite_buy)
{
   if(!InpAllowM1Origin)
      return false;

   MqlRates m1[];
   ArrayResize(m1,3);
   ArraySetAsSeries(m1,true);
   if(CopyRates(_Symbol,PERIOD_M1,0,3,m1)<3)
      return false;

   MqlRates m5[];
   ArrayResize(m5,2);
   ArraySetAsSeries(m5,true);
   if(CopyRates(_Symbol,PERIOD_M5,0,2,m5)<2)
      return false;

   MqlRates c=m1[1];
   double range=c.high-c.low;
   if(range<=0.0 || c.close==c.open)
      return false;

   double body=MathAbs(c.close-c.open);
   double upper=c.high-MathMax(c.open,c.close);
   double lower=MathMin(c.open,c.close)-c.low;

   bool bull=c.close>c.open;
   bool bear=c.close<c.open;

   bool wickless=(body>0.0 &&
                  (upper+lower)/range<=InpWicklessRatio &&
                  body/range>=InpMinBodyRatio);

   if(!wickless)
      return false;

   if(!M1PriceInsideM5Range(c.open,m5[1]))
      return false;

   bool signal_buy=bull;
   if(signal_buy==current_buy)
      return false;

   opposite_buy=signal_buy;
   return true;
}

bool ManageOppositeEntry(const bool opposite_buy,
                          const double signal_level,
                          const bool signal_is_m1)
{
   ulong ticket=0;
   if(!SelectOurPosition(ticket))
      return false;

   if(!PositionSelectByTicket(ticket))
      return false;

   bool current_buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   if(opposite_buy==current_buy)
      return false;

   // Never stack repeated opposite hedges from multiple M1/M5 confirmations.
   if(HasOppositePosition(current_buy))
      return false;

   double profit=PositionGetDouble(POSITION_PROFIT);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double tp=PositionGetDouble(POSITION_TP);
   double current=current_buy
                 ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                 : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   // CASE A: original trade is profitable and the TP is still far away.
   // Close profit and reverse with normal sizing. No recovery martingale.
   if(profit>0.0 && ProfitIsFarFromTP(current_buy,entry,tp,current))
   {
      if(!ClosePositionProfitOnly(ticket))
         return false;

      return OpenOppositeNormal(opposite_buy);
   }

   // CASE B: original trade is losing/non-profitable.
   // Do NOT close it. Hedge with the opposite direction and size the
   // opposite trade to cover the floating loss at its projected TP.
   if(profit<=0.0)
   {
      if(!IsHedgingAccount())
      {
         Print("Opposite recovery skipped: account is not hedging mode.");
         return false;
      }

      double atr = signal_is_m1
                 ? GetATR(PERIOD_M1,InpM5ATRPeriod)
                 : GetATR(PERIOD_M5,InpM5ATRPeriod);

      double target_distance = MathMax(MathAbs(signal_level-current),
                                       atr*InpRecoveryTargetATR);

      if(target_distance<=0.0)
         return false;

      return OpenOppositeRecovery(opposite_buy,MathAbs(profit),target_distance);
   }

   // Profitable but close to TP: do not churn the position.
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
int OnInit()
{
   if(!ValidateConfiguredLotFloors())
      return(INIT_PARAMETERS_INCORRECT);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   ArrayResize(g_levels, 0);
   g_last_bar_time = iTime(_Symbol, InpTimeframe, 0);

   Print("NeoFL Candle Revisit Engine initialized. Dashboard=", InpShowNeoFLDashboard);
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
   DashUpdate();

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
         // M1 is NOT an entry/origin engine in v3.64.
         // It is used only for monitoring and post-entry reassessment.
         if(HasOpenPosition())
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
