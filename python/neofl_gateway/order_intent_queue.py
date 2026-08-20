"""Durable-in-process OrderIntent queue.

The Brain may decide what should be entered, but it does not become the broker
authority. A structured intent is queued for the MT5 Executioner. The Body only
activates Risk/Straddle/Bucket after a confirmed fill arrives.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from threading import Lock
from time import time
from typing import Any
from uuid import uuid4


class IntentState(str, Enum):
    QUEUED = "QUEUED"
    CLAIMED = "CLAIMED"
    FILLED = "FILLED"
    REJECTED = "REJECTED"
    CANCELLED = "CANCELLED"


@dataclass
class OrderIntent:
    symbol: str
    side: str
    volume: float
    intent_type: str = "MARKET"
    requested_price: float | None = None
    stop_loss: float | None = None
    take_profit: float | None = None
    strategy: str = "AGENTIC_BRAIN"
    rationale: str = ""
    created_at: float = field(default_factory=time)
    intent_id: str = field(default_factory=lambda: uuid4().hex)
    state: IntentState = IntentState.QUEUED
    claimed_by: str | None = None
    execution_report: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        value = asdict(self)
        value["state"] = self.state.value
        return value


class OrderIntentQueue:
    def __init__(self) -> None:
        self._lock = Lock()
        self._items: dict[str, OrderIntent] = {}

    def enqueue(self, intent: OrderIntent) -> OrderIntent:
        if intent.volume <= 0:
            raise ValueError("OrderIntent volume must be positive")
        if not intent.symbol or intent.side.upper() not in {"BUY", "SELL"}:
            raise ValueError("OrderIntent requires symbol and BUY/SELL side")
        with self._lock:
            self._items[intent.intent_id] = intent
        return intent

    def claim_next(self, worker_id: str) -> OrderIntent | None:
        with self._lock:
            candidates = [i for i in self._items.values() if i.state == IntentState.QUEUED]
            if not candidates:
                return None
            intent = min(candidates, key=lambda i: i.created_at)
            intent.state = IntentState.CLAIMED
            intent.claimed_by = worker_id
            return intent

    def report(self, intent_id: str, *, state: IntentState, report: dict[str, Any] | None = None) -> OrderIntent:
        with self._lock:
            intent = self._items.get(intent_id)
            if intent is None:
                raise KeyError(intent_id)
            intent.state = state
            intent.execution_report = report
            return intent

    def get(self, intent_id: str) -> OrderIntent | None:
        with self._lock:
            return self._items.get(intent_id)

    def pending(self) -> list[OrderIntent]:
        with self._lock:
            return [i for i in self._items.values() if i.state == IntentState.QUEUED]

    def snapshot(self) -> list[dict[str, Any]]:
        with self._lock:
            return [i.to_dict() for i in self._items.values()]
