"""FX relationship and synthetic cross analysis."""
from __future__ import annotations

from .models import FXQuote, RelationshipObservation, SyntheticCross


class FXRelationshipBrain:
    """Discovers and monitors mathematically linked FX relationships.

    Correlation is evidence, not a trade signal. Synthetic crosses are compared
    with executable observed markets after timestamps, quote quality and costs are
    considered by downstream validation/risk layers.
    """

    name = "fx-relationship"

    def synthetic_cross(self, *, first: FXQuote, second: FXQuote, target_symbol: str) -> SyntheticCross:
        """Construct a cross when the two legs share a common currency.

        For XAU/EUR from XAU/USD and EUR/USD, this naturally becomes
        XAU/USD divided by EUR/USD. The same algebra handles currency triangles
        when the leg orientation is supplied consistently.
        """
        if first.quote == second.quote:
            value = first_mid = self._mid(first) / self._mid(second)
            base = first.base
            quote = second.base
            method = f"{first.symbol} / {second.symbol}"
        elif first.base == second.base:
            value = self._mid(second) / self._mid(first)
            base = second.quote
            quote = first.quote
            method = f"{second.symbol} / {first.symbol}"
        else:
            raise ValueError("Quotes must share a common base or quote currency for this constructor")
        return SyntheticCross(target_symbol, base, quote, value, (first.symbol, second.symbol), min(first.timestamp, second.timestamp), method)

    def compare(self, synthetic: SyntheticCross, observed: FXQuote, *, historical_correlation: float | None = None, lead_lag_ms: float | None = None, directional_consistency: float | None = None) -> RelationshipObservation:
        observed_mid = self._mid(observed)
        residual = observed_mid - synthetic.implied_mid
        residual_bps = residual / max(abs(synthetic.implied_mid), 1e-12) * 10_000
        status = "ALIGNED" if abs(residual_bps) < 2.0 else "DIVERGENCE_CANDIDATE"
        return RelationshipObservation(
            target_symbol=observed.symbol,
            synthetic_value=synthetic.implied_mid,
            observed_mid=observed_mid,
            residual=residual,
            residual_bps=residual_bps,
            lead_lag_ms=lead_lag_ms,
            correlation=historical_correlation,
            directional_consistency=directional_consistency,
            status=status,
            rationale=(
                "Synthetic cross is a mathematical reference, not proof of arbitrage.",
                "Residual requires spread, latency, liquidity, financing and execution-cost validation before action.",
            ),
        )

    @staticmethod
    def _mid(q: FXQuote) -> float:
        return (q.bid + q.ask) / 2.0
