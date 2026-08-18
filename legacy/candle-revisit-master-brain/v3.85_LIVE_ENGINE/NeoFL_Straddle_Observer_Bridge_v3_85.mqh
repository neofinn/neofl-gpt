//+------------------------------------------------------------------+
//| NeoFL_Straddle_Observer_Bridge_v3_85.mqh                         |
//| Include in the EXECUTION EA.                                     |
//| The EA is the only component allowed to trade.                   |
//+------------------------------------------------------------------+
#pragma once
#include <Trade/Trade.mqh>

bool NeoFL_StraddleObserver_CloseCommand(const ulong magic)
{
   string prefix="NEOFL_SB_"+_Symbol+"_"+IntegerToString((int)magic)+"_";
   return (GlobalVariableCheck(prefix+"CLOSE_COMMAND") &&
           GlobalVariableGet(prefix+"CLOSE_COMMAND")>0.5);
}

double NeoFL_StraddleObserver_BasketPNL(const ulong magic)
{
   string prefix="NEOFL_SB_"+_Symbol+"_"+IntegerToString((int)magic)+"_";
   if(!GlobalVariableCheck(prefix+"BASKET_PNL")) return 0.0;
   return GlobalVariableGet(prefix+"BASKET_PNL");
}

double NeoFL_StraddleObserver_PeakPNL(const ulong magic)
{
   string prefix="NEOFL_SB_"+_Symbol+"_"+IntegerToString((int)magic)+"_";
   if(!GlobalVariableCheck(prefix+"PEAK_PNL")) return 0.0;
   return GlobalVariableGet(prefix+"PEAK_PNL");
}

bool NeoFL_StraddleObserver_CloseStraddles(CTrade &trade,const ulong magic,
                                            const string keyword="NEOFL STRADDLE")
{
   bool any=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      if(StringFind(comment,keyword)<0) continue;

      any=true;
      if(!trade.PositionClose(ticket))
      {
         Print("NeoFL Observer Bridge: failed to close straddle ticket ",
               ticket," retcode=",trade.ResultRetcode());
      }
   }
   return any;
}

// Call this early on every EA tick BEFORE opening new exposure.
// It consumes a latched observer command only after all straddles are gone.
void NeoFL_StraddleObserver_Process(CTrade &trade,const ulong magic)
{
   if(!NeoFL_StraddleObserver_CloseCommand(magic))
      return;

   NeoFL_StraddleObserver_CloseStraddles(trade,magic);

   string prefix="NEOFL_SB_"+_Symbol+"_"+IntegerToString((int)magic)+"_";
   bool still_open=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT),"NEOFL STRADDLE")>=0)
      {
         still_open=true;
         break;
      }
   }

   if(!still_open)
      GlobalVariableSet(prefix+"CLOSE_COMMAND",0.0);
}
