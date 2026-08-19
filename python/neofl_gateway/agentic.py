"""Agentic cognition primitives for NeoFL.

This module deliberately does not own broker execution. It turns a request into a
bounded plan, gathers only available evidence, runs specialist/critic passes, and
can re-plan when evidence is missing or contradictory. It is deterministic today
and exposes clean seams for an LLM reasoner later.
"""
from __future__ import annotations

import time
import uuid
from dataclasses import asdict, dataclass, field
from typing import Any, Callable

from .instrument_classification import classify_instrument


@dataclass
class Observation:
    source: str
    claim: str
    value: Any = None
    quality: str = "UNKNOWN"
    confidence: float = 0.0
    evidence: list[str] = field(default_factory=list)


@dataclass
class Task:
    id: str
    name: str
    purpose: str
    priority: int = 50
    status: str = "PENDING"
    result: Any = None
    attempts: int = 0


@dataclass
class Hypothesis:
    name: str
    thesis: str
    confidence: float
    evidence: list[str] = field(default_factory=list)
    invalidators: list[str] = field(default_factory=list)


@dataclass
class AgentState:
    goal: str
    symbol: str
    request_id: str
    phase: str = "UNDERSTANDING"
    iteration: int = 0
    max_iterations: int = 3
    tasks: list[Task] = field(default_factory=list)
    observations: list[Observation] = field(default_factory=list)
    hypotheses: list[Hypothesis] = field(default_factory=list)
    contradictions: list[str] = field(default_factory=list)
    lessons: list[str] = field(default_factory=list)
    final_verdict: str = "UNRESOLVED"
    final_reason: str = ""


Tool = Callable[[AgentState, Task], Any]


class WorkingMemory:
    """Bounded per-request memory; no hidden mutable global state."""

    def __init__(self, limit: int = 200) -> None:
        self.limit = limit
        self._items: list[dict[str, Any]] = []

    def add(self, kind: str, payload: dict[str, Any]) -> None:
        self._items.append({"ts": time.time(), "kind": kind, "payload": payload})
        if len(self._items) > self.limit:
            del self._items[:-self.limit]

    def recent(self, limit: int = 50) -> list[dict[str, Any]]:
        return self._items[-limit:]


class ToolRegistry:
    def __init__(self) -> None:
        self._tools: dict[str, Tool] = {}

    def register(self, name: str, tool: Tool) -> None:
        self._tools[name] = tool

    def run(self, name: str, state: AgentState, task: Task) -> Any:
        tool = self._tools.get(name)
        if tool is None:
            return {"status": "UNAVAILABLE", "reason": f"tool {name!r} is not registered"}
        return tool(state, task)

    def names(self) -> list[str]:
        return sorted(self._tools)


