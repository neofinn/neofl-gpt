"""Mission specification for the Brain's self-coder.

The Brain, not the external operator, owns the design/coding pass for the
standalone MT5 fallback. This module describes the contract the coder must
implement and the acceptance criteria it must satisfy before the artifact can
be considered a release candidate.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Any


@dataclass(frozen=True)
class StandaloneEAMission:
    mission_id: str = "standalone-ea-survival-v1"
    language: str = "MQL5"
    artifact: str = "mt5/NeoFL_StandaloneBrain.mq5"
    authority: str = "STANDALONE_BRAIN"
    objective: str = "Build a connection-independent trading and management replica of the NeoFL Brain strategy stack."

    required_modules: tuple[str, ...] = (
        "market_perception",
        "multi_timeframe_analysis",
        "regime_detection",
        "strategy_selection",
        "signal_generation",
        "position_sizing",
        "risk_management",
        "straddle_recovery",
        "bucket_exposure_management",
        "position_lifecycle",
        "trade_reconciliation",
        "local_memory",
        "connection_watchdog",
        "brain_reconnect_handover",
        "account_wide_universe",
    )

    survival_requirements: tuple[str, ...] = (
        "No dependency on Brain/MCP/API for continued market management once local mode is active.",
        "Existing positions remain managed during connection loss.",
        "New entries can be generated locally when the strategy has sufficient local evidence.",
        "Connection loss never resets recovery, bucket, position, or risk state.",
        "Terminal restart restores persisted local state before taking action.",
        "Reconnect performs state reconciliation before authority handover.",
        "Broker symbol names are resolved from the account-wide tradable universe.",
        "Host chart symbol must never constrain the local trading universe.",
    )

    acceptance: tuple[str, ...] = (
        "Compiles cleanly in MetaEditor.",
        "Runs with Brain endpoint unavailable.",
        "Runs with MCP unavailable.",
        "Continues managing an existing position through forced connection loss.",
        "Persists and restores open-trade/recovery state across terminal restart.",
        "Reconciles local state with broker state on startup and reconnect.",
        "Never duplicates an order after reconnect or restart.",
        "Keeps all trading decisions and management local while disconnected.",
        "Hands authority back to the external Brain only after reconciliation.",
    )

    forbidden_shortcuts: tuple[str, ...] = (
        "Do not replace the Brain with a simple indicator-only signal.",
        "Do not disable trading merely because the external connection is unavailable.",
        "Do not make the host chart the trading universe.",
        "Do not duplicate strategy/risk constants arbitrarily when the source contract exists in the repository.",
        "Do not embed secrets or API keys in the EA source.",
    )

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
