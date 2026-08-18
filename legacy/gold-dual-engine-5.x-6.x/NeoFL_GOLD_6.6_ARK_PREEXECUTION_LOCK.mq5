//+------------------------------------------------------------------+
//| NeoFL GOLD 6.5 - DUAL ENGINE TREND + ARK + S/D + LIQUIDITY       |
//| Intraday-first architecture                                      |
//| Trend: M5 + synthetic M15 + actual M15 + M30 survival            |
//| Entry/trailing: M1 liquidity sweep                               |
//| ARK: independent M15 event engine; only pauses Trend after fill  |
//+------------------------------------------------------------------+
#property strict
#property version   "6.40"
#property description "NeoFL GOLD 6.5 - Trend + ARK non-colliding dual engine"

#include <Trade/Trade.mqh>

CTrade trade;

//============================== INPUTS ==============================
input string InpTradeComment              = "NeoFL_GOLD_6.4";
input long   InpMagicTrend                = 64001;
input long   InpMagicARK                  = 64002;

input bool   InpEnableTrend               = true;
input bool   InpEnableARK                 = true;
input bool   InpAllowLong                = true;
input bool   InpAllowShort               = true;

input double InpRiskTrendPct              = 0.50;
input double InpRiskARKPct                = 1.00;
input double InpMaxRiskPct                = 1.50;

input int    InpMaxSpreadPoints           = 80;
input int    InpATRPeriod                 = 14;
input int    InpADXPeriod                 = 14;
input double InpMinADX                   = 16.0;

input int    InpFastEMA                   = 9;
input int    InpSlowEMA                   = 21;
input int    InpTrendEMA                  = 50;
input int    InpRSIPeriod                 = 14;
input int    InpMACDFast                  = 12;
input int    InpMACDSlow                  = 26;
input int    InpMACDSignal                = 9;

input double InpMinTrendScore             = 4.0;
input double InpStrongTrendScore          = 6.0;
input double InpMinMomentumScore          = 1.0;

input int    InpSyntheticM15Bars          = 3;      // 3 closed M5 candles
input double InpMinBodyATR                = 0.20;
input double InpLiquidityWickATR          = 0.15;

input int    InpZoneLookback              = 48;
input double InpZoneATRWidth              = 0.60;
input double InpZoneMinImpulseATR         = 1.00;
input int    InpZoneFreshBars             = 80;

input int    InpEntryLookbackM1           = 12;
input double InpSweepATR                  = 0.15;
input double InpSL_ATR                    = 1.25;
input double InpTP_ATR                    = 2.50;
input double InpTrailStartATR             = 0.90;
input double InpTrailATR                  = 0.75;
input double InpBreakEvenATR              = 0.70;

input int    InpMinMinutesBetweenTrades   = 1;
input int    InpTrendCooldownMinutes      = 5;
input int    InpARKCooldownMinutes        = 10;

input double InpARKMinScore               = 4.0;
input double InpARKImpulseATR             = 1.20;
input double InpARKRiskMultiplier         = 2.0;

input bool   InpUseSessionFilter          = false;
input int    InpSessionStartHour          = 7;
input int    InpSessionEndHour            = 22;

input bool   InpVerbose                  = true;

//============================== STATE ================================
datetime g_lastTrendTrade = 0;
datetime g_lastARKTrade   = 0;
datetime g_lastAnyTrade   = 0;
datetime g_lastLog        = 0;
datetime g_sequenceM5Open = 0;
int      g_sequenceDir    = 0;
bool     g_sequenceActive = false;
bool     g_heldIntoNextM5 = false;
bool     g_arkEventReady  = false;
bool     g_arkExecutionLock = false;
datetime g_arkLockBar = 0;
int      g_arkDirection   = 0;
double   g_arkScore       = 0.0;

//============================== HELPERS ==============================
void Log(string s)
{
   if(InpVerbose) Print("NeoFL GOLD 6.5 | ",s);
}

string Norm(string s)
{
   string r="";
   for(int i=0;i<StringLen(s);i++)
   {
      ushort c=StringGetCharacter(s,i);
      if((c>='A' && c<='Z') || (c>='a' && c<='z') || (c>='0' && c<='9'))
         r+=CharToString((uchar)c);
   }
   StringToUpper(r);
   return r;
}

