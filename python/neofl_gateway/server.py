"""NeoFL gateway HTTP transport.

The HTTP layer is only the Body. Every meaningful state transition is delegated
to NeoFLBody, which routes it through the single Agentic Soul before persistence.
"""
from __future__ import annotations

import json
import logging
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from .agent import AgentLoop, AgentRequest
from .api import ApiRegistry, StateStore
from .body import NeoFLBody
from .schema import DataQuality
from .webhooks import WebhookRegistry

log = logging.getLogger("neofl.gateway")
MAX_BODY_BYTES = 256 * 1024


class GatewayHandler(BaseHTTPRequestHandler):
    server_version = "NeoFL-Gateway/1.3"
    api: ApiRegistry
    webhooks: WebhookRegistry
    store: StateStore
    agent: AgentLoop
    body: NeoFLBody

    def log_message(self, fmt: str, *args) -> None:
        log.info("%s - %s", self.address_string(), fmt % args)

    def _send(self, status: int, payload) -> None:
        body = json.dumps(payload, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, message: str) -> None:
        self._send(status, {"error": message})

    def _auth(self) -> bool:
        token = self.headers.get("Authorization", "")
        token = token[7:] if token.startswith("Bearer ") else token
        return self.api.authorize(token)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        endpoint = self.api.get(parsed.path)
        if endpoint is None:
            self._error(404, "not found")
            return
        if endpoint.requires_auth and not self._auth():
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Bearer realm="NeoFL-Gateway"')
            self.end_headers()
            return
        query = {k: v[0] for k, v in parse_qs(parsed.query).items()}
        try:
            self._send(200, endpoint.invoke(query))
        except Exception:
            log.exception("endpoint %s failed", parsed.path)
            self._error(500, "endpoint error")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._error(400, "bad request")
            return
        if length <= 0 or length > MAX_BODY_BYTES:
            self._error(413, "payload size not accepted")
            return
        body_bytes = self.rfile.read(length)

        if parsed.path == "/input":
            if not self._auth():
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Bearer realm="NeoFL-Gateway"')
                self.end_headers()
                return
            try:
                payload = json.loads(body_bytes.decode("utf-8"))
                request = AgentRequest(
                    text=str(payload.get("text", "")),
                    symbol=payload.get("symbol"),
                    mode=str(payload.get("mode", "analyze")),
                    request_id=payload.get("request_id"),
                    context=payload.get("context") or {},
                )
                action = self.body.think(request)
                self._send(200 if action.allowed else 409, action.response)
            except ValueError as exc:
                self._error(400, str(exc))
            except Exception:
                log.exception("agent request failed")
                self._error(500, "agent error")
            return

        hook = self.webhooks.by_path(parsed.path)
        if hook is None:
            self._error(404, "not found")
            return
        signature = self.headers.get("X-NeoFL-Signature")
        snapshot, decision = hook.receive(body_bytes, signature)
        if decision.verdict.value == "BLOCKED":
            log.warning("webhook %s refused: %s", hook.name, decision.reason)
            self._error(400, "payload refused")
            return

        # Webhook data is not admitted directly into the Body anymore. The
        # webhook is only a sensory organ; Soul decides whether the observation
        # is usable before StateStore receives it.
        observation = snapshot.to_dict()
        action = self.body.receive_external_event(
            source=f"webhook:{hook.name}",
            symbol=snapshot.mapped_symbol,
            payload=observation,
            quality=snapshot.quality.value,
        )
        if not action.allowed:
            self._send(200, {"accepted": False, "reason": action.reason, "quality": snapshot.quality.value, "soul": action.response})
            return
        self.store.put_snapshot(snapshot)
        self._send(200, {"accepted": True, "symbol": snapshot.mapped_symbol, "quality": snapshot.quality.value, "soul": action.response})


def make_server(api: ApiRegistry, webhooks: WebhookRegistry, store: StateStore, agent: AgentLoop,
                host: str = "127.0.0.1", port: int = 8787) -> ThreadingHTTPServer:
    body = NeoFLBody(agent, store)
    handler = type("BoundGatewayHandler", (GatewayHandler,),
                   {"api": api, "webhooks": webhooks, "store": store, "agent": agent, "body": body})
    return ThreadingHTTPServer((host, port), handler)
