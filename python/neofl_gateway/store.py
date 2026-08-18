"""Persistence — SQLite.

Canon names PostgreSQL and Redis eventually. This is SQLite because it needs no server,
no install, and no credentials, so the system can actually run today rather than after an
infrastructure project. The schema and the access layer are what matter; the engine behind
them can change once there is something worth scaling.

Every table carries the raw payload alongside parsed columns. Parsing is a guess about
what mattered; the raw row is the evidence. When a parse turns out to be wrong, history
can be re-derived instead of being lost.
"""

from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Any, Iterable

SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    ts        REAL    NOT NULL,          -- when the engine emitted it
    received  REAL    NOT NULL,          -- when we stored it; the gap is bridge latency
    engine    TEXT    NOT NULL,
    symbol    TEXT,
    kind      TEXT    NOT NULL,
    detail    TEXT,
    value     REAL,
    raw       TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_ts     ON events(ts);
CREATE INDEX IF NOT EXISTS idx_events_engine ON events(engine, kind);

CREATE TABLE IF NOT EXISTS snapshots (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    ts        REAL    NOT NULL,
    received  REAL    NOT NULL,
    symbol    TEXT,
    balance   REAL,
    equity    REAL,
    bid       REAL,
    ask       REAL,
    positions INTEGER,
    raw       TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_snapshots_ts ON snapshots(ts);

CREATE TABLE IF NOT EXISTS positions (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    ts        REAL    NOT NULL,
    ticket    INTEGER NOT NULL,
    symbol    TEXT,
    type      TEXT,
    volume    REAL,
    open_px   REAL,
    sl        REAL,
    tp        REAL,
    profit    REAL,
    swap      REAL,
    comment   TEXT
);
CREATE INDEX IF NOT EXISTS idx_positions_ticket ON positions(ticket, ts);

CREATE TABLE IF NOT EXISTS market (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    ts        REAL    NOT NULL,
    received  REAL    NOT NULL,
    source    TEXT    NOT NULL,
    symbol    TEXT,
    quality   TEXT,
    bid       REAL,
    ask       REAL,
    event     TEXT,
    raw       TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_market_ts ON market(ts, symbol);

-- Bridge progress, so a restart resumes instead of re-reading the whole log.
CREATE TABLE IF NOT EXISTS cursors (
    name   TEXT PRIMARY KEY,
    offset INTEGER NOT NULL,
    ts     REAL    NOT NULL
);
"""


class Store:
    def __init__(self, path: str | Path = "neofl.db") -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # check_same_thread=False: the HTTP server is threaded. Writes are serialised by
        # SQLite's own locking, and this workload is write-light.
        self.db = sqlite3.connect(str(self.path), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        # WAL lets the reader poll while the bridge writes without blocking either.
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)
        self.db.commit()

    # --- writes ---------------------------------------------------------------

    def add_event(self, ev: dict[str, Any]) -> None:
        self.db.execute(
            "INSERT INTO events (ts, received, engine, symbol, kind, detail, value, raw)"
            " VALUES (?,?,?,?,?,?,?,?)",
            (float(ev.get("ts", 0)) or time.time(), time.time(),
             ev.get("engine", "?"), ev.get("symbol"), ev.get("kind", "?"),
             ev.get("detail"), ev.get("value"), json.dumps(ev)),
        )
        self.db.commit()

    def add_snapshot(self, snap: dict[str, Any]) -> None:
        acct = snap.get("account", {}) or {}
        mkt = snap.get("market", {}) or {}
        pos = snap.get("positions", []) or []
        ts = float(snap.get("ts", 0)) or time.time()
        now = time.time()

        self.db.execute(
            "INSERT INTO snapshots (ts, received, symbol, balance, equity, bid, ask,"
            " positions, raw) VALUES (?,?,?,?,?,?,?,?,?)",
            (ts, now, snap.get("symbol"), acct.get("balance"), acct.get("equity"),
             mkt.get("bid"), mkt.get("ask"), len(pos), json.dumps(snap)),
        )
        for p in pos:
            self.db.execute(
                "INSERT INTO positions (ts, ticket, symbol, type, volume, open_px, sl,"
                " tp, profit, swap, comment) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (ts, p.get("ticket", 0), snap.get("symbol"), p.get("type"),
                 p.get("volume"), p.get("open"), p.get("sl"), p.get("tp"),
                 p.get("profit"), p.get("swap"), p.get("comment")),
            )
        self.db.commit()

    def add_market(self, snapshot) -> None:
        """Store a normalized MarketSnapshot from the gateway."""
        d = snapshot.to_dict()
        self.db.execute(
            "INSERT INTO market (ts, received, source, symbol, quality, bid, ask, event, raw)"
            " VALUES (?,?,?,?,?,?,?,?,?)",
            (d.get("timestamp"), time.time(), d.get("source"),
             d.get("mapped_symbol") or d.get("instrument"), d.get("quality"),
             d.get("bid"), d.get("ask"), d.get("event"), json.dumps(d, default=str)),
        )
        self.db.commit()

    # --- cursors --------------------------------------------------------------

    def get_cursor(self, name: str) -> int:
        row = self.db.execute("SELECT offset FROM cursors WHERE name=?", (name,)).fetchone()
        return int(row["offset"]) if row else 0

    def set_cursor(self, name: str, offset: int) -> None:
        self.db.execute(
            "INSERT INTO cursors (name, offset, ts) VALUES (?,?,?)"
            " ON CONFLICT(name) DO UPDATE SET offset=excluded.offset, ts=excluded.ts",
            (name, offset, time.time()),
        )
        self.db.commit()

    # --- reads ----------------------------------------------------------------

    def recent_events(self, limit: int = 100, engine: str | None = None) -> list[dict]:
        if engine:
            rows = self.db.execute(
                "SELECT * FROM events WHERE engine=? ORDER BY id DESC LIMIT ?",
                (engine, limit)).fetchall()
        else:
            rows = self.db.execute(
                "SELECT * FROM events ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        return [dict(r) for r in rows]

    def latest_snapshot(self) -> dict | None:
        row = self.db.execute(
            "SELECT * FROM snapshots ORDER BY id DESC LIMIT 1").fetchone()
        return dict(row) if row else None

    def open_positions(self) -> list[dict]:
        """Positions from the most recent snapshot only — older rows are history."""
        snap = self.db.execute(
            "SELECT ts FROM snapshots ORDER BY id DESC LIMIT 1").fetchone()
        if not snap:
            return []
        rows = self.db.execute(
            "SELECT * FROM positions WHERE ts=? ORDER BY ticket", (snap["ts"],)).fetchall()
        return [dict(r) for r in rows]

    def stats(self) -> dict[str, Any]:
        def count(table: str) -> int:
            return self.db.execute(f"SELECT COUNT(*) c FROM {table}").fetchone()["c"]
        return {
            "events": count("events"),
            "snapshots": count("snapshots"),
            "positions": count("positions"),
            "market": count("market"),
            "db_path": str(self.path),
            "db_bytes": self.path.stat().st_size if self.path.exists() else 0,
        }

    def close(self) -> None:
        self.db.close()
