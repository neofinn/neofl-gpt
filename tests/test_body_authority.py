import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))

from neofl_gateway.agent import AgentLoop, AgentRequest
from neofl_gateway.body import NeoFLBody


class FakeStore:
    def __init__(self):
        self.requests = []
        self.decisions = []
        self.snapshots = []

    def put_request(self, value):
        self.requests.append(value)

    def put_decision(self, value):
        self.decisions.append(value)

    def put_snapshot(self, value):
        self.snapshots.append(value)


class BodyAuthorityTest(unittest.TestCase):
    def test_all_reasoning_enters_soul(self):
        store = FakeStore()
        body = NeoFLBody(AgentLoop(), store)
        result = body.think(AgentRequest(text='Analyze NAS100', symbol='NAS100'))
        self.assertTrue(result.allowed)
        self.assertEqual(len(store.requests), 1)
        self.assertEqual(len(store.decisions), 1)
        self.assertIn('agentic_loop', result.response['safety'])

    def test_execution_intent_never_gets_broker_authority(self):
        store = FakeStore()
        body = NeoFLBody(AgentLoop(), store)
        result = body.authorize_execution_intent(
            intent={'action': 'BUY', 'symbol': 'NAS100', 'volume': 1.0},
            symbol='NAS100',
        )
        self.assertFalse(result.response['execution_authorized'])
        self.assertEqual(result.response['execution_authority'], 'external_risk_execution_gate')

    def test_bad_external_state_is_not_admitted(self):
        store = FakeStore()
        body = NeoFLBody(AgentLoop(), store)
        result = body.receive_external_event(
            source='test-webhook',
            symbol='NAS100',
            payload={'price': None},
            quality='INVALID',
        )
        self.assertFalse(result.allowed)
        self.assertEqual(store.snapshots, [])


if __name__ == '__main__':
    unittest.main()
