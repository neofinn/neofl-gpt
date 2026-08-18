"""Three-stage reasoning contract: market -> thesis -> trade."""
from __future__ import annotations
from dataclasses import dataclass
from python.theories.base import TheoryResult
from python.risk.engine import RiskDecision

@dataclass(frozen=True)
class MarketAnalysis:
    regime: str
    direction: int
    volatility: str
    evidence: tuple[str, ...] = ()

@dataclass(frozen=True)
class ThesisAnalysis:
    results: tuple[TheoryResult, ...]
    dominant_direction: int
    confidence: float
    conflicts: tuple[str, ...] = ()

@dataclass(frozen=True)
class TradeAnalysis:
    direction: int
    valid: bool
    reason: str
    risk: RiskDecision | None = None

class ThesisSynthesizer:
    def synthesize(self, results: list[TheoryResult]) -> ThesisAnalysis:
        usable = [r for r in results if r.data_complete and r.direction != 0]
        if not usable:
            return ThesisAnalysis((), 0, 0.0, ("no usable thesis",))
        scores = {1: 0.0, -1: 0.0}
        for r in usable:
            scores[r.direction] += max(0.0, min(1.0, r.confidence))
        direction = 1 if scores[1] > scores[-1] else -1 if scores[-1] > scores[1] else 0
        total = scores[1] + scores[-1]
        confidence = scores[direction] / total if direction and total else 0.0
        conflicts = tuple(r.theory for r in usable if direction and r.direction != direction)
        return ThesisAnalysis(tuple(usable), direction, confidence, conflicts)
