from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any, Callable


@dataclass(frozen=True)
class AgentRequest:
    symbol: str
    question: str
    as_of: str | None = None
    snapshot: dict[str, Any] | None = None


@dataclass(frozen=True)
class AgentResponse:
    symbol: str
    answer: str
    observations: list[dict[str, Any]]
    as_of: str


class AgentLoop:
    """Small deterministic gateway loop for the NeoFL control room.

    The gateway deliberately separates observation collection from answer
    generation so the web control room can consume structured evidence.
    """

    def __init__(self, observer: Callable[[AgentRequest], list[dict[str, Any]]] | None = None):
        self.observer = observer or (lambda request: sqlite_snapshot_observations(request.snapshot, request.symbol))

    def run(self, request: AgentRequest) -> AgentResponse:
        observations = self.observer(request)
        answer = self._compose_answer(request, observations)
        return AgentResponse(
            symbol=request.symbol,
            answer=answer,
            observations=observations,
            as_of=request.as_of or datetime.now(timezone.utc).isoformat(),
        )

    @staticmethod
    def _compose_answer(request: AgentRequest, observations: list[dict[str, Any]]) -> str:
        if not observations:
            return f"No verified gateway observations are available for {request.symbol}."
        return f"Verified gateway observations available for {request.symbol}: {len(observations)}."


def sqlite_snapshot_observations(snapshot: dict[str, Any] | None, symbol: str) -> list[dict[str, Any]]:
    """Convert the latest bridge snapshot into explicit agent evidence."""
    if not snapshot:
        return []
    raw = snapshot.get("raw")
    try:
        payload = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError:
        payload = None
    if not isinstance(payload, dict):
        return []
    snap_symbol = str(payload.get("symbol") or snapshot.get("symbol") or "")
    if symbol and snap_symbol and snap_symbol.upper() != symbol.upper():
        return []
    market = payload.get("market") or {}
    account = payload.get("account") or {}
    positions = payload.get("positions") or []
    return [
        {"source": "MT5", "claim": "market_state", "value": market, "quality": "OK", "confidence": 0.95, "evidence": ["Latest normalized MT5 bridge snapshot."]},
        {"source": "MT5", "claim": "account_state", "value": {k: account.get(k) for k in ("balance", "equity") if k in account}, "quality": "OK", "confidence": 0.95, "evidence": ["Latest MT5 account telemetry."]},
        {"source": "MT5", "claim": "open_positions", "value": positions, "quality": "OK", "confidence": 0.95, "evidence": ["Latest MT5 position snapshot."]},
    ]
