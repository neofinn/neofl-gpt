"""NeoFL Body: every external state transition passes through Soul."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .agent import AgentLoop, AgentRequest
from .execution import ExecutionAuthority, ExecutionIntent
from .schema import DataQuality, Decision, Verdict

@dataclass
class BodyAction:
    allowed: bool
    reason: str
    response: dict[str, Any]

class NeoFLBody:
    """Physical/runtime layer governed by one Agentic Soul."""
    def __init__(self, agent: AgentLoop, store, execution: ExecutionAuthority | None = None) -> None:
        self.agent = agent
        self.store = store
        self.execution = execution or ExecutionAuthority()

    def think(self, request: AgentRequest) -> BodyAction:
        response = self.agent.handle(request)
        data = self.agent.to_dict(response)
        self.store.put_request(data)
        self._record_decision(request, data)
        return BodyAction(True, "Soul completed the request.", data)

    def receive_external_event(self, *, source: str, symbol: str | None, payload: dict[str, Any], quality: str = "UNKNOWN") -> BodyAction:
        request = AgentRequest(text=f"Process external {source} observation for {symbol or 'UNSPECIFIED'}.", symbol=symbol, mode="observe", context={"observations": [{"source": source, "claim": "external_event", "value": payload, "quality": quality, "confidence": 1.0 if quality in {"OK", "DATA_OK"} else 0.0, "evidence": [f"Received through {source} body ingress."]}]})
        result = self.think(request)
        if not result.allowed:
            return result
        verdict = str(result.response.get("verdict", "NO_DECISION")).upper()
        if verdict in {"NO_DECISION", "WAIT"} and quality not in {"OK", "DATA_OK", "DELAYED", "DATA_DELAYED"}:
            return BodyAction(False, "Soul refused to admit unusable external state.", result.response)
        return result

    def authorize_execution_intent(self, *, intent: dict[str, Any], symbol: str | None = None) -> BodyAction:
        request = AgentRequest(text="Evaluate this execution intent. Do not place or modify any broker order.", symbol=symbol, mode="trade", context={"observations": [{"source": "execution_intent", "claim": "proposed_action", "value": intent, "quality": "OK", "confidence": 1.0, "evidence": ["Intent submitted through Body execution boundary."]}]})
        result = self.think(request)
        data = dict(result.response)
        data["execution_authorized"] = False
        data["execution_authority"] = "external_risk_execution_gate"
        return BodyAction(result.allowed, result.reason, data)

    def paper_trade(self, *, text: str, symbol: str, account: str, side: str, quantity: float, mark: float, context: dict[str, Any] | None = None) -> BodyAction:
        """Run a simulated trade only after Soul explicitly authorizes paper execution."""
        response = self.agent.handle(AgentRequest(text=text, symbol=symbol, mode="paper_trade", context=context or {}))
        data = self.agent.to_dict(response)
        self.store.put_request(data)
        if not data["safety"].get("paper_execution_authorized"):
            return BodyAction(False, "Paper trade rejected by Soul.", {"agent": data, "execution": {"accepted": False, "reason": "Soul did not authorize the paper trade."}})
        intent = ExecutionIntent(request_id=response.request_id, account=account, symbol=symbol, side=side, quantity=quantity, reason=response.answer, soul_authorized=True, mode="paper")
        result = self.execution.submit(intent, mark)
        return BodyAction(bool(result.get("accepted")), "Soul-authorized paper trade." if result.get("accepted") else result["rejected"]["reason"], {"agent": data, "execution": result})

    def paper_report(self) -> dict[str, Any]:
        return self.execution.report()

    def _record_decision(self, request: AgentRequest, data: dict[str, Any]) -> None:
        verdict_name = str(data.get("verdict", "NO_DECISION")).upper()
        verdict_map = {"RECOMMEND": Verdict.PROCEED, "WAIT": Verdict.DECLINE, "NO_DECISION": Verdict.BLOCKED, "ANALYZE": Verdict.PROCEED}
        recorded = verdict_map.get(verdict_name, Verdict.ERROR)
        quality = DataQuality.OK if verdict_name != "NO_DECISION" else DataQuality.UNAVAILABLE
        self.store.put_decision(Decision(engine="Soul", symbol=request.symbol or "UNSPECIFIED", verdict=recorded, quality=quality, reason=str(data.get("answer", "Agentic cycle completed.")), inputs=request.text))
