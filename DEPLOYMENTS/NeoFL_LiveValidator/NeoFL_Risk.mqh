//+------------------------------------------------------------------+
//| NeoFL_Risk.mqh                                                   |
//| Core module. Position sizing and risk validation.                |
//| Computes size. Never decides direction, entry, or exit.          |
//+------------------------------------------------------------------+
//
// Canon: every strategy feeds the same risk architecture, and "the strategy should
// REQUEST risk, not calculate broker-specific position sizing itself." A strategy
// says "I want in, my stop is here"; this module answers "then your size is X, or
// you cannot take this trade."
//
// This is the module where a bug costs real money. Three failure modes are guarded
// explicitly, because each of them silently produces a plausible-looking number:
//
//   1. Division by zero or by a missing tick value -> infinite or absurd size.
//      Broker metadata is validated before any arithmetic touches it.
//
//   2. Rounding UP to the broker's volume step -> more risk than authorised.
//      Volume is always floored to the step, never rounded to nearest.
//
//   3. Minimum lot exceeding the risk budget -> the classic silent over-risk.
//      If the smallest tradable volume risks more than allowed, this module
//      DECLINES. It does not quietly trade the minimum and hope. On a small
//      account with a wide stop this is a routine condition, not an edge case.
//
// UNCONFIRMED defaults are marked below. They are placeholders pending product
// approval, not chosen trading parameters.
//
#ifndef __NEOFL_RISK_MQH__
#define __NEOFL_RISK_MQH__

#include "NeoFL_DataQuality.mqh"
#include "NeoFL_SymbolResolver.mqh"

enum ENUM_NEOFL_RISK_MODEL
{
   NEOFL_RISK_FIXED_LOT       = 0,  // always the same volume
   NEOFL_RISK_PERCENT_EQUITY  = 1,  // risk a share of current equity
   NEOFL_RISK_PERCENT_BALANCE = 2   // risk a share of balance (ignores open P/L)
};

//+------------------------------------------------------------------+
//| Risk configuration.                                               |
//|                                                                   |
//| Every value here is a TRADING parameter and belongs to the product |
//| owner. The defaults below are UNCONFIRMED placeholders so the code |
//| compiles and can be tested; they are not a recommendation.        |
//+------------------------------------------------------------------+
struct NeoFLRiskConfig
{
   ENUM_NEOFL_RISK_MODEL model;
   double fixed_lot;              // used when model == FIXED_LOT
   double risk_percent;           // used by the percent models
   double hard_max_lot;           // absolute ceiling; 0 disables
   double max_total_exposure_lot; // across all open positions; 0 disables
   int    max_open_positions;     // 0 disables
   int    max_trades_per_day;     // 0 disables
   double max_daily_drawdown_pct; // 0 disables
   bool   allow_min_lot_override; // see below -- default FALSE deliberately
};

//--- UNCONFIRMED defaults. Pending product approval; see docs/product/DECISIONS.md.
//
//    hard_max_lot = 0.01 mirrors the legacy v3.85 "hard start ceiling", which was a
//    deliberate safety rail. It appears nowhere in the v2 canon, so whether it
//    carries forward is a product decision, not an engineering one.
//
//    allow_min_lot_override = false means: when the broker's minimum lot risks MORE
//    than the configured budget, refuse the trade. Setting it true trades the
//    minimum anyway and knowingly exceeds the risk limit. False is the safe default
//    and the only one consistent with "risk percent" meaning anything.
void NeoFLRisk_Defaults(NeoFLRiskConfig &c)
{
   c.model                   = NEOFL_RISK_PERCENT_EQUITY;
   c.fixed_lot               = 0.01;
   c.risk_percent            = 1.0;
   c.hard_max_lot            = 0.01;
   c.max_total_exposure_lot  = 0.0;
   c.max_open_positions      = 1;
   c.max_trades_per_day      = 0;
   c.max_daily_drawdown_pct  = 0.0;
   c.allow_min_lot_override  = false;
}

//--- Result of a sizing request.
struct NeoFLRiskResult
{
   bool          approved;
   double        volume;         // 0 when not approved
   double        risk_money;     // what the approved size actually risks
   double        risk_percent;   // that, as a share of the account figure used
   NeoFLDecision decision;       // provenance (D-002)
};

//--- Broker contract facts needed for sizing, with validity attached.
struct NeoFLContractSpec
{
   bool   valid;
   double tick_size;
   double tick_value;
   double volume_min;
   double volume_max;
   double volume_step;
   int    digits;
   string reject_reason;
};

