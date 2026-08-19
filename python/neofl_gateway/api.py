"""API endpoint generation and bounded runtime state."""
from __future__ import annotations

import hmac
import time
from dataclasses import dataclass
from typing import Any, Callable

Handler = Callable[[dict[str, Any]], Any]


class ApiError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


@dataclass
class ApiEndpoint:
    path: str
    handler: Handler
    description: str = ""
    requires_auth: bool = True
    method: str = "GET"

    def invoke(self, query: dict[str, Any]) -> Any:
        return self.handler(query)


class ApiRegistry:
    def __init__(self, token: str | None = None) -> None:
        self._endpoints: dict[str, ApiEndpoint] = {}
        self._token = token

    def create(self, path: str, handler: Handler, *, description: str = "", requires_auth: bool = True) -> ApiEndpoint:
        if not path.startswith("/"):
            path = "/" + path
        if path in self._endpoints:
            raise ValueError(f"endpoint {path!r} already exists")
        endpoint = ApiEndpoint(path=path, handler=handler, description=description, requires_auth=requires_auth)
        self._endpoints[path] = endpoint
        return endpoint

    def get(self, path: str) -> ApiEndpoint | None:
        return self._endpoints.get(path)

    def authorize(self, provided: str | None) -> bool:
        if self._token is None:
            return True
        return bool(provided) and hmac.compare_digest(self._token, provided)

    def describe(self) -> list[dict[str, Any]]:
        return [{"path": e.path, "method": e.method, "description": e.description, "requires_auth": e.requires_auth}
                for e in sorted(self._endpoints.values(), key=lambda x: x.path)]


class StateStore:
    """Bounded live state with optional durable Supabase mirroring."""
    def __init__(self, history_limit: int = 1000, memory=None) -> None:
        self._latest: dict[str, dict[str, Any]] = {}
        self._events: list[dict[str, Any]] = []
        self._decisions: list[dict[str, Any]] = []
        self._requests: list[dict[str, Any]] = []
        self._history_limit = history_limit
        self.memory = memory

    def put_snapshot(self, snapshot) -> None:
        key = snapshot.mapped_symbol or snapshot.instrument
        record = snapshot.to_dict()
        self._latest[key] = record
        self._append(self._events, record)
        if self.memory:
            self.memory.brain_event("Data", "MARKET_SNAPSHOT", record)

    def put_decision(self, decision) -> None:
        record = decision.to_dict()
        self._append(self._decisions, record)
        if self.memory:
            self.memory.decision(record)

    def put_request(self, response: dict[str, Any]) -> None:
        self._append(self._requests, response)
        if self.memory:
            self.memory.request(response)

    def _append(self, target: list, record: dict[str, Any]) -> None:
        target.append(record)
        if len(target) > self._history_limit:
            del target[: len(target) - self._history_limit]

    def latest(self, symbol: str | None = None) -> Any:
        return self._latest.get(symbol) if symbol else self._latest

    def events(self, limit: int = 100) -> list[dict[str, Any]]:
        return self._events[-limit:]

    def decisions(self, limit: int = 100) -> list[dict[str, Any]]:
        return self._decisions[-limit:]

    def requests(self, limit: int = 100) -> list[dict[str, Any]]:
        return self._requests[-limit:]

    def execution_reports(self, limit: int = 100) -> list[dict[str, Any]]:
        if not self.memory:
            return []
        return self.memory.execution_reports(limit)


def build_default_api(store: StateStore, token: str | None = None) -> ApiRegistry:
    api = ApiRegistry(token=token)
    api.create("/health", lambda q: {"status": "ok", "time": time.time(), "persistence": store.memory.status() if store.memory else {"enabled": False}}, description="Liveness and persistence check.", requires_auth=False)
    api.create("/state", lambda q: store.latest(q.get("symbol")), description="Latest normalized snapshot per symbol.")
    api.create("/events", lambda q: store.events(int(q.get("limit", 100))), description="Recent normalized market events.")
    api.create("/decisions", lambda q: store.decisions(int(q.get("limit", 100))), description="Recent engine decisions with provenance.")
    api.create("/requests", lambda q: store.requests(int(q.get("limit", 100))), description="Recent Control Room agent requests and responses.")
    api.create("/execution-reports", lambda q: store.execution_reports(int(q.get("limit", 100))), description="Execution reports enriched with account, trade data, running PnL and rejection reasons.")
    api.create("/", lambda q: {"service": "NeoFL Gateway", "endpoints": api.describe()}, description="Endpoint index.", requires_auth=False)
    return api
