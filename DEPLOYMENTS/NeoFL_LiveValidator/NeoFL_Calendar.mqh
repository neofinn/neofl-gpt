//+------------------------------------------------------------------+
//| NeoFL_Calendar.mqh                                               |
//| Core module. Economic events and news proximity.                 |
//| Reports what is scheduled. Never decides whether to trade.       |
//+------------------------------------------------------------------+
//
// Canon: the calendar is a SHARED service consumed by both the trading engine and
// the Observer Network, not something each EA reimplements. It should let the
// observer explain "this trade occurred around event X" rather than only "a trade
// occurred".
//
// Two constraints shape this module:
//
// 1. MT5's calendar API is unavailable in the Strategy Tester and returns nothing
//    when the terminal is disconnected. That is a DATA_UNAVAILABLE condition, not a
//    "no events scheduled" condition, and the two must never be conflated. An engine
//    that cannot see the calendar must know it cannot see the calendar.
//
// 2. This module reports proximity to events. It does not decide to stand aside --
//    that threshold belongs to the strategy. Calendar says "CPI in 48 seconds";
//    the strategy decides what that means for it.
//
#ifndef __NEOFL_CALENDAR_MQH__
#define __NEOFL_CALENDAR_MQH__

#include "NeoFL_DataQuality.mqh"

//--- A scheduled or released economic event, normalized per canon.
struct NeoFLCalendarEvent
{
   bool     valid;
   ulong    event_id;
   string   name;
   string   country;
   string   currency;
   int      importance;          // ENUM_CALENDAR_EVENT_IMPORTANCE
   datetime scheduled;           // server time
   int      seconds_to_event;    // negative once released
   bool     released;
   bool     has_actual;
   double   actual;
   double   forecast;
   double   previous;
};

//--- Result of a calendar lookup, with quality attached.
struct NeoFLCalendarView
{
   ENUM_NEOFL_DATA_QUALITY quality;
   string                  detail;
   bool                    has_next;
   NeoFLCalendarEvent      next_high_impact;
};

//--- How far ahead to look for upcoming events.
int NeoFLCal_LookaheadSeconds() { return 4 * 60 * 60; }   // 4 hours
//--- How far back to consider a release still "recent".
int NeoFLCal_LookbackSeconds()  { return 60 * 60; }       // 1 hour

//--- Currencies whose events matter to this platform. Gold and US indices both key
//    off USD macro, so USD is the default focus.
string NeoFLCal_PrimaryCurrency() { return "USD"; }

//+------------------------------------------------------------------+
//| Is the MT5 calendar reachable at all?                             |
//|                                                                   |
//| Distinguishes "no events" from "cannot see events". In the        |
//| Strategy Tester the calendar API is absent entirely, so this is   |
//| expected to report UNAVAILABLE there -- which is correct, not a   |
//| failure.                                                          |
//+------------------------------------------------------------------+
ENUM_NEOFL_DATA_QUALITY NeoFLCal_Probe(string &detail)
{
   detail = "";

   MqlCalendarValue values[];
   ResetLastError();
   const datetime from = TimeCurrent() - NeoFLCal_LookbackSeconds();
   const datetime to   = TimeCurrent() + NeoFLCal_LookaheadSeconds();

   const int n = CalendarValueHistory(values, from, to, NULL, NeoFLCal_PrimaryCurrency());
   const int err = GetLastError();

   if(n < 0 || (n == 0 && err != 0))
   {
      detail = StringFormat("calendar unreachable (error %d); expected inside Strategy Tester", err);
      return NEOFL_DATA_UNAVAILABLE;
   }

   if(n == 0)
   {
      // Genuinely reachable, genuinely nothing scheduled in the window.
      detail = "calendar reachable; no events in window";
      return NEOFL_DATA_OK;
   }

   detail = StringFormat("calendar reachable; %d event value(s) in window", n);
   return NEOFL_DATA_OK;
}

//+------------------------------------------------------------------+
//| Fill an event record from a calendar value plus its definition.   |
//+------------------------------------------------------------------+
bool NeoFLCal_Describe(const MqlCalendarValue &v, NeoFLCalendarEvent &out)
{
   out.valid = false;

   MqlCalendarEvent ev;
   if(!CalendarEventById(v.event_id, ev))
      return false;

   MqlCalendarCountry country;
   string countryName = "";
   string currency    = "";
   if(CalendarCountryById(ev.country_id, country))
   {
      countryName = country.name;
      currency    = country.currency;
   }

   out.valid            = true;
   out.event_id         = v.event_id;
   out.name             = ev.name;
   out.country          = countryName;
   out.currency         = currency;
   out.importance       = (int)ev.importance;
   out.scheduled        = v.time;
   out.seconds_to_event = (int)(v.time - TimeCurrent());
   out.released         = (v.time <= TimeCurrent());
   out.has_actual       = v.HasActualValue();
   out.actual           = out.has_actual ? v.GetActualValue()   : 0.0;
   out.forecast         = v.HasForecastValue() ? v.GetForecastValue() : 0.0;
   out.previous         = v.HasPreviousValue() ? v.GetPreviousValue() : 0.0;
   return true;
}

