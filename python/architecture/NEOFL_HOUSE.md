# NeoFL House — Unified Organism Architecture

This document defines the house that contains the NeoFL body. The house is the runtime boundary; the body is the coordinated organism; the Soul is the central authority; specialist brains are independent analytical organs.

```text
                              NEOFL HOUSE
                                   |
                    +--------------+--------------+
                    |                             |
               DATA FOUNDATION              MEMORY / KNOWLEDGE
                    |                             |
              Shared World State            Supabase / KB
                    |                             |
                    +--------------+--------------+
                                   |
                         OBSERVATION / EVENT BUS
                                   |
      +----------------------------+----------------------------+
      |             |              |             |              |
    TRADER        INDEX         OPTION          FX          DATA-ARB
    BRAINS        BRAIN          BRAIN       RELATION         BRAIN
      |             |              |             |              |
      +-------------+--------------+-------------+--------------+
                                   |
                         BIDIRECTIONAL SIGNAL BUS
                                   |
                       CROSS-EXAMINATION / DEBATE
                                   |
                              NEOFL SOUL
                                   |
                    +--------------+--------------+
                    |                             |
                THESIS ENGINE               REGIME STATE
                    |                             |
                    +--------------+--------------+
                                   |
                        INSTRUMENT SELECTOR
                                   |
                  +----------------+----------------+
                  |                                 |
             DIRECT ASSET                     DERIVATIVE
                                                  |
                                            OPTION / FUTURE
                  |                                 |
                  +----------------+----------------+
                                   |
                              RISK BRAIN
                                   |
                         ACCOUNT / FIRM POLICY
                                   |
                         EXECUTION AUTHORITY
                                   |
              +------------------+------------------+
              |                  |                  |
             MT5              cTrader        FIX / Broker /
                                             Exchange / Prop
              |                  |                  |
              +------------------+------------------+
                                   |
                               OUTCOMES
                                   |
                         +---------+---------+
                         |                   |
                  EXPERIENCE LEARNING   EXPERIMENT BRAIN
                                             |
                                  +----------+----------+
                                  |          |          |
                              Backtest     Demo    Scenario Lab
                                  |          |          |
                                  +----------+----------+
                                             |
                                      VALIDATION LAB
                                             |
                                    KNOWLEDGE PROMOTION
                                             |
                                             +----> SOUL
```

## House rules

1. Specialist brains are independent analysts. No brain directly owns production execution.
2. Every significant signal has provenance and can be independently cross-examined by other relevant brains.
3. The Index Brain treats indexes as tradable assets and as aggregations of underlying assets.
4. The Option Brain evaluates derivative expressions and compares them with direct-asset exposure.
5. FX Relationship Brain discovers synthetic crosses, lead/lag and currency-network relationships without assuming correlation equals arbitrage.
6. Data Arbitrage compares reference feeds with connected broker feeds and tests whether timing/quote differences are executable after costs and policy.
7. Experiment Brain can observe and analyze the rest of NeoFL, generate hypotheses, backtest, paper trade, use demo accounts and construct adversarial scenarios. It cannot directly alter its own governing logic or obtain real-money execution authority.
8. The Experiment Brain receives observations from every specialist brain, the Soul, risk, execution and outcomes. Its own internal private state is not treated as external observation input during the same reasoning cycle.
9. Learning has two streams: experience from market outcomes and knowledge from books/research. Both feed hypothesis generation and validation.
10. Promotion is versioned and controlled. An experiment or theory cannot become production behavior merely because it looks promising.
11. Risk and account/firm policy are hard gates between thesis and execution.
12. Execution is platform-agnostic; connectors are adapters beneath the core.

## House metaphor

- **House:** runtime/infrastructure boundary.
- **Body:** shared data, event, memory, risk and execution organs.
- **Brains:** specialist intelligence.
- **Soul:** coordination, synthesis and final thesis authority.
- **Kitchen:** thesis synthesis — combine evidence into a coherent trade idea.
- **Laboratory:** Experiment Brain + Validation Lab.
- **Memory:** Supabase/knowledge store.
- **Nervous system:** event bus + shared world state + signal exchange.
- **Hands:** execution connectors.
- **Immune system:** risk, policy, data-quality and safety gates.

The objective is not a collection of bots. It is one explainable, testable organism whose specialists can disagree, experiment, learn and improve without bypassing its safety and production boundaries.
