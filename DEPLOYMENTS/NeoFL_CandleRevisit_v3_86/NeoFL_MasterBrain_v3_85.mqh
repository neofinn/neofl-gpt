//+------------------------------------------------------------------+
//| NeoFL Master Brain v3.85                                        |
//| Decision/data engine ONLY. NO trade execution.                  |
//| Shared by LIVE feeder script and BACKTEST EA.                   |
//+------------------------------------------------------------------+
#ifndef __NEOFL_MASTER_BRAIN_V385_MQH__
#define __NEOFL_MASTER_BRAIN_V385_MQH__

struct NeoFLMBConfig
{
   double activation_dd_pct;
   double activation_atr;
   double hard_dd_pct;
   int    grace_m3_bars;
   double recovery_dd_pct;
   double projection_atr;
   double tp_factor;
   double profit_buffer_money;
   double safety_factor;
   double max_straddle_lot;
   double exit_tolerance_money;
   double desired_basket_profit;
   double profit_lock_money;
   double emergency_basket_loss_pct;
   int    probability_trades;
};

string NeoFLMB_Key(const string prefix,const string symbol,const ulong magic,const string suffix)
{
   return prefix+"_"+symbol+"_"+(string)magic+"_"+suffix;
}

void NeoFLMB_Put(const string prefix,const string symbol,const ulong magic,const string suffix,const double value)
{
   GlobalVariableSet(NeoFLMB_Key(prefix,symbol,magic,suffix),value);
}

double NeoFLMB_Get(const string prefix,const string symbol,const ulong magic,const string suffix,const double fallback=0.0)
{
   string k=NeoFLMB_Key(prefix,symbol,magic,suffix);
   if(!GlobalVariableCheck(k)) return fallback;
   return GlobalVariableGet(k);
}

bool NeoFLMB_IsStraddle(const string comment)
{
   return StringFind(comment,"NEOFL STRADDLE")>=0;
}

bool NeoFLMB_FindMain(const string symbol,const ulong magic,ulong &ticket)
{
   ticket=0;
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      if(NeoFLMB_IsStraddle(PositionGetString(POSITION_COMMENT))) continue;
      ticket=t; return true;
   }
   return false;
}

bool NeoFLMB_FindStraddle(const string symbol,const ulong magic,ulong &ticket)
{
   ticket=0;
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      if(!NeoFLMB_IsStraddle(PositionGetString(POSITION_COMMENT))) continue;
      ticket=t; return true;
   }
   return false;
}

double NeoFLMB_ATR(const string symbol,const ENUM_TIMEFRAMES tf,const int period=14)
{
   int h=iATR(symbol,tf,period);
   if(h==INVALID_HANDLE) return 0.0;
   double b[]; ArraySetAsSeries(b,true);
   double v=0.0;
   if(CopyBuffer(h,0,1,1,b)==1) v=b[0];
   IndicatorRelease(h);
   return v;
}

double NeoFLMB_MoneyPerLot(const string symbol,const ENUM_ORDER_TYPE type,const double from,const double to)
{
   double p=0.0;
   if(!OrderCalcProfit(type,symbol,1.0,from,to,p)) return 0.0;
   return MathAbs(p);
}

double NeoFLMB_RoundUpLots(const string symbol,const double requested,const double cap)
{
   double broker_min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double broker_max=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(broker_min<=0.0) broker_min=0.01;
   if(broker_max<=0.0) broker_max=100.0;
   if(step<=0.0) step=broker_min;
   double hard_cap=MathMin(broker_max,MathMax(broker_min,cap));
   if(requested<=0.0) return 0.0;
   double lots=MathCeil(requested/step-1e-10)*step;
   lots=MathMin(lots,hard_cap);
   if(lots<broker_min) return 0.0;
   return NormalizeDouble(lots,2);
}

bool NeoFLMB_NewM3(const string symbol)
{
   datetime now=iTime(symbol,PERIOD_M3,0);
   double last=NeoFLMB_Get("NEOFL_MB",symbol,0,"LAST_M3",0.0);
   if(now==0 || (double)now==last) return false;
   NeoFLMB_Put("NEOFL_MB",symbol,0,"LAST_M3",(double)now);
   return true;
}

int NeoFLMB_AdverseM3Bars(const string symbol,const bool main_buy)
{
   MqlRates r[]; ArraySetAsSeries(r,true); ArrayResize(r,4);
   if(CopyRates(symbol,PERIOD_M3,0,4,r)<4) return 0;
   int n=0;
   for(int i=1;i<=2;i++)
   {
      bool bull=r[i].close>r[i].open;
      bool bear=r[i].close<r[i].open;
      if((main_buy && bear)||(!main_buy && bull)) n++;
   }
   return n;
}

