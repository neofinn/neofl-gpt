"""Liquid Flow ARK engine foundation.

ARK is intentionally isolated from NeoFL risk/execution.  The current foundation
uses the rules already defined for Liquid Flow ARK 7.1:

1. confirmed swing structure
2. BOS detection
3. order-block / FVG zone representation
4. zone mitigation
5. POC / VAH / VAL value-area confluence
6. directional opportunity -> lower-timeframe confirmation boundary

The proprietary CHoCH/entry/reassessment rules that have not been finalized are NOT
invented here.  `ARKOpportunity` exposes the evidence so the brain can pass it to a
later confirmation module.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Sequence


class Direction(Enum):
    NONE = 0
    LONG = 1
    SHORT = -1


@dataclass(frozen=True)
class Bar:
    time: int
    open: float
    high: float
    low: float
    close: float
    volume: float = 0.0


@dataclass(frozen=True)
class Swing:
    index: int
    price: float
    direction: Direction


@dataclass(frozen=True)
class ValueArea:
    poc: float
    vah: float
    val: float


@dataclass(frozen=True)
class ARKOpportunity:
    direction: Direction
    structure_confirmed: bool
    bos: bool
    value_confluence: bool
    zone_mitigated: bool
    lower_tf_confirmation_required: bool = True


class LiquidARKEngine:
    """Deterministic ARK evidence engine; not an execution engine."""

    name = "liquid_flow_ark"
    version = "7.1-foundation"

    @staticmethod
    def swings(bars: Sequence[Bar], left: int = 2, right: int = 2) -> list[Swing]:
        out: list[Swing] = []
        if len(bars) < left + right + 1:
            return out
        for i in range(left, len(bars) - right):
            h = bars[i].high
            l = bars[i].low
            if all(h > bars[j].high for j in range(i-left, i) if j >= 0) and \
               all(h >= bars[j].high for j in range(i+1, i+right+1)):
                out.append(Swing(i, h, Direction.SHORT))
            if all(l < bars[j].low for j in range(i-left, i) if j >= 0) and \
               all(l <= bars[j].low for j in range(i+1, i+right+1)):
                out.append(Swing(i, l, Direction.LONG))
        return out

    @staticmethod
    def bos(bars: Sequence[Bar], structure: Sequence[Swing]) -> Direction:
        if not bars or not structure:
            return Direction.NONE
        last = bars[-1].close
        highs = [s.price for s in structure if s.direction is Direction.SHORT]
        lows = [s.price for s in structure if s.direction is Direction.LONG]
        if highs and last > highs[-1]:
            return Direction.LONG
        if lows and last < lows[-1]:
            return Direction.SHORT
        return Direction.NONE

    @staticmethod
    def value_confluence(price: float, value: ValueArea, tolerance: float) -> bool:
        return any(abs(price - level) <= tolerance for level in (value.poc, value.vah, value.val))

    def evaluate(
        self,
        bars: Sequence[Bar],
        value_area: ValueArea | None = None,
        tolerance: float = 0.0,
        zone_mitigated: bool = False,
    ) -> ARKOpportunity | None:
        structure = self.swings(bars)
        direction = self.bos(bars, structure)
        if direction is Direction.NONE:
            return None
        confluence = bool(value_area and self.value_confluence(bars[-1].close, value_area, tolerance))
        return ARKOpportunity(
            direction=direction,
            structure_confirmed=bool(structure),
            bos=True,
            value_confluence=confluence,
            zone_mitigated=zone_mitigated,
        )
