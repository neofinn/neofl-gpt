//+------------------------------------------------------------------+
//| NeoFL_Straddle.mqh                                               |
//| Core module. Straddle sizing and bucket arithmetic.              |
//| Computes sizes and levels. Places no orders.                     |
//+------------------------------------------------------------------+
//
// Product owner's rule: main entry fixed at 0.01; the straddle is sized from the lots
// needed to cover the loss between the main entry and the straddle entry, so the gap
// always returns to zero.
//
// Main long Vm at Em, moving against us to Es where a short straddle Vs opens.
// gap = Em - Es. Bucket P/L at price P:
//
//     B(P) = (P - Em)*Vm*k + (Es - P)*Vs*k
//
// Setting B = 0 at D past the straddle entry gives:
//
//     Vs = Vm * (gap + D) / D
//
// "Cover the loss" describes a FAMILY of sizes, not one. All reach zero; they differ in
// how far price must travel. Two readings are therefore both supported:
//
//   RATIO           Vs = Vm*(n+1), recovers in gap/n. Gap-INDEPENDENT -- a 20 point and
//                   a 200 point gap both give 0.03 at n=2. This is what a fixed 0.03 has
//                   always been doing.
//
//   FIXED_DISTANCE  Vs = Vm*(gap+D)/D, recovers within D whatever the gap. Size GROWS
//                   with the gap, so exposure is unbounded as the gap widens.
//
// THE DELTA-NEUTRAL HAZARD
// ------------------------
// As Vs approaches Vm the recovery distance runs to infinity: the legs offset exactly,
// bucket P/L freezes, and no price recovers it. Vs > Vm is a requirement, not a
// preference. This module refuses rather than returning a plausible number.
//
// ROUNDING GOES UP HERE
// ---------------------
// Risk sizing floors so a trade never risks more than authorised. Straddle sizing must
// CEIL: flooring under-covers the gap, so the bucket stops short of zero and the
// handover never fires.
//
#ifndef __NEOFL_STRADDLE_MQH__
#define __NEOFL_STRADDLE_MQH__

#include "../NeoFL_DataValidation/NeoFL_DataQuality.mqh"

enum ENUM_NEOFL_STRADDLE_MODE
{
   NEOFL_STRADDLE_RATIO          = 0,  // Vs = Vm*(n+1); size fixed, distance follows gap
   NEOFL_STRADDLE_FIXED_DISTANCE = 1   // Vs = Vm*(gap+D)/D; distance fixed, size follows gap
};

struct NeoFLStraddleSizing
{
   bool          approved;
   double        volume;
   double        gap;
   double        recovery_distance;  // actual, after rounding
   double        zero_price;         // where the bucket reaches zero
   double        coverage;           // >= 1.0 means fully covered
   NeoFLDecision decision;
};

//--- Round UP onto the broker's volume grid. See header on rounding direction.
double NeoFLStr_CeilToStep(const double volume, const double vmin, const double vstep)
{
   if(volume <= vmin) return vmin;
   const double steps = MathCeil((volume - vmin) / vstep - 1e-9);
   int digits = 8;
   for(int d = 0; d <= 8; d++)
      if(MathAbs(vstep - NormalizeDouble(vstep, d)) < 1e-9) { digits = d; break; }
   return NormalizeDouble(vmin + steps * vstep, digits);
}

//--- Vs = Vm*(gap+D)/D
double NeoFLStr_RequiredVolume(const double mainVolume, const double gap, const double D)
{
   if(D <= 0.0) return 0.0;
   return mainVolume * (gap + D) / D;
}

//--- Vs = Vm*(n+1)
double NeoFLStr_VolumeForRatio(const double mainVolume, const double n)
{
   if(n <= 0.0) return 0.0;
   return mainVolume * (n + 1.0);
}

