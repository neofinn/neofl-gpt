//+------------------------------------------------------------------+
//| NeoFL Executioner EA                                             |
//| Canonical platform adapter: Brain -> Body -> MT5 -> Report       |
//| v4.5: production Vercel Body endpoint + deterministic diagnostics|
//+------------------------------------------------------------------+
#property strict
#property version "4.5"
#property description "NeoFL canonical execution adapter for MT5"

#include <Trade/Trade.mqh>

#define NEOFL_API_BASE_URL "https://neofl-gpt.vercel.app"

input string NeoFL_BINDING_TOKEN = "";
input int    PollIntervalSeconds = 5;
input int    MaxDeviationPoints = 50;

CTrade g_trade;
long   g_account = 0;
string g_server = "";
bool   g_authorized = false;
bool   g_execution_enabled = false;
string g_last_status = "STARTING";
string g_last_http = "-";
string g_last_error = "";

string EnvironmentName(){ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);return mode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "LIVE";}
string BaseURL(){return NEOFL_API_BASE_URL;}
string UrlValue(string value){StringReplace(value,"%","%25");StringReplace(value," ","%20");StringReplace(value,"#","%23");StringReplace(value,"?","%3F");StringReplace(value,"&","%26");StringReplace(value,"+","%2B");return value;}
string JsonString(string body,string key){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return "";p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(p>=StringLen(body)||StringGetCharacter(body,p)!='\"')return "";p++;string out="";bool esc=false;for(int i=p;i<StringLen(body);i++){ushort c=StringGetCharacter(body,i);if(esc){out+=CharToString((uchar)c);esc=false;continue;}if(c=='\\'){esc=true;continue;}if(c=='\"')break;out+=CharToString((uchar)c);}return out;}
double JsonNumber(string body,string key,double fallback=0.0){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return fallback;p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(p>=StringLen(body)||StringSubstr(body,p,4)=="null")return fallback;int e=p;while(e<StringLen(body)){ushort c=StringGetCharacter(body,e);if((c>='0'&&c<='9')||c=='-'||c=='+'||c=='.'||c=='e'||c=='E')e++;else break;}return StringToDouble(StringSubstr(body,p,e-p));}
bool JsonBool(string body,string key,bool fallback=false){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return fallback;p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(StringSubstr(body,p,4)=="true")return true;if(StringSubstr(body,p,5)=="false")return false;return fallback;}

void RenderStatus(){
   string auth=g_authorized?"CONNECTED":"OFFLINE";
   string gate=g_execution_enabled?"ENABLED":"LOCKED";
   Comment("NeoFL EXECUTION ENGINE v4.5\n",
           "ACCOUNT: ",g_account," | ",EnvironmentName(),"\n",
           "SERVER: ",g_server,"\n",
           "BODY: ",auth," | EXECUTION: ",gate,"\n",
           "STATUS: ",g_last_status," | HTTP: ",g_last_http,"\n",
           "API: ",BaseURL(),"\n",
           "HOST CHART: ",_Symbol," | UNIVERSE: ACCOUNT-WIDE");
}

bool HttpGet(string path,string &body,int &http){
   string url=BaseURL()+path;
   string headers="X-NeoFL-Binding-Token: "+NeoFL_BINDING_TOKEN+"\r\nAccept: application/json\r\n";
   char data[]; char result[]; string response_headers="";
   ResetLastError();
   http=WebRequest("GET",url,headers,10000,data,result,response_headers);
   g_last_http=IntegerToString(http);
   if(http==-1){
      int err=GetLastError();
      g_last_error="WebRequest error "+IntegerToString(err);
      Print("NeoFL WebRequest failed. Error=",err," URL=",url);
      body=""; return false;
   }
   body=CharArrayToString(result,0,-1,CP_UTF8);
   // Never dump HTML/JavaScript responses into the MT5 journal. This catches
   // stale AppDeploy URLs, redirects, and accidental webpage endpoints.
   if(StringFind(body,"<html")>=0 || StringFind(body,"<!DOCTYPE")>=0 || StringFind(body,"<script")>=0){
      g_last_error="HTML response received from API endpoint; endpoint/configuration is stale";
      Print("NeoFL API ERROR: HTML response received from ",url," HTTP=",http);
      return false;
   }
   return true;
}

