//+------------------------------------------------------------------+
//| NeoFL ARK 7.1 - MT5                                              |
//| ARK-native multi-asset scanner + M1 execution/trailing/re-entry  |
//|                                                                  |
//| IMPORTANT: Insert the proprietary ARK mathematical rules in      |
//| ARKSignal(). No generic volume/liquidity filter is used.         |
//+------------------------------------------------------------------+
#property strict
#property version   "7.10"

#include <Trade/Trade.mqh>
CTrade trade;

input string InpSymbols = "BTCUSD,XAUUSD,NAS100,US30,GER40,ETHUSD";
input ENUM_TIMEFRAMES InpExecTF = PERIOD_M1;
input double InpLots = 0.10;
input ulong InpMagic = 710071;
input int InpScanSeconds = 1;
input int InpMaxReentries = 2;
input bool InpAllowMultipleSymbols = true;
input bool InpUseRankingOnlyWhenCoincident = true;
input int InpM1Lookback = 14;
input double InpATRMult = 1.0;
input int InpSwingBars = 5;

enum ARK_DIRECTION { ARK_NONE=0, ARK_LONG=1, ARK_SHORT=-1 };
enum ARK_THESIS { THESIS_INVALID=0, THESIS_VALID=1, THESIS_WEAK=2 };

struct ARK_OPPORTUNITY
{
   string symbol;
   ARK_DIRECTION direction;
   double score;
   double entryLow;
   double entryHigh;
   double invalidation;
   double target;
   datetime detected;
   string cycle;
   bool valid;
};

struct ARK_CYCLE
{
   string cycle;
   string symbol;
   ARK_DIRECTION direction;
   int entries;
   bool thesisValid;
   bool active;
   double lastEntry;
   double lastExit;
};

ARK_OPPORTUNITY g_ops[];
ARK_CYCLE g_cycles[];
datetime g_lastBar[];

string Trim(string s)
{
   StringTrimLeft(s); StringTrimRight(s); return s;
}

string CycleID(string symbol, datetime t)
{
   return symbol + "_" + IntegerToString((long)t);
}

int FindCycle(string cycle)
{
   for(int i=0;i<ArraySize(g_cycles);i++)
      if(g_cycles[i].cycle==cycle) return i;
   return -1;
}

void AddCycle(const ARK_OPPORTUNITY &o)
{
   int n=ArraySize(g_cycles);
   ArrayResize(g_cycles,n+1);
   g_cycles[n].cycle=o.cycle;
   g_cycles[n].symbol=o.symbol;
   g_cycles[n].direction=o.direction;
   g_cycles[n].entries=0;
   g_cycles[n].thesisValid=true;
   g_cycles[n].active=true;
   g_cycles[n].lastEntry=0;
   g_cycles[n].lastExit=0;
}

double ATRProxy(string symbol,int shift=0)
{
   MqlRates r[];
   ArraySetAsSeries(r,true);
   int need=MathMax(InpM1Lookback+2,20);
   if(CopyRates(symbol,InpExecTF,shift,need,r)<need) return 0;
   double sum=0;
   for(int i=0;i<InpM1Lookback;i++)
      sum += r[i].high-r[i].low;
   return sum/InpM1Lookback;
}

bool M1Features(string symbol,double &close,double &swingHigh,double &swingLow,double &momentum)
{
   MqlRates r[];
   ArraySetAsSeries(r,true);
   int need=MathMax(InpM1Lookback+InpSwingBars+3,30);
   if(CopyRates(symbol,InpExecTF,0,need,r)<need) return false;

   close=r[0].close;
   swingHigh=r[1].high;
   swingLow=r[1].low;

   for(int i=1;i<=InpSwingBars;i++)
   {
      swingHigh=MathMax(swingHigh,r[i].high);
      swingLow=MathMin(swingLow,r[i].low);
   }

   double atr=ATRProxy(symbol,0);
   if(atr<=0) return false;
   momentum=(r[0].close-r[InpM1Lookback].close)/atr;
   return true;
}

