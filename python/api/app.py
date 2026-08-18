"""NeoFL gateway application.

The framework is intentionally optional at import time so the Python brain remains
usable without a web server dependency. Install FastAPI/uvicorn for HTTP service.
"""
from __future__ import annotations

import uuid

from .schemas import AnalyzeRequest, AnalyzeResponse


def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    """Initial gateway contract; specialist orchestration plugs in here."""
    return AnalyzeResponse(
        request_id=str(uuid.uuid4()),
        instrument=request.instrument,
        state="RESEARCH_PENDING",
        thesis=None,
        confidence=None,
        evidence={"task": request.task, "mode": request.mode, "timeframes": request.timeframes},
    )


def create_app():
    try:
        from fastapi import FastAPI
    except ImportError as exc:
        raise RuntimeError("Install fastapi and uvicorn to run the NeoFL HTTP gateway") from exc

    app = FastAPI(title="NeoFL Gateway", version="0.1.0")

    @app.get("/api/v1/health")
    def health():
        return {"status": "ok", "service": "neofl-gateway"}

    @app.post("/api/v1/analyze", response_model=None)
    def analyze_endpoint(payload: dict):
        request = AnalyzeRequest(
            instrument=str(payload["instrument"]),
            task=str(payload.get("task", "analyze")),
            mode=str(payload.get("mode", "research")),
            timeframes=tuple(payload.get("timeframes", ())),
            context=dict(payload.get("context", {})),
        )
        return analyze(request).__dict__

    return app