// Baseline balance is captured when a straddle first appears. It therefore
// includes the realized result of the main trade if that trade later closes.
double NeoFLMB_BasketPnl(const string symbol,const ulong magic,const bool has_straddle)
{
   if(!has_straddle) return 0.0;

   // The basket is the combined economic position.  While the main trade is
   // open, its floating P/L MUST be included.  When the main trade closes,
   // that same result becomes realized balance, so the basket remains
   // continuous instead of artificially jumping to a positive value.
   double base=NeoFLMB_Get("NEOFL_MB",symbol,magic,"BASKET_BASE_BALANCE",0.0);
   if(base<=0.0)
   {
      base=AccountInfoDouble(ACCOUNT_BALANCE);
      NeoFLMB_Put("NEOFL_MB",symbol,magic,"BASKET_BASE_BALANCE",base);
   }

   double realized=AccountInfoDouble(ACCOUNT_BALANCE)-base;
   double floating=0.0;

   ulong main_ticket=0;
   if(NeoFLMB_FindMain(symbol,magic,main_ticket) && PositionSelectByTicket(main_ticket))
   {
      floating += PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      floating -= NeoFLMB_PositionCommission(main_ticket);
   }

   ulong str_ticket=0;
   if(NeoFLMB_FindStraddle(symbol,magic,str_ticket) && PositionSelectByTicket(str_ticket))
   {
      floating += PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      floating -= NeoFLMB_PositionCommission(str_ticket);
   }

   return realized+floating;
}

// Sum the commission already paid for an open position.  Swap is read from
// POSITION_SWAP separately because it changes while the position remains open.
double NeoFLMB_PositionCommission(const ulong ticket)
{
   if(ticket==0 || !PositionSelectByTicket(ticket)) return 0.0;
   ulong position_id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(position_id==0) return 0.0;
   if(!HistorySelectByPosition(position_id)) return 0.0;

   double commission=0.0;
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      commission += MathAbs(HistoryDealGetDouble(d,DEAL_COMMISSION));
   }
   return commission;
}

// Basket P/L at a hypothetical price. This is used to solve the exact
// basket BE/target price rather than assigning an independent TP to the
// straddle leg.
double NeoFLMB_BasketAtPrice(const string symbol,const ulong magic,const double price)
{
   double value=0.0;
   double base=NeoFLMB_Get("NEOFL_MB",symbol,magic,"BASKET_BASE_BALANCE",0.0);
   if(base<=0.0) base=AccountInfoDouble(ACCOUNT_BALANCE);
   value += AccountInfoDouble(ACCOUNT_BALANCE)-base;

   ulong mt=0;
   if(NeoFLMB_FindMain(symbol,magic,mt) && PositionSelectByTicket(mt))
   {
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE ot=(pt==POSITION_TYPE_BUY)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      double lot=PositionGetDouble(POSITION_VOLUME);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double p=0.0;
      if(OrderCalcProfit(ot,symbol,lot,open,price,p)) value += p;
      value += PositionGetDouble(POSITION_SWAP);
      value -= NeoFLMB_PositionCommission(mt);
   }

   ulong st=0;
   if(NeoFLMB_FindStraddle(symbol,magic,st) && PositionSelectByTicket(st))
   {
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE ot=(pt==POSITION_TYPE_BUY)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      double lot=PositionGetDouble(POSITION_VOLUME);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double p=0.0;
      if(OrderCalcProfit(ot,symbol,lot,open,price,p)) value += p;
      value += PositionGetDouble(POSITION_SWAP);
      value -= NeoFLMB_PositionCommission(st);
   }
   return value;
}

