# Experiment Brain Execution Boundary

The Experiment Brain may use a **live connection only when that connection is explicitly identified and technically enforced as DEMO/PAPER/SANDBOX**. "Live connection" means a real connected platform session; it does not mean live-money execution.

## Allowed

- Historical backtests
- Market replay
- Simulation
- Paper accounts
- Demo accounts on supported brokers/platforms/prop environments
- Exchange testnets/sandboxes
- Stress and adversarial scenarios

## Forbidden

- Real-money production accounts
- Live-funded prop accounts
- Production broker accounts
- Production exchange accounts
- Production execution credentials

The execution fabric must expose the connector capability (`BACKTEST`, `PAPER`, `DEMO`, or `LIVE`) and independently enforce authorization. The Experiment Brain's maximum execution capability is `DEMO`; it must never receive or be able to request a `LIVE` capability.

The Experiment Brain may therefore run continuously against demo environments and observe real-time market conditions/fills there. Demo results remain experimental evidence and cannot directly promote a strategy to production.
