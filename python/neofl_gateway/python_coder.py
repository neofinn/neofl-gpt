"""Python coding agent used by the Brain for diagnosis and repair planning.

The coder can inspect supplied source snapshots, remember coding lessons, generate
patch proposals and define validation commands. It deliberately does not execute
arbitrary code, modify the repository, deploy, or touch broker execution directly.
Those actions remain outside the cognitive authority boundary and require the
existing deployment/CI path.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Any, Iterable
import difflib
import hashlib
import json

from .coding_memory import CodingMemory


@dataclass(frozen=True)
class CodePatchProposal:
    proposal_id: str
    target: str
    summary: str
    old_content: str
    new_content: str
    unified_diff: str
    validation: tuple[str, ...]
    risk: str = "REVIEW_REQUIRED"
    approved: bool = False


@dataclass(frozen=True)
class RepairPlan:
    issue: str
    targets: tuple[str, ...]
    steps: tuple[str, ...]
    validations: tuple[str, ...]
    rollback_required: bool = True


class PythonCoder:
    """Code-aware maintenance brain with explicit proposal/validation boundaries."""

    def __init__(self, memory: CodingMemory | None = None) -> None:
        self.memory = memory or CodingMemory()

    def diagnose(self, *, issue: str, files: dict[str, str], failures: Iterable[str] = ()) -> dict[str, Any]:
        failure_list = [str(x) for x in failures]
        relevant = []
        query = f"{issue} {' '.join(failure_list)}".lower()
        for path, content in files.items():
            if any(token in (path + " " + content).lower() for token in query.split() if len(token) > 3):
                relevant.append(path)
        lessons = [asdict(x) for x in self.memory.recall(query=issue, limit=8)]
        return {"issue": issue, "failure_evidence": failure_list, "relevant_files": relevant, "coding_memory": lessons}

    def plan_repair(self, *, issue: str, targets: Iterable[str], validations: Iterable[str]) -> RepairPlan:
        targets = tuple(dict.fromkeys(str(x) for x in targets))
        validations = tuple(dict.fromkeys(str(x) for x in validations))
        steps = (
            "Capture current source and failure evidence.",
            "Compare the failure with coding memory and repository contracts.",
            "Generate the smallest targeted patch.",
            "Validate syntax and targeted tests in an isolated build context.",
            "Record the result in coding memory and retain rollback information.",
        )
        return RepairPlan(issue, targets, steps, validations, rollback_required=True)

    def propose_patch(self, *, target: str, old_content: str, new_content: str, summary: str, validation: Iterable[str]) -> CodePatchProposal:
        diff = "".join(difflib.unified_diff(old_content.splitlines(True), new_content.splitlines(True), fromfile=target, tofile=target))
        material = json.dumps({"target": target, "summary": summary, "diff": diff}, sort_keys=True)
        proposal_id = hashlib.sha256(material.encode()).hexdigest()[:24]
        return CodePatchProposal(proposal_id, target, summary, old_content, new_content, diff, tuple(validation))

    def approve(self, proposal: CodePatchProposal) -> CodePatchProposal:
        """Mark a proposal approved for an external controlled patch executor."""
        return CodePatchProposal(**{**asdict(proposal), "approved": True, "risk": "APPROVED_FOR_VALIDATION"})
