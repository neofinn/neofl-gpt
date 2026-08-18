#property strict
#property version "3.00"
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int StopLossPoints=800,TakeProfitPoints=1600,MaxPositions=1;
input ulong Magic=30001; input int DeviationPoints=30;
input int USOpenHourET=9,USOpenMinuteET=30,USCloseHourET=16,USCloseMinuteET=0;
input int FastEMA=20,SlowEMA=50,RSIPeriod=14;
input bool RequireEMAConfirmation=true,RequireM5CHoCH=true,CloseOnOppositeBreak=true;
int hf,hs,hr; datetime sd=0; double hi=0,lo=0; bool ready=false; int bias=0;
bool DST(datetime g){MqlDateTime d,x;TimeToStruct(g,d);int y=d.year;ZeroMemory(x);x.year=y;x.mon=3;x.day=1;x.hour=7;datetime a=StructToTime(x);TimeToStruct(a,d);int ss=1+(7-d.day_of_week)%7+7;ZeroMemory(x);x.year=y;x.mon=11;x.day=1;x.hour=6;datetime b=StructToTime(x);TimeToStruct(b,d);int fs=1+(7-d.day_of_week)%7;ZeroMemory(x);x.year=y;x.mon=3;x.day=ss;x.hour=7;datetime st=StructToTime(x);ZeroMemory(x);x.year=y;x.mon=11;x.day=fs;x.hour=6;datetime en=StructToTime(x);return g>=st&&g<en;}
datetime NY(){datetime g=TimeGMT();return g+(DST(g)?-4:-5)*3600;}
bool Session(datetime &n){n=NY();MqlDateTime d;TimeToStruct(n,d);if(d.day_of_week==0||d.day_of_week==6)return false;int q=d.hour*60+d.min;return q>=USOpenHourET*60+USOpenMinuteET&&q<USCloseHourET*60+USCloseMinuteET;}
datetime Day(datetime t){MqlDateTime d;TimeToStruct(t,d);d.hour=0;d.min=0;d.sec=0;return StructToTime(d);}
double V(int h){double b[];ArraySetAsSeries(b,true);return CopyBuffer(h,0,1,1,b)==1?b[0]:EMPTY_VALUE;}
int C(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t&&PositionGetString(POSITION_SYMBOL)==_Symbol&&(ulong)PositionGetInteger(POSITION_MAGIC)==Magic)n++;}return n;}
void CloseOpp(int dir){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(!t||PositionGetString(POSITION_SYMBOL)!=_Symbol||(ulong)PositionGetInteger(POSITION_MAGIC)!=Magic)continue;long ty=PositionGetInteger(POSITION_TYPE);if((dir==1&&ty==POSITION_TYPE_SELL)||(dir==-1&&ty==POSITION_TYPE_BUY))trade.PositionClose(t);}}
void Open(int dir){double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),a=SymbolInfoDouble(_Symbol,SYMBOL_ASK),b=SymbolInfoDouble(_Symbol,SYMBOL_BID);if(dir==1)trade.Buy(Lots,_Symbol,0,NormalizeDouble(a-StopLossPoints*p,d),NormalizeDouble(a+TakeProfitPoints*p,d),"NeoFL ARK");else trade.Sell(Lots,_Symbol,0,NormalizeDouble(b+StopLossPoints*p,d),NormalizeDouble(b-TakeProfitPoints*p,d),"NeoFL ARK");}
int OnInit(){hf=iMA(_Symbol,PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE);hs=iMA(_Symbol,PERIOD_M5,SlowEMA,0,MODE_EMA,PRICE_CLOSE);hr=iRSI(_Symbol,PERIOD_M5,RSIPeriod,PRICE_CLOSE);trade.SetExpertMagicNumber(Magic);trade.SetDeviationInPoints(DeviationPoints);return(hf<0||hs<0||hr<0)?INIT_FAILED:INIT_SUCCEEDED;}
void OnDeinit(const int r){IndicatorRelease(hf);IndicatorRelease(hs);IndicatorRelease(hr);}
void OnTick(){datetime n;if(!Session(n))return;datetime d=Day(n);if(d!=sd){sd=d;hi=lo=0;ready=false;bias=0;}MqlDateTime x;TimeToStruct(n,x);int q=x.hour*60+x.min,op=USOpenHourET*60+USOpenMinuteET;if(q>=op+15&&!ready){MqlRates r[];ArraySetAsSeries(r,true);if(CopyRates(_Symbol,PERIOD_M15,1,1,r)==1){hi=r[0].high;lo=r[0].low;ready=true;}}if(!ready)return;static datetime last=0;MqlRates m[];ArraySetAsSeries(m,true);if(CopyRates(_Symbol,PERIOD_M5,1,3,m)<3||m[0].time==last)return;last=m[0].time;int br=m[0].close>hi?1:(m[0].close<lo?-1:0);if(!br)return;if(bias==0)bias=br;else if(br!=bias){if(CloseOnOppositeBreak)CloseOpp(br);bias=br;}double f=V(hf),s=V(hs),r=V(hr);int e=f>s?1:(f<s?-1:0);if(RequireEMAConfirmation&&e!=bias)return;if((bias==1&&r<50)||(bias==-1&&r>50))return;if(C()>=MaxPositions)return;Open(bias);}