//+------------------------------------------------------------------+
//| Read and validate contract metadata.                              |
//|                                                                   |
//| Every field is checked before use. A zero tick value or step is a  |
//| division waiting to happen, and brokers do occasionally report     |
//| zeros for a symbol that is not fully initialised.                  |
//+------------------------------------------------------------------+
NeoFLContractSpec NeoFLRisk_ReadContract(const string symbol)
{
   NeoFLContractSpec s;
   s.valid = false;
   s.tick_size = s.tick_value = 0.0;
   s.volume_min = s.volume_max = s.volume_step = 0.0;
   s.digits = 0;
   s.reject_reason = "";

   if(!SymbolSelect(symbol, true))
   {
      s.reject_reason = "symbol not available from broker: " + symbol;
      return s;
   }

   s.tick_size   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   s.tick_value  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   s.volume_min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   s.volume_max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   s.volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   s.digits      = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   if(s.tick_size <= 0.0)
   { s.reject_reason = "broker reports tick_size <= 0"; return s; }
   if(s.tick_value <= 0.0)
   { s.reject_reason = "broker reports tick_value <= 0; cannot convert price distance to money"; return s; }
   if(s.volume_step <= 0.0)
   { s.reject_reason = "broker reports volume_step <= 0"; return s; }
   if(s.volume_min <= 0.0 || s.volume_max < s.volume_min)
   { s.reject_reason = "broker reports an incoherent volume range"; return s; }

   s.valid = true;
   return s;
}

//--- Decimal places implied by a volume step, for normalization.
int NeoFLRisk_VolumeDigits(const double step)
{
   for(int d = 0; d <= 8; d++)
      if(MathAbs(step - NormalizeDouble(step, d)) < 1e-9)
         return d;
   return 8;
}

//+------------------------------------------------------------------+
//| Floor a volume onto the broker's step grid.                       |
//|                                                                   |
//| FLOOR, never round-to-nearest. Rounding up would take more risk    |
//| than authorised -- a 0.014 requirement becoming 0.02 is a 43%      |
//| overshoot, silently, on every trade.                              |
//+------------------------------------------------------------------+
double NeoFLRisk_FloorToStep(const double volume, const NeoFLContractSpec &s)
{
   if(volume <= 0.0) return 0.0;
   const double steps = MathFloor((volume - s.volume_min) / s.volume_step + 1e-9);
   const double v = s.volume_min + steps * s.volume_step;
   return NormalizeDouble(MathMax(0.0, v), NeoFLRisk_VolumeDigits(s.volume_step));
}

//+------------------------------------------------------------------+
//| Money risked by `volume` if price moves `stopDistance` against it. |
//+------------------------------------------------------------------+
double NeoFLRisk_MoneyAtRisk(const double volume, const double stopDistance,
                             const NeoFLContractSpec &s)
{
   if(volume <= 0.0 || stopDistance <= 0.0 || !s.valid) return 0.0;
   const double ticks = stopDistance / s.tick_size;
   return ticks * s.tick_value * volume;
}

