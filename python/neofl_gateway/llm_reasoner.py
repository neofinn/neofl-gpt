"""Optional LLM reasoner for NeoFL Agentic Soul."""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any


class OpenAIReasoner:
    def __init__(self, api_key: str | None = None, model: str | None = None, timeout: int = 30) -> None:
        self.api_key = api_key or os.getenv("OPENAI_API_KEY", "")
        self.model = model or os.getenv("NEOFL_REASONING_MODEL", "gpt-5.6-luna")
        self.timeout = timeout

    @property
    def enabled(self) -> bool:
        return bool(self.api_key)

    def reason(self, *, goal: str, symbol: str, observations: list[dict[str, Any]], hypotheses: list[dict[str, Any]], contradictions: list[str], memory: list[dict[str, Any]] | None = None) -> dict[str, Any] | None:
        if not self.enabled:
            return None
        prompt = self._prompt(goal, symbol, observations, hypotheses, contradictions, memory or [])
        payload = json.dumps({"model": self.model, "input": prompt}).encode("utf-8")
        req = urllib.request.Request("https://api.openai.com/v1/responses", data=payload, method="POST", headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as response:
                body = json.loads(response.read().decode("utf-8"))
            text = self._output_text(body)
            if not text:
                return None
            parsed = self._parse_json(text)
            return parsed if isinstance(parsed, dict) else None
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
            return None

    @staticmethod
    def _prompt(goal: str, symbol: str, observations: list[dict[str, Any]], hypotheses: list[dict[str, Any]], contradictions: list[str], memory: list[dict[str, Any]]) -> str:
        return f"""You are the bounded reasoning layer of NeoFL, a trading research and decision-support system.
You are NOT an execution authority. Never invent market data, prices, positions, news, rules, or outcomes.
If evidence is missing, say so. Treat UNKNOWN/UNAVAILABLE/INVALID evidence as non-tradable.
Use prior episodic memory as context, not as proof. Challenge the strongest thesis and produce a calibrated recommendation.

Return ONLY valid JSON with this shape:
{{
  \"verdict\": \"RECOMMEND|WAIT|NO_DECISION\",
  \"reason\": \"short explanation\",
  \"confidence\": 0.0,
  \"hypotheses\": [{{\"name\": \"...\", \"thesis\": \"...\", \"confidence\": 0.0, \"evidence\": [\"...\"], \"invalidators\": [\"...\"]}}],
  \"contradictions\": [\"...\"],
  \"missing_evidence\": [\"...\"],
  \"next_actions\": [\"...\"]
}}

GOAL: {goal}
SYMBOL: {symbol}
OBSERVATIONS: {json.dumps(observations, default=str)}
CURRENT HYPOTHESES: {json.dumps(hypotheses, default=str)}
CONTRADICTIONS: {json.dumps(contradictions, default=str)}
PRIOR EPISODIC MEMORY: {json.dumps(memory, default=str)}
"""

    @staticmethod
    def _output_text(body: dict[str, Any]) -> str:
        direct = body.get("output_text")
        if isinstance(direct, str):
            return direct
        chunks: list[str] = []
        for item in body.get("output", []) or []:
            if not isinstance(item, dict):
                continue
            for content in item.get("content", []) or []:
                if isinstance(content, dict) and isinstance(content.get("text"), str):
                    chunks.append(content["text"])
        return "\n".join(chunks)

    @staticmethod
    def _parse_json(text: str) -> Any:
        text = text.strip()
        if text.startswith("```"):
            lines = text.splitlines()
            if lines and lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            text = "\n".join(lines).strip()
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            start, end = text.find("{"), text.rfind("}")
            if start >= 0 and end > start:
                return json.loads(text[start:end + 1])
            raise