bool IsGoldSymbol(string sym)
{
   string n=Norm(sym);
   // Explicitly reject crypto/other cross symbols such as BTCXAU.
   if(StringFind(n,"BTC")>=0 || StringFind(n,"ETH")>=0 ||
      StringFind(n,"XBT")>=0 || StringFind(n,"CRYPTO")>=0)
      return false;

   if(StringFind(n,"XAUUSD")>=0) return true;
   if(StringFind(n,"GOLD")>=0)   return true;

   return false;
}

bool InSession()
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(),t);

   if(InpSessionStartHour<=InpSessionEndHour)
      return (t.hour>=InpSessionStartHour && t.hour<InpSessionEndHour);

   return (t.hour>=InpSessionStartHour || t.hour<InpSessionEndHour);
}

double PointValue()
{
   return SymbolInfoDouble(_Symbol,SYMBOL_POINT);
}

double NormalizePrice(double p)
{
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return NormalizeDouble(p,digits);
}

double NormalizeVolume(double v)
{
   double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(step<=0) step=minv;
   v=MathMax(minv,MathMin(maxv,v));
   v=MathFloor(v/step)*step;
   return NormalizeDouble(v,2);
}

double SpreadPoints()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   return (ask-bid)/PointValue();
}

bool CooldownOK(datetime lastTrade,int minutes)
{
   if(lastTrade==0) return true;
   return (TimeCurrent()-lastTrade >= minutes*60);
}

bool HasOurPosition(int magic=0)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      long pm=(long)PositionGetInteger(POSITION_MAGIC);
      if(magic==0 || pm==magic) return true;
   }
   return false;
}

bool ARKOwnsTrade()
{
   return HasOurPosition((int)InpMagicARK);
}

bool TrendOwnsTrade()
{
   return HasOurPosition((int)InpMagicTrend);
}

bool AnyOurTrade()
{
   return HasOurPosition(0);
}

bool NewBar(ENUM_TIMEFRAMES tf)
{
   static datetime m5=0,m15=0,m30=0,m1=0;
   datetime t=iTime(_Symbol,tf,0);

   if(tf==PERIOD_M5)
   {
      if(t==m5) return false;
      m5=t; return true;
   }
   if(tf==PERIOD_M15)
   {
      if(t==m15) return false;
      m15=t; return true;
   }
   if(tf==PERIOD_M30)
   {
      if(t==m30) return false;
      m30=t; return true;
   }
   if(tf==PERIOD_M1)
   {
      if(t==m1) return false;
      m1=t; return true;
   }
   return false;
}

double ATR(ENUM_TIMEFRAMES tf,int shift=1)
{
   int h=iATR(_Symbol,tf,InpATRPeriod);
   if(h==INVALID_HANDLE) return 0;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,0,shift,1,b)!=1)
   {
      IndicatorRelease(h);
      return 0;
   }
   double x=b[0];
   IndicatorRelease(h);
   return x;
}

double EMA(ENUM_TIMEFRAMES tf,int period,int shift=1)
{
   int h=iMA(_Symbol,tf,period,0,MODE_EMA,PRICE_CLOSE);
   if(h==INVALID_HANDLE) return 0;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,0,shift,1,b)!=1)
   {
      IndicatorRelease(h);
      return 0;
   }
   double x=b[0];
   IndicatorRelease(h);
   return x;
}

double RSI(ENUM_TIMEFRAMES tf,int shift=1)
{
   int h=iRSI(_Symbol,tf,InpRSIPeriod,PRICE_CLOSE);
   if(h==INVALID_HANDLE) return 50;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,0,shift,1,b)!=1)
   {
      IndicatorRelease(h);
      return 50;
   }
   double x=b[0];
   IndicatorRelease(h);
   return x;
}

double ADX(ENUM_TIMEFRAMES tf,int shift=1)
{
   int h=iADX(_Symbol,tf,InpADXPeriod);
   if(h==INVALID_HANDLE) return 0;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,0,shift,1,b)!=1)
   {
      IndicatorRelease(h);
      return 0;
   }
   double x=b[0];
   IndicatorRelease(h);
   return x;
}

double MACDMain(ENUM_TIMEFRAMES tf,int shift=1)
{
   int h=iMACD(_Symbol,tf,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE);
   if(h==INVALID_HANDLE) return 0;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,0,shift,1,b)!=1)
   {
      IndicatorRelease(h);
      return 0;
   }
   double x=b[0];
   IndicatorRelease(h);
   return x;
}