//--- Total volume currently open under a magic number, for exposure limits.
double NeoFLRisk_OpenExposure(const string symbol, const ulong magic)
{
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

int NeoFLRisk_OpenCount(const string symbol, const ulong magic)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Size a trade.                                                     |
//|                                                                   |
//| `stopDistance` is the price distance to the stop, in price units   |
//| (not points). A strategy that cannot state its stop cannot be      |
//| sized -- risk is meaningless without it, and this refuses rather   |
//| than inventing a default stop.                                     |
//+------------------------------------------------------------------+
NeoFLRiskResult NeoFLRisk_Size(const string symbol,
                               const double stopDistance,
                               const NeoFLRiskConfig &cfg,
                               const ulong magic)
{
   NeoFLRiskResult r;
   r.approved     = false;
   r.volume       = 0.0;
   r.risk_money   = 0.0;
   r.risk_percent = 0.0;
   NeoFLDecision_Begin(r.decision, "Risk", symbol);

   //--- Gold-only guard. A strategy must never size an instrument the resolver rejects.
   NeoFLInstrument inst;
   if(!NeoFLSym_ClassifyString(symbol, inst))
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_INVALID,
                        "symbol not recognised: " + inst.reject_reason);
      return r;
   }

   const NeoFLContractSpec spec = NeoFLRisk_ReadContract(symbol);
   if(!spec.valid)
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_INVALID,
                        "contract metadata unusable: " + spec.reject_reason);
      return r;
   }

   if(stopDistance <= 0.0)
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_OK,
                        "no stop distance supplied; risk cannot be defined without a stop");
      return r;
   }

   const double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   //--- Position and exposure limits, before any sizing work.
   if(cfg.max_open_positions > 0 &&
      NeoFLRisk_OpenCount(symbol, magic) >= cfg.max_open_positions)
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        StringFormat("already at max open positions (%d)", cfg.max_open_positions),
                        StringFormat("open=%d", NeoFLRisk_OpenCount(symbol, magic)));
      return r;
   }

   //--- Desired volume, per the configured model.
   double desired = 0.0;
   double budget  = 0.0;
   string basis   = "";

   if(cfg.model == NEOFL_RISK_FIXED_LOT)
   {
      desired = cfg.fixed_lot;
      basis   = StringFormat("fixed_lot=%.2f", cfg.fixed_lot);
   }
   else
   {
      const double account = (cfg.model == NEOFL_RISK_PERCENT_EQUITY) ? equity : balance;
      if(account <= 0.0)
      {
         NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_INVALID,
                           "account equity/balance is zero or negative");
         return r;
      }
      budget = account * cfg.risk_percent / 100.0;

      // Money risked per 1.0 lot over this stop distance.
      const double perLot = NeoFLRisk_MoneyAtRisk(1.0, stopDistance, spec);
      if(perLot <= 0.0)
      {
         NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_INVALID,
                           "cannot value the stop distance; refusing to size blind");
         return r;
      }
      desired = budget / perLot;
      basis   = StringFormat("%s=%.2f risk=%.2f%% budget=%.2f per_lot=%.2f",
                             (cfg.model == NEOFL_RISK_PERCENT_EQUITY ? "equity" : "balance"),
                             account, cfg.risk_percent, budget, perLot);
   }

   //--- Apply the hard ceiling before normalization, so the cap is real.
   if(cfg.hard_max_lot > 0.0 && desired > cfg.hard_max_lot)
      desired = cfg.hard_max_lot;

   if(cfg.max_total_exposure_lot > 0.0)
   {
      const double open = NeoFLRisk_OpenExposure(symbol, magic);
      const double room = cfg.max_total_exposure_lot - open;
      if(room <= 0.0)
      {
         NeoFLDecision_Set(r.decision, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                           StringFormat("exposure limit reached: %.2f of %.2f lots open",
                                        open, cfg.max_total_exposure_lot), basis);
         return r;
      }
      if(desired > room) desired = room;
   }

   if(desired > spec.volume_max) desired = spec.volume_max;

   //--- The critical case: is the smallest tradable size already too much risk?
   //
   //    On a small account with a wide stop this happens routinely. Trading the
   //    minimum anyway would exceed the configured risk -- quietly, on every such
   //    trade -- which makes "risk percent" meaningless. Refuse unless explicitly
   //    overridden.
   if(desired < spec.volume_min)
   {
      const double minRisk = NeoFLRisk_MoneyAtRisk(spec.volume_min, stopDistance, spec);
      const double minPct  = (equity > 0.0) ? (minRisk / equity * 100.0) : 0.0;

      if(!cfg.allow_min_lot_override)
      {
         NeoFLDecision_Set(r.decision, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                           StringFormat("minimum lot %.2f risks %.2f (%.2f%%), above the %.2f budget; "
                                        "stop too wide for this account",
                                        spec.volume_min, minRisk, minPct, budget),
                           basis);
         return r;
      }

      desired = spec.volume_min;   // explicit override: knowingly over-risking
   }

   //--- Floor onto the broker's grid. Never round up.
   double volume = NeoFLRisk_FloorToStep(desired, spec);

   if(volume < spec.volume_min || volume <= 0.0)
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        StringFormat("normalized volume %.4f is below the broker minimum %.4f",
                                     volume, spec.volume_min), basis);
      return r;
   }

   const double risk = NeoFLRisk_MoneyAtRisk(volume, stopDistance, spec);

   r.approved     = true;
   r.volume       = volume;
   r.risk_money   = risk;
   r.risk_percent = (equity > 0.0) ? (risk / equity * 100.0) : 0.0;

   NeoFLDecision_Set(r.decision, NEOFL_VERDICT_PROCEED, NEOFL_DATA_OK,
                     StringFormat("size %.2f lots risking %.2f (%.2f%% of equity)",
                                  volume, risk, r.risk_percent),
                     StringFormat("%s stop_distance=%.5f min=%.2f step=%.2f cap=%.2f",
                                  basis, stopDistance, spec.volume_min,
                                  spec.volume_step, cfg.hard_max_lot));
   return r;
}

#endif // __NEOFL_RISK_MQH__
