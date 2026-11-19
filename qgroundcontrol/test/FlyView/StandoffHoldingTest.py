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


# STRATUM #98 / KAN-47: after the vehicle accepts the standoff the slot is "en route". It becomes
# "holding" only when the vehicle went from Standoff to Hold AND stays inside the capture tolerance
# of the slot for the dwell time; it returns to en route when the vehicle leaves the tolerance, and
# other modes leave the slot as it was. These tests mount the real StandoffController against a
# stub vehicle.
CMD_STANDOFF = 31010
TARGET = QGeoCoordinate(47.0, 8.0)
RADIUS = 100.0
HEIGHT = 100.0
BEARING = 90.0
SLOT = TARGET.atDistanceAndAzimuth(RADIUS, BEARING)
DWELL_S = 0.3


class Fact(QObject):
    def __init__(self, value):
        super().__init__()
        self._v = value

    @Property(float, constant=True)
    def rawValue(self):
        return self._v


class VehicleAltitude(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self._v = 0.0

    def _get(self):
        return self._v

    def _set(self, v):
        self._v = v
        self.changed.emit()

    rawValue = Property(float, _get, _set, notify=changed)


class StubVehicle(QObject):
    mavCommandResult = Signal(int, int, int, int, int)
    textMessageReceived = Signal(int, int, int, str, str)
    flightModeChanged = Signal(str)
    coordinateChanged = Signal()

    def __init__(self):
        super().__init__()
        self._mode = "Hold"
        self._coord = QGeoCoordinate()
        self._alt = VehicleAltitude()

    @Property(int, constant=True)
    def id(self):
        return 1

    @Property(str, constant=True)
    def pauseFlightMode(self):
        return "Hold"

    @Property(QObject, constant=True)
    def altitudeRelative(self):
        return self._alt

    def _get_mode(self):
        return self._mode

    def _set_mode(self, mode):
        if mode != self._mode:
            self._mode = mode
            self.flightModeChanged.emit(mode)

    flightMode = Property(str, _get_mode, _set_mode, notify=flightModeChanged)

    def _get_coord(self):
        return self._coord

    def _set_coord(self, coord):
        self._coord = coord
        self.coordinateChanged.emit()

    coordinate = Property(QGeoCoordinate, _get_coord, _set_coord, notify=coordinateChanged)

    @Slot(QGeoCoordinate, float, float, float, result=bool)
    def guidedModeStandoff(self, target, distance, bearing, height):
        return True

    @Slot(int, int, bool, float, float, float, float, float, float, float)
    def sendCommand(self, comp, command, showError, p1, p2, p3, p4, p5, p6, p7):
        pass


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


class AppSettings(QObject):
    def __init__(self):
        super().__init__()
        self._p = Fact(2.0)

    @Property(QObject, constant=True)
    def stratumProfile(self):
        return self._p


class FlyViewSettings(QObject):
    def __init__(self, horizontal, vertical, dwell):
        super().__init__()
        self._h = Fact(horizontal)
        self._v = Fact(vertical)
        self._d = Fact(dwell)

    @Property(QObject, constant=True)
    def standoffHoldHorizontalTolerance(self):
        return self._h

    @Property(QObject, constant=True)
    def standoffHoldVerticalTolerance(self):
        return self._v

    @Property(QObject, constant=True)
    def standoffHoldDwellTime(self):
        return self._d


class SettingsManager(QObject):
    def __init__(self, horizontal, vertical, dwell):
        super().__init__()
        self._a = AppSettings()
        self._f = FlyViewSettings(horizontal, vertical, dwell)

    @Property(QObject, constant=True)
    def appSettings(self):
        return self._a

    @Property(QObject, constant=True)
    def flyViewSettings(self):
        return self._f


class QGC(QObject):
    def __init__(self, horizontal, vertical, dwell):
        super().__init__()
        self.mvm = VehicleManager()
        self.sm = SettingsManager(horizontal, vertical, dwell)

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
    property bool holding:  c.holding
    property bool active:   c._standoffActive
    property bool stateOk:  c.inStandoffOrHold
    property string mode:   c.vehicleMode

    property int  req:    0
    onReqChanged: c.beginStandoff(%(radius)s, %(height)s, 30, %(bearing)s, QtPositioning.coordinate(%(lat)s, %(lon)s))

    property int  cancelReq: 0
    onCancelReqChanged: c.cancelStandoff()

    StandoffController { id: c; slotCoordinate: QtPositioning.coordinate(%(slat)s, %(slon)s) }
}
'''


class StandoffHoldingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.root = Path(__file__).resolve().parents[2]

    def mount(self, horizontal=10.0, vertical=5.0, dwell=DWELL_S):
        self.temp = tempfile.TemporaryDirectory()
        folder = Path(self.temp.name)
        source = (self.root / "src/FlyView/StandoffController.qml").read_text(encoding="utf-8")
        source = re.sub(r"import QGroundControl[\w.]*\n", "", source)   # QGroundControl is stubbed
        (folder / "StandoffController.qml").write_text(source, encoding="utf-8")
        host = HOST % dict(radius=RADIUS, height=HEIGHT, bearing=BEARING, lat=TARGET.latitude(), lon=TARGET.longitude(),
                           slat=SLOT.latitude(), slon=SLOT.longitude())
        (folder / "Host.qml").write_text(host, encoding="utf-8")
        self.engine = QQmlEngine()
        self.qgc = QGC(horizontal, vertical, dwell)
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

    def place(self, coordinate, height=HEIGHT):
        self.vehicle._alt.rawValue = height
        self.vehicle.coordinate = coordinate

    def accepted_standoff(self, start=None):
        """Send the command and accept it: the vehicle is put into Standoff mode."""
        self.place(start or TARGET.atDistanceAndAzimuth(RADIUS, BEARING + 180))
        self.item.setProperty("req", self.item.property("req") + 1)
        self.vehicle.mavCommandResult.emit(1, 1, CMD_STANDOFF, 0, 0)
        QTest.qWait(5)
        self.assertTrue(self.item.property("active"))
        self.assertEqual(self.vehicle.flightMode, "Standoff")

    def settle(self):
        """Let the dwell elapse, then deliver a position update."""
        QTest.qWait(int(DWELL_S * 1000) + 100)
        self.vehicle.coordinate = self.vehicle.coordinate
        QTest.qWait(5)

    def holding(self):
        return self.item.property("holding")

    def test_the_slot_stays_en_route_while_the_vehicle_is_in_standoff_mode(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT)                                     # right on the slot, but still in Standoff mode
        self.settle()
        self.assertFalse(self.holding())

    def test_standoff_then_hold_on_the_slot_shows_holding_after_the_dwell(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT.atDistanceAndAzimuth(4, 0))          # inside 10 m, 5 m vertical
        self.vehicle.flightMode = "Hold"
        QTest.qWait(5)
        self.assertFalse(self.holding())                     # dwell not over yet
        self.settle()
        self.assertTrue(self.holding())

    def test_hold_somewhere_else_does_not_show_holding(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT.atDistanceAndAzimuth(60, 0))         # outside the horizontal tolerance
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertFalse(self.holding())

    def test_vertical_difference_outside_the_tolerance_is_not_holding(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT, height=HEIGHT + 12)
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertFalse(self.holding())

    def test_engage_and_fly_away_returns_to_en_route_and_abort_back_on_the_slot_holds_again(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT)
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertTrue(self.holding())

        for _ in range(2):                                   # the same cycle twice
            self.vehicle.flightMode = "Engagement"           # engage: still on the slot, nothing changes yet
            QTest.qWait(5)
            self.assertTrue(self.holding())
            self.place(SLOT.atDistanceAndAzimuth(80, 0))     # ... then it flies away in Engagement
            QTest.qWait(5)
            self.assertFalse(self.holding())                 # en route right away
            self.vehicle.flightMode = "Abort"
            self.place(SLOT.atDistanceAndAzimuth(30, 0))
            self.settle()
            self.assertFalse(self.holding())
            self.place(SLOT)                                 # back on the slot, firmware puts it in Hold
            self.vehicle.flightMode = "Hold"
            self.settle()
            self.assertTrue(self.holding())

    def test_hold_elsewhere_after_another_mode_is_not_holding(self):
        self.mount()
        self.accepted_standoff()
        self.vehicle.flightMode = "Return"
        self.place(SLOT.atDistanceAndAzimuth(200, 0))
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertFalse(self.holding())

    def test_holding_returns_to_en_route_when_displaced_and_holds_again_when_back(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT)
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertTrue(self.holding())
        self.place(SLOT.atDistanceAndAzimuth(40, 270))       # displaced
        QTest.qWait(5)
        self.assertFalse(self.holding())
        self.place(SLOT)
        self.settle()
        self.assertTrue(self.holding())

    def test_other_modes_leave_the_slot_as_it_was(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT)
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertTrue(self.holding())
        self.vehicle.flightMode = "Engagement"
        QTest.qWait(5)
        self.assertTrue(self.item.property("active"))
        self.assertTrue(self.holding())
        self.assertEqual(self.item.property("mode"), "Engagement")
        self.assertFalse(self.item.property("stateOk"))

    def test_abort_while_en_route_keeps_the_slot_en_route(self):
        self.mount()
        self.accepted_standoff()
        self.vehicle.flightMode = "Abort"
        self.settle()
        self.assertTrue(self.item.property("active"))
        self.assertFalse(self.holding())

    def test_closing_the_target_clears_holding(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT)
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertTrue(self.holding())
        self.item.setProperty("cancelReq", 1)
        QTest.qWait(5)
        self.assertFalse(self.holding())
        self.assertFalse(self.item.property("active"))

    def test_a_new_accepted_command_starts_en_route_again(self):
        self.mount()
        self.accepted_standoff()
        self.place(SLOT)
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertTrue(self.holding())
        self.item.setProperty("req", self.item.property("req") + 1)   # a new command, accepted
        self.vehicle.mavCommandResult.emit(1, 1, CMD_STANDOFF, 0, 0)
        QTest.qWait(5)
        self.assertFalse(self.holding())

    def test_the_tolerances_are_configurable(self):
        self.mount(horizontal=50.0, vertical=20.0)
        self.accepted_standoff()
        self.place(SLOT.atDistanceAndAzimuth(40, 0), height=HEIGHT + 15)
        self.vehicle.flightMode = "Hold"
        self.settle()
        self.assertTrue(self.holding())


if __name__ == "__main__":
    unittest.main()