double MACDSignal(ENUM_TIMEFRAMES tf,int shift=1)
{
   int h=iMACD(_Symbol,tf,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE);
   if(h==INVALID_HANDLE) return 0;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,1,shift,1,b)!=1)
   {
      IndicatorRelease(h);
      return 0;
   }
   double x=b[0];
   IndicatorRelease(h);
   return x;
}

int CandleDir(ENUM_TIMEFRAMES tf,int shift)
{
   double o=iOpen(_Symbol,tf,shift);
   double c=iClose(_Symbol,tf,shift);
   if(c>o) return 1;
   if(c<o) return -1;
   return 0;
}

double CandleBody(ENUM_TIMEFRAMES tf,int shift)
{
   return MathAbs(iClose(_Symbol,tf,shift)-iOpen(_Symbol,tf,shift));
}

double HighestHigh(ENUM_TIMEFRAMES tf,int startShift,int count)
{
   double x=-DBL_MAX;
   for(int i=startShift;i<startShift+count;i++)
      x=MathMax(x,iHigh(_Symbol,tf,i));
   return x;
}

double LowestLow(ENUM_TIMEFRAMES tf,int startShift,int count)
{
   double x=DBL_MAX;
   for(int i=startShift;i<startShift+count;i++)
      x=MathMin(x,iLow(_Symbol,tf,i));
   return x;
}

//=========================== SYNTHETIC M15 ===========================
int SyntheticM15Direction(double &strength)
{
   strength=0;
   double atr=ATR(PERIOD_M5,1);
   if(atr<=0) return 0;

   int bull=0,bear=0;
   double net=0;

   for(int i=1;i<=InpSyntheticM15Bars;i++)
   {
      int d=CandleDir(PERIOD_M5,i);
      if(d>0) bull++;
      if(d<0) bear++;

      double body=CandleBody(PERIOD_M5,i);
      net += d*MathMin(1.5,body/atr);
   }

   strength=MathAbs(net);

   if(bull>=2 && net>0.70) return 1;
   if(bear>=2 && net<-0.70) return -1;

   return 0;
}


//====================== M5 SEQUENCE / RIDE LOGIC =====================
// Two closed M5 candles establish direction.
// The third M5 candle is the execution candle and is decomposed into M1.
// A Trend trade is allowed only in the same direction as the sequence.
// The position is managed tick-by-tick with the M1 trailing engine.
// At the third M5 close, continuation into the fourth M5 is allowed only
// if the trailing stop has reached a profitable (locked-in) level.

int M5DirectionalSequence()
{
   int d1=CandleDir(PERIOD_M5,1);
   int d2=CandleDir(PERIOD_M5,2);

   if(d1!=0 && d1==d2) return d1;
   return 0;
}

bool PositionHasLockedProfit(int magic)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;

      long type=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);

      if(sl==0) return false;

      if(type==POSITION_TYPE_BUY && sl>open) return true;
      if(type==POSITION_TYPE_SELL && sl<open) return true;
   }
   return false;
}

bool PositionStillDirectional(int direction,int magic)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;

      long type=PositionGetInteger(POSITION_TYPE);
      if(direction>0 && type==POSITION_TYPE_BUY) return true;
      if(direction<0 && type==POSITION_TYPE_SELL) return true;
   }
   return false;
}

void ManageThirdToFourthM5()
{
   // Only Trend positions participate in this M5 sequence rule.
   if(!TrendOwnsTrade()) return;

   int d=M5DirectionalSequence();

   // At the opening of a new M5 candle, the previous M5 candle has closed.
   // If the two latest closed M5 candles are still directional, check whether
   // the existing trade earned a locked-profit trailing stop.
   if(d==0)
   {
      // The sequence broke. Do not force continuation.
      if(!PositionHasLockedProfit((int)InpMagicTrend))
      {
         Log("M5 SEQUENCE BROKEN | no locked profit | closing Trend trade");
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong ticket=PositionGetTicket(i);
            if(ticket==0) continue;
            if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
            if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicTrend) continue;
            trade.PositionClose(ticket);
         }
      }
      return;
   }

   bool locked=PositionHasLockedProfit((int)InpMagicTrend);

   if(locked)
   {
      g_heldIntoNextM5=true;
      Log(StringFormat("M5 CONTINUATION | direction=%d | trailing locked profit | 4th M5 allowed",d));
   }
   else
   {
      g_heldIntoNextM5=false;
      Log("M5 CONTINUATION BLOCKED | trailing has not locked profit | close Trend trade");
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicTrend) continue;
         trade.PositionClose(ticket);
      }
   }
}

