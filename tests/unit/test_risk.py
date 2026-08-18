"""Position sizing.

Sizing is where a bug costs real money, and the failure modes are quiet — they
produce plausible numbers rather than errors. These cases are hand-computable so the
expected values can be checked independently of the implementation.

Reference case throughout: XAUUSD-like contract, tick 0.01, tick value $1.00.
A $5.00 stop is 500 ticks, so 1.0 lot risks $500.
"""

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "python"))

from neofl_core.risk import (  # noqa: E402
    ContractSpec, Outcome, RiskConfig, RiskModel,
    floor_to_step, money_at_risk, size,
)

GOLD = ContractSpec(tick_size=0.01, tick_value=1.0,
                    volume_min=0.01, volume_max=50.0, volume_step=0.01)


class ArithmeticTest(unittest.TestCase):
    def test_money_at_risk_is_hand_checkable(self):
        # $5.00 stop / 0.01 tick = 500 ticks; x $1.00 x 1.0 lot = $500.
        self.assertEqual(money_at_risk(1.0, 5.0, GOLD), 500.0)
        self.assertEqual(money_at_risk(0.1, 5.0, GOLD), 50.0)

    def test_percent_equity_sizing(self):
        """$10,000 at 1% = $100 budget; $500 per lot -> 0.20 lots."""
        r = size(5.0, GOLD, RiskConfig(hard_max_lot=0.0), equity=10_000)
        self.assertIs(r.outcome, Outcome.APPROVED)
        self.assertAlmostEqual(r.volume, 0.20, places=6)
        self.assertAlmostEqual(r.risk_money, 100.0, places=2)
        self.assertAlmostEqual(r.risk_percent, 1.0, places=4)

    def test_equity_and_balance_models_differ_when_pl_is_open(self):
        cfg_e = RiskConfig(model=RiskModel.PERCENT_EQUITY, hard_max_lot=0.0)
        cfg_b = RiskConfig(model=RiskModel.PERCENT_BALANCE, hard_max_lot=0.0)
        # Equity drawn down below balance by open losses.
        re = size(5.0, GOLD, cfg_e, equity=8_000, balance=10_000)
        rb = size(5.0, GOLD, cfg_b, equity=8_000, balance=10_000)
        self.assertLess(re.volume, rb.volume,
                        "equity model must size smaller when sitting on open losses")

    def test_fixed_lot_ignores_account_size(self):
        cfg = RiskConfig(model=RiskModel.FIXED_LOT, fixed_lot=0.05, hard_max_lot=0.0)
        small = size(5.0, GOLD, cfg, equity=500)
        large = size(5.0, GOLD, cfg, equity=500_000)
        self.assertEqual(small.volume, large.volume)


class RoundingTest(unittest.TestCase):
    """Rounding UP would take more risk than authorised, on every trade."""

    def test_volume_is_floored_not_rounded(self):
        # 0.745% of 10k = $74.50 budget -> 0.149 lots raw.
        r = size(5.0, GOLD, RiskConfig(hard_max_lot=0.0, risk_percent=0.745), equity=10_000)
        self.assertEqual(r.volume, 0.14, "0.149 must floor to 0.14, not round to 0.15")

    def test_floored_size_never_exceeds_budget(self):
        for pct in (0.1, 0.37, 0.745, 1.0, 1.99, 3.33):
            with self.subTest(pct=pct):
                r = size(5.0, GOLD, RiskConfig(hard_max_lot=0.0, risk_percent=pct),
                         equity=10_000)
                if r.outcome is Outcome.APPROVED:
                    budget = 10_000 * pct / 100.0
                    self.assertLessEqual(r.risk_money, budget + 1e-9,
                                         f"{r.volume} lots risks more than the {pct}% budget")

    def test_floor_to_step_respects_broker_grid(self):
        coarse = ContractSpec(0.01, 1.0, 0.1, 50.0, 0.1)
        self.assertEqual(floor_to_step(0.37, coarse), 0.3)
        self.assertEqual(floor_to_step(0.10, coarse), 0.1)


