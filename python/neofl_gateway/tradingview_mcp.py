"""TradingView MCP integration for the NeoFL agent runtime.

TradingView is an evidence source only. This adapter deliberately exposes no
execution path: broker actions remain under the canonical NeoFL Body/MT5
execution fabric.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

from .mcp_client import MCPClient, MCPTool


@dataclass
class TradingViewMCP:
    client: MCPClient

    @classmethod
    def from_env(cls) -> "TradingViewMCP | None":
        url = os.getenv("NEOFL_TRADINGVIEW_MCP_URL")
        token = os.getenv("NEOFL_TRADINGVIEW_MCP_TOKEN")
        if not url:
            return None
        return cls(MCPClient(url=url, token=token))

    def connect(self) -> list[MCPTool]:
        self.client.initialize()
        return self.client.list_tools()

    def tools(self) -> list[MCPTool]:
        if not self.client.initialized:
            return self.connect()
        return list(self.client.tools.values())

    def analyze(self, symbol: str, timeframe: str | None = None) -> list[dict[str, Any]]:
        """Call read-only TradingView analysis tools selected by capability."""
        tools = self.tools()
        results: list[dict[str, Any]] = []
        hints = ("analysis", "technical", "indicator", "market", "quote", "snapshot", "price")
        for tool in tools:
            text = f"{tool.name} {tool.description}".lower()
            if not any(hint in text for hint in hints):
                continue
            if any(word in text for word in ("trade", "execute", "order", "buy", "sell")):
                continue
            properties = (tool.input_schema or {}).get("properties") or {}
            args: dict[str, Any] = {}
            for key in ("symbol", "ticker", "instrument"):
                if key in properties:
                    args[key] = symbol
                    break
            for key in ("timeframe", "interval"):
                if timeframe and key in properties:
                    args[key] = timeframe
                    break
            try:
                results.append({
                    "source": f"TradingView-MCP:{tool.name}",
                    "claim": "technical_market_evidence",
                    "value": self.client.call_tool(tool.name, args),
                    "quality": "OK",
                    "confidence": 0.9,
                })
            except Exception as exc:
                results.append({
                    "source": f"TradingView-MCP:{tool.name}",
                    "claim": "technical_market_evidence",
                    "value": None,
                    "quality": "UNAVAILABLE",
                    "confidence": 0.0,
                    "evidence": [str(exc)],
                })
        return results

    @property
    def status(self) -> dict[str, Any]:
        return self.client.status
