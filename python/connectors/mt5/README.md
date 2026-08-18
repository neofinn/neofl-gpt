# NeoFL MetaTrader 5 Adapter

NeoFL uses `ariadng/metatrader-mcp-server` as the initial MT5 adapter candidate. The external MCP implementation remains outside the NeoFL core; NeoFL talks to it through this adapter boundary.

## Account isolation

Credentials must NEVER be committed to GitHub. Configure them through the deployment/runtime secret store. The adapter must expose account identity, server, login state, account mode (DEMO/LIVE when the provider exposes it), and connection health to the NeoFL world state.

## Safety gate

The adapter must default to `DEMO`/paper operation. Live trading requires an explicit account-policy gate and separate live authorization. The Soul cannot bypass this gate.

## Responsibilities

- connect/disconnect MT5
- retrieve account state
- retrieve symbols, quotes, bars and positions
- submit/cancel/modify orders only when execution authority is granted
- return broker/execution timestamps and errors
- normalize MT5 symbols into NeoFL canonical instruments
- publish connection/account/market/order events

## Reference implementation

Repository: `ariadng/metatrader-mcp-server`
