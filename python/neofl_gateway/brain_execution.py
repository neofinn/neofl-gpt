"""Brain -> MT5 live execution bridge.

No EA/file bridge is used. The Brain supplies a structured execution intent;
this module validates it against live MT5 state, then submits through the
existing native connector when both explicit live-trading gates are enabled.
"""
from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Any

from .mt5_native import MT5NativeConnector, MT5NativeError


class BrainExecutionError(RuntimeError):
    pass


@dataclass
class ExecutionIntent:
    action: str
    symbol: str
    volume: float
    order_type: int
    price: float
    deviation: int = 20
    magic: int = 0
    comment: str = "NeoFL Brain"
    stop_loss: float = 0.0
    take_profit: float = 0.0


class BrainExecutionGateway:
    """Live observation + execution boundary owned by the Brain."""

    def __init__(self, mt5: MT5NativeConnector) -> None:
        self.mt5 = mt5
        self.brain_live_execution = os.getenv("NEOFL_BRAIN_LIVE_EXECUTION", "false").lower() in {
            "1", "true", "yes", "on"
        }

    def observe(self, symbol: str) -> dict[str, Any]:
        resolved = self.mt5.resolve_symbol(symbol)
        return {
            "timestamp": time.time(),
            "account": self.mt5.account(),
            "terminal": self.mt5.terminal(),
            "symbol": resolved,
            "tick": self.mt5.tick(resolved),
            "positions": self.mt5.positions(resolved),
            "orders": self.mt5.orders(resolved),
        }

    def execute(self, payload: dict[str, Any]) -> dict[str, Any]:
        if not self.brain_live_execution:
            raise BrainExecutionError("Brain live execution is disabled; set NEOFL_BRAIN_LIVE_EXECUTION=true explicitly")
        if not self.mt5.live_trading_enabled:
            raise BrainExecutionError("MT5 live trading is disabled; set NEOFL_MT5_LIVE_TRADING=true explicitly")

        action = str(payload.get("action", "")).lower()
        if action not in {"buy", "sell", "close"}:
            raise BrainExecutionError("action must be buy, sell, or close")
        symbol = self.mt5.resolve_symbol(str(payload.get("symbol", "")))

        if action == "close":
            ticket = int(payload["ticket"])
            volume = float(payload["volume"])
            order_type = int(payload["order_type"])
            price = float(payload["price"])
            request_result = self.mt5.close_position(ticket, symbol, volume, order_type, price,
                                                      int(payload.get("deviation", 20)),
                                                      int(payload.get("magic", 0)),
                                                      str(payload.get("comment", "NeoFL Brain")))
            return {"executed": True, "action": action, "symbol": symbol, "result": request_result}

        volume = float(payload["volume"])
        price = float(payload["price"])
        order_type = int(payload["order_type"])
        import MetaTrader5 as mt5_api
        request = {
            "action": mt5_api.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": volume,
            "type": order_type,
            "price": price,
            "sl": float(payload.get("stop_loss", 0.0) or 0.0),
            "tp": float(payload.get("take_profit", 0.0) or 0.0),
            "deviation": int(payload.get("deviation", 20)),
            "magic": int(payload.get("magic", 0)),
            "comment": str(payload.get("comment", "NeoFL Brain")),
            "type_time": mt5_api.ORDER_TIME_GTC,
            "type_filling": int(payload.get("type_filling", mt5_api.ORDER_FILLING_IOC)),
        }
        check = self.mt5.check_order(request)
        if int(check.get("retcode", -1)) != 0:
            raise BrainExecutionError(f"order_check rejected: {check}")
        result = self.mt5.send_order(request)
        return {"executed": True, "action": action, "symbol": symbol, "order_check": check, "result": result}
