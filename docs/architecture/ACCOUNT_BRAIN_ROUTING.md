# Account-level Brain routing

The MT5 terminal remains branch-agnostic. The Execution Gateway resolves the Brain deployment assigned to each account.

Supported deployment records contain `name`, `branch`, `build`, `endpoint`, and `enabled`. An account can be assigned to `MAIN` or `PARALLEL` without changing the EA.

The terminal-side `NeoFL_Reporter.mq5` sends account heartbeat telemetry to `/mt5/report` and execution events to `/mt5/execution-report`. The gateway should return its resolved deployment identity (`branch`, `build`, `brain`, `mcp`) so the terminal/dashboard can display the active connection unambiguously.

Every execution report should retain account, Brain deployment, build, and intent identifiers for audit/reconciliation.
