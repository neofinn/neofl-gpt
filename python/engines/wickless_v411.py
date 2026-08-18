"""NeoFL Wickless v4.11 signal engine.

Port of the supplied NeoFL v4.11 intelligence rules.  This module deliberately
stops at signal generation; execution/recovery remains in the NeoFL core.

Rules mirrored from the supplied build:
- M30 EMA12 trend and slope must agree with M15 EMA12 trend and slope.
- M5 is the wickless recorder.
- Long: closed M5 candle is bullish and has no meaningful upper wick.
- Short: closed M5 candle is bearish and has no meaningful lower wick.
- Signal level is the M5 high for long / M5 low for short.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


@dataclass(frozen=True)
class Bar:
    time: int
    open: float
    high: float
    low: float
    close: float


@dataclass(frozen=True)
class WicklessSignal:
    symbol: str
    direction: int
    level: float
    time: int
    m30_trend: int
    m15_trend: int


def ema(values: Sequence[float], period: int) -> float:
    if len(values) < period:
        return 0.0
    k = 2.0 / (period + 1.0)
    value = sum(values[:period]) / period
    for x in values[period:]:
        value = x * k + value * (1.0 - k)
    return value


def trend_ema12(closes: Sequence[float]) -> int:
    """Equivalent to the v4.11 closed-bar EMA12 trend test."""
    if len(closes) < 14:
        return 0
    current = ema(closes[:-1], 12)
    previous = ema(closes[:-2], 12)
    close = closes[-2]
    if current <= 0 or previous <= 0 or close <= 0:
        return 0
    if close > current and current > previous:
        return 1
    if close < current and current < previous:
        return -1
    return 0


def wickless(bar: Bar, direction: int, tolerance: float) -> bool:
    if direction > 0:
        return bar.close > bar.open and (bar.high - max(bar.open, bar.close)) <= tolerance
    if direction < 0:
        return bar.close < bar.open and (min(bar.open, bar.close) - bar.low) <= tolerance
    return False


class WicklessV411Engine:
    name = "wickless_v4_11"
    version = "4.11"

    def __init__(self, wick_tolerance: float = 0.0):
        self.wick_tolerance = max(0.0, wick_tolerance)
        self._last_m5_time: dict[str, int] = {}

    def evaluate(
        self,
        symbol: str,
        m30: Sequence[Bar],
        m15: Sequence[Bar],
        m5: Sequence[Bar],
    ) -> WicklessSignal | None:
        if not m30 or not m15 or len(m5) < 2:
            return None
        m30_trend = trend_ema12([b.close for b in m30])
        m15_trend = trend_ema12([b.close for b in m15])
        if m30_trend == 0 or m15_trend == 0 or m30_trend != m15_trend:
            return None

        bar = m5[-2]  # closed candle; never use the forming candle
        if self._last_m5_time.get(symbol) == bar.time:
            return None
        self._last_m5_time[symbol] = bar.time

        if m30_trend > 0 and wickless(bar, 1, self.wick_tolerance):
            return WicklessSignal(symbol, 1, bar.high, bar.time, m30_trend, m15_trend)
        if m30_trend < 0 and wickless(bar, -1, self.wick_tolerance):
            return WicklessSignal(symbol, -1, bar.low, bar.time, m30_trend, m15_trend)
        return None
