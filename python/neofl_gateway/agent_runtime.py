"""NeoFL autonomous agent runtime.

The runtime hosts NeoFL's MCP clients and cognitive loop. TradingView is an
additional read-only evidence source; MetaTrader remains the Body/execution
source and execution authority.
"""
from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field
from typing import Any

from .agent import AgentLoop, AgentRequest, AgentResponse
from .mcp_client import MCPClient, MCPError, MCPTool
from .tradingview_mcp import TradingViewMCP


@dataclass
class AgentRuntimeStatus:
    running: bool = False
    cycle: int = 0
    last_cycle_at: float | None = None
    last_error: str | None = None
    mcp: dict[str, Any] = field(default_factory=dict)
    tradingview_mcp: dict[str, Any] = field(default_factory=dict)
    discovered_tools: list[str] = field(default_factory=list)


class NeoFLAgentRuntime:
    """Long-lived observe -> reason -> reassess loop for NeoFL."""

    OBSERVATION_HINTS = {
        "market": ("market", "quote", "tick", "price", "symbol", "rates"),
        "account": ("account", "balance", "equity", "margin", "fund"),
        "positions": ("position", "positions", "open_positions"),
        "orders": ("order", "orders", "history", "trade", "deals"),
    }

    def __init__(self, agent: AgentLoop, mcp: MCPClient | None = None,
                 tradingview: TradingViewMCP | None = None) -> None:
        self.agent = agent
        self.mcp = mcp
        self.tradingview = tradingview
        self.status = AgentRuntimeStatus()
        self._tools: dict[str, MCPTool] = {}

    def connect_mcp(self) -> dict[str, Any]:
        if self.mcp is None:
            raise MCPError("NeoFL MetaTrader MCP client is not configured")
        self.mcp.initialize()
        tools = self.mcp.list_tools()
        self._tools = {tool.name: tool for tool in tools}
        self.status.mcp = self.mcp.status
        self.status.discovered_tools = sorted(self._tools)
        self.status.last_error = None
        return self.status.mcp

    def connect_tradingview(self) -> dict[str, Any]:
        if self.tradingview is None:
            self.status.tradingview_mcp = {"configured": False}
            return self.status.tradingview_mcp
        self.tradingview.connect()
        self.status.tradingview_mcp = self.tradingview.status
        return self.status.tradingview_mcp

    def observe(self, symbol: str | None = None) -> list[dict[str, Any]]:
        """Acquire a bounded evidence bundle from MetaTrader + TradingView MCP."""
        observations: list[dict[str, Any]] = []
        if self.mcp is not None:
            if not self.mcp.initialized:
                self.connect_mcp()
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
                            "source": f"MetaTrader-MCP:{name}",
                            "claim": category,
                            "value": result,
                            "quality": "OK",
                            "confidence": 0.95,
                        })
                    except Exception as exc:
                        observations.append({
                            "source": f"MetaTrader-MCP:{name}",
                            "claim": category,
                            "value": None,
                            "quality": "UNAVAILABLE",
                            "confidence": 0.0,
                            "evidence": [str(exc)],
                        })
        if self.tradingview is not None and symbol:
            try:
                observations.extend(self.tradingview.analyze(symbol))
                self.status.tradingview_mcp = self.tradingview.status
            except Exception as exc:
                observations.append({
                    "source": "TradingView-MCP",
                    "claim": "technical_market_evidence",
                    "value": None,
                    "quality": "UNAVAILABLE",
                    "confidence": 0.0,
                    "evidence": [str(exc)],
                })
        return observations

    def cycle(self, request: AgentRequest, *, pull_mcp: bool = True) -> AgentResponse:
        """Run one cognition cycle using fresh external evidence."""
        self.status.running = True
        self.status.cycle += 1
        self.status.last_cycle_at = time.time()
        try:
            context = dict(request.context or {})
            if pull_mcp:
                if self.mcp is not None:
                    context["mcp_status"] = self.connect_mcp()
                if self.tradingview is not None:
                    context["tradingview_mcp_status"] = self.connect_tradingview()
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
        if interval_seconds <= 0:
            raise ValueError("interval_seconds must be positive")
        self.status.running = True
        while self.status.running:
            self.cycle(request_factory(), pull_mcp=True)
            time.sleep(interval_seconds)

    def stop(self) -> None:
        self.status.running = False

    def introspect(self) -> dict[str, Any]:
        return asdict(self.status)

    @staticmethod
    def _looks_like_execution_tool(tool: MCPTool) -> bool:
        text = f"{tool.name} {tool.description}".lower()
        return any(word in text for word in (
            "place order", "send order", "trade", "execute", "close position",
            "modify order", "cancel order", "buy", "sell",
        ))

    @staticmethod
    def _arguments_for(tool: MCPTool, symbol: str | None) -> dict[str, Any]:
        properties = (tool.input_schema or {}).get("properties") or {}
        args: dict[str, Any] = {}
        if symbol:
            for key in ("symbol", "instrument", "ticker"):
                if key in properties:
                    args[key] = symbol
                    break
        return args
