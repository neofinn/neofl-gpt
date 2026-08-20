"""Long-term memory for the NeoFL agentic Brain.

Memory is deliberately append-only at the event level. Retrieval is explicit so
cognition can choose relevant memories instead of injecting the whole history.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from time import time
from typing import Any, Iterable
import hashlib
import json


@dataclass(frozen=True)
class MemoryRecord:
    memory_id: str
    account_id: str
    category: str
    event_type: str
    content: dict[str, Any]
    importance: float
    created_at: float
    symbol: str | None = None
    trade_id: str | None = None
    outcome: str | None = None


class LongTermMemory:
    """In-process durable-memory interface with deterministic IDs.

    The interface is storage-neutral: production persistence can be backed by
    the existing NeoFL database without changing Brain cognition code.
    """

    CATEGORIES = {"episodic", "strategy", "knowledge", "market", "execution"}

    def __init__(self) -> None:
        self._records: dict[str, MemoryRecord] = {}

    def remember(
        self,
        *,
        account_id: str,
        category: str,
        event_type: str,
        content: dict[str, Any],
        importance: float = 0.5,
        symbol: str | None = None,
        trade_id: str | None = None,
        outcome: str | None = None,
        created_at: float | None = None,
    ) -> MemoryRecord:
        category = category.lower()
        if category not in self.CATEGORIES:
            raise ValueError(f"Unsupported memory category: {category}")
        importance = max(0.0, min(1.0, float(importance)))
        timestamp = time() if created_at is None else float(created_at)
        material = json.dumps({"account_id": account_id, "category": category, "event_type": event_type, "content": content, "symbol": symbol, "trade_id": trade_id, "created_at": timestamp}, sort_keys=True, default=str)
        memory_id = hashlib.sha256(material.encode()).hexdigest()[:32]
        record = MemoryRecord(memory_id, account_id, category, event_type, dict(content), importance, timestamp, symbol, trade_id, outcome)
        self._records[memory_id] = record
        return record

    def retrieve(
        self,
        *,
        account_id: str,
        query_terms: Iterable[str] = (),
        categories: Iterable[str] = (),
        symbol: str | None = None,
        limit: int = 20,
    ) -> list[MemoryRecord]:
        terms = [str(t).lower() for t in query_terms if str(t).strip()]
        cats = {str(c).lower() for c in categories}
        candidates = []
        for record in self._records.values():
            if record.account_id != account_id:
                continue
            if cats and record.category not in cats:
                continue
            if symbol and record.symbol not in {None, symbol}:
                continue
            haystack = json.dumps(asdict(record), sort_keys=True, default=str).lower()
            matches = sum(term in haystack for term in terms)
            if terms and matches == 0:
                continue
            score = matches + record.importance + min(record.created_at / 10**10, 1.0)
            candidates.append((score, record))
        candidates.sort(key=lambda item: item[0], reverse=True)
        return [record for _, record in candidates[: max(1, int(limit))]]

    def record_trade_outcome(self, *, account_id: str, trade_id: str, symbol: str, thesis: dict[str, Any], outcome: dict[str, Any], importance: float = 0.9) -> MemoryRecord:
        return self.remember(account_id=account_id, category="episodic", event_type="trade_outcome", content={"thesis": thesis, "outcome": outcome}, importance=importance, symbol=symbol, trade_id=trade_id, outcome=str(outcome.get("status", "UNKNOWN")))

    def snapshot(self, account_id: str | None = None) -> list[dict[str, Any]]:
        records = self._records.values() if account_id is None else (r for r in self._records.values() if r.account_id == account_id)
        return [asdict(r) for r in sorted(records, key=lambda r: r.created_at, reverse=True)]
