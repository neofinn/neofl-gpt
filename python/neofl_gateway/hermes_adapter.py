"""Hermes adapter for NeoFLGPT Parallel.

Hermes is an agent/tool runtime. This adapter keeps Hermes behind NeoFL's
existing tool bus so Hermes can discover NeoFL market/account tools without
hard-coding broker logic into Hermes.

The adapter can proxy an existing NeoFL MCP client. Discovery is lazy so a
local Hermes installation can be tested without an MCP endpoint, while a
configured NeoFL MCP endpoint is automatically exposed to Hermes.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from typing import Any, Callable

from .mcp_client import MCPClient, MCPTool


@dataclass
class HermesStatus:
    configured: bool
    installed: bool
    executable: str | None
    transport: str
    execution_tools_enabled: bool
    mcp_configured: bool = False
    mcp_initialized: bool = False
    mcp_tool_count: int = 0
    last_error: str | None = None


class HermesAdapter:
    """Bridge Hermes to the NeoFL tool registry and optional NeoFL MCP bus."""

    def __init__(
        self,
        tool_registry: dict[str, Callable[..., Any]] | None = None,
        mcp_client: MCPClient | None = None,
    ) -> None:
        self.tool_registry = dict(tool_registry or {})
        self.executable = os.getenv("HERMES_EXECUTABLE", "hermes")
        self.transport = os.getenv("HERMES_TRANSPORT", "local")
        self.execution_tools_enabled = os.getenv("HERMES_EXECUTION_TOOLS", "true").lower() in {
            "1", "true", "yes", "on"
        }
        self.mcp = mcp_client
        if self.mcp is None:
            url = os.getenv("NEOFL_MARKETDATA_MCP_URL") or os.getenv("NEOFL_MCP_URL")
            token = os.getenv("NEOFL_MARKETDATA_MCP_TOKEN") or os.getenv("NEOFL_MCP_TOKEN")
            if url:
                self.mcp = MCPClient(url=url, token=token)
        self.last_error: str | None = None

    @property
    def installed(self) -> bool:
        return shutil.which(self.executable) is not None

    @property
    def configured(self) -> bool:
        return bool(self.tool_registry) or self.installed or self.mcp is not None

    def _refresh_mcp_tools(self) -> list[MCPTool]:
        if self.mcp is None:
            return []
        try:
            tools = self.mcp.list_tools()
            self.last_error = None
            return tools
        except Exception as exc:
            self.last_error = str(exc)
            return []

    def status(self) -> HermesStatus:
        mcp_tools = list(self.mcp.tools.values()) if self.mcp is not None else []
        return HermesStatus(
            configured=self.configured,
            installed=self.installed,
            executable=shutil.which(self.executable),
            transport=self.transport,
            execution_tools_enabled=self.execution_tools_enabled,
            mcp_configured=bool(self.mcp and self.mcp.url),
            mcp_initialized=bool(self.mcp and self.mcp.initialized),
            mcp_tool_count=len(mcp_tools),
            last_error=self.last_error,
        )

    def doctor(self) -> dict[str, Any]:
        """Return real local Hermes availability; never report success by assumption."""
        result: dict[str, Any] = {
            "installed": self.installed,
            "executable": shutil.which(self.executable),
            "mcp_configured": bool(self.mcp and self.mcp.url),
        }
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
        if self.mcp is not None:
            tools = self._refresh_mcp_tools()
            result["mcp_initialized"] = self.mcp.initialized
            result["mcp_tool_count"] = len(tools)
            result["mcp_tools"] = sorted(t.name for t in tools)
            if self.last_error:
                result["mcp_error"] = self.last_error
        return result

    def tool_manifest(self) -> list[dict[str, Any]]:
        """Return the live NeoFL tool manifest available to Hermes."""
        execution_prefixes = ("place_", "modify_", "close_", "cancel_", "send_")
        manifest: dict[str, dict[str, Any]] = {}

        for name, fn in sorted(self.tool_registry.items()):
            if not self.execution_tools_enabled and name.startswith(execution_prefixes):
                continue
            manifest[name] = {
                "name": name,
                "description": getattr(fn, "__doc__", "") or name,
                "transport": "neo-fl-registry",
            }

        for tool in self._refresh_mcp_tools():
            if not self.execution_tools_enabled and tool.name.startswith(execution_prefixes):
                continue
            manifest.setdefault(tool.name, {
                "name": tool.name,
                "description": tool.description or tool.name,
                "input_schema": tool.input_schema,
                "transport": "neo-fl-mcp",
            })

        return [manifest[name] for name in sorted(manifest)]

    def call(self, name: str, arguments: dict[str, Any] | None = None) -> Any:
        """Invoke a registered NeoFL tool or a discovered NeoFL MCP tool."""
        arguments = arguments or {}
        execution_prefixes = ("place_", "modify_", "close_", "cancel_", "send_")
        if not self.execution_tools_enabled and name.startswith(execution_prefixes):
            raise PermissionError(f"Hermes execution tool is disabled: {name}")

        if name in self.tool_registry:
            return self.tool_registry[name](**arguments)

        if self.mcp is not None:
            tools = self._refresh_mcp_tools()
            if any(tool.name == name for tool in tools):
                return self.mcp.call_tool(name, arguments)

        raise KeyError(f"Unknown NeoFL tool: {name}")

    def manifest_json(self) -> str:
        return json.dumps(self.tool_manifest(), indent=2, sort_keys=True)
