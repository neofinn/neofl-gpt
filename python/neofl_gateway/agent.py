"""First operational NeoFL reasoning loop.

This is deliberately a deterministic orchestration kernel, not an LLM. It accepts a
Control Room request, classifies which specialist domains are relevant, records a
provenance decision, and returns a structured response. LLM providers and specialist
brains can be attached behind this stable boundary later.
"""
from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field
from typing import Any


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


class AgentLoop:
    """The first Soul-facing router.

    It does not place orders. Execution is intentionally outside this loop.
    """

    KEYWORDS = {
        "Index Brain": ("index", "nas", "spx", "us30", "ger40", "uk100", "jpn225"),
        "Option Brain": ("option", "options", "greek", "delta", "gamma", "theta", "vega", "iv"),
        "FX Relationship": ("forex", "fx", "eurusd", "usdjpy", "jpy", "eur"),
        "Data Arbitrage": ("latency", "arbitrage", "feed", "delay", "stale", "broker"),
        "Experiment Brain": ("experiment", "hypothesis", "backtest", "scenario", "crash", "trap"),
        "Risk Brain": ("risk", "drawdown", "margin", "position", "exposure", "stop"),
        "Knowledge Brain": ("theory", "thesis", "book", "research", "learn", "study"),
        "Trader Brains": ("trade", "entry", "long", "short", "buy", "sell", "signal", "setup"),
    }

    def handle(self, request: AgentRequest) -> AgentResponse:
        text = request.text.strip()
        if not text:
            raise ValueError("request text is required")

        lowered = text.lower()
        routed = [name for name, words in self.KEYWORDS.items() if any(w in lowered for w in words)]
        if "Trader Brains" not in routed and request.mode in {"analyze", "trade"}:
            routed.append("Trader Brains")
        if "Risk Brain" not in routed:
            routed.append("Risk Brain")

        symbol = request.symbol or "UNSPECIFIED"
        state = "ROUTED_FOR_ANALYSIS"
        answer = (
            f"NeoFL received the request for {symbol}. "
            f"Soul routed it to: {', '.join(routed)}. "
            "No trade was authorized; this cycle is analysis-only."
        )
        return AgentResponse(
            request_id=request.request_id or f"neo-{int(time.time() * 1000)}",
            status="accepted",
            mode=request.mode,
            routed_brains=routed,
            answer=answer,
            reasoning_state=state,
            created_at=time.time(),
            safety={
                "execution_authorized": False,
                "live_trading": False,
                "requires_risk_gate": True,
            },
        )

    @staticmethod
    def to_dict(response: AgentResponse) -> dict[str, Any]:
        return asdict(response)
