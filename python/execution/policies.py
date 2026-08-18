"""Broker, exchange and prop-firm account policy abstraction."""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class AccountPolicy:
    """Rules that can veto an otherwise valid NeoFL trade.

    Values are deliberately generic so regulated brokers, exchanges and prop firms
    can supply their own limits without changing strategy or Soul logic.
    """
    account_id: str
    venue_type: str  # broker | prop_firm | exchange | other
    max_daily_loss: float | None = None
    max_drawdown: float | None = None
    trailing_drawdown: float | None = None
    max_position_size: float | None = None
    max_total_exposure: float | None = None
    news_restricted: bool = False
    overnight_restricted: bool = False
    allowed_symbols: frozenset[str] = frozenset()
    allowed_sessions: frozenset[str] = frozenset()
    custom_rules: dict[str, object] = field(default_factory=dict)

    def permits(self, *, symbol: str, quantity: float, daily_loss_used: float = 0.0, exposure: float = 0.0) -> tuple[bool, tuple[str, ...]]:
        reasons: list[str] = []
        if self.allowed_symbols and symbol not in self.allowed_symbols:
            reasons.append("symbol_not_allowed")
        if self.max_position_size is not None and quantity > self.max_position_size:
            reasons.append("position_size_limit")
        if self.max_total_exposure is not None and exposure > self.max_total_exposure:
            reasons.append("exposure_limit")
        if self.max_daily_loss is not None and daily_loss_used >= self.max_daily_loss:
            reasons.append("daily_loss_limit")
        return not reasons, tuple(reasons)
