"""The MT5 -> Python bridge.

Reads what the terminal writes into its MQL5/Files sandbox and feeds it to the store and
the gateway. This is the piece that turns two programs into one system: without it the EA
knows its own state and nothing outside can see it, which makes D-002 impossible — an AI
cannot verify engines process data correctly if their processing never leaves the terminal.

STRICTLY ONE-WAY
This module reads. It has no write path into the terminal, and must never gain one. The
EA's telemetry writer has no read path either, so the channel is physically incapable of
carrying instructions inward — that is how D-001 is enforced here, by shape rather than by
policy.

WHY POLLING FILES
MT5 cannot push. WebRequest needs per-URL allow-listing by hand and blocks the calling
thread, which is a poor trade on the tick path. Files need no permission, and — the real
advantage — they persist: if this process is down for an hour, the events are still on
disk and get picked up on restart rather than lost.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Callable

from .store import Store


def default_terminal_files() -> Path | None:
    """Locate the MQL5/Files sandbox on this machine.

    Returns None rather than guessing when it cannot be found — a bridge silently
    watching the wrong directory looks identical to a terminal that is not running.
    """
    base = Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5"
    candidate = base / "drive_c/Program Files/MetaTrader 5/MQL5/Files"
    return candidate if candidate.is_dir() else None


class Bridge:
    """Tails the terminal's telemetry files into the store."""

    def __init__(
        self,
        files_dir: Path,
        store: Store,
        *,
        on_event: Callable[[dict], None] | None = None,
        on_snapshot: Callable[[dict], None] | None = None,
    ) -> None:
        self.dir = Path(files_dir) / "NeoFL"
        self.store = store
        self.on_event = on_event
        self.on_snapshot = on_snapshot
        self._last_state_mtime = 0.0

    # --- events (append-only JSONL) -------------------------------------------

    def poll_events(self) -> int:
        """Read new lines since the stored cursor. Returns how many were ingested.

        The cursor is a byte offset held in the database, so a restart resumes exactly
        where it stopped rather than replaying the whole log or skipping the gap.
        """
        path = self.dir / "events.jsonl"
        if not path.is_file():
            return 0

        offset = self.store.get_cursor("events.jsonl")
        size = path.stat().st_size

        if size < offset:
            # File shrank: the terminal rotated or cleared it. Start over rather than
            # seeking past the end and silently reading nothing forever.
            offset = 0

        if size == offset:
            return 0

        ingested = 0
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            fh.seek(offset)
            # readline() rather than `for line in fh`: iteration enables a read-ahead
            # buffer and Python then refuses tell(), and the byte offset is the whole
            # point of the cursor.
            while True:
                line = fh.readline()
                if not line:
                    break
                if not line.endswith("\n"):
                    # Partial final line — the EA is mid-write. Leave the cursor before
                    # it so it is read whole on the next pass.
                    break
                offset = fh.tell()
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue          # skip the bad line; do not stall the bridge
                self.store.add_event(ev)
                if self.on_event:
                    self.on_event(ev)
                ingested += 1

        self.store.set_cursor("events.jsonl", offset)
        return ingested

    # --- state (whole-file snapshot) ------------------------------------------

    def poll_state(self) -> bool:
        """Ingest the state snapshot if it changed. Returns True when one was stored."""
        path = self.dir / "state.json"
        if not path.is_file():
            return False

        mtime = path.stat().st_mtime
        if mtime <= self._last_state_mtime:
            return False

        try:
            snap = json.loads(path.read_text(encoding="utf-8", errors="replace"))
        except json.JSONDecodeError:
            # The EA writes to a temp file and renames, so this should not happen. If it
            # does, leave the mtime unadvanced and retry next pass rather than skipping.
            return False

        self._last_state_mtime = mtime
        self.store.add_snapshot(snap)
        if self.on_snapshot:
            self.on_snapshot(snap)
        return True

    # --- health ---------------------------------------------------------------

    def terminal_alive(self, max_age_seconds: float = 60.0) -> tuple[bool, str]:
        """Is the terminal actually writing?

        D-002: absence must be observable. A bridge finding no new data cannot tell the
        difference between a quiet market and a dead terminal unless it checks freshness
        explicitly — so it checks, and says which.
        """
        path = self.dir / "state.json"
        if not path.is_file():
            return False, f"no telemetry at {path}; is the EA attached and running?"
        age = time.time() - path.stat().st_mtime
        if age > max_age_seconds:
            return False, f"telemetry {age:.0f}s stale (limit {max_age_seconds:.0f}s)"
        return True, f"telemetry fresh ({age:.0f}s old)"

    def poll_once(self) -> dict:
        events = self.poll_events()
        state = self.poll_state()
        alive, detail = self.terminal_alive()
        return {"events": events, "snapshot": state, "alive": alive, "detail": detail}
