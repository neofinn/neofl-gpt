"""Learning loop: record -> diagnose -> hypothesize -> validate -> promote.

This first implementation is intentionally conservative. It records experiences and
creates hypotheses but never changes live production behavior automatically.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass(frozen=True)
class LearningRecord:
    decision_id: str
    outcome: Any
    decision_quality: float | None
    error_class: str | None
    root_cause: str | None
    improvement_hypothesis: str | None
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    validation_status: str = "UNVALIDATED"


class LearningLoop:
    def __init__(self) -> None:
        self.records: list[LearningRecord] = []

    def record_outcome(self, *, decision_id: str, outcome: Any, decision_quality: float | None = None) -> LearningRecord:
        record = LearningRecord(
            decision_id=decision_id,
            outcome=outcome,
            decision_quality=decision_quality,
            error_class=None,
            root_cause=None,
            improvement_hypothesis=None,
        )
        self.records.append(record)
        return record

    def diagnose(self, record: LearningRecord, *, error_class: str | None, root_cause: str | None, hypothesis: str | None) -> LearningRecord:
        updated = LearningRecord(
            decision_id=record.decision_id,
            outcome=record.outcome,
            decision_quality=record.decision_quality,
            error_class=error_class,
            root_cause=root_cause,
            improvement_hypothesis=hypothesis,
            created_at=record.created_at,
            validation_status="UNVALIDATED",
        )
        self.records[-1] = updated
        return updated

    def propose(self, record: LearningRecord) -> str | None:
        return record.improvement_hypothesis

    def promote(self, record: LearningRecord, *, validated: bool) -> LearningRecord:
        status = "VALIDATED_CANDIDATE" if validated else "REJECTED"
        updated = LearningRecord(
            decision_id=record.decision_id,
            outcome=record.outcome,
            decision_quality=record.decision_quality,
            error_class=record.error_class,
            root_cause=record.root_cause,
            improvement_hypothesis=record.improvement_hypothesis,
            created_at=record.created_at,
            validation_status=status,
        )
        self.records[-1] = updated
        return updated
