"""NeoFL cognitive Soul.

The Soul is the only cognitive authority. It owns goals, working memory,
long-term memory hooks, coding memory, self-repair planning, tool selection,
specialist delegation, criticism, replanning and final decisions. It never owns
broker execution.
"""
from __future__ import annotations

import time
import uuid
from dataclasses import asdict, dataclass, field
from typing import Any, Callable

from .agentic import AgenticSoul, AgentState, Observation, Task
from .coding_memory import CodingMemory
from .python_coder import PythonCoder, RepairPlan, CodePatchProposal


@dataclass
class Goal:
    id: str
    text: str
    priority: int = 100
    status: str = "ACTIVE"
    created_at: float = field(default_factory=time.time)


@dataclass
class MemoryRecord:
    id: str
    kind: str
    key: str
    value: dict[str, Any]
    created_at: float = field(default_factory=time.time)
    uses: int = 0


class SoulMemory:
    """Small deterministic working memory; persistent stores can be attached later."""
    def __init__(self, provider: Callable[[str], list[dict[str, Any]]] | None = None, limit: int = 500) -> None:
        self.provider = provider
        self.limit = limit
        self._records: list[MemoryRecord] = []

    def recall(self, key: str, limit: int = 25) -> list[dict[str, Any]]:
        external = self.provider(key) if self.provider else []
        local = [asdict(x) for x in self._records if x.key == key]
        return (external or [])[-limit:] + local[-limit:]

    def remember(self, kind: str, key: str, value: dict[str, Any]) -> None:
        self._records.append(MemoryRecord(uuid.uuid4().hex[:16], kind, key, value))
        if len(self._records) > self.limit:
            del self._records[:-self.limit]


class GoalManager:
    def create(self, text: str) -> Goal:
        return Goal(id=f"goal-{uuid.uuid4().hex[:12]}", text=text)


class SpecialistCouncil:
    """Makes specialist participation explicit rather than treating brains as side processes."""
    def select(self, goal: str, symbol: str) -> list[str]:
        return self._unique(AgenticSoul().create_plan(goal, symbol, "analyze", {}).tasks)

    @staticmethod
    def _unique(tasks: list[Task]) -> list[str]:
        names: list[str] = []
        for task in tasks:
            if task.id.startswith("brain:"):
                name = task.id.split(":", 1)[1]
                if name not in names:
                    names.append(name)
        return names


class CriticEngine:
    def challenge(self, state: AgentState) -> list[str]:
        issues: list[str] = []
        if not state.observations:
            issues.append("No observations exist to support a conclusion.")
        usable = [o for o in state.observations if o.quality in {"OK", "DATA_OK", "DELAYED", "DATA_DELAYED"}]
        if usable and not state.hypotheses:
            issues.append("Evidence exists but no hypothesis was formed.")
        if len(state.hypotheses) >= 2:
            ordered = sorted(state.hypotheses, key=lambda h: h.confidence, reverse=True)
            if ordered[0].confidence - ordered[1].confidence < 0.10:
                issues.append("Leading hypotheses remain too close; more evidence is required.")
        return issues


class Replanner:
    def replan(self, state: AgentState, issues: list[str]) -> None:
        state.lessons.extend([f"Critic: {x}" for x in issues if f"Critic: {x}" not in state.lessons])
        state.tasks = [t for t in state.tasks if t.status != "DONE" and not t.id.startswith("brain:")]
        state.tasks.append(Task(id=f"reobserve:{state.iteration}", name="context_observation", purpose="Acquire missing or conflicting evidence identified by the critic.", priority=125))
        state.tasks.append(Task(id=f"recritic:{state.iteration}", name="evidence_audit", purpose="Re-test the thesis after new evidence.", priority=120))
        state.contradictions.clear()


