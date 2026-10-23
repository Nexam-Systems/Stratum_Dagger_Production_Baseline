import os
from pathlib import Path
import tempfile
import unittest

import PySide6

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlComponent, QJSValue
from PySide6.QtTest import QTest


# STRATUM Issue #4 / Phase 0: deterministic logic tests for the RTL Point-of-No-Return
# estimator. The estimator depends only on QtQuick and injected telemetry, so it mounts
# standalone with a mock vehicle whose facts are driven by scalar harness properties. The
# internal 1 Hz timer is disabled (autoTick:false); tests call advance(dt) directly.
HARNESS = '''import QtQuick

Item {
    id: harness
    readonly property var estimator: estimator

    property bool inConnected: true
    property bool inArmed: false
    property bool inFlying: false
    property bool inHasBattery: true
    property real inVoltage: 22.8
    property real inCurrent: 87.72
    property real inPercent: 60
    property real inGroundSpeed: 27.78
    property real inDistanceToHome: 5000
    property int  inChargeState: 1

    QtObject { id: vFact; property real rawValue: harness.inVoltage }
    QtObject { id: iFact; property real rawValue: harness.inCurrent }
    QtObject { id: pctFact; property real rawValue: harness.inPercent }
    QtObject { id: csFact; property real rawValue: harness.inChargeState }
    QtObject {
        id: battObj
        property var voltage: vFact
        property var current: iFact
        property var percentRemaining: pctFact
        property var chargeState: csFact
    }
    QtObject {
        id: batteriesModel
        property int count: harness.inHasBattery ? 1 : 0
        function get(index) { return battObj }
    }
    QtObject { id: gsFact; property real rawValue: harness.inGroundSpeed }
    QtObject { id: dhFact; property real rawValue: harness.inDistanceToHome }
    QtObject { id: factsObj; property var groundSpeed: gsFact; property var distanceToHome: dhFact }
    QtObject { id: linkObj; property bool communicationLost: false }
    QtObject {
        id: vehicleObj
        property bool initialConnectComplete: harness.inConnected
        property bool armed: harness.inArmed
        property bool flying: harness.inFlying
        property var batteries: batteriesModel
        property var vehicle: factsObj
        property var vehicleLinkManager: linkObj
    }

    RTLPointOfNoReturnEstimator {
        id: estimator
        vehicle: vehicleObj
        autoTick: false
    }
}
'''


class RTLPointOfNoReturnTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.root = Path(__file__).resolve().parents[2]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        src = self.root / "src/FlyView/RTLPointOfNoReturnEstimator.qml"
        (self.folder / "RTLPointOfNoReturnEstimator.qml").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
        self.engine = QQmlEngine()
        self.errors = []
        self.engine.warnings.connect(lambda errs: self.errors.extend(e.toString() for e in errs))
        path = self.folder / "Harness.qml"
        path.write_text(HARNESS, encoding="utf-8")
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(path)))
        self.assertFalse(self.component.isError(), [e.toString() for e in self.component.errors()])
        self.item = self.component.create()
        self.assertIsNotNone(self.item)
        self.est = self.item.property("estimator")

    def tearDown(self):
        if getattr(self, "item", None) is not None:
            self.item.deleteLater()
        self.engine.deleteLater()
        self.app.processEvents()
        self.temp.cleanup()

    def set_harness(self, **kwargs):
        for key, value in kwargs.items():
            self.item.setProperty(key, value)

    def set_est(self, **kwargs):
        for key, value in kwargs.items():
            self.est.setProperty(key, value)

    def advance(self, dt=1.0):
        result = self.engine.newQObject(self.est).property("advance").call([QJSValue(float(dt))])
        self.assertFalse(result.isError(), result.toString())
        QTest.qWait(5)

    def configure_worked_example(self):
        # Contract Section 5 worked example -> 00:59 / ENERGY / UNCALIBRATED.
        self.set_est(powerFilterTauSec=0.0, energyRemainingOverrideWh=300.0,
                     returnPowerOverrideW=2000.0, homeRadialRateOverrideMS=27.78,
                     reserveFraction=0.20, packNominalEnergyWh=570.0, rtlOverheadWh=20.0,
                     returnSpeedMS=27.78, totalDistanceLimitM=15000.0, distanceFlownM=5000.0)
        self.set_harness(inVoltage=22.8, inCurrent=87.72, inGroundSpeed=27.78,
                         inDistanceToHome=5000.0, inConnected=True)

    def test_worked_example_energy_pnr(self):
        self.configure_worked_example()
        self.advance()
        self.assertEqual(self.est.property("pnrReason"), "ENERGY")
        self.assertEqual(self.est.property("pnrStatus"), "UNCALIBRATED")
        self.assertEqual(self.est.property("pnrCountdownSeconds"), 59)
        self.assertAlmostEqual(self.est.property("energyMarginWh"), 66.0, delta=1.0)
        self.assertAlmostEqual(self.est.property("rtlEstimatedTimeSeconds"), 180.0, delta=1.0)

    def test_distance_limit_can_dominate(self):
        self.configure_worked_example()
        # Plenty of energy + low power so the 15 km budget is the binding limit (~90 s).
        self.set_est(energyRemainingOverrideWh=560.0, returnPowerOverrideW=300.0)
        self.set_harness(inCurrent=13.16)  # ~300 W outbound
        self.advance()
        self.assertEqual(self.est.property("pnrReason"), "DISTANCE")
        self.assertAlmostEqual(self.est.property("pnrCountdownSeconds"), 90, delta=2)

    def test_pnr_reached_when_reserve_already_breached(self):
        self.configure_worked_example()
        self.set_est(energyRemainingOverrideWh=100.0)  # below reserve + return cost
        self.advance()
        self.assertEqual(self.est.property("pnrStatus"), "PNR_REACHED")
        self.assertEqual(self.est.property("pnrCountdownSeconds"), 0)
        self.assertIn(self.est.property("pnrReason"), ("ENERGY", "BOTH"))

    def test_beyond_prediction_horizon(self):
        self.set_est(powerFilterTauSec=0.0, energyRemainingOverrideWh=560.0,
                     returnPowerOverrideW=200.0, homeRadialRateOverrideMS=0.0,
                     reserveFraction=0.20, packNominalEnergyWh=570.0, rtlOverheadWh=20.0,
                     returnSpeedMS=27.78, totalDistanceLimitM=15000.0, distanceFlownM=0.0)
        self.set_harness(inVoltage=22.8, inCurrent=8.8, inGroundSpeed=5.0, inDistanceToHome=100.0)
        self.advance()
        self.assertEqual(self.est.property("pnrStatus"), "BEYOND_HORIZON")
        self.assertEqual(self.est.property("pnrCountdownSeconds"), -1)

    def test_unknown_when_disconnected(self):
        self.configure_worked_example()
        self.set_harness(inConnected=False)
        self.advance()
        self.assertEqual(self.est.property("pnrStatus"), "UNKNOWN")
        self.assertEqual(self.est.property("pnrCountdownSeconds"), -1)

    def test_unknown_without_power_signal(self):
        self.configure_worked_example()
        self.set_harness(inVoltage=0.0)  # no valid electrical power
        self.advance()
        self.assertEqual(self.est.property("pnrStatus"), "UNKNOWN")

    def test_unknown_without_battery(self):
        self.configure_worked_example()
        self.set_harness(inHasBattery=False)
        self.advance()
        self.assertEqual(self.est.property("pnrStatus"), "UNKNOWN")

    def test_battery_critical_passthrough(self):
        self.configure_worked_example()
        self.set_harness(inChargeState=3)
        self.advance()
        self.assertTrue(self.est.property("batteryCritical"))

    def test_countdown_is_dynamic_not_fixed(self):
        self.configure_worked_example()
        self.advance()
        baseline = self.est.property("pnrCountdownSeconds")
        # Draining faster (more outbound power) must bring the PNR sooner.
        self.set_harness(inCurrent=150.0)
        self.set_est(returnPowerOverrideW=0.0)  # return power follows measured power
        self.advance()
        self.assertLess(self.est.property("pnrCountdownSeconds"), baseline)

    def test_uses_15km_total_distance_budget(self):
        self.assertEqual(self.est.property("totalDistanceLimitM"), 15000)
        self.assertAlmostEqual(self.est.property("reserveFraction"), 0.20, places=3)

    def _configure_flightworthy(self):
        # Valid in-flight inputs so the estimate computes once a verified takeoff occurs.
        self.set_est(powerFilterTauSec=0.0, energyRemainingOverrideWh=300.0,
                     returnPowerOverrideW=2000.0, homeRadialRateOverrideMS=0.0,
                     reserveFraction=0.20, packNominalEnergyWh=570.0, rtlOverheadWh=20.0,
                     returnSpeedMS=27.78, totalDistanceLimitM=15000.0)
        self.set_harness(inVoltage=22.8, inCurrent=87.72, inGroundSpeed=20.0,
                         inDistanceToHome=3000.0, inConnected=True)

    def test_takeoff_resets_flown_distance(self):
        self._configure_flightworthy()
        self.set_est(distanceFlownM=1234.0)             # stale value from a previous session
        self.set_harness(inArmed=True, inFlying=False)
        self.advance()                                  # on ground -> ground seen
        self.set_harness(inGroundSpeed=0.0, inFlying=True)
        self.advance()                                  # verified takeoff -> reset
        self.assertLess(self.est.property("distanceFlownM"), 50.0)
        self.assertEqual(self.est.property("pnrStatus"), "UNCALIBRATED")

    def test_reconnect_midflight_does_not_zero_flown_and_is_unknown(self):
        self._configure_flightworthy()
        self.set_harness(inArmed=True, inFlying=False)
        self.advance()                                  # ground
        self.set_harness(inFlying=True)
        self.advance()                                  # takeoff
        self.advance()
        self.advance()                                  # accumulate flown distance
        self.assertGreater(self.est.property("distanceFlownM"), 0.0)
        self.assertEqual(self.est.property("pnrStatus"), "UNCALIBRATED")
        # Lose the link mid-flight, then reconnect while still airborne.
        self.set_harness(inConnected=False)
        self.advance()
        self.set_harness(inConnected=True)
        self.advance()
        self.assertEqual(self.est.property("pnrStatus"), "UNKNOWN")
        self.assertEqual(self.est.property("pnrUnknownReason"), "MISSING_FLOWN_DISTANCE")
        self.assertGreater(self.est.property("distanceFlownM"), 0.0)   # never silently zeroed

    def test_startup_while_airborne_is_unknown(self):
        self._configure_flightworthy()
        self.set_harness(inArmed=True, inFlying=True)   # connect to an already-flying vehicle
        self.advance()
        self.assertEqual(self.est.property("pnrStatus"), "UNKNOWN")
        self.assertEqual(self.est.property("pnrUnknownReason"), "MISSING_FLOWN_DISTANCE")

    def test_fresh_takeoff_recovers_trusted_track(self):
        self._configure_flightworthy()
        self.set_harness(inArmed=True, inFlying=True)   # startup airborne -> unknown
        self.advance()
        self.assertEqual(self.est.property("pnrUnknownReason"), "MISSING_FLOWN_DISTANCE")
        self.set_harness(inFlying=False)
        self.advance()                                  # ground seen on the live link
        self.set_harness(inFlying=True)
        self.advance()                                  # verified new-flight takeoff
        self.assertEqual(self.est.property("pnrStatus"), "UNCALIBRATED")

    def test_no_engine_warnings(self):
        self.configure_worked_example()
        self.advance()
        self.assertFalse(self.errors, self.errors)


if __name__ == "__main__":
    unittest.main(verbosity=2)
