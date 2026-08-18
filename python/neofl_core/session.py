"""Reference implementation of NeoFL US-session timing.

Mirrors CORE/NeoFL_Session/NeoFL_Session.mqh.

Why this matters enough to mirror: broker server time is arbitrary — the same UTC
instant is 09:30 on one broker's clock and 16:30 on another's. Anything keyed to the
US open must be derived from an absolute reference, with DST computed rather than
assumed. That arithmetic is easy to get subtly wrong and expensive to debug inside
MetaTrader, so it is kept executable here.

US Eastern DST (post-2007 rule):
    starts  second Sunday in March,    02:00 local (07:00 GMT, EST = GMT-5)
    ends    first  Sunday in November, 02:00 local (06:00 GMT, EDT = GMT-4)
"""

from datetime import datetime, timedelta

US_OPEN_HOUR, US_OPEN_MINUTE = 9, 30
US_CLOSE_HOUR, US_CLOSE_MINUTE = 16, 0
OPENING_RANGE_MINUTES = 15  # canon: the FIRST M15 candle, not three


def nth_weekday_of_month(year: int, month: int, weekday_sunday0: int, nth: int) -> int:
    """Day-of-month of the nth given weekday. weekday_sunday0: 0=Sunday."""
    first = datetime(year, month, 1)
    # Python's weekday(): Monday=0..Sunday=6. Convert to Sunday=0.
    first_dow_sunday0 = (first.weekday() + 1) % 7
    offset = (weekday_sunday0 - first_dow_sunday0) % 7
    return 1 + offset + (nth - 1) * 7


def is_us_dst(gmt: datetime) -> bool:
    """Is this GMT instant inside US Eastern daylight saving time?"""
    start = datetime(gmt.year, 3, nth_weekday_of_month(gmt.year, 3, 0, 2), 7)
    end = datetime(gmt.year, 11, nth_weekday_of_month(gmt.year, 11, 0, 1), 6)
    return start <= gmt < end


def gmt_to_eastern(gmt: datetime) -> datetime:
    return gmt + timedelta(hours=-4 if is_us_dst(gmt) else -5)


def is_eastern_weekday(eastern: datetime) -> bool:
    return eastern.weekday() < 5  # Mon-Fri


def eastern_minute_of_day(eastern: datetime) -> int:
    return eastern.hour * 60 + eastern.minute


def is_us_session_open(eastern: datetime) -> bool:
    if not is_eastern_weekday(eastern):
        return False
    m = eastern_minute_of_day(eastern)
    return (US_OPEN_HOUR * 60 + US_OPEN_MINUTE) <= m < (US_CLOSE_HOUR * 60 + US_CLOSE_MINUTE)


def minutes_since_us_open(eastern: datetime) -> int:
    return eastern_minute_of_day(eastern) - (US_OPEN_HOUR * 60 + US_OPEN_MINUTE)


def opening_range_complete(eastern: datetime) -> bool:
    """True once the first M15 candle of the session has closed (09:45 ET onward)."""
    if not is_us_session_open(eastern):
        return False
    return minutes_since_us_open(eastern) >= OPENING_RANGE_MINUTES
