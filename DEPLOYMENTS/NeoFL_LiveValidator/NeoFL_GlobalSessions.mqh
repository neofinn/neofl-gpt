//+------------------------------------------------------------------+
//| NeoFL_GlobalSessions.mqh                                         |
//| Core module. Global market hours and DST.                        |
//| Reports what is open. Never decides whether to trade.            |
//+------------------------------------------------------------------+
//
// Decision D-003: session timing is a GLOBAL concern. Gold trades in every zone and
// its day runs from the Asian session open to the American session close; each major
// index keeps its own exchange hours rather than borrowing New York's.
//
// Everything is computed in GMT. Broker server time is never trusted.
//
// WHY DST IS THE HARD PART
// ------------------------
// There is no single rule, and one major market has none at all:
//
//     US          second Sunday March    -> first Sunday November
//     EU / UK     last Sunday March      -> last Sunday October
//     Australia   first Sunday October   -> first Sunday April   (southern, inverted)
//     Japan       none
//
// Applying US dates globally is wrong for several weeks a year. In mid-March the US
// has switched and the EU has not; in late October the EU has switched and the US has
// not. During those weeks the London/New York overlap -- the deepest liquidity window
// of the day -- moves by an hour. A single-rule implementation silently trades the
// wrong window and nothing complains.
//
#ifndef __NEOFL_GLOBAL_SESSIONS_MQH__
#define __NEOFL_GLOBAL_SESSIONS_MQH__

#include "NeoFL_DataQuality.mqh"

enum ENUM_NEOFL_DST_RULE
{
   NEOFL_DST_NONE = 0,   // Japan, Hong Kong
   NEOFL_DST_US   = 1,
   NEOFL_DST_EU   = 2,   // also the UK
   NEOFL_DST_AU   = 3    // southern hemisphere, inverted
};

enum ENUM_NEOFL_MARKET
{
   NEOFL_MKT_SYDNEY    = 0,
   NEOFL_MKT_TOKYO     = 1,
   NEOFL_MKT_HONGKONG  = 2,
   NEOFL_MKT_FRANKFURT = 3,
   NEOFL_MKT_LONDON    = 4,
   NEOFL_MKT_NEWYORK   = 5,
   NEOFL_MKT_COUNT     = 6
};

enum ENUM_NEOFL_SESSION
{
   NEOFL_SESSION_ASIAN   = 0,
   NEOFL_SESSION_LONDON  = 1,
   NEOFL_SESSION_NEWYORK = 2,
   NEOFL_SESSION_COUNT   = 3
};

//--- Day-of-month of the nth given weekday. dow: 0=Sunday, nth: 1=first.
int NeoFLGS_NthWeekday(const int year, const int month, const int dow, const int nth)
{
   MqlDateTime t; ZeroMemory(t);
   t.year = year; t.mon = month; t.day = 1; t.hour = 12;
   MqlDateTime f; TimeToStruct(StructToTime(t), f);
   return 1 + (dow - f.day_of_week + 7) % 7 + (nth - 1) * 7;
}

//--- Days in a month, leap years handled.
int NeoFLGS_DaysInMonth(const int year, const int month)
{
   const int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
   if(month == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0))
      return 29;
   return days[month - 1];
}

//--- Day-of-month of the LAST given weekday. Required by the EU/UK rule.
int NeoFLGS_LastWeekday(const int year, const int month, const int dow)
{
   const int last = NeoFLGS_DaysInMonth(year, month);
   MqlDateTime t; ZeroMemory(t);
   t.year = year; t.mon = month; t.day = last; t.hour = 12;
   MqlDateTime f; TimeToStruct(StructToTime(t), f);
   return last - (f.day_of_week - dow + 7) % 7;
}

//--- Build a GMT datetime.
datetime NeoFLGS_Gmt(const int year, const int month, const int day, const int hour)
{
   MqlDateTime t; ZeroMemory(t);
   t.year = year; t.mon = month; t.day = day; t.hour = hour;
   return StructToTime(t);
}

