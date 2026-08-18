"""Data-feed comparison models."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any


class DataEdgeStatus(str, Enum):
    DATA_ARTIFACT = "DATA_ARTIFACT"
    NON_EXECUTABLE = "NON_EXECUTABLE"
    CANDIDATE = "CANDIDATE"
    VALIDATED = "VALIDATED"
    POLICY_BLOCKED = "POLICY_BLOCKED"


@dataclass(frozen=True)
class FeedObservation:
    source: str
    symbol: str
    timestamp: datetime
    bid: float
    ask: float
    sequence: int | None = None
    quality: float = 1.0
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class ArbitrageObservation:
    symbol: str
    reference: FeedObservation
    broker: FeedObservation
    timestamp_difference_ms: float
    bid_difference: float
    ask_difference: float
    executable_buy_edge: float
    executable_sell_edge: float
    estimated_total_cost: float
    edge_duration_ms: float | None
    status: DataEdgeStatus
    rationale: tuple[str, ...] = ()
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
