//+------------------------------------------------------------------+
//| NeoFL_Session.mqh                                                |
//| Core module. Trading sessions and US market timing.              |
//| Answers "is the market in session?" -- never "should we trade?"  |
//+------------------------------------------------------------------+
//
// Canon: Jobbing must have a dedicated US-session timing module rather than
// relying on arbitrary broker/server times, and session rules are a shared
// service rather than something each EA reimplements.
//
// The problem this solves: broker server time is arbitrary. The same UTC instant
// is 09:30 on one broker's clock and 16:30 on another's. Anything keyed to the US
// open must be computed from an absolute reference, which here is GMT, with US
// Eastern DST derived rather than assumed.
//
// US Eastern DST (post-2007 rule):
//     starts  second Sunday in March,    02:00 local (07:00 GMT, EST = GMT-5)
//     ends    first  Sunday in November, 02:00 local (06:00 GMT, EDT = GMT-4)
//
#ifndef __NEOFL_SESSION_MQH__
#define __NEOFL_SESSION_MQH__

#include "../NeoFL_DataValidation/NeoFL_DataQuality.mqh"

//--- US cash equity session, Eastern time.
int NeoFLSess_UsOpenHourET()    { return 9;  }
int NeoFLSess_UsOpenMinuteET()  { return 30; }
int NeoFLSess_UsCloseHourET()   { return 16; }
int NeoFLSess_UsCloseMinuteET() { return 0;  }

//+------------------------------------------------------------------+
//| Nth given weekday of a month, as a day-of-month.                 |
//| dow: 0=Sunday. nth: 1=first.                                      |
//+------------------------------------------------------------------+
int NeoFLSess_NthWeekdayOfMonth(const int year, const int month, const int dow, const int nth)
{
   MqlDateTime t;
   ZeroMemory(t);
   t.year = year; t.mon = month; t.day = 1; t.hour = 12;
   const datetime first = StructToTime(t);

   MqlDateTime firstStruct;
   TimeToStruct(first, firstStruct);

   // Days to advance from the 1st to reach the first `dow`.
   const int offset = (dow - firstStruct.day_of_week + 7) % 7;
   return 1 + offset + (nth - 1) * 7;
}

//+------------------------------------------------------------------+
//| Is the given GMT time inside US Eastern daylight saving?          |
//+------------------------------------------------------------------+
bool NeoFLSess_IsUsDst(const datetime gmt)
{
   MqlDateTime g;
   TimeToStruct(gmt, g);
   const int year = g.year;

   // Second Sunday in March, 07:00 GMT (02:00 EST).
   const int startDay = NeoFLSess_NthWeekdayOfMonth(year, 3, 0, 2);
   MqlDateTime s; ZeroMemory(s);
   s.year = year; s.mon = 3; s.day = startDay; s.hour = 7;
   const datetime dstStart = StructToTime(s);

   // First Sunday in November, 06:00 GMT (02:00 EDT).
   const int endDay = NeoFLSess_NthWeekdayOfMonth(year, 11, 0, 1);
   MqlDateTime e; ZeroMemory(e);
   e.year = year; e.mon = 11; e.day = endDay; e.hour = 6;
   const datetime dstEnd = StructToTime(e);

   return gmt >= dstStart && gmt < dstEnd;
}

//--- Convert a GMT time to US Eastern.
datetime NeoFLSess_GmtToEastern(const datetime gmt)
{
   return gmt + (NeoFLSess_IsUsDst(gmt) ? -4 : -5) * 3600;
}

//--- Current US Eastern time, derived from GMT rather than broker server time.
datetime NeoFLSess_NowEastern()
{
   return NeoFLSess_GmtToEastern(TimeGMT());
}

//+------------------------------------------------------------------+
//| Is this a weekday in US Eastern terms?                            |
//| Note this is calendar-only -- market holidays are the Calendar     |
//| engine's concern, not this one.                                    |
//+------------------------------------------------------------------+
bool NeoFLSess_IsEasternWeekday(const datetime easternTime)
{
   MqlDateTime t;
   TimeToStruct(easternTime, t);
   return t.day_of_week >= 1 && t.day_of_week <= 5;
}

//--- Minutes since midnight, Eastern.
int NeoFLSess_EasternMinuteOfDay(const datetime easternTime)
{
   MqlDateTime t;
   TimeToStruct(easternTime, t);
   return t.hour * 60 + t.min;
}

