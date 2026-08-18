"""Bucket engine.

A bucket is a portfolio of related positions, not one position. In this architecture the
basket mechanism IS the risk control — there are no broker stops behind it — so bucket
integrity is a safety property.

Reference contract throughout: XAUUSD-like, $100 per $1.00 move per lot.
"""

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "python"))

from neofl_core.bucket import (  # noqa: E402
    Bucket, BucketState, Direction, Position, Role,
)

K = 100.0


def pos(ticket, role, direction, volume, entry, swap=0.0, commission=0.0):
    return Position(ticket, role, direction, volume, entry, K, swap, commission)


def recovery_bucket():
    """The documented scenario: 0.01 long rescued by a 0.03 short."""
    return Bucket("B1", "XAUUSD", [
        pos(1, Role.MAIN, Direction.BUY, 0.01, 2400.0),
        pos(2, Role.STRADDLE, Direction.SELL, 0.03, 2380.0),
    ])


class ZeroFloatingTest(unittest.TestCase):
    def test_zero_floating_price_is_exact(self):
        b = recovery_bucket()
        z = b.zero_floating_price()
        self.assertIsNotNone(z)
        self.assertAlmostEqual(z, 2370.0, places=6)
        self.assertAlmostEqual(b.total(z), 0.0, places=9,
                               msg="bucket P/L must be exactly zero at the computed price")

    def test_pl_moves_monotonically_toward_zero(self):
        b = recovery_bucket()
        prices = [2400, 2390, 2380, 2375, 2370]
        totals = [b.total(p) for p in prices]
        self.assertEqual(totals, sorted(totals), "net short bucket profits as price falls")
        self.assertLess(totals[0], 0.0)
        self.assertAlmostEqual(totals[-1], 0.0, places=9)

    def test_costs_shift_the_zero_point(self):
        """Costs must move the target, or recovery exits fractionally early forever."""
        clean = recovery_bucket()
        costed = Bucket("B", "XAUUSD", [
            pos(1, Role.MAIN, Direction.BUY, 0.01, 2400.0, swap=-1.0, commission=-0.7),
            pos(2, Role.STRADDLE, Direction.SELL, 0.03, 2380.0, commission=-2.1),
        ])
        self.assertNotAlmostEqual(clean.zero_floating_price(),
                                  costed.zero_floating_price(), places=4)
        self.assertAlmostEqual(costed.total(costed.zero_floating_price()), 0.0, places=9)

    def test_realized_pl_shifts_the_zero_point(self):
        b = recovery_bucket()
        b.realized = -15.0
        self.assertAlmostEqual(b.total(b.zero_floating_price()), 0.0, places=9)


class DeltaNeutralTest(unittest.TestCase):
    """Equal and opposite legs freeze the bucket. Waiting for zero waits forever."""

    def setUp(self):
        self.neutral = Bucket("N", "XAUUSD", [
            pos(1, Role.MAIN, Direction.BUY, 0.01, 2400.0),
            pos(2, Role.STRADDLE, Direction.SELL, 0.01, 2380.0),
        ])

    def test_zero_floating_price_is_none_not_a_number(self):
        self.assertIsNone(self.neutral.zero_floating_price())
        self.assertTrue(self.neutral.is_delta_neutral())

    def test_pl_is_frozen_across_all_prices(self):
        totals = {round(self.neutral.total(p), 6) for p in (2000, 2380, 2400, 3000)}
        self.assertEqual(len(totals), 1, "delta-neutral P/L must not vary with price")

    def test_handover_never_becomes_possible(self):
        for p in (2000, 2380, 2400, 3000):
            with self.subTest(price=p):
                self.assertFalse(self.neutral.ready_for_handover(p))

    def test_asymmetric_sizing_is_what_makes_recovery_possible(self):
        """Why the legacy uses 0.03 against 0.01 rather than 0.01 against 0.01."""
        self.assertIsNone(self.neutral.zero_floating_price())
        self.assertIsNotNone(recovery_bucket().zero_floating_price())


class StateTest(unittest.TestCase):
    def test_state_progression(self):
        main_only = Bucket("M", "XAUUSD", [pos(1, Role.MAIN, Direction.BUY, 0.01, 2400.0)])
        self.assertIs(main_only.state(2400.0), BucketState.MAIN_ONLY)

        b = recovery_bucket()
        self.assertIs(b.state(2400.0), BucketState.RECOVERING)
        self.assertIs(b.state(2370.0), BucketState.BASKET_NEUTRAL)

        runner = Bucket("R", "XAUUSD", [pos(2, Role.STRADDLE, Direction.SELL, 0.03, 2380.0)])
        self.assertIs(runner.state(2370.0), BucketState.RUNNER)

        closed = Bucket("C", "XAUUSD", [], realized=42.0)
        self.assertIs(closed.state(2370.0), BucketState.CLOSED)

    def test_handover_requires_both_legs_and_non_negative_bucket(self):
        b = recovery_bucket()
        self.assertFalse(b.ready_for_handover(2400.0), "still negative")
        self.assertTrue(b.ready_for_handover(2370.0))
        self.assertTrue(b.ready_for_handover(2360.0), "past zero also qualifies")

        main_only = Bucket("M", "XAUUSD", [pos(1, Role.MAIN, Direction.BUY, 0.01, 2400.0)])
        self.assertFalse(main_only.ready_for_handover(2400.0), "no straddle to hand over to")


class IdentityTest(unittest.TestCase):
    """Roles come from structure, never from comment text."""

    def test_roles_are_explicit_not_parsed(self):
        b = recovery_bucket()
        self.assertIs(b.main.role, Role.MAIN)
        self.assertIs(b.straddle.role, Role.STRADDLE)
        self.assertEqual(b.main.ticket, 1)
        self.assertEqual(b.straddle.ticket, 2)

    def test_position_carries_no_comment_field(self):
        """Regression guard: legacy identified roles by comment, and a stripped
        comment made the straddle be mistaken for the main trade."""
        self.assertNotIn("comment", Position.__dataclass_fields__)


class ExposureTest(unittest.TestCase):
    def test_net_exposure_is_signed(self):
        self.assertAlmostEqual(recovery_bucket().net_exposure(), -0.02, places=9)

    def test_gross_exposure_is_unsigned(self):
        self.assertAlmostEqual(recovery_bucket().gross_exposure(), 0.04, places=9)

    def test_net_zero_means_delta_neutral(self):
        b = Bucket("N", "XAUUSD", [
            pos(1, Role.MAIN, Direction.BUY, 0.02, 2400.0),
            pos(2, Role.STRADDLE, Direction.SELL, 0.02, 2380.0),
        ])
        self.assertAlmostEqual(b.net_exposure(), 0.0, places=9)
        self.assertTrue(b.is_delta_neutral())


if __name__ == "__main__":
    unittest.main()
