"""Global session timing and DST (decision D-003).

DST boundary dates below are real calendar facts, asserted outright rather than
recomputed by the logic under test. If the implementation and the calendar disagree,
the implementation is wrong.

The cases that matter most are the weeks when regions are out of step — mid-March
(US switched, EU not) and late October (EU switched, US not). During those weeks the
London/New York overlap moves, and a single-rule implementation trades the wrong window.
"""

import sys
import unittest
from datetime import datetime, time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "python"))

from neofl_core.sessions_global import (  # noqa: E402
    MARKETS,
    DstRule,
    active_sessions,
    gold_day_active,
    gold_day_phase,
    in_overlap,
    index_market_open,
    is_dst,
    is_weekend_gmt,
    last_weekday,
    nth_weekday,
)


class DstCalendarTest(unittest.TestCase):
    """Verified against the actual calendar."""

    def test_us_dst_dates(self):
        # Second Sunday March -> first Sunday November.
        for year, start, end in ((2025, 9, 2), (2026, 8, 1), (2027, 14, 7)):
            with self.subTest(year=year):
                self.assertEqual(nth_weekday(year, 3, 0, 2), start)
                self.assertEqual(nth_weekday(year, 11, 0, 1), end)

    def test_eu_dst_dates(self):
        # Last Sunday March -> last Sunday October.
        for year, start, end in ((2025, 30, 26), (2026, 29, 25), (2027, 28, 31)):
            with self.subTest(year=year):
                self.assertEqual(last_weekday(year, 3, 0), start)
                self.assertEqual(last_weekday(year, 10, 0), end)

    def test_japan_never_observes_dst(self):
        for month in range(1, 13):
            with self.subTest(month=month):
                self.assertFalse(is_dst(DstRule.NONE, datetime(2026, month, 15, 12)))

    def test_australia_dst_is_inverted(self):
        """Southern hemisphere: DST in the northern winter."""
        self.assertTrue(is_dst(DstRule.AU, datetime(2026, 1, 15, 12)))   # Jan = AU summer
        self.assertFalse(is_dst(DstRule.AU, datetime(2026, 7, 15, 12)))  # Jul = AU winter


class DstDivergenceTest(unittest.TestCase):
    """The weeks a single-rule implementation gets wrong."""

    def test_march_us_switched_eu_has_not(self):
        """2026: US switches 8 March, EU waits until 29 March."""
        mid_march = datetime(2026, 3, 20, 12)
        self.assertTrue(is_dst(DstRule.US, mid_march))
        self.assertFalse(is_dst(DstRule.EU, mid_march))

    def test_october_eu_switched_us_has_not(self):
        """2026: EU switches back 25 October, US waits until 1 November."""
        late_october = datetime(2026, 10, 28, 12)
        self.assertFalse(is_dst(DstRule.EU, late_october))
        self.assertTrue(is_dst(DstRule.US, late_october))

    def test_offsets_differ_during_divergence(self):
        """London and New York are 4 hours apart in mid-March, 5 the rest of winter."""
        mid_march = datetime(2026, 3, 20, 12)
        london = MARKETS["LONDON"].utc_offset(mid_march)
        newyork = MARKETS["NEWYORK"].utc_offset(mid_march)
        self.assertEqual(london - newyork, 4.0)

        deep_winter = datetime(2026, 1, 20, 12)
        london_w = MARKETS["LONDON"].utc_offset(deep_winter)
        newyork_w = MARKETS["NEWYORK"].utc_offset(deep_winter)
        self.assertEqual(london_w - newyork_w, 5.0)


