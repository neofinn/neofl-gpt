# NeoFL Body — Execution Fabric Contract v1

**Status:** Canonical addendum
**Date:** 2026-08-19
**Authority:** Product-owner architecture addendum to `MASTER_ARCHITECTURE_v2.md`

## 1. Purpose

NeoFL is one shared trading framework with independent strategy EAs. The shared Body owns canonical state, account identity, risk/execution boundaries, telemetry, and execution lifecycle. Strategy signal logic remains outside the Body and must not be merged into execution infrastructure.

## 2. Canonical flow

```text
Strategy / Brain
      |
      v
Canonical OrderIntent
      |
      v
NeoFL Execution Fabric
      |
      +--> Platform Adapter (MT5 today)
      |       |
      |       v
      |    MQL5 execution authority
      |
      v
ExecutionReport
      |
      v
NeoFL Body State / Observer / Telemetry
```

The gateway is an adapter/fabric boundary, not a strategy engine.

## 3. Canonical account identity

```text
account_id
account_number
connector
server
environment
binding
execution_enabled
```

Binding credentials are never embedded in generated URLs. They are supplied through the `X-NeoFL-Binding-Token` header or an authenticated request body.

## 4. Canonical OrderIntent

```text
OrderIntent
- id
- account_id
- strategy
- symbol
- direction
- order_type
- quantity
- entry
- stop
- target
- time_in_force
- thesis_id
- risk_profile
- metadata
- status
- created_at
- claimed_at
- completed_at
```

Lifecycle:

```text
QUEUED -> CLAIMED -> EXECUTED
                   \-> REJECTED
QUEUED -> CANCELLED
```

The gateway does not invent signals. It transports normalized intent and maintains lifecycle state.

## 5. Canonical ExecutionReport

```text
ExecutionReport
- id
- intent_id
- account_id
- adapter
- status
- filled_quantity
- average_fill_price
- realized_pnl
- broker_order_id
- rejection_code
- timestamp
- metadata
```

The platform adapter translates canonical intent into platform-native execution and returns a report.

## 6. MT5 adapter

`mt5/NeoFL_Executioner.mq5` is the MT5 platform adapter.

Responsibilities:

- identify runtime MT5 account/server/environment
- authenticate against the Body gateway
- publish account telemetry
- claim canonical `OrderIntent` records
- resolve broker symbol aliases where required
- execute only when the Body `execution_enabled` gate is true
- return an `ExecutionReport`
- fail closed when authentication or execution authorization is unavailable

The EA contains no strategy signal generation.

## 7. Explicit execution gate

Every account has an `execution_enabled` state. The default is locked.

```text
execution_enabled = false
        |
        +--> telemetry/handshake allowed
        +--> intent visibility allowed
        +--> broker execution BLOCKED

execution_enabled = true
        |
        +--> authenticated adapter may claim/execute intents
```

Changing this gate is an explicit administrative action.

## 8. External Brain boundary

The Agentic Brain may analyze telemetry, classify regime, inspect performance, diagnose anomalies, analyze backtests, recommend parameters, and produce canonical recommendations/intents subject to the NeoFL control boundary.

The Agentic Brain must not become an unbounded direct broker-order authority.

## 9. Strategy isolation

The independent strategy modules remain:

- ARK / Liquid Flow
- Jobbing
- Price Action
- Gold
- FX
- BTC
- Indices

They consume shared Body infrastructure but do not share signal rules accidentally.

## 10. Canonical Body routes

```text
POST /api/accounts
POST /api/handshake
POST /api/telemetry
POST /api/v1/order-intents
GET  /api/v1/execution/next
POST /api/v1/execution-report
POST /api/v1/order-intents/:id/cancel
GET  /api/v1/accounts/:id
```

Legacy account/handshake/telemetry routes may remain during migration; new integrations should use the canonical `v1` contract.

## 11. Failure rules

- Missing or invalid binding -> reject and expose no private account state.
- Missing market/platform data -> no fabricated execution input.
- AI unavailable -> deterministic NeoFL execution infrastructure remains independent.
- Execution gate locked -> no broker order.
- Unsupported symbol/direction/quantity -> rejected intent with an execution report.
- Adapter/network failure -> no local autonomous trade generation.

## 12. Source-of-truth relationship

This document is an addendum to the current architecture canon. It defines the Body/Execution Fabric boundary introduced on 2026-08-19 without changing the independence of the seven strategy families.
