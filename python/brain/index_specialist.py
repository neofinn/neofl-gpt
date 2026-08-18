"""Index specialist brain adapter for the NeoFL Soul.

The specialist treats an index as both a tradable asset and an aggregation. It
reports observed-vs-underlying state and forward-looking evidence; it never trades.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from ..indices.engine import IndexIntelligenceEngine
from ..indices.models import ConstituentObservation, IndexAnalysis, IndexConstituent, IndexDefinition


@dataclass
class IndexBrainResult:
    analysis: IndexAnalysis
    forecast: dict[str, Any]


class IndexSpecialistBrain:
    name = "index-intelligence"

    def __init__(self, engine: IndexIntelligenceEngine | None = None) -> None:
        self.engine = engine or IndexIntelligenceEngine()

    def analyze(self, world: Any) -> IndexBrainResult:
        analysis = self.engine.analyze(
            world.definition,
            world.constituents,
            world.observations,
            observed_returns=world.observed_returns,
            index_momentum=getattr(world, "index_momentum", None),
            technical_state=getattr(world, "technical_state", None),
            session_state=getattr(world, "session_state", None),
            volatility_state=getattr(world, "volatility_state", None),
        )
        forecast = self._forecast(analysis)
        return IndexBrainResult(analysis=analysis, forecast=forecast)

    @staticmethod
    def _forecast(analysis: IndexAnalysis) -> dict[str, Any]:
        """Conservative forward state from currently observed basket evidence.

        This is a forecast *state*, not a probability claim. Calibrated probabilities
        require historical lead/lag training and are intentionally left to the
        learning/validation layer.
        """
        if analysis.state == "INDEX_MODEL_UNCERTAIN" or analysis.state == "UNDERLYING_ANALYSIS_INVALID":
            return {"state": "UNAVAILABLE", "reason": analysis.state}
        short = analysis.underlying_implied_return.get("5m", 0.0)
        breadth = analysis.weighted_breadth.get("5m", 0.0)
        if short > 0 and breadth > 0.5:
            state = "FORWARD_BULLISH_BIAS"
        elif short < 0 and breadth < 0.5:
            state = "FORWARD_BEARISH_BIAS"
        else:
            state = "FORWARD_MIXED"
        return {
            "state": state,
            "horizon": "5m",
            "basis": "underlying_weighted_return_and_breadth",
            "lead_lag": analysis.lead_lag_state,
            "divergence": analysis.divergence,
            "confidence": analysis.confidence,
        }
