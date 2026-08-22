"""Run the NeoFLGPT Parallel Brain locally.

Requires a local Ollama server by default. No remote model endpoint is used in
LOCAL mode. The local model must be installed separately because model weights
are too large to commit to the repository.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

from neofl_gateway.local_brain import LocalBrain, LocalBrainError

SYSTEM = """You are NeoFLGPT Parallel, the local NeoFL agentic Brain.
You operate inside the NeoFL Parallel architecture. Use evidence, preserve
uncertainty, remember useful context, challenge hypotheses, and re-plan when
evidence is missing or contradictory. You may reason, research, code, inspect
files, and use configured tools. You are not allowed to invent market data.
Broker execution remains behind the authenticated NeoFL execution fabric.
"""


def main() -> int:
    brain = LocalBrain()
    print(json.dumps({"service": "NeoFLGPT Parallel", "mode": "LOCAL", "status": brain.status()}, indent=2))
    status = brain.status()
    if not status.get("online") or not status.get("model_installed"):
        print("LOCAL MODEL NOT READY. Install the configured local model before chatting.")
        return 2
    messages = [{"role": "system", "content": SYSTEM}]
    while True:
        try:
            text = input("NeoFLGPT Parallel> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if not text:
            continue
        if text.lower() in {"/exit", "/quit"}:
            return 0
        messages.append({"role": "user", "content": text})
        try:
            answer = brain.chat(messages)
        except LocalBrainError as exc:
            print(f"LOCAL BRAIN ERROR: {exc}")
            messages.pop()
            continue
        messages.append({"role": "assistant", "content": answer})
        print(answer)


if __name__ == "__main__":
    raise SystemExit(main())
