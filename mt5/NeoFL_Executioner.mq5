//+------------------------------------------------------------------+
//| NeoFL Executioner EA                                             |
//| Canonical platform adapter: Brain -> Body -> MT5 -> Report       |
//+------------------------------------------------------------------+
#property strict
#property version "4.3"
#property description "NeoFL canonical execution adapter for MT5"

#include <Trade/Trade.mqh>

input string NeoFL_API_BASE_URL = "";
input string NeoFL_BINDING_TOKEN = "";
input int    PollIntervalSeconds = 5;
input int    MaxDeviationPoints = 50;
input string MarketSymbol = "";

CTrade g_trade;
long   g_account = 0;
string g_server = "";
bool   g_authorized = false;
bool   g_execution_enabled = false;
string g_last_market_symbol = "";

string EnvironmentName(){ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);return mode==ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "LIVE";}
string BaseURL(){string s=NeoFL_API_BASE_URL;while(StringLen(s)>0 && StringSubstr(s,StringLen(s)-1)=="/")s=StringSubstr(s,0,StringLen(s)-1);return s;}
string UrlValue(string value){StringReplace(value,"%","%25");StringReplace(value," ","%20");StringReplace(value,"#","%23");StringReplace(value,"?","%3F");StringReplace(value,"&","%26");StringReplace(value,"+","%2B");return value;}
string JsonString(string body,string key){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return "";p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(p>=StringLen(body)||StringGetCharacter(body,p)!='\"')return "";p++;string out="";bool esc=false;for(int i=p;i<StringLen(body);i++){ushort c=StringGetCharacter(body,i);if(esc){out+=CharToString((uchar)c);esc=false;continue;}if(c=='\\'){esc=true;continue;}if(c=='\"')break;out+=CharToString((uchar)c);}return out;}
double JsonNumber(string body,string key,double fallback=0.0){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return fallback;p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(p>=StringLen(body)||StringSubstr(body,p,4)=="null")return fallback;int e=p;while(e<StringLen(body)){ushort c=StringGetCharacter(body,e);if((c>='0'&&c<='9')||c=='-'||c=='+'||c=='.'||c=='e'||c=='E')e++;else break;}return StringToDouble(StringSubstr(body,p,e-p));}
bool JsonBool(string body,string key,bool fallback=false){string marker="\""+key+"\":";int p=StringFind(body,marker);if(p<0)return fallback;p+=StringLen(marker);while(p<StringLen(body)&&(StringGetCharacter(body,p)==' '||StringGetCharacter(body,p)=='\t'))p++;if(StringSubstr(body,p,4)=="true")return true;if(StringSubstr(body,p,5)=="false")return false;return fallback;}

bool HttpGet(string path,string &body,int &http){string url=BaseURL()+path;string headers="X-NeoFL-Binding-Token: "+NeoFL_BINDING_TOKEN+"\r\n";char data[];char result[];string response_headers="";ResetLastError();http=WebRequest("GET",url,headers,10000,data,result,response_headers);if(http==-1){Print("NeoFL WebRequest GET failed. Error=",GetLastError()," URL=",url);body="";return false;}body=CharArrayToString(result,0,-1,CP_UTF8);return true;}

bool Handshake(){if(BaseURL()==""||NeoFL_BINDING_TOKEN==""){g_authorized=false;g_execution_enabled=false;Print("NeoFL BLOCKED: API base URL and binding token are required.");return false;}string path=StringFormat("/api/v1/body/handshake?account_number=%I64d&server=%s&connector=MT5&environment=%s",g_account,UrlValue(g_server),EnvironmentName());string body;int http=0;if(!HttpGet(path,body,http)){g_authorized=false;g_execution_enabled=false;return false;}g_authorized=(http>=200&&http<300&&StringFind(body,"\"accepted\":true")>=0);g_execution_enabled=JsonBool(body,"execution_enabled",false);if(!g_authorized){g_execution_enabled=false;Print("NeoFL BLOCKED: canonical handshake rejected. HTTP=",http," response=",body);}else if(!g_execution_enabled)Print("NeoFL BODY CONNECTED: execution gate is LOCKED.");else Print("NeoFL BODY CONNECTED: execution gate is ENABLED.");return g_authorized;}

