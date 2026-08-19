//+------------------------------------------------------------------+
//| NeoFL Executioner EA                                             |
//| Canonical platform adapter: Body -> OrderIntent -> MT5 -> Report |
//+------------------------------------------------------------------+
#property strict
#property version "4.2"
#property description "NeoFL canonical execution adapter for MT5"

#include <Trade/Trade.mqh>

input string NeoFL_API_BASE_URL = "";
input string NeoFL_BINDING_TOKEN = "";
input int    PollIntervalSeconds = 5;
input int    MaxDeviationPoints = 50;

CTrade g_trade;
long   g_account = 0;
string g_server = "";
bool   g_authorized = false;
bool   g_execution_enabled = false;

string EnvironmentName(){ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);return mode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "LIVE";}
string BaseURL(){string s=NeoFL_API_BASE_URL;while(StringLen(s)>0 && StringSubstr(s,StringLen(s)-1)=="/")s=StringSubstr(s,0,StringLen(s)-1);return s;}
string JsonEscape(string value){StringReplace(value,"\\","\\\\");StringReplace(value,"\"","\\\"");return value;}
string UrlValue(string value){StringReplace(value,"%","%25");StringReplace(value," ","%20");StringReplace(value,"#","%23");StringReplace(value,"?","%3F");StringReplace(value,"&","%26");StringReplace(value,"+","%2B");return value;}
string JsonString(string body,string key){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return "";p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(p>=StringLen(body)||StringGetCharacter(body,p)!='\"')return "";p++;string out="";bool esc=false;for(int i=p;i<StringLen(body);i++){ushort c=StringGetCharacter(body,i);if(esc){out+=CharToString((uchar)c);esc=false;continue;}if(c=='\\'){esc=true;continue;}if(c=='\"')break;out+=CharToString((uchar)c);}return out;}
double JsonNumber(string body,string key,double fallback=0.0){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return fallback;p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(p>=StringLen(body)||StringSubstr(body,p,4)=="null")return fallback;int e=p;while(e<StringLen(body)){ushort c=StringGetCharacter(body,e);if((c>='0'&&c<='9')||c=='-'||c=='+'||c=='.'||c=='e'||c=='E')e++;else break;}return StringToDouble(StringSubstr(body,p,e-p));}
bool JsonBool(string body,string key,bool fallback=false){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return fallback;p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(StringSubstr(body,p,4)=="true")return true;if(StringSubstr(body,p,5)=="false")return false;return fallback;}

bool HttpGet(string path,string &body,int &http){string url=BaseURL()+path;string headers="X-NeoFL-Binding-Token: "+NeoFL_BINDING_TOKEN+"\r\n";char data[];char result[];string response_headers="";ResetLastError();http=WebRequest("GET",url,headers,10000,data,result,response_headers);if(http==-1){Print("NeoFL WebRequest GET failed. Error=",GetLastError()," URL=",url);body="";return false;}body=CharArrayToString(result,0,-1,CP_UTF8);return true;}

bool Handshake(){if(BaseURL()==""||NeoFL_BINDING_TOKEN==""){g_authorized=false;g_execution_enabled=false;Print("NeoFL BLOCKED: API base URL and binding token are required.");return false;}string path=StringFormat("/api/handshake?account_number=%I64d&server=%s&connector=MT5&environment=%s",g_account,UrlValue(g_server),EnvironmentName());string body;int http=0;if(!HttpGet(path,body,http)){g_authorized=false;g_execution_enabled=false;return false;}g_authorized=(http>=200&&http<300&&StringFind(body,"\"accepted\":true")>=0);g_execution_enabled=JsonBool(body,"execution_enabled",false);if(!g_authorized){g_execution_enabled=false;Print("NeoFL BLOCKED: handshake rejected. HTTP=",http," response=",body);}else if(!g_execution_enabled)Print("NeoFL CONNECTED: execution gate is LOCKED.");else Print("NeoFL CONNECTED: execution gate is ENABLED.");return g_authorized;}

string ResolveSymbol(string requested){if(SymbolSelect(requested,true))return requested;string upper=requested;StringToUpper(upper);if(upper=="XAUUSD"||upper=="GOLD"){int total=SymbolsTotal(false);for(int i=0;i<total;i++){string s=SymbolName(i,false);string u=s;StringToUpper(u);if(u=="GOLD"||StringFind(u,"XAUUSD")>=0)return s;}}return "";}

