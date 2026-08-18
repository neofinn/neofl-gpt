"""NeoFL Python brain.

The engine is deliberately broker-agnostic and deterministic. Adapters provide data
and execution capabilities; the engine decides state transitions and emits intents.
"""

from .engine import NeoFLEngine
from .models import EngineConfig, EngineState, Event, EventType, OrderIntent

__all__ = [
    "NeoFLEngine",
    "EngineConfig",
    "EngineState",
    "Event",
    "EventType",
    "OrderIntent",
]
