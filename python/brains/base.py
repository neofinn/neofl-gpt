"""Common specialist-brain protocol."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(frozen=True)
class BrainSignal:
    brain: str
    symbol: str
    direction: str | None
    state: str
    confidence: float | None = None
    evidence: dict[str, Any] = field(default_factory=dict)


class SpecialistBrain(Protocol):
    name: str

    def analyze(self, world_state: dict[str, Any], context: dict[str, Any] | None = None) -> BrainSignal: ...