//============================= TREND =================================
int TrendTF(ENUM_TIMEFRAMES tf,double &score)
{
   score=0;

   double close=iClose(_Symbol,tf,1);
   double e9=EMA(tf,InpFastEMA,1);
   double e21=EMA(tf,InpSlowEMA,1);
   double e50=EMA(tf,InpTrendEMA,1);
   double rsi=RSI(tf,1);
   double adx=ADX(tf,1);
   double mm=MACDMain(tf,1);
   double ms=MACDSignal(tf,1);

   if(close<=0 || e9<=0 || e21<=0 || e50<=0) return 0;

   if(e9>e21) score+=1.0; else if(e9<e21) score-=1.0;
   if(e21>e50) score+=1.0; else if(e21<e50) score-=1.0;
   if(close>e9) score+=1.0; else if(close<e9) score-=1.0;

   if(rsi>55) score+=1.0;
   else if(rsi<45) score-=1.0;

   if(mm>ms) score+=1.0;
   else if(mm<ms) score-=1.0;

   if(mm>0) score+=0.5;
   else if(mm<0) score-=0.5;

   if(adx>=InpMinADX)
   {
      if(score>0) score+=0.5;
      if(score<0) score-=0.5;
   }

   if(score>=InpMinTrendScore) return 1;
   if(score<=-InpMinTrendScore) return -1;
   return 0;
}

int M5Pressure(double &score)
{
   score=0;
   double atr=ATR(PERIOD_M5,1);
   if(atr<=0) return 0;

   for(int i=1;i<=3;i++)
   {
      int d=CandleDir(PERIOD_M5,i);
      double body=CandleBody(PERIOD_M5,i);
      double w=body/atr;

      if(d>0) score+=MathMin(1.5,w);
      if(d<0) score-=MathMin(1.5,w);
   }

   if(score>=InpMinMomentumScore) return 1;
   if(score<=-InpMinMomentumScore) return -1;
   return 0;
}

int CombinedTrend(double &score,double &m5s,double &m15s,double &m30s,double &syns)
{
   score=0;
   m5s=m15s=m30s=syns=0;

   int d5=TrendTF(PERIOD_M5,m5s);
   int d15=TrendTF(PERIOD_M15,m15s);
   int d30=TrendTF(PERIOD_M30,m30s);
   int ds=SyntheticM15Direction(syns);
   int dp=M5Pressure(score);

   // Intraday-first weighting. M5 + synthetic M15 dominate.
   double total = m5s*1.60 + syns*1.35 + m15s*1.25 + m30s*0.75 + score*0.80;
   score=total;

   if(total>=InpStrongTrendScore) return 1;
   if(total<=-InpStrongTrendScore) return -1;

   // Early intraday qualification: 3 M5 candles + actual M15 agreement.
   if(ds!=0 && d15==ds && dp==ds)
      return ds;

   // Strong M5 + M15 with M30 not yet confirmed is allowed.
   if(d5!=0 && d15==d5 && MathAbs(m5s)>=3.0)
      return d5;

   return 0;
}

