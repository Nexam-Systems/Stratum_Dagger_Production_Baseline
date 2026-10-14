import os
from pathlib import Path
import time
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QJSValue, QQmlComponent, QQmlEngine


class TargetGpsEstimateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.engine = QQmlEngine()
        source = Path(__file__).resolve().parents[2] / "src/FlyView/TargetGpsEstimate.qml"
        text = source.read_text(encoding="utf-8")
        for module in ["QGroundControl", "QGroundControl.Controls", "QGroundControl.FlyView"]:
            text = text.replace("import " + module + "\n", "")
        text = text.replace("QGCLabel", "Label")
        text = text.replace("CameraGeolocation { id: geometry }", """
        QtObject {
            id: geometry
            property var arguments: []
            function estimate(position, home, height, roll, pitch, yaw, cameraRoll, cameraPitch, cameraYaw) {
                arguments = [height, roll, pitch, yaw, cameraRoll, cameraPitch, cameraYaw]
                return {status: "DEGRADED", reason: "Local model fixture", latitude: 12.001, longitude: 77.001,
                        horizontalRange: 100, bearing: 0, slantRange: 141.421}
            }
        }
        """)
        text = text.replace("QGCPalette { id: qgcPal }", """
        QtObject { id: qgcPal; property color text: "white"; property color warningText: "orange" }
        QtObject { id: ScreenTools; property real defaultFontPixelHeight: 16; property real smallFontPointSize: 9; property real smallFontPixelSize: 12 }
        """.replace("id: ScreenTools", "id: screenTools"))
        text = text.replace("ScreenTools.", "screenTools.")
        fixture = """
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
    readonly property var estimatePanel: panel
    readonly property var vehicleMock: craft
    readonly property var facts: attitude
    QtObject {
        id: craft
        property var coordinate: ({isValid: true, latitude: 12, longitude: 77, altitude: 150})
        property var homePosition: ({isValid: true, latitude: 12, longitude: 77, altitude: 50})
        property double positionTimestampMs: Date.now()
        property var vehicle: attitude
        property var vehicleLinkManager: QtObject { property bool communicationLost: false }
        property var gps: QtObject { property var lock: QtObject { property real rawValue: 3 } }
        signal positionUpdated()
    }
    QtObject {
        id: attitude
        property double attitudeTimestampMs: Date.now()
        property var roll: QtObject { property real rawValue: 5 }
        property var pitch: QtObject { property real rawValue: -10 }
        property var heading: QtObject { property real rawValue: 90 }
        property var altitudeRelative: QtObject { property real rawValue: 100 }
        signal attitudeUpdated()
    }
    TestEstimator {
        id: panel
        vehicle: craft
        gimbalRollDegrees: 15
        gimbalPitchDegrees: -45
        gimbalYawDegrees: -30
        gimbalTimestampMs: Date.now()
        width: 480
    }
"""
        text = text.split("Item {", 1)[1]
        fixture += "component TestEstimator : Item {" + text + "\n}"
        cls.component = QQmlComponent(cls.engine)
        cls.component.setData(fixture.encode(), QUrl.fromLocalFile(str(source.parent / "GeolocationTestHarness.qml")))
        assert not cls.component.isError(), [error.toString() for error in cls.component.errors()]

    def setUp(self):
        self.item = self.component.create()
        self.assertIsNotNone(self.item)
        self.panel = self.item.property("estimatePanel")
        self.vehicle = self.item.property("vehicleMock")
        self.facts = self.item.property("facts")

    def tearDown(self):
        self.item.deleteLater()
        self.app.processEvents()

    def estimate(self):
        method = self.engine.newQObject(self.panel).property("_buildEstimate")
        result = method.call()
        self.assertFalse(result.isError(), result.toString())
        return result.toVariant()

    def test_estimates_without_any_tracker(self):
        result = self.estimate()
        self.assertEqual(result["status"], "DEGRADED")
        self.assertIsNotNone(result["latitude"])
        self.assertIsNotNone(result["longitude"])

    def test_stale_position_invalidates(self):
        self.vehicle.setProperty("positionTimestampMs", int(time.time() * 1000) - 2100)
        result = self.estimate()
        self.assertEqual(result["status"], "INVALID")
        self.assertIsNone(result["latitude"])
        self.assertIn("position", result["reason"])

    def test_stale_camera_and_vehicle_attitude(self):
        self.panel.setProperty("gimbalTimestampMs", int(time.time() * 1000) - 1600)
        self.assertIn("C12", self.estimate()["reason"])
        self.panel.setProperty("gimbalTimestampMs", int(time.time() * 1000))
        self.facts.setProperty("attitudeTimestampMs", int(time.time() * 1000) - 1600)
        self.assertIn("Vehicle attitude", self.estimate()["reason"])

    def test_skew_missing_roll_and_gps_fix(self):
        self.facts.setProperty("attitudeTimestampMs", int(time.time() * 1000) - 700)
        self.assertIn("aligned", self.estimate()["reason"])
        self.facts.setProperty("attitudeTimestampMs", int(time.time() * 1000))
        self.panel.setProperty("gimbalRollDegrees", float("nan"))
        self.assertEqual(self.estimate()["status"], "INVALID")
        self.panel.setProperty("gimbalRollDegrees", 0)
        gps = self.engine.newQObject(self.vehicle).property("gps").toQObject()
        lock = self.engine.newQObject(gps).property("lock").toQObject()
        lock.setProperty("rawValue", float("nan"))
        self.assertIn("GPS", self.estimate()["reason"])

    def test_lost_link_invalidates(self):
        link = self.engine.newQObject(self.vehicle).property("vehicleLinkManager").toQObject()
        link.setProperty("communicationLost", True)
        self.assertIn("lost", self.estimate()["reason"])

    def test_public_compute_estimate_for_fetch_target(self):
        result = self.engine.newQObject(self.panel).property("computeEstimate").call()
        self.assertFalse(result.isError(), result.toString())
        estimate = result.toVariant()
        self.assertEqual(estimate["status"], "DEGRADED")
        self.assertAlmostEqual(estimate["latitude"], 12.001)
        self.assertAlmostEqual(estimate["longitude"], 77.001)


if __name__ == "__main__":
    unittest.main()