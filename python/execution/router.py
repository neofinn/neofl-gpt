"""Execution router and adapter protocol."""
from __future__ import annotations

from typing import Protocol

from .models import ExecutionReport, OrderIntent
from .policies import AccountPolicy


class ExecutionAdapter(Protocol):
    name: str

    def submit(self, intent: OrderIntent) -> ExecutionReport:
        ...

    def cancel(self, order_id: str) -> ExecutionReport:
        ...

    def reconcile(self, account_id: str) -> object:
        ...


class ExecutionRouter:
    """Routes canonical intents to authorized venue adapters.

    It intentionally has no broker/platform implementation built in. Adapters are
    injected by deployment and can target MT5, cTrader, FIX, REST/WebSocket broker
    APIs, exchange APIs, or supported prop-firm platforms.
    """

    def __init__(self) -> None:
        self._adapters: dict[str, ExecutionAdapter] = {}
        self._policies: dict[str, AccountPolicy] = {}

    def register_adapter(self, adapter: ExecutionAdapter) -> None:
        self._adapters[adapter.name] = adapter

    def register_policy(self, policy: AccountPolicy) -> None:
        self._policies[policy.account_id] = policy

    def submit(self, intent: OrderIntent, *, daily_loss_used: float = 0.0, exposure: float = 0.0) -> ExecutionReport:
        policy = self._policies.get(intent.account_id or "")
        if policy is None:
            return ExecutionReport("unassigned", "BLOCKED", "router", reason="account_policy_missing")
        allowed, reasons = policy.permits(
            symbol=intent.symbol,
            quantity=intent.quantity,
            daily_loss_used=daily_loss_used,
            exposure=exposure,
        )
        if not allowed:
            return ExecutionReport("unassigned", "BLOCKED", "router", broker_or_firm=policy.account_id, reason=",".join(reasons))

        platform = str(intent.metadata.get("platform", ""))
        adapter = self._adapters.get(platform)
        if adapter is None:
            return ExecutionReport("unassigned", "BLOCKED", "router", broker_or_firm=policy.account_id, reason="execution_adapter_missing")
        return adapter.submit(intent)
