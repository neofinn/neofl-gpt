//+------------------------------------------------------------------+
//| NeoFL Executioner EA                                             |
//| Universal EA: intelligence lives in NeoFL; this EA executes only. |
//+------------------------------------------------------------------+
#property strict
#property version "2.0"
#property description "Universal NeoFL execution-only EA with account-bound API routing"

input string NeoFL_API_URL = "https://neofl-execution-gateway-1li631.v2.appdeploy.ai/api/execution/318558926";
input string NeoFL_BINDING_TOKEN = "";
input bool   RequireDemoAccount = true;
input double MaximumStartingLot = 0.01;

enum ENUM_STRADDLE_RISK { STRADDLE_LOW=0, STRADDLE_MEDIUM=1, STRADDLE_HIGH=2 };
input ENUM_STRADDLE_RISK StraddleRisk = STRADDLE_MEDIUM;
input string AllowedAssetClasses = "GOLD,FX,INDEX,STOCK,CRYPTO,COMMODITY,OPTION,FUTURE";

long g_account = 0;
string g_server = "";

string BaseUrl()
{
   string u = NeoFL_API_URL;
   while(StringSubstr(u,StringLen(u)-1,1)=="/") u=StringSubstr(u,0,StringLen(u)-1);
   return u;
}

bool IdentityOK()
{
   long account=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   string server=AccountInfoString(ACCOUNT_SERVER);
   ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(account!=g_account) return false;
   if(server!=g_server) return false;
   if(RequireDemoAccount && mode!=ACCOUNT_TRADE_MODE_DEMO) return false;
   return true;
}

int OnInit()
{
   g_account=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   g_server=AccountInfoString(ACCOUNT_SERVER);
   ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);

   if(NeoFL_API_URL=="" || StringFind(NeoFL_API_URL,"YOUR-NEOFL-API")>=0)
   {
      Print("NeoFL BLOCKED: configure account-bound NeoFL_API_URL.");
      return INIT_FAILED;
   }
   if(RequireDemoAccount && mode!=ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("NeoFL BLOCKED: demo account required.");
      return INIT_FAILED;
   }

   // The URL itself identifies the account route. The gateway must still
   // verify account/server/token before accepting any command.
   EventSetTimer(1);
   Print("NeoFL Executioner started: account=",g_account," server=",g_server);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick() {}

void OnTimer()
{
   if(!IdentityOK())
   {
      Print("NeoFL BLOCKED: runtime account/server/environment changed.");
      return;
   }
   // Command polling/execution transport is fail-closed until the gateway
   // returns a verified, account-bound command. No local strategy exists.
}

// IMPORTANT: no signal generation, strategy logic, or autonomous order
// creation belongs in this EA. NeoFL Brain is the sole decision maker.