//+------------------------------------------------------------------+
//| Is the US cash session open at this Eastern time?                 |
//+------------------------------------------------------------------+
bool NeoFLSess_IsUsSessionOpenAt(const datetime easternTime)
{
   if(!NeoFLSess_IsEasternWeekday(easternTime))
      return false;

   const int m     = NeoFLSess_EasternMinuteOfDay(easternTime);
   const int open  = NeoFLSess_UsOpenHourET()  * 60 + NeoFLSess_UsOpenMinuteET();
   const int close = NeoFLSess_UsCloseHourET() * 60 + NeoFLSess_UsCloseMinuteET();
   return m >= open && m < close;
}

bool NeoFLSess_IsUsSessionOpenNow()
{
   return NeoFLSess_IsUsSessionOpenAt(NeoFLSess_NowEastern());
}

//--- Minutes elapsed since the US open; negative before it, on the given day.
int NeoFLSess_MinutesSinceUsOpen(const datetime easternTime)
{
   const int open = NeoFLSess_UsOpenHourET() * 60 + NeoFLSess_UsOpenMinuteET();
   return NeoFLSess_EasternMinuteOfDay(easternTime) - open;
}

//+------------------------------------------------------------------+
//| Has the first M15 candle of the US session completed?             |
//|                                                                   |
//| Jobbing's opening range is that first M15 candle (09:30-09:45),   |
//| so this is true from 09:45 onward. The canon is explicit that the |
//| earlier three-candle concept is obsolete: ONE candle.             |
//+------------------------------------------------------------------+
bool NeoFLSess_OpeningRangeComplete(const datetime easternTime)
{
   if(!NeoFLSess_IsUsSessionOpenAt(easternTime))
      return false;
   return NeoFLSess_MinutesSinceUsOpen(easternTime) >= 15;
}

//--- Start of the Eastern calendar day, for per-day state resets.
datetime NeoFLSess_EasternDayStart(const datetime easternTime)
{
   MqlDateTime t;
   TimeToStruct(easternTime, t);
   t.hour = 0; t.min = 0; t.sec = 0;
   return StructToTime(t);
}

//+------------------------------------------------------------------+
//| Assess session state and return a provenance record (D-002).      |
//| Reports the closed case explicitly: an engine that is silent      |
//| because the market is shut must be distinguishable from one that  |
//| is silent because it is broken.                                   |
//+------------------------------------------------------------------+
NeoFLDecision NeoFLSess_AssessUsSession(const string symbol)
{
   NeoFLDecision d;
   NeoFLDecision_Begin(d, "Session", symbol);

   const datetime gmt     = TimeGMT();
   const datetime eastern = NeoFLSess_GmtToEastern(gmt);
   const bool     dst     = NeoFLSess_IsUsDst(gmt);

   const string inputs = StringFormat("gmt=%s eastern=%s dst=%s offset=UTC%d",
                                      TimeToString(gmt, TIME_DATE | TIME_MINUTES),
                                      TimeToString(eastern, TIME_DATE | TIME_MINUTES),
                                      dst ? "yes" : "no",
                                      dst ? -4 : -5);

   if(!NeoFLSess_IsEasternWeekday(eastern))
   {
      NeoFLDecision_Set(d, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        "weekend in US Eastern terms", inputs);
      return d;
   }

   if(!NeoFLSess_IsUsSessionOpenAt(eastern))
   {
      const int since = NeoFLSess_MinutesSinceUsOpen(eastern);
      NeoFLDecision_Set(d, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        StringFormat("outside US session (%d minutes %s the 09:30 open)",
                                     MathAbs(since), since < 0 ? "before" : "after"),
                        inputs);
      return d;
   }

   if(!NeoFLSess_OpeningRangeComplete(eastern))
   {
      NeoFLDecision_Set(d, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        StringFormat("first M15 candle still forming (%d of 15 minutes)",
                                     NeoFLSess_MinutesSinceUsOpen(eastern)),
                        inputs);
      return d;
   }

   NeoFLDecision_Set(d, NEOFL_VERDICT_PROCEED, NEOFL_DATA_OK,
                     StringFormat("US session open, opening range complete (%d minutes in)",
                                  NeoFLSess_MinutesSinceUsOpen(eastern)),
                     inputs);
   return d;
}

#endif // __NEOFL_SESSION_MQH__
