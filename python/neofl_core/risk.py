"""Reference implementation of NeoFL position sizing.

Mirrors CORE/NeoFL_Risk/NeoFL_Risk.mqh.

Sizing is the module where a bug costs real money, and the failure modes are quiet —
they produce plausible-looking numbers rather than errors. Keeping the arithmetic
executable here means it can be checked against hand-computed answers instead of only
being read.

Three guarded failure modes:

  1. Division by zero or missing broker metadata -> absurd size.
  2. Rounding UP to the volume step -> more risk than authorised.
  3. Minimum lot exceeding the risk budget -> silent over-risk. This is routine on a
     small account with a wide stop, not an edge case.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum


class RiskModel(Enum):
    FIXED_LOT = "FIXED_LOT"
    PERCENT_EQUITY = "PERCENT_EQUITY"
    PERCENT_BALANCE = "PERCENT_BALANCE"


class Outcome(Enum):
    APPROVED = "APPROVED"
    DECLINED = "DECLINED"   # evaluated, cannot size within the rules
    BLOCKED = "BLOCKED"     # cannot evaluate at all


@dataclass
class ContractSpec:
    """Broker facts required for sizing."""

    tick_size: float
    tick_value: float
    volume_min: float
    volume_max: float
    volume_step: float

    def validate(self) -> str | None:
        if self.tick_size <= 0:
            return "tick_size <= 0"
        if self.tick_value <= 0:
            return "tick_value <= 0; cannot convert price distance to money"
        if self.volume_step <= 0:
            return "volume_step <= 0"
        if self.volume_min <= 0 or self.volume_max < self.volume_min:
            return "incoherent volume range"
        return None


@dataclass
class RiskConfig:
    """Every field is a TRADING parameter owned by the product owner.

    These defaults are UNCONFIRMED placeholders so the code is testable — not a
    recommendation. `hard_max_lot` mirrors the legacy v3.85 hard ceiling, which the
    v2 canon does not mention.
    """

    model: RiskModel = RiskModel.PERCENT_EQUITY
    fixed_lot: float = 0.01
    risk_percent: float = 1.0
    hard_max_lot: float = 0.01
    max_total_exposure_lot: float = 0.0
    max_open_positions: int = 1
    allow_min_lot_override: bool = False


@dataclass
class RiskResult:
    outcome: Outcome
    volume: float
    risk_money: float
    risk_percent: float
    reason: str


def volume_digits(step: float) -> int:
    for d in range(9):
        if abs(step - round(step, d)) < 1e-9:
            return d
    return 8


def floor_to_step(volume: float, spec: ContractSpec) -> float:
    """Floor onto the broker's grid.

    FLOOR, never round-to-nearest. Rounding 0.014 up to 0.02 is a 43% risk overshoot,
    silently, on every trade.
    """
    if volume <= 0:
        return 0.0
    steps = math.floor((volume - spec.volume_min) / spec.volume_step + 1e-9)
    v = spec.volume_min + steps * spec.volume_step
    return round(max(0.0, v), volume_digits(spec.volume_step))


def money_at_risk(volume: float, stop_distance: float, spec: ContractSpec) -> float:
    if volume <= 0 or stop_distance <= 0:
        return 0.0
    return (stop_distance / spec.tick_size) * spec.tick_value * volume


def size(
    stop_distance: float,
    spec: ContractSpec,
    cfg: RiskConfig,
    *,
    equity: float,
    balance: float | None = None,
    open_positions: int = 0,
    open_exposure: float = 0.0,
) -> RiskResult:
    """Size a trade, or explain why it cannot be sized."""
    balance = equity if balance is None else balance

    problem = spec.validate()
    if problem:
        return RiskResult(Outcome.BLOCKED, 0.0, 0.0, 0.0,
                          f"contract metadata unusable: {problem}")

    if stop_distance <= 0:
        return RiskResult(Outcome.BLOCKED, 0.0, 0.0, 0.0,
                          "no stop distance supplied; risk is undefined without a stop")

    if cfg.max_open_positions > 0 and open_positions >= cfg.max_open_positions:
        return RiskResult(Outcome.DECLINED, 0.0, 0.0, 0.0,
                          f"already at max open positions ({cfg.max_open_positions})")

    budget = 0.0
    if cfg.model is RiskModel.FIXED_LOT:
        desired = cfg.fixed_lot
    else:
        account = equity if cfg.model is RiskModel.PERCENT_EQUITY else balance
        if account <= 0:
            return RiskResult(Outcome.BLOCKED, 0.0, 0.0, 0.0,
                              "account equity/balance is zero or negative")
        budget = account * cfg.risk_percent / 100.0
        per_lot = money_at_risk(1.0, stop_distance, spec)
        if per_lot <= 0:
            return RiskResult(Outcome.BLOCKED, 0.0, 0.0, 0.0,
                              "cannot value the stop distance; refusing to size blind")
        desired = budget / per_lot

    if cfg.hard_max_lot > 0 and desired > cfg.hard_max_lot:
        desired = cfg.hard_max_lot

    if cfg.max_total_exposure_lot > 0:
        room = cfg.max_total_exposure_lot - open_exposure
        if room <= 0:
            return RiskResult(Outcome.DECLINED, 0.0, 0.0, 0.0,
                              f"exposure limit reached: {open_exposure:.2f} of "
                              f"{cfg.max_total_exposure_lot:.2f} lots open")
        desired = min(desired, room)

    desired = min(desired, spec.volume_max)

    # The critical case: is the smallest tradable size already too much risk?
    if desired < spec.volume_min:
        min_risk = money_at_risk(spec.volume_min, stop_distance, spec)
        min_pct = (min_risk / equity * 100.0) if equity > 0 else 0.0
        if not cfg.allow_min_lot_override:
            return RiskResult(
                Outcome.DECLINED, 0.0, 0.0, 0.0,
                f"minimum lot {spec.volume_min:.2f} risks {min_risk:.2f} "
                f"({min_pct:.2f}%), above the {budget:.2f} budget; "
                f"stop too wide for this account",
            )
        desired = spec.volume_min

    volume = floor_to_step(desired, spec)
    if volume < spec.volume_min or volume <= 0:
        return RiskResult(Outcome.DECLINED, 0.0, 0.0, 0.0,
                          f"normalized volume {volume:.4f} is below the broker "
                          f"minimum {spec.volume_min:.4f}")

    risk = money_at_risk(volume, stop_distance, spec)
    pct = (risk / equity * 100.0) if equity > 0 else 0.0
    return RiskResult(
        Outcome.APPROVED, volume, risk, pct,
        f"size {volume:.2f} lots risking {risk:.2f} ({pct:.2f}% of equity)",
    )