string ResolveSymbol(string requested){if(requested!=""&&SymbolSelect(requested,true))return requested;string target=requested;StringToUpper(target);if(target==""||target=="XAUUSD"||target=="GOLD"){int total=SymbolsTotal(false);for(int i=0;i<total;i++){string s=SymbolName(i,false);string u=s;StringToUpper(u);if(u=="GOLD"||StringFind(u,"XAUUSD")>=0)return s;}}return requested;}

string StateSymbol(){string s=MarketSymbol;if(s=="")s=_Symbol;string resolved=ResolveSymbol(s);if(resolved!="")s=resolved;g_last_market_symbol=s;return s;}

bool SendHeartbeat(){string path=StringFormat("/api/v1/body/heartbeat?account_number=%I64d&server=%s&connector=MT5&environment=%s",g_account,UrlValue(g_server),EnvironmentName());string body;int http=0;if(!HttpGet(path,body,http)){Print("NeoFL body heartbeat failed.");return false;}if(http<200||http>=300){Print("NeoFL body heartbeat rejected. HTTP=",http," response=",body);return false;}return true;}

bool SendTelemetry(){double balance=AccountInfoDouble(ACCOUNT_BALANCE);double equity=AccountInfoDouble(ACCOUNT_EQUITY);double profit=AccountInfoDouble(ACCOUNT_PROFIT);double drawdown=MathMax(0.0,balance-equity);int open=PositionsTotal();string path=StringFormat("/api/v1/body/telemetry?account_number=%I64d&server=%s&connector=MT5&environment=%s&balance=%.8f&equity=%.8f&profit=%.8f&drawdown=%.8f&open_trades=%d&ea_status=ONLINE",g_account,UrlValue(g_server),EnvironmentName(),balance,equity,profit,drawdown,open);string body;int http=0;if(!HttpGet(path,body,http)){Print("NeoFL body telemetry request failed.");return false;}if(http<200||http>=300){Print("NeoFL body telemetry rejected. HTTP=",http," response=",body);return false;}return true;}

bool SendMarketState(){string symbol=StateSymbol();if(symbol=="")return false;MqlTick tick;if(!SymbolInfoTick(symbol,tick))return false;int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);double point=SymbolInfoDouble(symbol,SYMBOL_POINT);datetime m5_time=iTime(symbol,PERIOD_M5,0);datetime h1_time=iTime(symbol,PERIOD_H1,0);double m5_open=iOpen(symbol,PERIOD_M5,0),m5_high=iHigh(symbol,PERIOD_M5,0),m5_low=iLow(symbol,PERIOD_M5,0),m5_close=iClose(symbol,PERIOD_M5,0);double h1_open=iOpen(symbol,PERIOD_H1,0),h1_high=iHigh(symbol,PERIOD_H1,0),h1_low=iLow(symbol,PERIOD_H1,0),h1_close=iClose(symbol,PERIOD_H1,0);string path=StringFormat("/api/v1/body/market-state?account_number=%I64d&server=%s&connector=MT5&environment=%s&symbol=%s&bid=%.10f&ask=%.10f&spread=%.10f&digits=%d&point=%.10f&time=%s&timeframe=M5&m5_time=%s&m5_open=%.10f&m5_high=%.10f&m5_low=%.10f&m5_close=%.10f&h1_time=%s&h1_open=%.10f&h1_high=%.10f&h1_low=%.10f&h1_close=%.10f",g_account,UrlValue(g_server),EnvironmentName(),UrlValue(symbol),tick.bid,tick.ask,(tick.ask-tick.bid),digits,point,UrlValue(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)),UrlValue(TimeToString(m5_time,TIME_DATE|TIME_SECONDS)),m5_open,m5_high,m5_low,m5_close,UrlValue(TimeToString(h1_time,TIME_DATE|TIME_SECONDS)),h1_open,h1_high,h1_low,h1_close);string body;int http=0;if(!HttpGet(path,body,http)){Print("NeoFL market-state request failed.");return false;}if(http<200||http>=300){Print("NeoFL market-state rejected. HTTP=",http," response=",body);return false;}return true;}

