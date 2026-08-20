//+------------------------------------------------------------------+
//| NeoFL_Reporter.mq5                                                |
//| Terminal-side reporter: identifies the connected account, reports  |
//| deployment/communication state, and publishes execution events.   |
//+------------------------------------------------------------------+
#property strict
#property version "1.0"

input string GatewayURL = "";
input string GatewayAPIKey = "";
input string ReporterInstance = "";
input int HeartbeatSeconds = 5;
input bool ReportPositions = true;
input bool ReportOrders = true;

string LastDeployment = "";
datetime LastHeartbeat = 0;

string JsonEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   return value;
}

string AccountIdentity()
{
   return IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));
}

string BuildReport()
{
   string broker = JsonEscape(AccountInfoString(ACCOUNT_COMPANY));
   string server = JsonEscape(AccountInfoString(ACCOUNT_SERVER));
   string currency = JsonEscape(AccountInfoString(ACCOUNT_CURRENCY));
   string symbol = JsonEscape(_Symbol);
   string payload = "{";
   payload += "\"type\":\"mt5_heartbeat\",";
   payload += "\"account_id\":\"" + AccountIdentity() + "\",";
   payload += "\"instance\":\"" + JsonEscape(ReporterInstance) + "\",";
   payload += "\"broker\":\"" + broker + "\",";
   payload += "\"server\":\"" + server + "\",";
   payload += "\"currency\":\"" + currency + "\",";
   payload += "\"symbol\":\"" + symbol + "\",";
   payload += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2) + ",";
   payload += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2) + ",";
   payload += "\"positions\":" + IntegerToString(PositionsTotal()) + ",";
   payload += "\"orders\":" + IntegerToString(OrdersTotal()) + ",";
   payload += "\"terminal\":\"MT5\",";
   payload += "\"reporter_version\":\"1.0\"";
   payload += "}";
   return payload;
}

bool PostJSON(string path, string payload)
{
   if(GatewayURL == "") return false;
   string url = GatewayURL + path;
   string headers = "Content-Type: application/json\r\nAuthorization: Bearer " + GatewayAPIKey + "\r\n";
   char data[], result[];
   StringToCharArray(payload, data, 0, -1, CP_UTF8);
   string result_headers;
   ResetLastError();
   int status = WebRequest("POST", url, headers, 5000, data, result, result_headers);
   if(status < 200 || status >= 300)
   {
      PrintFormat("NeoFL Reporter HTTP failure: %d error=%d", status, GetLastError());
      return false;
   }
   string response = CharArrayToString(result, 0, -1, CP_UTF8);
   if(StringFind(response, "\"branch\":\"neoflgpt-parallel\"") >= 0)
      LastDeployment = "neoflgpt-parallel";
   else if(StringFind(response, "\"branch\":\"main\"") >= 0)
      LastDeployment = "main";
   return true;
}

int OnInit()
{
   EventSetTimer(MathMax(1, HeartbeatSeconds));
   Print("NeoFL Reporter started: account=", AccountIdentity());
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   string report = BuildReport();
   if(PostJSON("/mt5/report", report))
      LastHeartbeat = TimeCurrent();
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   string payload = "{";
   payload += "\"type\":\"execution_event\",";
   payload += "\"account_id\":\"" + AccountIdentity() + "\",";
   payload += "\"instance\":\"" + JsonEscape(ReporterInstance) + "\",";
   payload += "\"transaction_type\":" + IntegerToString((int)trans.type) + ",";
   payload += "\"order\":" + IntegerToString((long)trans.order) + ",";
   payload += "\"deal\":" + IntegerToString((long)trans.deal) + ",";
   payload += "\"position\":" + IntegerToString((long)trans.position) + ",";
   payload += "\"symbol\":\"" + JsonEscape(trans.symbol) + "\",";
   payload += "\"volume\":" + DoubleToString(trans.volume,8) + ",";
   payload += "\"price\":" + DoubleToString(trans.price,8) + ",";
   payload += "\"retcode\":" + IntegerToString((int)result.retcode);
   payload += "}";
   PostJSON("/mt5/execution-report", payload);
}
