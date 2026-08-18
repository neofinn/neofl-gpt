"""Source-specific payloads to the common schema.

Canon: do not create source-specific strategy logic inside the EAs. Everything a
provider does oddly gets absorbed here, so the rest of the system only ever sees
`MarketSnapshot`.

Symbol mapping is configuration-driven, never hard-coded into strategy logic — and
it reuses the same resolver the MQL5 side uses, so `BTCXAU` is rejected identically
on both sides of the bridge.
"""

from __future__ import annotations

import time
from typing import Any

from neofl_core.symbol_resolver import AssetClass, classify

from .schema import DataQuality, MarketSnapshot, Source, replace_quality

# External instrument codes to the base symbol a broker would name.
# Configuration, not logic: extend this rather than special-casing in a strategy.
INSTRUMENT_MAP: dict[str, str] = {
    "GC": "XAUUSD",     # COMEX gold futures
    "MGC": "XAUUSD",    # micro gold
    "XAUUSD": "XAUUSD",
    "GOLD": "XAUUSD",
    "ES": "US500",
    "MES": "US500",
    "NQ": "US100",
    "MNQ": "US100",
    "YM": "US30",
    "MYM": "US30",
}


def map_instrument(instrument: str) -> str | None:
    """Map an external instrument code to a NeoFL base symbol.

    Returns None when unknown — the caller must then mark the snapshot unusable
    rather than guessing. A wrong mapping trades the wrong instrument.
    """
    key = (instrument or "").strip().upper()
    if key in INSTRUMENT_MAP:
        return INSTRUMENT_MAP[key]

    # Fall back to the semantic resolver, which correctly rejects BTCXAU.
    info = classify(instrument)
    if info.asset_class is AssetClass.GOLD:
        return info.base_symbol
    return None


def _as_float(value: Any) -> float | None:
    """None stays None. A source that omits a field must not become 0.0 —
    that is fabricated data wearing the costume of a measurement."""
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def normalize_tradingview(payload: dict[str, Any]) -> MarketSnapshot:
    """TradingView alert JSON to the common schema.

    Expected shape (configured in the alert message body):

        {"request_id": "...", "sent_at": 1750000000.0,
         "ticker": "XAUUSD", "event": "liquidity_sweep",
         "bid": 2412.30, "ask": 2412.55, "confidence": 0.82}

    TradingView is supplemental per canon — never treated as a raw order-book source.
    """
    instrument = str(payload.get("ticker") or payload.get("instrument") or "").strip()
    mapped = map_instrument(instrument)

    snapshot = MarketSnapshot(
        timestamp=float(payload.get("sent_at") or time.time()),
        source=Source.TRADINGVIEW,
        instrument=instrument or "(missing)",
        mapped_symbol=mapped,
        bid=_as_float(payload.get("bid")),
        ask=_as_float(payload.get("ask")),
        last=_as_float(payload.get("last")),
        volume=_as_float(payload.get("volume")),
        event=payload.get("event"),
        confidence=_as_float(payload.get("confidence")),
        raw=payload,
    )

    if not instrument:
        return replace_quality(
            snapshot, DataQuality.INVALID, "payload carries no instrument"
        )

    if mapped is None:
        return replace_quality(
            snapshot,
            DataQuality.INVALID,
            f"instrument {instrument!r} does not map to a NeoFL symbol; refusing to guess",
        )

    bid, ask = snapshot.bid, snapshot.ask
    if bid is not None and ask is not None:
        if bid <= 0 or ask <= 0 or ask < bid:
            return replace_quality(
                snapshot, DataQuality.INVALID, f"implausible quote bid={bid} ask={ask}"
            )

    return snapshot


def normalize_cme(payload: dict[str, Any]) -> MarketSnapshot:
    """CME futures / order-flow to the common schema.

    Canon: CME gold futures are the primary external order-flow candidate for ARK, and
    contract rollover must be handled rather than one contract hard-coded forever. The
    contract month is therefore carried through in `raw` for the caller to reconcile.
    """
    instrument = str(payload.get("product") or payload.get("instrument") or "").strip()
    mapped = map_instrument(instrument)

    snapshot = MarketSnapshot(
        timestamp=float(payload.get("sent_at") or time.time()),
        source=Source.CME,
        instrument=instrument or "(missing)",
        mapped_symbol=mapped,
        bid=_as_float(payload.get("bid")),
        ask=_as_float(payload.get("ask")),
        last=_as_float(payload.get("last")),
        volume=_as_float(payload.get("volume")),
        delta=_as_float(payload.get("delta")),
        bid_depth=_as_float(payload.get("bid_depth")),
        ask_depth=_as_float(payload.get("ask_depth")),
        imbalance=_as_float(payload.get("imbalance")),
        liquidity_sweep=payload.get("liquidity_sweep"),
        event=payload.get("event"),
        raw=payload,
    )

    if mapped is None:
        return replace_quality(
            snapshot,
            DataQuality.INVALID,
            f"product {instrument!r} does not map to a NeoFL symbol; refusing to guess",
        )

    # Depth without both sides is incomplete, not zero. ARK reasons about imbalance,
    # and a missing side read as 0 would manufacture an imbalance that never existed.
    if (snapshot.bid_depth is None) != (snapshot.ask_depth is None):
        return replace_quality(
            snapshot, DataQuality.INCOMPLETE, "order-book depth present on one side only"
        )

    return snapshot
