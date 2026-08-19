import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))

from neofl_gateway.agent import AgentLoop, AgentRequest


class AgentLoopTest(unittest.TestCase):
    def test_routes_index_option_and_risk_without_execution(self):
        response = AgentLoop().handle(AgentRequest(
            text='Analyze NAS100 options: compare the index movement with the underlying and Greeks.',
            symbol='NAS100',
        ))
        self.assertEqual(response.status, 'accepted')
        self.assertIn('Index Brain', response.routed_brains)
        self.assertIn('Option Brain', response.routed_brains)
        self.assertIn('Risk Brain', response.routed_brains)
        self.assertFalse(response.safety['execution_authorized'])


if __name__ == '__main__':
    unittest.main()