//========================= SUPPLY / DEMAND ===========================
bool FindZone(int direction,double &zoneLow,double &zoneHigh,double &quality)
{
   zoneLow=0; zoneHigh=0; quality=0;

   double atr=ATR(PERIOD_M15,1);
   if(atr<=0) return false;

   double bestQ=-DBL_MAX;
   int bestShift=-1;

   // Demand: bullish impulse originating from a low.
   // Supply: bearish impulse originating from a high.
   for(int s=2;s<=InpZoneLookback;s++)
   {
      double o=iOpen(_Symbol,PERIOD_M15,s);
      double c=iClose(_Symbol,PERIOD_M15,s);
      double hi=iHigh(_Symbol,PERIOD_M15,s);
      double lo=iLow(_Symbol,PERIOD_M15,s);
      double body=MathAbs(c-o);

      if(body < atr*InpZoneMinImpulseATR) continue;

      double priorHi=HighestHigh(PERIOD_M15,s+1,4);
      double priorLo=LowestLow(PERIOD_M15,s+1,4);

      if(direction<0 && c<o && c<priorLo)
      {
         double q=body/atr;
         if(q>bestQ && s<=InpZoneFreshBars)
         {
            bestQ=q;
            bestShift=s;
            zoneLow=MathMin(o,c)-atr*0.10;
            zoneHigh=MathMax(o,c)+atr*InpZoneATRWidth;
         }
      }

      if(direction>0 && c>o && c>priorHi)
      {
         double q=body/atr;
         if(q>bestQ && s<=InpZoneFreshBars)
         {
            bestQ=q;
            bestShift=s;
            zoneLow=MathMin(o,c)-atr*InpZoneATRWidth;
            zoneHigh=MathMax(o,c)+atr*0.10;
         }
      }
   }

   if(bestShift<0) return false;

   // Freshness/untested approximation: price must not have crossed the zone
   // since the impulse candle.
   int bars=iBars(_Symbol,PERIOD_M15);
   if(bestShift>=bars-1) return false;

   double current=iClose(_Symbol,PERIOD_M15,1);
   if(direction<0 && current>zoneHigh) { /* may be approaching supply */ }
   if(direction>0 && current<zoneLow)  { /* may be approaching demand */ }

   quality=bestQ;
   return true;
}

bool PriceNearZone(int direction,double low,double high,double atr)
{
   double p=(SymbolInfoDouble(_Symbol,SYMBOL_BID)+SymbolInfoDouble(_Symbol,SYMBOL_ASK))/2.0;
   double buffer=atr*0.50;

   if(p>=low-buffer && p<=high+buffer) return true;

   // Do not require the zone to be touched if price is breaking away strongly.
   if(direction<0 && p>high && p-high<=atr*0.80) return true;
   if(direction>0 && p<low && low-p<=atr*0.80) return true;

   return false;
}

//=========================== M1 LIQUIDITY ============================
bool LiquiditySweep(int direction,double &sweepLevel)
{
   sweepLevel=0;
   double atr=ATR(PERIOD_M1,1);
   if(atr<=0) return false;

   double priorHigh=HighestHigh(PERIOD_M1,2,InpEntryLookbackM1);
   double priorLow =LowestLow(PERIOD_M1,2,InpEntryLookbackM1);

   double h=iHigh(_Symbol,PERIOD_M1,1);
   double l=iLow(_Symbol,PERIOD_M1,1);
   double o=iOpen(_Symbol,PERIOD_M1,1);
   double c=iClose(_Symbol,PERIOD_M1,1);

   if(direction<0)
   {
      // Buy-side liquidity sweep: take prior highs, close back below.
      if(h>priorHigh+atr*InpSweepATR && c<priorHigh && c<o)
      {
         sweepLevel=h;
         return true;
      }
   }
   else
   {
      // Sell-side liquidity sweep: take prior lows, close back above.
      if(l<priorLow-atr*InpSweepATR && c>priorLow && c>o)
      {
         sweepLevel=l;
         return true;
      }
   }

   return false;
}

bool M1MicroConfirmation(int direction)
{
   double atr=ATR(PERIOD_M1,1);
   if(atr<=0) return false;

   double c1=iClose(_Symbol,PERIOD_M1,1);
   double c2=iClose(_Symbol,PERIOD_M1,2);
   double body=CandleBody(PERIOD_M1,1);

   if(direction<0)
      return (c1<c2 && body>=atr*InpMinBodyATR);

   return (c1>c2 && body>=atr*InpMinBodyATR);
}

