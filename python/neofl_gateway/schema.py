"""The common data schema every external source is normalized into.

Canon: all external data must be normalized to a common schema, and source-specific
logic must never leak into the EAs. A strategy asks "what is the market doing" — not
"what did TradingView's webhook payload look like this week".

The quality states mirror `CORE/NeoFL_DataValidation/NeoFL_DataQuality.mqh` exactly.
Both sides of the bridge must agree on what DELAYED means, or the MQL5 side will act
on data the Python side already considered unusable.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Any


class DataQuality(str, Enum):
    """Mirrors ENUM_NEOFL_DATA_QUALITY. Values match the MQL5 names."""

    OK = "DATA_OK"
    DELAYED = "DATA_DELAYED"
    INCOMPLETE = "DATA_INCOMPLETE"
    UNAVAILABLE = "DATA_UNAVAILABLE"
    INVALID = "DATA_INVALID"

    @property
    def tradable(self) -> bool:
        """Only OK and DELAYED may be acted on — same rule as NeoFLData_IsTradable."""
        return self in (DataQuality.OK, DataQuality.DELAYED)


class Source(str, Enum):
    CME = "CME"
    TRADINGVIEW = "TradingView"
    CALENDAR = "Calendar"
    NEWS = "News"
    MT5 = "MT5"
    INTERNAL = "Internal"


@dataclass
class MarketSnapshot:
    """The canon's common schema.

    Every field is optional except identity and quality, because a source that cannot
    supply depth must say so rather than sending zeros that read as real values.
    `None` means "this source does not provide it"; 0.0 means "measured as zero".
    That distinction is the whole point — conflating them is how fabricated data
    reaches a strategy.
    """

    timestamp: float
    source: Source
    instrument: str                 # as the source names it, e.g. "GC"
    mapped_symbol: str | None = None  # broker symbol, e.g. "XAUUSD"
    quality: DataQuality = DataQuality.OK

    bid: float | None = None
    ask: float | None = None
    last: float | None = None
    volume: float | None = None
    delta: float | None = None
    bid_depth: float | None = None
    ask_depth: float | None = None
    imbalance: float | None = None
    liquidity_sweep: bool | None = None

    event: str | None = None
    confidence: float | None = None

    detail: str = ""                # why quality is what it is
    raw: dict[str, Any] = field(default_factory=dict)  # original payload, for audit

    def age_seconds(self, now: float | None = None) -> float:
        return (time.time() if now is None else now) - self.timestamp

    def with_freshness(self, budget_seconds: float, now: float | None = None) -> "MarketSnapshot":
        """Downgrade to DELAYED when older than the budget.

        Never upgrades: a snapshot already marked INVALID stays INVALID no matter how
        fresh it is. Freshness is necessary for usability, not sufficient.
        """
        if not self.quality.tradable:
            return self
        age = self.age_seconds(now)
        if age > budget_seconds:
            return replace_quality(
                self,
                DataQuality.DELAYED,
                f"{age:.1f}s old, budget {budget_seconds:.0f}s",
            )
        return self

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["source"] = self.source.value
        d["quality"] = self.quality.value
        return d


def replace_quality(snap: MarketSnapshot, quality: DataQuality, detail: str) -> MarketSnapshot:
    """Return a copy with a different quality verdict, preserving the reason."""
    d = {k: v for k, v in snap.__dict__.items()}
    d["quality"] = quality
    d["detail"] = detail
    return MarketSnapshot(**d)


def unavailable(source: Source, instrument: str, detail: str) -> MarketSnapshot:
    """Construct an explicit 'no data' record.

    Canon: missing data must be reported, never fabricated. Returning this is always
    correct; returning a snapshot of zeros never is.
    """
    return MarketSnapshot(
        timestamp=time.time(),
        source=source,
        instrument=instrument,
        quality=DataQuality.UNAVAILABLE,
        detail=detail,
    )


# --- Decision provenance (D-002), mirroring NeoFLDecision in MQL5 -------------------


class Verdict(str, Enum):
    NONE = "NONE"
    PROCEED = "PROCEED"
    DECLINE = "DECLINE"   # evaluated, conditions not met — normal
    BLOCKED = "BLOCKED"   # could not evaluate
    ERROR = "ERROR"


@dataclass
class Decision:
    """Why a component concluded what it concluded.

    D-002: the AI verifies engines process data correctly, which requires the inputs,
    the data quality behind them, the conclusion, and the reason. A component that
    only reports outcomes cannot be checked.
    """

    engine: str
    symbol: str
    verdict: Verdict
    quality: DataQuality
    reason: str
    inputs: str = ""
    at: float = field(default_factory=time.time)

    def to_dict(self) -> dict[str, Any]:
        return {
            "engine": self.engine,
            "symbol": self.symbol,
            "verdict": self.verdict.value,
            "quality": self.quality.value,
            "reason": self.reason,
            "inputs": self.inputs,
            "at": self.at,
        }

    def __str__(self) -> str:
        return (
            f"[{self.engine}] {self.symbol} {self.verdict.value} "
            f'quality={self.quality.value} reason="{self.reason}" inputs="{self.inputs}"'
        )
