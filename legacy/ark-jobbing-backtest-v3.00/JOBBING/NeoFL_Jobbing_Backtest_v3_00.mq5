#property strict
#property version "3.00"
#include <Trade/Trade.mqh>
CTrade trade;
input double Lots=0.10;
input int StopLossPoints=250,TakeProfitPoints=350,MaxHoldSeconds=60,CooldownSeconds=10,MaxPositions=1;
input ulong Magic=30002; input int DeviationPoints=30;
input int USOpenHourET=9,USOpenMinuteET=30,USCloseHourET=16,USCloseMinuteET=0;
input int FastEMA=5,SlowEMA=13,RSIPeriod=7,ATRPeriod=14;
input double MinImpulseATR=0.08,MaxSpreadPoints=80,MicroBreakPoints=5;
int hf,hs,hr,ha; datetime cd=0,cool=0; int lastMicro=0; double lastBid=0;
bool DST(datetime g){MqlDateTime d,x;TimeToStruct(g,d);int y=d.year;ZeroMemory(x);x.year=y;x.mon=3;x.day=1;x.hour=7;datetime a=StructToTime(x);TimeToStruct(a,d);int ss=1+(7-d.day_of_week)%7+7;ZeroMemory(x);x.year=y;x.mon=11;x.day=1;x.hour=6;datetime b=StructToTime(x);TimeToStruct(b,d);int fs=1+(7-d.day_of_week)%7;ZeroMemory(x);x.year=y;x.mon=3;x.day=ss;x.hour=7;datetime st=StructToTime(x);ZeroMemory(x);x.year=y;x.mon=11;x.day=fs;x.hour=6;datetime en=StructToTime(x);return g>=st&&g<en;}
datetime NY(){datetime g=TimeGMT();return g+(DST(g)?-4:-5)*3600;}
bool Session(datetime &n){n=NY();MqlDateTime d;TimeToStruct(n,d);if(d.day_of_week==0||d.day_of_week==6)return false;int q=d.hour*60+d.min;return q>=USOpenHourET*60+USOpenMinuteET&&q<USCloseHourET*60+USCloseMinuteET;}
double V(int h){double b[];ArraySetAsSeries(b,true);return CopyBuffer(h,0,1,1,b)==1?b[0]:EMPTY_VALUE;}
int C(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t&&PositionGetString(POSITION_SYMBOL)==_Symbol&&(ulong)PositionGetInteger(POSITION_MAGIC)==Magic)n++;}return n;}
void Manage(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(!t||PositionGetString(POSITION_SYMBOL)!=_Symbol||(ulong)PositionGetInteger(POSITION_MAGIC)!=Magic)continue;if(TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME)>=MaxHoldSeconds){trade.PositionClose(t);cool=TimeCurrent()+CooldownSeconds;lastMicro=0;}}}
void Open(int d){double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);int dg=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);double a=SymbolInfoDouble(_Symbol,SYMBOL_ASK),b=SymbolInfoDouble(_Symbol,SYMBOL_BID);if(d==1)trade.Buy(Lots,_Symbol,0,NormalizeDouble(a-StopLossPoints*p,dg),NormalizeDouble(a+TakeProfitPoints*p,dg),"NeoFL Job");else trade.Sell(Lots,_Symbol,0,NormalizeDouble(b+StopLossPoints*p,dg),NormalizeDouble(b-TakeProfitPoints*p,dg),"NeoFL Job");}
int OnInit(){hf=iMA(_Symbol,PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE);hs=iMA(_Symbol,PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE);hr=iRSI(_Symbol,PERIOD_M1,RSIPeriod,PRICE_CLOSE);ha=iATR(_Symbol,PERIOD_M1,ATRPeriod);trade.SetExpertMagicNumber(Magic);trade.SetDeviationInPoints(DeviationPoints);return(hf<0||hs<0||hr<0||ha<0)?INIT_FAILED:INIT_SUCCEEDED;}
void OnDeinit(const int r){IndicatorRelease(hf);IndicatorRelease(hs);IndicatorRelease(hr);IndicatorRelease(ha);}
void OnTick(){datetime n;if(!Session(n))return;Manage();if(C()||TimeCurrent()<cool)return;MqlTick t;if(!SymbolInfoTick(_Symbol,t))return;double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT),sp=(t.ask-t.bid)/p;if(sp>MaxSpreadPoints||p<=0)return;int micro=0;if(lastBid>0){double z=(t.bid-lastBid)/p;if(z>=MicroBreakPoints)micro=1;else if(z<=-MicroBreakPoints)micro=-1;}lastBid=t.bid;if(!micro||micro==lastMicro)return;lastMicro=micro;double f=V(hf),s=V(hs),r=V(hr),a=V(ha);int trend=f>s?1:(f<s?-1:0);if(micro!=trend||a<=0)return;MqlRates q[];ArraySetAsSeries(q,true);if(CopyRates(_Symbol,PERIOD_M1,0,1,q)<1)return;if(MathAbs(q[0].close-q[0].open)/a<MinImpulseATR)return;if((trend==1&&r<52)||(trend==-1&&r>48))return;Open(trend);}
