//+------------------------------------------------------------------+
//| NeoFL_StandaloneBrain.mq5                                        |
//| Standalone trading machine: no NeoFL/API/MCP dependency.         |
//+------------------------------------------------------------------+
#property strict
#property version "1.0.1"
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
      if(StringFind(line,"last_bar=")==0)
         g_last_bar=(datetime)StringToInteger(StringSubstr(line,9));
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
   if(symbol==_Symbol && tf==PERIOD_M5 && t!=g_last_bar)
   {
      g_last_bar=t;
      return true;
   }
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

bool ReadIndicatorValue(int handle,int shift,double &value)
{
   if(handle==INVALID_HANDLE)return false;
   double buffer[1];
   ArraySetAsSeries(buffer,true);
   bool ok=(CopyBuffer(handle,0,shift,1,buffer)==1);
   if(ok)value=buffer[0];
   IndicatorRelease(handle);
   return ok;
}

bool ReadMA(string symbol,ENUM_TIMEFRAMES tf,int period,int shift,double &value)
{
   int handle=iMA(symbol,tf,period,0,MODE_EMA,PRICE_CLOSE);
   return ReadIndicatorValue(handle,shift,value);
}

bool ReadATR(string symbol,ENUM_TIMEFRAMES tf,int period,int shift,double &value)
{
   int handle=iATR(symbol,tf,period);
   return ReadIndicatorValue(handle,shift,value);
}

bool LocalDecision(string symbol,ENUM_TIMEFRAMES tf,string &direction,double &volume,double &stop,double &target)
{
   double fast0,fast1,slow0,slow1,atr;
   if(!ReadMA(symbol,tf,FastMAPeriod,0,fast0))return false;
   if(!ReadMA(symbol,tf,FastMAPeriod,1,fast1))return false;
   if(!ReadMA(symbol,tf,SlowMAPeriod,0,slow0))return false;
   if(!ReadMA(symbol,tf,SlowMAPeriod,1,slow1))return false;
   if(!ReadATR(symbol,tf,ATRPeriod,0,atr))return false;

   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick)||atr<=0)return false;

   if(fast1<=slow1 && fast0>slow0)
   {
      direction="BUY";
      stop=tick.ask-ATRStopMultiple*atr;
      target=tick.ask+(tick.ask-stop)*RewardRisk;
   }
   else if(fast1>=slow1 && fast0<slow0)
   {
      direction="SELL";
      stop=tick.bid+ATRStopMultiple*atr;
      target=tick.bid-(stop-tick.bid)*RewardRisk;
   }
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
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL)==symbol &&
         PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         return true;
   }
   return false;
}

void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket))continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      long type=PositionGetInteger(POSITION_TYPE);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double volume=PositionGetDouble(POSITION_VOLUME);
      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick))continue;

      double risk=MathAbs(entry-sl);
      if(risk<=0)continue;
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
               bool placed=(type==POSITION_TYPE_BUY ?
                  g_trade.Sell(recovery,symbol,0,0,0,"StandaloneRecovery") :
                  g_trade.Buy(recovery,symbol,0,0,0,"StandaloneRecovery"));
               if(placed && (g_trade.ResultRetcode()==TRADE_RETCODE_DONE ||
                             g_trade.ResultRetcode()==TRADE_RETCODE_PLACED))
                  GlobalVariableSet(key,(double)TimeCurrent());
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
   }
}

void TradeCycle()
{
   if(!EnableTrading || !g_ready)return;
   if(PositionsTotal()>=MaxOpenPositions)return;

   // Local standalone decision engine. Account-wide discovery and management
   // remain active; the canonical Brain strategy can replace this module.
   if(!IsNewBar(_Symbol,PERIOD_M5))return;
   if(HasPosition(_Symbol))return;

   string direction;
   double volume,stop,target;
   if(!LocalDecision(_Symbol,PERIOD_M5,direction,volume,stop,target))return;

   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(50);
   bool ok=(direction=="BUY" ?
      g_trade.Buy(volume,_Symbol,0,stop,target,"StandaloneBrain") :
      g_trade.Sell(volume,_Symbol,0,stop,target,"StandaloneBrain"));
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

void OnDeinit(const int reason)
{
   SaveState();
   EventKillTimer();
}

void OnTick(){ManagePositions();}
void OnTimer(){ScanUniverse();ManagePositions();TradeCycle();SaveState();}
