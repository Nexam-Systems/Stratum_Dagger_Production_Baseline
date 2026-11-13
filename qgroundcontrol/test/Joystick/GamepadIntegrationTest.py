import os
from pathlib import Path
import time
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QUrl, Qt, QPoint
from PySide6.QtGui import QGuiApplication, QFontDatabase, QFont
from PySide6.QtQml import QJSValue, QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest


class GamepadIntegrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        font = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts/segoeui.ttf"
        if font.exists():
            QFontDatabase.addApplicationFont(str(font))
            cls.app.setFont(QFont("Segoe UI", 10))
        cls.engine = QQmlEngine()
        cls.source_dir = Path(__file__).resolve().parents[2] / "src/FlyView"
        controller = (cls.source_dir / "GamepadCommandController.qml").read_text(encoding="utf-8").split("Item {", 1)[1]
        controller = controller.replace("QGroundControl.unitsConversion.", "testUnits.")
        overlay = (cls.source_dir / "GamepadOverlay.qml").read_text(encoding="utf-8").split("Rectangle {", 1)[1]
        overlay = overlay.replace("QGCButton {", "Button { property bool primary; property string iconSource;")
        overlay = overlay.replace("QGCLabel", "Label").replace("ScreenTools.", "screenTools.")
        overlay = overlay.replace("required property var controller", "property var controller: commands\n    width: parent ? parent.width : 300")
        fixture = """
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
    width: 1024
    height: 768
    readonly property var controller: commands
    property alias joystick: gamepad
    property alias manager: managerMock
    property alias vehicle: vehicleMock
    property alias guided: guidedMock
    property alias widgets: widgetsMock
    property alias engagement: engagementMock
    readonly property var overlay: panelLoader.item
    readonly property var holdProgress: holdBar
    QtObject {
        id: screenTools
        property real defaultFontPixelWidth: 8
        property real defaultFontPixelHeight: 16
        property real smallFontPointSize: 9
    }
    QtObject {
        id: testUnits
        function metersToAppSettingsVerticalDistanceUnits(value) { return value * 3.28084 }
    }
    QtObject {
        id: gamepad
        property bool isGamepad: true
        property string name: "Simulated PlayStation gamepad"
        property int generation: 0
        property var settings: QtObject { property var calibrated: QtObject { property bool rawValue: true } }
        function supportsProtectedGamepad() { return true }
        function setProtectedGamepadMode(enabled) { return ++generation }
        signal protectedGamepadState(int buttons, bool safetyHeld, bool manualHeld, bool ready, int generation, double timestampMs)
    }
    QtObject {
        id: managerMock
        property var activeJoystick: gamepad
        property bool activeJoystickEnabledForActiveVehicle: true
    }
    QtObject {
        id: vehicleMock
        property bool initialConnectComplete: true
        property bool armed: true
        property bool flying: true
        property var flightModes: ["Abort", "Standoff", "Engagement"]
        property string flightMode: "Standoff"
        property var vehicleLinkManager: QtObject { property bool communicationLost: false }
        property var supports: QtObject { property bool guidedMode: true }
        property real minimumAltitude: 10
        function minimumTakeoffAltitudeMeters() { return minimumAltitude }
    }
    QtObject {
        id: guidedMock
        property bool showTakeoff: true
        property bool showRTL: true
        property int actionTakeoff: 3
        property int actionRTL: 1
        property var requests: []
        function executeAction(action, data, value, option) { requests = requests.concat([{action: action, altitude: value}]) }
    }
    QtObject {
        id: engagementMock
        property string abortModeName: "Abort"
        property string engagementModeName: "Engagement"
        property int abortRequests: 0
        property int engageRequests: 0
        function abort() { ++abortRequests }
        function engage() { ++engageRequests }
    }
    QtObject {
        id: widgetsMock
        property bool targetValid: true
        property bool acceptRequest: true
        property real distance: 300
        property var requests: []
        function gamepadStandoffRequest() { return targetValid ? {distance: distance, height: 150} : null }
        function executeGamepadStandoff(request) {
            if (!acceptRequest) return false
            requests = requests.concat([request])
            return true
        }
        function toggleStandoff() {}
    }
    QtObject {
        id: mapMock
        property var navigation: []
        function pan(horizontal, vertical) { navigation = navigation.concat([{x: horizontal, y: vertical}]) }
    }
    TestController {
        id: commands
        joystickManager: managerMock
        vehicle: vehicleMock
        guidedController: guidedMock
        engagementController: engagementMock
        widgetLayer: widgetsMock
        mapControl: mapMock
    }
    Loader {
        id: panelLoader
        sourceComponent: panelFactory
        x: 20
        y: 20
        width: Math.min(300, parent.width - 40)
        height: parent.height - 40
    }
    GamepadHoldProgress {
        id: holdBar
        safetyState: commands.state
        x: 340
        y: 20
        width: 320
        height: implicitHeight
    }
"""
        fixture += "component TestController : Item {" + controller
        fixture += "Component { id: panelFactory; Rectangle {" + overlay + "\n}\n}"
        cls.component = QQmlComponent(cls.engine)
        cls.component.setData(fixture.encode(), QUrl.fromLocalFile(str(cls.source_dir / "GamepadTestHarness.qml")))
        assert not cls.component.isError(), [error.toString() for error in cls.component.errors()]

    def setUp(self):
        self.item = self.component.create()
        self.assertIsNotNone(self.item)
        self.controller = self.item.property("controller")
        self.gamepad = self.item.property("joystick")
        self.state = self.engine.newQObject(self.controller).property("state").toQObject()

    def tearDown(self):
        self.item.deleteLater()
        self.app.processEvents()

    def call(self, obj, name, *arguments):
        values = [QJSValue(value if isinstance(value, (bool, str)) else float(value)) for value in arguments]
        result = self.engine.newQObject(obj).property(name).call(values)
        self.assertFalse(result.isError(), result.toString())
        return result

    def feed(self, buttons=0, safety=False, manual=False, generation=None):
        self.call(self.gamepad, "protectedGamepadState", buttons, safety, manual, True,
                  self.controller.property("_generation") if generation is None else generation, int(time.time() * 1000))

    def enable(self):
        self.call(self.controller, "enable")
        self.assertTrue(self.controller.property("modeEnabled"))
        self.feed()

    def select(self, face):
        self.feed(face)
        self.feed()
        self.feed(safety=True)
        self.state.setProperty("armStartedMs", int(time.time() * 1000) - 700)

    def commit(self):
        self.feed(1 << 10, safety=True)

    def requests(self, name):
        return self.item.property(name).property("requests").toVariant()

    def test_startup_requires_explicit_enable(self):
        self.assertFalse(self.controller.property("modeEnabled"))
        self.assertFalse(self.item.property("manager").property("activeJoystickEnabledForActiveVehicle"))
        self.select(8)
        self.commit()
        self.assertEqual(self.requests("guided"), [])

    def test_takeoff_snapshot_and_units(self):
        self.enable()
        self.select(8)
        self.controller.setProperty("takeoffAltitudeMeters", 40)
        self.commit()
        self.assertEqual(len(self.requests("guided")), 1)
        self.assertAlmostEqual(self.requests("guided")[0]["altitude"], 20 * 3.28084)

    def test_safety_rechecked_at_commit(self):
        self.enable()
        self.select(8)
        self.item.property("guided").setProperty("showTakeoff", False)
        self.commit()
        self.assertEqual(self.requests("guided"), [])

    def test_standoff_snapshot_and_rejection(self):
        self.enable()
        self.select(4)
        self.item.property("widgets").setProperty("distance", 500)
        self.commit()
        self.assertEqual(self.requests("widgets")[0]["distance"], 300)
        self.feed()
        self.item.property("widgets").setProperty("targetValid", False)
        self.select(4)
        self.commit()
        self.assertEqual(len(self.requests("widgets")), 1)

    def test_abort_and_rtl_routes(self):
        self.enable()
        self.select(1)
        self.commit()
        self.assertEqual(self.requests("guided")[0]["action"], 1)
        self.feed()
        self.feed((1 << 9) | 2)
        self.assertEqual(self.item.property("engagement").property("abortRequests"), 0)
        self.state.setProperty("holdStartedMs", int(time.time() * 1000) - 1000)
        self.feed((1 << 9) | 2)
        self.assertEqual(self.item.property("engagement").property("abortRequests"), 1)

    def test_engage_route_and_progress(self):
        self.enable()
        self.feed((1 << 9) | 8)
        self.feed()
        self.feed(1 << 10, safety=True)
        self.state.setProperty("holdStartedMs", int(time.time() * 1000) - 1500)
        self.feed(1 << 10, safety=True)
        bar = self.item.property("holdProgress")
        self.assertTrue(bar.property("visible"))
        self.assertAlmostEqual(bar.property("progress"), 0.5, delta=0.05)
        self.assertEqual(self.item.property("engagement").property("engageRequests"), 0)
        self.state.setProperty("holdStartedMs", int(time.time() * 1000) - 3000)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.item.property("engagement").property("engageRequests"), 1)
        self.assertEqual(bar.property("progress"), 1)
        self.assertTrue(bar.property("completed"))

    def test_timed_hold_progress_resets_on_release(self):
        self.enable()
        self.feed((1 << 9) | 2)
        self.state.setProperty("holdStartedMs", int(time.time() * 1000) - 500)
        self.feed((1 << 9) | 2)
        bar = self.item.property("holdProgress")
        self.assertAlmostEqual(bar.property("progress"), 0.5, delta=0.05)
        self.feed()
        self.assertFalse(bar.property("visible"))
        self.assertEqual(bar.property("progress"), 0)

    def test_hold_bar_renders_filling_and_completed(self):
        self.enable()
        self.feed((1 << 9) | 8)
        self.feed()
        self.feed(1 << 10, safety=True)
        window = QQuickWindow()
        window.resize(1024, 768)
        self.item.setParentItem(window.contentItem())
        window.show()
        self.state.setProperty("holdStartedMs", int(time.time() * 1000) - 1500)
        self.feed(1 << 10, safety=True)
        QTest.qWait(50)
        partial = window.grabWindow()
        self.state.setProperty("holdStartedMs", int(time.time() * 1000) - 3000)
        self.feed(1 << 10, safety=True)
        QTest.qWait(50)
        full = window.grabWindow()

        def filled_pixels(image):
            return sum(image.pixelColor(horizontal, vertical).green() > 180
                       and image.pixelColor(horizontal, vertical).red() < 100
                       for horizontal in range(348, 652) for vertical in range(20, 85))

        self.assertGreater(filled_pixels(partial), 0)
        self.assertGreater(filled_pixels(full), filled_pixels(partial))
        output = os.environ.get("STRATUM_GAMEPAD_SCREENSHOT_DIR")
        if output:
            partial.save(str(Path(output) / "stratum-engage-hold-partial.png"))
            full.save(str(Path(output) / "stratum-engage-hold-full.png"))
        self.call(self.controller, "disable")
        self.assertFalse(self.item.property("holdProgress").property("visible"))
        window.close()
        self.item.setParentItem(None)
        window.deleteLater()

    def test_disable_and_old_generation(self):
        self.enable()
        generation = self.controller.property("_generation")
        self.select(8)
        self.call(self.controller, "disable")
        self.commit()
        self.enable()
        self.feed(8, generation=generation)
        self.assertEqual(self.state.property("pendingCommand"), "")
        self.assertEqual(self.requests("guided"), [])

    def test_disconnect_clears_selection(self):
        self.enable()
        self.select(8)
        self.item.property("vehicle").property("vehicleLinkManager").setProperty("communicationLost", True)
        self.assertFalse(self.controller.property("modeEnabled"))
        self.commit()
        self.assertEqual(self.requests("guided"), [])

    def test_overlay_desktop_and_mobile(self):
        self.enable()
        window = QQuickWindow()
        self.item.setParentItem(window.contentItem())
        for width, height in [(1024, 768), (360, 740), (360, 360)]:
            window.resize(width, height)
            self.item.setWidth(width)
            self.item.setHeight(height)
            window.show()
            QTest.qWait(50)
            panel = self.item.property("overlay")
            self.assertLessEqual(panel.y() + panel.height(), height)
            image = window.grabWindow()
            self.assertFalse(image.isNull())
            self.assertNotEqual(image.pixelColor(25, 25), image.pixelColor(width - 5, height - 5))
            output = os.environ.get("STRATUM_GAMEPAD_SCREENSHOT_DIR")
            if output:
                image.save(str(Path(output) / f"stratum-gamepad-{width}.png"))
        window.close()
        self.item.setParentItem(None)
        window.deleteLater()

    def test_touch_hold_enable_stays_enabled_after_release(self):
        window = QQuickWindow()
        window.resize(1024, 768)
        self.item.setParentItem(window.contentItem())
        window.show()
        QTest.qWait(50)
        point = QPoint(160, 80)
        QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier, point)
        self.assertFalse(self.controller.property("modeEnabled"))
        QTest.mousePress(window, Qt.LeftButton, Qt.NoModifier, point)
        QTest.qWait(1550)
        self.assertTrue(self.controller.property("modeEnabled"))
        self.feed()
        QTest.mouseRelease(window, Qt.LeftButton, Qt.NoModifier, point)
        self.assertTrue(self.controller.property("modeEnabled"))
        QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier, point)
        self.assertFalse(self.controller.property("modeEnabled"))
        window.close()
        self.item.setParentItem(None)
        window.deleteLater()


if __name__ == "__main__":
    unittest.main()