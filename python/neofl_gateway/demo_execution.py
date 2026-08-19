"""Live-market / demo-account execution boundary.

This adapter never fabricates fills. It delegates every order to an injected
broker transport (MT5 bridge in deployment) and requires an explicit DEMO
account identity. CI can test the contract with a fake transport, while the
running system uses the real MT5 demo terminal/bridge.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol


class DemoBrokerTransport(Protocol):
    def account(self) -> dict[str, Any]: ...
    def quote(self, symbol: str) -> dict[str, Any]: ...
    def order(self, *, account: str, symbol: str, side: str, quantity: float, request_id: str, reason: str) -> dict[str, Any]: ...
    def close(self, *, ticket: str, symbol: str, quantity: float, request_id: str, reason: str) -> dict[str, Any]: ...
    def positions(self, account: str) -> list[dict[str, Any]]: ...


@dataclass
class DemoExecution:
    transport: DemoBrokerTransport
    account_id: str

    def _require_demo(self) -> dict[str, Any]:
        account = self.transport.account()
        if str(account.get("account_type", "")).upper() != "DEMO":
            raise PermissionError("NeoFL execution requires a DEMO broker account.")
        if str(account.get("login", "")) != self.account_id:
            raise PermissionError("Configured execution account does not match broker account.")
        return account

    def submit(self, *, request_id: str, symbol: str, side: str, quantity: float, reason: str) -> dict[str, Any]:
        account = self._require_demo()
        quote = self.transport.quote(symbol)
        if quote.get("quality") not in {"OK", "DATA_OK", "DELAYED", "DATA_DELAYED"}:
            return {"accepted": False, "rejected": {"account": account.get("login"), "symbol": symbol, "side": side, "quantity": quantity, "request_id": request_id, "reason": "Live quote is not tradable."}}
        result = self.transport.order(account=self.account_id, symbol=symbol, side=side, quantity=quantity, request_id=request_id, reason=reason)
        return {"accepted": bool(result.get("accepted")), "broker": result, "account": account}

    def positions(self) -> list[dict[str, Any]]:
        self._require_demo()
        return self.transport.positions(self.account_id)

    def close(self, *, ticket: str, symbol: str, quantity: float, request_id: str, reason: str) -> dict[str, Any]:
        self._require_demo()
        return self.transport.close(ticket=ticket, symbol=symbol, quantity=quantity, request_id=request_id, reason=reason)
