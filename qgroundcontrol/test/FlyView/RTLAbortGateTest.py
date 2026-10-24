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


# STRATUM Issue #42 / Block-1: deterministic tests for the Layer-1 RTL & Abort gate.
# RTLAbortGate depends only on QtQuick + injected vehicle/estimator mocks, so it mounts
# standalone. Hysteresis is disabled (hysteresisSeconds:0) so advance(dt) commits at once.
HARNESS = '''import QtQuick

Item {
    id: harness
    readonly property var gate: gate

    property bool   inArmed: true
    property bool   inFlying: true
    property string inFlightMode: "Hold"
    property real   inFlightTimeSec: 60

    property string inPnrStatus: "UNCALIBRATED"
    property int    inPnrCountdown: 600
    property bool   inValidated: false
    property bool   inBattCritical: false
    property real   inDistanceM: 1000

    QtObject { id: ftFact; property real rawValue: harness.inFlightTimeSec }
    QtObject { id: factsObj; property var flightTime: ftFact }
    QtObject {
        id: vehicleObj
        property bool armed: harness.inArmed
        property bool flying: harness.inFlying
        property string flightMode: harness.inFlightMode
        property var vehicle: factsObj
        property var coordinate: null
        property var homePosition: null
    }
    QtObject {
        id: estimatorObj
        property string pnrStatus: harness.inPnrStatus
        property int    pnrCountdownSeconds: harness.inPnrCountdown
        property bool   modelValidated: harness.inValidated
        property bool   batteryCritical: harness.inBattCritical
        property real   distanceFromHomeM: harness.inDistanceM
    }

    RTLAbortGate {
        id: gate
        vehicle: vehicleObj
        estimator: estimatorObj
        autoTick: false
        hysteresisSeconds: 0
    }
}
'''


class RTLAbortGateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.root = Path(__file__).resolve().parents[2]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        src = self.root / "src/FlyView/RTLAbortGate.qml"
        (self.folder / "RTLAbortGate.qml").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
        self.engine = QQmlEngine()
        path = self.folder / "Harness.qml"
        path.write_text(HARNESS, encoding="utf-8")
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(path)))
        self.assertFalse(self.component.isError(), [e.toString() for e in self.component.errors()])
        self.item = self.component.create()
        self.assertIsNotNone(self.item)
        self.gate = self.item.property("gate")

    def tearDown(self):
        if getattr(self, "item", None) is not None:
            self.item.deleteLater()
        self.engine.deleteLater()
        self.app.processEvents()
        self.temp.cleanup()

    def set(self, **kwargs):
        for key, value in kwargs.items():
            self.item.setProperty(key, value)

    def advance(self, dt=1.0):
        self.engine.newQObject(self.gate).property("advance").call([QJSValue(float(dt))])
        QTest.qWait(2)

    def rtl(self):
        return self.gate.property("rtlAllowed")

    def abort(self):
        return self.gate.property("abortAllowed")

    # ---- Ground / nominal ----
    def test_on_ground_allows_both(self):
        self.set(inArmed=False, inFlying=False)
        self.advance()
        self.assertTrue(self.rtl())
        self.assertTrue(self.abort())

    def test_airborne_provisional_nominal_allows(self):
        self.advance()  # 1 min flown, 1 km home, PNR counting -> allowed
        self.assertTrue(self.rtl())

    # ---- Simple time policy (§4) ----
    def test_out_of_time_grays_rtl(self):
        self.set(inFlightTimeSec=26 * 60)  # effective_remaining <= 0
        self.advance()
        self.assertFalse(self.rtl())

    def test_backstop_used_and_distance_grays(self):
        self.set(inFlightTimeSec=14 * 60, inDistanceM=9000)  # used>13 AND dist>8
        self.advance()
        self.assertFalse(self.rtl())

    def test_effective_remaining_le_distance_grays(self):
        self.set(inFlightTimeSec=20 * 60, inDistanceM=6000)  # eff=5 <= dist=6
        self.advance()
        self.assertFalse(self.rtl())

    # ---- Degradation ladder (§3) ----
    def test_provisional_pnr_reached_grays(self):
        self.set(inPnrStatus="PNR_REACHED")
        self.advance()
        self.assertFalse(self.rtl())

    def test_provisional_pnr_floor_grays(self):
        self.set(inPnrCountdown=3)  # <= pnrFloorSeconds (5)
        self.advance()
        self.assertFalse(self.rtl())

    def test_unknown_uses_simple_policy_only(self):
        # PNR UNKNOWN but simple policy nominal -> allowed (PNR ignored).
        self.set(inPnrStatus="UNKNOWN", inPnrCountdown=-1)
        self.advance()
        self.assertTrue(self.rtl())
        self.set(inFlightTimeSec=26 * 60)  # now simple policy fails
        self.advance()
        self.assertFalse(self.rtl())

    def test_validated_uses_pnr_gate_ignoring_simple(self):
        # VALIDATED: PNR energy is the gate even when simple policy would gray.
        self.set(inValidated=True, inPnrStatus="VALIDATED", inPnrCountdown=600,
                 inFlightTimeSec=26 * 60)
        self.advance()
        self.assertTrue(self.rtl())
        self.set(inPnrStatus="PNR_REACHED")
        self.advance()
        self.assertFalse(self.rtl())

    def test_battery_critical_grays(self):
        self.set(inBattCritical=True)
        self.advance()
        self.assertFalse(self.rtl())

    # ---- Abort budget (§5) ----
    def test_abort_counter_and_budget(self):
        self.assertEqual(self.gate.property("abortsDone"), 0)
        for expected in (1, 2, 3):
            self.set(inFlightMode="Hold"); self.advance()
            self.set(inFlightMode="Abort"); self.advance()
            self.assertEqual(self.gate.property("abortsDone"), expected)
        self.assertFalse(self.abort())  # budget (maxAborts=3) exhausted

    def test_abort_resets_on_disarm(self):
        self.set(inFlightMode="Abort"); self.advance()
        self.assertEqual(self.gate.property("abortsDone"), 1)
        self.set(inArmed=False); self.advance()
        self.assertEqual(self.gate.property("abortsDone"), 0)

    # ---- Hysteresis ----
    def test_hysteresis_debounces_transition(self):
        self.gate.setProperty("hysteresisSeconds", 3)
        self.assertTrue(self.rtl())
        self.set(inFlightTimeSec=26 * 60)  # raw -> gray
        self.advance(1.0)
        self.assertTrue(self.rtl())        # not yet (1s < 3s)
        self.advance(2.5)                  # total 3.5s >= 3s
        self.assertFalse(self.rtl())


if __name__ == "__main__":
    unittest.main()
