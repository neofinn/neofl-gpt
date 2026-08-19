import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))

from neofl_gateway.agent import AgentLoop, AgentRequest


class AgenticSoulTest(unittest.TestCase):
    def test_no_evidence_fails_closed(self):
        response = AgentLoop().handle(AgentRequest(
            text='Determine whether NAS100 has a valid long setup.',
            symbol='NAS100',
        ))
        self.assertTrue(response.safety['agentic_loop'])
        self.assertFalse(response.safety['execution_authorized'])
        self.assertIn(response.verdict, {'WAIT', 'NO_DECISION'})
        self.assertGreaterEqual(response.iterations, 1)
        self.assertTrue(response.plan)
        self.assertTrue(response.contradictions)

    def test_supplied_quality_evidence_reaches_specialists(self):
        response = AgentLoop().handle(AgentRequest(
            text='Analyze NAS100 setup and challenge the thesis.',
            symbol='NAS100',
            context={
                'observations': [
                    {
                        'source': 'MT5',
                        'claim': 'market_state',
                        'value': {'bid': 20000, 'ask': 20001},
                        'quality': 'OK',
                        'confidence': 0.9,
                        'evidence': ['live quote received'],
                    }
                ]
            },
        ))
        self.assertTrue(response.hypotheses)
        self.assertFalse(response.safety['execution_authorized'])
        self.assertTrue({'Market Structure Brain', 'Trader Brains'} & set(response.routed_brains))


if __name__ == '__main__':
    unittest.main()
