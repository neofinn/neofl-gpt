"""Experiment, scenario and connector authorization models."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any


class ExperimentStatus(str, Enum):
    IDEA = "IDEA"
    HYPOTHESIS = "HYPOTHESIS"
    RUNNING = "RUNNING"
    PROMISING = "PROMISING"
    VALIDATING = "VALIDATING"
    VALIDATED = "VALIDATED"
    CANDIDATE = "CANDIDATE"
    PROMOTED = "PROMOTED"
    REJECTED = "REJECTED"


class ConnectorCapability(str, Enum):
    BACKTEST = "BACKTEST"
    PAPER = "PAPER"
    DEMO = "DEMO"
    LIVE = "LIVE"


@dataclass(frozen=True)
class Scenario:
    name: str
    category: str
    description: str
    shocks: dict[str, Any] = field(default_factory=dict)
    impossible_or_extreme: bool = False


@dataclass(frozen=True)
class Experiment:
    experiment_id: str
    hypothesis: str
    origin: str
    market: str | None = None
    instrument: str | None = None
    timeframe: str | None = None
    control_version: str | None = None
    experimental_version: str | None = None
    scenario: Scenario | None = None
    status: ExperimentStatus = ExperimentStatus.IDEA
    sample_size: int = 0
    results: dict[str, Any] = field(default_factory=dict)
    failure_conditions: tuple[str, ...] = ()
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


@dataclass(frozen=True)
class ExperimentAuthorization:
    """Hard capability boundary for the Experiment Brain."""
    allowed: frozenset[ConnectorCapability] = frozenset({
        ConnectorCapability.BACKTEST,
        ConnectorCapability.PAPER,
        ConnectorCapability.DEMO,
    })

    def permits(self, capability: ConnectorCapability) -> bool:
        return capability in self.allowed
