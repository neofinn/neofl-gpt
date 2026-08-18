"""FX relationship and synthetic cross data contracts."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass(frozen=True)
class FXQuote:
    symbol: str
    base: str
    quote: str
    bid: float
    ask: float
    timestamp: datetime
    source: str
    quality: float = 1.0


@dataclass(frozen=True)
class SyntheticCross:
    symbol: str
    base: str
    quote: str
    implied_mid: float
    legs: tuple[str, ...]
    timestamp: datetime
    methodology: str


@dataclass(frozen=True)
class RelationshipObservation:
    target_symbol: str
    synthetic_value: float
    observed_mid: float
    residual: float
    residual_bps: float
    lead_lag_ms: float | None
    correlation: float | None
    directional_consistency: float | None
    status: str
    rationale: tuple[str, ...] = ()
    metadata: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
