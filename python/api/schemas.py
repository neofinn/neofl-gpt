"""Transport contracts for the NeoFL gateway."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class AnalyzeRequest:
    instrument: str
    task: str = "analyze"
    mode: str = "research"
    timeframes: tuple[str, ...] = ()
    context: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class AnalyzeResponse:
    request_id: str
    instrument: str
    state: str
    thesis: str | None
    confidence: float | None
    evidence: dict[str, Any] = field(default_factory=dict)
    conflicts: list[dict[str, Any]] = field(default_factory=list)
    risk_state: str | None = None