//============================== ARK =================================
bool DetectARKEvent(int &direction,double &score)
{
   direction=0;
   score=0;

   double atr=ATR(PERIOD_M15,1);
   if(atr<=0) return false;

   // ARK is event-driven: displacement + liquidity sweep + structure change.
   double h1=iHigh(_Symbol,PERIOD_M15,1);
   double l1=iLow(_Symbol,PERIOD_M15,1);
   double o1=iOpen(_Symbol,PERIOD_M15,1);
   double c1=iClose(_Symbol,PERIOD_M15,1);

   double range=h1-l1;
   double priorHigh=HighestHigh(PERIOD_M15,2,8);
   double priorLow =LowestLow(PERIOD_M15,2,8);

   if(range<atr*InpARKImpulseATR) return false;

   bool bearishSweep=(h1>priorHigh && c1<o1 && c1<priorHigh);
   bool bullishSweep=(l1<priorLow && c1>o1 && c1>priorLow);

   double adx=ADX(PERIOD_M15,1);
   double mac=MACDMain(PERIOD_M15,1);
   double sig=MACDSignal(PERIOD_M15,1);

   if(bearishSweep)
   {
      score=2.0 + MathMin(2.0,range/atr-1.0);
      if(mac<sig) score+=1.0;
      if(adx>=InpMinADX) score+=1.0;
      direction=-1;
   }
   else if(bullishSweep)
   {
      score=2.0 + MathMin(2.0,range/atr-1.0);
      if(mac>sig) score+=1.0;
      if(adx>=InpMinADX) score+=1.0;
      direction=1;
   }

   return (direction!=0 && score>=InpARKMinScore);
}

//=========================== RISK / ORDER ============================
double CalcLots(double riskPct,double slDistance)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney=equity*(MathMin(riskPct,InpMaxRiskPct)/100.0);

   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);

   if(tickSize<=0 || tickValue<=0 || slDistance<=0) return 0;

   double lossPerLot=(slDistance/tickSize)*tickValue;
   if(lossPerLot<=0) return 0;

   return NormalizeVolume(riskMoney/lossPerLot);
}

bool StopsValid(int direction,double entry,double sl,double tp)
{
   int stops=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist=stops*PointValue();

   if(direction>0)
      return ((entry-sl)>=minDist && (tp-entry)>=minDist);

   return ((sl-entry)>=minDist && (entry-tp)>=minDist);
}

bool OpenTrade(int direction,bool ark)
{
   if(direction==0) return false;
   if(direction>0 && !InpAllowLong) return false;
   if(direction<0 && !InpAllowShort) return false;

   if(!InSession()) return false;
   if(SpreadPoints()>InpMaxSpreadPoints) return false;

   if(AnyOurTrade()) return false;

   int cooldown=ark?InpARKCooldownMinutes:InpTrendCooldownMinutes;
   if(!CooldownOK(g_lastAnyTrade,InpMinMinutesBetweenTrades)) return false;
   if(ark && !CooldownOK(g_lastARKTrade,cooldown)) return false;
   if(!ark && !CooldownOK(g_lastTrendTrade,cooldown)) return false;

   double atr=ATR(PERIOD_M1,1);
   double atrM5=ATR(PERIOD_M5,1);
   if(atr<=0) atr=atrM5;
   if(atr<=0) return false;

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double entry=(direction>0?ask:bid);

   double slDist=atr*InpSL_ATR;
   double tpDist=atr*InpTP_ATR;

   if(ark)
   {
      slDist*=1.10;
      tpDist*=1.20;
   }

   double sl=(direction>0?entry-slDist:entry+slDist);
   double tp=(direction>0?entry+tpDist:entry-tpDist);

   sl=NormalizePrice(sl);
   tp=NormalizePrice(tp);

   if(!StopsValid(direction,entry,sl,tp))
      return false;

   double risk=ark ? MathMin(InpRiskARKPct*InpARKRiskMultiplier,InpMaxRiskPct)
                   : InpRiskTrendPct;

   double lots=CalcLots(risk,MathAbs(entry-sl));
   if(lots<=0) return false;

   trade.SetExpertMagicNumber(ark?InpMagicARK:InpMagicTrend);
   trade.SetDeviationInPoints(20);

   bool ok=false;
   string cmt=ark ? InpTradeComment+"_ARK" : InpTradeComment+"_TREND";

   if(direction>0)
      ok=trade.Buy(lots,_Symbol,0,sl,tp,cmt);
   else
      ok=trade.Sell(lots,_Symbol,0,sl,tp,cmt);

   if(ok)
   {
      datetime now=TimeCurrent();
      g_lastAnyTrade=now;
      if(ark) g_lastARKTrade=now;
      else    g_lastTrendTrade=now;

      Log(StringFormat("%s TRADE OPEN | dir=%d lots=%.2f risk=%.2f%%",
                       ark?"ARK":"TREND",direction,lots,risk));
   }
   else
      Log(StringFormat("%s ORDER FAILED | retcode=%d %s",
                       ark?"ARK":"TREND",
                       trade.ResultRetcode(),
                       trade.ResultRetcodeDescription()));

   return ok;
}