bool Handshake(){
   if(NeoFL_BINDING_TOKEN==""){g_authorized=false;g_execution_enabled=false;g_last_status="BLOCKED_NO_BINDING";g_last_error="Binding key is empty";RenderStatus();Print("NeoFL BLOCKED: enter the NeoFL Binding Key in EA Inputs.");return false;}
   string path=StringFormat("/api/v1/body/handshake?account_number=%I64d&server=%s&connector=MT5&environment=%s",g_account,UrlValue(g_server),EnvironmentName());
   string body; int http=0;
   if(!HttpGet(path,body,http)){g_authorized=false;g_execution_enabled=false;g_last_status="HANDSHAKE_ERROR";RenderStatus();return false;}
   g_authorized=(http>=200&&http<300&&StringFind(body,"\"accepted\":true")>=0);
   g_execution_enabled=JsonBool(body,"execution_enabled",false);
   if(!g_authorized){g_execution_enabled=false;g_last_status=(http==401?"HANDSHAKE_UNAUTHORIZED":"HANDSHAKE_REJECTED");Print("NeoFL BLOCKED: handshake rejected. HTTP=",http," response=",body);}
   else if(!g_execution_enabled){g_last_status="CONNECTED_LOCKED";Print("NeoFL BODY CONNECTED: execution gate is LOCKED.");}
   else{g_last_status="READY";g_last_error="";Print("NeoFL BODY CONNECTED: execution gate is ENABLED.");}
   RenderStatus(); return g_authorized;
}

string ResolveSymbol(string requested){
   if(requested!=""&&SymbolSelect(requested,true))return requested;
   string target=requested;StringToUpper(target);int total=SymbolsTotal(false);
   for(int i=0;i<total;i++){string s=SymbolName(i,false);if(s=="")continue;string u=s;StringToUpper(u);if(u==target||(target=="XAUUSD"&&StringFind(u,"XAUUSD")>=0)||(target=="GOLD"&&(u=="GOLD"||StringFind(u,"XAUUSD")>=0))){SymbolSelect(s,true);return s;}}
   return "";
}

bool SendHeartbeat(){
   string path=StringFormat("/api/v1/body/heartbeat?account_number=%I64d&server=%s&connector=MT5&environment=%s",g_account,UrlValue(g_server),EnvironmentName());
   string body;int http=0;if(!HttpGet(path,body,http)){Print("NeoFL body heartbeat failed.");return false;}if(http<200||http>=300){Print("NeoFL body heartbeat rejected. HTTP=",http," response=",body);return false;}return true;
}

bool SendTelemetry(){
   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY),profit=AccountInfoDouble(ACCOUNT_PROFIT);double drawdown=MathMax(0.0,balance-equity);int open=PositionsTotal();
   string path=StringFormat("/api/v1/body/telemetry?account_number=%I64d&server=%s&connector=MT5&environment=%s&balance=%.8f&equity=%.8f&profit=%.8f&drawdown=%.8f&open_trades=%d&ea_status=%s",g_account,UrlValue(g_server),EnvironmentName(),balance,equity,profit,drawdown,open,UrlValue(g_last_status));
   string body;int http=0;if(!HttpGet(path,body,http)){Print("NeoFL body telemetry request failed.");return false;}if(http<200||http>=300){Print("NeoFL body telemetry rejected. HTTP=",http," response=",body);return false;}return true;
}

bool SendMarketStateForSymbol(string symbol){
   if(!SymbolSelect(symbol,true))return false;MqlTick tick;if(!SymbolInfoTick(symbol,tick))return false;int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);double point=SymbolInfoDouble(symbol,SYMBOL_POINT);datetime m5_time=iTime(symbol,PERIOD_M5,0),h1_time=iTime(symbol,PERIOD_H1,0);double m5_open=iOpen(symbol,PERIOD_M5,0),m5_high=iHigh(symbol,PERIOD_M5,0),m5_low=iLow(symbol,PERIOD_M5,0),m5_close=iClose(symbol,PERIOD_M5,0);double h1_open=iOpen(symbol,PERIOD_H1,0),h1_high=iHigh(symbol,PERIOD_H1,0),h1_low=iLow(symbol,PERIOD_H1,0),h1_close=iClose(symbol,PERIOD_H1,0);
   string path=StringFormat("/api/v1/body/market-state?account_number=%I64d&server=%s&connector=MT5&environment=%s&symbol=%s&bid=%.10f&ask=%.10f&spread=%.10f&digits=%d&point=%.10f&time=%s&timeframe=M5&m5_time=%s&m5_open=%.10f&m5_high=%.10f&m5_low=%.10f&m5_close=%.10f&h1_time=%s&h1_open=%.10f&h1_high=%.10f&h1_low=%.10f&h1_close=%.10f",g_account,UrlValue(g_server),EnvironmentName(),UrlValue(symbol),tick.bid,tick.ask,(tick.ask-tick.bid),digits,point,UrlValue(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)),UrlValue(TimeToString(m5_time,TIME_DATE|TIME_SECONDS)),m5_open,m5_high,m5_low,m5_close,UrlValue(TimeToString(h1_time,TIME_DATE|TIME_SECONDS)),h1_open,h1_high,h1_low,h1_close);
   string body;int http=0;if(!HttpGet(path,body,http)){Print("NeoFL market-state request failed for ",symbol);return false;}if(http<200||http>=300){Print("NeoFL market-state rejected for ",symbol," HTTP=",http," response=",body);return false;}return true;
}

