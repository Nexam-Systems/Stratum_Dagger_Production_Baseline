import math
import os
from pathlib import Path
import time
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine, QQmlPropertyMap
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest


class CameraFovIndicatorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.engine = QQmlEngine()
        cls.objects = []
        cls.video = cls.make_object(c12YawDegrees=30.0, c12PitchDegrees=-30.0, c12AttitudeTimestampMs=0)
        cls.video_settings = cls.make_object(
            daggerCamera=cls.make_object(rawValue=1), rtspUrl=cls.make_object(rawValue="rtsp://camera/tv"),
        )
        cls.fov_settings = cls.make_object(cameraHFov=cls.make_object(rawValue=80))
        cls.settings = cls.make_object(videoSettings=cls.video_settings, gimbalControllerSettings=cls.fov_settings)
        cls.vehicles = cls.make_object(activeVehicle=None)
        cls.qgc = cls.make_object(videoManager=cls.video, settingsManager=cls.settings, multiVehicleManager=cls.vehicles)
        source = Path(__file__).resolve().parents[2] / "src/FlightMap/MapItems/CameraFovIndicator.qml"
        text = source.read_text(encoding="utf-8")
        text = text.replace("import QGroundControl\nimport QGroundControl.Controls", "")
        text = text.replace("QGroundControl.", "testQgc.")
        text = text.replace("id: root", "id: root\n    required property var testQgc", 1)
        cls.component = QQmlComponent(cls.engine)
        cls.component.setData(text.encode(), QUrl.fromLocalFile(str(source)))
        if cls.component.isError():
            raise AssertionError("\n".join(error.toString() for error in cls.component.errors()))

    @classmethod
    def make_object(cls, **properties):
        obj = QQmlPropertyMap()
        obj.setParent(cls.engine)
        for name, value in properties.items():
            obj.insert(name, value)
        cls.objects.append(obj)
        return obj

    def setUp(self):
        self.now = int(time.time() * 1000)
        self.facts = self.make_object(heading=self.make_object(rawValue=90.0), attitudeTimestampMs=self.now)
        self.gimbal = self.make_object(
            absolutePitch=self.make_object(rawValue=-30.0), absoluteYaw=self.make_object(rawValue=120.0),
            bodyYaw=self.make_object(rawValue=30.0), yawInVehicleFrame=True,
            attitudeTimestampMs=self.now, retracted=False,
        )
        self.stream = self.make_object(hfov=60, statusTimestampMs=self.now, uri="rtsp://camera/tv")
        self.camera = self.make_object(currentStreamInstance=self.stream, isBasic=False, modelName="C12")
        self.vehicle = self.make_object(
            vehicle=self.facts, gimbalController=self.make_object(activeGimbal=self.gimbal),
            cameraManager=self.make_object(currentCameraInstance=self.camera),
            vehicleLinkManager=self.make_object(communicationLost=False),
            coordinate=self.make_object(isValid=True),
        )
        self.vehicles.insert("activeVehicle", self.vehicle)
        self.video_settings.value("daggerCamera").insert("rawValue", 1)
        self.video_settings.value("rtspUrl").insert("rawValue", "rtsp://camera/tv")
        self.fov_settings.value("cameraHFov").insert("rawValue", 80)
        self.video.insert("c12YawDegrees", 30.0)
        self.video.insert("c12PitchDegrees", -30.0)
        self.video.insert("c12AttitudeTimestampMs", self.now)
        self.map = self.make_object(bearing=0.0)
        self.item = self.component.createWithInitialProperties({
            "vehicle": self.vehicle, "map": self.map, "iconSize": 40.0, "testQgc": self.qgc,
        })
        self.assertIsNotNone(self.item, "\n".join(error.toString() for error in self.component.errors()))
        self.item.setProperty("_c12SelectionMs", self.now - 1000)
        self.item.setProperty("_nowMs", self.now)

    def tearDown(self):
        self.item.deleteLater()
        self.app.processEvents()

    def test_relative_camera_yaw_and_map_rotation(self):
        self.assertTrue(self.item.property("_available"))
        self.assertAlmostEqual(self.item.property("_bearing"), 60.0)
        self.video.insert("c12YawDegrees", -30.0)
        self.assertAlmostEqual(self.item.property("_bearing"), 120.0)
        self.facts.value("heading").insert("rawValue", 350.0)
        self.video.insert("c12YawDegrees", 30.0)
        self.assertAlmostEqual(self.item.property("_bearing"), 320.0)
        self.video.insert("c12YawDegrees", -30.0)
        self.assertAlmostEqual(self.item.property("_bearing"), 20.0)
        self.map.insert("bearing", 10.0)
        self.assertAlmostEqual(self.item.property("rotation"), 10.0)

    def test_generic_yaw_frames(self):
        self.video_settings.value("daggerCamera").insert("rawValue", 0)
        self.assertTrue(self.item.property("_available"))
        self.facts.value("heading").insert("rawValue", 180.0)
        self.assertAlmostEqual(self.item.property("_bearing"), 210.0)
        self.gimbal.insert("yawInVehicleFrame", False)
        self.assertAlmostEqual(self.item.property("_bearing"), 120.0)
        self.gimbal.insert("attitudeTimestampMs", self.now - 2001)
        self.assertFalse(self.item.property("_available"))
        self.gimbal.insert("attitudeTimestampMs", self.now)
        self.assertTrue(self.item.property("_available"))

    def test_fov_sources_and_staleness(self):
        self.assertEqual(self.item.property("_hfov"), 60.0)
        self.stream.insert("hfov", 45)
        self.assertEqual(self.item.property("_hfov"), 45.0)
        self.stream.insert("statusTimestampMs", self.now - 15001)
        self.assertFalse(self.item.property("_available"))
        self.stream.insert("hfov", 0)
        self.assertEqual(self.item.property("_hfov"), 80.0)
        self.assertTrue(self.item.property("_available"))
        self.fov_settings.value("cameraHFov").insert("rawValue", 0)
        self.assertFalse(self.item.property("_available"))
        self.stream.insert("hfov", 180)
        self.stream.insert("statusTimestampMs", self.now)
        self.assertFalse(self.item.property("_available"))

    def test_missing_stale_and_wrong_vehicle(self):
        self.video.insert("c12AttitudeTimestampMs", 0)
        self.assertFalse(self.item.property("_available"))
        self.video.insert("c12AttitudeTimestampMs", self.now - 2001)
        self.assertFalse(self.item.property("_available"))
        self.video.insert("c12AttitudeTimestampMs", self.now)
        self.facts.insert("attitudeTimestampMs", self.now - 2001)
        self.assertFalse(self.item.property("_available"))
        self.facts.insert("attitudeTimestampMs", self.now)
        self.vehicle.value("vehicleLinkManager").insert("communicationLost", True)
        self.assertFalse(self.item.property("_available"))
        self.vehicle.value("vehicleLinkManager").insert("communicationLost", False)
        self.video.insert("c12PitchDegrees", math.nan)
        self.assertFalse(self.item.property("_available"))
        self.video.insert("c12PitchDegrees", -30.0)
        self.vehicles.insert("activeVehicle", None)
        self.assertFalse(self.item.property("_available"))

    def test_c12_does_not_use_another_camera_fov(self):
        self.camera.insert("modelName", "Other camera")
        self.assertIsNone(self.item.property("_stream"))
        self.assertEqual(self.item.property("_hfov"), 80.0)
        self.camera.insert("modelName", "Skydroid C12")
        self.assertEqual(self.item.property("_hfov"), 60.0)
        self.video_settings.value("rtspUrl").insert("rawValue", "rtsp://camera/ir")
        self.assertIsNone(self.item.property("_stream"))
        self.assertEqual(self.item.property("_hfov"), 80.0)
        self.stream.insert("uri", "rtsp://camera/ir")
        self.assertEqual(self.item.property("_hfov"), 60.0)

    def test_camera_switch_waits_for_new_telemetry(self):
        self.video_settings.value("daggerCamera").insert("rawValue", 0)
        self.video.insert("c12AttitudeTimestampMs", self.now - 500)
        self.video_settings.value("daggerCamera").insert("rawValue", 1)
        self.assertFalse(self.item.property("_available"))
        self.video.insert("c12AttitudeTimestampMs", int(time.time() * 1000))
        self.assertTrue(self.item.property("_available"))

    def test_pitch_and_zoom_legibility(self):
        self.video.insert("c12PitchDegrees", 0.0)
        forward_radius = self.item.property("_coneRadius")
        self.assertAlmostEqual(forward_radius, 150.0)
        self.assertAlmostEqual(self.item.property("_innerRadius"), 23.2)
        self.video.insert("c12PitchDegrees", -60.0)
        self.assertLess(self.item.property("_coneRadius"), forward_radius)
        self.video.insert("c12PitchDegrees", -90.0)
        self.assertTrue(self.item.property("_nadir"))
        self.map.insert("zoomLevel", 5)
        width = self.item.property("width")
        self.map.insert("zoomLevel", 20)
        self.assertEqual(self.item.property("width"), width)
        self.item.setProperty("iconSize", 12.0)
        self.assertEqual(self.item.property("_radius"), 72.0)
        self.item.setProperty("iconSize", 100.0)
        self.assertEqual(self.item.property("_radius"), 180.0)

    def test_canvas_renders_with_clear_icon_center(self):
        self.video.insert("c12YawDegrees", 90.0)
        self.video.insert("c12PitchDegrees", 0.0)
        window = QQuickWindow()
        window.setColor("#516F8E")
        window.resize(320, 320)
        self.item.setParentItem(window.contentItem())
        self.item.setX((320 - self.item.width()) / 2)
        self.item.setY((320 - self.item.height()) / 2)
        window.show()
        QTest.qWait(100)
        image = window.grabWindow()
        self.assertFalse(image.isNull())
        center = image.pixelColor(160, 160)
        self.assertEqual(center, image.pixelColor(160, 150))
        self.assertNotEqual(center, image.pixelColor(160, 80))
        self.assertNotEqual(center, image.pixelColor(160, 30))
        cone_fill = image.pixelColor(160, 80)
        self.assertGreater(cone_fill.red(), center.red() + 20)
        self.assertGreater(cone_fill.red() - center.red(), cone_fill.green() - center.green())
        self.stream.insert("hfov", 100)
        QTest.qWait(50)
        wide_image = window.grabWindow()
        self.assertNotEqual(wide_image.pixelColor(210, 110), image.pixelColor(210, 110))
        output = os.environ.get("STRATUM_FOV_SCREENSHOT")
        if output:
            wide_image.save(output)
        window.close()
        self.item.setParentItem(None)
        window.deleteLater()


if __name__ == "__main__":
    unittest.main()