"""Native MetaTrader 5 Python connector.

No EA or file telemetry is used. The connector talks to the installed MetaTrader 5
terminal through the official MetaTrader5 Python package.
"""
from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from typing import Any

try:
    import MetaTrader5 as mt5  # type: ignore
except ImportError:
    mt5 = None

class MT5NativeError(RuntimeError):
    pass

@dataclass
class MT5NativeStatus:
    installed: bool
    connected: bool
    terminal_path: str | None
    account: dict[str, Any] | None
    last_error: str | None
    live_trading_enabled: bool

class MT5NativeConnector:
    """Thin, auditable wrapper around the MetaTrader5 Python API."""
    def __init__(self, terminal_path: str | None = None) -> None:
        self.terminal_path = terminal_path or os.getenv("NEOFL_MT5_TERMINAL_PATH")
        self.live_trading_enabled = os.getenv("NEOFL_MT5_LIVE_TRADING", "false").lower() in {"1", "true", "yes", "on"}
        self.connected = False
        self.last_error: str | None = None

    @property
    def installed(self) -> bool:
        return mt5 is not None

    def connect(self) -> dict[str, Any]:
        if mt5 is None:
            raise MT5NativeError("MetaTrader5 Python package is not installed")
        try:
            ok = mt5.initialize(self.terminal_path) if self.terminal_path else mt5.initialize()
        except Exception as exc:
            self.last_error = str(exc)
            raise MT5NativeError(f"MT5 initialize failed: {exc}") from exc
        if not ok:
            self.last_error = str(mt5.last_error())
            raise MT5NativeError(f"MT5 initialize failed: {self.last_error}")
        self.connected = True
        self.last_error = None
        return self.status()

    def ensure_connected(self) -> None:
        if not self.connected:
            self.connect()

    def shutdown(self) -> None:
        if mt5 is not None and self.connected:
            mt5.shutdown()
        self.connected = False

    def status(self) -> dict[str, Any]:
        account = None
        if mt5 is not None and self.connected:
            info = mt5.account_info()
            if info is not None:
                account = info._asdict()
        return asdict(MT5NativeStatus(self.installed, self.connected, self.terminal_path, account, self.last_error, self.live_trading_enabled))

    def account(self) -> dict[str, Any]:
        self.ensure_connected(); info = mt5.account_info()
        if info is None: raise MT5NativeError(f"account_info failed: {mt5.last_error()}")
        return info._asdict()

    def terminal(self) -> dict[str, Any]:
        self.ensure_connected(); info = mt5.terminal_info()
        if info is None: raise MT5NativeError(f"terminal_info failed: {mt5.last_error()}")
        return info._asdict()

    def resolve_symbol(self, symbol: str) -> str:
        self.ensure_connected()
        requested = str(symbol or "").strip()
        if not requested:
            raise MT5NativeError("symbol is required")
        exact = mt5.symbol_info(requested)
        if exact is not None:
            mt5.symbol_select(requested, True)
            return requested
        target = requested.upper()
        symbols = mt5.symbols_get() or []
        candidates = []
        for info in symbols:
            name = str(info.name)
            upper = name.upper()
            base = upper.split(".", 1)[0]
            if upper == target or base == target or (target in {"XAUUSD", "GOLD"} and (base == "XAUUSD" or base == "GOLD")):
                candidates.append(name)
        if not candidates:
            raise MT5NativeError(f"symbol not found: {requested}")
        selected = sorted(candidates, key=lambda n: (0 if n.upper() == target else 1, len(n)))[0]
        if not mt5.symbol_select(selected, True):
            raise MT5NativeError(f"symbol_select failed for {selected}: {mt5.last_error()}")
        return selected

    def symbol(self, symbol: str) -> dict[str, Any]:
        self.ensure_connected(); resolved = self.resolve_symbol(symbol); info = mt5.symbol_info(resolved)
        if info is None: raise MT5NativeError(f"symbol_info({resolved}) failed: {mt5.last_error()}")
        return info._asdict()

    def tick(self, symbol: str) -> dict[str, Any]:
        self.ensure_connected(); resolved = self.resolve_symbol(symbol); tick = mt5.symbol_info_tick(resolved)
        if tick is None: raise MT5NativeError(f"symbol_info_tick({resolved}) failed: {mt5.last_error()}")
        return tick._asdict()

    def positions(self, symbol: str | None = None) -> list[dict[str, Any]]:
        self.ensure_connected(); resolved = self.resolve_symbol(symbol) if symbol else None
        rows = mt5.positions_get(symbol=resolved) if resolved else mt5.positions_get()
        if rows is None: raise MT5NativeError(f"positions_get failed: {mt5.last_error()}")
        return [row._asdict() for row in rows]

    def orders(self, symbol: str | None = None) -> list[dict[str, Any]]:
        self.ensure_connected(); resolved = self.resolve_symbol(symbol) if symbol else None
        rows = mt5.orders_get(symbol=resolved) if resolved else mt5.orders_get()
        if rows is None: raise MT5NativeError(f"orders_get failed: {mt5.last_error()}")
        return [row._asdict() for row in rows]

    def history_deals(self, date_from: Any, date_to: Any, group: str | None = None) -> list[dict[str, Any]]:
        self.ensure_connected(); rows = mt5.history_deals_get(date_from, date_to, group=group) if group else mt5.history_deals_get(date_from, date_to)
        if rows is None: raise MT5NativeError(f"history_deals_get failed: {mt5.last_error()}")
        return [row._asdict() for row in rows]

    def check_order(self, request: dict[str, Any]) -> dict[str, Any]:
        self.ensure_connected(); result = mt5.order_check(request)
        if result is None: raise MT5NativeError(f"order_check failed: {mt5.last_error()}")
        return result._asdict()

    def send_order(self, request: dict[str, Any]) -> dict[str, Any]:
        if not self.live_trading_enabled:
            raise MT5NativeError("live trading is disabled; set NEOFL_MT5_LIVE_TRADING=true explicitly")
        self.ensure_connected(); result = mt5.order_send(request)
        if result is None: raise MT5NativeError(f"order_send failed: {mt5.last_error()}")
        return result._asdict()

    def close_position(self, ticket: int, symbol: str, volume: float, order_type: int, price: float, deviation: int = 20, magic: int = 0, comment: str = "NeoFL") -> dict[str, Any]:
        resolved = self.resolve_symbol(symbol)
        request = {"action": mt5.TRADE_ACTION_DEAL, "symbol": resolved, "volume": float(volume), "type": int(order_type), "position": int(ticket), "price": float(price), "deviation": int(deviation), "magic": int(magic), "comment": comment, "type_time": mt5.ORDER_TIME_GTC, "type_filling": mt5.ORDER_FILLING_IOC}
        return self.send_order(request)
