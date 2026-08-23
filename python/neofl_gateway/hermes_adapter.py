"""Hermes adapter for NeoFLGPT Parallel.

Hermes is an agent/tool runtime. This adapter keeps Hermes behind NeoFL's
existing tool bus so Hermes can discover market, account, coding and MT5
execution capabilities without hard-coding broker logic into Hermes.

The adapter is transport-neutral: it can launch a local Hermes process when
installed, or expose a JSON tool manifest for an external Hermes runtime.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from typing import Any, Callable


@dataclass
class HermesStatus:
    configured: bool
    installed: bool
    executable: str | None
    transport: str
    execution_tools_enabled: bool
    last_error: str | None = None


class HermesAdapter:
    """Bridge Hermes to the NeoFL tool registry."""

    def __init__(self, tool_registry: dict[str, Callable[..., Any]] | None = None) -> None:
        self.tool_registry = tool_registry or {}
        self.executable = os.getenv("HERMES_EXECUTABLE", "hermes")
        self.transport = os.getenv("HERMES_TRANSPORT", "local")
        self.execution_tools_enabled = os.getenv("HERMES_EXECUTION_TOOLS", "true").lower() in {
            "1", "true", "yes", "on"
        }

    @property
    def installed(self) -> bool:
        return shutil.which(self.executable) is not None

    @property
    def configured(self) -> bool:
        return bool(self.tool_registry) or self.installed

    def status(self) -> HermesStatus:
        return HermesStatus(
            configured=self.configured,
            installed=self.installed,
            executable=shutil.which(self.executable),
            transport=self.transport,
            execution_tools_enabled=self.execution_tools_enabled,
        )

    def doctor(self) -> dict[str, Any]:
        """Return real local Hermes availability; never report success by assumption."""
        result: dict[str, Any] = {"installed": self.installed, "executable": shutil.which(self.executable)}
        if not self.installed:
            result["ready"] = False
            result["error"] = "Hermes executable is not installed on this host"
            return result
        try:
            completed = subprocess.run(
                [self.executable, "--help"],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            result["ready"] = completed.returncode == 0
            result["returncode"] = completed.returncode
            result["stderr"] = completed.stderr[-2000:]
            result["stdout"] = completed.stdout[-2000:]
        except Exception as exc:
            result["ready"] = False
            result["error"] = str(exc)
        return result

    def tool_manifest(self) -> list[dict[str, Any]]:
        """Return tools Hermes may invoke through the NeoFL bus."""
        execution_prefixes = ("place_", "modify_", "close_", "cancel_", "send_")
        manifest: list[dict[str, Any]] = []
        for name, fn in sorted(self.tool_registry.items()):
            if not self.execution_tools_enabled and name.startswith(execution_prefixes):
                continue
            manifest.append({
                "name": name,
                "description": getattr(fn, "__doc__", "") or name,
            })
        return manifest

    def call(self, name: str, arguments: dict[str, Any] | None = None) -> Any:
        """Invoke a registered NeoFL tool on Hermes' behalf."""
        if name not in self.tool_registry:
            raise KeyError(f"Unknown NeoFL tool: {name}")
        return self.tool_registry[name](**(arguments or {}))

    def manifest_json(self) -> str:
        return json.dumps(self.tool_manifest(), indent=2, sort_keys=True)