bool Report(string intent_id,string status,double filled,double price,string broker_order_id,string rejection){string path=StringFormat("/api/v1/execution-report?account_number=%I64d&intent_id=%s&adapter=MT5&status=%s&filled_quantity=%.8f&average_fill_price=%.8f&broker_order_id=%s&rejection_code=%s",g_account,UrlValue(intent_id),UrlValue(status),filled,price,UrlValue(broker_order_id),UrlValue(rejection));string body;int http=0;if(!HttpGet(path,body,http))return false;if(http<200||http>=300){Print("NeoFL execution report rejected. HTTP=",http," response=",body);return false;}return true;}

void ProcessIntent(){if(!g_authorized||!g_execution_enabled)return;string body;int http=0;string path=StringFormat("/api/v1/execution/next?account_number=%I64d",g_account);if(!HttpGet(path,body,http)||http<200||http>=300)return;if(StringFind(body,"\"available\":true")<0)return;string intent_id=JsonString(body,"id");string symbol_requested=JsonString(body,"symbol");string direction=JsonString(body,"direction");double volume=JsonNumber(body,"quantity",0.0);double sl=JsonNumber(body,"stop",0.0);double tp=JsonNumber(body,"target",0.0);string symbol=ResolveSymbol(symbol_requested);if(intent_id==""||symbol==""||volume<=0){Report(intent_id,"REJECTED",0,0,"","INVALID_INTENT");return;}g_trade.SetDeviationInPoints(MaxDeviationPoints);bool ok=false;if(direction=="BUY")ok=g_trade.Buy(volume,symbol,0.0,sl,tp,"NeoFL:"+intent_id);else if(direction=="SELL")ok=g_trade.Sell(volume,symbol,0.0,sl,tp,"NeoFL:"+intent_id);else{Report(intent_id,"REJECTED",0,0,"","UNSUPPORTED_DIRECTION");return;}if(ok){ulong ticket=g_trade.ResultOrder();string broker_order_id=StringFormat("%I64u",ticket);double fill=g_trade.ResultPrice();Report(intent_id,"FILLED",volume,fill,broker_order_id,"");Print("NeoFL execution completed: intent=",intent_id," symbol=",symbol," volume=",volume," price=",fill);}else{Report(intent_id,"REJECTED",0,0,"",IntegerToString(g_trade.ResultRetcode()));Print("NeoFL execution rejected: intent=",intent_id," retcode=",g_trade.ResultRetcode()," ",g_trade.ResultRetcodeDescription());}}

int OnInit(){g_account=(long)AccountInfoInteger(ACCOUNT_LOGIN);g_server=AccountInfoString(ACCOUNT_SERVER);if(BaseURL()==""||NeoFL_BINDING_TOKEN==""){Print("NeoFL BLOCKED: configure NeoFL_API_BASE_URL and NeoFL_BINDING_TOKEN.");return INIT_FAILED;}EventSetTimer(MathMax(1,PollIntervalSeconds));Handshake();Print("NeoFL Executioner 4.3 started. Account=",g_account," Server=",g_server);return INIT_SUCCEEDED;}
void OnDeinit(const int reason){EventKillTimer();}
void OnTick(){ }
void OnTimer(){if(!Handshake())return;SendHeartbeat();SendTelemetry();SendMarketState();ProcessIntent();}
