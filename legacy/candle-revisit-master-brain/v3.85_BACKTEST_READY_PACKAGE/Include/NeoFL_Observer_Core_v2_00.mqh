//+------------------------------------------------------------------+
//| NeoFL_Observer_Core.mqh v2.00                                    |
//| Silent M1 observer + M3 straddle/reassessment state engine.       |
//| NEVER executes trades.                                            |
//+------------------------------------------------------------------+
#ifndef __NEOFL_OBSERVER_CORE_V2_MQH__
#define __NEOFL_OBSERVER_CORE_V2_MQH__

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
double NeoFLObs_Get(const string prefix,const string symbol,const ulong magic,const string suffix,const double fallback=0.0)
{
   string k=NeoFLObs_Key(prefix,symbol,magic,suffix);
   if(!GlobalVariableCheck(k)) return fallback;
   return GlobalVariableGet(k);
}

bool NeoFLObs_IsStraddlePosition()
{
   string c=PositionGetString(POSITION_COMMENT);
   return (StringFind(c,"NEOFL STRADDLE")>=0);
}

bool NeoFLObs_MainPosition(const string symbol,const ulong magic,ulong &ticket)
{
   string sym=NeoFLObs_Sym(symbol);
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      if(NeoFLObs_IsStraddlePosition()) continue;
      ticket=t;
      return true;
   }
   ticket=0;
   return false;
}

bool NeoFLObs_StraddlePosition(const string symbol,const ulong magic,ulong &ticket)
{
   string sym=NeoFLObs_Sym(symbol);
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      if(!NeoFLObs_IsStraddlePosition()) continue;
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

double NeoFLObs_MoneyPerLotMove(const string symbol,const bool buy,const double from,const double to)
{
   double pnl=0.0;
   ENUM_ORDER_TYPE type=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,NeoFLObs_Sym(symbol),1.0,from,to,pnl))
      return 0.0;
   return MathAbs(pnl);
}

void NeoFLObs_ResetPositionState(const string prefix,const string symbol,const ulong magic)
{
   NeoFLObs_Put(prefix,symbol,magic,"M1_STATE",0);
   NeoFLObs_Put(prefix,symbol,magic,"M1_EXIT",0);
   NeoFLObs_Put(prefix,symbol,magic,"M1_OPPOSITE",0);
   NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_ARM",0);
   NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_EXIT",0);
   NeoFLObs_Put(prefix,symbol,magic,"BASKET_TERMINATE",0);
   NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_LOTS",0);
   NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_REQUIRED_LOTS",0);
   NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_COVERAGE",0);
   NeoFLObs_Put(prefix,symbol,magic,"RISK_STATE",0);
}

void NeoFLObs_M1SilentMeasure(const string prefix,const string symbol,const ulong magic,
                              double &mfe,double &mae)
{
   ulong ticket=0;
   if(!NeoFLObs_MainPosition(symbol,magic,ticket))
   {
      NeoFLObs_Put(prefix,symbol,magic,"MFE_MONEY",0);
      NeoFLObs_Put(prefix,symbol,magic,"MAE_MONEY",0);
      return;
   }

   double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   static ulong tracked=0;
   static double local_mfe=0.0,local_mae=0.0;
   if(tracked!=ticket)
   {
      tracked=ticket;
      local_mfe=0.0;
      local_mae=0.0;
   }
   if(profit>local_mfe) local_mfe=profit;
   if(profit<local_mae) local_mae=profit;
   mfe=local_mfe;
   mae=MathAbs(local_mae);

   NeoFLObs_Put(prefix,symbol,magic,"MFE_MONEY",mfe);
   NeoFLObs_Put(prefix,symbol,magic,"MAE_MONEY",mae);

   // M1 is observational only: no exit/opposite signals are produced here.
   NeoFLObs_Put(prefix,symbol,magic,"M1_STATE",1);
}

void NeoFLObs_Drawdown(const string prefix,const string symbol,const ulong magic,
                       double &position_loss_pct)
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   static double peak_eq=0.0;
   if(eq>peak_eq) peak_eq=eq;
   double account_dd=(peak_eq>0.0?100.0*(peak_eq-eq)/peak_eq:0.0);

   position_loss_pct=0.0;
   ulong ticket=0;
   if(NeoFLObs_MainPosition(symbol,magic,ticket))
   {
      double loss=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(loss<0.0 && eq>0.0)
         position_loss_pct=(-loss/eq)*100.0;
   }

   NeoFLObs_Put(prefix,symbol,magic,"EQUITY",eq);
   NeoFLObs_Put(prefix,symbol,magic,"BALANCE",bal);
   NeoFLObs_Put(prefix,symbol,magic,"DD_PCT",account_dd);
   NeoFLObs_Put(prefix,symbol,magic,"POSITION_LOSS_PCT",position_loss_pct);
   NeoFLObs_Put(prefix,symbol,magic,"FREE_MARGIN",AccountInfoDouble(ACCOUNT_MARGIN_FREE));
   NeoFLObs_Put(prefix,symbol,magic,"MARGIN_USED",AccountInfoDouble(ACCOUNT_MARGIN));
   NeoFLObs_Put(prefix,symbol,magic,"MARGIN_PCT",
               eq>0.0?100.0*AccountInfoDouble(ACCOUNT_MARGIN)/eq:100.0);
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

