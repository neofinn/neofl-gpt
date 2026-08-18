"""NeoFL agentic brain orchestration skeleton."""
from __future__ import annotations
from dataclasses import dataclass
from python.data_contracts import DataSnapshot
from python.theories.registry import TheoryRegistry
from .thesis import MarketAnalysis, ThesisAnalysis, TradeAnalysis, ThesisSynthesizer

@dataclass
class BrainCycle:
    market: MarketAnalysis | None = None
    thesis: ThesisAnalysis | None = None
    trade: TradeAnalysis | None = None

class NeoFLBrain:
    """Observe -> evaluate available theories -> synthesize -> hand off."""
    def __init__(self, registry: TheoryRegistry) -> None:
        self.registry = registry
        self.synthesizer = ThesisSynthesizer()
        self.last_cycle = BrainCycle()

    def evaluate(self, market: object, data: DataSnapshot) -> BrainCycle:
        results = []
        for theory in self.registry.all():
            if not theory.data_ready(data):
                continue
            result = theory.evaluate(market)
            if result is not None:
                results.append(result)
        thesis = self.synthesizer.synthesize(results)
        self.last_cycle = BrainCycle(thesis=thesis)
        return self.last_cycle
