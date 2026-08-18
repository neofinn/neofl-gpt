"""Shared theory protocol."""
from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any
from python.data_contracts import DataRequirement, DataSnapshot

@dataclass(frozen=True)
class TheoryResult:
    theory: str
    version: str
    direction: int
    confidence: float
    regime: str | None
    evidence: tuple[str, ...] = ()
    invalidation: str | None = None
    data_complete: bool = True
    metadata: dict[str, Any] = field(default_factory=dict)

class TradingTheory(ABC):
    name: str
    version: str

    @abstractmethod
    def requirements(self) -> tuple[DataRequirement, ...]: ...

    @abstractmethod
    def evaluate(self, market: Any) -> TheoryResult | None: ...

    def data_ready(self, snapshot: DataSnapshot) -> bool:
        return all(snapshot.satisfies(r) for r in self.requirements())
