# How to build and run NeoFL

Verified on this workstation 2026-08-16: macOS 26.5.2, Apple Silicon, MetaTrader 5 build 6090
running under the bundled Wine 11.1 in `/Applications/MetaTrader 5.app`.

There are four loops, fastest first. Use the cheapest one that can answer your question.

| Loop | What it proves | Speed | Automatable |
|---|---|---|---|
| 1. Logic tests (Python) | State machines, math, resolver rules are correct | ms | ✅ fully |
| 2. MQL5 compile | The code is valid MQL5 and links with its includes | ~1 s | ✅ fully — **verified working** |
| 3. Strategy Tester | Behavior against historical data | minutes | ⚠️ needs account in config |
| 4. Demo account | Real broker execution, fills, slippage | live | human-gated (GATE 3) |

## Loop 1 — logic tests in Python

Most NeoFL bugs will not be MQL5 syntax. They will be in the Bucket and Straddle state machines,
the risk math, and the symbol resolver — logic that is expensive to test through MT5 and cheap to
test directly.

```bash
python3 -m unittest discover -s tests -t .
```

Where practical, encode a rule as an executable Python reference (for example the straddle
transition: *initial SL at straddle BE → bucket floating hits zero → move SL to bucket zero-floating
level → close original → runner*), test it exhaustively there, and require the MQL5 to match. A
state machine that is wrong in Python is wrong in MQL5 too, and Python tells you in milliseconds.

## Loop 2 — compile MQL5 (works on this Mac)

MetaEditor runs under MetaTrader 5.app's bundled Wine. Compilation is fully automatable here.

```bash
tools/mql5_compile.sh DEPLOYMENTS/NeoFL_GOLD          # a whole package
tools/mql5_compile.sh path/to/One.mq5                 # a single file
```

The script copies the directory into the Wine staging area (so `#include "..."` resolves against
sibling `.mqh` files, matching the single-folder packaging rule), compiles, prints errors and
warnings, and copies the resulting `.ex5` back next to the source. Exit 0 only on zero errors.

### Why the script parses the log instead of checking the exit code

MetaEditor's exit status does not indicate success. Measured on this machine:

| Outcome | Exit code |
|---|---|
| 0 errors, 1 warning | **1** |
| 2 errors, 0 warnings | **0** |

A build script trusting `$?` would report a broken build as green and a clean build as failed. The
`Result:` line in the compile log is authoritative. The log is UTF-16LE and must be decoded
(`iconv -f UTF-16LE`).

### Environment overrides

`WINE_PREFIX` and `WINE_BIN` can be set if MetaTrader is installed elsewhere. Defaults:

```
WINE_PREFIX=~/Library/Application Support/net.metaquotes.wine.metatrader5
WINE_BIN=/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine
```

## Loop 3 — Strategy Tester

The terminal accepts a config file and can run the tester headlessly:

```bash
WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" \
  "C:\\Program Files\\MetaTrader 5\\terminal64.exe" \
  /config:"C:\\Program Files\\MetaTrader 5\\config\\<name>.ini"
```

with a `[Tester]` section specifying `Expert`, `Symbol`, `Period`, `Model`, `FromDate`, `ToDate`,
`Deposit`, `Report`, and `ShutdownTerminal=1`.

**Current blocker.** A headless run attempted on 2026-08-16 failed with:

```
Tester   tester not started because the account is not specified
Terminal shutdown with -1000012353
```

The tester requires an account in the config. Resolving that means putting broker login details in
the ini — **an AI agent must never request, handle, or store broker credentials.** Two safe options:

1. **You add the account line yourself** to the ini (kept out of Git — `.gitignore` covers
   `*.set.local` and `accounts.ini`; add your ini there too), then agents can invoke the run.
2. **Run the tester from the MT5 GUI**, which uses the already-logged-in account. This is the normal
   path and is appropriate anyway, since backtest validation is a human approval gate (GATE 3).

Either way, **the compile loop stays fully automated** — which is where most iteration happens.

### History data