void NeoFLObs_RecoveryCoverage(const string prefix,const string symbol,const ulong magic)
{
   ulong ticket=0;
   double loss=0.0;
   if(NeoFLObs_MainPosition(symbol,magic,ticket))
   {
      double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(p<0.0) loss=-p;
   }

   double maxlot=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_VOLUME_MAX);
   if(maxlot<=0.0) maxlot=10.0;

   double atr=NeoFLObs_ATR(symbol,PERIOD_M3,14);
   double point=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_POINT);
   double tick_size=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_TRADE_TICK_VALUE);
   double distance=MathMax(point,atr);
   double money_one=(tick_size>0.0 && tick_value>0.0?distance/tick_size*tick_value:0.0);
   double required=(money_one>0.0?loss/money_one:0.0);
   double coverage=(required>0.0?MathMin(100.0,maxlot/required*100.0):100.0);

   NeoFLObs_Put(prefix,symbol,magic,"RECOVERY_LOSS",loss);
   NeoFLObs_Put(prefix,symbol,magic,"RECOVERY_REQUIRED_LOTS",required);
   NeoFLObs_Put(prefix,symbol,magic,"RECOVERY_MAX_LOTS",maxlot);
   NeoFLObs_Put(prefix,symbol,magic,"RECOVERY_COVERAGE",coverage);
}

