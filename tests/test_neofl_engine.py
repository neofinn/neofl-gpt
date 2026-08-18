import unittest

from neofl_engine import EngineConfig, EventType, NeoFLEngine, OrderIntent
from neofl_engine.ports import AccountPort, EventStore, ExecutionPort, MarketDataPort, RiskPort, StrategyPort


class MemoryStore(EventStore):
    def __init__(self):
        self.events = []

    def append(self, event):
        self.events.append(event)


class Market(MarketDataPort):
    def snapshot(self):
        return {"symbol": "XAUUSD", "bid": 3000.0, "ask": 3000.2}


class Account(AccountPort):
    def snapshot(self):
        return {"equity": 10000.0, "balance": 10000.0}


class Strategy(StrategyPort):
    def evaluate(self, market, account):
        return [OrderIntent(symbol=market["symbol"], side="BUY", volume=0.01, reason="test")]


class Risk(RiskPort):
    def approve(self, intent, account, market):
        return True, "approved"


class Execution(ExecutionPort):
    def __init__(self):
        self.submitted = []
        self.reconciled = False

    def submit(self, intent):
        self.submitted.append(intent)
        return intent.intent_id

    def reconcile(self):
        self.reconciled = True
        return {}


class NeoFLEngineTests(unittest.TestCase):
    def make_engine(self):
        execution = Execution()
        store = MemoryStore()
        engine = NeoFLEngine(
            config=EngineConfig(), market=Market(), account=Account(),
            strategy=Strategy(), risk=Risk(), execution=execution, store=store,
        )
        return engine, execution, store

    def test_start_reconciles_before_ready(self):
        engine, execution, _ = self.make_engine()
        engine.start()
        self.assertTrue(execution.reconciled)
        self.assertEqual(engine.state.value, "READY")

    def test_cycle_risk_approval_precedes_execution(self):
        engine, execution, store = self.make_engine()
        engine.start()
        intents = engine.cycle()
        self.assertEqual(len(intents), 1)
        self.assertEqual(len(execution.submitted), 1)
        types = [event.type for event in store.events]
        self.assertLess(types.index(EventType.RISK_CHECK), types.index(EventType.ORDER_INTENT))

    def test_halted_engine_emits_no_order(self):
        engine, execution, _ = self.make_engine()
        engine.halt("manual safety halt")
        self.assertEqual(engine.cycle(), [])
        self.assertEqual(execution.submitted, [])


if __name__ == "__main__":
    unittest.main()
