"""Deterministic, fail-closed NeoFL trade risk gate."""
from __future__ import annotations
from dataclasses import dataclass
from enum import Enum

class RiskOutcome(Enum):
    APPROVED = "APPROVED"
    DECLINED = "DECLINED"
    BLOCKED = "BLOCKED"

@dataclass(frozen=True)
class RiskContext:
    equity: float
    balance: float
    open_positions: int
    open_exposure_lots: float
    max_open_positions: int = 1
    max_exposure_lots: float = 0.0

@dataclass(frozen=True)
class RiskDecision:
    outcome: RiskOutcome
    requested_lots: float
    approved_lots: float
    reason: str

class RiskEngine:
    def evaluate(self, requested_lots: float, ctx: RiskContext) -> RiskDecision:
        if requested_lots <= 0:
            return RiskDecision(RiskOutcome.BLOCKED, requested_lots, 0.0, "requested size <= 0")
        if ctx.equity <= 0 or ctx.balance <= 0:
            return RiskDecision(RiskOutcome.BLOCKED, requested_lots, 0.0, "account state invalid")
        if ctx.max_open_positions > 0 and ctx.open_positions >= ctx.max_open_positions:
            return RiskDecision(RiskOutcome.DECLINED, requested_lots, 0.0, "max open positions reached")
        if ctx.max_exposure_lots > 0:
            room = ctx.max_exposure_lots - ctx.open_exposure_lots
            if room <= 0:
                return RiskDecision(RiskOutcome.DECLINED, requested_lots, 0.0, "exposure limit reached")
            if requested_lots > room:
                return RiskDecision(RiskOutcome.DECLINED, requested_lots, 0.0, "requested exposure exceeds limit")
        return RiskDecision(RiskOutcome.APPROVED, requested_lots, requested_lots, "risk checks passed")
