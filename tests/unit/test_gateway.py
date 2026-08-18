"""Gateway input/output surface.

Covers the two properties that matter most:

  1. A hostile or malformed payload cannot reach published state.
  2. Transport validity is not content validity — a perfectly signed, fresh,
     non-replayed payload carrying BTCXAU must still not be published.

The second is the subtler one and was a real defect: every transport check passed,
so nothing objected to the content, and BTCXAU landed in published state despite the
gold-only rule.
"""

import hashlib
import hmac
import json
import sys
import time
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "python"))

from neofl_gateway.api import ApiRegistry, StateStore, build_default_api  # noqa: E402
from neofl_gateway.normalizers import map_instrument, normalize_tradingview  # noqa: E402
from neofl_gateway.schema import DataQuality, Verdict  # noqa: E402
from neofl_gateway.webhooks import WebhookRegistry  # noqa: E402

SECRET = "test-secret"


def signed(body: dict, secret: str = SECRET) -> tuple[bytes, str]:
    raw = json.dumps(body).encode()
    return raw, hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()


def valid_payload(**overrides) -> dict:
    payload = {
        "request_id": f"req-{time.time_ns()}",
        "sent_at": time.time(),
        "ticker": "XAUUSD",
        "bid": 2412.30,
        "ask": 2412.55,
        "event": "liquidity_sweep",
    }
    payload.update(overrides)
    return payload


class WebhookTransportTest(unittest.TestCase):
    """Signature, replay and freshness — the hostile-input surface."""

    def setUp(self):
        self.registry = WebhookRegistry()
        self.hook = self.registry.create("tv", normalize_tradingview, secret=SECRET)

    def test_valid_payload_is_accepted(self):
        raw, sig = signed(valid_payload())
        snap, decision = self.hook.receive(raw, sig)
        self.assertEqual(decision.verdict, Verdict.PROCEED)
        self.assertEqual(snap.mapped_symbol, "XAUUSD")

    def test_unsigned_payload_is_refused(self):
        raw, _ = signed(valid_payload())
        _, decision = self.hook.receive(raw, None)
        self.assertEqual(decision.verdict, Verdict.BLOCKED)

    def test_wrong_signature_is_refused(self):
        raw, sig = signed(valid_payload(), secret="wrong-secret")
        _, decision = self.hook.receive(raw, sig)
        self.assertEqual(decision.verdict, Verdict.BLOCKED)
        self.assertIn("signature", decision.reason)

    def test_replayed_request_id_is_refused(self):
        payload = valid_payload()
        raw, sig = signed(payload)
        _, first = self.hook.receive(raw, sig)
        _, second = self.hook.receive(raw, sig)
        self.assertEqual(first.verdict, Verdict.PROCEED)
        self.assertEqual(second.verdict, Verdict.BLOCKED)
        self.assertIn("replay", second.reason)

    def test_stale_payload_is_refused(self):
        raw, sig = signed(valid_payload(sent_at=time.time() - 300))
        _, decision = self.hook.receive(raw, sig)
        self.assertEqual(decision.verdict, Verdict.BLOCKED)
        self.assertIn("old", decision.reason)

    def test_future_timestamp_is_refused(self):
        raw, sig = signed(valid_payload(sent_at=time.time() + 600))
        _, decision = self.hook.receive(raw, sig)
        self.assertEqual(decision.verdict, Verdict.BLOCKED)

    def test_missing_replay_and_freshness_fields_are_refused(self):
        for missing in ("request_id", "sent_at"):
            with self.subTest(missing=missing):
                payload = valid_payload()
                del payload[missing]
                raw, sig = signed(payload)
                _, decision = self.hook.receive(raw, sig)
                self.assertEqual(decision.verdict, Verdict.BLOCKED)

    def test_malformed_json_is_refused(self):
        raw = b"{not json"
        sig = hmac.new(SECRET.encode(), raw, hashlib.sha256).hexdigest()
        _, decision = self.hook.receive(raw, sig)
        self.assertEqual(decision.verdict, Verdict.BLOCKED)

    def test_webhook_path_is_unguessable(self):
        """Knowing the webhook's name must not reveal its URL."""
        self.assertNotEqual(self.hook.path, "/webhook/tv")
        self.assertGreater(len(self.hook.path), len("/webhook/tv/") + 15)

    def test_every_refusal_is_observable(self):
        """D-002: a silently dropped payload is indistinguishable from no traffic."""
        raw, _ = signed(valid_payload())
        _, decision = self.hook.receive(raw, None)
        self.assertTrue(decision.reason, "a refusal must state why")


