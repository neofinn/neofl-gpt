"""Local SQLite episodic memory used when Supabase is not configured."""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Any


class LocalMemory:
    enabled = True

    def __init__(self, path: str = "neofl_memory.db") -> None:
        self.path = Path(path)
        self.last_error: str | None = None
        self._init()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.path)

    def _init(self) -> None:
        with self._connect() as db:
            db.execute("CREATE TABLE IF NOT EXISTS agent_memory (id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL NOT NULL, symbol TEXT, request_id TEXT, payload TEXT NOT NULL)")

    def request(self, data: dict[str, Any]) -> bool:
        return self._write(data, "request")

    def decision(self, data: dict[str, Any]) -> bool:
        return self._write(data, "decision")

    def brain_event(self, brain: str, event_type: str, payload: dict[str, Any]) -> bool:
        return self._write({"brain": brain, "event_type": event_type, **payload}, "brain_event")

    def learning(self, source: str, hypothesis: str, outcome: str, lesson: str, payload: dict[str, Any] | None = None) -> bool:
        return self._write({"source": source, "hypothesis": hypothesis, "outcome": outcome, "lesson": lesson, "payload": payload or {}}, "learning")

    def _write(self, payload: dict[str, Any], kind: str) -> bool:
        try:
            with self._connect() as db:
                db.execute("INSERT INTO agent_memory(ts,symbol,request_id,payload) VALUES(?,?,?,?)", (time.time(), payload.get("symbol"), payload.get("request_id"), json.dumps({"kind": kind, "data": payload}, default=str)))
            self.last_error = None
            return True
        except sqlite3.Error as exc:
            self.last_error = str(exc)
            return False

    def recent_agent_memory(self, symbol: str | None = None, limit: int = 10) -> list[dict[str, Any]]:
        try:
            with self._connect() as db:
                if symbol:
                    rows = db.execute("SELECT payload FROM agent_memory WHERE symbol=? ORDER BY id DESC LIMIT ?", (symbol, limit)).fetchall()
                else:
                    rows = db.execute("SELECT payload FROM agent_memory ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
            out=[]
            for (raw,) in reversed(rows):
                item=json.loads(raw)
                if item.get("kind") == "request":
                    data=item.get("data") or {}
                    response=data.get("response") or {}
                    out.append({"request_id": data.get("request_id"), "symbol": data.get("symbol"), "goal": (data.get("request") or {}).get("text") or data.get("input_text"), "verdict": response.get("verdict"), "reason": response.get("answer") or response.get("reason"), "hypotheses": response.get("hypotheses", [])[:3], "timestamp": data.get("created_at")})
            return out[-limit:]
        except (sqlite3.Error, json.JSONDecodeError):
            return []

    def status(self) -> dict[str, Any]:
        return {"enabled": True, "provider": "sqlite", "path": str(self.path), "last_error": self.last_error}
