//+------------------------------------------------------------------+
//| NeoFL_Observer_Core.mqh                                         |
//| Shared observer calculations. No trade execution.                |
//+------------------------------------------------------------------+
#ifndef __NEOFL_OBSERVER_CORE_MQH__
#define __NEOFL_OBSERVER_CORE_MQH__

string NeoFLObs_Sym(const string symbol)
{
   return (symbol=="" ? _Symbol : symbol);
}
string NeoFLObs_Key(const string prefix,const string symbol,const ulong magic,const string suffix)
{
   return prefix+"_"+NeoFLObs_Sym(symbol)+"_"+(string)magic+"_"+suffix;
}
void NeoFLObs_Put(const string prefix,const string symbol,const ulong magic,const string suffix,const double value)
{
   GlobalVariableSet(NeoFLObs_Key(prefix,symbol,magic,suffix),value);
}
bool NeoFLObs_OurPosition(const string symbol,const ulong magic,ulong &ticket)
{
   string sym=NeoFLObs_Sym(symbol);
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      ticket=t;
      return true;
   }
   ticket=0;
   return false;
}
double NeoFLObs_ATR(const string symbol,ENUM_TIMEFRAMES tf,const int period)
{
   int h=iATR(NeoFLObs_Sym(symbol),tf,period);
   if(h==INVALID_HANDLE) return 0.0;
   double b[];
   ArraySetAsSeries(b,true);
   double v=0.0;
   if(CopyBuffer(h,0,1,1,b)==1) v=b[0];
   IndicatorRelease(h);
   return v;
}
void NeoFLObs_ResetPositionState(const string prefix,const string symbol,const ulong magic)
{
   NeoFLObs_Put(prefix,symbol,magic,"MFE_MONEY",0);
   NeoFLObs_Put(prefix,symbol,magic,"MAE_MONEY",0);
   NeoFLObs_Put(prefix,symbol,magic,"M1_EXIT",0);
   NeoFLObs_Put(prefix,symbol,magic,"M1_OPPOSITE",0);
}
void NeoFLObs_Position(const string prefix,const string symbol,const ulong magic,
                       const int confirm_bars,const double profit_arm,
                       const double retrace_pct,const double atr_reversal_mult)
{
   ulong ticket=0;
   if(!NeoFLObs_OurPosition(symbol,magic,ticket))
   {
      NeoFLObs_ResetPositionState(prefix,symbol,magic);
      NeoFLObs_Put(prefix,symbol,magic,"M1_STATE",1); // WAITING
      return;
   }

   bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double bid=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_BID);
   double ask=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_ASK);
   double px=buy?bid:ask;

   static ulong tracked_ticket=0;
   static double mfe=0.0, mae=0.0;
   static bool armed=false;

   if(tracked_ticket!=ticket)
   {
      tracked_ticket=ticket;
      mfe=0.0; mae=0.0; armed=false;
      NeoFLObs_Put(prefix,symbol,magic,"M1_EXIT",0);
      NeoFLObs_Put(prefix,symbol,magic,"M1_OPPOSITE",0);
   }

   if(profit>mfe) mfe=profit;
   if(profit<mae) mae=profit;

   NeoFLObs_Put(prefix,symbol,magic,"MFE_MONEY",mfe);
   NeoFLObs_Put(prefix,symbol,magic,"MAE_MONEY",MathAbs(mae));

   if(mfe>=profit_arm) armed=true;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   ArrayResize(r,5);
   if(CopyRates(NeoFLObs_Sym(symbol),PERIOD_M1,0,5,r)<5)
      return;

   double atr=NeoFLObs_ATR(symbol,PERIOD_M1,14);
   int same=0;
   for(int i=1;i<=confirm_bars && i<ArraySize(r);++i)
   {
      bool bull=(r[i].close>r[i].open);
      bool bear=(r[i].close<r[i].open);
      if((buy && bear) || (!buy && bull)) same++;
   }

   bool opposite=(same>=confirm_bars);
   double retrace=0.0;
   if(mfe>0.000001)
      retrace=MathMax(0.0,100.0*(mfe-profit)/mfe);

   bool profit_exit=false; // M1 observer NEVER closes a normal profitable trade; it only observes.
   double adverse=MathAbs(px-entry);
   bool deep_adverse=(atr>0.0 && adverse>=atr*atr_reversal_mult && opposite);

   NeoFLObs_Put(prefix,symbol,magic,"M1_OPPOSITE",opposite?1:0);
   NeoFLObs_Put(prefix,symbol,magic,"M1_EXIT",deep_adverse?1:0);
   NeoFLObs_Put(prefix,symbol,magic,"M1_STATE",deep_adverse?4:(opposite?3:(armed?2:1)));
   NeoFLObs_Put(prefix,symbol,magic,"M1_LAST_CLOSED",(double)r[1].time);
   NeoFLObs_Put(prefix,symbol,magic,"MFE_RETRACE_PCT",retrace);
   NeoFLObs_Put(prefix,symbol,magic,"OPPOSITE_CONF",
               100.0*(double)same/(double)MathMax(1,confirm_bars));
}
void NeoFLObs_Drawdown(const string prefix,const string symbol,const ulong magic)
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   static double peak_eq=0.0;
   if(eq>peak_eq) peak_eq=eq;
   double dd=(peak_eq>0.0?100.0*(peak_eq-eq)/peak_eq:0.0);

   NeoFLObs_Put(prefix,symbol,magic,"EQUITY",eq);
   NeoFLObs_Put(prefix,symbol,magic,"BALANCE",bal);
   NeoFLObs_Put(prefix,symbol,magic,"DD_PCT",dd);
   NeoFLObs_Put(prefix,symbol,magic,"FREE_MARGIN",AccountInfoDouble(ACCOUNT_MARGIN_FREE));
   NeoFLObs_Put(prefix,symbol,magic,"MARGIN_USED",AccountInfoDouble(ACCOUNT_MARGIN));
   NeoFLObs_Put(prefix,symbol,magic,"MARGIN_PCT",
               eq>0.0?100.0*AccountInfoDouble(ACCOUNT_MARGIN)/eq:100.0);
}
void NeoFLObs_Recovery(const string prefix,const string symbol,const ulong magic)
{
   ulong ticket=0;
   double loss=0.0;
   if(NeoFLObs_OurPosition(symbol,magic,ticket))
   {
      double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(p<0.0) loss=-p;
   }

   double broker_max=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_VOLUME_MAX);
   if(broker_max<=0.0) broker_max=10.0;
   // NeoFL hard execution cap is 0.01 lot regardless of broker maximum.
   double maxlot=MathMin(broker_max,0.01);

   double point=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_POINT);
   double tick_size=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_TRADE_TICK_VALUE);
   double atr=NeoFLObs_ATR(symbol,PERIOD_M1,14);
   double distance=MathMax(point,atr);
   double money_one=(tick_size>0.0 && tick_value>0.0 ? distance/tick_size*tick_value:0.0);
   double required=(money_one>0.0?loss/money_one:0.0);
   double coverage=(required>0.0?MathMin(100.0,maxlot/required*100.0):100.0);

   NeoFLObs_Put(prefix,symbol,magic,"RECOVERY_LOSS",loss);
   NeoFLObs_Put(prefix,symbol,magic,"RECOVERY_REQUIRED_LOTS",required);
   NeoFLObs_Put(prefix,symbol,magic,"RECOVERY_MAX_LOTS",maxlot);
   NeoFLObs_Put(prefix,symbol,magic,"RECOVERY_COVERAGE",coverage);
}
void NeoFLObs_Probability(const string prefix,const string symbol,const ulong magic,const int max_trades)
{
   datetime to=TimeCurrent();
   datetime from=to-90*86400;
   if(!HistorySelect(from,to)) return;

   int wins=0,losses=0,total=0;
   int deals=HistoryDealsTotal();
   for(int i=deals-1;i>=0 && total<max_trades;--i)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=NeoFLObs_Sym(symbol)) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=magic) continue;
      if(HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;

      double p=HistoryDealGetDouble(d,DEAL_PROFIT)+
               HistoryDealGetDouble(d,DEAL_SWAP)+
               HistoryDealGetDouble(d,DEAL_COMMISSION);
      total++;
      if(p>0.0) wins++;
      else if(p<0.0) losses++;
   }

   NeoFLObs_Put(prefix,symbol,magic,"WIN_PROB",total>0?100.0*wins/total:0.0);
   NeoFLObs_Put(prefix,symbol,magic,"LOSS_PROB",total>0?100.0*losses/total:0.0);
   NeoFLObs_Put(prefix,symbol,magic,"SAMPLE_TRADES",total);
}
void NeoFLObs_Update(const string prefix,const string symbol,const ulong magic,
                    const int confirm_bars,const double profit_arm,
                    const double retrace_pct,const double atr_reversal_mult,
                    const int probability_trades)
{
   NeoFLObs_Put(prefix,symbol,magic,"HEARTBEAT",(double)TimeCurrent());
   NeoFLObs_Position(prefix,symbol,magic,confirm_bars,profit_arm,retrace_pct,atr_reversal_mult);
   NeoFLObs_Drawdown(prefix,symbol,magic);
   NeoFLObs_Recovery(prefix,symbol,magic);
   NeoFLObs_Probability(prefix,symbol,magic,probability_trades);
}
#endif
