"""Pure data contracts for the NeoFL engine.

No broker SDK, database client, or strategy implementation belongs here. These models
are the stable language spoken between the brain and its adapters.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any
from uuid import uuid4


class EngineState(str, Enum):
    STARTING = "STARTING"
    READY = "READY"
    RUNNING = "RUNNING"
    DEGRADED = "DEGRADED"
    HALTED = "HALTED"
    STOPPED = "STOPPED"


class EventType(str, Enum):
    ENGINE_START = "ENGINE_START"
    ENGINE_STOP = "ENGINE_STOP"
    MARKET_DATA = "MARKET_DATA"
    ACCOUNT_SNAPSHOT = "ACCOUNT_SNAPSHOT"
    POSITION_SNAPSHOT = "POSITION_SNAPSHOT"
    SIGNAL = "SIGNAL"
    RISK_CHECK = "RISK_CHECK"
    ORDER_INTENT = "ORDER_INTENT"
    EXECUTION_REPORT = "EXECUTION_REPORT"
    RECOVERY_EVENT = "RECOVERY_EVENT"
    ERROR = "ERROR"
    HEARTBEAT = "HEARTBEAT"


@dataclass(frozen=True)
class Event:
    type: EventType
    payload: dict[str, Any] = field(default_factory=dict)
    event_id: str = field(default_factory=lambda: str(uuid4()))
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def as_dict(self) -> dict[str, Any]:
        return {
            "event_id": self.event_id,
            "type": self.type.value,
            "timestamp": self.timestamp.isoformat(),
            "payload": self.payload,
        }


@dataclass(frozen=True)
class EngineConfig:
    """Operational guardrails, not trading-strategy parameters."""

    engine_name: str = "NeoFL-GPT"
    heartbeat_seconds: float = 5.0
    max_event_history: int = 2000
    fail_closed_on_adapter_error: bool = True


@dataclass(frozen=True)
class OrderIntent:
    """A proposed order; it is NOT a broker order and cannot execute by itself."""

    symbol: str
    side: str
    volume: float
    reason: str
    bucket_id: str | None = None
    price: float | None = None
    stop_loss: float | None = None
    take_profit: float | None = None
    intent_id: str = field(default_factory=lambda: str(uuid4()))

    def as_dict(self) -> dict[str, Any]:
        return {
            "intent_id": self.intent_id,
            "symbol": self.symbol,
            "side": self.side,
            "volume": self.volume,
            "reason": self.reason,
            "bucket_id": self.bucket_id,
            "price": self.price,
            "stop_loss": self.stop_loss,
            "take_profit": self.take_profit,
        }