class AgenticSoul:
    """Planner/orchestrator/critic. It can recommend but never authorize execution."""

    BRAIN_KEYWORDS = {
        "Index Brain": ("index", "nas", "spx", "us30", "ger40", "uk100", "jpn225"),
        "Option Brain": ("option", "options", "greek", "delta", "gamma", "theta", "vega", "iv"),
        "FX Relationship": ("forex", "fx", "eurusd", "usdjpy", "jpy", "eur"),
        "Data Arbitrage": ("latency", "arbitrage", "feed", "delay", "stale", "broker"),
        "Experiment Brain": ("experiment", "hypothesis", "backtest", "scenario", "crash", "trap"),
        "Risk Brain": ("risk", "drawdown", "margin", "position", "exposure", "stop"),
        "Knowledge Brain": ("theory", "thesis", "book", "research", "learn", "study", "rules"),
        "Trader Brains": ("trade", "entry", "long", "short", "buy", "sell", "signal", "setup"),
        "Market Structure Brain": ("structure", "trend", "break", "sweep", "liquidity", "support", "resistance"),
    }

    def __init__(self, tools: ToolRegistry | None = None) -> None:
        self.tools = tools or ToolRegistry()
        self._install_default_tools()

    def _install_default_tools(self) -> None:
        self.tools.register("instrument_discovery", self._instrument_discovery)
        self.tools.register("context_observation", self._context_observation)
        self.tools.register("evidence_audit", self._evidence_audit)
        self.tools.register("risk_gate", self._risk_gate)

    def create_plan(self, text: str, symbol: str, mode: str, context: dict[str, Any]) -> AgentState:
        request_id = context.get("request_id") or f"neo-{uuid.uuid4().hex[:16]}"
        state = AgentState(goal=text, symbol=symbol, request_id=request_id)
        lowered = text.lower()
        names = [name for name, words in self.BRAIN_KEYWORDS.items() if any(w in lowered for w in words)]
        if symbol and "Trader Brains" not in names and mode in {"analyze", "trade"}:
            names.append("Trader Brains")
        if "Risk Brain" not in names:
            names.append("Risk Brain")
        if symbol:
            state.tasks.append(self._task("instrument", "instrument_discovery", "Determine canonical instrument and signal domain.", 100))
        state.tasks.append(self._task("context", "context_observation", "Inspect only supplied live/context evidence; never invent missing data.", 95))
        for brain in names:
            state.tasks.append(self._task(f"brain:{brain}", "evidence_audit", f"Run {brain} as a specialist evidence pass.", 80))
        state.tasks.append(self._task("critic", "evidence_audit", "Cross-examine the current thesis and identify contradictions or missing evidence.", 90))
        state.tasks.append(self._task("risk", "risk_gate", "Apply fail-closed risk/data-quality gate.", 110))
        state.tasks.sort(key=lambda x: -x.priority)
        return state

    @staticmethod
    def _task(task_id: str, name: str, purpose: str, priority: int) -> Task:
        return Task(id=task_id, name=name, purpose=purpose, priority=priority)

    def run(self, state: AgentState, context: dict[str, Any]) -> AgentState:
        memory = WorkingMemory()
        state.phase = "PLANNING"
        while state.iteration < state.max_iterations:
            state.iteration += 1
            state.phase = "OBSERVING"
            progress = False
            for task in state.tasks:
                if task.status == "DONE":
                    continue
                task.attempts += 1
                result = self.tools.run(task.name, state, task)
                task.result = result
                task.status = "DONE"
                memory.add("task", {"task": asdict(task)})
                self._consume(state, task, result)
                progress = True
                if state.phase == "BLOCKED":
                    break

            state.phase = "CROSS_EXAMINING"
            self._cross_examine(state)
            if state.contradictions and state.iteration < state.max_iterations:
                state.phase = "REPLANNING"
                self._replan(state)
                continue
            break

        state.phase = "DECIDING"
        self._decide(state, context)
        state.phase = "RESOLVED" if state.final_verdict != "UNRESOLVED" else "BLOCKED"
        return state

    def _consume(self, state: AgentState, task: Task, result: Any) -> None:
        if not isinstance(result, dict):
            return
        for item in result.get("observations", []):
            try:
                state.observations.append(Observation(**item))
            except TypeError:
                state.observations.append(Observation(source=task.name, claim=str(item)))
        for item in result.get("hypotheses", []):
            if isinstance(item, dict):
                state.hypotheses.append(Hypothesis(**item))
        for contradiction in result.get("contradictions", []):
            if contradiction not in state.contradictions:
                state.contradictions.append(str(contradiction))
        for lesson in result.get("lessons", []):
            if lesson not in state.lessons:
                state.lessons.append(str(lesson))

    def _cross_examine(self, state: AgentState) -> None:
        if not state.observations:
            state.contradictions.append("No evidence was available to evaluate the request.")
            return
        unknown = [o for o in state.observations if o.quality in {"UNKNOWN", "UNAVAILABLE", "INVALID"}]
        if unknown and not state.hypotheses:
            state.contradictions.append("Evidence quality is insufficient to form a defensible thesis.")
        if len(state.hypotheses) >= 2:
            ranked = sorted(state.hypotheses, key=lambda h: h.confidence, reverse=True)
            if abs(ranked[0].confidence - ranked[1].confidence) < 0.10:
                state.contradictions.append("Leading hypotheses are too close in confidence; more evidence is required.")

    def _replan(self, state: AgentState) -> None:
        state.tasks = [t for t in state.tasks if t.name != "risk_gate" or t.status == "DONE"]
        state.tasks.append(self._task(
            f"recheck:{state.iteration}", "context_observation",
            "Re-check missing or conflicting evidence before deciding.", 120,
        ))
        state.contradictions.clear()

    def _decide(self, state: AgentState, context: dict[str, Any]) -> None:
        if not state.observations:
            state.final_verdict = "NO_DECISION"
            state.final_reason = "No evidence available; the agent refuses to invent market facts."
            return
        bad = [o for o in state.observations if o.quality in {"INVALID", "UNAVAILABLE"}]
        if bad or state.contradictions:
            state.final_verdict = "WAIT"
            state.final_reason = "Evidence is incomplete or contradicted; additional observation is required."
            return
        if any(o.quality == "UNKNOWN" for o in state.observations):
            state.final_verdict = "WAIT"
            state.final_reason = "Required evidence remains unknown; fail-closed decision."
            return
        if state.hypotheses:
            best = max(state.hypotheses, key=lambda h: h.confidence)
            state.final_verdict = "RECOMMEND" if best.confidence >= 0.60 else "WAIT"
            state.final_reason = best.thesis
        else:
            state.final_verdict = "ANALYZE"
            state.final_reason = "Evidence collected, but no specialist produced a sufficiently strong thesis."

    @staticmethod
    def _instrument_discovery(state: AgentState, task: Task) -> dict[str, Any]:
        route = classify_instrument(state.symbol)
        return {
            "observations": [{
                "source": "instrument_classifier",
                "claim": "signal_domain",
                "value": route.signal_domain.value,
                "quality": "OK" if route.signal_domain.value != "UNKNOWN" else "UNKNOWN",
                "confidence": 1.0 if route.signal_domain.value != "UNKNOWN" else 0.2,
                "evidence": [route.reason],
            }]
        }

    @staticmethod
    def _context_observation(state: AgentState, task: Task) -> dict[str, Any]:
        # Context is injected by the caller and consumed by AgentLoop. The task itself
        # stays pure so it is safe to run in tests and simulations.
        return {"observations": []}

    def _evidence_audit(self, state: AgentState, task: Task) -> dict[str, Any]:
        brain = task.id.split(":", 1)[1] if ":" in task.id else "Agent"
        observations = [o for o in state.observations if o.source == brain]
        if not observations:
            return {
                "observations": [{
                    "source": brain,
                    "claim": "specialist_evidence",
                    "value": "not_available",
                    "quality": "UNKNOWN",
                    "confidence": 0.0,
                    "evidence": ["No specialist data provider is connected yet."],
                }]
            }
        return {"observations": [], "hypotheses": [{
            "name": f"{brain} thesis",
            "thesis": f"{brain} evidence supports continued investigation; no execution conclusion is authorized.",
            "confidence": min(0.55, sum(o.confidence for o in observations) / max(1, len(observations))),
            "evidence": [e for o in observations for e in o.evidence],
            "invalidators": ["new contradictory market data", "data quality degradation"],
        }]}

    @staticmethod
    def _risk_gate(state: AgentState, task: Task) -> dict[str, Any]:
        if any(o.quality in {"INVALID", "UNAVAILABLE", "UNKNOWN"} for o in state.observations):
            return {"observations": [{
                "source": "Risk Brain",
                "claim": "execution_gate",
                "value": "BLOCKED",
                "quality": "OK",
                "confidence": 1.0,
                "evidence": ["Missing/unknown evidence forces a fail-closed risk decision."],
            }]}
        return {"observations": [{
            "source": "Risk Brain",
            "claim": "execution_gate",
            "value": "ANALYSIS_ONLY",
            "quality": "OK",
            "confidence": 1.0,
            "evidence": ["Agentic Soul cannot authorize broker execution."],
        }]}


def state_to_dict(state: AgentState) -> dict[str, Any]:
    return asdict(state)
