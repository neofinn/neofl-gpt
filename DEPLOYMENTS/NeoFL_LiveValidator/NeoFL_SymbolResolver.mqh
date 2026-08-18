//+------------------------------------------------------------------+
//| NeoFL_SymbolResolver.mqh                                         |
//| Core module. Resolves a broker symbol to an InstrumentDescriptor. |
//| No trading logic. No order placement.                            |
//+------------------------------------------------------------------+
//
// Canon: symbol matching must be SEMANTIC, not substring.
//
//   XAUUSD, XAUUSDm, XAUUSD.a, XAUUSD.pro, PREFIX_XAUUSD_SUFFIX, GOLD  -> GOLD
//   BTCXAU                                                            -> NOT GOLD
//
// BTCXAU contains "XAU" and is not gold: there XAU is the QUOTE currency of a
// crypto cross. The distinguishing rule is positional --
//
//     XAU is gold only when it is the BASE, i.e. immediately followed by a
//     recognized quote currency.
//
//   XAUUSD  -> XAU at index 0, "USD" follows        -> base=XAU quote=USD -> GOLD
//   BTCXAU  -> XAU at index 3, nothing follows      -> XAU is the quote   -> NOT GOLD
//
// Naive substring matching on "XAU" is exactly the bug this module exists to
// prevent. Do not "simplify" it back into a StringFind.
//
#ifndef __NEOFL_SYMBOL_RESOLVER_MQH__
#define __NEOFL_SYMBOL_RESOLVER_MQH__

//--- Asset classes NeoFL can resolve to.
enum ENUM_NEOFL_ASSET
{
   NEOFL_ASSET_UNKNOWN = 0,
   NEOFL_ASSET_GOLD    = 1,
   NEOFL_ASSET_FX      = 2,
   NEOFL_ASSET_CRYPTO  = 3,
   NEOFL_ASSET_INDEX   = 4
};

//--- Result of resolving a broker symbol.
struct NeoFLInstrument
{
   bool             valid;          // was the symbol understood at all
   ENUM_NEOFL_ASSET asset_class;
   string           base_symbol;    // canonical, e.g. "XAUUSD"
   string           broker_symbol;  // exactly as the broker names it
   string           base;           // e.g. "XAU"
   string           quote;          // e.g. "USD"
   double           tick_size;
   double           tick_value;
   double           point;
   double           contract_size;
   int              digits;
   string           reject_reason;  // populated when valid == false
};

