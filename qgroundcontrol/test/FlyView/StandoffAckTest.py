import os
import re
import tempfile
import unittest
from pathlib import Path

import PySide6

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QObject, QUrl, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtPositioning import QGeoCoordinate
from PySide6.QtQml import QQmlEngine, QQmlComponent
from PySide6.QtTest import QTest


# STRATUM #98 / KAN-46: the standoff command is only SENT by Set Standoff; the slot becomes active
# ("en route") when the vehicle acknowledges it, and a rejection or timeout keeps the draft. These
# tests mount the real StandoffController against a stub vehicle that emits the same signals as
# Vehicle (mavCommandResult, textMessageReceived, flightModeChanged).
CMD_STANDOFF = 31010


class StubVehicle(QObject):
    mavCommandResult = Signal(int, int, int, int, int)
    textMessageReceived = Signal(int, int, int, str, str)
    flightModeChanged = Signal(str)

    def __init__(self):
        super().__init__()
        self._mode = "Hold"
        self.sent = []
        self.sendCommands = []
        self.refuse = False

    @Property(int, constant=True)
    def id(self):
        return 1

    def _get_mode(self):
        return self._mode

    def _set_mode(self, mode):
        if mode != self._mode:
            self._mode = mode
            self.flightModeChanged.emit(mode)

    flightMode = Property(str, _get_mode, _set_mode, notify=flightModeChanged)

    @Slot(QGeoCoordinate, float, float, float, result=bool)
    def guidedModeStandoff(self, target, distance, bearing, height):
        if self.refuse:
            return False
        self.sent.append((distance, bearing, height))
        return True

    @Slot(int, int, bool, float, float, float, float, float, float, float)
    def sendCommand(self, comp, command, showError, p1, p2, p3, p4, p5, p6, p7):
        self.sendCommands.append(command)