bool SendTelemetry(){double balance=AccountInfoDouble(ACCOUNT_BALANCE);double equity=AccountInfoDouble(ACCOUNT_EQUITY);double profit=AccountInfoDouble(ACCOUNT_PROFIT);double drawdown=MathMax(0.0,balance-equity);int open=PositionsTotal();string path=StringFormat("/api/telemetry?account_number=%I64d&server=%s&connector=MT5&environment=%s&balance=%.8f&equity=%.8f&profit=%.8f&drawdown=%.8f&open_trades=%d&brain_status=CONNECTED",g_account,UrlValue(g_server),EnvironmentName(),balance,equity,profit,drawdown,open);string body;int http=0;if(!HttpGet(path,body,http)){Print("NeoFL telemetry request failed.");return false;}if(http<200||http>=300){Print("NeoFL telemetry rejected. HTTP=",http," response=",body);return false;}return true;}

bool Report(string intent_id,string status,double filled,double price,string broker_order_id,string rejection){string path=StringFormat("/api/v1/execution-report?account_number=%I64d&intent_id=%s&adapter=MT5&status=%s&filled_quantity=%.8f&average_fill_price=%.8f&broker_order_id=%s&rejection_code=%s",g_account,UrlValue(intent_id),UrlValue(status),filled,price,UrlValue(broker_order_id),UrlValue(rejection));string body;int http=0;if(!HttpGet(path,body,http))return false;if(http<200||http>=300){Print("NeoFL execution report rejected. HTTP=",http," response=",body);return false;}return true;}

void ProcessIntent(){if(!g_authorized||!g_execution_enabled)return;string body;int http=0;string path=StringFormat("/api/v1/execution/next?account_number=%I64d",g_account);if(!HttpGet(path,body,http)||http<200||http>=300)return;if(StringFind(body,"\"available\":true")<0)return;string intent_id=JsonString(body,"id");string symbol_requested=JsonString(body,"symbol");string direction=JsonString(body,"direction");double volume=JsonNumber(body,"quantity",0.0);double sl=JsonNumber(body,"stop",0.0);double tp=JsonNumber(body,"target",0.0);string symbol=ResolveSymbol(symbol_requested);if(intent_id==""||symbol==""||volume<=0){Report(intent_id,"REJECTED",0,0,"","INVALID_INTENT");return;}g_trade.SetDeviationInPoints(MaxDeviationPoints);bool ok=false;if(direction=="BUY")ok=g_trade.Buy(volume,symbol,0.0,sl,tp,"NeoFL:"+intent_id);else if(direction=="SELL")ok=g_trade.Sell(volume,symbol,0.0,sl,tp,"NeoFL:"+intent_id);else{Report(intent_id,"REJECTED",0,0,"","UNSUPPORTED_DIRECTION");return;}if(ok){ulong ticket=g_trade.ResultOrder();string broker_order_id=StringFormat("%I64u",ticket);double fill=g_trade.ResultPrice();Report(intent_id,"FILLED",volume,fill,broker_order_id,"");Print("NeoFL execution completed: intent=",intent_id," symbol=",symbol," volume=",volume," price=",fill);}else{Report(intent_id,"REJECTED",0,0,"",IntegerToString(g_trade.ResultRetcode()));Print("NeoFL execution rejected: intent=",intent_id," retcode=",g_trade.ResultRetcode()," ",g_trade.ResultRetcodeDescription());}}

int OnInit(){g_account=(long)AccountInfoInteger(ACCOUNT_LOGIN);g_server=AccountInfoString(ACCOUNT_SERVER);if(BaseURL()==""||NeoFL_BINDING_TOKEN==""){Print("NeoFL BLOCKED: configure NeoFL_API_BASE_URL and NeoFL_BINDING_TOKEN.");return INIT_FAILED;}EventSetTimer(MathMax(1,PollIntervalSeconds));Handshake();Print("NeoFL Executioner 4.2 started. Account=",g_account," Server=",g_server);return INIT_SUCCEEDED;}
void OnDeinit(const int reason){EventKillTimer();}
void OnTick(){ }
void OnTimer(){if(!Handshake())return;SendTelemetry();ProcessIntent();}