//--- Quote currencies recognized when deciding whether a base is followed by one.
const string NEOFL_QUOTES[] = {"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};

//--- Direct gold aliases that are not XAU-prefixed pairs.
const string NEOFL_GOLD_ALIASES[] = {"GOLD","XAUUSD"};

//+------------------------------------------------------------------+
//| Strip broker decoration: separators, digits, and case.           |
//| "fx.XAUUSD.pro_m" -> "FXXAUUSDPROM"                              |
//+------------------------------------------------------------------+
string NeoFLSym_Normalize(const string raw)
{
   string out = "";
   const int n = StringLen(raw);
   for(int i = 0; i < n; i++)
   {
      const ushort c = StringGetCharacter(raw, i);
      // Keep letters only; separators and digits are broker decoration.
      if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
         out += ShortToString(c);
   }
   StringToUpper(out);
   return out;
}

//+------------------------------------------------------------------+
//| Is `candidate` one of the recognized quote currencies?           |
//+------------------------------------------------------------------+
bool NeoFLSym_IsQuote(const string candidate)
{
   for(int i = 0; i < ArraySize(NEOFL_QUOTES); i++)
      if(NEOFL_QUOTES[i] == candidate)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Find XAU acting as a BASE currency: present, and immediately     |
//| followed by a recognized quote. Returns the quote, or "".        |
//|                                                                  |
//| This is the BTCXAU guard. Scans every occurrence so a prefixed   |
//| symbol still resolves.                                           |
//+------------------------------------------------------------------+
string NeoFLSym_GoldQuoteOrEmpty(const string normalized)
{
   int from = 0;
   while(true)
   {
      const int at = StringFind(normalized, "XAU", from);
      if(at < 0)
         return "";

      // Take the three characters following this "XAU".
      const string following = StringSubstr(normalized, at + 3, 3);
      if(NeoFLSym_IsQuote(following))
         return following;   // XAU is the base -> gold

      from = at + 1;         // keep scanning; may be a prefixed occurrence
   }
   return "";
}

//+------------------------------------------------------------------+
//| Classify a symbol STRING only. No broker calls, so this is       |
//| unit-testable without a terminal connection or market data.      |
//+------------------------------------------------------------------+
bool NeoFLSym_ClassifyString(const string raw, NeoFLInstrument &out)
{
   out.valid         = false;
   out.asset_class   = NEOFL_ASSET_UNKNOWN;
   out.base_symbol   = "";
   out.broker_symbol = raw;
   out.base          = "";
   out.quote         = "";
   out.tick_size     = 0.0;
   out.tick_value    = 0.0;
   out.point         = 0.0;
   out.contract_size = 0.0;
   out.digits        = 0;
   out.reject_reason = "";

   if(StringLen(raw) == 0)
   {
      out.reject_reason = "empty symbol";
      return false;
   }

   const string norm = NeoFLSym_Normalize(raw);
   if(StringLen(norm) == 0)
   {
      out.reject_reason = "symbol contains no letters";
      return false;
   }

   // 1) XAU acting as base, e.g. XAUUSD / XAUUSD.pro / FX_XAUUSD_m
   const string goldQuote = NeoFLSym_GoldQuoteOrEmpty(norm);
   if(goldQuote != "")
   {
      out.valid       = true;
      out.asset_class = NEOFL_ASSET_GOLD;
      out.base        = "XAU";
      out.quote       = goldQuote;
      out.base_symbol = "XAU" + goldQuote;
      return true;
   }

   // 2) Direct alias, e.g. GOLD / GOLDm. Quote is implicitly USD.
   if(StringFind(norm, "GOLD") >= 0)
   {
      out.valid       = true;
      out.asset_class = NEOFL_ASSET_GOLD;
      out.base        = "XAU";
      out.quote       = "USD";
      out.base_symbol = "XAUUSD";
      return true;
   }

   // 3) Symbol mentions XAU but not as a base -> explicitly rejected as gold.
   if(StringFind(norm, "XAU") >= 0)
   {
      out.reject_reason = "XAU present as quote currency, not base; not the gold instrument";
      return false;
   }

   out.reject_reason = "unrecognized instrument";
   return false;
}

//+------------------------------------------------------------------+
//| Convenience: is this broker symbol the gold instrument?          |
//+------------------------------------------------------------------+
bool NeoFLSym_IsGold(const string raw)
{
   NeoFLInstrument info;
   if(!NeoFLSym_ClassifyString(raw, info))
      return false;
   return info.asset_class == NEOFL_ASSET_GOLD;
}

//+------------------------------------------------------------------+
//| Full resolve: classification plus live broker contract metadata. |
//| Requires the symbol to exist in Market Watch.                    |
//+------------------------------------------------------------------+
bool NeoFLSym_Resolve(const string raw, NeoFLInstrument &out)
{
   if(!NeoFLSym_ClassifyString(raw, out))
      return false;

   if(!SymbolSelect(raw, true))
   {
      out.valid         = false;
      out.reject_reason = "symbol not available from broker: " + raw;
      return false;
   }

   out.tick_size     = SymbolInfoDouble(raw, SYMBOL_TRADE_TICK_SIZE);
   out.tick_value    = SymbolInfoDouble(raw, SYMBOL_TRADE_TICK_VALUE);
   out.point         = SymbolInfoDouble(raw, SYMBOL_POINT);
   out.contract_size = SymbolInfoDouble(raw, SYMBOL_TRADE_CONTRACT_SIZE);
   out.digits        = (int)SymbolInfoInteger(raw, SYMBOL_DIGITS);

   // Contract metadata must be real; never let a zero divisor reach risk sizing.
   if(out.tick_size <= 0.0 || out.point <= 0.0)
   {
      out.valid         = false;
      out.reject_reason = "broker returned invalid contract metadata";
      return false;
   }

   return true;
}

string NeoFLSym_AssetName(const ENUM_NEOFL_ASSET a)
{
   if(a == NEOFL_ASSET_GOLD)   return "GOLD";
   if(a == NEOFL_ASSET_FX)     return "FX";
   if(a == NEOFL_ASSET_CRYPTO) return "CRYPTO";
   if(a == NEOFL_ASSET_INDEX)  return "INDEX";
   return "UNKNOWN";
}

#endif // __NEOFL_SYMBOL_RESOLVER_MQH__
