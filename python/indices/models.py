"""Canonical, time-aware models for index intelligence."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any


class WeightingMethod(str, Enum):
    FLOAT_ADJUSTED_MARKET_CAP = "FLOAT_ADJUSTED_MARKET_CAP"
    MARKET_CAP = "MARKET_CAP"
    PRICE_WEIGHTED = "PRICE_WEIGHTED"
    EQUAL_WEIGHTED = "EQUAL_WEIGHTED"
    CAPPED_MARKET_CAP = "CAPPED_MARKET_CAP"
    FACTOR_WEIGHTED = "FACTOR_WEIGHTED"
    OTHER = "OTHER"


@dataclass(frozen=True)
class IndexDefinition:
    index_id: str
    index_name: str
    provider: str
    methodology: str
    weighting_method: WeightingMethod
    calculation_method: str
    divisor_method: str | None = None
    currency: str | None = None
    trading_calendar: str | None = None
    trading_hours: str | None = None
    rebalance_frequency: str | None = None
    reconstitution_rules: str | None = None
    corporate_action_rules: str | None = None
    float_adjustment_rules: str | None = None
    weight_caps: dict[str, float] = field(default_factory=dict)
    sector_rules: str | None = None
    effective_from: datetime | None = None
    effective_to: datetime | None = None
    validation_status: str = "UNVALIDATED"


@dataclass(frozen=True)
class IndexConstituent:
    symbol: str
    name: str
    weight: float
    sector: str | None = None
    industry: str | None = None
    currency: str | None = None
    shares_or_float_factor: float | None = None
    effective_from: datetime | None = None
    effective_to: datetime | None = None


@dataclass(frozen=True)
class ConstituentObservation:
    canonical_symbol: str
    provider_symbol: str
    timestamp: datetime
    price: float
    returns: dict[str, float]
    data_age_seconds: float
    market_status: str
    source: str
    quality: float
    stale: bool = False


@dataclass(frozen=True)
class IndexAnalysis:
    index: str
    model_status: str
    methodology: str
    provider: str
    observed_direction: str
    underlying_direction: str
    index_return: dict[str, float]
    underlying_implied_return: dict[str, float]
    residual: dict[str, float]
    breadth: dict[str, float]
    weighted_breadth: dict[str, float]
    dispersion: dict[str, float]
    sector_contribution: dict[str, dict[str, float]]
    top_positive_contributors: list[dict[str, Any]]
    top_negative_contributors: list[dict[str, Any]]
    leaders: list[dict[str, Any]]
    laggards: list[dict[str, Any]]
    weighted_momentum: dict[str, float]
    index_momentum: dict[str, float]
    lead_lag_state: str
    divergence: str
    technical_state: dict[str, Any]
    session_state: dict[str, Any]
    volatility_state: dict[str, Any]
    data_quality: float
    constituent_coverage: float
    underlying_confirmation: str
    confidence: float
    state: str
    diagnostics: tuple[str, ...] = ()
