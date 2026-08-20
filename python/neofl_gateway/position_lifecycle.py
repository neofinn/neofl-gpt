"""Post-fill position lifecycle for the agentic Body.

The Brain is responsible for the entry decision. Once MT5 confirms an actual
fill, the Body owns the resulting position lifecycle and activates the existing
risk/straddle/bucket management components. No pre-entry risk/straddle mutation
is performed here.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable


@dataclass(frozen=True)
class ExecutionFill:
    order_id: str
    symbol: str
    side: str
    volume: float
    price: float
    timestamp: float
    broker_position_id: str | None = None
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass
class PositionLifecycle:
    fill: ExecutionFill
    risk_active: bool = False
    straddle_active: bool = False
    bucket_active: bool = False
    management_state: str = "FILLED"
    risk_result: Any = None
    straddle_result: Any = None
    bucket_result: Any = None


class PostFillManager:
    """Activates management only after a confirmed broker fill."""

    def __init__(self, *, risk_engine: Callable[[ExecutionFill], Any] | None = None,
                 straddle_engine: Callable[[ExecutionFill], Any] | None = None,
                 bucket_engine: Callable[[ExecutionFill], Any] | None = None) -> None:
        self.risk_engine = risk_engine
        self.straddle_engine = straddle_engine
        self.bucket_engine = bucket_engine
        self.positions: dict[str, PositionLifecycle] = {}

    def on_fill(self, fill: ExecutionFill) -> PositionLifecycle:
        key = fill.broker_position_id or fill.order_id
        lifecycle = PositionLifecycle(fill=fill)

        # This is deliberately the first point at which management engines run.
        if self.risk_engine is not None:
            lifecycle.risk_result = self.risk_engine(fill)
            lifecycle.risk_active = True
        if self.straddle_engine is not None:
            lifecycle.straddle_result = self.straddle_engine(fill)
            lifecycle.straddle_active = True
        if self.bucket_engine is not None:
            lifecycle.bucket_result = self.bucket_engine(fill)
            lifecycle.bucket_active = True

        lifecycle.management_state = "MANAGING"
        self.positions[key] = lifecycle
        return lifecycle

    def on_close(self, position_id: str) -> PositionLifecycle | None:
        lifecycle = self.positions.pop(position_id, None)
        if lifecycle is not None:
            lifecycle.management_state = "CLOSED"
        return lifecycle

    def snapshot(self) -> list[dict[str, Any]]:
        return [
            {
                "position_id": key,
                "order_id": item.fill.order_id,
                "symbol": item.fill.symbol,
                "side": item.fill.side,
                "volume": item.fill.volume,
                "price": item.fill.price,
                "management_state": item.management_state,
                "risk_active": item.risk_active,
                "straddle_active": item.straddle_active,
                "bucket_active": item.bucket_active,
            }
            for key, item in self.positions.items()
        ]
