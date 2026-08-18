"""Runtime registry for NeoFL specialist brains."""
from __future__ import annotations

from typing import Any

from .base import BrainSignal, SpecialistBrain


class BrainRegistry:
    def __init__(self) -> None:
        self._brains: dict[str, SpecialistBrain] = {}

    def register(self, brain: SpecialistBrain) -> None:
        self._brains[brain.name] = brain

    def names(self) -> tuple[str, ...]:
        return tuple(sorted(self._brains))

    def analyze_all(self, world_state: dict[str, Any], context: dict[str, Any] | None = None) -> list[BrainSignal]:
        results: list[BrainSignal] = []
        for brain in self._brains.values():
            results.append(brain.analyze(world_state, context or {}))
        return results