void SendAccountUniverseMarketState(){int total=SymbolsTotal(false),sent=0;for(int i=0;i<total;i++){if(sent>=2000)break;string symbol=SymbolName(i,false);if(symbol=="")continue;long mode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);if(mode==SYMBOL_TRADE_MODE_DISABLED)continue;if(SendMarketStateForSymbol(symbol))sent++;}Print("NeoFL account universe telemetry: market-state sent for ",sent," tradable symbols.");}

bool Report(string intent_id,string status,double filled,double price,string broker_order_id,string rejection_code,string rejection_reason,string symbol,string direction,double quantity,double stop,double target){
   string path=StringFormat("/api/v1/execution-report?account_number=%I64d&server=%s&connector=MT5&environment=%s&intent_id=%s&adapter=MT5&status=%s&filled_quantity=%.8f&average_fill_price=%.8f&broker_order_id=%s&rejection_code=%s&rejection_reason=%s&symbol=%s&direction=%s&quantity=%.8f&stop=%.10f&target=%.10f",g_account,UrlValue(g_server),EnvironmentName(),UrlValue(intent_id),UrlValue(status),filled,price,UrlValue(broker_order_id),UrlValue(rejection_code),UrlValue(rejection_reason),UrlValue(symbol),UrlValue(direction),quantity,stop,target);
   string body;int http=0;if(!HttpGet(path,body,http))return false;if(http<200||http>=300){Print("NeoFL execution report rejected. HTTP=",http," response=",body);return false;}return true;
}

void ProcessIntent(){
   if(!g_authorized||!g_execution_enabled)return;string body;int http=0;string path=StringFormat("/api/v1/execution/next?account_number=%I64d",g_account);if(!HttpGet(path,body,http)||http<200||http>=300)return;if(StringFind(body,"\"available\":true")<0)return;
   string intent_id=JsonString(body,"id"),symbol_requested=JsonString(body,"symbol"),direction=JsonString(body,"direction");double volume=JsonNumber(body,"quantity",0.0),sl=JsonNumber(body,"stop",0.0),tp=JsonNumber(body,"target",0.0);string symbol=ResolveSymbol(symbol_requested);
   if(intent_id==""||symbol==""||volume<=0){Report(intent_id,"REJECTED",0,0,"","INVALID_INTENT","Intent is missing id, symbol, or positive quantity or symbol is not tradable on this account.",symbol,direction,volume,sl,tp);return;}
   g_trade.SetDeviationInPoints(MaxDeviationPoints);bool ok=false;if(direction=="BUY")ok=g_trade.Buy(volume,symbol,0.0,sl,tp,"NeoFL:"+intent_id);else if(direction=="SELL")ok=g_trade.Sell(volume,symbol,0.0,sl,tp,"NeoFL:"+intent_id);else{Report(intent_id,"REJECTED",0,0,"","UNSUPPORTED_DIRECTION","Only BUY and SELL are supported by the MT5 execution adapter.",symbol,direction,volume,sl,tp);return;}
   if(ok){ulong ticket=g_trade.ResultOrder();string broker_order_id=StringFormat("%I64u",ticket);double fill=g_trade.ResultPrice();Report(intent_id,"FILLED",volume,fill,broker_order_id,"","",symbol,direction,volume,sl,tp);Print("NeoFL execution completed: intent=",intent_id," symbol=",symbol," volume=",volume," price=",fill);}
   else{string code=IntegerToString(g_trade.ResultRetcode());string reason=g_trade.ResultRetcodeDescription();Report(intent_id,"REJECTED",0,0,"",code,reason,symbol,direction,volume,sl,tp);Print("NeoFL execution rejected: intent=",intent_id," symbol=",symbol," retcode=",g_trade.ResultRetcode()," ",reason);}
}

int OnInit(){
   g_account=(long)AccountInfoInteger(ACCOUNT_LOGIN);g_server=AccountInfoString(ACCOUNT_SERVER);RenderStatus();
   if(NeoFL_BINDING_TOKEN==""){Print("NeoFL BLOCKED: enter the NeoFL Binding Key in EA Inputs.");return INIT_FAILED;}
   int poll_seconds=(PollIntervalSeconds<1?1:PollIntervalSeconds);EventSetTimer(poll_seconds);Handshake();Print("NeoFL Executioner 4.5 started. Account=",g_account," Server=",g_server," HostChart=",_Symbol," Universe=ACCOUNT-WIDE");return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){EventKillTimer();Comment("");}
void OnTick(){ }
void OnTimer(){if(!Handshake())return;SendHeartbeat();SendTelemetry();SendAccountUniverseMarketState();ProcessIntent();RenderStatus();}
