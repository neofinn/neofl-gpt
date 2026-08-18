"""Options/F&O Greeks specialist for the NeoFL theory library.

Greeks are sensitivity measures, not standalone trade signals. The specialist is
responsible for translating option-chain risk into a thesis that the Soul can combine
with underlying price, volatility, liquidity and regime analysis.

Primary Greeks:
- Delta: option-value sensitivity to underlying price.
- Gamma: sensitivity of Delta to underlying price.
- Theta: sensitivity to passage of time/time decay.
- Vega: sensitivity to implied volatility.
- Rho: sensitivity to interest rates.

The specialist also treats IV, IV rank/percentile, skew, term structure, open interest,
volume, bid/ask liquidity, expiry, strike/moneyness and futures basis as first-class
F&O context. Greek values should preferably come from a trusted broker/exchange/data
provider; model-computed Greeks must record the model and inputs used.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class GreekDirection(str, Enum):
    POSITIVE = "POSITIVE"
    NEGATIVE = "NEGATIVE"
    NEUTRAL = "NEUTRAL"


@dataclass(frozen=True)
class OptionGreeks:
    delta: float
    gamma: float
    theta: float
    vega: float
    rho: float


@dataclass(frozen=True)
class OptionContract:
    symbol: str
    underlying: str
    expiry: str
    strike: float
    option_type: str  # CALL / PUT
    last_price: float | None
    implied_volatility: float | None
    greeks: OptionGreeks | None
    open_interest: float | None = None
    volume: float | None = None
    bid: float | None = None
    ask: float | None = None


@dataclass(frozen=True)
class FNOContext:
    underlying_price: float
    futures_price: float | None
    risk_free_rate: float | None
    realized_volatility: float | None
    iv_atm: float | None
    iv_rank: float | None
    iv_percentile: float | None
    put_call_oi_ratio: float | None
    put_call_volume_ratio: float | None
    skew: float | None
    term_structure_slope: float | None
    days_to_expiry: float


@dataclass(frozen=True)
class GreekThesis:
    direction: int  # -1 short underlying, 0 neutral, +1 long underlying
    confidence: float
    volatility_view: str
    thesis: str
    evidence: tuple[str, ...]
    risks: tuple[str, ...]


class FNOGreeksTheory:
    name = "fno_greeks"
    version = "1.0"

    def analyze(self, context: FNOContext, contracts: list[OptionContract]) -> GreekThesis:
        evidence: list[str] = []
        risks: list[str] = []
        score = 0.0

        if context.iv_atm is not None and context.realized_volatility is not None:
            if context.iv_atm > context.realized_volatility:
                evidence.append("ATM implied volatility exceeds realized volatility")
                score += 0.15
                vol_view = "HIGH_IV_PREMIUM"
            else:
                evidence.append("ATM implied volatility is at or below realized volatility")
                score -= 0.15
                vol_view = "LOW_IV_PREMIUM"
        else:
            vol_view = "UNKNOWN"
            risks.append("volatility_inputs_missing")

        if context.skew is not None:
            evidence.append(f"option skew observed: {context.skew:.4f}")
        if context.term_structure_slope is not None:
            evidence.append(f"IV term structure slope observed: {context.term_structure_slope:.4f}")
        if context.put_call_oi_ratio is not None:
            evidence.append(f"put/call OI ratio observed: {context.put_call_oi_ratio:.3f}")
        if context.futures_price is not None:
            basis = context.futures_price - context.underlying_price
            evidence.append(f"futures basis observed: {basis:.6f}")

        if context.days_to_expiry <= 1:
            risks.append("near_expiry_gamma_and_theta_risk")
        if not contracts:
            risks.append("option_chain_missing")

        # This first layer deliberately does not convert Greeks into an automatic
        # directional trade. It reports the volatility/risk regime and leaves
        # directional synthesis to the Soul alongside price-action specialists.
        confidence = min(1.0, max(0.0, 0.50 + abs(score)))
        return GreekThesis(
            direction=0,
            confidence=confidence,
            volatility_view=vol_view,
            thesis="F&O Greeks provide option-risk and volatility context; directional action requires confluence with the underlying market thesis.",
            evidence=tuple(evidence),
            risks=tuple(risks),
        )
