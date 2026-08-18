"""US session timing.

Broker server time is arbitrary, so US-open timing is derived from GMT with DST
computed. These cases are mirrored in CORE/NeoFL_Session/NeoFL_Session.mqh and by
NeoFL_CoreSelfTest.mq5 — keep them in step.

The DST boundaries below are fixed calendar facts, so they can be asserted outright
rather than recomputed by the same logic under test.
"""

import sys
import unittest
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "python"))

from neofl_core.session import (  # noqa: E402
    gmt_to_eastern,
    is_us_dst,
    is_us_session_open,
    minutes_since_us_open,
    nth_weekday_of_month,
    opening_range_complete,
)


class DstBoundaryTest(unittest.TestCase):
    """Verified against the actual calendar, not against the implementation."""

    def test_known_dst_start_days(self):
        # Second Sunday in March.
        for year, day in ((2024, 10), (2025, 9), (2026, 8), (2027, 14)):
            with self.subTest(year=year):
                self.assertEqual(nth_weekday_of_month(year, 3, 0, 2), day)

    def test_known_dst_end_days(self):
        # First Sunday in November.
        for year, day in ((2024, 3), (2025, 2), (2026, 1), (2027, 7)):
            with self.subTest(year=year):
                self.assertEqual(nth_weekday_of_month(year, 11, 0, 1), day)

    def test_summer_is_dst_winter_is_not(self):
        self.assertTrue(is_us_dst(datetime(2026, 7, 1, 12)))
        self.assertFalse(is_us_dst(datetime(2026, 1, 15, 12)))

    def test_transition_is_sharp(self):
        """2026: DST begins 8 March at 07:00 GMT."""
        self.assertFalse(is_us_dst(datetime(2026, 3, 8, 6, 59)))
        self.assertTrue(is_us_dst(datetime(2026, 3, 8, 7, 0)))
        # And ends 1 November at 06:00 GMT.
        self.assertTrue(is_us_dst(datetime(2026, 11, 1, 5, 59)))
        self.assertFalse(is_us_dst(datetime(2026, 11, 1, 6, 0)))

    def test_offset_applied_correctly(self):
        """14:30 GMT is the 09:30 open in summer, but 09:30 needs 14:30 EST in winter."""
        self.assertEqual(gmt_to_eastern(datetime(2026, 7, 1, 14, 30)).hour, 10)  # EDT = GMT-4
        self.assertEqual(gmt_to_eastern(datetime(2026, 1, 15, 14, 30)).hour, 9)  # EST = GMT-5


class SessionWindowTest(unittest.TestCase):
    def test_session_open_and_closed_times(self):
        cases = [
            (datetime(2026, 6, 10, 9, 29), False, "one minute before the open"),
            (datetime(2026, 6, 10, 9, 30), True, "at the open"),
            (datetime(2026, 6, 10, 12, 0), True, "midday"),
            (datetime(2026, 6, 10, 15, 59), True, "one minute before the close"),
            (datetime(2026, 6, 10, 16, 0), False, "at the close"),
            (datetime(2026, 6, 10, 3, 0), False, "overnight"),
        ]
        for eastern, expected, label in cases:
            with self.subTest(label=label):
                self.assertEqual(is_us_session_open(eastern), expected)

    def test_weekends_are_closed(self):
        self.assertFalse(is_us_session_open(datetime(2026, 6, 13, 11, 0)))  # Saturday
        self.assertFalse(is_us_session_open(datetime(2026, 6, 14, 11, 0)))  # Sunday

    def test_minutes_since_open_signs(self):
        self.assertEqual(minutes_since_us_open(datetime(2026, 6, 10, 9, 30)), 0)
        self.assertEqual(minutes_since_us_open(datetime(2026, 6, 10, 9, 45)), 15)
        self.assertEqual(minutes_since_us_open(datetime(2026, 6, 10, 9, 0)), -30)


class OpeningRangeTest(unittest.TestCase):
    """Canon: the opening range is the FIRST M15 candle. Not three."""

    def test_range_completes_at_0945_not_before(self):
        cases = [
            (datetime(2026, 6, 10, 9, 30), False, "at the open"),
            (datetime(2026, 6, 10, 9, 44), False, "one minute short"),
            (datetime(2026, 6, 10, 9, 45), True, "first M15 candle closed"),
            (datetime(2026, 6, 10, 10, 30), True, "well into the session"),
        ]
        for eastern, expected, label in cases:
            with self.subTest(label=label):
                self.assertEqual(opening_range_complete(eastern), expected)

    def test_three_candle_concept_is_obsolete(self):
        """Guards against reintroducing the superseded 3x M15 (45-minute) range."""
        at_0945 = datetime(2026, 6, 10, 9, 45)
        self.assertTrue(
            opening_range_complete(at_0945),
            "range must be complete at 09:45; requiring 10:15 is the obsolete 3-candle rule",
        )

    def test_range_never_complete_outside_session(self):
        self.assertFalse(opening_range_complete(datetime(2026, 6, 13, 11, 0)))  # Saturday
        self.assertFalse(opening_range_complete(datetime(2026, 6, 10, 3, 0)))   # overnight


class MirrorConsistencyTest(unittest.TestCase):
    def test_mql5_session_module_shares_these_constants(self):
        module = (REPO_ROOT / "CORE" / "NeoFL_Session" / "NeoFL_Session.mqh").read_text(
            encoding="utf-8"
        )
        self.assertIn("NeoFLSess_OpeningRangeComplete", module)
        self.assertIn("NeoFLSess_IsUsDst", module)
        # Derived from GMT, never from broker server time.
        self.assertIn("TimeGMT", module)


if __name__ == "__main__":
    unittest.main()
