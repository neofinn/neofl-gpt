"""Methodology-aware constituent/index analysis engine.

This module is analysis-only. It never places orders. It refuses to produce a
validated underlying conclusion when the index model or constituent coverage is
insufficient.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import sqrt
from statistics import mean, pstdev
from typing import Iterable, Mapping, Sequence

from .models import ConstituentObservation, IndexAnalysis, IndexDefinition, IndexConstituent, WeightingMethod


HORIZONS = ("1m", "5m", "15m", "30m", "1h", "4h", "1D")


@dataclass(frozen=True)
class Contribution:
    symbol: str
    weight: float
    return_value: float
    contribution: float
    sector: str | None


def _direction(value: float, epsilon: float = 1e-12) -> str:
    if value > epsilon:
        return "BULLISH"
    if value < -epsilon:
        return "BEARISH"
    return "FLAT"


class IndexIntelligenceEngine:
    """Computes the causal/structural state of an index from its basket."""

    def __init__(self, *, min_weighted_coverage: float = 0.90, min_constituent_coverage: float = 0.80):
        self.min_weighted_coverage = min_weighted_coverage
        self.min_constituent_coverage = min_constituent_coverage

    def _active(self, definition: IndexDefinition, constituents: Sequence[IndexConstituent], timestamp) -> list[IndexConstituent]:
        return [c for c in constituents if
                (c.effective_from is None or timestamp >= c.effective_from) and
                (c.effective_to is None or timestamp < c.effective_to)]

    def _contributions(self, definition: IndexDefinition, constituents: Sequence[IndexConstituent], observations: Mapping[str, ConstituentObservation], horizon: str) -> list[Contribution]:
        active = self._active(definition, constituents, next(iter(observations.values())).timestamp)
        available = [c for c in active if c.symbol in observations and not observations[c.symbol].stale]
        if not available:
            return []

        if definition.weighting_method == WeightingMethod.PRICE_WEIGHTED:
            # A price-weighted index is not represented by market-cap weights.
            # Use price influence supplied by the constituent observations; callers
            # must provide the appropriate observation-level price data.
            total_price = sum(observations[c.symbol].price for c in available)
            if total_price <= 0:
                return []
            return [Contribution(c.symbol, observations[c.symbol].price / total_price,
                                 observations[c.symbol].returns.get(horizon, 0.0),
                                 observations[c.symbol].price / total_price * observations[c.symbol].returns.get(horizon, 0.0), c.sector)
                    for c in available]

        if definition.weighting_method == WeightingMethod.EQUAL_WEIGHTED:
            weight = 1.0 / len(available)
            return [Contribution(c.symbol, weight, observations[c.symbol].returns.get(horizon, 0.0),
                                 weight * observations[c.symbol].returns.get(horizon, 0.0), c.sector) for c in available]

        # Market-cap, float-adjusted, capped and factor-weighted models use the
        # effective constituent weights supplied by the versioned index definition.
        weight_sum = sum(max(0.0, c.weight) for c in available)
        if weight_sum <= 0:
            return []
        return [Contribution(c.symbol, c.weight / weight_sum, observations[c.symbol].returns.get(horizon, 0.0),
                             (c.weight / weight_sum) * observations[c.symbol].returns.get(horizon, 0.0), c.sector)
                for c in available]

    def analyze(self, definition: IndexDefinition, constituents: Sequence[IndexConstituent], observations: Mapping[str, ConstituentObservation], *, observed_returns: Mapping[str, float], index_momentum: Mapping[str, float] | None = None, technical_state: dict | None = None, session_state: dict | None = None, volatility_state: dict | None = None) -> IndexAnalysis:
        if definition.validation_status != "VALIDATED":
            return self._blocked(definition, "INDEX_MODEL_UNCERTAIN")
        if not observations:
            return self._blocked(definition, "UNDERLYING_ANALYSIS_INVALID")

        active = self._active(definition, constituents, next(iter(observations.values())).timestamp)
        active_weight = sum(max(0.0, c.weight) for c in active)
        fresh = [c for c in active if c.symbol in observations and not observations[c.symbol].stale]
        fresh_weight = sum(max(0.0, c.weight) for c in fresh)
        constituent_coverage = len(fresh) / len(active) if active else 0.0
        weighted_coverage = fresh_weight / active_weight if active_weight else 0.0
        data_quality = mean([observations[c.symbol].quality for c in fresh]) if fresh else 0.0

        if constituent_coverage < self.min_constituent_coverage or weighted_coverage < self.min_weighted_coverage:
            return self._blocked(definition, "UNDERLYING_ANALYSIS_INVALID", data_quality, constituent_coverage, weighted_coverage)

        implied: dict[str, float] = {}
        residual: dict[str, float] = {}
        breadth: dict[str, float] = {}
        weighted_breadth: dict[str, float] = {}
        dispersion: dict[str, float] = {}
        sector_contribution: dict[str, dict[str, float]] = {}
        positives: list[dict] = []
        negatives: list[dict] = []
        leaders: list[dict] = []
        laggards: list[dict] = []

        for horizon in HORIZONS:
            cs = self._contributions(definition, active, observations, horizon)
            if not cs:
                implied[horizon] = 0.0
                residual[horizon] = observed_returns.get(horizon, 0.0)
                breadth[horizon] = 0.0
                weighted_breadth[horizon] = 0.0
                dispersion[horizon] = 0.0
                continue
            implied[horizon] = sum(c.contribution for c in cs)
            residual[horizon] = observed_returns.get(horizon, 0.0) - implied[horizon]
            breadth[horizon] = sum(c.return_value > 0 for c in cs) / len(cs)
            weighted_breadth[horizon] = sum(c.weight for c in cs if c.return_value > 0) / sum(c.weight for c in cs)
            dispersion[horizon] = pstdev(c.return_value for c in cs) if len(cs) > 1 else 0.0

            by_sector: dict[str, float] = {}
            for c in cs:
                if c.sector:
                    by_sector[c.sector] = by_sector.get(c.sector, 0.0) + c.contribution
            sector_contribution[horizon] = by_sector

            if horizon == "5m":
                ordered = sorted(cs, key=lambda c: c.contribution, reverse=True)
                positives = [{"symbol": c.symbol, "weight": c.weight, "return": c.return_value, "contribution": c.contribution} for c in ordered[:10] if c.contribution > 0]
                negatives = [{"symbol": c.symbol, "weight": c.weight, "return": c.return_value, "contribution": c.contribution} for c in reversed(ordered[-10:]) if c.contribution < 0]
                leaders = [{"symbol": c.symbol, "weight": c.weight, "contribution": c.contribution} for c in ordered[:10]]
                laggards = [{"symbol": c.symbol, "weight": c.weight, "contribution": c.contribution} for c in ordered[-10:]]

        weighted_momentum = {h: implied[h] for h in HORIZONS}
        idx_momentum = index_momentum or {}
        short = "5m"
        if implied.get(short, 0.0) > 0 and observed_returns.get(short, 0.0) > 0 and weighted_breadth.get(short, 0.0) >= 0.5:
            confirmation = "STRONG"
        elif implied.get(short, 0.0) < 0 and observed_returns.get(short, 0.0) < 0 and weighted_breadth.get(short, 0.0) < 0.5:
            confirmation = "STRONG"
        else:
            confirmation = "MIXED"

        divergence = "NONE"
        if observed_returns.get(short, 0.0) <= 0 and implied.get(short, 0.0) > 0 and weighted_breadth.get(short, 0.0) > 0.5:
            divergence = "UNDERLYING_BULLISH_DIVERGENCE"
        elif observed_returns.get(short, 0.0) >= 0 and implied.get(short, 0.0) < 0 and weighted_breadth.get(short, 0.0) < 0.5:
            divergence = "UNDERLYING_BEARISH_DIVERGENCE"

        state = "BULLISH_CONFIRMED" if confirmation == "STRONG" and implied[short] > 0 else "BEARISH_CONFIRMED" if confirmation == "STRONG" and implied[short] < 0 else "UNDERLYING_DIVERGENCE" if divergence != "NONE" else "MIXED"
        return IndexAnalysis(
            index=definition.index_id, model_status=definition.validation_status, methodology=definition.methodology,
            provider=definition.provider, observed_direction=_direction(observed_returns.get(short, 0.0)), underlying_direction=_direction(implied[short]),
            index_return=dict(observed_returns), underlying_implied_return=implied, residual=residual, breadth=breadth,
            weighted_breadth=weighted_breadth, dispersion=dispersion, sector_contribution=sector_contribution,
            top_positive_contributors=positives, top_negative_contributors=negatives, leaders=leaders, laggards=laggards,
            weighted_momentum=weighted_momentum, index_momentum=idx_momentum, lead_lag_state="NOT_TESTED", divergence=divergence,
            technical_state=technical_state or {}, session_state=session_state or {}, volatility_state=volatility_state or {},
            data_quality=data_quality, constituent_coverage=weighted_coverage, underlying_confirmation=confirmation,
            confidence=min(1.0, max(0.0, data_quality * weighted_coverage)), state=state,
        )

    @staticmethod
    def _blocked(definition: IndexDefinition, state: str, quality: float = 0.0, coverage: float = 0.0, weighted_coverage: float = 0.0) -> IndexAnalysis:
        return IndexAnalysis(
            index=definition.index_id, model_status=definition.validation_status, methodology=definition.methodology, provider=definition.provider,
            observed_direction="UNKNOWN", underlying_direction="UNKNOWN", index_return={}, underlying_implied_return={}, residual={},
            breadth={}, weighted_breadth={}, dispersion={}, sector_contribution={}, top_positive_contributors=[], top_negative_contributors=[],
            leaders=[], laggards=[], weighted_momentum={}, index_momentum={}, lead_lag_state="NOT_TESTED", divergence="NONE",
            technical_state={}, session_state={}, volatility_state={}, data_quality=quality, constituent_coverage=weighted_coverage or coverage,
            underlying_confirmation="INSUFFICIENT_DATA", confidence=0.0, state=state,
            diagnostics=("Trading must be disabled until the index model and required underlying data are valid.",),
        )
