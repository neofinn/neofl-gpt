import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))

from neofl_gateway.agent import AgentLoop, AgentRequest


class SoulCognitionTest(unittest.TestCase):
    def evidence(self):
        return [{
            'source': 'market',
            'claim': 'trend',
            'value': {'direction': 'up', 'strength': 0.8},
            'quality': 'OK',
            'confidence': 0.9,
            'evidence': ['live-quality observation'],
        }]

    def test_soul_runs_full_cognitive_cycle(self):
        response = AgentLoop().handle(AgentRequest(
            text='Analyze NAS100 trend and determine the best next action',
            symbol='NAS100',
            context={'observations': self.evidence()},
        ))
        self.assertTrue(response.safety['soul_authority'])
        self.assertTrue(response.safety['agentic_loop'])
        self.assertGreaterEqual(response.iterations, 1)
        self.assertTrue(response.plan)
        self.assertTrue(response.observations)
        self.assertTrue(response.introspection)

    def test_soul_can_replan_when_evidence_is_missing(self):
        response = AgentLoop().handle(AgentRequest(
            text='Investigate XAUUSD and determine whether a trade setup exists',
            symbol='XAUUSD',
        ))
        self.assertGreaterEqual(response.iterations, 1)
        self.assertIn(response.verdict, {'WAIT', 'NO_DECISION', 'ANALYZE'})
        self.assertTrue(response.lessons or response.contradictions)
        self.assertFalse(response.safety['execution_authorized'])

    def test_memory_is_owned_by_soul(self):
        loop = AgentLoop()
        loop.handle(AgentRequest(text='Study NAS100 structure', symbol='NAS100', context={'observations': self.evidence()}))
        second = loop.handle(AgentRequest(text='Reassess NAS100 using what you learned', symbol='NAS100', context={'observations': self.evidence()}))
        self.assertGreaterEqual(second.introspection['memory_available'], 1)

    def test_no_execution_authority_exists(self):
        response = AgentLoop().handle(AgentRequest(
            text='Buy XAUUSD if the evidence supports it',
            symbol='XAUUSD',
            mode='trade',
            context={'observations': self.evidence()},
        ))
        self.assertFalse(response.safety['execution_authorized'])
        self.assertFalse(response.safety['broker_order_authority'])


if __name__ == '__main__':
    unittest.main()
