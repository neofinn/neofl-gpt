"""Registry for independent NeoFL theories."""
from __future__ import annotations
from .base import TradingTheory

class TheoryRegistry:
    def __init__(self) -> None:
        self._items: dict[str, TradingTheory] = {}

    def register(self, theory: TradingTheory) -> None:
        if theory.name in self._items:
            raise ValueError(f"theory already registered: {theory.name}")
        self._items[theory.name] = theory

    def get(self, name: str) -> TradingTheory:
        return self._items[name]

    def all(self) -> tuple[TradingTheory, ...]:
        return tuple(self._items.values())
