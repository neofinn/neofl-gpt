"""Central NeoFL Soul orchestrator.

Specialist brains advise; the Soul synthesizes. It does not place broker orders and
cannot bypass the risk gate.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Iterable, Protocol

from .constitution import NeoFLConstitution


class SpecialistBrain(Protocol):
    name: str

    def analyze(self, world: Any) -> Any:
        ...


@dataclass(frozen=True)
class SoulObservation:
    created_at: datetime
    world: Any
    specialist_results: tuple[Any, ...]


@dataclass(frozen=True)
class SoulDecision:
    action: str
    confidence: float
    rationale: str
    risk_required: bool = True
    metadata: dict[str, Any] = field(default_factory=dict)


class NeoFLSoul:
    """Coordinates parallel specialist brains into one controlled decision flow."""

    name = "neofl-soul"
    version = "0.1.0"

    def __init__(self, specialists: Iterable[SpecialistBrain] = (), constitution: NeoFLConstitution | None = None):
        self.specialists = tuple(specialists)
        self.constitution = constitution or NeoFLConstitution()
        self.last_observation: SoulObservation | None = None

    def observe(self, world: Any) -> SoulObservation:
        results = tuple(s.analyze(world) for s in self.specialists)
        observation = SoulObservation(
            created_at=datetime.now(timezone.utc),
            world=world,
            specialist_results=results,
        )
        self.last_observation = observation
        return observation

    def synthesize(self, observation: SoulObservation) -> SoulDecision:
        """Initial conservative synthesizer.

        Until a validated thesis model is installed, the Soul observes but defaults
        to WAIT. This prevents the architecture from becoming an accidental live
        trading system while specialist engines are still being normalized.
        """
        return SoulDecision(
            action="WAIT",
            confidence=0.0,
            rationale="No validated production thesis synthesizer is installed.",
            risk_required=True,
            metadata={"specialist_count": len(observation.specialist_results)},
        )

    def authorize(self, decision: SoulDecision, *, risk_approved: bool, data_fresh: bool, broker_reconciled: bool) -> SoulDecision:
        ok, reasons = self.constitution.validate_action(
            risk_approved=risk_approved,
            data_fresh=data_fresh,
            broker_reconciled=broker_reconciled,
        )
        if decision.action == "WAIT":
            return decision
        if not ok:
            return SoulDecision(
                action="BLOCK",
                confidence=decision.confidence,
                rationale=f"Constitution veto: {', '.join(reasons)}",
                metadata={**decision.metadata, "veto_reasons": reasons},
            )
        return decision
