"""Canonical execution objects shared by every platform adapter."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any


class Side(str, Enum):
    BUY = "BUY"
    SELL = "SELL"


class OrderType(str, Enum):
    MARKET = "MARKET"
    LIMIT = "LIMIT"
    STOP = "STOP"
    STOP_LIMIT = "STOP_LIMIT"


@dataclass(frozen=True)
class OrderIntent:
    symbol: str
    side: Side
    order_type: OrderType
    quantity: float
    entry_price: float | None = None
    stop_price: float | None = None
    take_profit: float | None = None
    time_in_force: str | None = None
    strategy: str | None = None
    thesis_id: str | None = None
    risk_profile: str | None = None
    account_id: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


@dataclass(frozen=True)
class ExecutionReport:
    intent_id: str
    status: str
    platform: str
    broker_or_firm: str | None = None
    order_id: str | None = None
    filled_quantity: float = 0.0
    average_price: float | None = None
    fees: float = 0.0
    slippage: float | None = None
    reason: str | None = None
    raw: dict[str, Any] = field(default_factory=dict)
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
