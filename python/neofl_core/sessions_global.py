"""Global market sessions and DST.

Decision D-003: session timing is a global concern. Gold trades in every zone and its
trading day runs from the Asian session open to the American session close; each major
index keeps its own exchange hours.

Everything here is computed in GMT. Broker server time is never trusted — the same UTC
instant is 09:30 on one broker's clock and 16:30 on another's.

WHY DST IS THE HARD PART
------------------------
There is no single DST rule, and one major market has none at all:

    US          second Sunday March    -> first Sunday November
    EU / UK     last Sunday March      -> last Sunday October
    Australia   first Sunday October   -> first Sunday April   (southern, inverted)
    Japan       none

Applying US dates globally is wrong for several weeks a year. In mid-March the US has
switched and the EU has not; in late October the EU has switched and the US has not.
During those weeks the London–New York overlap — the highest-liquidity window of the
day — moves by an hour. A system that assumes one rule silently trades the wrong window.
"""

from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from enum import Enum


class DstRule(Enum):
    NONE = "NONE"
    US = "US"
    EU = "EU"
    AU = "AU"


def nth_weekday(year: int, month: int, weekday_sunday0: int, nth: int) -> int:
    """Day-of-month of the nth given weekday. weekday_sunday0: 0=Sunday."""
    first = datetime(year, month, 1)
    first_dow = (first.weekday() + 1) % 7  # Python Mon=0 -> Sun=0
    return 1 + (weekday_sunday0 - first_dow) % 7 + (nth - 1) * 7


def last_weekday(year: int, month: int, weekday_sunday0: int) -> int:
    """Day-of-month of the LAST given weekday. Needed for EU/UK rules."""
    last_day = calendar.monthrange(year, month)[1]
    last = datetime(year, month, last_day)
    last_dow = (last.weekday() + 1) % 7
    return last_day - (last_dow - weekday_sunday0) % 7


def is_dst(rule: DstRule, gmt: datetime) -> bool:
    """Is daylight saving active for this rule at this GMT instant?"""
    y = gmt.year

    if rule is DstRule.NONE:
        return False

    if rule is DstRule.US:
        # 02:00 local: 07:00 GMT starting (EST -5), 06:00 GMT ending (EDT -4).
        start = datetime(y, 3, nth_weekday(y, 3, 0, 2), 7)
        end = datetime(y, 11, nth_weekday(y, 11, 0, 1), 6)
        return start <= gmt < end

    if rule is DstRule.EU:
        # 01:00 GMT on both boundaries, by definition of the EU directive.
        start = datetime(y, 3, last_weekday(y, 3, 0), 1)
        end = datetime(y, 10, last_weekday(y, 10, 0), 1)
        return start <= gmt < end

    if rule is DstRule.AU:
        # Southern hemisphere: DST spans the new year, so the window is inverted.
        # Starts first Sunday October 02:00 AEST (16:00 GMT the day before).
        # Ends first Sunday April 03:00 AEDT (16:00 GMT the day before).
        start = datetime(y, 10, nth_weekday(y, 10, 0, 1), 16) - timedelta(days=1)
        end = datetime(y, 4, nth_weekday(y, 4, 0, 1), 16) - timedelta(days=1)
        # Active from October through to April of the following year.
        return gmt >= start or gmt < end

    return False


@dataclass(frozen=True)
class Market:
    """A tradable venue with its own clock."""

    key: str
    name: str
    region: str
    base_utc_offset: float   # standard-time offset in hours
    dst_rule: DstRule
    open_local: time
    close_local: time
    # Some venues break for lunch (Tokyo 11:30-12:30). None when continuous.
    lunch_start_local: time | None = None
    lunch_end_local: time | None = None

    def utc_offset(self, gmt: datetime) -> float:
        return self.base_utc_offset + (1.0 if is_dst(self.dst_rule, gmt) else 0.0)

    def to_local(self, gmt: datetime) -> datetime:
        return gmt + timedelta(hours=self.utc_offset(gmt))

    def is_open(self, gmt: datetime) -> bool:
        local = self.to_local(gmt)
        if local.weekday() >= 5:       # Sat/Sun in local terms
            return False

        t = local.time()
        if self.open_local <= self.close_local:
            within = self.open_local <= t < self.close_local
        else:                          # venue spans midnight
            within = t >= self.open_local or t < self.close_local

        if not within:
            return False

        if self.lunch_start_local and self.lunch_end_local:
            if self.lunch_start_local <= t < self.lunch_end_local:
                return False

        return True


# --- The markets NeoFL cares about -------------------------------------------------
# Exchange cash hours in local time. Index strategies consult their own venue; using a
# shared default is exactly what D-003 forbids.

