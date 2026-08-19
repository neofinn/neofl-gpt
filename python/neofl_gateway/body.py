"""NeoFL Body: every external state transition passes through Soul.

The Body owns transport, storage and integrations, but it never decides by itself.
Soul is the single cognitive authority. No market event, webhook, decision or
execution intent may bypass the Brain boundary.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .agent import AgentLoop, AgentRequest
from .schema import DataQuality, Decision, Verdict


@dataclass
class BodyAction:
    allowed: bool
    reason: str
    response: dict[str, Any]


class NeoFLBody:
    """Physical/runtime layer governed by one Agentic Soul."""

    def __init__(self, agent: AgentLoop, store) -> None:
        self.agent = agent
        self.store = store

    def think(self, request: AgentRequest) -> BodyAction:
        """All user/system reasoning enters through Soul."""
        response = self.agent.handle(request)
        data = self.agent.to_dict(response)
        self.store.put_request(data)
        self._record_decision(request, data)
        return BodyAction(True, "Soul completed the request.", data)

    def receive_external_event(self, *, source: str, symbol: str | None, payload: dict[str, Any], quality: str = "UNKNOWN") -> BodyAction:
        """Route external observations through Soul before the Body stores them."""
        request = AgentRequest(
            text=f"Process external {source} observation for {symbol or 'UNSPECIFIED'}.",
            symbol=symbol,
            mode="observe",
            context={
                "observations": [{
                    "source": source,
                    "claim": "external_event",
                    "value": payload,
                    "quality": quality,
                    "confidence": 1.0 if quality in {"OK", "DATA_OK"} else 0.0,
                    "evidence": [f"Received through {source} body ingress."],
                }]
            },
        )
        result = self.think(request)
        if not result.allowed:
            return result
        verdict = str(result.response.get("verdict", "NO_DECISION")).upper()
        if verdict in {"NO_DECISION", "WAIT"} and quality not in {"OK", "DATA_OK", "DELAYED", "DATA_DELAYED"}:
            return BodyAction(False, "Soul refused to admit unusable external state.", result.response)
        return result

    def authorize_execution_intent(self, *, intent: dict[str, Any], symbol: str | None = None) -> BodyAction:
        """Execution proposals must be evaluated by Soul; Soul cannot place orders itself."""
        request = AgentRequest(
            text="Evaluate this execution intent. Do not place or modify any broker order.",
            symbol=symbol,
            mode="trade",
            context={"observations": [{
                "source": "execution_intent",
                "claim": "proposed_action",
                "value": intent,
                "quality": "OK",
                "confidence": 1.0,
                "evidence": ["Intent submitted through Body execution boundary."],
            }]},
        )
        result = self.think(request)
        # Hard boundary: this method only authorizes the next controlled gate;
        # it never calls a broker/executor.
        data = dict(result.response)
        data["execution_authorized"] = False
        data["execution_authority"] = "external_risk_execution_gate"
        return BodyAction(result.allowed, result.reason, data)

    def _record_decision(self, request: AgentRequest, data: dict[str, Any]) -> None:
        verdict_name = str(data.get("verdict", "NO_DECISION")).upper()
        verdict_map = {
            "RECOMMEND": Verdict.PROCEED,
            "WAIT": Verdict.DECLINE,
            "NO_DECISION": Verdict.BLOCKED,
            "ANALYZE": Verdict.PROCEED,
        }
        recorded = verdict_map.get(verdict_name, Verdict.ERROR)
        quality = DataQuality.OK if verdict_name != "NO_DECISION" else DataQuality.UNAVAILABLE
        self.store.put_decision(Decision(
            engine="Soul",
            symbol=request.symbol or "UNSPECIFIED",
            verdict=recorded,
            quality=quality,
            reason=str(data.get("answer", "Agentic cycle completed.")),
            inputs=request.text,
        ))
