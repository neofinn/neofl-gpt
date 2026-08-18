//+------------------------------------------------------------------+
//| NeoFL Observer Network v1.20 - Institutional Risk Observer       |
//| SCRIPT: continuous observation only; NEVER executes trades.      |
//| M1 observation + account risk/fund monitoring.                  |
//| Execution remains in the main NeoFL EA.                         |
//+------------------------------------------------------------------+
#property strict
#property version "1.20"
#property description "Continuous M1 observer plus account drawdown, realized P/L, win/loss probability and safe-withdrawal monitor. NEVER trades."

#include "NeoFL_Observer_Core.mqh"

input string InpSymbol="";
input ulong  InpMagic=26081401;
input string InpObserverPrefix="NEOFL_OBS";
input int    InpLoopSeconds=1;
input int    InpProbabilityTrades=100;
input int    InpM1ConfirmBars=2;
input double InpProfitArmMoney=1.00;
input double InpM1RetraceFromMFEPct=35.0;
input double InpM1ATRReversalMult=0.35;

input double InpSafetyReservePct=20.0;
input double InpAccountDDWarnPct=8.0;
input double InpAccountDDHardStopPct=15.0;
input double InpCapitalBase=0.0; // 0 = lock first-run account balance

string Key(const string name)
{
   return InpObserverPrefix+"_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+name;
}

void SetMetric(const string name,const double value)
{
   GlobalVariableSet(Key(name),value);
}

double GetMetric(const string name,const double def=0.0)
{
   string k=Key(name);
   if(GlobalVariableCheck(k)) return GlobalVariableGet(k);
   return def;
}

string CapitalKey()
{
   return "NEOFL_CAPITAL_BASE_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+(_Symbol)+"_"+(string)InpMagic;
}

double LoadCapitalBase()
{
   if(InpCapitalBase>0.0)
   {
      GlobalVariableSet(CapitalKey(),InpCapitalBase);
      return InpCapitalBase;
   }
   string k=CapitalKey();
   if(GlobalVariableCheck(k)) return GlobalVariableGet(k);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   GlobalVariableSet(k,bal);
   return bal;
}

double FloatingLossAccount()
{
   double loss=0.0;
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(p<0.0) loss+=-p;
   }
   return loss;
}

double RealizedProfitForMagic()
{
   if(!HistorySelect(0,TimeCurrent())) return 0.0;
   double total=0.0;
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      total+=HistoryDealGetDouble(deal,DEAL_PROFIT);
      total+=HistoryDealGetDouble(deal,DEAL_SWAP);
      total+=HistoryDealGetDouble(deal,DEAL_COMMISSION);
   }
   return total;
}

void WinLossProbability(double &winProb,double &lossProb,int &wins,int &losses)
{
   wins=0; losses=0;
   if(!HistorySelect(0,TimeCurrent()))
   {
      winProb=0.0; lossProb=0.0; return;
   }
   int n=HistoryDealsTotal();
   for(int i=0;i<n;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      double pnl=HistoryDealGetDouble(deal,DEAL_PROFIT)
                +HistoryDealGetDouble(deal,DEAL_SWAP)
                +HistoryDealGetDouble(deal,DEAL_COMMISSION);
      if(pnl>0.0) wins++;
      else if(pnl<0.0) losses++;
   }
   int total=wins+losses;
   winProb=(total>0 ? 100.0*wins/total : 0.0);
   lossProb=(total>0 ? 100.0*losses/total : 0.0);
}

void UpdateAccountMetrics()
{
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double floatingLoss=FloatingLossAccount();
   if(eq<=0.0) return;

   string peakKey=Key("PEAK_EQUITY");
   double peak=GlobalVariableCheck(peakKey)?GlobalVariableGet(peakKey):eq;
   if(eq>peak) peak=eq;
   GlobalVariableSet(peakKey,peak);

   double dd=(peak>0.0?100.0*(peak-eq)/peak:0.0);
   dd=MathMax(0.0,dd);
   double maxDD=GetMetric("MAX_DD_PCT",0.0);
   maxDD=MathMax(maxDD,dd);

   double capital=LoadCapitalBase();
   double reserve=eq*MathMax(0.0,MathMin(100.0,InpSafetyReservePct))/100.0;
   double safe=MathMax(0.0,bal-capital-margin-floatingLoss-reserve);
   bool safeNow=(safe>0.0 && PositionsTotal()==0);

   double winProb=0.0,lossProb=0.0;
   int wins=0,losses=0;
   WinLossProbability(winProb,lossProb,wins,losses);

   int riskState=0; // 0 green, 1 amber, 2 red
   if(dd>=InpAccountDDHardStopPct) riskState=2;
   else if(dd>=InpAccountDDWarnPct) riskState=1;

   SetMetric("BALANCE",bal);
   SetMetric("EQUITY",eq);
   SetMetric("PEAK_EQUITY",peak);
   SetMetric("DD_PCT",dd);
   SetMetric("MAX_DD_PCT",maxDD);
   SetMetric("REALIZED_PROFIT",RealizedProfitForMagic());
   SetMetric("FLOATING_LOSS",floatingLoss);
   SetMetric("MARGIN_USED",margin);
   SetMetric("SAFE_WITHDRAWAL",safe);
   SetMetric("WITHDRAWAL_SAFE",safeNow?1.0:0.0);
   SetMetric("WIN_PROB",winProb);
   SetMetric("LOSS_PROB",lossProb);
   SetMetric("WIN_COUNT",wins);
   SetMetric("LOSS_COUNT",losses);
   SetMetric("RISK_STATE",riskState);
   SetMetric("HEARTBEAT",(double)TimeCurrent());
}

void OnStart()
{
   string sym=(InpSymbol==""?_Symbol:InpSymbol);
   Print("NeoFL Institutional Observer v1.20 started for ",sym," magic ",InpMagic);
   while(!IsStopped())
   {
      // M1 observer: it never places, modifies, or closes an order.
      NeoFLObs_Update(InpObserverPrefix,sym,InpMagic,
                      InpM1ConfirmBars,InpProfitArmMoney,
                      InpM1RetraceFromMFEPct,InpM1ATRReversalMult,
                      InpProbabilityTrades);

      // Account/fund observation is continuous and independent of trade execution.
      UpdateAccountMetrics();
      Sleep(MathMax(1,InpLoopSeconds)*1000);
   }
   Print("NeoFL Institutional Observer v1.20 stopped.");
}