//+------------------------------------------------------------------+
//| Is daylight saving active for this rule at this GMT instant?      |
//+------------------------------------------------------------------+
bool NeoFLGS_IsDst(const ENUM_NEOFL_DST_RULE rule, const datetime gmt)
{
   if(rule == NEOFL_DST_NONE)
      return false;

   MqlDateTime g; TimeToStruct(gmt, g);
   const int y = g.year;

   if(rule == NEOFL_DST_US)
   {
      // 02:00 local: 07:00 GMT starting (EST -5), 06:00 GMT ending (EDT -4).
      const datetime start = NeoFLGS_Gmt(y, 3,  NeoFLGS_NthWeekday(y, 3, 0, 2), 7);
      const datetime end   = NeoFLGS_Gmt(y, 11, NeoFLGS_NthWeekday(y, 11, 0, 1), 6);
      return gmt >= start && gmt < end;
   }

   if(rule == NEOFL_DST_EU)
   {
      // 01:00 GMT on both boundaries, by definition of the EU directive.
      const datetime start = NeoFLGS_Gmt(y, 3,  NeoFLGS_LastWeekday(y, 3, 0), 1);
      const datetime end   = NeoFLGS_Gmt(y, 10, NeoFLGS_LastWeekday(y, 10, 0), 1);
      return gmt >= start && gmt < end;
   }

   if(rule == NEOFL_DST_AU)
   {
      // Southern hemisphere: the window spans the new year, so it is inverted.
      const datetime start = NeoFLGS_Gmt(y, 10, NeoFLGS_NthWeekday(y, 10, 0, 1), 16) - 86400;
      const datetime end   = NeoFLGS_Gmt(y, 4,  NeoFLGS_NthWeekday(y, 4, 0, 1), 16) - 86400;
      return gmt >= start || gmt < end;
   }

   return false;
}

//--- Market definitions. Exchange cash hours, local time, expressed in minutes.
void NeoFLGS_MarketSpec(const ENUM_NEOFL_MARKET m,
                        double &baseOffset, ENUM_NEOFL_DST_RULE &rule,
                        int &openMin, int &closeMin,
                        int &lunchStart, int &lunchEnd,
                        string &name)
{
   lunchStart = -1; lunchEnd = -1;
   switch(m)
   {
      case NEOFL_MKT_SYDNEY:
         baseOffset = 10.0; rule = NEOFL_DST_AU;
         openMin = 10*60; closeMin = 16*60; name = "Sydney"; return;
      case NEOFL_MKT_TOKYO:
         baseOffset = 9.0;  rule = NEOFL_DST_NONE;
         openMin = 9*60;  closeMin = 15*60;
         lunchStart = 11*60+30; lunchEnd = 12*60+30; name = "Tokyo"; return;
      case NEOFL_MKT_HONGKONG:
         baseOffset = 8.0;  rule = NEOFL_DST_NONE;
         openMin = 9*60+30; closeMin = 16*60;
         lunchStart = 12*60; lunchEnd = 13*60; name = "Hong Kong"; return;
      case NEOFL_MKT_FRANKFURT:
         baseOffset = 1.0;  rule = NEOFL_DST_EU;
         openMin = 9*60;  closeMin = 17*60+30; name = "Frankfurt"; return;
      case NEOFL_MKT_LONDON:
         baseOffset = 0.0;  rule = NEOFL_DST_EU;
         openMin = 8*60;  closeMin = 16*60+30; name = "London"; return;
      case NEOFL_MKT_NEWYORK:
      default:
         baseOffset = -5.0; rule = NEOFL_DST_US;
         openMin = 9*60+30; closeMin = 16*60; name = "New York"; return;
   }
}

//--- Current UTC offset for a market, DST included.
double NeoFLGS_MarketOffset(const ENUM_NEOFL_MARKET m, const datetime gmt)
{
   double base; ENUM_NEOFL_DST_RULE rule; int o, c, ls, le; string n;
   NeoFLGS_MarketSpec(m, base, rule, o, c, ls, le, n);
   return base + (NeoFLGS_IsDst(rule, gmt) ? 1.0 : 0.0);
}

//--- GMT converted to a market's local time.
datetime NeoFLGS_ToLocal(const ENUM_NEOFL_MARKET m, const datetime gmt)
{
   return gmt + (int)(NeoFLGS_MarketOffset(m, gmt) * 3600.0);
}

string NeoFLGS_MarketName(const ENUM_NEOFL_MARKET m)
{
   double base; ENUM_NEOFL_DST_RULE rule; int o, c, ls, le; string n;
   NeoFLGS_MarketSpec(m, base, rule, o, c, ls, le, n);
   return n;
}

