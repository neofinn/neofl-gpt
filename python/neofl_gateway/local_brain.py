"""Local model adapter for the NeoFLGPT Parallel runtime.

LOCAL mode uses a real Ollama localhost server or an explicit GGUF model.
No remote model endpoint is implied by this adapter.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


class LocalBrainError(RuntimeError):
    pass


class LocalBrain:
    def __init__(self, *, backend: str | None = None, model: str | None = None,
                 ollama_url: str | None = None, gguf_path: str | None = None,
                 timeout: int = 120) -> None:
        self.backend = (backend or os.getenv("NEOFL_LOCAL_BACKEND", "ollama")).lower()
        self.model = model or os.getenv("NEOFL_LOCAL_MODEL", "qwen3:8b")
        self.ollama_url = (ollama_url or os.getenv("NEOFL_OLLAMA_URL", "http://127.0.0.1:11434")).rstrip("/")
        self.gguf_path = gguf_path or os.getenv("NEOFL_GGUF_MODEL", "")
        self.timeout = timeout
        self._llama = None

    @property
    def enabled(self) -> bool:
        return bool(self.model) if self.backend == "ollama" else bool(self.gguf_path)

    def status(self) -> dict[str, Any]:
        if self.backend == "ollama":
            try:
                code, body = self._http("/api/tags", None, method="GET")
                if code == 200:
                    tags = json.loads(body).get("models", [])
                    names = [str(x.get("name", "")) for x in tags]
                    installed = self.model in names or any(
                        n.split(":", 1)[0] == self.model.split(":", 1)[0] for n in names
                    )
                    return {"mode": "LOCAL", "backend": "ollama", "online": True,
                            "model": self.model, "model_installed": installed,
                            "endpoint": self.ollama_url, "models": names}
                return {"mode": "LOCAL", "backend": "ollama", "online": False,
                        "model": self.model, "model_installed": False,
                        "endpoint": self.ollama_url, "error": f"HTTP {code}"}
            except Exception as exc:
                return {"mode": "LOCAL", "backend": "ollama", "online": False,
                        "model": self.model, "model_installed": False,
                        "error": str(exc), "endpoint": self.ollama_url}
        p = Path(self.gguf_path)
        return {"mode": "LOCAL", "backend": "llama.cpp", "online": p.is_file(),
                "model": self.gguf_path, "model_installed": p.is_file()}

    def chat(self, messages: list[dict[str, str]], *, temperature: float = 0.2,
             max_tokens: int = 2048) -> str:
        if self.backend == "ollama":
            payload = {"model": self.model, "messages": messages, "stream": False,
                       "options": {"temperature": temperature, "num_predict": max_tokens}}
            code, body = self._http("/api/chat", payload)
            if code != 200:
                raise LocalBrainError(f"Ollama HTTP {code}: {body[:500]}")
            return str(json.loads(body).get("message", {}).get("content", ""))
        return self._chat_llama(messages, temperature, max_tokens)

    def _chat_llama(self, messages: list[dict[str, str]], temperature: float, max_tokens: int) -> str:
        if not self.gguf_path or not Path(self.gguf_path).is_file():
            raise LocalBrainError("NEOFL_GGUF_MODEL does not point to an existing GGUF model")
        if self._llama is None:
            try:
                from llama_cpp import Llama
            except ImportError as exc:
                raise LocalBrainError("Install llama-cpp-python for GGUF local inference") from exc
            self._llama = Llama(model_path=self.gguf_path, n_ctx=8192, verbose=False)
        result = self._llama.create_chat_completion(messages=messages, temperature=temperature,
                                                     max_tokens=max_tokens)
        return str(result["choices"][0]["message"]["content"])

    def _http(self, path: str, payload: Any, *, method: str = "POST") -> tuple[int, str]:
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(self.ollama_url + path, data=data, method=method,
                                     headers={"Content-Type": "application/json", "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as response:
                return response.status, response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read().decode("utf-8", errors="replace")
        except urllib.error.URLError as exc:
            raise LocalBrainError(f"Ollama unreachable at {self.ollama_url}: {exc.reason}") from exc
