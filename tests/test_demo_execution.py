import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))

from neofl_gateway.demo_execution import DemoExecution
from neofl_gateway.execution import ExecutionAuthority, ExecutionIntent


class FakeDemoTransport:
    def __init__(self, account_type='DEMO'):
        self._account_type = account_type
        self.orders = []

    def account(self):
        return {'login': '12345', 'account_type': self._account_type, 'balance': 10000.0, 'equity': 10000.0}

    def quote(self, symbol):
        return {'symbol': symbol, 'bid': 100.0, 'ask': 100.1, 'quality': 'OK'}

    def order(self, *, account, symbol, side, quantity, request_id, reason):
        self.orders.append((account, symbol, side, quantity, request_id, reason))
        return {'accepted': True, 'ticket': 'DEMO-1', 'deal': 'DEMO-DEAL-1', 'price': 100.1}

    def close(self, *, ticket, symbol, quantity, request_id, reason):
        return {'accepted': True, 'ticket': ticket, 'realised_pnl': 3.0}

    def positions(self, account):
        return [{'ticket': 'DEMO-1', 'account': account, 'symbol': 'XAUUSD', 'side': 'BUY', 'quantity': 1.0, 'unrealised_pnl': 2.0}]


class DemoExecutionTest(unittest.TestCase):
    def test_real_order_uses_live_quote_and_demo_account(self):
        transport = FakeDemoTransport()
        authority = ExecutionAuthority(transport, '12345')
        result = authority.submit(ExecutionIntent('r1', '12345', 'XAUUSD', 'BUY', 1.0, 'Soul recommendation', True, 'demo_live'))
        self.assertTrue(result['accepted'])
        self.assertEqual(transport.orders[0][0], '12345')
        self.assertEqual(result['broker']['ticket'], 'DEMO-1')

    def test_real_account_is_blocked(self):
        authority = ExecutionAuthority(FakeDemoTransport('REAL'), '12345')
        result = authority.submit(ExecutionIntent('r2', '12345', 'XAUUSD', 'BUY', 1.0, 'Soul recommendation', True, 'demo_live'))
        self.assertFalse(result['accepted'])
        self.assertIn('DEMO broker account', result['rejected']['reason'])

    def test_paper_mode_is_blocked(self):
        authority = ExecutionAuthority(FakeDemoTransport(), '12345')
        result = authority.submit(ExecutionIntent('r3', '12345', 'XAUUSD', 'BUY', 1.0, 'test', True, 'paper'))
        self.assertFalse(result['accepted'])
        self.assertIn('simulated/paper fills are disabled', result['rejected']['reason'])


if __name__ == '__main__':
    unittest.main()
