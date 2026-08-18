"""Symbol resolution rules from the canon.

The canon is explicit that matching must be semantic, not substring: `GOLD` and the
XAUUSD broker variants are gold; `BTCXAU` is not, because there XAU is the quote
currency of a crypto cross.

These cases are mirrored by the MQL5 self-test script in
CORE/NeoFL_SymbolResolver/NeoFL_SymbolResolver_SelfTest.mq5 -- keep them in step.
"""

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "python"))

from neofl_core.symbol_resolver import AssetClass, classify, is_gold, normalize  # noqa: E402


class GoldRecognitionTest(unittest.TestCase):
    """Canon: the resolver identifies the base gold instrument, not an exact name."""

    VALID_GOLD = [
        "XAUUSD",
        "XAUUSDm",
        "XAUUSD.a",
        "XAUUSD.pro",
        "PREFIX_XAUUSD_SUFFIX",
        "GOLD",
        "GOLDm",
        "xauusd",
        "XAUUSD.raw",
        "fx.XAUUSD.c",
        "XAUUSD-5",
    ]

    def test_valid_gold_symbols_resolve(self):
        for symbol in self.VALID_GOLD:
            with self.subTest(symbol=symbol):
                self.assertTrue(is_gold(symbol), f"{symbol} should resolve as gold")

    def test_gold_resolves_to_canonical_base_symbol(self):
        for symbol in self.VALID_GOLD:
            with self.subTest(symbol=symbol):
                self.assertEqual(classify(symbol).base_symbol, "XAUUSD")

    def test_broker_symbol_is_preserved_verbatim(self):
        """Execution must use the broker's own name, not the canonical one."""
        self.assertEqual(classify("fx.XAUUSD.c").broker_symbol, "fx.XAUUSD.c")


class GoldRejectionTest(unittest.TestCase):
    """Canon: BTCXAU is not gold merely because the string contains XAU."""

    def test_btcxau_is_rejected(self):
        info = classify("BTCXAU")
        self.assertNotEqual(info.asset_class, AssetClass.GOLD)
        self.assertFalse(info.valid)
        self.assertIn("quote", info.reject_reason)

    def test_other_xau_crosses_are_rejected(self):
        for symbol in ("ETHXAU", "BTCXAU.pro", "SOLXAU", "btcxau"):
            with self.subTest(symbol=symbol):
                self.assertFalse(is_gold(symbol))

    def test_unrelated_instruments_are_not_gold(self):
        for symbol in ("EURUSD", "BTCUSD", "US500", "US100", "US30", "NAS100"):
            with self.subTest(symbol=symbol):
                self.assertFalse(is_gold(symbol))

    def test_empty_and_junk_input(self):
        self.assertFalse(is_gold(""))
        self.assertFalse(is_gold("...."))
        self.assertFalse(is_gold("12345"))


class NormalizationTest(unittest.TestCase):
    def test_strips_separators_digits_and_case(self):
        self.assertEqual(normalize("fx.XAUUSD.pro_m"), "FXXAUUSDPROM")
        self.assertEqual(normalize("xau-usd"), "XAUUSD")
        self.assertEqual(normalize("XAUUSD-5"), "XAUUSD")

    def test_non_gold_quote_currency_still_resolves_as_gold(self):
        """XAU as base against a non-USD quote is still the gold instrument."""
        info = classify("XAUEUR")
        self.assertEqual(info.asset_class, AssetClass.GOLD)
        self.assertEqual(info.quote, "EUR")
        self.assertEqual(info.base_symbol, "XAUEUR")


class MirrorConsistencyTest(unittest.TestCase):
    """The MQL5 module and this reference must stay in step."""

    def test_mql5_module_covers_the_same_cases(self):
        selftest = (
            REPO_ROOT / "CORE" / "NeoFL_SymbolResolver" / "NeoFL_SymbolResolver_SelfTest.mq5"
        ).read_text(encoding="utf-8")
        for symbol in ("XAUUSD", "GOLD", "PREFIX_XAUUSD_SUFFIX", "BTCXAU", "ETHXAU"):
            with self.subTest(symbol=symbol):
                self.assertIn(symbol, selftest)

    def test_mql5_module_does_not_use_naive_substring_match(self):
        """A bare StringFind("XAU") would wrongly accept BTCXAU."""
        module = (
            REPO_ROOT / "CORE" / "NeoFL_SymbolResolver" / "NeoFL_SymbolResolver.mqh"
        ).read_text(encoding="utf-8")
        self.assertIn("NeoFLSym_IsQuote", module)
        self.assertIn("NeoFLSym_GoldQuoteOrEmpty", module)


if __name__ == "__main__":
    unittest.main()
