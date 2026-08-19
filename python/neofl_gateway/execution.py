"""Single execution boundary for live-market testing on a broker DEMO account.

No simulated fills are generated here. A real MT5/demo transport must be injected
at runtime. Soul remains the only authority allowed to produce an execution intent;
this module only validates the demo-account boundary and delegates to the broker.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .demo_execution import DemoExecution, DemoBrokerTransport


@dataclass
class ExecutionIntent:
    request_id: str
    account: str
    symbol: str
    side: str
    quantity: float
    reason: str
    soul_authorized: bool = False
    mode: str = "demo_live"


class ExecutionAuthority:
    """The sole broker-order boundary; live-market execution requires DEMO."""
    def __init__(self, broker: DemoBrokerTransport | None = None, account_id: str | None = None) -> None:
        self.broker = DemoExecution(broker, account_id) if broker is not None and account_id else None
        self.rejected: list[dict[str, Any]] = []

    def submit(self, intent: ExecutionIntent, mark: float | None = None) -> dict[str, Any]:
        if intent.mode != "demo_live":
            return self._reject(intent, "Execution requires demo_live mode; simulated/paper fills are disabled.")
        if not intent.soul_authorized:
            return self._reject(intent, "Execution rejected: Soul authorization is required.")
        if self.broker is None:
            return self._reject(intent, "Demo broker transport is not connected.")
        if intent.quantity <= 0:
            return self._reject(intent, "Execution rejected: quantity must be positive.")
        if not intent.symbol or intent.side.upper() not in {"BUY", "SELL"}:
            return self._reject(intent, "Execution rejected: invalid symbol or side.")
        try:
            return self.broker.submit(request_id=intent.request_id, symbol=intent.symbol, side=intent.side.upper(), quantity=float(intent.quantity), reason=intent.reason)
        except PermissionError as exc:
            return self._reject(intent, str(exc))

    def positions(self) -> list[dict[str, Any]]:
        if self.broker is None:
            return []
        return self.broker.positions()

    def _reject(self, intent: ExecutionIntent, reason: str) -> dict[str, Any]:
        item = {"account": intent.account, "symbol": intent.symbol, "side": intent.side, "quantity": intent.quantity, "reason": reason, "request_id": intent.request_id}
        self.rejected.append(item)
        return {"accepted": False, "rejected": item, "mode": intent.mode}

    def report(self) -> dict[str, Any]:
        return {"running": self.positions(), "closed": [], "rejected": list(self.rejected)}
