"""NeoFL Experiment Brain.

Research freedom is intentionally broad; execution authority is not. The brain can
create hypotheses and scenarios, run research through approved sandbox connectors,
and record results, but it has no LIVE connector permission.
"""
from __future__ import annotations

from dataclasses import replace
from typing import Iterable

from .models import ConnectorCapability, Experiment, ExperimentAuthorization, ExperimentStatus, Scenario


DEFAULT_SCENARIOS = (
    Scenario("MARKET_CRASH", "MARKET", "Severe index/market shock with volatility expansion", {"index_return": -0.08, "volatility_multiplier": 4.0}),
    Scenario("FLASH_CRASH", "MARKET", "Rapid adverse move with liquidity deterioration", {"price_shock": -0.04, "spread_multiplier": 5.0}),
    Scenario("BULL_TRAP", "STRUCTURE", "Breakout appears bullish while underlying leadership deteriorates", {"index_breakout": True, "underlying_direction": "BEARISH"}),
    Scenario("BEAR_TRAP", "STRUCTURE", "Breakdown appears bearish while underlying leadership improves", {"index_breakdown": True, "underlying_direction": "BULLISH"}),
    Scenario("LIQUIDITY_VACUUM", "LIQUIDITY", "Spread/slippage and market depth deteriorate sharply", {"spread_multiplier": 10.0, "slippage_multiplier": 5.0}),
    Scenario("INDEX_BASKET_DECOUPLING", "INDEX", "Observed index and underlying basket diverge materially", {"residual_multiplier": 5.0}),
    Scenario("LEADER_EXHAUSTION", "INDEX", "Largest weighted constituents lose momentum while index remains strong", {"leader_momentum": "FALLING", "index_state": "STRONG"}),
    Scenario("STALE_CONSTITUENT", "DATA", "Important constituent becomes stale or unavailable", {"stale_weight": 0.15}),
    Scenario("WORST_TO_WORST", "SYSTEM", "Compound market, data, execution and policy stress", {"market_crash": True, "spread_explosion": True, "stale_data": True, "execution_delay": True, "order_rejection": True}),
)


class ExperimentBrain:
    name = "experiment"

    def __init__(self, authorization: ExperimentAuthorization | None = None, scenarios: Iterable[Scenario] = DEFAULT_SCENARIOS) -> None:
        self.authorization = authorization or ExperimentAuthorization()
        self.scenarios = tuple(scenarios)
        self.ledger: dict[str, Experiment] = {}

    def create(self, experiment: Experiment) -> Experiment:
        self.ledger[experiment.experiment_id] = experiment
        return experiment

    def propose(self, *, experiment_id: str, hypothesis: str, origin: str, **kwargs) -> Experiment:
        return self.create(Experiment(experiment_id=experiment_id, hypothesis=hypothesis, origin=origin, status=ExperimentStatus.HYPOTHESIS, **kwargs))

    def run_permission(self, capability: ConnectorCapability) -> bool:
        return self.authorization.permits(capability)

    def record_result(self, experiment_id: str, *, status: ExperimentStatus, results: dict, sample_size: int = 0) -> Experiment:
        current = self.ledger[experiment_id]
        updated = replace(current, status=status, results=dict(results), sample_size=sample_size)
        self.ledger[experiment_id] = updated
        return updated

    def promote_candidate(self, experiment_id: str, *, validated: bool) -> Experiment:
        current = self.ledger[experiment_id]
        status = ExperimentStatus.CANDIDATE if validated else ExperimentStatus.REJECTED
        updated = replace(current, status=status)
        self.ledger[experiment_id] = updated
        return updated

    def can_execute_live(self) -> bool:
        return self.authorization.permits(ConnectorCapability.LIVE)
