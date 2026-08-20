# NeoFL Execution — Account-Wide Tradable Universe

## Non-negotiable execution boundary

The MT5 Execution EA is an **account-level execution body**. The chart hosting the EA is only a runtime host. The host chart symbol MUST NOT define the execution universe or silently replace an order's requested symbol.

### Required behavior

1. On connection/initialization, discover the connected MT5 account's available symbol universe.
2. Accept an explicit `symbol` on every Brain `OrderIntent`.
3. Validate that requested symbol against the connected account at execution time.
4. Use `SymbolSelect(requested_symbol, true)` when the broker exposes the symbol but it is not currently selected in Market Watch.
5. Read price, digits, point, tick size/value, volume min/max/step, stops level, freeze level, trade mode, and filling constraints from the **requested symbol**, never from `_Symbol`.
6. Execute the order against the requested symbol.
7. Return the requested/actual symbol, execution result, retcode, order ticket, deal ticket when available, executed volume and prices to Brain.
8. If the symbol is unavailable, disabled, closed, or otherwise not executable, fail closed and return a symbol-specific reason. Never substitute the host chart symbol.
9. Account-level telemetry must report the account's symbol universe and per-symbol execution capability separately from the host chart.

## Host chart rule

`_Symbol` may be used only for host-chart/UI diagnostics. It must never be used as the fallback execution symbol for Brain orders.

Forbidden execution pattern:

```mql5
trade.Buy(volume, _Symbol, ...);
```

Required pattern:

```mql5
trade.Buy(volume, intent_symbol, ...);
```

## Example

If the EA is attached to `EURUSD`, Brain must still be able to submit:

```text
OrderIntent.symbol = XAUUSD
```

and the EA must validate and execute `XAUUSD` if that instrument is tradable on the connected account.

The same applies to any other broker-provided instrument: FX, metals, indices, energies, crypto CFDs, stocks/CFDs, futures, or other instruments actually exposed and tradeable by that account.

## Universe definition

The tradable universe is **not** "all MT5 symbols" and is **not** "the chart symbol". It is the intersection of:

- symbols exposed by the connected broker/account;
- symbols that can be selected/resolved by MT5;
- symbols whose trade mode permits the requested operation;
- symbols whose session is open for the requested operation;
- broker/account permissions and execution constraints.

This validation is performed per `OrderIntent` immediately before execution.

## Acceptance tests

- EA hosted on EURUSD can execute a valid XAUUSD OrderIntent.
- EA hosted on XAUUSD can execute a valid GBPJPY OrderIntent.
- EA hosted on any symbol can execute a valid symbol that is not currently selected in Market Watch after successful `SymbolSelect`.
- A request for an unavailable symbol is rejected with `SYMBOL_UNAVAILABLE`; host symbol is never substituted.
- A request for a non-tradable/closed symbol is rejected with a symbol-specific execution reason.
- Telemetry identifies host chart symbol separately from account universe and target execution symbol.
- An OrderIntent with a missing/empty symbol is rejected; it never defaults to `_Symbol`.

## Integration note

The current repository contains the execution contract and reusable execution boundary, but the concrete broker/MT5 EA source must consume this contract. Do not claim live multi-symbol execution until the EA passes the acceptance tests against a connected MT5 account.
