"""Immutable-by-policy NeoFL operating boundaries.

The constitution is intentionally small and explicit. Learning may propose changes
but must never silently remove these controls.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class NeoFLConstitution:
    require_risk_approval: bool = True
    require_fresh_required_data: bool = True
    require_broker_reconciliation: bool = True
    prohibit_fabricated_market_data: bool = True
    prohibit_single_outcome_promotion: bool = True
    require_decision_journal: bool = True
    require_learning_validation: bool = True

    def validate_action(self, *, risk_approved: bool, data_fresh: bool, broker_reconciled: bool) -> tuple[bool, tuple[str, ...]]:
        reasons: list[str] = []
        if self.require_risk_approval and not risk_approved:
            reasons.append("risk_veto")
        if self.require_fresh_required_data and not data_fresh:
            reasons.append("required_data_not_fresh")
        if self.require_broker_reconciliation and not broker_reconciled:
            reasons.append("broker_not_reconciled")
        return not reasons, tuple(reasons)