//+------------------------------------------------------------------+
//| Size the recovery straddle.                                       |
//+------------------------------------------------------------------+
NeoFLStraddleSizing NeoFLStr_Size(const string symbol,
                                  const double mainVolume,
                                  const double mainEntry,
                                  const double straddleEntry,
                                  const bool   mainIsLong,
                                  const ENUM_NEOFL_STRADDLE_MODE mode,
                                  const double recoveryRatio,
                                  const double recoveryDistance,
                                  const double volumeMin,
                                  const double volumeMax,
                                  const double volumeStep,
                                  const double straddleMaxLot)
{
   NeoFLStraddleSizing r;
   r.approved = false;
   r.volume = 0.0; r.recovery_distance = 0.0; r.zero_price = 0.0; r.coverage = 0.0;
   r.gap = mainIsLong ? (mainEntry - straddleEntry) : (straddleEntry - mainEntry);
   NeoFLDecision_Begin(r.decision, "Straddle", symbol);

   const string inputs = StringFormat("main=%.2f@%.5f straddle_entry=%.5f gap=%.5f mode=%s",
                                      mainVolume, mainEntry, straddleEntry, r.gap,
                                      mode == NEOFL_STRADDLE_RATIO ? "RATIO" : "FIXED_DISTANCE");

   if(r.gap <= 0.0)
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_OK,
                        "straddle entry is not adverse to the main entry; no loss to cover",
                        inputs);
      return r;
   }

   if(mainVolume <= 0.0)
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_INVALID,
                        "main volume is zero or negative", inputs);
      return r;
   }

   double exact = 0.0;
   if(mode == NEOFL_STRADDLE_FIXED_DISTANCE)
   {
      if(recoveryDistance <= 0.0)
      {
         NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_OK,
                           "recovery distance must be positive", inputs);
         return r;
      }
      exact = NeoFLStr_RequiredVolume(mainVolume, r.gap, recoveryDistance);
   }
   else
   {
      if(recoveryRatio <= 0.0)
      {
         NeoFLDecision_Set(r.decision, NEOFL_VERDICT_BLOCKED, NEOFL_DATA_OK,
                           "recovery ratio must be positive; n -> 0 is delta-neutral", inputs);
         return r;
      }
      exact = NeoFLStr_VolumeForRatio(mainVolume, recoveryRatio);
   }

   double volume = NeoFLStr_CeilToStep(exact, volumeMin, volumeStep);

   const double cap = (straddleMaxLot > 0.0) ? MathMin(volumeMax, straddleMaxLot) : volumeMax;
   if(volume > cap)
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        StringFormat("required straddle %.2f exceeds the cap %.2f; "
                                     "capping would under-cover the gap", volume, cap),
                        inputs);
      return r;
   }

   // A straddle no larger than the main is the delta-neutral case: the legs offset and
   // no price ever brings the bucket to zero.
   if(volume <= mainVolume)
   {
      NeoFLDecision_Set(r.decision, NEOFL_VERDICT_DECLINE, NEOFL_DATA_OK,
                        StringFormat("straddle %.2f is not larger than main %.2f; bucket "
                                     "would be delta-neutral and could never reach zero",
                                     volume, mainVolume),
                        inputs);
      return r;
   }

   // Actual distance after rounding: D = gap*Vm / (Vs - Vm)
   r.recovery_distance = r.gap * mainVolume / (volume - mainVolume);
   r.zero_price = mainIsLong ? (straddleEntry - r.recovery_distance)
                             : (straddleEntry + r.recovery_distance);
   r.coverage = (exact > 0.0) ? volume / exact : 0.0;
   r.volume   = volume;
   r.approved = true;

   NeoFLDecision_Set(r.decision, NEOFL_VERDICT_PROCEED, NEOFL_DATA_OK,
                     StringFormat("straddle %.2f covers the %.5f gap; bucket zero at %.5f "
                                  "(%.5f from straddle entry)",
                                  volume, r.gap, r.zero_price, r.recovery_distance),
                     inputs);
   return r;
}

//--- Bucket P/L for a two-leg bucket at an arbitrary price.
double NeoFLStr_BucketPL(const double mainVolume, const double mainEntry, const bool mainIsLong,
                         const double strVolume, const double strEntry,
                         const double price, const double moneyPerUnitPerLot)
{
   const double mainDir = mainIsLong ? 1.0 : -1.0;
   const double strDir  = mainIsLong ? -1.0 : 1.0;
   return ((price - mainEntry) * mainDir * mainVolume
         + (price - strEntry)  * strDir  * strVolume) * moneyPerUnitPerLot;
}

#endif // __NEOFL_STRADDLE_MQH__