//+------------------------------------------------------------------+
//| Next high-impact event, if the calendar can be seen.              |
//|                                                                   |
//| Returns quality alongside the answer so a caller can tell         |
//| "nothing scheduled" from "cannot tell".                           |
//+------------------------------------------------------------------+
NeoFLCalendarView NeoFLCal_NextHighImpact()
{
   NeoFLCalendarView view;
   view.quality  = NEOFL_DATA_UNAVAILABLE;
   view.detail   = "";
   view.has_next = false;
   view.next_high_impact.valid = false;

   MqlCalendarValue values[];
   ResetLastError();
   const datetime now  = TimeCurrent();
   const datetime to   = now + NeoFLCal_LookaheadSeconds();

   const int n = CalendarValueHistory(values, now, to, NULL, NeoFLCal_PrimaryCurrency());
   const int err = GetLastError();

   if(n < 0 || (n == 0 && err != 0))
   {
      view.detail = StringFormat("calendar unreachable (error %d)", err);
      return view;
   }

   view.quality = NEOFL_DATA_OK;

   if(n == 0)
   {
      view.detail = StringFormat("no %s events in the next %d minutes",
                                 NeoFLCal_PrimaryCurrency(),
                                 NeoFLCal_LookaheadSeconds() / 60);
      return view;
   }

   // Values come ordered by time; take the first high-importance one.
   for(int i = 0; i < n; i++)
   {
      NeoFLCalendarEvent e;
      if(!NeoFLCal_Describe(values[i], e))
         continue;
      if(e.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      view.has_next         = true;
      view.next_high_impact = e;
      view.detail = StringFormat("%s in %d minute(s)", e.name, e.seconds_to_event / 60);
      return view;
   }

   view.detail = StringFormat("%d event(s) in window, none high-impact", n);
   return view;
}

//+------------------------------------------------------------------+
//| Assess calendar state and return a provenance record (D-002).     |
//|                                                                   |
//| Reports proximity; it does not impose a stand-aside window. The   |
//| strategy owns that threshold, because how close is too close      |
//| differs between a scalper and a swing engine.                     |
//+------------------------------------------------------------------+
NeoFLDecision NeoFLCal_Assess(const string symbol)
{
   NeoFLDecision d;
   NeoFLDecision_Begin(d, "Calendar", symbol);

   const NeoFLCalendarView view = NeoFLCal_NextHighImpact();

   if(view.quality == NEOFL_DATA_UNAVAILABLE)
   {
      // Not an error: the tester has no calendar. But the caller must know it is
      // operating blind rather than assume the schedule is clear.
      NeoFLDecision_Set(d, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_UNAVAILABLE,
                        "cannot see calendar: " + view.detail,
                        StringFormat("currency=%s lookahead=%dmin",
                                     NeoFLCal_PrimaryCurrency(),
                                     NeoFLCal_LookaheadSeconds() / 60));
      return d;
   }

   if(!view.has_next)
   {
      NeoFLDecision_Set(d, NEOFL_VERDICT_PROCEED, NEOFL_DATA_OK,
                        "no high-impact event ahead: " + view.detail,
                        StringFormat("currency=%s lookahead=%dmin",
                                     NeoFLCal_PrimaryCurrency(),
                                     NeoFLCal_LookaheadSeconds() / 60));
      return d;
   }

   const NeoFLCalendarEvent e = view.next_high_impact;
   const string inputs = StringFormat("event=\"%s\" currency=%s scheduled=%s seconds_to_event=%d",
                                      e.name, e.currency,
                                      TimeToString(e.scheduled, TIME_DATE | TIME_MINUTES),
                                      e.seconds_to_event);

   NeoFLDecision_Set(d, NEOFL_VERDICT_PROCEED, NEOFL_DATA_OK,
                     StringFormat("high-impact event ahead: %s in %d second(s)",
                                  e.name, e.seconds_to_event),
                     inputs);
   return d;
}

//--- Convenience: seconds until the next high-impact event.
//    Returns -1 when the calendar cannot be seen, and INT_MAX when nothing is
//    scheduled. Callers MUST distinguish the two; treating -1 as "far away" is the
//    mistake this signature exists to make obvious.
int NeoFLCal_SecondsToNextHighImpact()
{
   const NeoFLCalendarView view = NeoFLCal_NextHighImpact();
   if(view.quality == NEOFL_DATA_UNAVAILABLE) return -1;
   if(!view.has_next)                          return INT_MAX;
   return view.next_high_impact.seconds_to_event;
}

#endif // __NEOFL_CALENDAR_MQH__
