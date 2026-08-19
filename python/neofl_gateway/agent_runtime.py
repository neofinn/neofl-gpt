"""NeoFL autonomous agent runtime.

The runtime is the missing bridge between the existing CognitiveSoul and external
MCP tools. It makes NeoFL itself the MCP client/agent host while preserving the
existing Soul, specialist, risk, memory, Body, and execution contracts.

This first stage is deliberately additive: it discovers tools and acquires live
observations through MCP, then hands those observations to the existing Soul. It
does not rewrite the established strategy engines or execution fabric.
"""
from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field
from typing import Any

from .agent import AgentLoop, AgentRequest, AgentResponse
from .mcp_client import MCPClient, MCPError, MCPTool


@dataclass
class AgentRuntimeStatus:
    running: bool = False
    cycle: int = 0
    last_cycle_at: float | None = None
    last_error: str | None = None
    mcp: dict[str, Any] = field(default_factory=dict)
    discovered_tools: list[str] = field(default_factory=list)


class NeoFLAgentRuntime:
    """Long-lived observe -> reason -> act-loop host for NeoFL."""

    OBSERVATION_HINTS = {
        "market": ("market", "quote", "tick", "price", "symbol", "rates"),
        "account": ("account", "balance", "equity", "margin", "fund"),
        "positions": ("position", "positions", "open_positions"),
        "orders": ("order", "orders", "history", "trade", "deals"),
    }

    def __init__(self, agent: AgentLoop, mcp: MCPClient | None = None) -> None:
        self.agent = agent
        self.mcp = mcp
        self.status = AgentRuntimeStatus()
        self._tools: dict[str, MCPTool] = {}

    def connect_mcp(self) -> dict[str, Any]:
        if self.mcp is None:
            raise MCPError("NeoFL MCP client is not configured")
        self.mcp.initialize()
        tools = self.mcp.list_tools()
        self._tools = {tool.name: tool for tool in tools}
        self.status.mcp = self.mcp.status
        self.status.discovered_tools = sorted(self._tools)
        self.status.last_error = None
        return self.status.mcp

    def observe(self, symbol: str | None = None) -> list[dict[str, Any]]:
        """Acquire a bounded evidence bundle from discovered MCP tools.

        Tool selection is capability-driven rather than hard-coded to one broker
        API. We only call tools whose names strongly resemble an observation
        capability. Execution-capable tools are never called by this method.
        """
        if self.mcp is None:
            return []
        if not self.mcp.initialized:
            self.connect_mcp()

        observations: list[dict[str, Any]] = []
        for category, hints in self.OBSERVATION_HINTS.items():
            candidates = [name for name in self._tools if any(h in name.lower() for h in hints)]
            for name in candidates[:2]:
                tool = self._tools[name]
                if self._looks_like_execution_tool(tool):
                    continue
                args = self._arguments_for(tool, symbol)
                try:
                    result = self.mcp.call_tool(name, args)
                    observations.append({
                        "source": f"MCP:{name}",
                        "claim": category,
                        "value": result,
                        "quality": "OK",
                        "confidence": 0.95,
                        "evidence": [f"Live result from MetaTrader MCP tool {name}."],
                    })
                except Exception as exc:
                    observations.append({
                        "source": f"MCP:{name}",
                        "claim": category,
                        "value": None,
                        "quality": "UNAVAILABLE",
                        "confidence": 0.0,
                        "evidence": [f"MCP tool failed: {exc}"],
                    })
        return observations

    def cycle(self, request: AgentRequest, *, pull_mcp: bool = True) -> AgentResponse:
        """Run one autonomous cognition cycle using fresh MCP evidence."""
        self.status.running = True
        self.status.cycle += 1
        self.status.last_cycle_at = time.time()
        try:
            context = dict(request.context or {})
            if pull_mcp and self.mcp is not None:
                context["mcp_status"] = self.connect_mcp()
                fresh = self.observe(request.symbol)
                existing = list(context.get("observations") or [])
                context["observations"] = existing + fresh
            enriched = AgentRequest(
                text=request.text,
                symbol=request.symbol,
                mode=request.mode,
                request_id=request.request_id,
                context=context,
            )
            response = self.agent.handle(enriched)
            self.status.last_error = None
            return response
        except Exception as exc:
            self.status.last_error = str(exc)
            raise

    def run_forever(self, request_factory, interval_seconds: float = 1.0) -> None:
        """Persistent Brain loop; request_factory supplies the current goal/state."""
        if interval_seconds <= 0:
            raise ValueError("interval_seconds must be positive")
        self.status.running = True
        while self.status.running:
            request = request_factory()
            self.cycle(request, pull_mcp=True)
            time.sleep(interval_seconds)

    def stop(self) -> None:
        self.status.running = False

    def introspect(self) -> dict[str, Any]:
        return asdict(self.status)

    @staticmethod
    def _looks_like_execution_tool(tool: MCPTool) -> bool:
        text = f"{tool.name} {tool.description}".lower()
        execution_words = ("place order", "send order", "trade", "execute", "close position", "modify order", "cancel order")
        return any(word in text for word in execution_words)

    @staticmethod
    def _arguments_for(tool: MCPTool, symbol: str | None) -> dict[str, Any]:
        schema = tool.input_schema or {}
        properties = schema.get("properties") or {}
        args: dict[str, Any] = {}
        if symbol:
            for key in ("symbol", "instrument", "ticker"):
                if key in properties:
                    args[key] = symbol
                    break
        return args
