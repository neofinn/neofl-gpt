"""Straddle sizing — how many lots are needed to cover the main trade's gap loss.

Product owner's rule (2026-08-16):

    Main entry is fixed at 0.01 lots. The straddle is sized from how many lots are
    needed to cover the loss between the main entry and the straddle entry. The loss
    across that gap must always come back to zero.

THE EQUATION
------------
Main is long `Vm` at `Em`. It moves against us to `Es`, where a short straddle of `Vs`
opens. Gap = Em − Es, so the main is down `gap × Vm × k`.

Bucket P/L at price P:

    B(P) = (P − Em)·Vm·k  +  (Es − P)·Vs·k

Setting B = 0 at a target `D` below the straddle entry (P = Es − D):

    Vs = Vm · (gap + D) / D

WHAT THIS REVEALS
-----------------
"Cover the loss" does not determine a single size — it determines a *family* of sizes.
Every one of them reaches zero; they differ in how far price must travel to get there.

Expressing D as a fraction of the gap makes it intuitive. With D = gap/n:

    Vs = Vm · (n + 1)        and recovery happens in  gap / n

    n = 1  ->  Vs = 2 × main  ->  recovers in the full gap
    n = 2  ->  Vs = 3 × main  ->  recovers in half the gap    <- the legacy 0.03
    n = 3  ->  Vs = 4 × main  ->  recovers in a third
    n -> 0 ->  Vs -> main     ->  DELTA NEUTRAL, never recovers

The last line is the hazard. As the straddle approaches the main's size, the recovery
distance runs to infinity: the legs offset exactly, bucket P/L freezes, and waiting for
zero waits forever. `Vs > Vm` is not a preference, it is a requirement.

ROUNDING GOES THE OTHER WAY HERE
--------------------------------
Risk sizing floors to the broker's volume step, so a trade never risks more than
authorised. Straddle sizing must **ceil**: flooring would leave the gap under-covered, so
the bucket would stop just short of zero and the handover would never fire. Covering
slightly more than required is the safe direction; covering slightly less defeats the
mechanism.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum


class StraddleOutcome(Enum):
    APPROVED = "APPROVED"
    DECLINED = "DECLINED"   # evaluated, cannot size within the rules
    BLOCKED = "BLOCKED"     # cannot evaluate at all


@dataclass
class StraddleSizing:
    outcome: StraddleOutcome
    volume: float
    gap: float
    recovery_distance: float   # actual distance to zero, after rounding
    zero_price: float          # actual price at which the bucket reaches zero
    coverage: float            # covered / required; >= 1.0 means fully covered
    reason: str


def required_volume(main_volume: float, gap: float, recovery_distance: float) -> float:
    """Exact straddle volume to bring the bucket to zero `recovery_distance` past entry.

        Vs = Vm · (gap + D) / D
    """
    if recovery_distance <= 0:
        raise ValueError("recovery_distance must be positive")
    return main_volume * (gap + recovery_distance) / recovery_distance


def volume_for_ratio(main_volume: float, n: float) -> float:
    """Straddle volume that recovers in gap/n. Vs = Vm · (n + 1).

    n = 2 gives 3× the main volume — the legacy 0.03 against 0.01.
    """
    if n <= 0:
        raise ValueError("n must be positive; n -> 0 is the delta-neutral limit")
    return main_volume * (n + 1.0)


def ceil_to_step(volume: float, volume_min: float, volume_step: float) -> float:
    """Round UP onto the broker grid — see the module docstring on rounding direction."""
    if volume <= volume_min:
        return volume_min
    steps = math.ceil((volume - volume_min) / volume_step - 1e-9)
    digits = next((d for d in range(9) if abs(volume_step - round(volume_step, d)) < 1e-9), 8)
    return round(volume_min + steps * volume_step, digits)


class SizingMode(Enum):
    """Two readings of "size the straddle to cover the gap loss".

    RATIO — recover in gap/n. Volume is main·(n+1), which is **independent of the gap**:
    a 20-point gap and a 200-point gap both give 0.03 at n=2. This is what a fixed 0.03
    has been doing all along. Recovery distance scales with the gap.

    FIXED_DISTANCE — recover within a set distance D past the straddle entry, whatever
    the gap. Volume is main·(gap+D)/D, so it **grows with the gap**: a wider adverse move
    demands a larger straddle to claw it back over the same distance.

    The phrase "how many lots we need to cover the loss between main entry and straddle
    entry" describes FIXED_DISTANCE — the size follows the gap. RATIO keeps the size
    constant and lets the distance follow the gap instead. Both fully cover the loss.
    """

    RATIO = "RATIO"
    FIXED_DISTANCE = "FIXED_DISTANCE"


def size_straddle(
    *,
    main_volume: float,
    main_entry: float,
    straddle_entry: float,
    main_is_long: bool,
    mode: "SizingMode" = None,
    recovery_distance: float = 10.0,
    recovery_ratio: float = 2.0,
    volume_min: float = 0.01,
    volume_max: float = 100.0,
    volume_step: float = 0.01,
    money_per_unit_per_lot: float = 100.0,
) -> StraddleSizing:
    """Size the recovery straddle.

    `recovery_ratio` (n) sets how fast the bucket returns to zero: recovery happens in
    gap/n, and volume is main × (n+1). Default 2.0 reproduces the legacy 0.03 against
    0.01 — three times the main, recovering in half the gap.
    """
    # Gap is the adverse distance, always positive.
    gap = (main_entry - straddle_entry) if main_is_long else (straddle_entry - main_entry)

    if gap <= 0:
        return StraddleSizing(
            StraddleOutcome.BLOCKED, 0.0, gap, 0.0, 0.0, 0.0,
            "straddle entry is not adverse to the main entry; there is no loss to cover",
        )

    if main_volume <= 0:
        return StraddleSizing(StraddleOutcome.BLOCKED, 0.0, gap, 0.0, 0.0, 0.0,
                              "main volume is zero or negative")

    if recovery_ratio <= 0:
        return StraddleSizing(
            StraddleOutcome.BLOCKED, 0.0, gap, 0.0, 0.0, 0.0,
            "recovery ratio must be positive; n -> 0 is the delta-neutral limit "
            "where the bucket can never reach zero",
        )

    mode = mode or SizingMode.RATIO
    if mode is SizingMode.FIXED_DISTANCE:
        if recovery_distance <= 0:
            return StraddleSizing(StraddleOutcome.BLOCKED, 0.0, gap, 0.0, 0.0, 0.0,
                                  "recovery distance must be positive")
        exact = required_volume(main_volume, gap, recovery_distance)
    else:
        exact = volume_for_ratio(main_volume, recovery_ratio)
    volume = ceil_to_step(exact, volume_min, volume_step)

    if volume > volume_max:
        return StraddleSizing(
            StraddleOutcome.DECLINED, 0.0, gap, 0.0, 0.0, 0.0,
            f"required straddle {volume:.2f} exceeds the broker maximum {volume_max:.2f}",
        )

    # Rounding up must never land on or below the main volume — that is delta-neutral.
    if volume <= main_volume:
        return StraddleSizing(
            StraddleOutcome.DECLINED, 0.0, gap, 0.0, 0.0, 0.0,
            f"straddle {volume:.2f} is not larger than main {main_volume:.2f}; "
            "the bucket would be delta-neutral and could never reach zero",
        )

    # Recompute the ACTUAL recovery distance after rounding, rather than reporting the
    # requested one. Rounding up recovers slightly sooner; the caller should see the
    # real number.
    #   Vs = Vm(gap + D)/D  ->  D = gap·Vm / (Vs − Vm)
    actual_distance = gap * main_volume / (volume - main_volume)
    zero_price = (straddle_entry - actual_distance if main_is_long
                  else straddle_entry + actual_distance)

    coverage = volume / exact if exact > 0 else 0.0

    return StraddleSizing(
        StraddleOutcome.APPROVED,
        volume,
        gap,
        actual_distance,
        zero_price,
        coverage,
        f"straddle {volume:.2f} covers the {gap:.2f} gap "
        f"({gap * main_volume * money_per_unit_per_lot:.2f} loss); "
        f"bucket reaches zero at {zero_price:.2f}, {actual_distance:.2f} from straddle entry",
    )
