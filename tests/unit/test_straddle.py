"""Straddle sizing — covering the main trade's gap loss.

Product owner's rule: main fixed at 0.01; straddle sized from the lots needed to cover
the loss between main entry and straddle entry, so the gap always returns to zero.

Cross-checked against the Bucket engine, which derives the zero price from a different
formula. Two independent derivations agreeing is the correctness evidence here.
"""

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "python"))

from neofl_core.bucket import Bucket, Direction, Position, Role  # noqa: E402
from neofl_core.straddle import (  # noqa: E402
    SizingMode, StraddleOutcome, ceil_to_step, required_volume,
    size_straddle, volume_for_ratio,
)

K = 100.0


class EquationTest(unittest.TestCase):
    def test_ratio_formula(self):
        """Vs = Vm(n+1); n=2 reproduces the legacy 0.03 against 0.01."""
        self.assertAlmostEqual(volume_for_ratio(0.01, 1), 0.02)
        self.assertAlmostEqual(volume_for_ratio(0.01, 2), 0.03)
        self.assertAlmostEqual(volume_for_ratio(0.01, 3), 0.04)

    def test_required_volume_formula(self):
        """Vs = Vm(gap+D)/D. Gap 20, recover in 10 -> 0.03."""
        self.assertAlmostEqual(required_volume(0.01, 20.0, 10.0), 0.03)
        self.assertAlmostEqual(required_volume(0.01, 20.0, 20.0), 0.02)

    def test_ratio_is_gap_independent(self):
        """A fixed straddle size is what RATIO mode means."""
        for gap in (10, 50, 200):
            with self.subTest(gap=gap):
                r = size_straddle(main_volume=0.01, main_entry=2400.0,
                                  straddle_entry=2400.0 - gap, main_is_long=True,
                                  mode=SizingMode.RATIO, recovery_ratio=2.0)
                self.assertAlmostEqual(r.volume, 0.03)

    def test_fixed_distance_scales_with_gap(self):
        """Size follows the gap; recovery distance stays put."""
        sizes = []
        for gap in (10, 50, 200):
            r = size_straddle(main_volume=0.01, main_entry=2400.0,
                              straddle_entry=2400.0 - gap, main_is_long=True,
                              mode=SizingMode.FIXED_DISTANCE, recovery_distance=10.0)
            sizes.append(r.volume)
            self.assertLessEqual(r.recovery_distance, 10.0 + 1e-6)
        self.assertEqual(sizes, sorted(sizes))
        self.assertLess(sizes[0], sizes[-1], "a wider gap must demand a larger straddle")


class BucketCrossCheckTest(unittest.TestCase):
    """The straddle sizer and the Bucket engine must agree, via different formulas."""

    def _check(self, gap, mode, **kw):
        r = size_straddle(main_volume=0.01, main_entry=2400.0,
                          straddle_entry=2400.0 - gap, main_is_long=True,
                          mode=mode, **kw)
        self.assertIs(r.outcome, StraddleOutcome.APPROVED)
        b = Bucket("X", "XAUUSD", [
            Position(1, Role.MAIN, Direction.BUY, 0.01, 2400.0, K),
            Position(2, Role.STRADDLE, Direction.SELL, r.volume, 2400.0 - gap, K),
        ])
        self.assertAlmostEqual(b.zero_floating_price(), r.zero_price, places=6)
        self.assertAlmostEqual(b.total(r.zero_price), 0.0, places=6)

    def test_agreement_across_gaps_and_modes(self):
        for gap in (10, 20, 50, 100):
            with self.subTest(gap=gap, mode="RATIO"):
                self._check(gap, SizingMode.RATIO, recovery_ratio=2.0)
            with self.subTest(gap=gap, mode="FIXED_DISTANCE"):
                self._check(gap, SizingMode.FIXED_DISTANCE, recovery_distance=10.0)


class RoundingTest(unittest.TestCase):
    """Straddle rounds UP — the opposite of risk sizing."""

    def test_ceil_not_floor(self):
        self.assertAlmostEqual(ceil_to_step(0.021, 0.01, 0.01), 0.03)
        self.assertAlmostEqual(ceil_to_step(0.020, 0.01, 0.01), 0.02)

    def test_rounding_up_never_undercovers(self):
        """Flooring would stop the bucket short of zero and the handover would never fire."""
        for gap in (7, 13, 37, 91):
            with self.subTest(gap=gap):
                r = size_straddle(main_volume=0.01, main_entry=2400.0,
                                  straddle_entry=2400.0 - gap, main_is_long=True,
                                  mode=SizingMode.FIXED_DISTANCE, recovery_distance=10.0)
                self.assertGreaterEqual(r.coverage, 1.0,
                                        "rounded size must fully cover the requirement")


class GuardTest(unittest.TestCase):
    def test_delta_neutral_is_refused(self):
        """A straddle no larger than the main can never bring the bucket to zero."""
        r = size_straddle(main_volume=0.05, main_entry=2400.0, straddle_entry=2380.0,
                          main_is_long=True, mode=SizingMode.RATIO,
                          recovery_ratio=2.0, volume_max=0.05)
        self.assertIsNot(r.outcome, StraddleOutcome.APPROVED)

    def test_non_adverse_entry_is_blocked(self):
        r = size_straddle(main_volume=0.01, main_entry=2400.0, straddle_entry=2420.0,
                          main_is_long=True)
        self.assertIs(r.outcome, StraddleOutcome.BLOCKED)
        self.assertIn("no loss to cover", r.reason)

    def test_broker_maximum_declines(self):
        r = size_straddle(main_volume=0.01, main_entry=2400.0, straddle_entry=2000.0,
                          main_is_long=True, mode=SizingMode.FIXED_DISTANCE,
                          recovery_distance=1.0, volume_max=0.10)
        self.assertIs(r.outcome, StraddleOutcome.DECLINED)
        self.assertIn("exceeds the broker maximum", r.reason)

    def test_short_main_mirrors(self):
        r = size_straddle(main_volume=0.01, main_entry=2400.0, straddle_entry=2420.0,
                          main_is_long=False, mode=SizingMode.RATIO, recovery_ratio=2.0)
        self.assertIs(r.outcome, StraddleOutcome.APPROVED)
        self.assertAlmostEqual(r.gap, 20.0)
        self.assertGreater(r.zero_price, 2420.0, "a short main recovers upward")

    def test_every_outcome_states_why(self):
        for r in (size_straddle(main_volume=0.01, main_entry=2400.0,
                                straddle_entry=2380.0, main_is_long=True),
                  size_straddle(main_volume=0.01, main_entry=2400.0,
                                straddle_entry=2420.0, main_is_long=True)):
            self.assertTrue(r.reason)


if __name__ == "__main__":
    unittest.main()
