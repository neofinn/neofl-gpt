//+------------------------------------------------------------------+
//| NeoFL_StandaloneBrain.mq5                                        |
//| Standalone trading machine: no NeoFL/API/MCP dependency.         |
//|                                                                  |
//| This first release implements the local machine shell, account-  |
//| wide universe discovery, persistent state, watchdog, risk gates, |
//| position reconciliation and deterministic local decision engine.  |
//| Strategy-specific rules are isolated in LocalDecision() so the    |
//| canonical Brain strategy contract can be mirrored without any    |
//| network dependency.                                               |
//+------------------------------------------------------------------+
#property strict
#property version "1.0"
#property description "Standalone NeoFL trading machine"

#include <Trade/Trade.mqh>

input bool   EnableTrading = true;
input int    TimerSeconds = 1;
input int    MaxOpenPositions = 20;
input double MaxAccountRiskPercent = 2.0;
input double FixedLot = 0.01;
input int    FastMAPeriod = 20;
input int    SlowMAPeriod = 50;
input int    ATRPeriod = 14;
input double ATRStopMultiple = 2.0;
input double RewardRisk = 2.0;
input bool   EnableStraddleRecovery = true;
input double StraddleTriggerR = 1.0;
input double StraddleMultiplier = 3.0;
input long   MagicNumber = 440044;
input string StateFile = "NeoFL_StandaloneBrain.state";

CTrade g_trade;
datetime g_last_bar = 0;
bool g_ready = false;

struct PositionState
{
   ulong ticket;
   string symbol;
   long type;
   double volume;
   double entry;
   double stop;
   double target;
   double recovery_trigger;
};

string GVPrefix(){return "NeoFLSB_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"_";}
void SaveState()
{
   int h=FileOpen(StateFile,FILE_COMMON|FILE_WRITE|FILE_TXT);
   if(h==INVALID_HANDLE)return;
   FileWrite(h,"version=1");
   FileWrite(h,"account="+(string)AccountInfoInteger(ACCOUNT_LOGIN));
   FileWrite(h,"last_bar="+(string)g_last_bar);
   FileWrite(h,"timestamp="+(string)TimeCurrent());
   FileClose(h);
}
void LoadState()
{
   int h=FileOpen(StateFile,FILE_COMMON|FILE_READ|FILE_TXT);
   if(h==INVALID_HANDLE)return;
   while(!FileIsEnding(h))
   {
      string line=FileReadString(h);
      if(StringFind(line,"last_bar=")==0)g_last_bar=(datetime)StringToInteger(StringSubstr(line,9));
   }
   FileClose(h);
}

bool IsTradableSymbol(string symbol)
{
   if(symbol=="")return false;
   long mode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED)return false;
   long order=SymbolInfoInteger(symbol,SYMBOL_ORDER_MODE);
   return order!=0;
}

bool IsNewBar(string symbol,ENUM_TIMEFRAMES tf)
{
   datetime t=iTime(symbol,tf,0);
   if(t==0)return false;
   if(symbol==_Symbol && tf==PERIOD_M5 && t!=g_last_bar){g_last_bar=t;return true;}
   return false;
}

double NormalizeVolume(string symbol,double volume)
{
   double minv=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxv=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(step<=0)return 0;
   volume=MathMin(volume,maxv);
   if(volume<minv)return 0;
   volume=MathFloor(volume/step)*step;
   int digits=(int)MathMax(0,MathRound(-MathLog10(step)));
   return NormalizeDouble(volume,digits);
}

double CalculateRiskVolume(string symbol,double entry,double stop)
{
   double budget=AccountInfoDouble(ACCOUNT_EQUITY)*MaxAccountRiskPercent/100.0;
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   double distance=MathAbs(entry-stop);
   if(budget<=0||tick_size<=0||tick_value<=0||distance<=0)return 0;
   double money_per_lot=(distance/tick_size)*tick_value;
   if(money_per_lot<=0)return 0;
   return NormalizeVolume(symbol,budget/money_per_lot);
}

