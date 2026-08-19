"""Optional durable NeoFL memory backed by Supabase REST.

The gateway remains runnable locally without Supabase. When NEOFL_SUPABASE_URL and
NEOFL_SUPABASE_SERVICE_ROLE_KEY are present, accepted requests, Soul decisions,
brain events, experiments and learning events are mirrored to the NeoFL project.
Service-role credentials are server-only and must never be exposed to the browser.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any


class SupabaseMemory:
    def __init__(self, url: str | None = None, service_role_key: str | None = None) -> None:
        self.url = (url or os.getenv("NEOFL_SUPABASE_URL", "")).rstrip("/")
        self.key = service_role_key or os.getenv("NEOFL_SUPABASE_SERVICE_ROLE_KEY", "")
        self.enabled = bool(self.url and self.key)
        self.last_error: str | None = None

    def _insert(self, table: str, row: dict[str, Any]) -> bool:
        if not self.enabled:
            return False
        body = json.dumps(row, default=str).encode("utf-8")
        req = urllib.request.Request(
            f"{self.url}/rest/v1/{table}",
            data=body,
            method="POST",
            headers={
                "apikey": self.key,
                "Authorization": f"Bearer {self.key}",
                "Content-Type": "application/json",
                "Prefer": "return=minimal",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as response:
                response.read()
            self.last_error = None
            return True
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            self.last_error = str(exc)
            return False

    def request(self, data: dict[str, Any]) -> bool:
        request = data.get("request") or {}
        return self._insert("agent_requests", {
            "request_id": request.get("request_id") or data.get("request_id"),
            "mode": request.get("mode", "analyze"),
            "symbol": request.get("symbol"),
            "input_text": request.get("text", ""),
            "response": data,
            "status": "accepted",
        })

    def decision(self, data: dict[str, Any]) -> bool:
        return self._insert("soul_decisions", {
            "request_id": data.get("request_id"),
            "symbol": data.get("symbol"),
            "state": data.get("verdict", "PROCEED"),
            "confidence": data.get("confidence"),
            "execution_authorized": False,
            "rationale": data.get("reason", ""),
            "payload": data,
        })

    def brain_event(self, brain: str, event_type: str, payload: dict[str, Any]) -> bool:
        return self._insert("brain_events", {
            "brain": brain,
            "event_type": event_type,
            "symbol": payload.get("symbol"),
            "state": payload.get("state"),
            "confidence": payload.get("confidence"),
            "payload": payload,
        })

    def learning(self, source: str, hypothesis: str, outcome: str, lesson: str, payload: dict[str, Any] | None = None) -> bool:
        return self._insert("learning_events", {
            "source": source,
            "hypothesis": hypothesis,
            "outcome": outcome,
            "lesson": lesson,
            "payload": payload or {},
        })

    def status(self) -> dict[str, Any]:
        return {"enabled": self.enabled, "configured": bool(self.url and self.key), "last_error": self.last_error}
