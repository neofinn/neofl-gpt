# NeoFL Body — Current Organism Map

NeoFL is one body containing multiple specialist brains coordinated by one Soul.

```text
                         NEOFL BODY
                             |
                     Shared World State
                             |
              +--------------+--------------+
              |                             |
        SPECIALIST BRAINS               DATA FABRIC
              |                             |
      +-------+-------+              market/underlying
      |       |       |               data + quality
     ARK   Wickless Godfather               |
      |       |       |                       |
      +-------+-------+                       |
              |                               |
          INDEX BRAIN <-----------------------+
              |
              |  index as tradable asset
              |  + index as aggregation
              |
              v
       BIDIRECTIONAL SIGNAL EXCHANGE
              |
       cross-examination by other brains
              |
              v
          NEOFL SOUL
              |
       thesis / conflict / regime
              |
              v
          TRADE ANALYSIS
              |
          RISK AUTHORITY
              |
       ACCOUNT / FIRM POLICY
              |
       EXECUTION FABRIC
              |
      +-------+-------+--------+
      |       |       |        |
     MT5   cTrader   FIX   Broker/Prop/Exchange APIs

      Outcome -> World State -> Learning Loop -> validated improvement
```

## Current body components

### Data fabric
Shared market state is supplied to brains. Brains should not independently fetch arbitrary market data.

### Specialist brains
Specialists produce independent observations/theses. Current integrated specialist: Index Intelligence. Existing strategy engines include Liquid ARK and Wickless; Godfather is planned for normalization into the same protocol.

### Index brain
The Index Brain treats an index as both a tradable asset and an aggregation. It can originate a signal from underlying constituent behavior or independently challenge a trader signal. When a trader brain generates an index signal, Index Intelligence cross-examines it using basket behavior. When Index Intelligence generates a signal, trader brains analyze the index as a tradable asset.

### Signal exchange
Signals have provenance. Receiving brains independently confirm, disagree, or mark the signal mixed. Disagreement is information and becomes learning data; it is not resolved by naïve voting.

### Soul
The Soul is the central coordinator/referee. It synthesizes independent evidence, evaluates conflicts and regime, then passes an actionable thesis through risk. It does not bypass risk or execution authority.

### Risk
Risk and account/firm policy are hard gates. Prop-firm and broker-specific constraints live outside strategy logic.

### Execution fabric
Execution is platform agnostic. MT5, cTrader, FIX, broker APIs, exchange APIs and compatible prop-firm platforms are adapters, not the NeoFL core.

### Learning
The body records predictions, cross-examinations, decisions and outcomes. Improvements are hypotheses until validated; live behavior is not rewritten from a single outcome.
