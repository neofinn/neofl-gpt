#!/usr/bin/env python3
"""Start the NeoFL gateway and Agentic Soul."""
from __future__ import annotations

import argparse
import logging
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from neofl_gateway.agent import AgentLoop, sqlite_snapshot_observations
from neofl_gateway.agentic import AgenticSoul
from neofl_gateway.api import StateStore, build_default_api
from neofl_gateway.bridge import Bridge, default_terminal_files
from neofl_gateway.llm_reasoner import OpenAIReasoner
from neofl_gateway.normalizers import normalize_cme, normalize_tradingview
from neofl_gateway.server import make_server
from neofl_gateway.store import Store
from neofl_gateway.supabase_memory import SupabaseMemory
from neofl_gateway.webhooks import WebhookRegistry


def main() -> int:
    parser = argparse.ArgumentParser(description="NeoFL data and agentic AI gateway")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--token", default=None, help="Bearer token; omit only for local development")
    parser.add_argument("--db", default="neofl.db", help="SQLite path")
    parser.add_argument("--mt5-files", default=None, help="MQL5/Files directory; auto-detected if omitted")
    parser.add_argument("--poll", type=float, default=2.0, help="MT5 bridge poll seconds")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    memory = SupabaseMemory()
    store = StateStore(memory=memory)
    db = Store(args.db)
    api = build_default_api(store, token=args.token)

    reasoner = OpenAIReasoner()
    soul = AgenticSoul(reasoner=reasoner)
    agent = AgentLoop(
        soul=soul,
        context_provider=lambda symbol: sqlite_snapshot_observations(db.latest_snapshot(), symbol),
    )
    api.create(
        "/agent/status",
        lambda q: {
            "agentic": True,
            "reasoner": "openai-responses" if reasoner.enabled else "deterministic-fallback",
            "model": reasoner.model if reasoner.enabled else None,
            "tools": soul.tools.names(),
            "execution_authorized": False,
            "perception": "MT5 SQLite bridge snapshot",
        },
        description="Agentic Soul state, perception and reasoning provider.",
    )
    api.create("/memory/health", lambda q: memory.status(), description="Durable Supabase memory status.", requires_auth=False)

    files = Path(args.mt5_files) if args.mt5_files else default_terminal_files()
    bridge = None
    if files and Path(files).is_dir():
        bridge = Bridge(Path(files), db)
        api.create("/mt5/health", lambda q: dict(zip(("alive", "detail"), bridge.terminal_alive())),
                   description="Is the terminal writing telemetry?", requires_auth=False)
        api.create("/mt5/positions", lambda q: db.open_positions(), description="Open positions from latest MT5 snapshot.")
        api.create("/mt5/state", lambda q: db.latest_snapshot(), description="Latest full MT5 state snapshot.")
        api.create("/mt5/events", lambda q: db.recent_events(int(q.get("limit", 100)), q.get("engine")),
                   description="Engine decisions from MT5.")
    api.create("/db/stats", lambda q: db.stats(), description="Local bridge persistence statistics.")

    webhooks = WebhookRegistry()
    tv = webhooks.create("tradingview", normalize_tradingview)
    cme = webhooks.create("cme", normalize_cme)

    base = f"http://{args.host}:{args.port}"
    print("=" * 72)
    print("  NeoFL Gateway + Agentic Soul")
    print("=" * 72)
    print(f"  read API      {base}/")
    print(f"  agent input   POST {base}/input")
    print(f"  agent status  {base}/agent/status")
    print(f"  auth          {'Bearer token required' if args.token else 'DISABLED (local only)'}")
    print(f"  persistence   {'SUPABASE enabled' if memory.enabled else 'local only (configure NEOFL_SUPABASE_URL + service key)'}")
    print(f"  reasoner      {'OpenAI ' + reasoner.model if reasoner.enabled else 'deterministic fail-closed fallback'}")
    print("  perception    MT5 latest snapshot via SQLite bridge")
    print("  execution     DISABLED — Agentic Soul is recommendation-only")
    print()
    print("  Webhooks:")
    for hook in (tv, cme):
        print(f"    {hook.name:<12} POST {base}{hook.path}")
    print("=" * 72)

    if bridge:
        def pump():
            while True:
                try:
                    r = bridge.poll_once()
                    if r["events"] or r["snapshot"]:
                        logging.info("bridge: +%d events, snapshot=%s", r["events"], r["snapshot"])
                except Exception:
                    logging.exception("bridge poll failed")
                time.sleep(args.poll)
        threading.Thread(target=pump, daemon=True).start()
        print(f"  MT5 bridge    watching {Path(files) / 'NeoFL'}")
        print(f"  database      {args.db}")
    else:
        print("  MT5 bridge    NOT FOUND - pass --mt5-files <MQL5/Files path>")

    server = make_server(api, webhooks, store, agent, host=args.host, port=args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
        server.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
