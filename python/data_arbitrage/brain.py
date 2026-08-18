"""Reference-feed vs connected-broker data-arbitrage analysis."""
from __future__ import annotations

from .models import ArbitrageObservation, DataEdgeStatus, FeedObservation


class DataArbitrageBrain:
    """Detects time/quote discrepancies and tests whether they are executable.

    This is analytical only. Account/firm policy and the Execution Fabric decide
    whether any candidate edge is permitted to be acted upon.
    """

    name = "data-arbitrage"

    def compare(self, reference: FeedObservation, broker: FeedObservation, *, estimated_total_cost: float = 0.0, edge_duration_ms: float | None = None, policy_allows: bool = True) -> ArbitrageObservation:
        if reference.symbol != broker.symbol:
            raise ValueError("Reference and broker symbols must be normalized to the same canonical instrument")
        dt_ms = (broker.timestamp - reference.timestamp).total_seconds() * 1000.0
        buy_edge = reference.ask - broker.ask
        sell_edge = broker.bid - reference.bid
        net_buy = buy_edge - estimated_total_cost
        net_sell = sell_edge - estimated_total_cost
        if not policy_allows:
            status = DataEdgeStatus.POLICY_BLOCKED
            rationale = ("Account/firm policy prohibits acting on this data edge.",)
        elif max(net_buy, net_sell) <= 0:
            status = DataEdgeStatus.NON_EXECUTABLE
            rationale = ("Observed quote difference does not exceed estimated executable costs.",)
        elif dt_ms <= 0:
            status = DataEdgeStatus.DATA_ARTIFACT
            rationale = ("No positive reference-to-broker timing advantage was established.",)
        else:
            status = DataEdgeStatus.CANDIDATE
            rationale = ("Positive reference-to-broker timing difference with a net quote edge; requires historical and demo validation.",)
        return ArbitrageObservation(
            symbol=reference.symbol,
            reference=reference,
            broker=broker,
            timestamp_difference_ms=dt_ms,
            bid_difference=broker.bid - reference.bid,
            ask_difference=broker.ask - reference.ask,
            executable_buy_edge=net_buy,
            executable_sell_edge=net_sell,
            estimated_total_cost=estimated_total_cost,
            edge_duration_ms=edge_duration_ms,
            status=status,
            rationale=rationale,
        )
