"""Gateway telemetry state for MT5 account connectivity and Brain routing."""
from __future__ import annotations
from threading import Lock
from time import time
from typing import Any

class TelemetryRegistry:
    def __init__(self) -> None:
        self._lock = Lock()
        self._accounts: dict[str, dict[str, Any]] = {}

    def heartbeat(self, payload: dict[str, Any], deployment: dict[str, Any] | None = None) -> dict[str, Any]:
        account = str(payload.get("account_id", ""))
        if not account:
            raise ValueError("account_id is required")
        with self._lock:
            state = self._accounts.setdefault(account, {})
            state.update(payload)
            state["last_heartbeat"] = time()
            state["communication"] = "ONLINE"
            if deployment:
                state["brain"] = deployment.get("name")
                state["branch"] = deployment.get("branch")
                state["build"] = deployment.get("build")
                state["brain_endpoint"] = deployment.get("endpoint")
            state.setdefault("mcp", {"status": "UNKNOWN"})
            return dict(state)

    def execution(self, payload: dict[str, Any]) -> dict[str, Any]:
        account = str(payload.get("account_id", ""))
        if not account:
            raise ValueError("account_id is required")
        with self._lock:
            state = self._accounts.setdefault(account, {})
            state["last_execution"] = time()
            state["last_execution_event"] = dict(payload)
            return dict(state)

    def set_mcp(self, account_id: str, *, status: str, endpoint: str | None = None, tools: int | None = None) -> None:
        with self._lock:
            state = self._accounts.setdefault(account_id, {})
            state["mcp"] = {"status": status, "endpoint": endpoint, "tools": tools}

    def snapshot(self) -> dict[str, Any]:
        now = time()
        with self._lock:
            result = {}
            for account, state in self._accounts.items():
                item = dict(state)
                last = float(item.get("last_heartbeat", 0))
                item["communication"] = "ONLINE" if last and now - last <= 15 else "OFFLINE"
                result[account] = item
            return result
