"""Legacy source is read-only reference material.

The handoff directive requires that superseded work be preserved, never deleted.
These tests fail loudly if preserved source disappears — especially the files the
v2 canon identifies as direct ancestors of current architecture.
"""

import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY = REPO_ROOT / "legacy"

EXPECTED_FAMILIES = [
    "gold-dual-engine-5.x-6.x",
    "ark-7.1-standalone",
    "candle-revisit-master-brain",
    "ark-jobbing-backtest-v3.00",
    "observer-network",
]

# Ancestors of current v2 architecture — the highest-value legacy assets.
CRITICAL_ANCESTORS = [
    # Straddle / recovery engine ancestor.
    "candle-revisit-master-brain/v3.85_BACKTEST_READY_PACKAGE/Include/NeoFL_MasterBrain_v3_85.mqh",
    # One of the two canon-confirmed latest observer components.
    "candle-revisit-master-brain/v3.85_BACKTEST_READY_PACKAGE/Include/NeoFL_Observer_Core_v2_00.mqh",
    # Named ARK, implements today's Jobbing (opening range).
    "ark-jobbing-backtest-v3.00/ARK/NeoFL_ARK_Backtest_v3_00.mq5",
]


class LegacyPreservationTest(unittest.TestCase):
    def test_all_families_present(self):
        for family in EXPECTED_FAMILIES:
            with self.subTest(family=family):
                self.assertTrue((LEGACY / family).is_dir())

    def test_critical_ancestors_preserved(self):
        for relative in CRITICAL_ANCESTORS:
            with self.subTest(file=relative):
                path = LEGACY / relative
                self.assertTrue(path.is_file())
                self.assertGreater(path.stat().st_size, 0)

    def test_inventory_documents_every_family(self):
        inventory = (REPO_ROOT / "docs" / "architecture" / "SOURCE_INVENTORY.md").read_text(
            encoding="utf-8"
        )
        for family in EXPECTED_FAMILIES:
            with self.subTest(family=family):
                self.assertIn(family, inventory)

    def test_inventory_records_the_ark_jobbing_name_collision(self):
        """The single most misleading thing in legacy/ must stay documented."""
        inventory = (REPO_ROOT / "docs" / "architecture" / "SOURCE_INVENTORY.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("NeoFL_ARK_Backtest_v3_00.mq5", inventory)
        self.assertIn("Jobbing", inventory)

    def test_legacy_source_count_has_not_shrunk(self):
        sources = list(LEGACY.rglob("*.mq5")) + list(LEGACY.rglob("*.mqh"))
        self.assertGreaterEqual(len(sources), 36)


if __name__ == "__main__":
    unittest.main()