class MinimumLotTest(unittest.TestCase):
    """The classic silent over-risk: min lot larger than the budget allows."""

    def test_declines_when_minimum_lot_exceeds_budget(self):
        # $200 at 1% = $2 budget, but 0.01 lot over a $5 stop risks $5.
        r = size(5.0, GOLD, RiskConfig(hard_max_lot=0.0), equity=200)
        self.assertIs(r.outcome, Outcome.DECLINED)
        self.assertEqual(r.volume, 0.0)
        self.assertIn("stop too wide", r.reason)

    def test_override_trades_minimum_but_says_so(self):
        r = size(5.0, GOLD,
                 RiskConfig(hard_max_lot=0.0, allow_min_lot_override=True), equity=200)
        self.assertIs(r.outcome, Outcome.APPROVED)
        self.assertEqual(r.volume, 0.01)
        self.assertGreater(r.risk_percent, 1.0, "override knowingly exceeds the budget")

    def test_override_is_off_by_default(self):
        self.assertFalse(RiskConfig().allow_min_lot_override)


class GuardTest(unittest.TestCase):
    """Bad inputs must block, never produce a plausible-looking size."""

    def test_broken_contract_metadata_blocks(self):
        cases = [
            (ContractSpec(0.01, 0.0, 0.01, 50, 0.01), "tick_value"),
            (ContractSpec(0.0, 1.0, 0.01, 50, 0.01), "tick_size"),
            (ContractSpec(0.01, 1.0, 0.01, 50, 0.0), "volume_step"),
            (ContractSpec(0.01, 1.0, 0.0, 50, 0.01), "volume range"),
            (ContractSpec(0.01, 1.0, 10.0, 1.0, 0.01), "volume range"),
        ]
        for spec, expect in cases:
            with self.subTest(expect=expect):
                r = size(5.0, spec, RiskConfig(), equity=10_000)
                self.assertIs(r.outcome, Outcome.BLOCKED)
                self.assertEqual(r.volume, 0.0)
                self.assertIn(expect, r.reason)

    def test_missing_stop_blocks(self):
        for stop in (0.0, -1.0):
            with self.subTest(stop=stop):
                r = size(stop, GOLD, RiskConfig(), equity=10_000)
                self.assertIs(r.outcome, Outcome.BLOCKED)
                self.assertIn("stop", r.reason)

    def test_zero_equity_blocks(self):
        r = size(5.0, GOLD, RiskConfig(), equity=0.0)
        self.assertIs(r.outcome, Outcome.BLOCKED)

    def test_no_path_returns_size_without_approval(self):
        """Any non-approved outcome must carry volume 0."""
        for r in (size(0.0, GOLD, RiskConfig(), equity=10_000),
                  size(5.0, GOLD, RiskConfig(), equity=0.0),
                  size(5.0, GOLD, RiskConfig(hard_max_lot=0.0), equity=200)):
            self.assertEqual(r.volume, 0.0)
            self.assertIsNot(r.outcome, Outcome.APPROVED)


class LimitTest(unittest.TestCase):
    def test_hard_cap_binds(self):
        r = size(5.0, GOLD, RiskConfig(hard_max_lot=0.01), equity=10_000)
        self.assertEqual(r.volume, 0.01, "hard cap must bind below the risk-derived size")

    def test_max_open_positions_declines(self):
        cfg = RiskConfig(max_open_positions=1)
        r = size(5.0, GOLD, cfg, equity=10_000, open_positions=1)
        self.assertIs(r.outcome, Outcome.DECLINED)
        self.assertIn("max open positions", r.reason)

    def test_exposure_limit_caps_then_declines(self):
        cfg = RiskConfig(hard_max_lot=0.0, max_total_exposure_lot=0.30)
        capped = size(5.0, GOLD, cfg, equity=10_000, open_exposure=0.25)
        self.assertLessEqual(capped.volume, 0.05)
        full = size(5.0, GOLD, cfg, equity=10_000, open_exposure=0.30)
        self.assertIs(full.outcome, Outcome.DECLINED)

    def test_broker_max_volume_caps(self):
        tiny = ContractSpec(0.01, 1.0, 0.01, 0.05, 0.01)
        r = size(5.0, tiny, RiskConfig(hard_max_lot=0.0), equity=1_000_000)
        self.assertLessEqual(r.volume, 0.05)


class ProvenanceTest(unittest.TestCase):
    """D-002: every outcome states why."""

    def test_every_result_carries_a_reason(self):
        for r in (size(5.0, GOLD, RiskConfig(), equity=10_000),
                  size(0.0, GOLD, RiskConfig(), equity=10_000),
                  size(5.0, GOLD, RiskConfig(hard_max_lot=0.0), equity=200)):
            self.assertTrue(r.reason, "silence is not a valid outcome")


if __name__ == "__main__":
    unittest.main()
