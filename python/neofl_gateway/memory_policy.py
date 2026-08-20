"""Policies controlling what long-term memory enters a cognitive cycle."""
from __future__ import annotations

from .long_term_memory import LongTermMemory, MemoryRecord


def retrieve_brain_context(
    memory: LongTermMemory,
    *,
    account_id: str,
    symbol: str | None,
    phase: str,
    query_terms: list[str] | None = None,
) -> list[MemoryRecord]:
    terms = list(query_terms or []) + [phase]
    categories = ["episodic", "strategy", "market", "execution"]
    return memory.retrieve(account_id=account_id, query_terms=terms, categories=categories, symbol=symbol, limit=12)


def memory_prompt_context(records: list[MemoryRecord]) -> list[dict]:
    """Serialize only selected memories for the Soul; never dump the full store."""
    return [
        {
            "memory_id": r.memory_id,
            "category": r.category,
            "event_type": r.event_type,
            "symbol": r.symbol,
            "importance": r.importance,
            "outcome": r.outcome,
            "content": r.content,
        }
        for r in records
    ]