//+------------------------------------------------------------------+
//| Is this exchange trading right now?                               |
//| Honours the lunch break where the venue has one -- Tokyo and Hong |
//| Kong both close midday, and a model that ignores that reports     |
//| liquidity which is not there.                                     |
//+------------------------------------------------------------------+
bool NeoFLGS_IsMarketOpen(const ENUM_NEOFL_MARKET m, const datetime gmt)
{
   double base; ENUM_NEOFL_DST_RULE rule; int openMin, closeMin, lunchStart, lunchEnd;
   string name;
   NeoFLGS_MarketSpec(m, base, rule, openMin, closeMin, lunchStart, lunchEnd, name);

   const datetime local = NeoFLGS_ToLocal(m, gmt);
   MqlDateTime t; TimeToStruct(local, t);

   if(t.day_of_week == 0 || t.day_of_week == 6)
      return false;

   const int minute = t.hour * 60 + t.min;

   bool within;
   if(openMin <= closeMin) within = (minute >= openMin && minute < closeMin);
   else                    within = (minute >= openMin || minute < closeMin);

   if(!within)
      return false;

   if(lunchStart >= 0 && minute >= lunchStart && minute < lunchEnd)
      return false;

   return true;
}

//--- Dealing-session windows. Gold does not trade on an exchange clock, so these are
//    the conventional windows, anchored to a region's local time so they shift with
//    that region's DST rather than a fixed GMT block.
void NeoFLGS_SessionSpec(const ENUM_NEOFL_SESSION s,
                         ENUM_NEOFL_MARKET &anchor, int &openMin, int &closeMin,
                         string &name)
{
   switch(s)
   {
      case NEOFL_SESSION_ASIAN:
         anchor = NEOFL_MKT_TOKYO;   openMin = 8*60; closeMin = 17*60; name = "Asian";   return;
      case NEOFL_SESSION_LONDON:
         anchor = NEOFL_MKT_LONDON;  openMin = 8*60; closeMin = 17*60; name = "London";  return;
      case NEOFL_SESSION_NEWYORK:
      default:
         anchor = NEOFL_MKT_NEWYORK; openMin = 8*60; closeMin = 17*60; name = "NewYork"; return;
   }
}

bool NeoFLGS_IsSessionOpen(const ENUM_NEOFL_SESSION s, const datetime gmt)
{
   ENUM_NEOFL_MARKET anchor; int openMin, closeMin; string name;
   NeoFLGS_SessionSpec(s, anchor, openMin, closeMin, name);

   const datetime local = NeoFLGS_ToLocal(anchor, gmt);
   MqlDateTime t; TimeToStruct(local, t);
   const int minute = t.hour * 60 + t.min;

   if(openMin <= closeMin) return (minute >= openMin && minute < closeMin);
   return (minute >= openMin || minute < closeMin);
}

string NeoFLGS_SessionName(const ENUM_NEOFL_SESSION s)
{
   ENUM_NEOFL_MARKET a; int o, c; string n;
   NeoFLGS_SessionSpec(s, a, o, c, n);
   return n;
}

//--- Comma-separated list of open sessions; "" when none.
string NeoFLGS_ActiveSessions(const datetime gmt)
{
   string out = "";
   for(int i = 0; i < NEOFL_SESSION_COUNT; i++)
   {
      const ENUM_NEOFL_SESSION s = (ENUM_NEOFL_SESSION)i;
      if(NeoFLGS_IsSessionOpen(s, gmt))
         out += (out == "" ? "" : "+") + NeoFLGS_SessionName(s);
   }
   return out;
}

int NeoFLGS_ActiveSessionCount(const datetime gmt)
{
   int n = 0;
   for(int i = 0; i < NEOFL_SESSION_COUNT; i++)
      if(NeoFLGS_IsSessionOpen((ENUM_NEOFL_SESSION)i, gmt))
         n++;
   return n;
}

//--- More than one session open: liquidity concentrates here. The London/New York
//    overlap is the deepest window of the day, and it MOVES during the weeks when US
//    and EU DST are out of step.
bool NeoFLGS_InOverlap(const datetime gmt)
{
   return NeoFLGS_ActiveSessionCount(gmt) > 1;
}

//+------------------------------------------------------------------+
//| The metals/FX week, in GMT: closes Friday 22:00, reopens Sunday   |
//| 22:00. Expressed in GMT because brokers disagree about when the   |
//| week begins.                                                      |
//+------------------------------------------------------------------+
bool NeoFLGS_IsWeekendGmt(const datetime gmt)
{
   MqlDateTime t; TimeToStruct(gmt, t);
   if(t.day_of_week == 6)                     return true;   // Saturday
   if(t.day_of_week == 5 && t.hour >= 22)     return true;   // Friday evening
   if(t.day_of_week == 0 && t.hour <  22)     return true;   // Sunday before reopen
   return false;
}