class CognitiveSoul(AgenticSoul):
    """Autonomous cognition plus an internal coding/repair capability."""
    def __init__(self, tools=None, reasoner=None, memory: SoulMemory | None = None, coding_memory: CodingMemory | None = None) -> None:
        super().__init__(tools=tools, reasoner=reasoner)
        self.memory = memory or SoulMemory()
        self.coding_memory = coding_memory or CodingMemory()
        self.coder = PythonCoder(self.coding_memory)
        self.goals = GoalManager()
        self.council = SpecialistCouncil()
        self.critic = CriticEngine()
        self.replanner = Replanner()

    def create_plan(self, text: str, symbol: str, mode: str, context: dict[str, Any]) -> AgentState:
        goal = self.goals.create(text)
        context = dict(context)
        context["goal_id"] = goal.id
        context["goal_priority"] = goal.priority
        context["memory"] = self.memory.recall(symbol or "UNSPECIFIED")
        return super().create_plan(text, symbol, mode, context)

    def run(self, state: AgentState, context: dict[str, Any]) -> AgentState:
        state.max_iterations = min(max(state.max_iterations, 3), 5)
        for cycle in range(state.max_iterations):
            state.iteration = cycle + 1
            state.phase = "PERCEIVING"
            pending = [t for t in state.tasks if t.status != "DONE"]
            if not pending:
                break
            for task in pending:
                task.attempts += 1
                result = self.tools.run(task.name, state, task)
                task.result = result
                task.status = "DONE"
                self._consume(state, task, result)

            state.phase = "CRITICIZING"
            issues = self.critic.challenge(state)
            for issue in issues:
                if issue not in state.contradictions:
                    state.contradictions.append(issue)
            if issues and cycle + 1 < state.max_iterations:
                state.phase = "REPLANNING"
                self.replanner.replan(state, issues)
                continue
            break

        state.phase = "SYNTHESIZING"
        self._llm_synthesis(state)
        self._decide(state, context)
        state.phase = "RESOLVED" if state.final_verdict != "UNRESOLVED" else "BLOCKED"
        self.memory.remember("episode", state.symbol or "UNSPECIFIED", {
            "goal": state.goal,
            "verdict": state.final_verdict,
            "reason": state.final_reason,
            "iterations": state.iteration,
            "specialists": [t.id for t in state.tasks if t.id.startswith("brain:")],
            "observations": len(state.observations),
            "contradictions": list(state.contradictions),
        })
        return state

    def diagnose_code(self, *, issue: str, files: dict[str, str], failures: list[str] | None = None) -> dict[str, Any]:
        """Let the Brain inspect a supplied code snapshot and coding history."""
        return self.coder.diagnose(issue=issue, files=files, failures=failures or [])

    def plan_code_repair(self, *, issue: str, targets: list[str], validations: list[str]) -> RepairPlan:
        return self.coder.plan_repair(issue=issue, targets=targets, validations=validations)

    def propose_code_patch(self, *, target: str, old_content: str, new_content: str, summary: str, validation: list[str]) -> CodePatchProposal:
        proposal = self.coder.propose_patch(target=target, old_content=old_content, new_content=new_content, summary=summary, validation=validation)
        self.coding_memory.remember(kind="fix", target=target, lesson=summary, evidence=list(validation), success=None)
        return proposal

    def introspect(self, state: AgentState) -> dict[str, Any]:
        return {
            "goal": state.goal,
            "phase": state.phase,
            "iteration": state.iteration,
            "specialists": [t.id.split(":", 1)[1] for t in state.tasks if t.id.startswith("brain:")],
            "observations": len(state.observations),
            "hypotheses": len(state.hypotheses),
            "contradictions": list(state.contradictions),
            "memory_available": len(self.memory.recall(state.symbol or "UNSPECIFIED")),
            "coding_memory_available": len(self.coding_memory.recall(limit=50)),
            "python_coder": True,
            "self_repair_mode": "PROPOSE_VALIDATE_ROLLBACK",
            "verdict": state.final_verdict,
        }
