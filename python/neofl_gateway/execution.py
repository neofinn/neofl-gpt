"""Execution boundary for NeoFL.

The Body can submit only an execution intent that has already been authorized by
Soul. This module is deliberately paper-only: it creates simulated fills so the
agent can exercise the complete lifecycle without sending broker orders.
"""
from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, asdict
from typing import Any


@dataclass
class ExecutionIntent:
    request_id: str
    account: str
    symbol: str
    side: str
    quantity: float
    reason: str
    soul_authorized: bool = False
    mode: str = "paper"


@dataclass
class PaperTrade:
    trade_id: str
    account: str
    symbol: str
    side: str
    quantity: float
    entry: float
    mark: float
    unrealised_pnl: float
    realised_pnl: float = 0.0
    status: str = "RUNNING"
    reason: str = ""
    opened_at: float = 0.0
    closed_at: float | None = None


class ExecutionAuthority:
    """Single execution boundary. Live broker execution is intentionally absent."""
    def __init__(self) -> None:
        self.running: dict[str, PaperTrade] = {}
        self.closed: list[PaperTrade] = []
        self.rejected: list[dict[str, Any]] = []

    def submit(self, intent: ExecutionIntent, mark: float) -> dict[str, Any]:
        if intent.mode != "paper":
            return self._reject(intent, "Live broker execution is disabled in the parallel sandbox.")
        if not intent.soul_authorized:
            return self._reject(intent, "Execution rejected: Soul authorization is required.")
        if intent.quantity <= 0:
            return self._reject(intent, "Execution rejected: quantity must be positive.")
        if not intent.symbol or intent.side.upper() not in {"BUY", "SELL"}:
            return self._reject(intent, "Execution rejected: invalid symbol or side.")
        trade_id = f"paper-{uuid.uuid4().hex[:12]}"
        trade = PaperTrade(
            trade_id=trade_id,
            account=intent.account,
            symbol=intent.symbol,
            side=intent.side.upper(),
            quantity=float(intent.quantity),
            entry=float(mark),
            mark=float(mark),
            unrealised_pnl=0.0,
            reason=intent.reason,
            opened_at=time.time(),
        )
        self.running[trade_id] = trade
        return {"accepted": True, "trade": asdict(trade), "mode": "paper"}

    def mark(self, trade_id: str, price: float) -> dict[str, Any]:
        trade = self.running[trade_id]
        trade.mark = float(price)
        direction = 1 if trade.side == "BUY" else -1
        trade.unrealised_pnl = (trade.mark - trade.entry) * trade.quantity * direction
        return asdict(trade)

    def close(self, trade_id: str, price: float) -> dict[str, Any]:
        trade = self.running.pop(trade_id)
        direction = 1 if trade.side == "BUY" else -1
        trade.mark = float(price)
        trade.realised_pnl = (trade.mark - trade.entry) * trade.quantity * direction
        trade.unrealised_pnl = 0.0
        trade.status = "CLOSED"
        trade.closed_at = time.time()
        self.closed.append(trade)
        return asdict(trade)

    def report(self) -> dict[str, Any]:
        return {
            "running": [asdict(x) for x in self.running.values()],
            "closed": [asdict(x) for x in self.closed],
            "rejected": list(self.rejected),
        }

    def _reject(self, intent: ExecutionIntent, reason: str) -> dict[str, Any]:
        item = {"account": intent.account, "symbol": intent.symbol, "side": intent.side, "quantity": intent.quantity, "reason": reason, "request_id": intent.request_id, "at": time.time()}
        self.rejected.append(item)
        return {"accepted": False, "rejected": item, "mode": "paper"}