//==================================================================//
// ARK 7.1 PROPRIETARY SIGNAL HOOK                                  //
//==================================================================//
// This is intentionally isolated. Replace the body with the exact
// ARK mathematical setup rules. Nothing outside this function should
// manufacture a signal.
//
// Required output:
// direction, score, entry zone, invalidation, target.
//
// Volume, tick-volume, order-book and liquidity filters are NOT used.
bool ARKSignal(string symbol, ARK_OPPORTUNITY &o)
{
   o.valid=false;
   o.symbol=symbol;
   o.direction=ARK_NONE;
   o.score=0;
   o.entryLow=0;
   o.entryHigh=0;
   o.invalidation=0;
   o.target=0;

   // ---------------------------------------------------------------
   // INSERT EXACT ARK 7.1 MATHEMATICS HERE.
   // ---------------------------------------------------------------
   // Example interface only:
   // if(ARK_LongCondition(...)) { ... }
   // if(ARK_ShortCondition(...)) { ... }
   //
   // Do not replace ARK with generic indicators.
   return false;
}

bool NewBar(string symbol)
{
   datetime t=iTime(symbol,InpExecTF,0);
   if(t==0) return false;

   int idx=-1;
   string list[];
   int n=StringSplit(InpSymbols,',',list);
   for(int i=0;i<n;i++) if(Trim(list[i])==symbol) { idx=i; break; }

   if(idx<0) return false;
   if(ArraySize(g_lastBar)<n) ArrayResize(g_lastBar,n);

   if(g_lastBar[idx]==t) return false;
   g_lastBar[idx]=t;
   return true;
}

void ScanUniverse()
{
   ArrayResize(g_ops,0);

   string s[];
   int n=StringSplit(InpSymbols,',',s);
   for(int i=0;i<n;i++)
   {
      string symbol=Trim(s[i]);
      if(symbol=="") continue;
      SymbolSelect(symbol,true);

      ARK_OPPORTUNITY o;
      if(ARKSignal(symbol,o))
      {
         o.detected=TimeCurrent();
         o.cycle=CycleID(symbol,o.detected);
         o.valid=true;

         int k=ArraySize(g_ops);
         ArrayResize(g_ops,k+1);
         g_ops[k]=o;
      }
   }
}

void RankCoincident()
{
   // Ranking is ONLY invoked when more than one opportunity
   // is simultaneously present in the same scan decision set.
   int n=ArraySize(g_ops);
   if(n<=1) return;

   for(int i=0;i<n-1;i++)
      for(int j=i+1;j<n;j++)
         if(g_ops[j].score>g_ops[i].score)
         {
            ARK_OPPORTUNITY tmp=g_ops[i];
            g_ops[i]=g_ops[j];
            g_ops[j]=tmp;
         }
}

bool HasPositionForCycle(string cycle)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(StringFind(c,cycle)>=0) return true;
   }
   return false;
}

double M1Entry(string symbol,const ARK_OPPORTUNITY &o,double &sl,string &model)
{
   double c,hi,lo,mom;
   if(!M1Features(symbol,c,hi,lo,mom)) return 0;

   double atr=ATRProxy(symbol,0);
   if(atr<=0) return 0;

   // M1 is execution optimization. It cannot change ARK direction.
   // Current base execution candidates:
   // 1) immediate
   // 2) pullback into ARK zone
   // 3) M1 directional confirmation
   //
   // The production optimizer can select among these using stored
   // walk-forward statistics.
   model="IMMEDIATE";

   if(o.direction==ARK_LONG)
   {
      if(o.entryLow>0 && o.entryHigh>0 && c<=o.entryHigh)
         model="PULLBACK";
      else if(mom>0)
         model="M1_CONFIRMATION";

      sl=(o.invalidation>0 ? MathMin(o.invalidation,lo) : lo);
      if(sl>=c) sl=c-atr*InpATRMult;
   }
   else if(o.direction==ARK_SHORT)
   {
      if(o.entryLow>0 && o.entryHigh>0 && c>=o.entryLow)
         model="PULLBACK";
      else if(mom<0)
         model="M1_CONFIRMATION";

      sl=(o.invalidation>0 ? MathMax(o.invalidation,hi) : hi);
      if(sl<=c) sl=c+atr*InpATRMult;
   }
   else return 0;

   return c;
}

