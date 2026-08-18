"""The repository must keep the shape and safety properties the v2 canon requires.

Cheap structural guards so drift is caught by the suite rather than by review.
"""

import os
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# v2 canon: shared Core, seven independent strategies, observer, scripts, external brain.
CORE_ENGINES = [
    "Core", "Engine", "Risk", "AutoCapital", "Execution", "Position",
    "Bucket", "Straddle", "Stop", "Breakeven", "Trailing", "TradeState",
    "SymbolResolver", "MarketData", "Session", "Calendar", "DataValidation",
    "Logger", "Diagnostics",
]

STRATEGIES = ["ARK", "JOBBING", "PRICE_ACTION", "GOLD", "FX", "BTC", "INDICES"]

REQUIRED_DIRECTORIES = [
    "docs/product", "docs/architecture", "docs/ai",
    "OBSERVER", "SCRIPTS", "DATA", "EXTERNAL_BRAIN", "DEPLOYMENTS",
    "BACKTEST", "python", "tests", "legacy",
]

REQUIRED_FILES = [
    "README.md",
    "CLAUDE.md",
    "CHANGELOG.md",
    ".gitignore",
    "docs/product/HANDOFF_DIRECTIVE.md",
    "docs/product/MASTER_ARCHITECTURE_v2.md",
    "docs/product/ENGINE_OBSERVER_SCRIPTS_LAYER.md",
    "docs/product/MASTER_UNIVERSE_CANON.md",
    "docs/product/MASTER_SPEC_v1.0.md",
    "docs/product/DECISIONS.md",
    "docs/architecture/ARCHITECTURE.md",
    "docs/architecture/SOURCE_INVENTORY.md",
    "docs/ai/DEVELOPMENT_WORKFLOW.md",
]

SECRET_PATTERNS = [".env", "*.key", "*.pem", "secrets/"]

# Canon: BTCXAU contains "XAU" but is not gold. Must never appear as a tradable symbol.
FORBIDDEN_INSTRUMENTS = ["BTCXAU", "ETHXAU"]

# Modules whose job is to REJECT these instruments, and which must therefore name them.
# Every file here has tests elsewhere asserting the rejection actually happens — being
# on this list buys an exemption from the text scan, not from proving the behavior.
#
# Adding a file here is a deliberate act. A new module that mentions a forbidden
# instrument should fail this test until someone justifies it.
REJECTION_AUTHORITIES = {
    "NeoFL_SymbolResolver.mqh",           # asserted by NeoFL_SymbolResolver_SelfTest.mq5
    "NeoFL_SymbolResolver_SelfTest.mq5",
    "symbol_resolver.py",                 # asserted by test_symbol_resolver.py
    "webhooks.py",                        # asserted by test_gateway.py ContentValidityTest
    "normalizers.py",                     # asserted by test_gateway.py InstrumentMappingTest
}


class RepositoryContractTest(unittest.TestCase):
    def test_core_engine_directories_exist(self):
        for engine in CORE_ENGINES:
            with self.subTest(engine=engine):
                self.assertTrue((REPO_ROOT / "CORE" / f"NeoFL_{engine}").is_dir())

    def test_every_strategy_has_module_backtest_and_deployment(self):
        """Seven independent strategies, each independently backtestable and deployable."""
        for strategy in STRATEGIES:
            with self.subTest(strategy=strategy):
                self.assertTrue((REPO_ROOT / "STRATEGIES" / strategy).is_dir())
                self.assertTrue((REPO_ROOT / "BACKTEST" / strategy).is_dir())
                self.assertTrue((REPO_ROOT / "DEPLOYMENTS" / f"NeoFL_{strategy}").is_dir())

    def test_required_directories_exist(self):
        for relative in REQUIRED_DIRECTORIES:
            with self.subTest(directory=relative):
                self.assertTrue((REPO_ROOT / relative).is_dir())

    def test_required_files_exist(self):
        for relative in REQUIRED_FILES:
            with self.subTest(file=relative):
                path = REPO_ROOT / relative
                self.assertTrue(path.is_file())
                self.assertGreater(path.stat().st_size, 0)

    def test_superseded_spec_is_marked_superseded(self):
        """v1.0 must stay visibly superseded so no agent implements from it."""
        spec = (REPO_ROOT / "docs" / "product" / "MASTER_SPEC_v1.0.md").read_text(encoding="utf-8")
        self.assertIn("SUPERSEDED", spec)

    def test_gitignore_blocks_secrets(self):
        gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
        for pattern in SECRET_PATTERNS:
            with self.subTest(pattern=pattern):
                self.assertIn(pattern, gitignore)

    def test_no_forbidden_instruments_outside_legacy_and_docs(self):
        """Gold only: no module may treat BTCXAU/ETHXAU as tradable.

        Exempt by design:
          - legacy/ is preserved as-is and never executed
          - docs/ and tests/ discuss these symbols deliberately
          - the symbol resolver is the designated rejection authority, so it is the
            one place that must name them; its own tests assert they are rejected
        """
        exempt_dirs = {"legacy", "docs", "tests", ".venv", ".git"}
        searchable = [
            path
            for extension in ("*.py", "*.mq5", "*.mqh", "*.json", "*.yaml", "*.yml")
            for path in REPO_ROOT.rglob(extension)
            if exempt_dirs.isdisjoint(path.parts) and path.name not in REJECTION_AUTHORITIES
        ]
        for path in searchable:
            content = path.read_text(encoding="utf-8", errors="ignore")
            for instrument in FORBIDDEN_INSTRUMENTS:
                with self.subTest(file=path.name, instrument=instrument):
                    self.assertNotIn(instrument, content)


class BuildToolingTest(unittest.TestCase):
    """The compile loop is the fastest real verification available; keep it wired up."""

    def test_compile_script_present_and_executable(self):
        script = REPO_ROOT / "tools" / "mql5_compile.sh"
        self.assertTrue(script.is_file())
        self.assertTrue(os.access(script, os.X_OK), "mql5_compile.sh must be executable")

    def test_compile_script_does_not_trust_exit_code(self):
        """MetaEditor exits 0 on failure and 1 on success; the log is authoritative."""
        script = (REPO_ROOT / "tools" / "mql5_compile.sh").read_text(encoding="utf-8")
        self.assertIn("Result:", script)
        self.assertIn("UTF-16LE", script)

    def test_running_doc_exists(self):
        self.assertTrue((REPO_ROOT / "docs" / "testing" / "RUNNING.md").is_file())


if __name__ == "__main__":
    unittest.main()
