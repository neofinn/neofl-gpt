"""NeoFL price-relationship arbitrage engine.

This engine searches mathematically implied cross prices rather than relying
only on feed latency. It is analysis-only: it identifies opportunities and
passes them to Soul/Risk; it never places orders.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Iterable


@dataclass(frozen=True)
class PriceObservation:
    symbol: str
    bid: float
    ask: float
    timestamp: float


@dataclass(frozen=True)
class Relationship:
    target: str
    numerator: str
    denominator: str
    formula: str


@dataclass(frozen=True)
class ArbitrageOpportunity:
    relationship: Relationship
    direct_mid: float
    synthetic_mid: float
    discrepancy: float
    discrepancy_bps: float
    estimated_cost_bps: float
    executable_edge_bps: float
    direction: str
    state: str


class PriceArbitrageEngine:
    """Discovers cross-currency and gold/currency synthetic-price gaps."""

    def __init__(self, min_edge_bps: float = 2.0):
        self.min_edge_bps = min_edge_bps

    @staticmethod
    def mid(o: PriceObservation) -> float:
        return (o.bid + o.ask) / 2.0

    def evaluate(self, direct: PriceObservation, numerator: PriceObservation,
                 denominator: PriceObservation, estimated_cost_bps: float = 0.0
                 ) -> ArbitrageOpportunity | None:
        a = self.mid(numerator)
        b = self.mid(denominator)
        d = self.mid(direct)
        if min(a, b, d) <= 0 or not all(isfinite(x) for x in (a, b, d)):
            return None
        synthetic = a / b
        discrepancy = d - synthetic
        discrepancy_bps = (discrepancy / synthetic) * 10_000
        edge = abs(discrepancy_bps) - estimated_cost_bps
        direction = "SELL_DIRECT_BUY_SYNTHETIC" if discrepancy > 0 else "BUY_DIRECT_SELL_SYNTHETIC"
        state = "OPPORTUNITY" if edge >= self.min_edge_bps else "NO_NET_EDGE"
        return ArbitrageOpportunity(
            Relationship(direct.symbol, numerator.symbol, denominator.symbol,
                         f"{numerator.symbol}/{denominator.symbol}"),
            d, synthetic, discrepancy, discrepancy_bps, estimated_cost_bps,
            edge, direction, state,
        )

    def scan(self, observations: dict[str, PriceObservation], relationships: Iterable[Relationship],
             estimated_cost_bps: float = 0.0) -> list[ArbitrageOpportunity]:
        results: list[ArbitrageOpportunity] = []
        for r in relationships:
            if r.target not in observations or r.numerator not in observations or r.denominator not in observations:
                continue
            result = self.evaluate(observations[r.target], observations[r.numerator],
                                   observations[r.denominator], estimated_cost_bps)
            if result is not None:
                results.append(result)
        return sorted(results, key=lambda x: abs(x.executable_edge_bps), reverse=True)


def default_relationships(symbols: Iterable[str]) -> list[Relationship]:
    """Generate common USD-cross relationships when all legs are available."""
    s = set(symbols)
    out: list[Relationship] = []
    for base in ("AUD", "NZD", "GBP", "EUR", "CAD", "CHF", "JPY"):
        for quote in ("AUD", "NZD", "GBP", "EUR", "CAD", "CHF", "JPY"):
            if base == quote:
                continue
            direct = f"{base}{quote}"
            if direct in s and f"{base}USD" in s and f"{quote}USD" in s:
                out.append(Relationship(direct, f"{base}USD", f"{quote}USD", f"{base}USD/{quote}USD"))
    # Gold/currency synthetic relationships: XAUUSD / CCYUSD = XAUCcy.
    if "XAUUSD" in s:
        for ccy in ("EUR", "GBP", "AUD", "NZD", "CAD", "CHF", "JPY"):
            direct = f"XAU{ccy}"
            ccy_usd = f"{ccy}USD"
            if direct in s and ccy_usd in s:
                out.append(Relationship(direct, "XAUUSD", ccy_usd, f"XAUUSD/{ccy_usd}"))
    return out
