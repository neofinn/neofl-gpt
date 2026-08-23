"""Provider-neutral reasoning router for NeoFLGPT Parallel.

The router never fabricates a result. If the selected provider is unavailable,
it returns None and the existing deterministic fail-closed Agentic Soul path
continues.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

from .llm_reasoner import OpenAIReasoner


class OllamaReasoner:
    def __init__(self, url: str | None = None, model: str | None = None, timeout: int = 60) -> None:
        self.url = (url or os.getenv("NEOFL_OLLAMA_URL", "http://127.0.0.1:11434")).rstrip("/")
        self.model = model or os.getenv("NEOFL_REASONING_MODEL", "qwen3:8b")
        self.timeout = timeout
        self.last_error: str | None = None

    @property
    def enabled(self) -> bool:
        try:
            req = urllib.request.Request(f"{self.url}/api/tags", method="GET")
            with urllib.request.urlopen(req, timeout=3) as response:
                return response.status == 200
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
            return False

    def reason(self, *, goal: str, symbol: str, observations: list[dict[str, Any]], hypotheses: list[dict[str, Any]], contradictions: list[str], memory: list[dict[str, Any]] | None = None) -> dict[str, Any] | None:
        prompt = OpenAIReasoner._prompt(goal, symbol, observations, hypotheses, contradictions, memory or [])
        payload = json.dumps({"model": self.model, "messages": [{"role": "user", "content": prompt}], "stream": False, "format": "json"}).encode("utf-8")
        req = urllib.request.Request(f"{self.url}/api/chat", data=payload, method="POST", headers={"Content-Type": "application/json", "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as response:
                body = json.loads(response.read().decode("utf-8"))
            text = str((body.get("message") or {}).get("content") or "").strip()
            if not text:
                return None
            parsed = OpenAIReasoner._parse_json(text)
            self.last_error = None
            return parsed if isinstance(parsed, dict) else None
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError) as exc:
            self.last_error = str(exc)
            return None


class RoutedReasoner:
    """Select OpenAI, Ollama, or fail-closed deterministic reasoning."""

    def __init__(self) -> None:
        self.mode = os.getenv("NEOFL_REASONER", "auto").strip().lower()
        self.openai = OpenAIReasoner()
        self.ollama = OllamaReasoner()

    @property
    def enabled(self) -> bool:
        if self.mode == "openai":
            return self.openai.enabled
        if self.mode == "ollama":
            return self.ollama.enabled
        return self.openai.enabled or self.ollama.enabled

    @property
    def provider(self) -> str:
        if self.mode == "openai":
            return "openai-responses" if self.openai.enabled else "unavailable"
        if self.mode == "ollama":
            return "ollama" if self.ollama.enabled else "unavailable"
        if self.openai.enabled:
            return "openai-responses"
        if self.ollama.enabled:
            return "ollama"
        return "deterministic-fallback"

    @property
    def model(self) -> str | None:
        if self.provider == "openai-responses":
            return self.openai.model
        if self.provider == "ollama":
            return self.ollama.model
        return None

    def reason(self, **kwargs: Any) -> dict[str, Any] | None:
        if self.provider == "openai-responses":
            return self.openai.reason(**kwargs)
        if self.provider == "ollama":
            return self.ollama.reason(**kwargs)
        return None