// Solve for the price at which the combined basket reaches a money target.
// The search is performed in the direction that benefits the straddle.
bool NeoFLMB_SolveBasketPrice(const string symbol,const ulong magic,const double from_price,
                              const double direction,const double target_money,double &result)
{
   result=0.0;
   if(from_price<=0.0 || direction==0.0) return false;
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(point<=0.0) point=0.00001;

   double lo=from_price;
   double hi=from_price;
   double step=MathMax(point,NeoFLMB_ATR(symbol,PERIOD_M3,14)*0.25);
   if(step<=0.0) step=point*100.0;

   // Expand until the requested basket target is bracketed, or until the
   // search reaches a deliberately generous price range.
   bool bracket=false;
   for(int i=0;i<60;i++)
   {
      hi=from_price+direction*step*MathPow(1.35,i);
      double v=NeoFLMB_BasketAtPrice(symbol,magic,hi);
      if((direction>0.0 && v>=target_money) || (direction<0.0 && v>=target_money))
      {
         bracket=true; break;
      }
   }
   if(!bracket) return false;

   // Bisection. The basket is monotonic in the straddle's favorable direction
   // when the straddle volume is larger than the main exposure, which is the
   // intended coverage configuration.
   lo=from_price;
   for(int i=0;i<50;i++)
   {
      double mid=(lo+hi)/2.0;
      double v=NeoFLMB_BasketAtPrice(symbol,magic,mid);
      if(v>=target_money) hi=mid;
      else lo=mid;
   }
   result=NormalizeDouble(hi,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
   return true;
}

void NeoFLMB_ResetCommands(const string prefix,const string symbol,const ulong magic)
{
   NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_ARM",0);
   NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_EXIT",0);
   NeoFLMB_Put(prefix,symbol,magic,"BASKET_TERMINATE",0);
   NeoFLMB_Put(prefix,symbol,magic,"BASKET_EMERGENCY",0);
}


void NeoFLMB_UpdateAccountMetrics(const string prefix,const string symbol,const ulong magic)
{
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double dd=(bal>0.0)?MathMax(0.0,(bal-eq)/bal*100.0):0.0;

   NeoFLMB_Put(prefix,symbol,magic,"BALANCE",bal);
   NeoFLMB_Put(prefix,symbol,magic,"EQUITY",eq);
   NeoFLMB_Put(prefix,symbol,magic,"MARGIN",margin);
   NeoFLMB_Put(prefix,symbol,magic,"FREE_MARGIN",free);
   NeoFLMB_Put(prefix,symbol,magic,"ACCOUNT_DD_PCT",dd);

   double realized=0.0;
   if(HistorySelect(0,TimeCurrent()))
   {
      int n=HistoryDealsTotal();
      for(int i=0;i<n;i++)
      {
         ulong d=HistoryDealGetTicket(i);
         if(d==0) continue;
         if(HistoryDealGetString(d,DEAL_SYMBOL)!=symbol) continue;
         if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=magic) continue;
         ENUM_DEAL_TYPE t=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE);
         if(t==DEAL_TYPE_BUY || t==DEAL_TYPE_SELL)
            realized += HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_COMMISSION);
      }
   }
   NeoFLMB_Put(prefix,symbol,magic,"REALIZED_PROFIT",realized);

   double reserve=eq*0.20;
   double safe=MathMax(0.0,bal-margin-reserve);
   NeoFLMB_Put(prefix,symbol,magic,"SAFE_TO_WITHDRAW",safe);
}

bool NeoFLMB_CalendarHighImpactNear(const string symbol,const string currency,const int before_min,const int after_min,const ENUM_CALENDAR_EVENT_IMPORTANCE min_importance)
{
   datetime now=TimeCurrent();
   MqlCalendarValue values[];
   ResetLastError();
   int count=CalendarValueHistory(values,now-after_min*60,now+before_min*60,NULL,currency);
   if(count<0)
   {
      NeoFLMB_Put("NEOFL_CAL",symbol,0,"LOCK",1);
      return true;
   }
   for(int i=0;i<count;i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id,ev)) continue;
      if(ev.importance<min_importance) continue;
      if(ev.time_mode!=CALENDAR_TIMEMODE_DATETIME) continue;
      NeoFLMB_Put("NEOFL_CAL",symbol,0,"EVENT_TIME",(double)values[i].time);
      NeoFLMB_Put("NEOFL_CAL",symbol,0,"LOCK",1);
      return true;
   }
   NeoFLMB_Put("NEOFL_CAL",symbol,0,"LOCK",0);
   return false;
}

