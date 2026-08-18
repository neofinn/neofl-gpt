"""Option Brain: derivative intelligence and instrument selection."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Sequence

from .models import InstrumentComparison, OptionObservation, OptionThesis


@dataclass(frozen=True)
class OptionBrainResult:
    thesis: OptionThesis
    comparison: InstrumentComparison | None


class OptionBrain:
    """Studies the option surface and challenges/expresses underlying theses.

    This is an analytical specialist. It does not place orders. A production
    implementation must receive authoritative chain data through the shared Data
    Fabric and should calibrate scoring with historical outcomes before automation.
    """

    name = "option-intelligence"

    def analyze(self, *, underlying: str, direction: str, horizon: str, expected_move: float | None, chain: Sequence[OptionObservation], direct_asset_expected_return: float | None = None, direct_capital_required: float | None = None, direct_max_loss: float | None = None) -> OptionBrainResult:
        candidates = [o for o in chain if o.contract.underlying == underlying and o.quality > 0 and o.data_age_seconds < 30]
        preferred = self._rank(candidates, direction, expected_move)
        greek_state = self._aggregate_greeks(preferred)
        ivs = [o.implied_volatility for o in candidates if o.implied_volatility is not None]
        option_premium = preferred[0].mid if preferred else None
        option_return = self._rough_payoff(preferred[0], direction, expected_move) if preferred else None
        option_score = self._score_option(preferred[0], expected_move) if preferred else 0.0
        direct_score = self._score_direct(direct_asset_expected_return, direct_capital_required, direct_max_loss)
        preferred_instrument = "OPTION" if option_score > direct_score and preferred else "DIRECT_ASSET"
        if not preferred and direct_score == 0:
            preferred_instrument = "NO_TRADE"

        thesis = OptionThesis(
            direction=direction,
            horizon=horizon,
            expected_underlying_move=expected_move,
            preferred_contracts=tuple(o.contract.symbol for o in preferred[:5]),
            greek_state=greek_state,
            volatility_state={"iv_mean": sum(ivs) / len(ivs) if ivs else None, "contracts_with_iv": len(ivs)},
            liquidity_state={"candidate_count": len(candidates), "best_spread": preferred[0].spread if preferred else None},
            rationale=self._rationale(preferred, direction, expected_move),
        )
        comparison = InstrumentComparison(
            underlying=underlying,
            thesis_direction=direction,
            direct_expected_return=direct_asset_expected_return,
            option_expected_return=option_return,
            direct_capital_required=direct_capital_required,
            option_premium_required=option_premium,
            direct_max_loss=direct_max_loss,
            option_max_loss=option_premium,
            direct_score=direct_score,
            option_score=option_score,
            preferred_instrument=preferred_instrument,
            rationale=thesis.rationale,
        )
        return OptionBrainResult(thesis, comparison)

    @staticmethod
    def _rank(chain: Sequence[OptionObservation], direction: str, expected_move: float | None) -> list[OptionObservation]:
        target = "CALL" if direction.upper() == "LONG" else "PUT" if direction.upper() == "SHORT" else ""
        pool = [o for o in chain if o.contract.option_type.upper() == target and o.ask > 0]
        # Prefer liquid, reasonably priced contracts; avoid hard-coding a universal
        # Delta because suitability depends on thesis horizon and market regime.
        return sorted(pool, key=lambda o: (-(o.volume + o.open_interest * 0.1), o.spread / max(o.mid, 1e-9), abs((o.delta or 0.0) - 0.5)))

    @staticmethod
    def _aggregate_greeks(options: Sequence[OptionObservation]) -> dict:
        if not options:
            return {}
        def avg(name: str):
            vals = [getattr(o, name) for o in options if getattr(o, name) is not None]
            return sum(vals) / len(vals) if vals else None
        return {name: avg(name) for name in ("delta", "gamma", "theta", "vega", "rho")}

    @staticmethod
    def _rough_payoff(option: OptionObservation, direction: str, expected_move: float | None) -> float | None:
        if expected_move is None or option.mid <= 0:
            return None
        intrinsic_change = max(0.0, expected_move - option.contract.strike + option.underlying_price) if direction.upper() == "LONG" else max(0.0, option.contract.strike - (option.underlying_price - expected_move))
        return (intrinsic_change - option.mid) / option.mid

    @staticmethod
    def _score_option(option: OptionObservation, expected_move: float | None) -> float:
        if option is None:
            return 0.0
        liquidity = min(1.0, (option.volume + option.open_interest) / 10000.0)
        spread_penalty = min(1.0, option.spread / max(option.mid, 1e-9))
        move_edge = 0.5 if expected_move is None else min(1.0, max(0.0, abs(expected_move) / max(option.mid, 1e-9)))
        return max(0.0, min(1.0, 0.45 * liquidity + 0.35 * move_edge + 0.20 * (1.0 - spread_penalty)))

    @staticmethod
    def _score_direct(expected_return: float | None, capital: float | None, max_loss: float | None) -> float:
        if expected_return is None:
            return 0.0
        return max(0.0, min(1.0, abs(expected_return) / max(abs(max_loss or expected_return), 1e-9)))

    @staticmethod
    def _rationale(options: Sequence[OptionObservation], direction: str, expected_move: float | None) -> tuple[str, ...]:
        if not options:
            return ("No sufficiently fresh/liquid option candidates were available.",)
        return (
            f"Directional thesis: {direction.upper()}.",
            f"Selected from {len(options)} candidate contracts after freshness/liquidity filtering.",
            "Greek and volatility state must be interpreted with the underlying thesis and horizon.",
        )