//============================ TRAILING ==============================
void TrailPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      long magic=PositionGetInteger(POSITION_MAGIC);
      if(magic!=InpMagicTrend && magic!=InpMagicARK) continue;

      long type=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double price=(type==POSITION_TYPE_BUY)?
                   SymbolInfoDouble(_Symbol,SYMBOL_BID):
                   SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double atr=ATR(PERIOD_M1,1);
      if(atr<=0) continue;

      double profitDist=(type==POSITION_TYPE_BUY)?price-open:open-price;

      // Break-even
      if(profitDist>=atr*InpBreakEvenATR)
      {
         double be=NormalizePrice(open);
         bool improve=(type==POSITION_TYPE_BUY)?(sl<be || sl==0):(sl>be || sl==0);
         if(improve)
            trade.PositionModify(ticket,be,tp);
      }

      // ATR trailing
      if(profitDist>=atr*InpTrailStartATR)
      {
         double newSL=(type==POSITION_TYPE_BUY)?
                      price-atr*InpTrailATR:
                      price+atr*InpTrailATR;
         newSL=NormalizePrice(newSL);

         bool improve=(type==POSITION_TYPE_BUY)?
                      (newSL>sl && newSL<price):
                      ((sl==0 || newSL<sl) && newSL>price);

         if(improve)
            trade.PositionModify(ticket,newSL,tp);
      }
   }
}


//======================= ARK EXECUTION RESERVATION ===================
// A qualifying ARK event reserves the execution slot BEFORE the order request.
// Trend cannot race ARK on the same M1 bar. If the ARK order fails, the
// reservation lasts for the current M1 bar only.
bool ARKExecutionReserved()
{
   if(!g_arkExecutionLock) return false;
   if(ARKOwnsTrade()) return true;

   datetime curBar=iTime(_Symbol,PERIOD_M1,0);
   if(curBar>0 && curBar==g_arkLockBar) return true;

   g_arkExecutionLock=false;
   return false;
}

//============================= ENGINES ===============================
void RunARK()
{
   if(!InpEnableARK) return;

   int dir=0;
   double score=0;
   bool event=DetectARKEvent(dir,score);

   g_arkEventReady=event;
   g_arkDirection=dir;
   g_arkScore=score;

   if(!event)
   {
      if(ARKOwnsTrade())
         g_arkExecutionLock=true;
      return;
   }

   datetime curBar=iTime(_Symbol,PERIOD_M1,0);

   // Reserve the execution slot BEFORE sending the ARK order.
   g_arkExecutionLock=true;
   g_arkLockBar=curBar;

   Log(StringFormat(
      "ARK M15 EVENT | READY BEFORE EXECUTION | dir=%d score=%.2f | TREND PAUSED BEFORE ORDER",
      dir,score));

   // Never let ARK fight an already-active Trend position.
   if(TrendOwnsTrade())
   {
      Log("ARK EVENT | Trend position already active | ARK waits, no collision");
      return;
   }

   if(!AnyOurTrade())
   {
      bool opened=OpenTrade(dir,true);

      if(opened)
      {
         g_arkExecutionLock=true;
         Log("ARK ORDER EXECUTED | Trend remains paused while ARK position is active");
      }
      else
      {
         Log("ARK ORDER FAILED | Trend remains paused for current M1 bar");
      }
   }
}

