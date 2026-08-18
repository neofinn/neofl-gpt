"""NeoFL's orchestration brain.

This module owns lifecycle, event flow, validation gates, and intent routing. It does
not contain broker-specific code and it does not invent trading signals. Strategies,
risk, persistence, and execution are injected through ports.

Safety invariant:
    market/account data -> strategy -> risk -> order intent -> execution adapter

An execution adapter is never called until the risk port explicitly approves an intent.
Adapter failures fail closed when configured to do so.
"""

from __future__ import annotations

from collections import deque
from threading import RLock
from typing import Callable

from .models import EngineConfig, EngineState, Event, EventType, OrderIntent
from .ports import AccountPort, EventStore, ExecutionPort, MarketDataPort, RiskPort, StrategyPort


EventListener = Callable[[Event], None]


class NeoFLEngine:
    """Deterministic coordinator for the NeoFL Python brain."""

    def __init__(
        self,
        *,
        config: EngineConfig | None = None,
        market: MarketDataPort,
        account: AccountPort,
        strategy: StrategyPort,
        risk: RiskPort,
        execution: ExecutionPort,
        store: EventStore,
    ) -> None:
        self.config = config or EngineConfig()
        self.market = market
        self.account = account
        self.strategy = strategy
        self.risk = risk
        self.execution = execution
        self.store = store
        self.state = EngineState.STOPPED
        self._events: deque[Event] = deque(maxlen=self.config.max_event_history)
        self._listeners: list[EventListener] = []
        self._lock = RLock()

    def add_listener(self, listener: EventListener) -> None:
        with self._lock:
            self._listeners.append(listener)

    def _emit(self, event: Event) -> Event:
        self._events.append(event)
        self.store.append(event)
        for listener in tuple(self._listeners):
            listener(event)
        return event

    def start(self) -> None:
        with self._lock:
            if self.state not in {EngineState.STOPPED, EngineState.HALTED}:
                return
            self.state = EngineState.STARTING
            self._emit(Event(EventType.ENGINE_START, {"engine": self.config.engine_name}))
            try:
                self.execution.reconcile()
                self.state = EngineState.READY
            except Exception as exc:
                self.state = EngineState.HALTED
                self._emit(Event(EventType.ERROR, {"stage": "startup_reconcile", "error": str(exc)}))
                if not self.config.fail_closed_on_adapter_error:
                    self.state = EngineState.READY
                    return
                raise

    def stop(self) -> None:
        with self._lock:
            if self.state is EngineState.STOPPED:
                return
            self.state = EngineState.STOPPED
            self._emit(Event(EventType.ENGINE_STOP, {"engine": self.config.engine_name}))

    def halt(self, reason: str) -> None:
        with self._lock:
            self.state = EngineState.HALTED
            self._emit(Event(EventType.ERROR, {"stage": "engine", "error": reason}))

    def heartbeat(self) -> Event:
        event = Event(EventType.HEARTBEAT, {"state": self.state.value})
        return self._emit(event)

    def cycle(self) -> list[OrderIntent]:
        """Run exactly one decision cycle.

        No data means no trade. Every proposed intent passes the risk gate before the
        execution port sees it. Returned intents are the auditable record of what the
        brain approved for execution.
        """
        with self._lock:
            if self.state not in {EngineState.READY, EngineState.RUNNING}:
                return []
            self.state = EngineState.RUNNING

            try:
                market = self.market.snapshot()
                account = self.account.snapshot()
            except Exception as exc:
                self.state = EngineState.DEGRADED
                self._emit(Event(EventType.ERROR, {"stage": "snapshot", "error": str(exc)}))
                return []

            if not market or not account:
                self._emit(Event(EventType.ERROR, {"stage": "validation", "error": "missing market/account data"}))
                return []

            self._emit(Event(EventType.MARKET_DATA, market))
            self._emit(Event(EventType.ACCOUNT_SNAPSHOT, account))

            try:
                candidates = self.strategy.evaluate(market, account)
            except Exception as exc:
                self.state = EngineState.DEGRADED
                self._emit(Event(EventType.ERROR, {"stage": "strategy", "error": str(exc)}))
                return []

            approved: list[OrderIntent] = []
            for intent in candidates:
                self._emit(Event(EventType.SIGNAL, intent.as_dict()))
                try:
                    ok, reason = self.risk.approve(intent, account, market)
                except Exception as exc:
                    ok, reason = False, f"risk exception: {exc}"

                self._emit(Event(EventType.RISK_CHECK, {
                    "intent": intent.as_dict(), "approved": ok, "reason": reason
                }))
                if not ok:
                    continue

                self._emit(Event(EventType.ORDER_INTENT, intent.as_dict()))
                approved.append(intent)
                try:
                    self.execution.submit(intent)
                except Exception as exc:
                    self.state = EngineState.DEGRADED
                    self._emit(Event(EventType.ERROR, {
                        "stage": "execution", "intent_id": intent.intent_id, "error": str(exc)
                    }))
                    if self.config.fail_closed_on_adapter_error:
                        break

            return approved

    def recent_events(self) -> tuple[Event, ...]:
        with self._lock:
            return tuple(self._events)
