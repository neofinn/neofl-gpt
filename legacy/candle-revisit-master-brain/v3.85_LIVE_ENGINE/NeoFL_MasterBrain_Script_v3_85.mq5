//+------------------------------------------------------------------+
//| NeoFL Master Brain Script v3.85 - LIVE                          |
//| Continuous observation/data authority. NO trade execution.       |
//+------------------------------------------------------------------+
#property strict
#property version "3.85"
#property description "NeoFL live Master Brain: M1 observer, M3 straddle, basket protection, DD/recovery and risk state. No execution."

#include "NeoFL_MasterBrain_v3_85.mqh"

input string InpSymbol="";
input ulong  InpMagic=26081401;
input int    InpLoopSeconds=1;
input string InpObserverPrefix="NEOFL_OBS";

input double InpObserverActivationDDPct=2.0;
input double InpObserverActivationATR=2.0;
input double InpObserverHardDDPct=5.0;
input int    InpObserverGraceM3Bars=3;
input double InpObserverRecoveryDDPct=0.50;
input double InpStraddleProjectionATR=1.0;
input double InpStraddleTPFactor=1.00;
input double InpStraddleProfitBufferMoney=1.00;
input double InpStraddleSafetyFactor=1.10;
input double InpStraddleMaxLot=10.0;
input double InpStraddleExitToleranceMoney=0.50;
input double InpDesiredBasketProfitMoney=1.00;
input double InpBasketProfitLockMoney=1.00;
input double InpEmergencyBasketLossPct=5.0;
input int    InpObserverProbabilityTrades=100;
input bool   InpUseCalendar=true;
input string InpCalendarCurrency="USD";
input int    InpCalendarBeforeMin=240;
input int    InpCalendarAfterMin=30;
input ENUM_CALENDAR_EVENT_IMPORTANCE InpCalendarMinImportance=CALENDAR_IMPORTANCE_HIGH;

string Sym(){return InpSymbol==""?_Symbol:InpSymbol;}

void OnStart()
{
   NeoFLMBConfig c;
   c.activation_dd_pct=InpObserverActivationDDPct;
   c.activation_atr=InpObserverActivationATR;
   c.hard_dd_pct=InpObserverHardDDPct;
   c.grace_m3_bars=InpObserverGraceM3Bars;
   c.recovery_dd_pct=InpObserverRecoveryDDPct;
   c.projection_atr=InpStraddleProjectionATR;
   c.tp_factor=InpStraddleTPFactor;
   c.profit_buffer_money=InpStraddleProfitBufferMoney;
   c.safety_factor=InpStraddleSafetyFactor;
   c.max_straddle_lot=InpStraddleMaxLot;
   c.exit_tolerance_money=InpStraddleExitToleranceMoney;
   c.desired_basket_profit=InpDesiredBasketProfitMoney;
   c.profit_lock_money=InpBasketProfitLockMoney;
   c.emergency_basket_loss_pct=InpEmergencyBasketLossPct;
   c.probability_trades=InpObserverProbabilityTrades;

   while(!IsStopped())
   {
      NeoFLMB_Update(InpObserverPrefix,Sym(),InpMagic,c);
      if(InpUseCalendar)
         NeoFLMB_CalendarHighImpactNear(Sym(),InpCalendarCurrency,InpCalendarBeforeMin,InpCalendarAfterMin,InpCalendarMinImportance);
      Sleep(MathMax(250,InpLoopSeconds*1000));
   }
}
