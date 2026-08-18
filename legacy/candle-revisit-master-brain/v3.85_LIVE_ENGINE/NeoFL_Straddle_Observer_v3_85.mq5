//+------------------------------------------------------------------+
//| NeoFL_Straddle_Observer_v3_85.mq5                                |
//| Continuous LIVE basket observer - NO TRADE EXECUTION             |
//| Publishes a latched close command for the execution EA.          |
//+------------------------------------------------------------------+
#property strict
#property version   "3.85"
#property description "NeoFL Straddle Observer: latches basket BE/profit and protects realized basket gains."

input ulong  InpMagic                    = 26081401;
input string InpStraddleCommentKeyword   = "NEOFL STRADDLE";
input int    InpPollMilliseconds         = 250;
input double InpBasketProfitBuffer       = 0.00;
input double InpBasketProfitTarget       = 0.00;
input bool   InpProtectPeakBasket        = true;
input bool   InpCloseIfMainGoneAtBE      = true;
input bool   InpIncludeSwapCommission    = true;
input bool   InpResetWhenNoStraddle      = true;
input bool   InpVerboseLog               = true;

string GV_PREFIX;

string GV(const string suffix)
{
   return GV_PREFIX + suffix;
}

double PositionNetProfit(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0.0;
   double p=PositionGetDouble(POSITION_PROFIT);
   if(InpIncludeSwapCommission)
      p += PositionGetDouble(POSITION_SWAP);
   return p;
}

bool IsOurPosition(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) return false;
   return true;
}

bool IsStraddlePosition(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) return false;
   string c=PositionGetString(POSITION_COMMENT);
   return (StringFind(c,InpStraddleCommentKeyword)>=0);
}

int CountStraddles()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(IsStraddlePosition(t)) n++;
   }
   return n;
}

int CountMainPositions()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(!IsOurPosition(t)) continue;
      if(!IsStraddlePosition(t)) n++;
   }
   return n;
}

// Sum net closed P/L for this magic after the saved cycle baseline.
double ClosedDelta(const datetime from_time)
{
   if(!HistorySelect(from_time,TimeCurrent()))
      return 0.0;

   double total=0.0;
   int deals=HistoryDealsTotal();
   for(int i=0;i<deals;i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;

      long magic=HistoryDealGetInteger(d,DEAL_MAGIC);
      if((ulong)magic!=InpMagic) continue;

      long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;

      total += HistoryDealGetDouble(d,DEAL_PROFIT);
      total += HistoryDealGetDouble(d,DEAL_SWAP);
      total += HistoryDealGetDouble(d,DEAL_COMMISSION);
   }
   return total;
}

double OpenFloating()
{
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(!IsOurPosition(t)) continue;
      total += PositionNetProfit(t);
   }
   return total;
}

void SetState(const double basket,const double peak,const double target,
              const int main_count,const int straddle_count,const bool close_cmd)
{
   GlobalVariableSet(GV("BASKET_PNL"),basket);
   GlobalVariableSet(GV("PEAK_PNL"),peak);
   GlobalVariableSet(GV("TARGET_PNL"),target);
   GlobalVariableSet(GV("MAIN_COUNT"),main_count);
   GlobalVariableSet(GV("STRADDLE_COUNT"),straddle_count);
   GlobalVariableSet(GV("CLOSE_COMMAND"),close_cmd ? 1.0 : 0.0);
   GlobalVariableSet(GV("HEARTBEAT"),(double)TimeLocal());
}

void Log(const string s)
{
   if(InpVerboseLog) Print("NeoFL Straddle Observer | ",s);
}

void ResetCycle()
{
   GlobalVariableSet(GV("CYCLE_START"),0.0);
   GlobalVariableSet(GV("BASELINE_CLOSED"),0.0);
   GlobalVariableSet(GV("PEAK_PNL"),-DBL_MAX);
   GlobalVariableSet(GV("TARGET_PNL"),InpBasketProfitTarget+InpBasketProfitBuffer);
   GlobalVariableSet(GV("CLOSE_COMMAND"),0.0);
   GlobalVariableSet(GV("BASKET_PNL"),0.0);
   GlobalVariableSet(GV("MAIN_COUNT"),0.0);
   GlobalVariableSet(GV("STRADDLE_COUNT"),0.0);
   GlobalVariableSet(GV("HEARTBEAT"),(double)TimeLocal());
}

void StartCycleIfNeeded()
{
   double start=GlobalVariableGet(GV("CYCLE_START"));
   if(start>0.0) return;

   datetime now=TimeCurrent();
   // Baseline is the closed P/L before this straddle cycle.
   if(!HistorySelect(0,now))
      return;

   double closed_before=0.0;
   int deals=HistoryDealsTotal();
   for(int i=0;i<deals;i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
      long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
      closed_before += HistoryDealGetDouble(d,DEAL_PROFIT);
      closed_before += HistoryDealGetDouble(d,DEAL_SWAP);
      closed_before += HistoryDealGetDouble(d,DEAL_COMMISSION);
   }

   GlobalVariableSet(GV("CYCLE_START"),(double)now);
   GlobalVariableSet(GV("BASELINE_CLOSED"),closed_before);
   GlobalVariableSet(GV("PEAK_PNL"),-DBL_MAX);
   GlobalVariableSet(GV("TARGET_PNL"),InpBasketProfitTarget+InpBasketProfitBuffer);
   GlobalVariableSet(GV("CLOSE_COMMAND"),0.0);
   Log("New straddle cycle baseline captured.");
}

int OnStart()
{
   GV_PREFIX="NEOFL_SB_"+_Symbol+"_"+IntegerToString((int)InpMagic)+"_";
   ResetCycle();

   Log("STARTED. Observation only; EA remains execution authority.");

   while(!IsStopped())
   {
      int sc=CountStraddles();
      int mc=CountMainPositions();

      if(sc==0)
      {
         if(InpResetWhenNoStraddle)
            ResetCycle();
         Sleep(MathMax(50,InpPollMilliseconds));
         continue;
      }

      StartCycleIfNeeded();

      datetime start=(datetime)GlobalVariableGet(GV("CYCLE_START"));
      double baseline=GlobalVariableGet(GV("BASELINE_CLOSED"));
      double closed_now=baseline+ClosedDelta(start);
      double floating=OpenFloating();
      double basket=closed_now-baseline+floating;

      double peak=GlobalVariableGet(GV("PEAK_PNL"));
      if(peak==-DBL_MAX || basket>peak)
         peak=basket;

      double target=GlobalVariableGet(GV("TARGET_PNL"));
      bool already_latched=(GlobalVariableGet(GV("CLOSE_COMMAND"))>0.5);

      // Once basket BE/profit is observed, latch the command.
      // This is deliberately NOT cleared when price retraces.
      if(!already_latched && basket>=target)
      {
         already_latched=true;
         Log(StringFormat("BASKET TARGET REACHED: %.2f >= %.2f. CLOSE LATCHED.",basket,target));
      }

      // If main is already gone, preserve the realized main result and
      // immediately settle the surviving straddle if basket was/ is safe.
      if(InpCloseIfMainGoneAtBE && mc==0 && sc>0)
      {
         if(basket>=target || (InpProtectPeakBasket && peak>=target))
         {
            already_latched=true;
            Log(StringFormat("MAIN GONE + SAFE BASKET. STRADDLE CLOSE LATCHED. Basket=%.2f Peak=%.2f",basket,peak));
         }
      }

      SetState(basket,peak,target,mc,sc,already_latched);

      Sleep(MathMax(50,InpPollMilliseconds));
   }

   Log("STOPPED.");
   return 0;
}