bool ExecuteOpportunity(const ARK_OPPORTUNITY &o)
{
   if(HasPositionForCycle(o.cycle)) return false;

   if(FindCycle(o.cycle)<0) AddCycle(o);

   double sl=0;
   string model="";
   double entry=M1Entry(o.symbol,o,sl,model);
   if(entry<=0) return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(o.symbol);
   trade.SetAsyncMode(false);

   string comment="ARK7.1|"+o.cycle+"|"+model;
   bool ok=false;

   if(o.direction==ARK_LONG)
      ok=trade.Buy(InpLots,o.symbol,0.0,sl,o.target,comment);
   else if(o.direction==ARK_SHORT)
      ok=trade.Sell(InpLots,o.symbol,0.0,sl,o.target,comment);

   if(!ok)
   {
      Print("ARK 7.1 CTrade execution failed: ",o.symbol,
            " retcode=",trade.ResultRetcode(),
            " desc=",trade.ResultRetcodeDescription());
      return false;
   }

   if(ok)
   {
      int c=FindCycle(o.cycle);
      if(c>=0)
      {
         g_cycles[c].entries++;
         g_cycles[c].lastEntry=entry;
      }
      Print("ARK 7.1 ENTRY: ",o.symbol," ",EnumToString(o.direction),
            " model=",model," cycle=",o.cycle);
   }
   return ok;
}

void ManageTrailing()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double oldSL=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);

      double c,hi,lo,mom;
      if(!M1Features(symbol,c,hi,lo,mom)) continue;

      double newSL=oldSL;
      if(type==POSITION_TYPE_BUY)
      {
         if(hi>0 && (oldSL==0 || lo>oldSL)) newSL=lo;
         if(newSL>oldSL && newSL<c)
            if(!trade.PositionModify(ticket,newSL,tp))
               Print("ARK 7.1 CTrade trailing modify failed: ",ticket,
                     " retcode=",trade.ResultRetcode(),
                     " desc=",trade.ResultRetcodeDescription());
      }
      else if(type==POSITION_TYPE_SELL)
      {
         if(hi>0 && (oldSL==0 || hi<oldSL)) newSL=hi;
         if((oldSL==0 || newSL<oldSL) && newSL>c)
            if(!trade.PositionModify(ticket,newSL,tp))
               Print("ARK 7.1 CTrade trailing modify failed: ",ticket,
                     " retcode=",trade.ResultRetcode(),
                     " desc=",trade.ResultRetcodeDescription());
      }
   }
}

void ReentryAssessment()
{
   // Called after a trailing exit is detected.
   // The exact ARK thesis reassessment belongs in ARKReassess().
}

ARK_THESIS ARKReassess(const ARK_OPPORTUNITY &o)
{
   // Insert exact ARK thesis validation here.
   // Trailing exit itself is NOT an ARK invalidation.
   return THESIS_INVALID;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(magic!=(long)InpMagic) return;

   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT) return;

   string comment=HistoryDealGetString(trans.deal,DEAL_COMMENT);
   if(StringFind(comment,"ARK7.1|")<0) return;

   // We intentionally do not immediately mark the ARK thesis invalid.
   // A trailing pullback must trigger thesis reassessment.
   Print("ARK 7.1 EXIT detected. Re-entry assessment required for: ",comment);
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   EventSetTimer(MathMax(1,InpScanSeconds));
   Print("NeoFL ARK 7.1 initialized.");
   Print("Scanner: Crypto + Gold + Indices CFDs");
   Print("Ranking: only for coincident opportunities");
   Print("Volume/liquidity qualification: DISABLED");
   Print("M1 execution + trailing architecture: ENABLED");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   ScanUniverse();

   if(ArraySize(g_ops)>1 && InpUseRankingOnlyWhenCoincident)
      RankCoincident();

   for(int i=0;i<ArraySize(g_ops);i++)
      ExecuteOpportunity(g_ops[i]);

   ManageTrailing();
}

void OnTick()
{
   // Execution/trailing is timer-driven so a single chart attachment
   // can scan the complete configured CFD universe.
}
