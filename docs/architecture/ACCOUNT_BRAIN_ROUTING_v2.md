# Account-level Brain routing — reconciled

The MT5 terminal is branch-agnostic. The Execution Gateway resolves the Brain deployment assigned to each account.

The gateway exposes account-level Brain switching, MT5 heartbeat/execution telemetry, MCP status, and dashboard data. The MT5 reporter sends telemetry to the gateway; the gateway attaches the resolved Brain name, branch, build, and endpoint to the account state.

The dashboard shows communication status, active Brain, branch/build, MCP status and endpoint, and allows an authorized admin to switch an account between MAIN and PARALLEL without changing the MT5 EA.

The existing `ACCOUNT_BRAIN_ROUTING.md` write was rejected because the target already exists and the write API requires the current blob SHA. This v2 file preserves the intended contract without overwriting the stale target blindly.
