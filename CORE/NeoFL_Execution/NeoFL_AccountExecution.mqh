#pragma once
#include <Trade/Trade.mqh>

// Account-wide execution boundary for NeoFL MT5 Body.
// The EA host chart is never used as an execution-symbol fallback.
class CNeoFLAccountExecution
{
private:
   CTrade m_trade;

   bool PrepareSymbol(const string symbol, string &reason)
   {
      if(StringLen(symbol) == 0)
      {
         reason = "SYMBOL_MISSING";
         return false;
      }

      // Resolve the broker's exact symbol name and make it available to MT5.
      if(!SymbolSelect(symbol, true))
      {
         reason = "SYMBOL_UNAVAILABLE";
         return false;
      }

      long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      if(trade_mode == SYMBOL_TRADE_MODE_DISABLED)
      {
         reason = "SYMBOL_TRADE_DISABLED";
         return false;
      }

      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      {
         reason = "SYMBOL_NO_PRICE";
         return false;
      }

      return true;
   }

public:
   bool CanTrade(const string symbol, string &reason)
   {
      return PrepareSymbol(symbol, reason);
   }

   bool Buy(const string symbol,
            const double volume,
            const double sl,
            const double tp,
            const string comment,
            string &reason)
   {
      if(!PrepareSymbol(symbol, reason))
         return false;

      if(!m_trade.Buy(volume, symbol, 0.0, sl, tp, comment))
      {
         reason = IntegerToString((int)m_trade.ResultRetcode()) + ":" + m_trade.ResultRetcodeDescription();
         return false;
      }
      return true;
   }

   bool Sell(const string symbol,
             const double volume,
             const double sl,
             const double tp,
             const string comment,
             string &reason)
   {
      if(!PrepareSymbol(symbol, reason))
         return false;

      if(!m_trade.Sell(volume, symbol, 0.0, sl, tp, comment))
      {
         reason = IntegerToString((int)m_trade.ResultRetcode()) + ":" + m_trade.ResultRetcodeDescription();
         return false;
      }
      return true;
   }

   ulong ResultOrder() const { return m_trade.ResultOrder(); }
   ulong ResultDeal() const { return m_trade.ResultDeal(); }
   uint ResultRetcode() const { return m_trade.ResultRetcode(); }
   string ResultDescription() const { return m_trade.ResultRetcodeDescription(); }
};
