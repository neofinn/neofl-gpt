"""Minimal Streamable-HTTP MCP client for the NeoFL agent runtime.

This module makes NeoFL the MCP *client* instead of requiring ChatGPT/Codex to
remain the permanent MCP host. Credentials are read from environment/configuration
and are never persisted by this module.

The client is intentionally transport-only: Soul/Brain decides which tools may be
used. Tool discovery and invocation are exposed as ordinary Python operations so
the existing AgenticSoul ToolRegistry can own the cognitive policy.
"""
from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass, field
from typing import Any


@dataclass
class MCPTool:
    name: str
    description: str = ""
    input_schema: dict[str, Any] = field(default_factory=dict)


class MCPError(RuntimeError):
    pass


class MCPClient:
    """Small dependency-free MCP client for Streamable HTTP endpoints."""

    def __init__(
        self,
        url: str,
        token: str | None = None,
        protocol_version: str | None = None,
        timeout: float = 15.0,
    ) -> None:
        if not url:
            raise ValueError("MCP url is required")
        self.url = url
        self.token = token or ""
        self.protocol_version = protocol_version or os.getenv("NEOFL_MCP_PROTOCOL", "2025-06-18")
        self.timeout = timeout
        self.session_id: str | None = None
        self.initialized = False
        self.server_info: dict[str, Any] = {}
        self.tools: dict[str, MCPTool] = {}
        self._request_id = 0

    @classmethod
    def from_env(cls, prefix: str = "NEOFL_MARKETDATA") -> "MCPClient":
        url = os.getenv(f"{prefix}_MCP_URL") or os.getenv("NEOFL_MCP_URL")
        token = os.getenv(f"{prefix}_MCP_TOKEN") or os.getenv("NEOFL_MCP_TOKEN")
        return cls(url=url or "", token=token)

    def initialize(self) -> dict[str, Any]:
        result, headers = self._rpc(
            "initialize",
            {
                "protocolVersion": self.protocol_version,
                "capabilities": {"tools": {}, "logging": {}},
                "clientInfo": {"name": "NeoFL-Agent-Runtime", "version": "1.0"},
            },
            include_session=False,
        )
        self.server_info = result.get("serverInfo") or {}
        self.initialized = True
        if not self.session_id:
            self.session_id = headers.get("Mcp-Session-Id") or headers.get("mcp-session-id")
        # MCP initialization requires the initialized notification before normal use.
        self._notification("notifications/initialized")
        return result

    def list_tools(self) -> list[MCPTool]:
        self._ensure_initialized()
        result, _ = self._rpc("tools/list", {})
        raw = result.get("tools") or []
        self.tools = {
            str(item.get("name")): MCPTool(
                name=str(item.get("name")),
                description=str(item.get("description", "")),
                input_schema=item.get("inputSchema") or {},
            )
            for item in raw
            if isinstance(item, dict) and item.get("name")
        }
        return list(self.tools.values())

    def call_tool(self, name: str, arguments: dict[str, Any] | None = None) -> dict[str, Any]:
        self._ensure_initialized()
        if name not in self.tools:
            self.list_tools()
        if name not in self.tools:
            raise MCPError(f"MCP tool is not registered: {name}")
        result, _ = self._rpc("tools/call", {"name": name, "arguments": arguments or {}})
        return result

    def close(self) -> None:
        self.session_id = None
        self.initialized = False
        self.tools.clear()

    def _ensure_initialized(self) -> None:
        if not self.initialized:
            self.initialize()

    def _headers(self, include_session: bool = True) -> dict[str, str]:
        headers = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            "User-Agent": "NeoFL-Agent-Runtime/1.0",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if include_session and self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        return headers

    def _rpc(self, method: str, params: dict[str, Any], include_session: bool = True) -> tuple[dict[str, Any], dict[str, str]]:
        self._request_id += 1
        request_id = self._request_id
        payload = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        request = urllib.request.Request(
            self.url,
            data=json.dumps(payload).encode("utf-8"),
            headers=self._headers(include_session),
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                raw = response.read().decode("utf-8", errors="replace")
                headers = {k: v for k, v in response.headers.items()}
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise MCPError(f"MCP HTTP {exc.code}: {body[:500]}") from exc
        except urllib.error.URLError as exc:
            raise MCPError(f"MCP transport error: {exc.reason}") from exc

        session = headers.get("Mcp-Session-Id") or headers.get("mcp-session-id")
        if session:
            self.session_id = session
        message = self._decode_message(raw)
        if message.get("error"):
            error = message["error"]
            raise MCPError(f"MCP {error.get('code')}: {error.get('message')}")
        return message.get("result") or {}, headers

    def _notification(self, method: str, params: dict[str, Any] | None = None) -> None:
        payload = {"jsonrpc": "2.0", "method": method}
        if params:
            payload["params"] = params
        request = urllib.request.Request(
            self.url,
            data=json.dumps(payload).encode("utf-8"),
            headers=self._headers(),
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout):
                pass
        except Exception as exc:
            raise MCPError(f"MCP notification failed: {exc}") from exc

    @staticmethod
    def _decode_message(raw: str) -> dict[str, Any]:
        raw = raw.strip()
        if not raw:
            return {}
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            # Streamable HTTP may return an SSE event containing the JSON-RPC message.
            for line in raw.splitlines():
                if line.startswith("data:"):
                    data = line[5:].strip()
                    try:
                        return json.loads(data)
                    except json.JSONDecodeError:
                        continue
        raise MCPError("MCP response was neither JSON nor a decodable SSE message")

    @property
    def status(self) -> dict[str, Any]:
        return {
            "configured": bool(self.url),
            "authenticated": bool(self.token),
            "initialized": self.initialized,
            "session_id_present": bool(self.session_id),
            "server_info": self.server_info,
            "tool_count": len(self.tools),
            "tool_names": sorted(self.tools),
        }