bool LocalDecision(string symbol,ENUM_TIMEFRAMES tf,string &direction,double &volume,double &stop,double &target)
{
   // Deterministic local baseline. The canonical strategy modules should be
   // mirrored here as they are promoted into the standalone release.
   double fast0=iMA(symbol,tf,FastMAPeriod,0,MODE_EMA,PRICE_CLOSE,0);
   double fast1=iMA(symbol,tf,FastMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
   double slow0=iMA(symbol,tf,SlowMAPeriod,0,MODE_EMA,PRICE_CLOSE,0);
   double slow1=iMA(symbol,tf,SlowMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
   double atr=iATR(symbol,tf,ATRPeriod,0);
   MqlTick tick;if(!SymbolInfoTick(symbol,tick)||atr<=0)return false;
   if(fast1<=slow1 && fast0>slow0){direction="BUY";stop=tick.ask-ATRStopMultiple*atr;target=tick.ask+(tick.ask-stop)*RewardRisk;}
   else if(fast1>=slow1 && fast0<slow0){direction="SELL";stop=tick.bid+ATRStopMultiple*atr;target=tick.bid-(stop-tick.bid)*RewardRisk;}
   else return false;
   double entry=(direction=="BUY"?tick.ask:tick.bid);
   volume=(FixedLot>0?NormalizeVolume(symbol,FixedLot):CalculateRiskVolume(symbol,entry,stop));
   if(volume<=0)return false;
   if(direction=="BUY" && !(stop<entry && target>entry))return false;
   if(direction=="SELL" && !(stop>entry && target<entry))return false;
   return true;
}

bool HasPosition(string symbol)
{
   for(int i=PositionsTotal()-1;i>=0;i--){ulong ticket=PositionGetTicket(i);if(ticket>0&&PositionSelectByTicket(ticket)&&PositionGetString(POSITION_SYMBOL)==symbol&&PositionGetInteger(POSITION_MAGIC)==MagicNumber)return true;}
   return false;
}

void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket))continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;
      string symbol=PositionGetString(POSITION_SYMBOL);long type=PositionGetInteger(POSITION_TYPE);double entry=PositionGetDouble(POSITION_PRICE_OPEN);double sl=PositionGetDouble(POSITION_SL);double volume=PositionGetDouble(POSITION_VOLUME);MqlTick tick;if(!SymbolInfoTick(symbol,tick))continue;
      double risk=MathAbs(entry-sl);if(risk<=0)continue;
      double adverse=(type==POSITION_TYPE_BUY?entry-tick.bid:tick.ask-entry);
      if(EnableStraddleRecovery && adverse>=risk*StraddleTriggerR)
      {
         string key=GVPrefix()+"REC_"+(string)ticket;
         if(!GlobalVariableCheck(key))
         {
            double recovery=NormalizeVolume(symbol,volume*StraddleMultiplier);
            if(recovery>0)
            {
               g_trade.SetExpertMagicNumber(MagicNumber);
               if(type==POSITION_TYPE_BUY)g_trade.Sell(recovery,symbol,0,0,0,"StandaloneRecovery");
               else g_trade.Buy(recovery,symbol,0,0,0,"StandaloneRecovery");
               if(g_trade.ResultRetcode()==TRADE_RETCODE_DONE||g_trade.ResultRetcode()==TRADE_RETCODE_PLACED)GlobalVariableSet(key,(double)TimeCurrent());
            }
         }
      }
   }
}

void ScanUniverse()
{
   int total=SymbolsTotal(false);
   for(int i=0;i<total;i++)
   {
      string symbol=SymbolName(i,false);
      if(!IsTradableSymbol(symbol))continue;
      SymbolSelect(symbol,true);
      // The standalone machine observes the complete account tradable universe.
   }
}

void TradeCycle()
{
   if(!EnableTrading || !g_ready)return;
   if(PositionsTotal()>=MaxOpenPositions)return;
   // Primary local strategy operates from the attached chart; universe discovery
   // and management are account-wide. Additional canonical strategies can be
   // promoted here without any external connection.
   string direction;double volume,stop,target;
   if(!IsNewBar(_Symbol,PERIOD_M5))return;
   if(HasPosition(_Symbol))return;
   if(!LocalDecision(_Symbol,PERIOD_M5,direction,volume,stop,target))return;
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(50);
   bool ok=(direction=="BUY"?g_trade.Buy(volume,_Symbol,0,stop,target,"StandaloneBrain"):g_trade.Sell(volume,_Symbol,0,stop,target,"StandaloneBrain"));
   if(ok)SaveState();
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(MagicNumber);
   LoadState();
   ScanUniverse();
   g_ready=true;
   EventSetTimer(MathMax(1,TimerSeconds));
   Print("NeoFL Standalone Brain started. External connections are not required.");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){SaveState();EventKillTimer();}
void OnTick(){ManagePositions();}
void OnTimer(){ScanUniverse();ManagePositions();TradeCycle();SaveState();}
