import os
from pathlib import Path
import tempfile
import re
import shutil
import subprocess
import time
import unittest
import PySide6

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QUrl, Qt, QPoint, QObject, Property, Signal
from PySide6.QtGui import QGuiApplication, QFontDatabase, QFont, QColor
from PySide6.QtQml import QQmlEngine, QQmlComponent, QJSValue
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest


class DisplayMode(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self._contrast = True

    def set_contrast(self, value):
        self._contrast = value
        self.changed.emit()

    highContrast = Property(bool, lambda self: self._contrast, set_contrast, notify=changed)


class RightHandFlyViewTest(unittest.TestCase):
    def test_widget_layer_cache_compiles(self):
        compiler = shutil.which("qmlcachegen")
        if not compiler:
            candidates = [Path(PySide6.__file__).parent / "qmlcachegen.exe",
                          Path(PySide6.__file__).parent / "qmlcachegen"]
            compiler = next((str(path) for path in candidates if path.is_file()), None)
        if not compiler:
            self.skipTest("Qt qmlcachegen is unavailable")
        source = self.root / "src/FlyView/FlyViewWidgetLayer.qml"
        result = subprocess.run([compiler, "--bare", "--resource-path",
                                 "/qml/QGroundControl/FlyView/FlyViewWidgetLayer.qml",
                                 "-o", str(self.folder / "widget.cpp"), str(source)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))

    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        font = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts/segoeui.ttf"
        if font.exists():
            QFontDatabase.addApplicationFont(str(font))
            cls.app.setFont(QFont("Segoe UI", 10))
        cls.root = Path(__file__).resolve().parents[2]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        self.engine = QQmlEngine()
        self.display_mode = DisplayMode()
        self.engine.rootContext().setContextProperty("displayMode", self.display_mode)
        self.errors = []
        self.engine.warnings.connect(lambda errors: self.errors.extend(error.toString() for error in errors))
        self.engine.rootContext().setContextProperty("mainWindow", None)
        for name, source in {
            "QGCPalette.qml": '''import QtQuick
QtObject {
property bool highContrast: displayMode.highContrast
property bool colorGroupEnabled: true
property color window: "#050A06"
property color windowShade: "#101910"
property color windowShadeLight: "#273324"
property color button: "#0B160B"
property color buttonText: "#D6FF85"
property color buttonBorder: "#C5F779"
property color groupBorder: "#C5F779"
property color text: "#F5FFE9"
property color warningText: "#FFD166"
property color buttonHighlight: "#C5F779"
property color buttonHighlightText: "#071007"
}''',
            "QGCLabel.qml": 'import QtQuick\nText { QGCPalette { id: labelPalette } color: labelPalette.text; font.family: "Segoe UI"; font.pointSize: 10 }',
            "QGCColoredImage.qml": 'import QtQuick\nItem { property url source; property size sourceSize: Qt.size(0,0); property int fillMode; property color color }',
            "QGCButton.qml": '''import QtQuick
import QtQuick.Controls
Button {
id: control
property string iconSource: ""
property color textColor: "white"
property int _horizontalPadding: 3
property real pointSize: 10
property int wrapMode: Text.WordWrap
font.pointSize: pointSize
contentItem: Text { text: control.text; color: control.textColor; font: control.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
}''',
            "DeadMouseArea.qml": 'import QtQuick\nMouseArea { acceptedButtons: Qt.AllButtons }',
            "QGCCompassWidget.qml": 'import QtQuick\nItem { property var vehicle; property real size: 112; implicitWidth: size; implicitHeight: size }',
        }.items():
            (self.folder / name).write_text(source, encoding="utf-8")
        palette_source = (self.root / 'src/QmlControls/QGCPalette.cc').read_text(encoding='utf-8')
        contrast_colors = dict(re.findall(r'\{"(\w+)", "(#[0-9A-F]+)"\}', palette_source))
        normal_colors = dict(re.findall(r'DECLARE_QGC_COLOR\(\s*(\w+),\s*"[^"]+",\s*"[^"]+",\s*"[^"]+",\s*"([^"]+)"', palette_source))
        palette = (self.folder / 'QGCPalette.qml').read_text()
        for name, color in contrast_colors.items():
            normal = normal_colors.get(name, color)
            palette = re.sub(r'property color ' + name + r': "[^"]+"',
                             f'property color {name}: highContrast ? "{color}" : "{normal}"', palette)
        (self.folder / 'QGCPalette.qml').write_text(palette, encoding='utf-8')
        for filename in ["MissionHoldButton.qml", "RightMissionPanel.qml"]:
            source = (self.root / "src/FlyView" / filename).read_text(encoding="utf-8")
            source = "\n".join(line for line in source.splitlines() if not line.startswith("import QGroundControl"))
            (self.folder / filename).write_text(source, encoding="utf-8")
        source = (self.root / "src/QmlControls/PipState.qml").read_text(encoding="utf-8")
        (self.folder / "PipState.qml").write_text(source, encoding="utf-8")
        header = (self.root / "src/Toolbar/FlightTelemetryHeader.qml").read_text(encoding="utf-8")
        header = "\n".join(line for line in header.splitlines() if not line.startswith("import QGroundControl"))
        header = header.replace("QGroundControl.unitsConversion", "null")
        (self.folder / "FlightTelemetryHeader.qml").write_text(header, encoding="utf-8")

    def tearDown(self):
        if hasattr(self, "window"):
            self.window.close()
        if hasattr(self, "item"):
            self.item.setParentItem(None)
            self.item.deleteLater()
        self.app.processEvents()
        self.engine.deleteLater()
        self.display_mode.deleteLater()
        self.app.processEvents()
        self.temp.cleanup()

    def load(self, source, width=1024, height=768):
        source = source.replace("ScreenTools.", "screenTools.")
        prefix = '''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
width: 1024; height: 768
QtObject { id: screenTools; property int smallFontPointSize: 10; property string normalFontFamily: "Segoe UI"; property string fixedFontFamily: "Consolas" }
'''
        path = self.folder / "Harness.qml"
        path.write_text(prefix + source + "\n}", encoding="utf-8")
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(path)))
        self.assertFalse(self.component.isError(), [error.toString() for error in self.component.errors()])
        self.item = self.component.create()
        self.assertIsNotNone(self.item)
        self.item.setWidth(width)
        self.item.setHeight(height)
        self.window = QQuickWindow()
        self.window.resize(width, height)
        self.item.setParentItem(self.window.contentItem())
        self.window.show()
        QTest.qWait(60)

    def call(self, obj, method, *args):
        values = [QJSValue(value if isinstance(value, (bool, str)) else float(value)) for value in args]
        result = self.engine.newQObject(obj).property(method).call(values)
        self.assertFalse(result.isError(), result.toString())
        return result

    def hold_scene(self):
        self.load('''
readonly property var button: held
property int requests: 0
QtObject { id: craft }
MissionHoldButton {
id: held; x: 20; y: 20; width: 140; height: 60
text: "Abort"; command: "Abort"; holdDuration: 1000
vehicleIdentity: craft; applicationActive: true
onCommitted: parent.requests++
}''')
        return self.item.property("button")

    def press(self):
        QTest.mouseMove(self.window, QPoint(80, 45))
        QTest.mousePress(self.window, Qt.LeftButton, Qt.NoModifier, QPoint(80, 45))

    def test_hold_threshold_and_no_repeat(self):
        button = self.hold_scene()
        self.press()
        button.setProperty("_startedMs", int(time.time() * 1000) - 800)
        QTest.qWait(40)
        self.assertEqual(self.item.property("requests"), 0)
        button.setProperty("_startedMs", int(time.time() * 1000) - 1000)
        QTest.qWait(40)
        self.assertEqual(self.item.property("requests"), 1)
        QTest.qWait(80)
        self.assertEqual(self.item.property("requests"), 1)

    def test_early_release_pointer_exit_and_focus(self):
        button = self.hold_scene()
        self.press()
        QTest.mouseRelease(self.window, Qt.LeftButton, Qt.NoModifier, QPoint(80, 45))
        self.assertFalse(button.property("holding"))
        self.press()
        QTest.mouseMove(self.window, QPoint(250, 150))
        QTest.qWait(40)
        self.assertFalse(button.property("holding"))
        QTest.mouseRelease(self.window, Qt.LeftButton, Qt.NoModifier, QPoint(250, 150))
        self.press()
        button.setProperty("applicationActive", False)
        self.assertFalse(button.property("holding"))
        self.assertEqual(self.item.property("requests"), 0)

    def test_view_disable_and_vehicle_cancel(self):
        button = self.hold_scene()
        for property_name in ["contextActive", "enabled", "visible"]:
            self.press()
            button.setProperty(property_name, False)
            self.assertFalse(button.property("holding"))
            QTest.mouseRelease(self.window, Qt.LeftButton, Qt.NoModifier, QPoint(80, 45))
            button.setProperty(property_name, True)
        self.press()
        button.setProperty("vehicleIdentity", None)
        self.assertFalse(button.property("holding"))
        self.assertEqual(self.item.property("requests"), 0)

    def test_camera_hold_stops_when_controls_hide(self):
        source = (self.root / "src/FlyView/FlyViewCameraControls.qml").read_text(encoding="utf-8")
        ptz = source.split("component PtzButton : IconButton {", 1)[1].split("\n    Timer {\n        interval: 250", 1)[0]
        self.load('''
id: root
property var commands: []
signal motionStopped()
function _send(command) { commands = commands.concat([command]); return true }
property real _btnHeight: 44
PtzButton { id: moved; x: 20; y: 20; width: 100; height: 50; ptzAction: "pan-up" }
readonly property var button: moved
component PtzButton: Button {
''' + ptz)
        QTest.mousePress(self.window, Qt.LeftButton, Qt.NoModifier, QPoint(60, 40))
        QTest.qWait(220)
        self.call(self.item, "motionStopped")
        commands = self.item.property("commands").toVariant()
        self.assertEqual(commands[-1], "stop")
        count = len(commands)
        QTest.qWait(250)
        self.assertEqual(len(self.item.property("commands").toVariant()), count)
        self.assertFalse(self.errors, self.errors)

    def panel_scene(self, width=1024, height=768):
        for name in ["RightMissionPanel.qml", "FlightTelemetryHeader.qml"]:
            path = self.folder / name
            path.write_text(path.read_text(encoding="utf-8").replace("ScreenTools.", "screenTools."), encoding="utf-8")
        self.load('''
    Rectangle { QGCPalette { id: pagePalette } anchors.fill: parent; color: pagePalette.window }
readonly property var panel: panel
readonly property var craft: craft
readonly property var header: header
property int abortRequests: 0
property int engageRequests: 0
property int secondaryRequests: 0
QtObject {
id: craft
property bool initialConnectComplete: true
property bool armed: true
property bool flying: true
property string flightMode: "Hold"
property var flightModes: ["Abort", "Engagement"]
property bool armedTimerSinceConnection: false
property double positionTimestampMs: Date.now()
property var coordinate: ({isValid:true, latitude:24.1, longitude:67.2})
property var homePosition: ({isValid:true})
property var vehicleLinkManager: QtObject { property bool communicationLost: false }
property var vehicle: QtObject {
property double attitudeTimestampMs: Date.now()
property double motionTimestampMs: Date.now()
property double altitudeTimestampMs: Date.now()
property var heading: QtObject { property real rawValue: 92 }
property var groundSpeed: QtObject { property real rawValue: 12; property real value: 12; property string units: "m/s" }
property var climbRate: QtObject { property real rawValue: -2; property real value: -2; property string units: "m/s" }
property var altitudeRelative: QtObject { property real rawValue: 80; property real value: 80; property string units: "m" }
property var distanceToHome: QtObject { property real rawValue: 300; property real value: 300; property string units: "m" }
property var clock: QtObject { property real rawValue: 3661 }
function getFact(name) { return clock }
}
}
QtObject { id: guided; property bool showTakeoff: true }
QtObject {
id: engagement
property string abortModeName: "Abort"
property string engagementModeName: "Engagement"
function abort() { abortRequests++ }
function engage() { engageRequests++ }
}
QtObject {
id: modeAction
property bool visible: true
property bool enabled: true
property string text: "Flight Mode"
property string iconSource: ""
property Component dropPanelComponent: Component {
ColumnLayout {
implicitWidth: 180
Button { objectName: "modeChoice"; text: "Hold"; onClicked: { secondaryRequests++; dropPanel.hide() } }
}
}
signal triggered(var button)
}
FlightTelemetryHeader {
id: header; x: 0; y: 0; width: parent.width; height: implicitHeight
vehicle: craft
pendingTarget: ({isValid:true, latitude:24.2, longitude:67.3})
designatedTarget: ({isValid:true, latitude:24.4, longitude:67.5})
}
RightMissionPanel {
id: panel; width: 280; height: parent.height - header.height
x: parent.width - width; y: header.height
vehicle: craft; guidedController: guided; engagementController: engagement
actionModel: [modeAction]
}
''', width, height)

    def test_panel_header_runtime_and_responsive(self):
        self.panel_scene()
        panel = self.item.property("panel")
        header = self.item.property("header")
        self.assertTrue(header.property("targetPending"))
        self.assertTrue(header.property("positionFresh"))
        for width, height in [(1366, 768), (1024, 600), (800, 600)]:
            self.window.resize(width, height)
            self.item.setWidth(width)
            self.item.setHeight(height)
            QTest.qWait(80)
            self.assertGreater(panel.height(), 250)
            preview = self.engine.newQObject(panel).property("previewSlot").toQObject()
            point = preview.mapToItem(self.item, 0, 0)
            self.assertLessEqual(point.y() + preview.height(), height)
            self.assertGreater(point.x(), width / 2)
            image = self.window.grabWindow()
            self.assertFalse(image.isNull())
            def check_text(item):
                if item.inherits("QQuickText") and item.isVisible():
                    self.assertLessEqual(item.property("contentWidth"), item.width() + 2)
                for child in item.childItems(): check_text(child)
            check_text(header)
            output = os.environ.get("STRATUM_RIGHT_PANEL_SCREENSHOTS")
            if output: image.save(str(Path(output) / f"stratum-right-panel-{width}.png"))
        self.assertFalse(self.errors, self.errors)

    def test_normal_colors_and_live_high_contrast_restore(self):
        self.panel_scene(1366, 768)
        panel = self.item.property("panel")
        engage = self.item.findChild(QObject, "missionEngage")
        takeoff = self.item.findChild(QObject, "missionTakeoff")
        self.assertEqual(panel.property("color"), QColor("#050A06"))
        self.display_mode.highContrast = False
        self.assertEqual(panel.property("color"), QColor("#06131B"))
        self.assertEqual(engage.property("background").property("color"), QColor("#7C202C"))
        self.assertEqual(takeoff.property("background").property("color"), QColor("#073E37"))
        self.assertEqual(engage.property("holdDuration"), 3000)
        self.assertEqual(engage.property("foreground"), QColor("#F1F7FA"))
        self.display_mode.highContrast = True
        self.assertEqual(panel.property("color"), QColor("#050A06"))
        self.assertEqual(engage.property("background").property("color"), QColor("#0B160B"))
        self.assertEqual(engage.property("foreground"), QColor("#D6FF85"))
        self.assertFalse(self.errors, self.errors)

    def test_both_themes_render_at_field_sizes(self):
        self.panel_scene()
        output = os.environ.get("STRATUM_RIGHT_PANEL_SCREENSHOTS")
        for normal in [True, False]:
            self.display_mode.highContrast = not normal
            for width, height in [(1366, 768), (1024, 600), (800, 600)]:
                self.window.resize(width, height)
                self.item.setWidth(width)
                self.item.setHeight(height)
                QTest.qWait(60)
                image = self.window.grabWindow()
                self.assertFalse(image.isNull())
                engage = self.item.findChild(QObject, "missionEngage")
                point = engage.mapToItem(self.item, 6, 6).toPoint()
                self.assertEqual(image.pixelColor(point), QColor("#7C202C" if normal else "#0B160B"))
                if output: image.save(str(Path(output) / f"stratum-{'normal' if normal else 'contrast'}-{width}.png"))
        self.assertFalse(self.errors, self.errors)

    def test_header_pending_designated_and_stale(self):
        self.panel_scene()
        header = self.item.property("header")
        self.call(header, "duration", 0)
        self.engine.newQObject(header).setProperty("pendingTarget", QJSValue(QJSValue.NullValue))
        self.assertFalse(header.property("targetPending"))
        self.assertAlmostEqual(self.engine.newQObject(header).property("target").property("latitude").toNumber(), 24.4)
        facts = self.engine.newQObject(self.item.property("craft")).property("vehicle").toQObject()
        fact = self.engine.newQObject(facts).property("clock").toQObject()
        value = self.engine.newQObject(header).property("duration").call([self.engine.newQObject(fact)])
        self.assertEqual(value.toString(), "01:01:01")
        facts.setProperty("motionTimestampMs", int(time.time() * 1000) - 3000)
        facts.setProperty("altitudeTimestampMs", int(time.time() * 1000) - 3000)
        header.setProperty("nowMs", int(time.time() * 1000))
        self.assertFalse(header.property("motionFresh"))
        self.assertFalse(header.property("altitudeFresh"))
        craft = self.item.property("craft")
        craft.setProperty("positionTimestampMs", int(time.time() * 1000) - 3000)
        header.setProperty("nowMs", int(time.time() * 1000))
        self.assertFalse(header.property("positionFresh"))

    def test_diamond_positions_and_command_dispatch(self):
        self.panel_scene(1366, 768)
        buttons = {name: self.item.findChild(QObject, "mission" + name) for name in ["Takeoff", "Abort", "Standoff", "Engage"]}
        self.assertTrue(all(buttons.values()))
        points = {name: button.mapToItem(self.item, button.width() / 2, button.height() / 2) for name, button in buttons.items()}
        self.assertLess(points["Takeoff"].y(), points["Abort"].y())
        self.assertLess(points["Abort"].x(), points["Standoff"].x())
        self.assertAlmostEqual(points["Abort"].y(), points["Standoff"].y())
        self.assertGreater(points["Engage"].y(), points["Standoff"].y())
        for name, duration, counter in [("Abort", 1000, "abortRequests"), ("Engage", 3000, "engageRequests")]:
            button = buttons[name]
            button.setProperty("applicationActive", True)
            self.assertEqual(button.property("holdDuration"), duration)
            QTest.mouseMove(self.window, points[name].toPoint())
            QTest.mousePress(self.window, Qt.LeftButton, Qt.NoModifier, points[name].toPoint())
            button.setProperty("_startedMs", int(time.time() * 1000) - duration + 100)
            QTest.qWait(30)
            self.assertEqual(self.item.property(counter), 0)
            button.setProperty("_startedMs", int(time.time() * 1000) - duration)
            QTest.qWait(40)
            self.assertEqual(self.item.property(counter), 1)
            self.assertTrue(self.item.property("panel").property("holdComplete"))
            self.assertEqual(self.item.property("panel").property("holdProgress"), 1)
            QTest.qWait(40)
            self.assertEqual(self.item.property(counter), 1)
            QTest.mouseRelease(self.window, Qt.LeftButton, Qt.NoModifier, points[name].toPoint())
        self.assertFalse(self.errors, self.errors)

    def test_pip_full_view_parent_is_not_preview_slot(self):
        self.load('''
readonly property var surface: surface
readonly property var preview: preview
readonly property var video: video
readonly property var pipState: video.pipState
Item { id: surface; width: 700; height: 600 }
Item { id: preview; x: 720; y: 500; width: 280; height: 158 }
Item {
id: pip
property var fullItemParent: surface
property var _pipContentItem: preview
property var _windowContentItem: preview
function showWindow() {}
}
Item {
id: video
property alias pipState: stateControl
PipState { id: stateControl; pipView: pip }
}
''')
        state = self.engine.newQObject(self.item).property("pipState").toQObject()
        video = self.item.property("video")
        state.setProperty("state", "pip")
        self.app.processEvents()
        self.assertEqual(video.parentItem(), self.item.property("preview"))
        state.setProperty("state", "full")
        self.app.processEvents()
        self.assertEqual(video.parentItem(), self.item.property("surface"))
        self.assertEqual(video.width(), 700)
        self.assertFalse(self.errors, self.errors)

    def test_secondary_popup_preserves_drop_panel_context(self):
        self.panel_scene(1366, 900)
        def visual_child(item, name):
            if item.objectName() == name: return item
            for child in item.childItems():
                found = visual_child(child, name)
                if found: return found
            return None
        button = visual_child(self.item, "missionSecondary_Flight Mode")
        self.assertIsNotNone(button)
        point = button.mapToItem(self.item, button.width() / 2, button.height() / 2)
        QTest.mouseClick(self.window, Qt.LeftButton, Qt.NoModifier, point.toPoint())
        QTest.qWait(80)
        choice = visual_child(self.window.contentItem(), "modeChoice")
        self.assertIsNotNone(choice)
        self.call(choice, "clicked")
        self.assertEqual(self.item.property("secondaryRequests"), 1)
        self.assertFalse(self.errors, self.errors)


if __name__ == "__main__":
    unittest.main()