void NeoFLObs_StraddleState(const string prefix,const string symbol,const ulong magic,
                            const double activation_dd_pct,const double activation_atr,
                            const double hard_dd_pct,const int grace_m3_bars,
                            const double recovery_dd_pct,const double projection_atr,
                            const double profit_buffer,const double safety_factor,
                            const double straddle_max_lot,const double exit_tolerance)
{
   ulong main_ticket=0;
   if(!NeoFLObs_MainPosition(symbol,magic,main_ticket))
   {
      NeoFLObs_ResetPositionState(prefix,symbol,magic);
      return;
   }

   bool main_buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double main_entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double main_profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   double bid=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_BID);
   double ask=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_ASK);
   double current=main_buy?bid:ask;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double position_loss_pct=(main_profit<0.0 && eq>0.0)?(-main_profit/eq*100.0):0.0;

   double atr3=NeoFLObs_ATR(symbol,PERIOD_M3,14);
   double adverse_distance=MathAbs(current-main_entry);
   bool adverse_distance_trigger=(atr3>0.0 && adverse_distance>=atr3*activation_atr);
   bool dd_trigger=(position_loss_pct>=activation_dd_pct);

   static int state=0; // 0 silent, 1 watch, 2 active, 3 grace, 4 terminate
   static int grace_left=0;
   static datetime last_m3=0;
   static bool armed_once=false;

   bool m3_new=false;
   datetime m3bar=iTime(NeoFLObs_Sym(symbol),PERIOD_M3,0);
   if(m3bar!=0 && m3bar!=last_m3)
   {
      last_m3=m3bar;
      m3_new=true;
   }

   if(state==0 && (dd_trigger || adverse_distance_trigger))
      state=2;

   // M3 confirmation: use only CLOSED M3 candles.
   MqlRates r[];
   ArraySetAsSeries(r,true);
   ArrayResize(r,4);
   bool m3_adverse=false;
   int adverse_count=0;
   if(CopyRates(NeoFLObs_Sym(symbol),PERIOD_M3,0,4,r)>=4)
   {
      for(int i=1;i<=2;i++)
      {
         bool bull=(r[i].close>r[i].open);
         bool bear=(r[i].close<r[i].open);
         if((main_buy && bear)||(!main_buy && bull))
            adverse_count++;
      }
      m3_adverse=(adverse_count>=2);
   }

   ulong str_ticket=0;
   bool has_straddle=NeoFLObs_StraddlePosition(symbol,magic,str_ticket);

   // Arm the opposite straddle only after activation AND M3 adverse confirmation.
   double required_lots=0.0;
   double projected_move=MathMax(adverse_distance,atr3*projection_atr);
   if(projected_move<=0.0) projected_move=adverse_distance;

   if(state>=2 && !has_straddle && m3_adverse && main_profit<0.0)
   {
      bool straddle_buy=!main_buy;
      double target=straddle_buy?current+projected_move:current-projected_move;
      double one_lot_profit=NeoFLObs_MoneyPerLotMove(symbol,straddle_buy,current,target);
      if(one_lot_profit>0.0)
         required_lots=(-main_profit+profit_buffer)/one_lot_profit*safety_factor;

      double broker_max=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_VOLUME_MAX);
      double cap=MathMin(broker_max,straddle_max_lot);
      if(cap<=0.0) cap=10.0;

      double step=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_VOLUME_STEP);
      if(step<=0.0) step=SymbolInfoDouble(NeoFLObs_Sym(symbol),SYMBOL_VOLUME_MIN);
      double executable=MathMin(required_lots,cap);
      if(step>0.0) executable=MathFloor(executable/step+1e-9)*step;

      double coverage=(required_lots>0.0?MathMin(100.0,executable/required_lots*100.0):100.0);

      NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_REQUIRED_LOTS",required_lots);
      NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_LOTS",executable);
      NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_COVERAGE",coverage);
      NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_START",current);

      if(executable>0.0)
      {
         NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_ARM",1);
         armed_once=true;
      }
   }

   if(has_straddle)
   {
      double str_profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      double main_loss=main_profit;
      double basket=main_loss+str_profit;

      NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_ACTIVE_PNL",str_profit);
      NeoFLObs_Put(prefix,symbol,magic,"BASKET_PNL",basket);

      // If main trade is recovering and basket is at/near BE, close the straddle
      // and let the original thesis continue.
      bool main_recovering=(position_loss_pct<=recovery_dd_pct);
      if(main_recovering && basket>=-exit_tolerance)
      {
         NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_EXIT",1);
         state=2;
      }

      // Hard DD reached: enter grace period. No automatic loss closure yet.
      if(position_loss_pct>=hard_dd_pct)
      {
         if(state<3)
         {
            state=3;
            grace_left=grace_m3_bars;
         }
      }

      if(state==3 && m3_new)
      {
         bool recovery_direction=main_recovering;
         if(recovery_direction)
         {
            if(basket>=-exit_tolerance)
               NeoFLObs_Put(prefix,symbol,magic,"STRADDLE_EXIT",1);
         }
         else
         {
            grace_left--;
            if(grace_left<=0)
            {
               // Final objective: terminate only if the basket is already
               // approximately flat/profitable; otherwise remain protected.
               if(basket>=-exit_tolerance)
               {
                  NeoFLObs_Put(prefix,symbol,magic,"BASKET_TERMINATE",1);
                  state=4;
               }
               else
               {
                  // Do not panic-close a losing basket. Stay active and keep
                  // observing for recovery.
                  state=2;
               }
            }
         }
      }
   }

   NeoFLObs_Put(prefix,symbol,magic,"RISK_STATE",state);
   NeoFLObs_Put(prefix,symbol,magic,"POSITION_LOSS_PCT",position_loss_pct);
   NeoFLObs_Put(prefix,symbol,magic,"M3_ADVERSE",m3_adverse?1:0);
   NeoFLObs_Put(prefix,symbol,magic,"GRACE_BARS_LEFT",grace_left);
}

void NeoFLObs_Update(const string prefix,const string symbol,const ulong magic,
                     const double activation_dd_pct,const double activation_atr,
                     const double hard_dd_pct,const int grace_m3_bars,
                     const double recovery_dd_pct,const double projection_atr,
                     const double profit_buffer,const double safety_factor,
                     const double straddle_max_lot,const double exit_tolerance,
                     const int probability_trades)
{
   NeoFLObs_Put(prefix,symbol,magic,"HEARTBEAT",(double)TimeCurrent());

   double mfe=0.0,mae=0.0,loss_pct=0.0;
   NeoFLObs_M1SilentMeasure(prefix,symbol,magic,mfe,mae);
   NeoFLObs_Drawdown(prefix,symbol,magic,loss_pct);
   NeoFLObs_RecoveryCoverage(prefix,symbol,magic);
   NeoFLObs_Probability(prefix,symbol,magic,probability_trades);

   NeoFLObs_StraddleState(prefix,symbol,magic,
                          activation_dd_pct,activation_atr,
                          hard_dd_pct,grace_m3_bars,
                          recovery_dd_pct,projection_atr,
                          profit_buffer,safety_factor,
                          straddle_max_lot,exit_tolerance);
}
#endif