void RunTrend()
{
   if(!InpEnableTrend) return;

   // ARK reserves the execution slot BEFORE sending its order.
   // This prevents a Trend order from racing an ARK order on the same M1 bar.
   if(ARKExecutionReserved())
   {
      if(ARKOwnsTrade())
         Log("TREND PAUSED | ARK POSITION ACTIVE");
      else
         Log("TREND PAUSED | ARK PRE-EXECUTION RESERVATION ACTIVE");
      return;
   }

   if(ARKOwnsTrade())
   {
      Log("TREND PAUSED | ARK POSITION ACTIVE");
      return;
   }

   // Core rule:
   // 1) Two closed M5 candles must point in the same direction.
   // 2) The third M5 candle is the execution candle.
   // 3) M1 is used to time the entry inside that third M5 candle.
   // 4) No waiting for a full M15 candle is required for this entry.
   int seqDir=M5DirectionalSequence();

   if(seqDir==0)
   {
      Log(StringFormat("M5 SEQUENCE WAIT | closedM5#1=%d closedM5#2=%d thirdLive=%d",
                    CandleDir(PERIOD_M5,1),
                    CandleDir(PERIOD_M5,2),
                    CandleDir(PERIOD_M5,0)));
      return;
   }

   double total,m5s,m15s,m30s,syns;
   int broadDir=CombinedTrend(total,m5s,m15s,m30s,syns);

   // The two-M5 sequence is the primary intraday trigger. M15/M30 remain
   // confirmation/context rather than a hard blocker for a strong sequence.
   if(broadDir!=0 && broadDir!=seqDir && MathAbs(total)<InpStrongTrendScore)
   {
      Log(StringFormat("M5 SEQUENCE BLOCK | seq=%d broad=%d total=%.2f",seqDir,broadDir,total));
      return;
   }

   // The current (third) M5 candle must be directional in the same direction.
   // It is still forming, so use its live open/current price only for direction.
   double m5Open=iOpen(_Symbol,PERIOD_M5,0);
   double liveBid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double liveAsk=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double liveMid=(liveBid+liveAsk)/2.0;
   int liveDir=(liveMid>m5Open)?1:((liveMid<m5Open)?-1:0);

   if(liveDir!=seqDir)
   {
      Log(StringFormat("M5 THIRD CANDLE WAIT | expected=%d live=%d",seqDir,liveDir));
      return;
   }

   // M1 is the execution layer inside the third M5 candle.
   double sweep=0;
   bool sweepOK=LiquiditySweep(seqDir,sweep);
   bool microOK=M1MicroConfirmation(seqDir);

   double zl,zh,zq;
   bool zone=FindZone(seqDir,zl,zh,zq);

   double atr=ATR(PERIOD_M1,1);
   bool near=(zone && atr>0)?PriceNearZone(seqDir,zl,zh,atr):false;
   bool strong=(MathAbs(total)>=InpStrongTrendScore);

   // Supply/demand improves location, but a strong two-M5 impulse may enter
   // on M1 liquidity without waiting for a perfect zone touch.
   if(sweepOK && microOK && (near || strong))
   {
      Log(StringFormat(
         "M5->M1 ENTRY READY | 2M5 direction=%d | 3rd M5=%d | sweep=1 micro=1 zone=%d",
         seqDir,liveDir,zone?1:0));

      OpenTrade(seqDir,false);
   }
   else
   {
      Log(StringFormat(
         "M5->M1 WAIT | seq=%d third=%d sweep=%d micro=%d zoneNear=%d strong=%d",
         seqDir,liveDir,sweepOK?1:0,microOK?1:0,near?1:0,strong?1:0));
   }
}

//============================== INIT ================================
int OnInit()
{
   if(!IsGoldSymbol(_Symbol))
   {
      Print("NeoFL GOLD 6.5 | INVALID SYMBOL: ",_Symbol,
            " | Allowed: XAUUSD extensions or GOLD variants; BTCXAU/crypto rejected.");
      return INIT_FAILED;
   }

   Log("INITIALIZED | " + _Symbol);
   Log("TREND: M5 + 3xM5 synthetic M15 + actual M15 + M30 survival");
   Log("M1: liquidity sweep + micro confirmation + trailing | 2-M5 setup -> 3rd M5 execution -> 4th M5 profit-lock continuation");
   Log("ARK: independent M15 event engine; Trend pauses BEFORE ARK order and remains paused while ARK is active");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(!IsGoldSymbol(_Symbol)) return;

   TrailPositions();

   // ARK and Trend scan independently on every tick.
   // Execution is evaluated at new M1 bars to avoid duplicate entries.
   if(NewBar(PERIOD_M5))
   {
      // A new M5 means the previous M5 has closed. Decide whether an
      // existing Trend position earned the right to continue into M5 #4.
      ManageThirdToFourthM5();
   }

   if(NewBar(PERIOD_M1))
   {
      RunARK();

      // M1 is only the execution/trailing layer; Trend direction comes from
      // the two closed M5 sequence + current third M5 candle.
      RunTrend();
   }
}
