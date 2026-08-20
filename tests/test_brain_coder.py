import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))

from neofl_gateway.coding_memory import CodingMemory
from neofl_gateway.python_coder import PythonCoder
from neofl_gateway.soul import CognitiveSoul


class BrainCoderTest(unittest.TestCase):
    def test_coding_memory_remembers_and_retrieves_lessons(self):
        memory = CodingMemory()
        memory.remember(kind='bug', target='gateway.py', lesson='Use the authoritative deployment resolver.', evidence=['routing regression'])
        rows = memory.recall(target='gateway.py', query='deployment')
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].kind, 'bug')

    def test_python_coder_only_proposes_patch(self):
        coder = PythonCoder()
        proposal = coder.propose_patch(
            target='x.py',
            old_content='x = 1\n',
            new_content='x = 2\n',
            summary='Correct x',
            validation=['python -m unittest'],
        )
        self.assertTrue(proposal.unified_diff)
        self.assertFalse(proposal.approved)
        approved = coder.approve(proposal)
        self.assertTrue(approved.approved)
        self.assertEqual(approved.risk, 'APPROVED_FOR_VALIDATION')

    def test_soul_owns_coder_and_reports_self_repair_mode(self):
        soul = CognitiveSoul()
        self.assertTrue(soul.coder)
        state = soul.create_plan('Analyze NAS100', 'NAS100', 'analyze', {})
        state = soul.run(state, {})
        info = soul.introspect(state)
        self.assertTrue(info['python_coder'])
        self.assertEqual(info['self_repair_mode'], 'PROPOSE_VALIDATE_ROLLBACK')
        self.assertGreaterEqual(info['coding_memory_available'], 0)


if __name__ == '__main__':
    unittest.main()
