import os
from pathlib import Path
import tempfile
import unittest

import PySide6

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QUrl, QMetaObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlComponent


# STRATUM Issue KAN-26 (#63): deterministic tests for the GNSS BAD/GOOD/BEST classifier.
# StratumGnssQuality is pure QtQuick with injected inputs, so it mounts standalone. Tests
# disable its 1 Hz timer and step evaluate() to simulate per-second evaluations.
class StratumGnssQualityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.root = Path(__file__).resolve().parents[2]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        src = self.root / "src/Toolbar/StratumGnssQuality.qml"
        (self.folder / "StratumGnssQuality.qml").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
        self.engine = QQmlEngine()
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(self.folder / "StratumGnssQuality.qml")))
        self.assertFalse(self.component.isError(), [e.toString() for e in self.component.errors()])
        self.item = self.component.create()
        self.assertIsNotNone(self.item)
        self.item.setProperty("running", False)  # step evaluate() manually

    def tearDown(self):
        if getattr(self, "item", None) is not None:
            self.item.deleteLater()
        self.engine.deleteLater()
        self.app.processEvents()
        self.temp.cleanup()

    def set(self, **kwargs):
        for key, value in kwargs.items():
            self.item.setProperty(key, value)

    def quality(self):
        return self.item.property("quality")

    def reason(self):
        return self.item.property("reason")

    def evaluate(self, times=1):
        for _ in range(times):
            QMetaObject.invokeMethod(self.item, "evaluate")

    def best_sample(self, **over):
        s = dict(connected=True, fixType=3, satellites=12, hdop=1.0, ephM=1.5, epvM=3.0, sampleAgeSec=0.0)
        s.update(over)
        self.set(**s)

    # ---- Initial / connection ----
    def test_initial_is_bad(self):
        self.assertEqual(self.quality(), "BAD")

    def test_disconnected_is_bad(self):
        self.best_sample()
        self.evaluate(3)
        self.set(connected=False)
        self.evaluate(1)
        self.assertEqual(self.quality(), "BAD")
        self.assertEqual(self.reason(), "DISCONNECTED")

    # ---- Promotion / hysteresis ----
    def test_best_after_three_seconds(self):
        self.best_sample()
        self.evaluate(2)
        self.assertEqual(self.quality(), "BAD")   # not yet promoted
        self.evaluate(1)
        self.assertEqual(self.quality(), "BEST")  # 3 consecutive BEST
        self.assertEqual(self.reason(), "VALID")

    def test_good_satellite_bottleneck(self):
        # 11 sats caps the result at GOOD even though every other metric is BEST-grade.
        self.best_sample(satellites=11, hdop=0.8, ephM=1.0, epvM=2.0)
        self.evaluate(3)
        self.assertEqual(self.quality(), "GOOD")
        self.assertEqual(self.reason(), "VALID")

    # ---- Weakest-link ----
    def test_weakest_link_epv_caps_at_good(self):
        # All BEST except EPV just past the BEST limit (3.01 > 3.0) -> GOOD, never averaged up.
        self.best_sample(epvM=3.01)
        self.evaluate(3)
        self.assertEqual(self.quality(), "GOOD")

    # ---- Boundaries (inclusive <= / >=) ----
    def test_good_at_exact_limits(self):
        self.best_sample(satellites=8, hdop=2.0, ephM=5.0, epvM=8.0)
        self.evaluate(3)
        self.assertEqual(self.quality(), "GOOD")

    def test_best_at_exact_limits(self):
        self.best_sample(satellites=12, hdop=1.0, ephM=1.5, epvM=3.0)
        self.evaluate(3)
        self.assertEqual(self.quality(), "BEST")

    def test_seven_sats_is_bad(self):
        self.best_sample(satellites=7, hdop=0.8, ephM=1.0, epvM=2.0)
        self.evaluate(3)
        self.assertEqual(self.quality(), "BAD")
        self.assertEqual(self.reason(), "BELOW_THRESHOLD")

    # ---- Minor downgrade debounce ----
    def test_eph_just_over_downgrades_to_bad(self):
        self.best_sample()
        self.evaluate(3)
        self.assertEqual(self.quality(), "BEST")
        self.set(ephM=5.01)            # just past the GOOD limit -> BELOW_THRESHOLD
        self.evaluate(1)
        self.assertEqual(self.quality(), "BEST")   # debouncing (1 of 2)
        self.evaluate(1)
        self.assertEqual(self.quality(), "BAD")
        self.assertEqual(self.reason(), "BELOW_THRESHOLD")

    def test_pending_downgrade_cancelled_on_recovery(self):
        self.best_sample()
        self.evaluate(3)
        self.assertEqual(self.quality(), "BEST")
        self.set(ephM=5.01)            # would downgrade
        self.evaluate(1)               # pending (1 of 2)
        self.set(ephM=1.5)             # recovers before the 2nd consecutive bad eval
        self.evaluate(1)
        self.assertEqual(self.quality(), "BEST")

    # ---- Immediate downgrades (bypass debounce) ----
    def test_lost_fix_immediate_bad(self):
        self.best_sample()
        self.evaluate(3)
        self.assertEqual(self.quality(), "BEST")
        self.set(fixType=2)            # 2D
        self.evaluate(1)
        self.assertEqual(self.quality(), "BAD")
        self.assertEqual(self.reason(), "LOST_FIX")

    def test_stale_immediate_bad(self):
        self.best_sample()
        self.evaluate(3)
        self.assertEqual(self.quality(), "BEST")
        self.set(sampleAgeSec=3.1)
        self.evaluate(1)
        self.assertEqual(self.quality(), "BAD")
        self.assertEqual(self.reason(), "STALE")

    def test_missing_field_is_bad(self):
        self.best_sample()
        self.evaluate(3)
        self.set(hdop=float("nan"))
        self.evaluate(1)
        self.assertEqual(self.quality(), "BAD")
        self.assertEqual(self.reason(), "MISSING_FIELD")

    # ---- Reset on vehicle change ----
    def test_reset_clears_quality(self):
        self.best_sample()
        self.evaluate(3)
        self.assertEqual(self.quality(), "BEST")
        QMetaObject.invokeMethod(self.item, "reset")
        self.assertEqual(self.quality(), "BAD")


if __name__ == "__main__":
    unittest.main()
