"""Webhook creation and receipt.

Canon: TradingView webhooks feed the external gateway, and webhook payloads must be
normalized. Also: request timestamps, nonces/request IDs, replay protection, and rate
limiting are security requirements, not optional extras.

A webhook is a URL on the public internet that causes something to happen inside a
trading system. Treat every payload as hostile: it can be replayed by anyone who saw
it once, forged by anyone who guesses the path, and malformed by a provider changing
its format without notice.

What this module deliberately does NOT do: act on a payload. A webhook produces a
normalized snapshot. Whether that snapshot means anything is the strategy's business,
and per D-001 nothing here can reach an order.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import secrets
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Callable

from .schema import DataQuality, Decision, MarketSnapshot, Source, Verdict, unavailable

# A payload older than this is refused outright: a stale alert acted on late is worse
# than no alert. Generous enough to absorb provider and network latency.
DEFAULT_MAX_AGE_SECONDS = 60.0

# Replay window: how many recent request ids to remember per endpoint.
REPLAY_MEMORY = 4096


class WebhookError(Exception):
    """Raised when a payload is refused. The message is safe to log, never to return
    to the caller verbatim — it can reveal which check failed."""


@dataclass
class Webhook:
    """A registered inbound endpoint."""

    name: str
    path: str
    secret: str
    normalizer: Callable[[dict[str, Any]], MarketSnapshot]
    max_age_seconds: float = DEFAULT_MAX_AGE_SECONDS
    _seen: deque = field(default_factory=lambda: deque(maxlen=REPLAY_MEMORY), repr=False)
    _seen_set: set = field(default_factory=set, repr=False)

    @property
    def url_suffix(self) -> str:
        return self.path

    def sign(self, body: bytes) -> str:
        """The signature a sender must compute. Shared with the provider at setup."""
        return hmac.new(self.secret.encode(), body, hashlib.sha256).hexdigest()

    def _check_signature(self, body: bytes, provided: str | None) -> None:
        if not provided:
            raise WebhookError("missing signature")
        expected = self.sign(body)
        # Constant-time: a naive == leaks the correct prefix through timing.
        if not hmac.compare_digest(expected, provided):
            raise WebhookError("signature mismatch")

    def _check_replay(self, request_id: str) -> None:
        if request_id in self._seen_set:
            raise WebhookError(f"replayed request id {request_id!r}")
        if len(self._seen) == self._seen.maxlen and self._seen:
            self._seen_set.discard(self._seen[0])
        self._seen.append(request_id)
        self._seen_set.add(request_id)

    def _check_freshness(self, sent_at: float, now: float) -> None:
        age = now - sent_at
        if age > self.max_age_seconds:
            raise WebhookError(f"payload {age:.1f}s old, limit {self.max_age_seconds:.0f}s")
        # A timestamp in the future means clock skew or forgery; tolerate a little.
        if age < -30.0:
            raise WebhookError(f"payload timestamped {-age:.1f}s in the future")

    def receive(
        self,
        body: bytes,
        signature: str | None,
        now: float | None = None,
    ) -> tuple[MarketSnapshot, Decision]:
        """Validate and normalize an inbound payload.

        Returns the snapshot and a provenance record (D-002) describing the outcome —
        including refusals, so a rejected webhook is observable rather than silent.
        """
        now = time.time() if now is None else now

        try:
            self._check_signature(body, signature)

            try:
                payload = json.loads(body.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise WebhookError(f"payload is not valid JSON: {exc}") from exc

            if not isinstance(payload, dict):
                raise WebhookError("payload must be a JSON object")

            request_id = str(payload.get("request_id") or "")
            if not request_id:
                raise WebhookError("missing request_id (required for replay protection)")
            self._check_replay(request_id)

            sent_at = payload.get("sent_at")
            if sent_at is None:
                raise WebhookError("missing sent_at (required for freshness check)")
            try:
                self._check_freshness(float(sent_at), now)
            except (TypeError, ValueError) as exc:
                raise WebhookError(f"sent_at is not a timestamp: {exc}") from exc

            snapshot = self.normalizer(payload)

        except WebhookError as exc:
            snap = unavailable(Source.TRADINGVIEW, self.name, str(exc))
            decision = Decision(
                engine=f"Webhook:{self.name}",
                symbol="-",
                verdict=Verdict.BLOCKED,
                quality=DataQuality.UNAVAILABLE,
                reason=f"payload refused: {exc}",
                inputs=f"bytes={len(body)}",
            )
            return snap, decision

        # Transport validity is not content validity. A correctly signed, fresh,
        # non-replayed payload can still normalize to something unusable — an
        # unmappable instrument, an implausible quote, one-sided depth.
        #
        # These must NOT be treated as accepted. Letting them through is how BTCXAU
        # ends up in published state despite the gold-only rule: every transport
        # check passed, so nothing objected to the content.
        if not snapshot.quality.tradable:
            decision = Decision(
                engine=f"Webhook:{self.name}",
                symbol=snapshot.mapped_symbol or snapshot.instrument,
                verdict=Verdict.DECLINE,
                quality=snapshot.quality,
                reason=f"payload well-formed but unusable: {snapshot.detail}",
                inputs=f"instrument={snapshot.instrument} bytes={len(body)}",
            )
            return snapshot, decision

        decision = Decision(
            engine=f"Webhook:{self.name}",
            symbol=snapshot.mapped_symbol or snapshot.instrument,
            verdict=Verdict.PROCEED,
            quality=snapshot.quality,
            reason="payload accepted and normalized",
            inputs=f"instrument={snapshot.instrument} bytes={len(body)}",
        )
        return snapshot, decision


class WebhookRegistry:
    """Creates and holds webhooks.

    `create()` is the 'webhook creator': it mints a path and a secret, wires a
    normalizer, and hands back everything needed to configure the sending provider.
    """

    def __init__(self) -> None:
        self._hooks: dict[str, Webhook] = {}

    def create(
        self,
        name: str,
        normalizer: Callable[[dict[str, Any]], MarketSnapshot],
        *,
        secret: str | None = None,
        max_age_seconds: float = DEFAULT_MAX_AGE_SECONDS,
    ) -> Webhook:
        if name in self._hooks:
            raise ValueError(f"webhook {name!r} already exists")

        # Unguessable path: knowing the name must not reveal the endpoint.
        path = f"/webhook/{name}/{secrets.token_urlsafe(16)}"
        hook = Webhook(
            name=name,
            path=path,
            secret=secret or secrets.token_urlsafe(32),
            normalizer=normalizer,
            max_age_seconds=max_age_seconds,
        )
        self._hooks[name] = hook
        return hook

    def get(self, name: str) -> Webhook | None:
        return self._hooks.get(name)

    def by_path(self, path: str) -> Webhook | None:
        for hook in self._hooks.values():
            if hmac.compare_digest(hook.path, path):
                return hook
        return None

    def names(self) -> list[str]:
        return sorted(self._hooks)
