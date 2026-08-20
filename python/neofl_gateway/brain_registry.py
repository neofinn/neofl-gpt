"""Account-level Brain routing for the execution gateway.

MT5 stays branch-agnostic. The gateway assigns each account to a Brain
(deployment), and every execution/report carries the resolved deployment.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from threading import Lock
from time import time


@dataclass
class BrainDeployment:
    name: str
    branch: str
    build: str
    endpoint: str
    enabled: bool = True


@dataclass
class AccountBrainBinding:
    account_id: str
    deployment: str
    updated_at: float


class BrainRegistry:
    def __init__(self, deployments: list[BrainDeployment] | None = None) -> None:
        self._lock = Lock()
        self._deployments = {d.name: d for d in (deployments or [])}
        self._bindings: dict[str, AccountBrainBinding] = {}

    def register(self, deployment: BrainDeployment) -> None:
        with self._lock:
            self._deployments[deployment.name] = deployment

    def assign(self, account_id: str, deployment: str) -> AccountBrainBinding:
        with self._lock:
            target = self._deployments.get(deployment)
            if target is None or not target.enabled:
                raise ValueError(f"Brain deployment unavailable: {deployment}")
            binding = AccountBrainBinding(account_id, deployment, time())
            self._bindings[account_id] = binding
            return binding

    def resolve(self, account_id: str) -> BrainDeployment | None:
        with self._lock:
            binding = self._bindings.get(account_id)
            return self._deployments.get(binding.deployment) if binding else None

    def binding(self, account_id: str) -> AccountBrainBinding | None:
        with self._lock:
            return self._bindings.get(account_id)

    def snapshot(self) -> dict:
        with self._lock:
            return {
                "deployments": {k: asdict(v) for k, v in self._deployments.items()},
                "accounts": {k: asdict(v) for k, v in self._bindings.items()},
            }
