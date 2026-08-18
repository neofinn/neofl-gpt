"""Ports (interfaces) between the NeoFL brain and the outside world."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Iterable

from .models import Event, OrderIntent


class EventStore(ABC):
    """Durable event/state sink. Supabase will implement this port."""

    @abstractmethod
    def append(self, event: Event) -> None:
        raise NotImplementedError

    def append_many(self, events: Iterable[Event]) -> None:
        for event in events:
            self.append(event)


class MarketDataPort(ABC):
    @abstractmethod
    def snapshot(self) -> dict[str, Any]:
        """Return normalized, validated market state."""
        raise NotImplementedError


class AccountPort(ABC):
    @abstractmethod
    def snapshot(self) -> dict[str, Any]:
        raise NotImplementedError


class ExecutionPort(ABC):
    """Execution boundary.

    The engine emits OrderIntent objects. An adapter such as MT5 translates an approved
    intent into a broker request. This separation prevents an AI/data component from
    silently becoming an execution authority.
    """

    @abstractmethod
    def submit(self, intent: OrderIntent) -> str:
        raise NotImplementedError

    @abstractmethod
    def reconcile(self) -> dict[str, Any]:
        raise NotImplementedError


class StrategyPort(ABC):
    @abstractmethod
    def evaluate(self, market: dict[str, Any], account: dict[str, Any]) -> list[OrderIntent]:
        """Produce intents only; strategy implementations must not execute orders."""
        raise NotImplementedError


class RiskPort(ABC):
    @abstractmethod
    def approve(self, intent: OrderIntent, account: dict[str, Any], market: dict[str, Any]) -> tuple[bool, str]:
        raise NotImplementedError