MARKETS: dict[str, Market] = {
    "SYDNEY": Market("SYDNEY", "ASX", "Asia-Pacific", 10.0, DstRule.AU,
                     time(10, 0), time(16, 0)),
    "TOKYO": Market("TOKYO", "Tokyo Stock Exchange", "Asia-Pacific", 9.0, DstRule.NONE,
                    time(9, 0), time(15, 0), time(11, 30), time(12, 30)),
    "HONGKONG": Market("HONGKONG", "HKEX", "Asia-Pacific", 8.0, DstRule.NONE,
                       time(9, 30), time(16, 0), time(12, 0), time(13, 0)),
    "FRANKFURT": Market("FRANKFURT", "XETRA (DAX)", "Europe", 1.0, DstRule.EU,
                        time(9, 0), time(17, 30)),
    "LONDON": Market("LONDON", "LSE (FTSE)", "Europe", 0.0, DstRule.EU,
                     time(8, 0), time(16, 30)),
    "NEWYORK": Market("NEWYORK", "NYSE / Nasdaq", "Americas", -5.0, DstRule.US,
                      time(9, 30), time(16, 0)),
}

# Which venue governs which index.
INDEX_VENUE: dict[str, str] = {
    "US500": "NEWYORK",
    "US100": "NEWYORK",
    "US30": "NEWYORK",
    "GER40": "FRANKFURT",
    "UK100": "LONDON",
    "JP225": "TOKYO",
    "HK50": "HONGKONG",
    "AUS200": "SYDNEY",
}


# --- FX / metal session windows ----------------------------------------------------
# Gold does not trade on an exchange clock; it trades around the world continuously.
# These are the conventional dealing windows, expressed in each region's local time so
# they shift correctly with that region's DST.

@dataclass(frozen=True)
class TradingWindow:
    key: str
    name: str
    anchor_market: str      # whose clock and DST rule this window follows
    open_local: time
    close_local: time

    def is_open(self, gmt: datetime) -> bool:
        market = MARKETS[self.anchor_market]
        local = market.to_local(gmt)
        t = local.time()
        if self.open_local <= self.close_local:
            return self.open_local <= t < self.close_local
        return t >= self.open_local or t < self.close_local


SESSIONS: dict[str, TradingWindow] = {
    "ASIAN": TradingWindow("ASIAN", "Asian session", "TOKYO", time(8, 0), time(17, 0)),
    "LONDON": TradingWindow("LONDON", "London session", "LONDON", time(8, 0), time(17, 0)),
    "NEWYORK": TradingWindow("NEWYORK", "New York session", "NEWYORK", time(8, 0), time(17, 0)),
}


def active_sessions(gmt: datetime) -> list[str]:
    """Which dealing sessions are open right now."""
    return [k for k, w in SESSIONS.items() if w.is_open(gmt)]


def in_overlap(gmt: datetime) -> list[str]:
    """Sessions overlapping — where liquidity concentrates.

    The London/New York overlap is the deepest window of the day, and its GMT position
    moves during the weeks when US and EU DST are out of step.
    """
    active = active_sessions(gmt)
    return active if len(active) > 1 else []


def is_weekend_gmt(gmt: datetime) -> bool:
    """The metals/FX week: closes Friday 22:00 GMT, reopens Sunday 22:00 GMT.

    Expressed in GMT rather than a broker's clock, since brokers disagree about when
    the week starts.
    """
    dow, hour = gmt.weekday(), gmt.hour  # Mon=0 .. Sun=6
    if dow == 5:                                  # Saturday
        return True
    if dow == 4 and hour >= 22:                   # Friday evening
        return True
    if dow == 6 and hour < 22:                    # Sunday before the reopen
        return True
    return False


def gold_day_active(gmt: datetime) -> bool:
    """Is the gold trading day active?

    D-003: gold's day starts with the Asian session and ends with the American session.
    Between the Asian open and the New York close, gold is somewhere being actively
    traded — so the day is a span, not a single venue's hours.
    """
    if is_weekend_gmt(gmt):
        return False
    return bool(active_sessions(gmt))


def gold_day_phase(gmt: datetime) -> str:
    """Which part of gold's day this is — for context, not permission."""
    if is_weekend_gmt(gmt):
        return "WEEKEND"
    active = active_sessions(gmt)
    if not active:
        return "BETWEEN_SESSIONS"
    if len(active) > 1:
        return "OVERLAP:" + "+".join(active)
    return active[0]


def index_market_open(index_symbol: str, gmt: datetime) -> bool | None:
    """Is the venue for this index open? None when the index is unknown.

    None is deliberate: an unrecognised index must not be assumed open. The caller
    has to handle "I do not know" rather than receiving a confident False.
    """
    venue = INDEX_VENUE.get(index_symbol.upper())
    if venue is None:
        return None
    return MARKETS[venue].is_open(gmt)
