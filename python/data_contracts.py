"""Canonical market-data contracts for the NeoFL brain."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import FrozenSet

@dataclass(frozen=True)
class DataRequirement:
    timeframe: str
    bars: int
    closed_only: bool = True
    volume: bool = False
    ticks: bool = False
    dom: bool = False
    external: FrozenSet[str] = field(default_factory=frozenset)

@dataclass(frozen=True)
class DataSnapshot:
    symbol: str
    available_timeframes: FrozenSet[str]
    bars: dict[str, int]
    volume_source: str | None = None
    ticks_available: bool = False
    dom_available: bool = False
    external_sources: FrozenSet[str] = field(default_factory=frozenset)

    def satisfies(self, req: DataRequirement) -> bool:
        return (self.bars.get(req.timeframe, 0) >= req.bars and
                (not req.volume or self.volume_source is not None) and
                (not req.ticks or self.ticks_available) and
                (not req.dom or self.dom_available) and
                req.external.issubset(self.external_sources))

@dataclass(frozen=True)
class DataStatus:
    requirement: DataRequirement
    available: bool
    reason: str
