"""NeoFL Body: runtime/perception layer governed entirely by Soul."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .agent import AgentLoop, AgentRequest
from .order_intent_queue import OrderIntent, OrderIntentQueue
from .schema import DataQuality, Decision, Verdict

@dataclass
class BodyAction:
    allowed: bool
    reason: str
    response: dict[str, Any]

class NeoFLBody:
    """Physical/runtime layer. Soul decides; Body carries state and queued intent."""
    def __init__(self, agent: AgentLoop, store, order_queue: OrderIntentQueue | None = None) -> None:
        self.agent = agent
        self.store = store
        self.order_queue = order_queue or OrderIntentQueue()

    def think(self, request: AgentRequest) -> BodyAction:
        response = self.agent.handle(request)
        data = self.agent.to_dict(response)
        self.store.put_request(data)
        self._record_decision(request, data)
        return BodyAction(True, "Soul completed the request.", data)

    def receive_external_event(self, *, source: str, symbol: str | None, payload: dict[str, Any], quality: str = "UNKNOWN") -> BodyAction:
        request = AgentRequest(
            text=f"Process external {source} observation for {symbol or 'UNSPECIFIED'}.",
            symbol=symbol,
            mode="observe",
            context={"observations": [{"source": source, "claim": "external_event", "value": payload, "quality": quality, "confidence": 1.0 if quality in {"OK", "DATA_OK"} else 0.0, "evidence": [f"Received through {source} body ingress."]}]},
        )
        result = self.think(request)
        if not result.allowed:
            return result
        verdict = str(result.response.get("verdict", "NO_DECISION")).upper()
        if verdict in {"NO_DECISION", "WAIT"} and quality not in {"OK", "DATA_OK", "DELAYED", "DATA_DELAYED"}:
            return BodyAction(False, "Soul refused to admit unusable external state.", result.response)
        return result

    def propose_action(self, *, intent: dict[str, Any], symbol: str | None = None) -> BodyAction:
        """Evaluate and, when the Brain explicitly proposes an entry, queue OrderIntent.

        Queuing is not execution. Risk/Straddle/Bucket management is deliberately
        absent here and starts only after a confirmed broker fill.
        """
        request = AgentRequest(
            text="Evaluate this proposed entry and return the Brain's decision. Do not execute it directly.",
            symbol=symbol,
            mode="trade",
            context={"observations": [{"source": "body_action_proposal", "claim": "proposed_action", "value": intent, "quality": "OK", "confidence": 1.0, "evidence": ["Proposal entered through Body."]}]},
        )
        result = self.think(request)
        data = dict(result.response)
        data["execution_authorized"] = False
        data["execution_authority"] = "MT5_EXECUTIONER"

        # The Brain may explicitly return an OrderIntent candidate. Only a
        # positive trade verdict can put it into the queue.
        verdict = str(data.get("verdict", "NO_DECISION")).upper()
        candidate = data.get("order_intent") or intent
        if result.allowed and verdict in {"PROCEED", "RECOMMEND"} and isinstance(candidate, dict):
            try:
                queued = OrderIntent(
                    symbol=str(candidate.get("symbol") or symbol or ""),
                    side=str(candidate.get("side") or candidate.get("direction") or "").upper(),
                    volume=float(candidate.get("volume") or candidate.get("lots") or 0),
                    intent_type=str(candidate.get("intent_type", "MARKET")),
                    requested_price=candidate.get("requested_price"),
                    stop_loss=candidate.get("stop_loss"),
                    take_profit=candidate.get("take_profit"),
                    strategy=str(candidate.get("strategy", "AGENTIC_BRAIN")),
                    rationale=str(candidate.get("rationale") or data.get("answer", "")),
                )
                self.order_queue.enqueue(queued)
                data["order_intent"] = queued.to_dict()
                data["queued"] = True
            except (TypeError, ValueError) as exc:
                data["queued"] = False
                data["queue_error"] = str(exc)
        else:
            data["queued"] = False
        return BodyAction(result.allowed, result.reason, data)

    def queue_snapshot(self) -> list[dict[str, Any]]:
        return self.order_queue.snapshot()

    def _record_decision(self, request: AgentRequest, data: dict[str, Any]) -> None:
        verdict_name = str(data.get("verdict", "NO_DECISION")).upper()
        verdict_map = {"RECOMMEND": Verdict.PROCEED, "PROCEED": Verdict.PROCEED, "WAIT": Verdict.DECLINE, "NO_DECISION": Verdict.BLOCKED, "ANALYZE": Verdict.PROCEED}
        recorded = verdict_map.get(verdict_name, Verdict.ERROR)
        quality = DataQuality.OK if verdict_name != "NO_DECISION" else DataQuality.UNAVAILABLE
        self.store.put_decision(Decision(engine="Soul", symbol=request.symbol or "UNSPECIFIED", verdict=recorded, quality=quality, reason=str(data.get("answer", "Agentic cycle completed.")), inputs=request.text))
