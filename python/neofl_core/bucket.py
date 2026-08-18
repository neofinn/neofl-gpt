"""Reference implementation of the NeoFL Bucket engine.

Canon: a bucket is a *portfolio of related positions*, not one position. Bucket P/L and
individual trade P/L are different concepts, and conflating them is the single most
common way recovery logic goes wrong.

Legacy analysis (docs/architecture/LEGACY_STRADDLE_DEFECTS.md) established that in this
architecture the basket mechanism *is* the risk control — there are no broker stops
behind it. So bucket integrity is a safety property, and every function here either
returns a correct answer or refuses. None of them guess.

Six constraints carried from that analysis:

  1. One basket authority — this module, and nothing else, computes bucket state.
  2. Identity by magic number, never by comment. Comments are not reliable broker state.
  3. The zero-floating level is computed, and its non-existence is detected (see below).
  4. Costs are included, or their absence is declared.
  5. Consumers can tell "unknown" from "zero".
  6. At bucket zero: close the main, keep the straddle.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Role(Enum):
    """What a position is *for* within its bucket.

    Identity comes from the magic number, not a comment string. Legacy shared one magic
    across roles and discriminated on comment text — which brokers truncate, rewrite on
    partial fill, or strip. Worse, the legacy main-position scan used the same test
    inverted, so a stripped comment made the straddle be mistaken *for* the main trade.
    """

    MAIN = "MAIN"
    STRADDLE = "STRADDLE"
    LINKED = "LINKED"


class Direction(Enum):
    BUY = 1
    SELL = -1


@dataclass
class Position:
    ticket: int
    role: Role
    direction: Direction
    volume: float
    entry_price: float
    # Money per price-unit per lot. From broker contract spec; never assumed.
    money_per_unit_per_lot: float
    swap: float = 0.0
    commission: float = 0.0

    def floating(self, price: float) -> float:
        """Floating P/L at `price`, costs included."""
        move = (price - self.entry_price) * self.direction.value
        return move * self.volume * self.money_per_unit_per_lot + self.swap + self.commission

    def signed_exposure(self) -> float:
        """Volume signed by direction. Long 0.01 + short 0.03 = -0.02."""
        return self.volume * self.direction.value


class BucketState(Enum):
    EMPTY = "EMPTY"
    MAIN_ONLY = "MAIN_ONLY"
    RECOVERING = "RECOVERING"        # main + straddle, bucket still negative
    BASKET_NEUTRAL = "BASKET_NEUTRAL"  # bucket floating reached zero
    RUNNER = "RUNNER"                # main closed, straddle survives
    CLOSED = "CLOSED"


@dataclass
class Bucket:
    """A group of related positions tracked as one aggregate."""

    bucket_id: str
    symbol: str
    positions: list[Position] = field(default_factory=list)
    realized: float = 0.0            # closed P/L belonging to this bucket

    # --- composition -------------------------------------------------------------

    def by_role(self, role: Role) -> list[Position]:
        return [p for p in self.positions if p.role is role]

    @property
    def main(self) -> Position | None:
        m = self.by_role(Role.MAIN)
        return m[0] if m else None

    @property
    def straddle(self) -> Position | None:
        s = self.by_role(Role.STRADDLE)
        return s[0] if s else None

    # --- aggregates --------------------------------------------------------------

    def floating(self, price: float) -> float:
        return sum(p.floating(price) for p in self.positions)

    def total(self, price: float) -> float:
        """Bucket P/L: realized plus floating. This is the number recovery keys off."""
        return self.realized + self.floating(price)

    def net_exposure(self) -> float:
        """Signed volume across the bucket. Zero means delta-neutral — see below."""
        return sum(p.signed_exposure() for p in self.positions)

    def gross_exposure(self) -> float:
        return sum(p.volume for p in self.positions)

    # --- the critical calculation -------------------------------------------------

    def zero_floating_price(self) -> float | None:
        """Price at which bucket P/L reaches zero. None when no such price exists.

        Solving  sum( d_i * v_i * k_i * (P - e_i) ) + costs + realized = 0  for P:

            P = ( sum(d_i * v_i * k_i * e_i) - costs - realized ) / sum(d_i * v_i * k_i)

        **The denominator can be zero.** If the bucket is delta-neutral — say a 0.01 long
        against a 0.01 short — then price movement changes nothing: the legs offset
        exactly and bucket P/L is frozen at whatever the costs make it. There is no price
        at which it reaches zero, and waiting for one waits forever.

        This is not a contrived case. It is what a same-size hedge produces, and it is
        why the legacy design uses 0.03 against 0.01 rather than 0.01 against 0.01.

        Returning None here is the difference between a recovery system that reports
        "this bucket cannot recover through price" and one that silently never fires.
        """
        denominator = sum(
            p.signed_exposure() * p.money_per_unit_per_lot for p in self.positions
        )
        if abs(denominator) < 1e-12:
            return None

        numerator = sum(
            p.signed_exposure() * p.money_per_unit_per_lot * p.entry_price
            for p in self.positions
        )
        costs = sum(p.swap + p.commission for p in self.positions)
        return (numerator - costs - self.realized) / denominator

    def is_delta_neutral(self) -> bool:
        """True when price movement cannot change bucket P/L."""
        return self.zero_floating_price() is None

    # --- state --------------------------------------------------------------------

    def state(self, price: float) -> BucketState:
        has_main = self.main is not None
        has_straddle = self.straddle is not None

        if not self.positions:
            return BucketState.CLOSED if self.realized else BucketState.EMPTY
        if has_main and not has_straddle:
            return BucketState.MAIN_ONLY
        if not has_main and has_straddle:
            return BucketState.RUNNER
        if has_main and has_straddle:
            return (BucketState.BASKET_NEUTRAL if self.total(price) >= 0.0
                    else BucketState.RECOVERING)
        return BucketState.EMPTY

    def ready_for_handover(self, price: float) -> bool:
        """Has the bucket reached the point where the main closes and the straddle runs?

        Canon: at bucket zero, move the straddle's stop to the neutral level, close the
        original losing main trade, and let the straddle continue as the profit runner.

        Requires both legs present and bucket P/L at or above zero. A delta-neutral
        bucket can never satisfy this through price, which `zero_floating_price()`
        reports as None.
        """
        return (self.main is not None
                and self.straddle is not None
                and self.total(price) >= 0.0)
