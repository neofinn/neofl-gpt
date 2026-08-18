"""Provider-neutral contracts for LLM-assisted NeoFL cognition."""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class ModelRole(str, Enum):
    REASONER = "REASONER"
    RESEARCHER = "RESEARCHER"
    ADVERSARIAL = "ADVERSARIAL"
    SYNTHESIZER = "SYNTHESIZER"


@dataclass(frozen=True)
class CognitiveRequest:
    role: ModelRole
    task: str
    context: dict[str, Any] = field(default_factory=dict)
    constraints: tuple[str, ...] = ()


@dataclass(frozen=True)
class CognitiveResponse:
    role: ModelRole
    output: str
    structured: dict[str, Any] = field(default_factory=dict)
    confidence: float | None = None
    evidence: tuple[str, ...] = ()
    model: str | None = None
