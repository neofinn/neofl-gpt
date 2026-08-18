"""The gateway HTTP server.

Standard library only, so it runs with no install. Transport is kept separate from
logic — the registries in `api.py` and `webhooks.py` know nothing about HTTP, so
swapping in FastAPI later is a change to this file alone.

Run it:

    python3 python/run_gateway.py

Security posture: binds to localhost by default. Canon requires HTTPS, authentication,
rate limiting and replay protection before anything faces the public internet. Replay
protection and signature checking live in `webhooks.py`; TLS and rate limiting are
deliberately NOT implemented here, because the right place for them is a reverse proxy
in front of this process, and pretending otherwise would give a false sense of safety.
"""

from __future__ import annotations

import json
import logging
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from .api import ApiRegistry, StateStore
from .webhooks import WebhookRegistry

log = logging.getLogger("neofl.gateway")

MAX_BODY_BYTES = 256 * 1024  # a webhook payload has no business being larger


class GatewayHandler(BaseHTTPRequestHandler):
    server_version = "NeoFL-Gateway/1.0"

    # Injected by make_server().
    api: ApiRegistry
    webhooks: WebhookRegistry
    store: StateStore

    def log_message(self, fmt: str, *args) -> None:
        log.info("%s - %s", self.address_string(), fmt % args)

    # --- responses -----------------------------------------------------------

    def _send(self, status: int, payload) -> None:
        body = json.dumps(payload, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        # This surface is read-only and machine-facing; no reason to allow embedding.
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, message: str) -> None:
        # Deliberately terse. Detailed reasons go to the log, not to the caller —
        # telling a prober which check failed helps them pass it next time.
        self._send(status, {"error": message})

    # --- GET: the read surface ------------------------------------------------

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        endpoint = self.api.get(parsed.path)

        if endpoint is None:
            self._error(404, "not found")
            return

        if endpoint.requires_auth:
            token = self.headers.get("Authorization", "")
            token = token[7:] if token.startswith("Bearer ") else token
            if not self.api.authorize(token):
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Bearer realm="NeoFL-Gateway"')
                self.end_headers()
                return

        query = {k: v[0] for k, v in parse_qs(parsed.query).items()}
        try:
            self._send(200, endpoint.invoke(query))
        except Exception as exc:  # a handler bug must not take the gateway down
            log.exception("endpoint %s failed", parsed.path)
            self._error(500, "endpoint error")

    # --- POST: the webhook surface --------------------------------------------

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        hook = self.webhooks.by_path(parsed.path)

        if hook is None:
            # Same response as a signature failure, so probing cannot enumerate paths.
            self._error(404, "not found")
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._error(400, "bad request")
            return

        if length <= 0 or length > MAX_BODY_BYTES:
            self._error(413, "payload size not accepted")
            return

        body = self.rfile.read(length)
        signature = self.headers.get("X-NeoFL-Signature")

        snapshot, decision = hook.receive(body, signature)

        # Record the decision either way: a refused webhook must be observable, not
        # silent. An endpoint that quietly drops bad payloads looks identical to one
        # nobody is calling.
        self.store.put_decision(decision)

        if decision.verdict.value == "BLOCKED":
            # Transport-level refusal: the sender did something wrong.
            log.warning("webhook %s refused: %s", hook.name, decision.reason)
            self._error(400, "payload refused")
            return

        if decision.verdict.value == "DECLINE":
            # Well-formed but unusable content. The sender's transport was correct, so
            # this is not a 400 — a 400 would make the provider retry a payload that
            # will never become valid. But it must never reach published state.
            log.warning("webhook %s declined: %s", hook.name, decision.reason)
            self._send(200, {"accepted": False, "reason": "content not usable",
                             "quality": snapshot.quality.value})
            return

        # Only tradable snapshots are published. Everything else stops here, having
        # been recorded in the decision log above.
        self.store.put_snapshot(snapshot)
        log.info("webhook %s accepted %s", hook.name, snapshot.mapped_symbol)
        self._send(200, {"accepted": True, "symbol": snapshot.mapped_symbol,
                         "quality": snapshot.quality.value})


def make_server(
    api: ApiRegistry,
    webhooks: WebhookRegistry,
    store: StateStore,
    host: str = "127.0.0.1",
    port: int = 8787,
) -> ThreadingHTTPServer:
    handler = type("BoundGatewayHandler", (GatewayHandler,),
                   {"api": api, "webhooks": webhooks, "store": store})
    return ThreadingHTTPServer((host, port), handler)