void NeoFLMB_Update(const string prefix,const string symbol,const ulong magic,const NeoFLMBConfig &cfg)
{
   NeoFLMB_Put(prefix,symbol,magic,"HEARTBEAT",(double)TimeCurrent());
   NeoFLMB_UpdateAccountMetrics(prefix,symbol,magic);
   NeoFLMB_Put(prefix,symbol,magic,"DESIRED_BASKET_PROFIT",cfg.desired_basket_profit);
   NeoFLMB_Put(prefix,symbol,magic,"TP_FACTOR",cfg.tp_factor);
   NeoFLMB_ResetCommands(prefix,symbol,magic);

   ulong main_ticket=0, str_ticket=0;
   bool has_main=NeoFLMB_FindMain(symbol,magic,main_ticket);
   bool has_str=NeoFLMB_FindStraddle(symbol,magic,str_ticket);
   bool new_m3=NeoFLMB_NewM3(symbol);

   // State is persisted in the global-variable bus so the live script and
   // tester EA use the same state machine semantics.
   int state=(int)NeoFLMB_Get(prefix,symbol,magic,"RISK_STATE",0.0);
   int grace=(int)NeoFLMB_Get(prefix,symbol,magic,"GRACE_BARS_LEFT",0.0);

   if(!has_main && !has_str)
   {
      NeoFLMB_Put(prefix,symbol,magic,"M1_STATE",0);
      NeoFLMB_Put(prefix,symbol,magic,"RISK_STATE",0);
      NeoFLMB_Put(prefix,symbol,magic,"BASKET_PNL",0);
      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_ACTIVE_PNL",0);
      return;
   }

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double atr3=NeoFLMB_ATR(symbol,PERIOD_M3,14);

   // ---------------- Straddle lifecycle ----------------
   if(has_str)
   {
      if(!PositionSelectByTicket(str_ticket)) return;
      bool str_buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double str_pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP)+0.0;
      double basket=NeoFLMB_BasketPnl(symbol,magic,true);
      double base=NeoFLMB_Get("NEOFL_MB",symbol,magic,"BASKET_BASE_BALANCE",AccountInfoDouble(ACCOUNT_BALANCE));

      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_ACTIVE_PNL",str_pnl);
      NeoFLMB_Put(prefix,symbol,magic,"BASKET_PNL",basket);
      NeoFLMB_Put(prefix,symbol,magic,"BASKET_BASE_BALANCE",base);

      // If the main is already gone, the straddle becomes a residual leg.
      // Its realized main result is included through the balance baseline.
      if(!has_main)
      {
         // A residual straddle may close ONLY when the WHOLE basket reaches
         // the configured target. Its own profit is never an exit authority.
         if(basket>=cfg.desired_basket_profit-cfg.exit_tolerance_money)
            NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_EXIT",1);
      }

      double emergency=MathMax(cfg.exit_tolerance_money,
                               equity*MathMax(0.1,cfg.emergency_basket_loss_pct)/100.0);
      NeoFLMB_Put(prefix,symbol,magic,"BASKET_EMERGENCY_LOSS",emergency);

      if(basket<=-emergency)
      {
         NeoFLMB_Put(prefix,symbol,magic,"BASKET_EMERGENCY",1);
         NeoFLMB_Put(prefix,symbol,magic,"BASKET_TERMINATE",1);
      }

      if(has_main && PositionSelectByTicket(main_ticket))
      {
         double main_profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP)+0.0;
         bool recovering=(main_profit>=0.0 || (equity>0.0 && (-main_profit/equity*100.0)<=cfg.recovery_dd_pct));
         if(recovering && basket>=cfg.desired_basket_profit-cfg.exit_tolerance_money)
            NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_EXIT",1);

         if(cfg.hard_dd_pct>0.0 && equity>0.0 && main_profit<0.0 && (-main_profit/equity*100.0)>=cfg.hard_dd_pct)
         {
            if(state<3)
            {
               state=3;
               grace=cfg.grace_m3_bars;
            }
         }

         if(state==3 && new_m3)
         {
            if(grace>0) grace--;
            if(basket>=-cfg.exit_tolerance_money)
               NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_EXIT",1);
            else if(grace<=0 && basket>=cfg.desired_basket_profit-cfg.exit_tolerance_money)
               NeoFLMB_Put(prefix,symbol,magic,"BASKET_TERMINATE",1);
         }
      }

      NeoFLMB_Put(prefix,symbol,magic,"RISK_STATE",state);
      NeoFLMB_Put(prefix,symbol,magic,"GRACE_BARS_LEFT",grace);
      return;
   }

   // No straddle: clear its baseline so the next straddle starts a new basket.
   NeoFLMB_Put("NEOFL_MB",symbol,magic,"BASKET_BASE_BALANCE",0.0);

   if(!has_main) return;
   if(!PositionSelectByTicket(main_ticket)) return;

   bool main_buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double main_profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP)+0.0;
   double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
   double current=main_buy?bid:ask;
   double adverse=MathAbs(current-entry);
   double loss_pct=(main_profit<0.0 && equity>0.0)?(-main_profit/equity*100.0):0.0;
   bool dd_trigger=loss_pct>=cfg.activation_dd_pct;
   bool distance_trigger=(atr3>0.0 && adverse>=atr3*cfg.activation_atr);
   if(state==0 && (dd_trigger||distance_trigger)) state=2;

   int adverse_bars=NeoFLMB_AdverseM3Bars(symbol,main_buy);
   bool m3_adverse=adverse_bars>=2;

   NeoFLMB_Put(prefix,symbol,magic,"POSITION_LOSS_PCT",loss_pct);
   NeoFLMB_Put(prefix,symbol,magic,"M3_ADVERSE",m3_adverse?1:0);
   NeoFLMB_Put(prefix,symbol,magic,"DD_PCT",loss_pct);
   NeoFLMB_Put(prefix,symbol,magic,"M1_STATE",state);

   if(state>=2 && main_profit<0.0 && m3_adverse)
   {
      bool str_buy=!main_buy;
      ENUM_ORDER_TYPE str_ot=str_buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;

      // The coverage distance is the actual entry gap back to the main entry,
      // not an arbitrary ATR projection.  This is the amount of adverse price
      // travel the straddle must cover to neutralize the main floating loss.
      double entry_gap=MathAbs(entry-current);
      if(entry_gap<=0.0) entry_gap=SymbolInfoDouble(symbol,SYMBOL_POINT);

      double commission_main=NeoFLMB_PositionCommission(main_ticket);
      double raw_profit=PositionGetDouble(POSITION_PROFIT);
      double swap_cost=MathAbs(PositionGetDouble(POSITION_SWAP));
      double recovery_cost=commission_main+swap_cost;
      double required_money=MathAbs(raw_profit)+recovery_cost+cfg.profit_buffer_money;
      required_money*=MathMax(1.0,cfg.safety_factor);

      // Ask MT5 how much one lot of the straddle earns over the ACTUAL gap
      // from straddle entry back to the main entry.  This directly answers:
      // "how many lots are required to cover the negative floating loss?"
      double one_lot_gap=NeoFLMB_MoneyPerLot(symbol,str_ot,current,entry);
      double required=(one_lot_gap>0.0)?(required_money/one_lot_gap):0.0;
      double lots=NeoFLMB_RoundUpLots(symbol,required,cfg.max_straddle_lot);
      double coverage_money=(one_lot_gap>0.0)?(lots*one_lot_gap):0.0;
      double coverage=(required_money>0.0)?MathMin(9999.0,coverage_money/required_money*100.0):100.0;

      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_REQUIRED_MONEY",required_money);
      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_GAP_PRICE",entry_gap);
      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_GAP_MONEY_PER_LOT",one_lot_gap);
      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_REQUIRED_LOTS",required);
      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_LOTS",lots);
      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_COVERAGE",coverage);
      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_START",current);
      NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_MAIN_ENTRY",entry);

      // The BE reference is the ACTUAL main-entry gap.  The calculated lot
      // is deliberately rounded UP so the straddle can cover the main loss
      // when price traverses this gap.  We then calculate the small extra
      // distance required for the desired basket profit from the combined
      // net exposure.
      if(lots>0.0)
      {
         double favorable=str_buy?1.0:-1.0;
         double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
         if(point<=0.0) point=0.00001;

         ENUM_ORDER_TYPE main_ot=main_buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
         double main_lot=PositionGetDouble(POSITION_VOLUME);
         double main_step=NeoFLMB_MoneyPerLot(symbol,main_ot,current,current+favorable*point)*main_lot;
         double str_step=NeoFLMB_MoneyPerLot(symbol,str_ot,current,current+favorable*point)*lots;
         double net_step=MathMax(0.0,str_step-main_step);

         double be_price=entry;
         double extra_distance=0.0;
         if(net_step>0.0 && cfg.desired_basket_profit>0.0)
            extra_distance=(cfg.desired_basket_profit/net_step)*point*MathMax(1.0,cfg.tp_factor);

         double target_price=entry+favorable*extra_distance;
         NeoFLMB_Put(prefix,symbol,magic,"BASKET_BE_PRICE",be_price);
         NeoFLMB_Put(prefix,symbol,magic,"BASKET_TARGET_PRICE",target_price);
         NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_BE_DISTANCE",entry_gap);
         NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_TARGET_DISTANCE",MathAbs(target_price-current));
         NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_TP_PRICE",target_price);
         NeoFLMB_Put(prefix,symbol,magic,"STRADDLE_ARM",1);
      }
   }

   NeoFLMB_Put(prefix,symbol,magic,"RISK_STATE",state);
   NeoFLMB_Put(prefix,symbol,magic,"GRACE_BARS_LEFT",grace);
}

#endif
