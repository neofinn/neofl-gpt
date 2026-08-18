#!/usr/bin/env python3
"""Start the NeoFL gateway.

    python3 python/run_gateway.py [--port 8787] [--token SECRET]

Prints the webhook URLs and their signing secrets on startup. Those secrets are
credentials: configure them in the sending provider, and never commit them.
"""

from __future__ import annotations

import argparse
import logging
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from neofl_gateway.api import StateStore, build_default_api
from neofl_gateway.bridge import Bridge, default_terminal_files
from neofl_gateway.store import Store
from neofl_gateway.normalizers import normalize_cme, normalize_tradingview
from neofl_gateway.server import make_server
from neofl_gateway.webhooks import WebhookRegistry


def main() -> int:
    parser = argparse.ArgumentParser(description="NeoFL data gateway")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--token", default=None,
                        help="bearer token for the read API; omit to disable auth (local only)")
    parser.add_argument("--db", default="neofl.db", help="SQLite path")
    parser.add_argument("--mt5-files", default=None,
                        help="MQL5/Files directory; auto-detected if omitted")
    parser.add_argument("--poll", type=float, default=2.0, help="bridge poll seconds")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    store = StateStore()
    db = Store(args.db)
    api = build_default_api(store, token=args.token)

    # --- MT5 bridge: read-only, one-way. See neofl_gateway/bridge.py.
    files = Path(args.mt5_files) if args.mt5_files else default_terminal_files()
    bridge = None
    if files and Path(files).is_dir():
        bridge = Bridge(Path(files), db)
        api.create("/mt5/health",
                   lambda q: dict(zip(("alive", "detail"), bridge.terminal_alive())),
                   description="Is the terminal writing telemetry?", requires_auth=False)
        api.create("/mt5/positions", lambda q: db.open_positions(),
                   description="Open positions from the latest MT5 snapshot.")
        api.create("/mt5/state", lambda q: db.latest_snapshot(),
                   description="Latest full MT5 state snapshot.")
        api.create("/mt5/events",
                   lambda q: db.recent_events(int(q.get("limit", 100)), q.get("engine")),
                   description="Engine decisions from MT5 (D-002). ?engine=Risk to filter.")
    api.create("/db/stats", lambda q: db.stats(), description="Persistence statistics.")

    webhooks = WebhookRegistry()
    tv = webhooks.create("tradingview", normalize_tradingview)
    cme = webhooks.create("cme", normalize_cme)

    base = f"http://{args.host}:{args.port}"
    print("=" * 68)
    print("  NeoFL Gateway")
    print("=" * 68)
    print(f"  read API      {base}/")
    print(f"  auth          {'Bearer token required' if args.token else 'DISABLED (local only)'}")
    print()
    print("  Webhooks — configure these in the sending provider:")
    for hook in (tv, cme):
        print(f"    {hook.name:<12} POST {base}{hook.path}")
        print(f"    {'':<12} secret: {hook.secret}")
    print()
    print("  Every payload must include request_id and sent_at, and be signed:")
    print("    X-NeoFL-Signature: hex(hmac_sha256(secret, raw_body))")
    print()
    print("  This surface is READ-ONLY and cannot place orders (decision D-001).")
    print("=" * 68)

    if bridge:
        def pump():
            while True:
                try:
                    r = bridge.poll_once()
                    if r["events"] or r["snapshot"]:
                        logging.info("bridge: +%d events, snapshot=%s",
                                     r["events"], r["snapshot"])
                except Exception:
                    logging.exception("bridge poll failed")   # never kill the thread
                time.sleep(args.poll)
        threading.Thread(target=pump, daemon=True).start()
        print(f"  MT5 bridge    watching {Path(files) / 'NeoFL'}")
        print(f"  database      {args.db}")
    else:
        print("  MT5 bridge    NOT FOUND - pass --mt5-files <MQL5/Files path>")
    server = make_server(api, webhooks, store, host=args.host, port=args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
        server.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
