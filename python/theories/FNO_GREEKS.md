# F&O Greeks Theory Pack

NeoFL must understand options Greeks as a **risk/sensitivity language**, not as a standalone buy/sell signal. Cboe describes Greeks as sensitivities affecting theoretical option value: Delta to underlying price, Gamma to changes in Delta, Theta to time decay, Vega to implied volatility, and Rho to interest rates. citeturn0search1turn0search11

## Core concepts

| Greek | NeoFL interpretation |
|---|---|
| Delta | Directional exposure to the underlying |
| Gamma | How quickly directional exposure changes as the underlying moves |
| Theta | Time-decay exposure |
| Vega | Exposure to changes in implied volatility |
| Rho | Interest-rate sensitivity |

The same Greek can have different portfolio consequences depending on whether the position is long/short and call/put. Cboe's educational material explicitly frames Greeks as a dashboard for option risk. citeturn0search1turn0search8

## What NeoFL must analyze

Greeks alone are insufficient. For an F&O market state, the Data Fabric should collect:

- underlying spot/index price
- futures price and basis
- option chain by strike and expiry
- bid/ask and liquidity
- volume
- open interest
- implied volatility
- Delta/Gamma/Theta/Vega/Rho
- ATM IV
- IV rank/percentile when available
- call/put OI and volume relationships
- volatility skew
- IV term structure
- days to expiry
- realized volatility
- session/time-to-expiry context
- corporate/event/calendar risk where relevant

Cboe option datasets demonstrate that option-chain data can include IV, all five primary Greeks, quotes, volume and open interest. citeturn0search15turn0search7

## NeoFL interpretation layers

### Market analysis

Determine whether the underlying is trending, ranging, breaking out, reverting, or transitioning.

### F&O analysis

Determine whether the derivatives market confirms or conflicts with the underlying thesis:

- directional exposure
- gamma concentration
- volatility expansion/contraction
- IV premium/discount versus realized volatility
- skew
- term structure
- OI concentration
- expiry risk
- liquidity

### Trade analysis

Only after the underlying thesis and F&O context agree should NeoFL decide whether a particular option/future structure is suitable.

## Important distinction

A high Delta is not itself a bullish signal. High Gamma is not itself a buy signal. High Vega is not itself a volatility trade. Theta is not simply a "bad" value. These are sensitivities whose meaning depends on position structure, market regime, time to expiry and the rest of the portfolio.

## Learning objective

NeoFL should eventually learn relationships such as:

`market regime + IV regime + skew + gamma + expiry + structure -> historical expectancy`

It should measure these relationships from outcomes and validate improvements before promoting them into production behavior.

## Data provenance rule

When Greeks are supplied by a venue/broker/data vendor, retain the source and timestamp. When Greeks are model-computed, retain the pricing model and inputs. Cboe provides real-time implied-volatility and Greek analytics and also publishes trade/quote datasets with Greek fields, illustrating why provenance matters. citeturn0search5turn0search4

This theory pack is educational architecture, not a recommendation to trade a particular option or structure.
