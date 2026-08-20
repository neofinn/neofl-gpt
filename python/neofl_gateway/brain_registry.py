"""Account and global Brain deployment routing for the execution gateway.

MT5 remains branch-agnostic. The gateway owns deployment selection. A global
Brain is the default; an account may override it independently or return to
using the global selection.
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
    def __init__(self, deployments: list[BrainDeployment] | None = None, default: str = "MAIN") -> None:
        self._lock = Lock()
        self._deployments = {d.name: d for d in (deployments or [])}
        self._bindings: dict[str, AccountBrainBinding] = {}
        self._default = default
        self._validate(default)

    def _validate(self, deployment: str) -> BrainDeployment:
        target = self._deployments.get(deployment)
        if target is None or not target.enabled:
            raise ValueError(f"Brain deployment unavailable: {deployment}")
        return target

    def register(self, deployment: BrainDeployment) -> None:
        with self._lock:
            self._deployments[deployment.name] = deployment

    def set_default(self, deployment: str) -> BrainDeployment:
        with self._lock:
            target = self._validate(deployment)
            self._default = deployment
            return target

    def assign(self, account_id: str, deployment: str) -> AccountBrainBinding:
        with self._lock:
            self._validate(deployment)
            binding = AccountBrainBinding(account_id, deployment, time())
            self._bindings[account_id] = binding
            return binding

    def clear_assignment(self, account_id: str) -> None:
        with self._lock:
            self._bindings.pop(account_id, None)

    def resolve(self, account_id: str) -> BrainDeployment | None:
        with self._lock:
            binding = self._bindings.get(account_id)
            name = binding.deployment if binding else self._default
            return self._deployments.get(name)

    def binding(self, account_id: str) -> AccountBrainBinding | None:
        with self._lock:
            return self._bindings.get(account_id)

    def snapshot(self) -> dict:
        with self._lock:
            return {
                "default": self._default,
                "deployments": {k: asdict(v) for k, v in self._deployments.items()},
                "accounts": {k: asdict(v) for k, v in self._bindings.items()},
            }
