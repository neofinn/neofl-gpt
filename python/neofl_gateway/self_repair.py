"""Controlled self-repair orchestration for the Brain.

This layer coordinates diagnosis, patch proposal, isolated validation and memory.
It never executes arbitrary generated code or grants broker authority.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Any, Callable, Iterable

from .python_coder import PythonCoder, CodePatchProposal, RepairPlan


@dataclass(frozen=True)
class RepairResult:
    status: str
    proposal_id: str | None
    target: str
    message: str
    validation: list[str]
    rollback_available: bool = True


class SelfRepairEngine:
    """Bounded repair coordinator. External runner owns actual filesystem writes."""

    def __init__(self, coder: PythonCoder | None = None) -> None:
        self.coder = coder or PythonCoder()

    def inspect(self, *, issue: str, files: dict[str, str], failures: Iterable[str] = ()) -> dict[str, Any]:
        return self.coder.diagnose(issue=issue, files=files, failures=failures)

    def plan(self, *, issue: str, targets: Iterable[str], validations: Iterable[str]) -> RepairPlan:
        return self.coder.plan_repair(issue=issue, targets=targets, validations=validations)

    def propose(self, *, target: str, old_content: str, new_content: str,
                summary: str, validations: Iterable[str]) -> CodePatchProposal:
        return self.coder.propose_patch(
            target=target,
            old_content=old_content,
            new_content=new_content,
            summary=summary,
            validation=validations,
        )

    def validate(self, proposal: CodePatchProposal,
                 validator: Callable[[CodePatchProposal], tuple[bool, list[str]]]) -> RepairResult:
        if not proposal.approved:
            return RepairResult("REVIEW_REQUIRED", proposal.proposal_id, proposal.target,
                                "Patch must be approved before validation.", list(proposal.validation))
        try:
            ok, evidence = validator(proposal)
        except Exception as exc:
            ok, evidence = False, [f"validator_error:{type(exc).__name__}:{exc}"]
        self.coder.memory.remember(
            kind="test",
            target=proposal.target,
            lesson=proposal.summary,
            evidence=list(evidence),
            success=ok,
        )
        return RepairResult(
            "VALIDATED" if ok else "REJECTED",
            proposal.proposal_id,
            proposal.target,
            "Validation passed." if ok else "Validation failed; rollback required.",
            list(evidence),
        )

    @staticmethod
    def snapshot(proposal: CodePatchProposal) -> dict[str, Any]:
        """Return an immutable rollback payload for the external patch executor."""
        return {"proposal_id": proposal.proposal_id, "target": proposal.target,
                "old_content": proposal.old_content, "approved": proposal.approved}
