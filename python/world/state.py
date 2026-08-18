"""Versioned shared state passed to specialist brains."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass
class WorldState:
    version: int = 0
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    instruments: dict[str, dict[str, Any]] = field(default_factory=dict)
    data_quality: dict[str, float] = field(default_factory=dict)
    account: dict[str, Any] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)

    def update_instrument(self, symbol: str, observation: dict[str, Any]) -> None:
        self.instruments[symbol] = dict(observation)
        self.version += 1
        self.updated_at = datetime.now(timezone.utc)

    def snapshot(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "updated_at": self.updated_at.isoformat(),
            "instruments": self.instruments.copy(),
            "data_quality": self.data_quality.copy(),
            "account": self.account.copy(),
            "metadata": self.metadata.copy(),
        }
