# Data Gateway — input and output interfaces

The gateway is how data enters and leaves NeoFL. It is the transport that makes D-002
possible: an AI cannot observe the feed or verify engines without somewhere to read from.

Standard library only — it runs with no install. Transport is separated from logic, so
FastAPI can replace `server.py` later without touching the registries.

## Run it

```bash
python3 python/run_gateway.py --port 8787 --token YOUR_TOKEN
```

Startup prints each webhook URL and its signing secret. Those are credentials: configure
them in the sending provider, keep them out of Git.

## Input — webhooks

`WebhookRegistry.create(name, normalizer)` mints an endpoint and returns everything the
provider needs. Paths carry a random component, so knowing a webhook's name does not
reveal its URL.

Every payload must carry `request_id` and `sent_at`, and be signed:

```
X-NeoFL-Signature: hex(hmac_sha256(secret, raw_body))
```

Refusals, in order:

| Check | Why |
|---|---|
| HMAC signature | forged payloads. Constant-time compare — `==` leaks the correct prefix through timing |
| `request_id` replay | anyone who saw a payload once can resend it |
| `sent_at` freshness | a stale alert acted on late is worse than no alert |
| future timestamp | clock skew or forgery |
| JSON shape | providers change format without notice |
| body size | 256 KB ceiling |

## Transport validity is not content validity

The distinction that caused a real defect during development:

A payload can pass **every** transport check — correctly signed, fresh, never replayed,
valid JSON — and still carry `BTCXAU`. Nothing in the transport layer objects, because
nothing in the transport layer looks at meaning. It landed in published state despite
the gold-only rule.

So normalization produces a quality verdict, and only `tradable` snapshots are published:

```
signed + fresh + unique  ->  transport OK
    -> normalize -> DATA_INVALID (BTCXAU does not map)
    -> verdict DECLINE -> recorded, NOT published
```

`DECLINE` returns HTTP 200, not 400 — the sender did nothing wrong at transport level,
and a 400 would make the provider retry a payload that can never become valid.

## Output — read API

| Endpoint | Auth | Purpose |
|---|---|---|
| `/` | no | endpoint index |
| `/health` | no | liveness |
| `/state` | yes | latest normalized snapshot per symbol |
| `/events` | yes | recent market events |
| `/decisions` | yes | engine decisions with inputs and reasons (D-002) |

`/decisions` is the endpoint that serves D-002 directly — it is where an AI observer
reads how each component reasoned, including everything it declined and why.

## D-001 is structural, not documentary

`ApiRegistry` has no way to express a side effect. Handlers receive a request and return
data; there is no order path, no write path, no command surface. Adding one would mean
editing `api.py`, not slipping a call into a handler. A test asserts the registry exposes
no `create_command`, `place_order`, or similar.

## Common schema

Every source normalizes to `MarketSnapshot`, so strategies never see provider-specific
shapes. The quality states mirror `NeoFL_DataQuality.mqh` exactly — both sides of the
bridge must agree on what `DELAYED` means.

`None` means "this source does not provide it"; `0.0` means "measured as zero". Conflating
them is how fabricated data reaches a strategy — a missing depth side read as 0 would
manufacture an order-book imbalance that never existed.

## Not implemented here, deliberately

TLS and rate limiting belong in a reverse proxy in front of this process. Implementing
half-versions here would give a false sense of safety. The gateway binds to localhost by
default; anything public-facing needs that proxy first.
