//+------------------------------------------------------------------+
//| NeoFL_SymbolResolver_SelfTest.mq5                                |
//| SCRIPT: verifies the Symbol Resolver against the canon rules.    |
//| Places NO orders. Reads no market data. Safe to run any time.    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property script_show_inputs
#property description "Runs the NeoFL Symbol Resolver test suite and prints PASS/FAIL to the Experts tab."

#include "NeoFL_SymbolResolver.mqh"

input bool InpAlsoResolveChartSymbol = true;  // additionally resolve the current chart symbol

int g_pass = 0;
int g_fail = 0;

//--- Assert that `symbol` classifies as gold.
void ExpectGold(const string symbol)
{
   NeoFLInstrument info;
   const bool ok = NeoFLSym_ClassifyString(symbol, info);
   if(ok && info.asset_class == NEOFL_ASSET_GOLD)
   {
      g_pass++;
      PrintFormat("  PASS  %-24s -> GOLD  (base=%s quote=%s canonical=%s)",
                  symbol, info.base, info.quote, info.base_symbol);
   }
   else
   {
      g_fail++;
      PrintFormat("  FAIL  %-24s -> expected GOLD, got %s  [%s]",
                  symbol, NeoFLSym_AssetName(info.asset_class), info.reject_reason);
   }
}

//--- Assert that `symbol` does NOT classify as gold.
void ExpectNotGold(const string symbol)
{
   NeoFLInstrument info;
   NeoFLSym_ClassifyString(symbol, info);
   if(info.asset_class != NEOFL_ASSET_GOLD)
   {
      g_pass++;
      PrintFormat("  PASS  %-24s -> rejected  [%s]", symbol, info.reject_reason);
   }
   else
   {
      g_fail++;
      PrintFormat("  FAIL  %-24s -> WRONGLY classified as GOLD", symbol);
   }
}

void OnStart()
{
   Print("=====================================================");
   Print("  NeoFL Symbol Resolver - self test");
   Print("=====================================================");

   Print("[1] Valid gold symbols (canon: must all resolve)");
   ExpectGold("XAUUSD");
   ExpectGold("XAUUSDm");
   ExpectGold("XAUUSD.a");
   ExpectGold("XAUUSD.pro");
   ExpectGold("PREFIX_XAUUSD_SUFFIX");
   ExpectGold("GOLD");
   ExpectGold("GOLDm");
   ExpectGold("xauusd");              // case insensitive
   ExpectGold("XAUUSD.raw");
   ExpectGold("fx.XAUUSD.c");

   Print("");
   Print("[2] Must be REJECTED (canon: XAU present but not the base)");
   ExpectNotGold("BTCXAU");           // the canon's named counter-example
   ExpectNotGold("ETHXAU");
   ExpectNotGold("BTCXAU.pro");

   Print("");
   Print("[3] Other instruments must not masquerade as gold");
   ExpectNotGold("EURUSD");
   ExpectNotGold("BTCUSD");
   ExpectNotGold("US500");
   ExpectNotGold("");

   if(InpAlsoResolveChartSymbol)
   {
      Print("");
      Print("[4] Live resolve of this chart's symbol (uses broker metadata)");
      NeoFLInstrument live;
      if(NeoFLSym_Resolve(_Symbol, live))
         PrintFormat("  %s -> %s  base=%s quote=%s digits=%d point=%.5f tick_size=%.5f contract=%.1f",
                     _Symbol, NeoFLSym_AssetName(live.asset_class), live.base, live.quote,
                     live.digits, live.point, live.tick_size, live.contract_size);
      else
         PrintFormat("  %s -> not resolved as a NeoFL instrument  [%s]",
                     _Symbol, live.reject_reason);
      Print("  (informational only - not counted as pass/fail)");
   }

   Print("");
   Print("=====================================================");
   PrintFormat("  RESULT: %d passed, %d failed", g_pass, g_fail);
   if(g_fail == 0)
      Print("  ALL TESTS PASSED");
   else
      Print("  *** FAILURES PRESENT - DO NOT SHIP ***");
   Print("=====================================================");
}
