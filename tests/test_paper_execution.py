import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

from neofl_gateway.execution import ExecutionAuthority, ExecutionIntent


class DemoExecutionTest(unittest.TestCase):
    def test_execution_requires_demo_live_mode_and_transport(self):
        authority = ExecutionAuthority()
        result = authority.submit(ExecutionIntent("r1", "DEMO-001", "XAUUSD", "BUY", 0.01, "test", True, "paper"))
        self.assertFalse(result["accepted"])
        self.assertIn("simulated/paper fills are disabled", result["rejected"]["reason"])

        result = authority.submit(ExecutionIntent("r2", "DEMO-001", "XAUUSD", "BUY", 0.01, "test", True, "demo_live"))
        self.assertFalse(result["accepted"])
        self.assertIn("Demo broker transport is not connected", result["rejected"]["reason"])

    def test_execution_requires_soul_authorization(self):
        authority = ExecutionAuthority()
        result = authority.submit(ExecutionIntent("r3", "DEMO-001", "XAUUSD", "BUY", 0.01, "test", False, "demo_live"))
        self.assertFalse(result["accepted"])
        self.assertIn("Soul authorization is required", result["rejected"]["reason"])


if __name__ == "__main__":
    unittest.main()
