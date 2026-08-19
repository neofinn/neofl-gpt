"""Canonical NeoFL instrument classification and signal-domain routing.

Gold quoted in USD (XAUUSD variants) is the dedicated Gold domain.
Gold quoted in another currency (for example XAUEUR or XAUJPY) is treated as
an FX pair and therefore belongs to the FX signal domain, not the Gold domain.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import re


class AssetClass(str, Enum):
    GOLD = "GOLD"
    FX = "FX"
    INDEX = "INDEX"
    STOCK = "STOCK"
    CRYPTO = "CRYPTO"
    COMMODITY = "COMMODITY"
    OPTION = "OPTION"
    FUTURE = "FUTURE"
    UNKNOWN = "UNKNOWN"


@dataclass(frozen=True)
class InstrumentRoute:
    canonical_symbol: str
    asset_class: AssetClass
    signal_domain: AssetClass
    reason: str


def _clean(symbol: str) -> str:
    return re.sub(r"[^A-Z]", "", symbol.upper())


def classify_instrument(symbol: str) -> InstrumentRoute:
    s = _clean(symbol)

    # Dedicated Gold domain: only Gold quoted in USD.
    if s.startswith("XAUUSD") or s in {"GOLD", "XAUUSD"}:
        return InstrumentRoute(symbol, AssetClass.GOLD, AssetClass.GOLD,
                               "Gold quoted in USD uses the Gold signal domain.")

    # Gold against any non-USD currency is an FX cross for NeoFL routing.
    # Examples: XAUEUR, XAUJPY, XAUGBP, XAUAUD, XAUCAD, XAUCHF.
    if s.startswith("XAU") and len(s) >= 6:
        quote = s[3:6]
        if quote != "USD":
            return InstrumentRoute(symbol, AssetClass.FX, AssetClass.FX,
                                   f"Gold quoted in {quote} is routed as an FX pair, not Gold.")

    return InstrumentRoute(symbol, AssetClass.UNKNOWN, AssetClass.UNKNOWN,
                           "Instrument requires broker/instrument discovery before routing.")


def signal_allowed(route: InstrumentRoute, allowed_assets: set[AssetClass]) -> bool:
    return route.signal_domain in allowed_assets