Backtests need downloaded history for the symbol and period. Present on this machine:
`bases/Default/history/XAUUSD/2026.hcc` plus some FX majors for 2024. Anything else must be
downloaded in the terminal first, and a tester run against missing history is not a valid result.

## Loop 4 — demo account

Real broker execution. Per the canon this is a human approval gate. The initial objective is to
**prove execution, not profitability**: that orders are generated, reach MT5, are accepted, receive
SL/TP, trail correctly, and that state transitions fire as designed.

## What cannot be verified here

Be precise in status reports — an unverified claim about a trading system is worse than no claim.

- A passing Python test says the **logic** is right, not that the EA works.
- A clean compile says the code is **valid MQL5**, not that the strategy is correct.
- Neither says anything about profitability, broker behavior, fills, or slippage.
- Never report a backtest that was not actually run, or a trade that was not actually observed.

## MT5 ships built-in MCP servers — CONFIRMED

Probed 2026-08-16 against a running terminal. MetaTrader 5 build 6090 runs **two local MCP servers**,
both enabled on this machine, plus a built-in AI assistant.

From `config/assistant.ini` (UTF-16LE):

| Section | Endpoint | Enabled |
|---|---|---|
| `[MCP.MetaEditor]` | `http://127.0.0.1:22345/mcp` | yes |
| `[MCP.MetaTrader]` | `http://127.0.0.1:22346/mcp` | yes |
| `[MCP.Custom]` | `https://www.metatrader.com/mcp` | yes |

Verified server behavior on 22346:

```
Server: MetaTrader5-MCP
MCP-Protocol-Version: 2025-06-18
WWW-Authenticate: Bearer realm="MetaTrader5-MCP"
```

Auth is genuinely enforced — an invalid bearer token returns `401`. Each endpoint has its own
168-character API key stored in `assistant.ini`.

The MetaEditor server (22345) did not respond while only the terminal was running; it likely starts
with MetaEditor.

### Why this matters

A working MCP connection to the MetaTrader server is the most plausible route around the Strategy
Tester's account requirement, and would give programmatic access to market data, symbols, positions,
and history without hand-driving the GUI. **This is worth evaluating before building custom bridge
infrastructure** — it may replace part of the planned MT5 Data Bridge work.

To connect a client, the API key from `[MCP.MetaTrader]` must be supplied as a bearer token. That key
is a credential: it belongs to the account owner, must be added by them, and must never be committed.
`.gitignore` already excludes `accounts.ini`; treat `assistant.ini` the same way.

### ⚠️ Risk: the built-in assistant has trade permission

`[Assistant]` on this machine is configured with:

```
Provider = MQL5.community        Model = MQL5 Lite
Endpoint = https://api.inferdeck.net
PermissionsTrade    = 1     <-- AI is permitted to trade
PermissionsShell    = 0
PermissionsWeb      = 0
PermissionsOpposite = 1
```

`PermissionsTrade = 1` grants MetaTrader's own AI assistant authority to place trades, and it routes
through a third-party inference endpoint. That is in direct tension with the NeoFL canon:

> Do NOT give an LLM unrestricted live order authority.
> No AI component should bypass risk controls or human live-deployment approval.
> External AI must not become a single point of failure.

This is a product-owner decision, not an engineering one. Two things to weigh: whether an AI assistant
should hold trade permission on an account NeoFL also trades, and whether an unrelated AI acting on
the same account would corrupt the execution evidence NeoFL's own testing depends on. The setting
lives in MT5 under Tools → Options.

**UNCONFIRMED and not built against:** the actual tool surface either server exposes. Establishing
that requires an authenticated `initialize` handshake, which needs the owner's key.

## Toolchain gaps on this workstation

Not currently installed, and not yet needed:

- **Homebrew** — none. Needed before installing anything else via package manager.
- **Python 3.12+** — only system Python 3.9.6 is present. The canon calls for 3.12+; the current
  test suite runs fine on 3.9, but the Python data/analytics layer will want the newer runtime.
- **Docker, Node.js** — absent. Not required by any current phase.

Install these only when a phase actually requires them.
