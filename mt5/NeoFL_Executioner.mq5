//+------------------------------------------------------------------+
//| NeoFL Executioner EA                                             |
//| The EA contains NO trading strategy. NeoFL Brain supplies orders. |
//+------------------------------------------------------------------+
#property strict
#property version "1.0"
#property description "NeoFL account-bound execution-only EA"

input string NeoFL_API_URL = "https://YOUR-NEOFL-API.example.com";
input string NeoFL_API_KEY = "";
input long   BoundAccountNumber = 318558926;
input string BoundServer = "XMGlobal-MT5 7";
input bool   RequireDemoAccount = true;
input double MaximumStartingLot = 0.01;
input ENUM_STRING_PLACEHOLDER_PLACEHOLDER_PLACEHOLDER_UNUSED = 0;

// User operating envelope. Strategy decisions remain in NeoFL.
enum ENUM_STRADDLE_RISK { STRADDLE_LOW=0, STRADDLE_MEDIUM=1, STRADDLE_HIGH=2 };
input ENUM_STRADDLE_RISK StraddleRisk = STRADDLE_MEDIUM;
input string AllowedAssetClasses = "GOLD,FX,INDEX,STOCK,CRYPTO,COMMODITY,OPTION,FUTURE";

int OnInit()
{
   long account = (long)AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   ENUM_ACCOUNT_TRADE_MODE mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);

   if(account != BoundAccountNumber)
   {
      Print("NeoFL BLOCKED: account mismatch. Expected=", BoundAccountNumber,
            " Actual=", account);
      return INIT_FAILED;
   }
   if(BoundServer != "" && server != BoundServer)
   {
      Print("NeoFL BLOCKED: server mismatch. Expected=", BoundServer,
            " Actual=", server);
      return INIT_FAILED;
   }
   if(RequireDemoAccount && mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("NeoFL BLOCKED: demo account required.");
      return INIT_FAILED;
   }
   if(NeoFL_API_URL == "" || StringFind(NeoFL_API_URL, "YOUR-NEOFL-API") >= 0)
   {
      Print("NeoFL BLOCKED: configure NeoFL_API_URL first.");
      return INIT_FAILED;
   }

   Print("NeoFL Executioner bound to account ", account, " / ", server);
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTick() { }

void OnTimer()
{
   // Connection/command transport is deliberately fail-closed.
   // No strategy or autonomous order generation exists in this EA.
   // Production transport will authenticate the EA binding and fetch
   // only commands whose account_number matches BoundAccountNumber.
}

// All order placement must be initiated by a verified NeoFL command.
// This stub intentionally contains no autonomous trading logic.
