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
from PySide6.QtQml import QQmlEngine, QQmlComponent


# STRATUM Issue KAN-18: deterministic tests for the mission-lifecycle STATE classifier.
# StratumMissionState depends only on QtQuick + injected vehicle/standoff mocks, so it mounts
# standalone. The harness builds a mock vehicle whose state is driven by scalar properties.
HARNESS = '''import QtQuick

Item {
    id: harness
    readonly property var state: state

    // Mock geo-coordinate with the duck-typed API the classifier uses (isValid + distanceTo).
    component MockCoord: QtObject {
        property real latitude: 0
        property real longitude: 0
        property bool isValid: true
        function distanceTo(other) {
            var R = 6371000
            var dLat = (other.latitude - latitude) * Math.PI / 180
            var dLon = (other.longitude - longitude) * Math.PI / 180
            var la1 = latitude * Math.PI / 180
            var la2 = other.latitude * Math.PI / 180
            var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                  + Math.cos(la1) * Math.cos(la2) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
            return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        }
    }

    property bool inHasVehicle: true
    property bool inCommLost: false
    property bool inArmed: false
    property bool inFlying: false
    property bool inLanding: false
    property string inFlightMode: "Hold"
    property bool inReadyAvailable: false
    property bool inReady: true
    property bool inSensorsHealthy: true
    property string inRtlMode: "Return"
    property string inSmartRtlMode: "Smart RTL"

    property real inVehLat: 24.0
    property real inVehLon: 67.0
    property real inVehAltRel: 80.0
    property real inHomeLat: 24.0
    property real inHomeLon: 67.0

    property bool inStandoffActive: false
    property bool inHasTarget: true
    property real inStdLat: 24.02
    property real inStdLon: 67.02
    property real inStandoffDistance: 0
    property real inStandoffHeight: 80

    QtObject { id: altFact; property real rawValue: harness.inVehAltRel }
    QtObject { id: factsObj; property var altitudeRelative: altFact }
    QtObject { id: linkObj; property bool communicationLost: harness.inCommLost }

    MockCoord { id: vehCoord;  latitude: harness.inVehLat;  longitude: harness.inVehLon }
    MockCoord { id: homeCoord; latitude: harness.inHomeLat; longitude: harness.inHomeLon }
    MockCoord { id: stdCoord;  latitude: harness.inStdLat;  longitude: harness.inStdLon; isValid: harness.inHasTarget }

    QtObject {
        id: vehicleObj
        property bool armed: harness.inArmed
        property bool flying: harness.inFlying
        property bool landing: harness.inLanding
        property string flightMode: harness.inFlightMode
        property bool readyToFlyAvailable: harness.inReadyAvailable
        property bool readyToFly: harness.inReady
        property bool allSensorsHealthy: harness.inSensorsHealthy
        property string rtlFlightMode: harness.inRtlMode
        property string smartRTLFlightMode: harness.inSmartRtlMode
        property var vehicle: factsObj
        property var vehicleLinkManager: linkObj
        property var coordinate: vehCoord
        property var homePosition: homeCoord
    }

    QtObject {
        id: standoffObj
        property bool _standoffActive: harness.inStandoffActive
        property real _standoffDistance: harness.inStandoffDistance
        property real _standoffHeight: harness.inStandoffHeight
        property var _targetCoordinate: stdCoord
    }

    StratumMissionState {
        id: state
        vehicle: harness.inHasVehicle ? vehicleObj : null
        standoffController: standoffObj
    }
}
'''


class StratumMissionStateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.root = Path(__file__).resolve().parents[2]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        src = self.root / "src/Toolbar/StratumMissionState.qml"
        (self.folder / "StratumMissionState.qml").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
        self.engine = QQmlEngine()
        path = self.folder / "Harness.qml"
        path.write_text(HARNESS, encoding="utf-8")
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(path)))
        self.assertFalse(self.component.isError(), [e.toString() for e in self.component.errors()])
        self.item = self.component.create()
        self.assertIsNotNone(self.item)
        self.state = self.item.property("state")

    def tearDown(self):
        if getattr(self, "item", None) is not None:
            self.item.deleteLater()
        self.engine.deleteLater()
        self.app.processEvents()
        self.temp.cleanup()

    def set(self, **kwargs):
        for key, value in kwargs.items():
            self.item.setProperty(key, value)

    def key(self):
        return self.state.property("key")

    def text(self):
        return self.state.property("text")

    def armed(self, mode, **kwargs):
        self.set(inArmed=True, inFlying=True, inFlightMode=mode, **kwargs)

    # ---- Disconnected / ground ----
    def test_disconnected(self):
        self.set(inHasVehicle=False)
        self.assertEqual(self.key(), "DISCONNECTED")

    def test_comms_lost(self):
        self.set(inCommLost=True)
        self.assertEqual(self.key(), "COMMS_LOST")

    def test_not_ready_when_not_ready_to_fly(self):
        self.set(inArmed=False, inReadyAvailable=True, inReady=False)
        self.assertEqual(self.key(), "NOT_READY")
        self.assertEqual(self.text(), "CONNECTED: NOT READY")

    def test_not_ready_when_sensors_unhealthy(self):
        self.set(inArmed=False, inSensorsHealthy=False)
        self.assertEqual(self.key(), "NOT_READY")

    def test_ready(self):
        self.set(inArmed=False, inReadyAvailable=True, inReady=True, inSensorsHealthy=True)
        self.assertEqual(self.key(), "READY")
        self.assertEqual(self.text(), "CONNECTED: READY")

    # ---- Flight modes ----
    def test_flying_on_takeoff(self):
        self.armed("Takeoff")
        self.assertEqual(self.key(), "FLYING")

    def test_aborting(self):
        self.armed("Abort", inStandoffActive=True)
        self.assertEqual(self.key(), "ABORTING")
        self.assertEqual(self.text(), "ABORTING TO STDF")

    def test_engaging(self):
        self.armed("Engagement")
        self.assertEqual(self.key(), "ENGAGING")
        self.set(inFlightMode="Vision Engagement")
        self.assertEqual(self.key(), "ENGAGING")

    def test_rtl_safe_recovery(self):
        self.armed("Safe Recovery")
        self.assertEqual(self.key(), "RTL")
        self.assertEqual(self.text(), "RETURNING TO HOME")

    def test_rtl_return_mode_name(self):
        self.armed("Return")  # matches mocked rtlFlightMode
        self.assertEqual(self.key(), "RTL")

    def test_manual_position_and_literal(self):
        self.armed("Position")
        self.assertEqual(self.key(), "MANUAL")
        self.set(inFlightMode="Manual")
        self.assertEqual(self.key(), "MANUAL")

    def test_landing(self):
        self.armed("Hold", inLanding=True, inVehLat=24.5)  # away from home
        self.assertEqual(self.key(), "LANDING")

    # ---- Geometric states (Hold is ambiguous without geometry) ----
    def test_on_station_over_home(self):
        self.armed("Hold", inVehLat=24.0, inVehLon=67.0, inHomeLat=24.0, inHomeLon=67.0)
        self.assertEqual(self.key(), "ON_STATION")

    def test_transit_to_standoff(self):
        self.armed("Standoff", inStandoffActive=True, inVehLat=24.0, inVehLon=67.0,
                   inStdLat=24.02, inStdLon=67.02, inStandoffDistance=0)
        self.assertEqual(self.key(), "TRANSIT_STDOFF")
        self.assertEqual(self.text(), "TRANSIT TO STDOFF")

    def test_at_standoff_when_established(self):
        # Target co-located with the vehicle, orbit radius 0, height matches altitude.
        self.armed("Standoff", inStandoffActive=True, inVehLat=24.5, inVehLon=67.5,
                   inStdLat=24.5, inStdLon=67.5, inStandoffDistance=0,
                   inStandoffHeight=80, inVehAltRel=80)
        self.assertEqual(self.key(), "AT_STDOFF")

    def test_wrong_altitude_keeps_transit(self):
        self.armed("Standoff", inStandoffActive=True, inVehLat=24.5, inVehLon=67.5,
                   inStdLat=24.5, inStdLon=67.5, inStandoffDistance=0,
                   inStandoffHeight=200, inVehAltRel=80)
        self.assertEqual(self.key(), "TRANSIT_STDOFF")

    def test_hold_over_home_with_active_standoff_is_on_station(self):
        # After RTL to home the standoff may still be "active"; Hold over home must read
        # ON STATION, not TRANSIT (reported KAN-18 bug).
        self.armed("Hold", inStandoffActive=True, inVehLat=24.0, inVehLon=67.0,
                   inHomeLat=24.0, inHomeLon=67.0, inStdLat=24.02, inStdLon=67.02)
        self.assertEqual(self.key(), "ON_STATION")

    def test_hold_established_at_standoff_is_at_standoff(self):
        # Parked on the standoff orbit in Hold (PX4 switched out of Standoff mode).
        self.armed("Hold", inStandoffActive=True, inVehLat=24.5, inVehLon=67.5,
                   inStdLat=24.5, inStdLon=67.5, inStandoffDistance=0,
                   inStandoffHeight=80, inVehAltRel=80)
        self.assertEqual(self.key(), "AT_STDOFF")

    def test_hold_fallback_is_holding(self):
        self.armed("Hold", inVehLat=24.5, inVehLon=67.5)  # away from home, no standoff
        self.assertEqual(self.key(), "HOLDING")
        self.assertEqual(self.text(), "HOLDING")


if __name__ == "__main__":
    unittest.main()
