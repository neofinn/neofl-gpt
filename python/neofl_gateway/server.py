"""NeoFL gateway HTTP transport with account Brain routing and MT5 telemetry."""
from __future__ import annotations
import json, logging, os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from .agent import AgentLoop, AgentRequest
from .agent_runtime import NeoFLAgentRuntime
from .api import ApiRegistry, StateStore
from .body import NeoFLBody
from .brain_registry import BrainDeployment, BrainRegistry
from .mcp_client import MCPClient
from .telemetry import TelemetryRegistry
from .webhooks import WebhookRegistry

log = logging.getLogger("neofl.gateway")
MAX_BODY_BYTES = 256 * 1024

class GatewayHandler(BaseHTTPRequestHandler):
    server_version = "NeoFL-Gateway/1.6"
    api: ApiRegistry; webhooks: WebhookRegistry; store: StateStore; agent: AgentLoop; body: NeoFLBody; runtime: NeoFLAgentRuntime
    brains: BrainRegistry; telemetry: TelemetryRegistry

    def log_message(self, fmt: str, *args) -> None: log.info("%s - %s", self.address_string(), fmt % args)
    def _send(self, status: int, payload) -> None:
        body = json.dumps(payload, default=str).encode(); self.send_response(status); self.send_header("Content-Type","application/json"); self.send_header("Content-Length",str(len(body))); self.send_header("X-Content-Type-Options","nosniff"); self.end_headers(); self.wfile.write(body)
    def _error(self, status: int, message: str) -> None: self._send(status, {"error": message})
    def _auth(self) -> bool:
        token=self.headers.get("Authorization",""); token=token[7:] if token.startswith("Bearer ") else token; return self.api.authorize(token)
    def _json(self):
        try: length=int(self.headers.get("Content-Length","0"))
        except ValueError: raise ValueError("bad request")
        if length<=0 or length>MAX_BODY_BYTES: raise ValueError("payload size not accepted")
        return json.loads(self.rfile.read(length).decode())

    def do_GET(self) -> None:
        path=urlparse(self.path).path
        if path in {"/admin/brains","/admin/accounts"}:
            if not self._auth(): self.send_response(401); self.end_headers(); return
            self._send(200, self.brains.snapshot() if path.endswith("brains") else self.telemetry.snapshot()); return
        if path == "/admin/brain-routing":
            if not self._auth(): self.send_response(401); self.end_headers(); return
            self._send(200, self.brains.snapshot()); return
        if path == "/mt5/status":
            if not self._auth(): self.send_response(401); self.end_headers(); return
            self._send(200,{"accounts":self.telemetry.snapshot(),"brains":self.brains.snapshot()}); return
        if path == "/agent/runtime/status":
            if not self._auth(): self.send_response(401); self.end_headers(); return
            self._send(200,self.runtime.introspect()); return
        endpoint=self.api.get(path)
        if endpoint is None: self._error(404,"not found"); return
        if endpoint.requires_auth and not self._auth(): self.send_response(401); self.end_headers(); return
        query={k:v[0] for k,v in parse_qs(urlparse(self.path).query).items()}
        try: self._send(200,endpoint.invoke(query))
        except Exception: log.exception("endpoint failed"); self._error(500,"endpoint error")

    def do_POST(self) -> None:
        path=urlparse(self.path).path
        try: payload=self._json()
        except (ValueError, json.JSONDecodeError) as exc: self._error(400,str(exc)); return

        if path == "/admin/brain/global-switch":
            if not self._auth(): self.send_response(401); self.end_headers(); return
            try:
                deployment=str(payload["brain"] or payload["deployment"])
                resolved=self.brains.set_default(deployment)
                self._send(200,{"global":deployment,"deployment":resolved.__dict__,"routing":self.brains.snapshot()})
            except (KeyError,ValueError) as exc: self._error(400,str(exc))
            return

        if path in {"/admin/brain/switch","/admin/brain/assign"}:
            if not self._auth(): self.send_response(401); self.end_headers(); return
            try:
                account=str(payload["account_id"]); deployment=str(payload["brain"] or payload["deployment"])
                binding=self.brains.assign(account,deployment); resolved=self.brains.resolve(account)
                state=self.telemetry.heartbeat({"account_id":account,"brain":deployment}, {"name":resolved.name,"branch":resolved.branch,"build":resolved.build,"endpoint":resolved.endpoint})
                self._send(200,{"binding":binding.__dict__,"deployment":resolved.__dict__,"account":state})
            except (KeyError,ValueError) as exc: self._error(400,str(exc))
            return

        if path == "/admin/brain/use-global":
            if not self._auth(): self.send_response(401); self.end_headers(); return
            try:
                account=str(payload["account_id"]); self.brains.clear_assignment(account); resolved=self.brains.resolve(account)
                self._send(200,{"account_id":account,"routing":"GLOBAL","deployment":resolved.__dict__})
            except (KeyError,ValueError) as exc: self._error(400,str(exc))
            return

        if path == "/mt5/report":
            try:
                account=str(payload.get("account_id","")); deployment=self.brains.resolve(account)
                state=self.telemetry.heartbeat(payload, deployment.__dict__ if deployment else None)
                self._send(200,{"status":"CONNECTED","account":account,"brain":deployment.name if deployment else None,"branch":deployment.branch if deployment else None,"build":deployment.build if deployment else None,"mcp":state.get("mcp",{"status":"UNKNOWN"})})
            except ValueError as exc: self._error(400,str(exc))
            return

        if path == "/mt5/execution-report":
            try:
                account=str(payload.get("account_id","")); deployment=self.brains.resolve(account); state=self.telemetry.execution(payload)
                self._send(200,{"accepted":True,"account":account,"brain":deployment.name if deployment else None,"branch":deployment.branch if deployment else None,"build":deployment.build if deployment else None,"execution":state.get("last_execution_event")})
            except ValueError as exc: self._error(400,str(exc))
            return

        if path == "/admin/mcp/status":
            if not self._auth(): self.send_response(401); self.end_headers(); return
            account=str(payload.get("account_id","")); self.telemetry.set_mcp(account_id=account,status=str(payload.get("status","UNKNOWN")),endpoint=payload.get("endpoint"),tools=payload.get("tools")); self._send(200,{"ok":True,"account":account}); return

        if path == "/agent/runtime/cycle":
            if not self._auth(): self.send_response(401); self.end_headers(); return
            request=AgentRequest(text=str(payload.get("text","")),symbol=payload.get("symbol"),mode=str(payload.get("mode","analyze")),request_id=payload.get("request_id"),context=payload.get("context") or {})
            try: response=self.runtime.cycle(request,pull_mcp=bool(payload.get("pull_mcp",True))); self._send(200,{"runtime":self.runtime.introspect(),"response":self.agent.to_dict(response)})
            except Exception: log.exception("runtime cycle failed"); self._error(502,"agent runtime cycle failed")
            return

        if path == "/input":
            if not self._auth(): self.send_response(401); self.end_headers(); return
            try:
                request=AgentRequest(text=str(payload.get("text","")),symbol=payload.get("symbol"),mode=str(payload.get("mode","analyze")),request_id=payload.get("request_id"),context=payload.get("context") or {})
                action=self.body.think(request); self._send(200 if action.allowed else 409,action.response)
            except Exception: log.exception("agent request failed"); self._error(500,"agent error")
            return

        hook=self.webhooks.by_path(path)
        if hook is None: self._error(404,"not found"); return
        signature=self.headers.get("X-NeoFL-Signature"); snapshot,decision=hook.receive(json.dumps(payload).encode(),signature)
        if decision.verdict.value=="BLOCKED": self._error(400,"payload refused"); return
        action=self.body.receive_external_event(source=f"webhook:{hook.name}",symbol=snapshot.mapped_symbol,payload=snapshot.to_dict(),quality=snapshot.quality.value)
        self._send(200,{"accepted":action.allowed,"symbol":snapshot.mapped_symbol,"soul":action.response})