class GoldDayTest(unittest.TestCase):
    """D-003: gold's day starts with the Asian session and ends with the American."""

    def test_gold_is_active_across_all_three_regions(self):
        """A weekday must show gold trading in Asia, in London, and in New York."""
        wednesday = datetime(2026, 6, 10)
        phases = {
            gold_day_phase(wednesday.replace(hour=h)) for h in range(24)
        }
        self.assertTrue(any("ASIAN" in p for p in phases), "gold must trade in Asia")
        self.assertTrue(any("LONDON" in p for p in phases), "gold must trade in London")
        self.assertTrue(any("NEWYORK" in p for p in phases), "gold must trade in New York")

    def test_asian_session_opens_the_gold_day(self):
        # 23:00 GMT = 08:00 Tokyo.
        self.assertIn("ASIAN", active_sessions(datetime(2026, 6, 10, 23)))

    def test_american_session_closes_the_gold_day(self):
        # 20:00 GMT = 16:00 New York (EDT), still open.
        self.assertIn("NEWYORK", active_sessions(datetime(2026, 6, 10, 20)))
        # 22:00 GMT = 18:00 New York, closed.
        self.assertNotIn("NEWYORK", active_sessions(datetime(2026, 6, 10, 22)))

    def test_london_newyork_overlap_exists(self):
        """The deepest liquidity window of the day."""
        overlap = in_overlap(datetime(2026, 6, 10, 14))
        self.assertIn("LONDON", overlap)
        self.assertIn("NEWYORK", overlap)

    def test_gold_is_not_active_at_the_weekend(self):
        self.assertFalse(gold_day_active(datetime(2026, 6, 13, 12)))  # Saturday
        self.assertEqual(gold_day_phase(datetime(2026, 6, 13, 12)), "WEEKEND")

    def test_week_boundaries_are_gmt_not_broker_time(self):
        self.assertFalse(is_weekend_gmt(datetime(2026, 6, 12, 21)))  # Fri 21:00 open
        self.assertTrue(is_weekend_gmt(datetime(2026, 6, 12, 22)))   # Fri 22:00 closed
        self.assertTrue(is_weekend_gmt(datetime(2026, 6, 14, 21)))   # Sun 21:00 closed
        self.assertFalse(is_weekend_gmt(datetime(2026, 6, 14, 22)))  # Sun 22:00 reopened


class IndexVenueTest(unittest.TestCase):
    """Each index consults its own exchange, never a shared default."""

    def test_indices_follow_their_own_venues(self):
        """14:00 GMT: Europe and the US are open; Asia-Pacific is not."""
        at = datetime(2026, 6, 10, 14)
        self.assertTrue(index_market_open("US500", at))
        self.assertTrue(index_market_open("GER40", at))
        self.assertTrue(index_market_open("UK100", at))
        self.assertFalse(index_market_open("JP225", at))
        self.assertFalse(index_market_open("HK50", at))

    def test_asian_indices_open_while_us_sleeps(self):
        """02:00 GMT: Tokyo trading, New York shut. The inverse of the above."""
        at = datetime(2026, 6, 10, 2)
        self.assertTrue(index_market_open("JP225", at))
        self.assertFalse(index_market_open("US500", at))

    def test_unknown_index_returns_none_not_false(self):
        """An unrecognised index must not be assumed closed — or open."""
        self.assertIsNone(index_market_open("WHATEVER99", datetime(2026, 6, 10, 14)))

    def test_tokyo_lunch_break_is_observed(self):
        """TSE breaks 11:30-12:30 local; a venue model that ignores it is wrong."""
        # 03:00 GMT = 12:00 Tokyo — inside the lunch break.
        self.assertFalse(MARKETS["TOKYO"].is_open(datetime(2026, 6, 10, 3)))
        # 02:00 GMT = 11:00 Tokyo — trading.
        self.assertTrue(MARKETS["TOKYO"].is_open(datetime(2026, 6, 10, 2)))

    def test_no_market_opens_at_the_weekend(self):
        saturday = datetime(2026, 6, 13, 12)
        for key, market in MARKETS.items():
            with self.subTest(market=key):
                self.assertFalse(market.is_open(saturday))


if __name__ == "__main__":
    unittest.main()