//+------------------------------------------------------------------+
//| Is the gold trading day active?                                   |
//|                                                                   |
//| D-003: gold's day starts with the Asian session and ends with the |
//| American session. Between those bounds gold is somewhere being    |
//| actively traded, so the day is a span across regions rather than  |
//| one venue's hours.                                                |
//+------------------------------------------------------------------+
bool NeoFLGS_GoldDayActive(const datetime gmt)
{
   if(NeoFLGS_IsWeekendGmt(gmt))
      return false;
   return NeoFLGS_ActiveSessionCount(gmt) > 0;
}

//--- Which part of gold's day this is. Context, not permission.
string NeoFLGS_GoldDayPhase(const datetime gmt)
{
   if(NeoFLGS_IsWeekendGmt(gmt))
      return "WEEKEND";
   const string active = NeoFLGS_ActiveSessions(gmt);
   if(active == "")
      return "BETWEEN_SESSIONS";
   if(NeoFLGS_ActiveSessionCount(gmt) > 1)
      return "OVERLAP:" + active;
   return active;
}

//+------------------------------------------------------------------+
//| Which venue governs an index. Returns false when unknown --       |
//| an unrecognised index must not inherit New York's hours.          |
//+------------------------------------------------------------------+
bool NeoFLGS_IndexVenue(const string indexSymbol, ENUM_NEOFL_MARKET &venue)
{
   string s = indexSymbol;
   StringToUpper(s);

   if(s == "US500" || s == "US100" || s == "US30" ||
      s == "SPX"   || s == "NAS100" || s == "NSX")   { venue = NEOFL_MKT_NEWYORK;   return true; }
   if(s == "GER40" || s == "DAX" || s == "DE40")     { venue = NEOFL_MKT_FRANKFURT; return true; }
   if(s == "UK100" || s == "FTSE")                   { venue = NEOFL_MKT_LONDON;    return true; }
   if(s == "JP225" || s == "NIKKEI")                 { venue = NEOFL_MKT_TOKYO;     return true; }
   if(s == "HK50"  || s == "HSI")                    { venue = NEOFL_MKT_HONGKONG;  return true; }
   if(s == "AUS200")                                 { venue = NEOFL_MKT_SYDNEY;    return true; }

   return false;
}

//+------------------------------------------------------------------+
//| Assess global session state and return provenance (D-002).        |
//|                                                                   |
//| Reports which sessions are open and whether they overlap. Does    |
//| NOT decide whether to trade -- a strategy that only wants the     |
//| London/NY overlap and one that wants Asian range-building need    |
//| the same facts and will act on them differently.                  |
//+------------------------------------------------------------------+
NeoFLDecision NeoFLGS_Assess(const string symbol)
{
   NeoFLDecision d;
   NeoFLDecision_Begin(d, "GlobalSessions", symbol);

   const datetime gmt = TimeGMT();
   const string   active = NeoFLGS_ActiveSessions(gmt);
   const string   phase  = NeoFLGS_GoldDayPhase(gmt);

   const string inputs = StringFormat("gmt=%s active=[%s] london_utc%+.0f ny_utc%+.0f tokyo_utc%+.0f",
                                      TimeToString(gmt, TIME_DATE | TIME_MINUTES),
                                      active,
                                      NeoFLGS_MarketOffset(NEOFL_MKT_LONDON, gmt),
                                      NeoFLGS_MarketOffset(NEOFL_MKT_NEWYORK, gmt),
                                      NeoFLGS_MarketOffset(NEOFL_MKT_TOKYO, gmt));

   if(NeoFLGS_IsWeekendGmt(gmt))
   {
      NeoFLDecision_Set(d, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        "market closed for the weekend", inputs);
      return d;
   }

   if(active == "")
   {
      NeoFLDecision_Set(d, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        "between sessions: American close has passed, Asian open not reached",
                        inputs);
      return d;
   }

   NeoFLDecision_Set(d, NEOFL_VERDICT_PROCEED, NEOFL_DATA_OK,
                     StringFormat("%s active%s", phase,
                                  NeoFLGS_InOverlap(gmt) ? " (session overlap - deepest liquidity)" : ""),
                     inputs);
   return d;
}

#endif // __NEOFL_GLOBAL_SESSIONS_MQH__
