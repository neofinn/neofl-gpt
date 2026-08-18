"""Canonical option-chain and instrument-comparison models."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass(frozen=True)
class OptionContract:
    underlying: str
    symbol: str
    expiry: datetime
    strike: float
    option_type: str  # CALL | PUT
    multiplier: float = 1.0


@dataclass(frozen=True)
class OptionObservation:
    contract: OptionContract
    timestamp: datetime
    bid: float
    ask: float
    last: float
    volume: float
    open_interest: float
    implied_volatility: float | None
    delta: float | None
    gamma: float | None
    theta: float | None
    vega: float | None
    rho: float | None
    underlying_price: float
    expected_move: float | None = None
    data_age_seconds: float = 0.0
    quality: float = 1.0
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def mid(self) -> float:
        return (self.bid + self.ask) / 2.0

    @property
    def spread(self) -> float:
        return max(0.0, self.ask - self.bid)


@dataclass(frozen=True)
class OptionThesis:
    direction: str
    horizon: str
    expected_underlying_move: float | None
    preferred_contracts: tuple[str, ...]
    greek_state: dict[str, Any]
    volatility_state: dict[str, Any]
    liquidity_state: dict[str, Any]
    rationale: tuple[str, ...] = ()


@dataclass(frozen=True)
class InstrumentComparison:
    underlying: str
    thesis_direction: str
    direct_expected_return: float | None
    option_expected_return: float | None
    direct_capital_required: float | None
    option_premium_required: float | None
    direct_max_loss: float | None
    option_max_loss: float | None
    direct_score: float
    option_score: float
    preferred_instrument: str
    rationale: tuple[str, ...] = ()
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
