"""Reference implementation of the NeoFL symbol resolver.

This mirrors CORE/NeoFL_SymbolResolver/NeoFL_SymbolResolver.mqh rule for rule.

Why a mirror exists: MQL5 logic can only be exercised inside MetaTrader, which is slow
and needs a terminal. The classification rules are pure string logic, so they are kept
executable here too. A rule that is wrong in Python is wrong in MQL5 as well, and this
tells us in milliseconds.

If the two ever disagree, the MQL5 module is authoritative for runtime behavior and this
file is the bug -- but the disagreement itself means one of them is broken.
"""

from dataclasses import dataclass, field
from enum import Enum


class AssetClass(Enum):
    UNKNOWN = "UNKNOWN"
    GOLD = "GOLD"
    FX = "FX"
    CRYPTO = "CRYPTO"
    INDEX = "INDEX"


# Quote currencies recognized when deciding whether a base is followed by one.
QUOTES = ("USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF")


@dataclass
class Instrument:
    valid: bool = False
    asset_class: AssetClass = AssetClass.UNKNOWN
    base_symbol: str = ""
    broker_symbol: str = ""
    base: str = ""
    quote: str = ""
    reject_reason: str = ""


def normalize(raw: str) -> str:
    """Strip broker decoration: separators, digits, and case.

    "fx.XAUUSD.pro_m" -> "FXXAUUSDPROM"
    """
    return "".join(c for c in raw if c.isalpha()).upper()


def gold_quote_or_empty(normalized: str) -> str:
    """Find XAU acting as a BASE currency, and return its quote.

    This is the BTCXAU guard. XAU is gold only when it is immediately followed by a
    recognized quote currency:

        XAUUSD -> XAU at 0, "USD" follows   -> base, so gold
        BTCXAU -> XAU at 3, nothing follows -> quote, so NOT gold

    Every occurrence is scanned so prefixed broker symbols still resolve.
    """
    start = 0
    while True:
        at = normalized.find("XAU", start)
        if at < 0:
            return ""
        following = normalized[at + 3 : at + 6]
        if following in QUOTES:
            return following
        start = at + 1


def classify(raw: str) -> Instrument:
    """Classify a symbol string. No broker calls, so this is pure and testable."""
    info = Instrument(broker_symbol=raw)

    if not raw:
        info.reject_reason = "empty symbol"
        return info

    norm = normalize(raw)
    if not norm:
        info.reject_reason = "symbol contains no letters"
        return info

    # 1) XAU acting as base, e.g. XAUUSD / XAUUSD.pro / FX_XAUUSD_m
    quote = gold_quote_or_empty(norm)
    if quote:
        info.valid = True
        info.asset_class = AssetClass.GOLD
        info.base = "XAU"
        info.quote = quote
        info.base_symbol = "XAU" + quote
        return info

    # 2) Direct alias, e.g. GOLD / GOLDm. Quote is implicitly USD.
    if "GOLD" in norm:
        info.valid = True
        info.asset_class = AssetClass.GOLD
        info.base = "XAU"
        info.quote = "USD"
        info.base_symbol = "XAUUSD"
        return info

    # 3) Mentions XAU but not as a base -> explicitly rejected as gold.
    if "XAU" in norm:
        info.reject_reason = "XAU present as quote currency, not base; not the gold instrument"
        return info

    info.reject_reason = "unrecognized instrument"
    return info


def is_gold(raw: str) -> bool:
    return classify(raw).asset_class is AssetClass.GOLD
