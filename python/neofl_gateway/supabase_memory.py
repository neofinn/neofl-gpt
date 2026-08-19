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
import urllib.parse
import urllib.request
from typing import Any


class SupabaseMemory:
    def __init__(self, url: str | None = None, service_role_key: str | None = None) -> None:
        self.url = (url or os.getenv("NEOFL_SUPABASE_URL", "")).rstrip("/")
        self.key = service_role_key or os.getenv("NEOFL_SUPABASE_SERVICE_ROLE_KEY", "")
        self.enabled = bool(self.url and self.key)
        self.last_error: str | None = None

    def _headers(self) -> dict[str, str]:
        return {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
        }

    def _insert(self, table: str, row: dict[str, Any]) -> bool:
        if not self.enabled:
            return False
        body = json.dumps(row, default=str).encode("utf-8")
        req = urllib.request.Request(
            f"{self.url}/rest/v1/{table}",
            data=body,
            method="POST",
            headers={**self._headers(), "Prefer": "return=minimal"},
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as response:
                response.read()
            self.last_error = None
            return True
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            self.last_error = str(exc)
            return False

    def _select(self, table: str, select: str, *, order: str | None = None, limit: int = 100) -> list[dict[str, Any]]:
        if not self.enabled:
            return []
        params = {"select": select, "limit": str(max(1, min(limit, 500)))}
        if order:
            params["order"] = order
        url = f"{self.url}/rest/v1/{table}?{urllib.parse.urlencode(params, safe='(),:*') }"
        req = urllib.request.Request(url, method="GET", headers=self._headers())
        try:
            with urllib.request.urlopen(req, timeout=8) as response:
                data = json.loads(response.read().decode("utf-8"))
            self.last_error = None
            return data if isinstance(data, list) else []
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError) as exc:
            self.last_error = str(exc)
            return []

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

    def execution_reports(self, limit: int = 100) -> list[dict[str, Any]]:
        """Return execution reports enriched with their intent and MT5 account identity.

        The browser never receives the service-role key. The gateway joins the three
        server-side sources needed by the Control Room: execution report, order intent,
        and gateway account. This also preserves rejected signals, including their
        rejection reason, instead of collapsing them into a generic error.
        """
        reports = self._select(
            "gateway_execution_reports",
            "id,timestamp,intent_id,account_id,adapter,environment,status,filled_quantity,average_fill_price,realized_pnl,broker_order_id,rejection_code,rejection_reason,metadata",
            order="timestamp.desc",
            limit=limit,
        )
        intents = self._select(
            "gateway_order_intents",
            "id,account_id,strategy,symbol,direction,order_type,quantity,entry,stop,target,time_in_force,thesis_id,risk_profile,metadata,status,created_at,completed_at",
            order="created_at.desc",
            limit=min(limit * 2, 500),
        )
        accounts = self._select(
            "gateway_accounts",
            "id,account_number,connector,server,environment,label,ea_status,brain_connected,execution_enabled,balance,equity,profit,current_positions",
            limit=500,
        )
        intent_by_id = {str(x.get("id")): x for x in intents}
        account_by_id = {str(x.get("id")): x for x in accounts}

        out: list[dict[str, Any]] = []
        for report in reports:
            intent = intent_by_id.get(str(report.get("intent_id")), {})
            account = account_by_id.get(str(report.get("account_id")), {})
            positions = account.get("current_positions") or []
            if isinstance(positions, dict):
                positions = [positions]

            ticket = str(report.get("broker_order_id") or "")
            unrealized = None
            matched_position: dict[str, Any] | None = None
            for position in positions:
                if not isinstance(position, dict):
                    continue
                candidate = str(position.get("ticket") or position.get("order") or position.get("position_id") or "")
                if ticket and candidate == ticket:
                    matched_position = position
                    break

            if matched_position is not None:
                unrealized = matched_position.get("profit")
                if unrealized is None:
                    unrealized = matched_position.get("unrealized_pnl")

            status = str(report.get("status") or "").upper()
            if status in {"FILLED", "PARTIALLY_FILLED", "OPEN", "RUNNING"} and matched_position is not None:
                bucket = "RUNNING"
            elif status in {"REJECTED", "DECLINED", "BLOCKED", "ERROR"}:
                bucket = "REJECTED"
            else:
                bucket = "CLOSED" if report.get("realized_pnl") is not None or status in {"CLOSED", "FILLED_CLOSED", "CANCELLED"} else "RUNNING"

            out.append({
                "id": report.get("id"),
                "timestamp": report.get("timestamp"),
                "account_id": report.get("account_id"),
                "account_number": account.get("account_number") or "UNKNOWN",
                "broker": account.get("server") or account.get("connector") or "MT5",
                "environment": report.get("environment") or account.get("environment"),
                "adapter": report.get("adapter"),
                "status": status,
                "bucket": bucket,
                "intent_id": report.get("intent_id"),
                "trade": {
                    "strategy": intent.get("strategy"),
                    "symbol": intent.get("symbol"),
                    "direction": intent.get("direction"),
                    "order_type": intent.get("order_type"),
                    "quantity": intent.get("quantity"),
                    "entry": intent.get("entry"),
                    "stop": intent.get("stop"),
                    "target": intent.get("target"),
                    "time_in_force": intent.get("time_in_force"),
                    "thesis_id": intent.get("thesis_id"),
                },
                "filled_quantity": report.get("filled_quantity"),
                "average_fill_price": report.get("average_fill_price"),
                "broker_order_id": report.get("broker_order_id"),
                "unrealized_pnl": unrealized,
                "realized_pnl": report.get("realized_pnl"),
                "rejection_code": report.get("rejection_code"),
                "rejection_reason": report.get("rejection_reason") or "",
                "position": matched_position,
                "metadata": report.get("metadata") or {},
            })
        return out

    def status(self) -> dict[str, Any]:
        return {"enabled": self.enabled, "configured": bool(self.url and self.key), "last_error": self.last_error}