def _mcp_client_from_environment():
    url=os.getenv("NEOFL_MARKETDATA_MCP_URL") or os.getenv("NEOFL_MCP_URL"); token=os.getenv("NEOFL_MARKETDATA_MCP_TOKEN") or os.getenv("NEOFL_MCP_TOKEN")
    return MCPClient(url=url,token=token) if url else None

def make_server(api,webhooks,store,agent,host="127.0.0.1",port=8787):
    body=NeoFLBody(agent,store); runtime=NeoFLAgentRuntime(agent,_mcp_client_from_environment())
    brains=BrainRegistry([BrainDeployment("MAIN","main",os.getenv("NEOFL_MAIN_BUILD","unknown"),os.getenv("NEOFL_MAIN_BRAIN_URL","")),BrainDeployment("PARALLEL","neoflgpt-parallel",os.getenv("NEOFL_PARALLEL_BUILD","unknown"),os.getenv("NEOFL_PARALLEL_BRAIN_URL", ""))], default=os.getenv("NEOFL_DEFAULT_BRAIN","MAIN"))
    telemetry=TelemetryRegistry()
    handler=type("BoundGatewayHandler",(GatewayHandler,),{"api":api,"webhooks":webhooks,"store":store,"agent":agent,"body":body,"runtime":runtime,"brains":brains,"telemetry":telemetry})
    return ThreadingHTTPServer((host,port),handler)
