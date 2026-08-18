# What's needed from you — plain English

Ordered by what unblocks the most. Everything else is either built or something I can do
without you.

---

## 1. ARK's trading rules — nobody else has these

**What:** How ARK decides to trade. What it looks at, what makes it enter, what makes it stay out.

**Why it matters:** ARK is one of your seven strategies and it is completely stuck. The old
`NeoFL_ARK_7_1_MT5.mq5` says outright that the real rules go into `ARKSignal()` — and that
function is empty. Nothing anywhere in your files describes them.

**What happens without it:** ARK never gets built. I will not invent trading rules, and
guessing at them would be worse than leaving it empty.

**Note:** the file *named* ARK in your backtest folder is actually today's Jobbing strategy.
So "ARK" as it exists today is a name with no strategy behind it.

---

## 2. Two risk decisions — these block the Execution engine

**What:**

- **How should position size be decided?** A fixed lot every time, or a percentage of the
  account, or both available and you pick per strategy?
- **Does the 0.01 hard cap stay?** Your old v3.85 build capped every main entry at 0.01 lots
  as a deliberate safety rail. Nothing in your newer architecture mentions it, so I do not
  know if you still want it.

**Why it matters:** Execution is the next Core piece to build, and it is the first one that
actually sends orders. I am not willing to pick your risk numbers for you.

**What happens without it:** The Execution engine stays unbuilt, and with it steps 5 through
16 of your build order.

---

## 3. Run the research script — one click, big payoff

**What:** In MT5, drag `NeoFL_WicklessResearch` (under Scripts → NeoFL) onto a gold chart.
It reads history, places no orders, prints a table.

**Why it matters:** Your whole strategy rests on "wickless candle, price comes back, breakout
follows." Nobody has ever measured whether that is true. The script measures it — and it
also runs the *opposite* trade on every same signal as a control.

If both columns look the same, the candle shape is telling you nothing and the pattern is
just price leaving a level, which it has to do in one direction or the other. That would be
disappointing and worth knowing.

**What happens without it:** Every suggestion I make about improving entries stays guesswork.

---

## 4. Which end of the wickless candle?

**What:** You said the level is at "the wickless end". The code always uses the candle's
**open**.

For a perfectly clean candle those are the same thing. But your setting allows up to 15%
wick, so a candle can qualify with a small wick on one end and none on the other. The code
still takes the open.

**Why it matters:** If you meant "whichever end has no wick", then on some candles the level
is being placed at the wrong price — and every trade from that level is measured from the
wrong point.

**What happens without it:** It stays as the open. Which may well be right — I just cannot
confirm it.

---

## 5. Your straddle recovery speed

**What:** Both work and both fully cover the loss:

- **0.02 lots** — breaks even when price returns to your original entry
- **0.03 lots** — breaks even halfway back *(what your old build did)*

**Why it matters:** It is one setting in the EA, no rebuild needed. 0.03 recovers sooner and
holds slightly more exposure. On your account the difference is about 1 cent per dollar of
gold movement, so it is genuinely your preference rather than a safety question.

**What happens without it:** It stays on 0.02.

---

## 6. Confirm the numbers on your account

**What:** Restart the EA and send me the startup block from the **Experts** tab. It now
prints your broker's contract size and tick value.

**Why it matters:** All my straddle maths assumed 0.01 lot costs 1 cent per dollar of gold
movement. That is very probably right for a cent account, but I inferred it — I have not
seen your broker confirm it.

**What happens without it:** The maths is probably fine, but "probably" is doing work I would
rather remove.

---

## 7. Backtesting — needs your credentials, so it has to be you

**What:** Run the EA in MT5's Strategy Tester yourself.

**Why it matters:** **Nothing in this system has ever been backtested.** Not by me, not by
anyone. Your v3.86 is trading live on code I have verified compiles and calculates
correctly — which is not the same as evidence that it makes money.

The Strategy Tester needs your broker login. I will not handle your credentials, so this one
cannot be delegated.

**What happens without it:** You are trading on logic that has been checked but never tested.

---

## Not needed from you

For completeness, so you know where the line is:

- The gateway, database and MT5 bridge all run with no setup — it finds your terminal itself
- No API keys, no accounts, no installs
- No MT5 settings to change (except `PermissionsTrade`, below)

**One loose end from earlier:** MetaTrader's own AI assistant still has `PermissionsTrade = 1`,
which lets it place trades through a third-party service. Your decision D-001 says AI never
gets order authority. Setting is under Tools → Options.
