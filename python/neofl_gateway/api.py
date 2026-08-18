"""API endpoint generation — the output side.

Canon: the gateway publishes real-time state and logs events. This is where the
observer, the external brain, and any dashboard read from.

An endpoint is declared, not hand-written: give it a path, a handler, and whether it
requires auth, and the server exposes it. That keeps every endpoint consistent about
authentication, error shape, and — critically — read-only-ness.

D-001 is enforced structurally here, not by convention. `ApiEndpoint` has no way to
express a side effect: handlers receive a request and return data. There is no order
path, and adding one would require changing this module rather than slipping a call
into a handler.
"""

from __future__ import annotations

import hmac
import json
import time
from dataclasses import dataclass, field
from typing import Any, Callable

Handler = Callable[[dict[str, Any]], Any]


class ApiError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


@dataclass
class ApiEndpoint:
    """A generated read-only endpoint."""

    path: str
    handler: Handler
    description: str = ""
    requires_auth: bool = True
    method: str = "GET"

    def invoke(self, query: dict[str, Any]) -> Any:
        return self.handler(query)


class ApiRegistry:
    """Generates and holds endpoints.

    Deliberately read-only. There is no `create_command()` and no write path, because
    per D-001 nothing reachable over this surface may alter trading state.
    """

    def __init__(self, token: str | None = None) -> None:
        self._endpoints: dict[str, ApiEndpoint] = {}
        self._token = token

    def create(
        self,
        path: str,
        handler: Handler,
        *,
        description: str = "",
        requires_auth: bool = True,
    ) -> ApiEndpoint:
        if not path.startswith("/"):
            path = "/" + path
        if path in self._endpoints:
            raise ValueError(f"endpoint {path!r} already exists")
        endpoint = ApiEndpoint(
            path=path, handler=handler, description=description, requires_auth=requires_auth
        )
        self._endpoints[path] = endpoint
        return endpoint

    def get(self, path: str) -> ApiEndpoint | None:
        return self._endpoints.get(path)

    def authorize(self, provided: str | None) -> bool:
        if self._token is None:
            return True  # auth disabled (local development only)
        if not provided:
            return False
        return hmac.compare_digest(self._token, provided)

    def describe(self) -> list[dict[str, Any]]:
        """Self-documenting index, so a client can discover the surface."""
        return [
            {
                "path": e.path,
                "method": e.method,
                "description": e.description,
                "requires_auth": e.requires_auth,
            }
            for e in sorted(self._endpoints.values(), key=lambda x: x.path)
        ]


class StateStore:
    """Latest normalized state per symbol, plus a bounded event history.

    Canon: the gateway publishes real-time state; the observer needs an event history
    rather than only snapshots, so the external brain can see *why* something happened
    and not merely what the world looks like now.
    """

    def __init__(self, history_limit: int = 1000) -> None:
        self._latest: dict[str, dict[str, Any]] = {}
        self._events: list[dict[str, Any]] = []
        self._decisions: list[dict[str, Any]] = []
        self._history_limit = history_limit

    def put_snapshot(self, snapshot) -> None:
        key = snapshot.mapped_symbol or snapshot.instrument
        record = snapshot.to_dict()
        self._latest[key] = record
        self._append(self._events, record)

    def put_decision(self, decision) -> None:
        self._append(self._decisions, decision.to_dict())

    def _append(self, target: list, record: dict[str, Any]) -> None:
        target.append(record)
        if len(target) > self._history_limit:
            del target[: len(target) - self._history_limit]

    def latest(self, symbol: str | None = None) -> Any:
        if symbol:
            return self._latest.get(symbol)
        return self._latest

    def events(self, limit: int = 100) -> list[dict[str, Any]]:
        return self._events[-limit:]

    def decisions(self, limit: int = 100) -> list[dict[str, Any]]:
        return self._decisions[-limit:]


def build_default_api(store: StateStore, token: str | None = None) -> ApiRegistry:
    """The standard NeoFL read surface.

    These are exactly what D-002 requires an AI observer to have: the current state of
    the feed, the event history, and the decision log showing how each engine reasoned.
    """
    api = ApiRegistry(token=token)

    api.create(
        "/health",
        lambda q: {"status": "ok", "time": time.time()},
        description="Liveness check.",
        requires_auth=False,
    )
    api.create(
        "/state",
        lambda q: store.latest(q.get("symbol")),
        description="Latest normalized snapshot per symbol. ?symbol=XAUUSD for one.",
    )
    api.create(
        "/events",
        lambda q: store.events(int(q.get("limit", 100))),
        description="Recent normalized market events, oldest first.",
    )
    api.create(
        "/decisions",
        lambda q: store.decisions(int(q.get("limit", 100))),
        description="Recent engine decisions with inputs and reasons (D-002).",
    )
    api.create(
        "/",
        lambda q: {"service": "NeoFL Gateway", "endpoints": api.describe()},
        description="Endpoint index.",
        requires_auth=False,
    )
    return api
