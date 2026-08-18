"""Bidirectional signal cross-examination between NeoFL specialist brains."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass(frozen=True)
class BrainSignal:
    origin: str
    symbol: str
    direction: str
    confidence: float
    evidence: tuple[str, ...] = ()
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class CrossExamination:
    signal: BrainSignal
    examiner: str
    stance: str
    confidence: float
    reasons: tuple[str, ...] = ()


class SignalExchange:
    """Routes signals for independent confirmation or disagreement.

    No specialist is given authority over another. The Soul receives all results.
    """

    def examine(self, signal: BrainSignal, examiner: str, *, stance: str, confidence: float, reasons: tuple[str, ...] = ()) -> CrossExamination:
        return CrossExamination(signal, examiner, stance, max(0.0, min(1.0, confidence)), reasons)
