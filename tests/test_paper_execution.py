import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

from neofl_gateway.agent import AgentLoop
from neofl_gateway.body import NeoFLBody
from neofl_gateway.execution import ExecutionAuthority


class Store:
    def __init__(self):
        self.requests = []
        self.decisions = []
    def put_request(self, value): self.requests.append(value)
    def put_decision(self, value): self.decisions.append(value)


class PaperExecutionTest(unittest.TestCase):
    def test_soul_gates_paper_trade_and_tracks_pnl(self):
        body = NeoFLBody(AgentLoop(), Store(), ExecutionAuthority())
        evidence = {"observations": [{"source": "paper_feed", "claim": "market_state", "value": {"price": 100.0}, "quality": "OK", "confidence": 0.95, "evidence": ["synthetic paper market"]}]}
        opened = body.paper_trade(text="Evaluate this paper BUY setup using the supplied market evidence.", symbol="XAUUSD", account="PAPER-001", side="BUY", quantity=1.0, mark=100.0, context=evidence)
        self.assertTrue(opened.allowed)
        trade_id = opened.response["execution"]["trade"]["trade_id"]
        marked = body.execution.mark(trade_id, 102.0)
        self.assertEqual(marked["unrealised_pnl"], 2.0)
        closed = body.execution.close(trade_id, 103.0)
        self.assertEqual(closed["realised_pnl"], 3.0)
        report = body.paper_report()
        self.assertEqual(len(report["running"]), 0)
        self.assertEqual(len(report["closed"]), 1)

    def test_live_mode_can_never_be_submitted(self):
        from neofl_gateway.execution import ExecutionIntent
        authority = ExecutionAuthority()
        result = authority.submit(ExecutionIntent("r1", "REAL-001", "XAUUSD", "BUY", 1, "test", True, "live"), 100)
        self.assertFalse(result["accepted"])
        self.assertIn("Live broker execution is disabled", result["rejected"]["reason"])


if __name__ == "__main__":
    unittest.main()
