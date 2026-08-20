import os
from datetime import datetime, timezone
from collections import deque
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="NeoFL Gateway", version="1.0.0")
TOKEN = os.getenv("NEOFL_GATEWAY_TOKEN", "")
queue = deque()
accounts = {}
telemetry_store = {}


def auth(token: str | None):
    if TOKEN and token != TOKEN:
        raise HTTPException(401, "invalid gateway token")

class Handshake(BaseModel):
    account_number: int
    server: str
    connector: str = "MT5"
    environment: str = "DEMO"
    binding_token: str | None = None

class Telemetry(BaseModel):
    account_number: int
    server: str
    connector: str = "MT5"
    environment: str = "DEMO"
    payload: dict = Field(default_factory=dict)

class ExecutionReport(BaseModel):
    intent_id: str
    account_number: int
    symbol: str
    status: str
    payload: dict = Field(default_factory=dict)

@app.get("/health")
def health():
    return {"status":"ok","service":"neofl-gateway","time":datetime.now(timezone.utc).isoformat()}

@app.post("/api/handshake")
def handshake(body: Handshake, x_neofl_binding_token: str | None = Header(default=None)):
    auth(x_neofl_binding_token or body.binding_token)
    key=f"{body.account_number}:{body.server}"
    accounts[key]={**body.model_dump(exclude={"binding_token"}),"last_seen":datetime.now(timezone.utc).isoformat()}
    return {"status":"CONNECTED","authenticated":True,"account":body.account_number,"server":body.server}

@app.post("/api/heartbeat")
def heartbeat(body: Handshake, x_neofl_binding_token: str | None = Header(default=None)):
    auth(x_neofl_binding_token or body.binding_token)
    key=f"{body.account_number}:{body.server}"
    accounts.setdefault(key,{})["last_seen"]=datetime.now(timezone.utc).isoformat()
    return {"status":"HEALTHY","account":body.account_number,"server":body.server}

@app.post("/api/telemetry")
def telemetry_route(body: Telemetry, x_neofl_binding_token: str | None = Header(default=None)):
    auth(x_neofl_binding_token)
    key=f"{body.account_number}:{body.server}"
    telemetry_store[key]=body.model_dump()
    accounts.setdefault(key,{})["last_seen"]=datetime.now(timezone.utc).isoformat()
    return {"status":"ACCEPTED"}

@app.post("/api/v1/order-intents")
def create_intent(body: dict, x_neofl_binding_token: str | None = Header(default=None)):
    auth(x_neofl_binding_token)
    queue.append(body)
    return {"status":"QUEUED","intent_id":body.get("id") or body.get("intent_id")}

@app.get("/api/v1/execution/next")
def next_execution(account_number: int, server: str, x_neofl_binding_token: str | None = Header(default=None)):
    auth(x_neofl_binding_token)
    if not queue:
        return {"intent":None}
    return {"intent":queue.popleft()}

@app.post("/api/v1/execution-report")
def execution_report(body: ExecutionReport, x_neofl_binding_token: str | None = Header(default=None)):
    auth(x_neofl_binding_token)
    return {"status":"ACCEPTED","intent_id":body.intent_id}

@app.get("/api/v1/accounts/{account_id}")
def account_state(account_id: str, x_neofl_binding_token: str | None = Header(default=None)):
    auth(x_neofl_binding_token)
    matches={k:v for k,v in accounts.items() if k.startswith(account_id+":")}
    return {"accounts":matches}