class ContentValidityTest(unittest.TestCase):
    """Transport validity is NOT content validity. This was a real defect."""

    def setUp(self):
        self.registry = WebhookRegistry()
        self.hook = self.registry.create("tv", normalize_tradingview, secret=SECRET)

    def test_btcxau_is_declined_despite_valid_transport(self):
        raw, sig = signed(valid_payload(ticker="BTCXAU"))
        snap, decision = self.hook.receive(raw, sig)
        self.assertEqual(decision.verdict, Verdict.DECLINE)
        self.assertEqual(snap.quality, DataQuality.INVALID)
        self.assertIsNone(snap.mapped_symbol)

    def test_other_xau_crosses_are_declined(self):
        for ticker in ("ETHXAU", "SOLXAU"):
            with self.subTest(ticker=ticker):
                raw, sig = signed(valid_payload(ticker=ticker))
                _, decision = self.hook.receive(raw, sig)
                self.assertEqual(decision.verdict, Verdict.DECLINE)

    def test_implausible_quote_is_declined(self):
        raw, sig = signed(valid_payload(bid=2413.0, ask=2400.0))  # ask below bid
        snap, decision = self.hook.receive(raw, sig)
        self.assertEqual(decision.verdict, Verdict.DECLINE)
        self.assertEqual(snap.quality, DataQuality.INVALID)

    def test_unknown_instrument_is_never_guessed(self):
        raw, sig = signed(valid_payload(ticker="WHATEVER123"))
        snap, decision = self.hook.receive(raw, sig)
        self.assertEqual(decision.verdict, Verdict.DECLINE)
        self.assertIn("refusing to guess", snap.detail)


class PublishedStateTest(unittest.TestCase):
    """Only usable data reaches the read surface."""

    def test_only_tradable_snapshots_are_published(self):
        store = StateStore()
        registry = WebhookRegistry()
        hook = registry.create("tv", normalize_tradingview, secret=SECRET)

        for ticker in ("XAUUSD", "BTCXAU", "ETHXAU"):
            raw, sig = signed(valid_payload(ticker=ticker))
            snap, decision = hook.receive(raw, sig)
            store.put_decision(decision)
            if decision.verdict is Verdict.PROCEED:
                store.put_snapshot(snap)

        self.assertEqual(list(store.latest().keys()), ["XAUUSD"])
        # But every attempt is still recorded.
        self.assertEqual(len(store.decisions()), 3)


class InstrumentMappingTest(unittest.TestCase):
    def test_futures_codes_map_to_base_symbols(self):
        self.assertEqual(map_instrument("GC"), "XAUUSD")
        self.assertEqual(map_instrument("MGC"), "XAUUSD")
        self.assertEqual(map_instrument("ES"), "US500")
        self.assertEqual(map_instrument("NQ"), "US100")

    def test_gold_variants_map_via_resolver(self):
        for symbol in ("XAUUSD.pro", "XAUUSDm", "GOLD"):
            with self.subTest(symbol=symbol):
                self.assertEqual(map_instrument(symbol), "XAUUSD")

    def test_btcxau_never_maps(self):
        self.assertIsNone(map_instrument("BTCXAU"))


class ReadApiTest(unittest.TestCase):
    def test_auth_required_except_health_and_index(self):
        api = build_default_api(StateStore(), token="tok")
        self.assertFalse(api.get("/state").requires_auth is False)
        self.assertFalse(api.get("/health").requires_auth)
        self.assertFalse(api.get("/").requires_auth)

    def test_authorize_rejects_wrong_token(self):
        api = ApiRegistry(token="right")
        self.assertTrue(api.authorize("right"))
        self.assertFalse(api.authorize("wrong"))
        self.assertFalse(api.authorize(None))

    def test_api_surface_is_read_only(self):
        """D-001: nothing on this surface may alter trading state."""
        api = build_default_api(StateStore())
        for endpoint in api.describe():
            with self.subTest(path=endpoint["path"]):
                self.assertEqual(endpoint["method"], "GET")

    def test_no_write_or_order_path_exists(self):
        """Structural guard: the registry offers no way to create a side effect."""
        api = ApiRegistry()
        for forbidden in ("create_command", "create_write", "place_order", "submit"):
            self.assertFalse(
                hasattr(api, forbidden), f"ApiRegistry must not expose {forbidden}"
            )


if __name__ == "__main__":
    unittest.main()