class VehicleManager(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self._v = None

    def _get(self):
        return self._v

    def _set(self, v):
        self._v = v
        self.changed.emit()

    activeVehicle = Property(QObject, _get, _set, notify=changed)


class Rank(QObject):
    @Property(int, constant=True)
    def rawValue(self):
        return self._v

    def __init__(self, v):
        super().__init__()
        self._v = v


class AppSettings(QObject):
    def __init__(self, profile):
        super().__init__()
        self._p = Rank(profile)

    @Property(QObject, constant=True)
    def stratumProfile(self):
        return self._p


class SettingsManager(QObject):
    def __init__(self, profile):
        super().__init__()
        self._a = AppSettings(profile)

    @Property(QObject, constant=True)
    def appSettings(self):
        return self._a


class QGC(QObject):
    def __init__(self, profile):
        super().__init__()
        self.mvm = VehicleManager()
        self.sm = SettingsManager(profile)

    @Property(QObject, constant=True)
    def multiVehicleManager(self):
        return self.mvm

    @Property(QObject, constant=True)
    def settingsManager(self):
        return self.sm


HOST = '''import QtQuick
import QtPositioning

Item {
    id: host
    property int  acceptedCount: 0
    property bool awaiting:      c.awaitingAck
    property bool rejected:      c.rejected
    property string reason:      c.rejectReason
    property string banner:      c.statusMessage
    property bool active:        c._standoffActive
    property real activeDistance: c._standoffDistance
    property real activeHeight:  c._standoffHeight
    property real activeDirection: c._standoffDirection
    property bool lastBegin:     false

    property int  req:    0
    property real reqD:   100
    property real reqH:   100
    property real reqDir: 0
    onReqChanged: lastBegin = c.beginStandoff(reqD, reqH, 30, reqDir, QtPositioning.coordinate(47.0, 8.0))

    property int  clearReq: 0
    onClearReqChanged: c.clearRejected()

    StandoffController { id: c; onStandoffAccepted: host.acceptedCount++ }
}
'''


class StandoffAckTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.root = Path(__file__).resolve().parents[2]

    def mount(self, profile=2):
        self.temp = tempfile.TemporaryDirectory()
        folder = Path(self.temp.name)
        source = (self.root / "src/FlyView/StandoffController.qml").read_text(encoding="utf-8")
        source = re.sub(r"import QGroundControl[\w.]*\n", "", source)   # QGroundControl is stubbed
        (folder / "StandoffController.qml").write_text(source, encoding="utf-8")
        (folder / "Host.qml").write_text(HOST, encoding="utf-8")
        self.engine = QQmlEngine()
        self.qgc = QGC(profile)
        self.vehicle = StubVehicle()
        self.qgc.mvm._set(self.vehicle)
        self.engine.rootContext().setContextProperty("QGroundControl", self.qgc)
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(folder / "Host.qml")))
        self.item = self.component.create()
        self.assertIsNotNone(self.item, [e.toString() for e in self.component.errors()])

    def tearDown(self):
        if getattr(self, "item", None) is not None:
            self.item.deleteLater()
        if getattr(self, "engine", None) is not None:
            self.engine.deleteLater()
        self.app.processEvents()
        if getattr(self, "temp", None) is not None:
            self.temp.cleanup()

    def begin(self, distance=100, height=100, direction=0):
        self.item.setProperty("reqD", float(distance))
        self.item.setProperty("reqH", float(height))
        self.item.setProperty("reqDir", float(direction))
        self.item.setProperty("req", self.item.property("req") + 1)
        QTest.qWait(5)

    def prop(self, name):
        return self.item.property(name)

    def ack(self, result=0, failure=0, command=CMD_STANDOFF, vehicle_id=1):
        self.vehicle.mavCommandResult.emit(vehicle_id, 1, command, result, failure)
        QTest.qWait(5)

    # ---- sending / accepted ----
    def test_set_standoff_only_sends_until_the_vehicle_accepts(self):
        self.mount()
        self.begin(150, 90, 45)
        self.assertTrue(self.prop("lastBegin"))
        self.assertEqual(self.vehicle.sent, [(150.0, 45.0, 90.0)])
        self.assertTrue(self.prop("awaiting"))
        self.assertFalse(self.prop("active"))               # not en route yet
        self.assertEqual(self.vehicle.flightMode, "Hold")   # mode not switched before the ACK

        self.ack(result=0)
        self.assertFalse(self.prop("awaiting"))
        self.assertTrue(self.prop("active"))                # slot is now en route
        self.assertEqual(self.prop("acceptedCount"), 1)
        self.assertEqual(self.vehicle.flightMode, "Standoff")
        self.assertEqual((self.prop("activeDistance"), self.prop("activeHeight"), self.prop("activeDirection")), (150.0, 90.0, 45.0))
        self.assertFalse(self.prop("rejected"))

    def test_a_second_command_is_refused_while_one_is_awaiting_its_ack(self):
        self.mount()
        self.begin()
        self.begin(200)
        self.assertFalse(self.prop("lastBegin"))
        self.assertEqual(len(self.vehicle.sent), 1)

    def test_up_front_refusal_changes_nothing(self):
        self.mount()
        self.vehicle.refuse = True
        self.begin()
        self.assertFalse(self.prop("lastBegin"))
        self.assertFalse(self.prop("awaiting"))
        self.assertFalse(self.prop("rejected"))

    # ---- rejected / timed out ----
    def test_rejected_keeps_the_draft_and_the_previous_standoff(self):
        self.mount()
        self.begin(150, 90, 45)
        self.ack(0)
        self.begin(300, 200, 90)                            # a new command...
        self.vehicle.textMessageReceived.emit(1, 1, 4, "Standoff target outside the allowed range", "")
        self.ack(result=2)                                  # ...that the vehicle DENIES
        self.assertTrue(self.prop("rejected"))
        self.assertFalse(self.prop("awaiting"))
        self.assertIn("denied", self.prop("reason"))
        self.assertIn("Standoff target outside the allowed range", self.prop("reason"))   # firmware STATUSTEXT
        # the earlier accepted standoff is untouched; the rejected values never became active
        self.assertTrue(self.prop("active"))
        self.assertEqual((self.prop("activeDistance"), self.prop("activeHeight"), self.prop("activeDirection")), (150.0, 90.0, 45.0))
        self.assertEqual(self.prop("acceptedCount"), 1)

    def test_timeout_counts_as_rejected(self):
        self.mount()
        self.begin()
        self.ack(result=4, failure=1)                       # MAV_RESULT_FAILED + no response
        self.assertTrue(self.prop("rejected"))
        self.assertIn("did not respond", self.prop("reason"))
        self.assertFalse(self.prop("active"))
        self.assertEqual(self.vehicle.flightMode, "Hold")

    def test_late_statustext_is_added_to_a_fresh_rejection(self):
        self.mount()
        self.begin()
        self.ack(result=2)
        self.vehicle.textMessageReceived.emit(1, 1, 3, "Standoff rejected: geofence", "")
        QTest.qWait(5)
        self.assertIn("Standoff rejected: geofence", self.prop("reason"))

    def test_editing_clears_the_rejection_and_a_resend_works(self):
        self.mount()
        self.begin()
        self.ack(result=2)
        self.assertTrue(self.prop("rejected"))
        self.item.setProperty("clearReq", 1)
        QTest.qWait(5)
        self.assertFalse(self.prop("rejected"))
        self.assertEqual(self.prop("reason"), "")
        self.begin(120)
        self.assertTrue(self.prop("lastBegin"))
        self.ack(0)
        self.assertTrue(self.prop("active"))

    def test_acks_for_other_commands_or_vehicles_are_ignored(self):
        self.mount()
        self.begin()
        self.ack(result=0, command=400)                     # e.g. an arm command
        self.ack(result=0, vehicle_id=2)
        self.assertTrue(self.prop("awaiting"))
        self.assertFalse(self.prop("active"))
        self.ack(result=0)
        self.assertTrue(self.prop("active"))

    def test_an_ack_nobody_is_waiting_for_does_nothing(self):
        self.mount()
        self.ack(result=0)
        self.assertFalse(self.prop("active"))
        self.assertEqual(self.vehicle.flightMode, "Hold")

    # ---- abort ----
    def test_abort_shows_the_firmware_statustext(self):
        self.mount()
        self.begin()
        self.ack(0)
        self.vehicle.textMessageReceived.emit(1, 1, 4, "Standoff aborted: link quality", "")
        self.vehicle.flightMode = "Abort"
        QTest.qWait(5)
        self.assertIn("Standoff aborted: link quality", self.prop("banner"))

    def test_abort_without_an_active_standoff_shows_nothing(self):
        self.mount()
        self.vehicle.textMessageReceived.emit(1, 1, 4, "something", "")
        self.vehicle.flightMode = "Abort"
        QTest.qWait(5)
        self.assertEqual(self.prop("banner"), "")

    # ---- Dropper keeps its existing behaviour ----
    def test_dropper_is_active_as_soon_as_it_is_sent(self):
        self.mount(profile=1)
        self.begin(150, 90, 45)
        self.assertTrue(self.prop("lastBegin"))
        self.assertFalse(self.prop("awaiting"))
        self.assertTrue(self.prop("active"))
        self.assertEqual(self.prop("acceptedCount"), 1)
        self.assertEqual(self.vehicle.sendCommands, [31010, 31011])


if __name__ == "__main__":
    unittest.main()
