"""Central NeoFL Soul: synthesize independent specialist evidence."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable

from python.brains.base import BrainSignal


@dataclass(frozen=True)
class SoulDecision:
    symbol: str
    state: str
    direction: str | None
    confidence: float | None
    signals: tuple[BrainSignal, ...] = ()
    conflicts: tuple[str, ...] = ()
    rationale: tuple[str, ...] = ()


class Soul:
    """Evidence synthesizer, not a direct execution authority."""

    name = "soul"

    def deliberate(self, symbol: str, signals: Iterable[BrainSignal]) -> SoulDecision:
        items = tuple(s for s in signals if s.symbol == symbol)
        directional = [s.direction for s in items if s.direction in {"LONG", "SHORT"}]
        if not items:
            return SoulDecision(symbol, "INSUFFICIENT_DATA", None, None)
        longs = directional.count("LONG")
        shorts = directional.count("SHORT")
        if longs and shorts:
            state = "CONFLICT"
            direction = "LONG" if longs > shorts else "SHORT" if shorts > longs else None
            conflicts = (f"Specialists disagree: LONG={longs}, SHORT={shorts}",)
        elif longs:
            state, direction, conflicts = "BULLISH_CONSENSUS", "LONG", ()
        elif shorts:
            state, direction, conflicts = "BEARISH_CONSENSUS", "SHORT", ()
        else:
            state, direction, conflicts = "MIXED", None, ()
        confidences = [s.confidence for s in items if s.confidence is not None]
        confidence = sum(confidences) / len(confidences) if confidences else None
        return SoulDecision(symbol, state, direction, confidence, items, conflicts, ("Decision is based on independent specialist evidence; risk and execution remain downstream gates.",))
