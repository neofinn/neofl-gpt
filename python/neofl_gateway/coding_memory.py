"""Coding memory: durable lessons about NeoFL code, failures and fixes.

This is advisory memory. It never edits source code by itself.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from time import time
from typing import Any
import hashlib
import json


@dataclass(frozen=True)
class CodingMemoryRecord:
    memory_id: str
    kind: str
    target: str
    lesson: str
    evidence: list[str]
    created_at: float
    success: bool | None = None


class CodingMemory:
    KINDS = {"bug", "fix", "architecture", "test", "deployment", "dependency", "incident"}

    def __init__(self) -> None:
        self._records: dict[str, CodingMemoryRecord] = {}

    def remember(self, *, kind: str, target: str, lesson: str, evidence: list[str] | None = None, success: bool | None = None) -> CodingMemoryRecord:
        kind = kind.lower()
        if kind not in self.KINDS:
            raise ValueError(f"Unsupported coding-memory kind: {kind}")
        evidence = [str(x) for x in (evidence or [])]
        material = json.dumps({"kind": kind, "target": target, "lesson": lesson, "evidence": evidence}, sort_keys=True)
        memory_id = hashlib.sha256(material.encode()).hexdigest()[:24]
        record = CodingMemoryRecord(memory_id, kind, target, lesson, evidence, time(), success)
        self._records[memory_id] = record
        return record

    def recall(self, *, target: str | None = None, query: str = "", limit: int = 20) -> list[CodingMemoryRecord]:
        q = query.lower().strip()
        rows = []
        for record in self._records.values():
            if target and target not in record.target:
                continue
            haystack = json.dumps(asdict(record), sort_keys=True).lower()
            if q and q not in haystack:
                continue
            rows.append(record)
        rows.sort(key=lambda r: r.created_at, reverse=True)
        return rows[:max(1, int(limit))]

    def snapshot(self) -> list[dict[str, Any]]:
        return [asdict(r) for r in sorted(self._records.values(), key=lambda r: r.created_at, reverse=True)]
