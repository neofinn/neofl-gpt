"""Shared world-state contracts passed to NeoFL specialist brains."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping, Sequence

from ..indices.models import ConstituentObservation, IndexConstituent, IndexDefinition


@dataclass(frozen=True)
class IndexWorld:
    """Shared snapshot for index analysis.

    The world contains the tradable index observation plus its versioned underlying
    model/observations. It is supplied by the data fabric; specialists do not fetch
    arbitrary data directly.
    """
    definition: IndexDefinition
    constituents: tuple[IndexConstituent, ...]
    observations: Mapping[str, ConstituentObservation]
    observed_returns: Mapping[str, float]
    index_momentum: Mapping[str, float] = field(default_factory=dict)
    technical_state: Mapping[str, Any] = field(default_factory=dict)
    session_state: Mapping[str, Any] = field(default_factory=dict)
    volatility_state: Mapping[str, Any] = field(default_factory=dict)
