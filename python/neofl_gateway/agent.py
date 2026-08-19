"""NeoFL Agentic Soul interface.

The public AgentLoop remains backwards compatible while delegating cognition to the
planner/observer/critic/replanner core. It never places orders.
"""
from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field
from typing import Any

from .agentic import AgenticSoul
from .instrument_classification import classify_instrument


@dataclass
class AgentRequest:
    text: str
    symbol: str | None = None
    mode: str = "analyze"
    request_id: str | None = None
    context: dict[str, Any] = field(default_factory=dict)


@dataclass
class AgentResponse:
    request_id: str
    status: str
    mode: str
    routed_brains: list[str]
    answer: str
    reasoning_state: str
    created_at: float
    safety: dict[str, Any]
    instrument_route: dict[str, Any] | None = None
    plan: list[dict[str, Any]] = field(default_factory=list)
    observations: list[dict[str, Any]] = field(default_factory=list)
    hypotheses: list[dict[str, Any]] = field(default_factory=list)
    contradictions: list[str] = field(default_factory=list)
    iterations: int = 0
    verdict: str = "UNRESOLVED"
    lessons: list[str] = field(default_factory=list)


class AgentLoop:
    """Agentic Soul: goal -> plan -> observe -> specialist -> critic -> replan -> decide."""

    def __init__(self, soul: AgenticSoul | None = None) -> None:
        self.soul = soul or AgenticSoul()

    def handle(self, request: AgentRequest) -> AgentResponse:
        text = request.text.strip()
        if not text:
            raise ValueError("request text is required")

        symbol = request.symbol or "UNSPECIFIED"
        route = asdict(classify_instrument(request.symbol)) if request.symbol else None
        context = dict(request.context or {})
        context["request_id"] = request.request_id or f"neo-{int(time.time() * 1000)}"
        state = self.soul.create_plan(text, symbol, request.mode, context)

        # Explicit caller-provided evidence is trusted only as supplied evidence.
        # Nothing is inferred when it is absent.
        for item in context.get("observations") or []:
            if isinstance(item, dict):
                state.observations.append(self._observation(item))

        state = self.soul.run(state, context)
        routed = [t.id.split(":", 1)[1] for t in state.tasks if t.id.startswith("brain:")]
        if "Risk Brain" not in routed:
            routed.append("Risk Brain")

        return AgentResponse(
            request_id=state.request_id,
            status="accepted",
            mode=request.mode,
            routed_brains=routed,
            answer=self._answer(state, route),
            reasoning_state=state.phase,
            created_at=time.time(),
            safety={
                "execution_authorized": False,
                "live_trading": False,
                "requires_risk_gate": True,
                "broker_order_authority": False,
                "agentic_loop": True,
            },
            instrument_route=route,
            plan=[asdict(t) for t in state.tasks],
            observations=[asdict(o) for o in state.observations],
            hypotheses=[asdict(h) for h in state.hypotheses],
            contradictions=state.contradictions,
            iterations=state.iteration,
            verdict=state.final_verdict,
            lessons=state.lessons,
        )

    @staticmethod
    def _observation(item: dict[str, Any]):
        from .agentic import Observation
        return Observation(
            source=str(item.get("source", "external")),
            claim=str(item.get("claim", "evidence")),
            value=item.get("value"),
            quality=str(item.get("quality", "UNKNOWN")),
            confidence=float(item.get("confidence", 0.0) or 0.0),
            evidence=[str(x) for x in item.get("evidence", [])],
        )

    @staticmethod
    def _answer(state, route: dict[str, Any] | None) -> str:
        route_text = ""
        if route:
            route_text = f" Instrument route: {route['signal_domain']}. {route['reason']}"
        contradiction_text = "" if not state.contradictions else f" Contradictions: {'; '.join(state.contradictions[:3])}."
        return (
            f"Soul completed an agentic analysis cycle for {state.symbol}. "
            f"Verdict: {state.final_verdict}. {state.final_reason}"
            f"{route_text}{contradiction_text} No broker execution was authorized."
        )

    @staticmethod
    def to_dict(response: AgentResponse) -> dict[str, Any]:
        return asdict(response)
