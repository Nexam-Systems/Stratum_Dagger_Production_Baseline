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
        self._light = False

    def set_contrast(self, value):
        self._contrast = value
        self._light = False
        self.changed.emit()

    def set_light(self, value):
        self._light = value
        if value:
            self._contrast = False
        self.changed.emit()

    highContrast = Property(bool, lambda self: self._contrast, set_contrast, notify=changed)
    lightTheme = Property(bool, lambda self: self._light, set_light, notify=changed)


class VehicleManagerStub(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self._vehicle = None

    def _set(self, vehicle):
        self._vehicle = vehicle
        self.changed.emit()

    activeVehicle = Property(QObject, lambda self: self._vehicle, _set, notify=changed)


class QGroundControlStub(QObject):
    def __init__(self):
        super().__init__()
        self.manager = VehicleManagerStub()

    multiVehicleManager = Property(QObject, lambda self: self.manager, constant=True)


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

    def test_changed_fly_view_and_toolbar_qml_cache_compile(self):
        compiler = shutil.which("qmlcachegen")
        if not compiler:
            candidates = [Path(PySide6.__file__).parent / "qmlcachegen.exe",
                          Path(PySide6.__file__).parent / "qmlcachegen"]
            compiler = next((str(path) for path in candidates if path.is_file()), None)
        if not compiler:
            self.skipTest("Qt qmlcachegen is unavailable")
        sources = [
            "src/FlyView/FlyView.qml",
            "src/FlyView/FlyViewVideoOSD.qml",
            "src/FlyView/FlyViewVideo.qml",
            "src/FlyView/RightMissionPanel.qml",
            "src/FlyView/FlyViewTopRightColumnLayout.qml",
            "src/Toolbar/FlightTelemetryHeader.qml",
            "src/Toolbar/FlyViewToolBar.qml",
            "src/Toolbar/FlyViewToolBarIndicators.qml",
            "src/Toolbar/GPSIndicator.qml",
            "src/Toolbar/MainStatusIndicator.qml",
            "src/Toolbar/RCRSSIIndicator.qml",
            "src/Toolbar/TelemetryRSSIIndicator.qml",
            "src/Toolbar/VehicleGPSIndicator.qml",
            "src/Toolbar/BatteryIndicator.qml",
            "src/Toolbar/SignalStrength.qml",
            "src/FlightMap/Widgets/QGCCompassWidget.qml",
        ]
        for index, relative_path in enumerate(sources):
            source = self.root / relative_path
            result = subprocess.run([compiler, "--bare", "--resource-path",
                                     "/qml/QGroundControl/" + relative_path.removeprefix("src/"),
                                     "-o", str(self.folder / f"changed-{index}.cpp"), str(source)], capture_output=True)
            self.assertEqual(result.returncode, 0, f"{relative_path}: {result.stderr.decode(errors='replace')}")

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
        self.qgc = QGroundControlStub()
        self.engine.rootContext().setContextProperty("QGroundControl", self.qgc)
        for name, source in {
            "QGCPalette.qml": '''import QtQuick
QtObject {
property bool highContrast: displayMode.highContrast
property bool lightTheme: displayMode.lightTheme
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
            "QGCCompassWidget.qml": 'import QtQuick\nItem { property var vehicle; property bool showHeadingLabel: true; property real size: 112; implicitWidth: size; implicitHeight: size }',
        }.items():
            (self.folder / name).write_text(source, encoding="utf-8")
        palette_source = (self.root / 'src/QmlControls/QGCPalette.cc').read_text(encoding='utf-8')
        contrast_colors = dict(re.findall(r'\{"(\w+)", "(#[0-9A-F]+)"\}', palette_source))
        normal_colors = dict(re.findall(r'DECLARE_QGC_COLOR\(\s*(\w+),\s*"[^"]+",\s*"[^"]+",\s*"[^"]+",\s*"([^"]+)"', palette_source))
        light_colors = {name: (disabled, enabled) for name, disabled, enabled in re.findall(
            r'DECLARE_QGC_COLOR\(\s*(\w+),\s*"([^"]+)",\s*"([^"]+)",\s*"[^"]+",\s*"[^"]+"', palette_source)}
        palette = (self.folder / 'QGCPalette.qml').read_text()
        for name in sorted(set(contrast_colors) | set(normal_colors)):
            normal = normal_colors[name] if name in normal_colors else contrast_colors[name]
            color = contrast_colors.get(name, normal)
            disabled, enabled = light_colors.get(name, (normal, normal))
            declaration = f'property color {name}: lightTheme ? (colorGroupEnabled ? "{enabled}" : "{disabled}") : highContrast ? "{color}" : "{normal}"'
            pattern = r'property color ' + name + r': "[^"]+"'
            if re.search(pattern, palette):
                palette = re.sub(pattern, declaration, palette)
            else:
                palette = palette.rsplit('}', 1)[0] + declaration + '\n}'
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

    def test_status_drawer_click_targets_follow_the_status_labels(self):
        source = (self.root / "src/Toolbar/MainStatusIndicator.qml").read_text(encoding="utf-8")
        status_label = source.split("id:                 mainStatusLabel", 1)[1].split("id:                 mainStatusChevron", 1)[0]
        chevron = source.split("id:                 mainStatusChevron", 1)[1].split("id:                 vtolModeLabel", 1)[0]
        self.assertIn("MouseArea", status_label)
        self.assertIn("onClicked:      control.dropMainStatusIndicator()", status_label)
        self.assertIn("MouseArea", chevron)
        self.assertIn("onClicked:      control.dropMainStatusIndicator()", chevron)
        self.assertNotIn("statusHoverArea", source)

    def test_photo_video_controls_are_not_loaded_in_right_dock(self):
        source = (self.root / "src/FlyView/FlyViewTopRightColumnLayout.qml").read_text(encoding="utf-8")
        self.assertIn("TerrainProgress", source)
        self.assertNotIn("PhotoVideoControl", source)

    def test_roi_overlay_is_not_on_the_video_and_dock_feedback_presentation(self):
        video = (self.root / "src/FlyView/FlyViewVideo.qml").read_text(encoding="utf-8")
        self.assertNotIn("TrackerRoiOverlay", video)
        self.assertFalse((self.root / "src/FlyView/TrackerRoiOverlay.qml").exists())
        panel = (self.root / "src/FlyView/RightMissionPanel.qml").read_text(encoding="utf-8")
        self.assertNotIn("text: root.feedback", panel)
        self.panel_scene()
        compass = self.item.findChild(QObject, "missionCompass")
        self.assertIsNotNone(compass)
        self.assertFalse(compass.property("showHeadingLabel"))
        self.assertFalse(self.errors, self.errors)

    def test_toolbar_indicator_palette_and_font_consistency(self):
        for name in ["GPSIndicator", "RCRSSIIndicator", "TelemetryRSSIIndicator", "BatteryIndicator"]:
            source = (self.root / f"src/Toolbar/{name}.qml").read_text(encoding="utf-8")
            self.assertIn('"#79CBE8"', source)
            self.assertIn("qgcPal.highContrast", source)
            self.assertIn("control.indicatorColor", source)
        source = (self.root / "src/Toolbar/FlightTelemetryHeader.qml").read_text(encoding="utf-8")
        compact = source.split("id: compactValueLabel", 1)[1].split("QGCLabel {", 1)[0]
        self.assertIn("font.family: ScreenTools.normalFontFamily", compact)
        self.assertIn("font.pointSize: ScreenTools.smallFontPointSize", compact)
        self.assertNotIn("font.bold: true", compact)

    def test_video_osd_is_hidden_in_picture_in_picture(self):
        video_source = (self.root / "src/FlyView/FlyViewVideo.qml").read_text(encoding="utf-8")
        osd_source = (self.root / "src/FlyView/FlyViewVideoOSD.qml").read_text(encoding="utf-8")
        self.assertIn("visible:    videoStreaming.visible && _root.pipState.state === _root.pipState.fullState", video_source)
        # KAN-41: the overlay is only the centre crosshair (hidden in PiP), no telemetry readouts.
        self.assertIn("visible:          !_root.compact", osd_source)
        self.assertIn("ReticleMark {", osd_source)
        self.assertNotIn("factText", osd_source)
        self.assertNotIn("HUDField", osd_source)

    def panel_scene(self, width=1024, height=768):
        for name in ["RightMissionPanel.qml", "FlightTelemetryHeader.qml"]:
            path = self.folder / name
            path.write_text(path.read_text(encoding="utf-8").replace("ScreenTools.", "screenTools."), encoding="utf-8")
        self.load('''
    Rectangle { QGCPalette { id: pagePalette } anchors.fill: parent; color: pagePalette.window }
readonly property var panel: panel
readonly property var craft: craft
readonly property var header: header
readonly property var action: modeAction
property int abortRequests: 0
property int engageRequests: 0
property int killRequests: 0
property int secondaryRequests: 0
QtObject {
id: craft
property bool killSwitchEngaged: false
function setKillSwitchEngaged(engaged) { killSwitchEngaged = engaged; killRequests++ }
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
readonly property var flightTime: clock
}
}
QtObject { id: guided; property bool showTakeoff: true; property bool showChangeAlt: true }
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
property string text: "Payload"
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
id: panel; width: Math.min(138, Math.max(122, parent.width * 0.11)); height: parent.height - header.height
x: parent.width - width - 6; y: header.height
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
            check_text(panel)
            for name in ["missionTakeoff", "missionAbort", "missionStandoff", "missionEngage"]:
                button = self.item.findChild(QObject, name)
                self.assertIsNotNone(button)
                button_right = button.mapToItem(panel, button.width(), 0).x()
                self.assertLessEqual(button_right, panel.width() + 1)
            output = os.environ.get("STRATUM_RIGHT_PANEL_SCREENSHOTS")
            if output: image.save(str(Path(output) / f"stratum-right-panel-{width}.png"))
        self.assertFalse(self.errors, self.errors)

    def test_compact_header_fits_toolbar_height(self):
        self.panel_scene(1024, 700)
        header = self.item.property("header")
        header.setProperty("compact", True)
        header.setWidth(520)
        header.setHeight(54)
        QTest.qWait(80)
        self.assertLessEqual(header.property("implicitHeight"), 54)
        fields = next(child for child in header.childItems() if child.metaObject().className() == "QQuickGridLayout")
        self.assertGreaterEqual(fields.y(), 5)
        self.assertGreaterEqual(fields.property("rowSpacing"), 5)
        image = self.window.grabWindow()
        self.assertFalse(image.isNull())
        output = os.environ.get("STRATUM_RIGHT_PANEL_SCREENSHOTS")
        if output:
            image.save(str(Path(output) / "stratum-compact-toolbar-header.png"))
        self.assertFalse(self.errors, self.errors)

    def test_emergency_kill_is_below_change_height_and_latches_until_pressed_again(self):
        self.panel_scene(1024, 768)
        craft = self.item.property("craft")
        kill = self.item.findChild(QObject, "missionEmergencyKill")
        change_height = self.item.findChild(QObject, "missionChangeHeight")
        self.assertIsNotNone(kill)
        self.assertEqual(kill.property("text"), "Emergency Kill")
        self.assertEqual(kill.property("shortText"), "E-Kill")
        self.assertGreaterEqual(kill.mapToItem(self.item, 0, 0).y(),
                                change_height.mapToItem(self.item, 0, change_height.height()).y())

        # No gating: any mode, disarmed, on the ground, even with the link reported lost.
        craft.setProperty("armed", False)
        craft.setProperty("flying", False)
        craft.setProperty("flightMode", "Land")
        self.engine.newQObject(craft).property("vehicleLinkManager").toQObject().setProperty("communicationLost", True)
        QTest.qWait(60)
        self.assertTrue(kill.isEnabled())

        point = kill.mapToItem(self.item, kill.width() / 2, kill.height() / 2).toPoint()
        QTest.mouseClick(self.window, Qt.LeftButton, Qt.NoModifier, point)
        QTest.qWait(30)
        self.assertEqual(self.item.property("killRequests"), 1)     # first click engages, no confirmation step
        self.assertTrue(craft.property("killSwitchEngaged"))
        self.assertEqual(kill.property("text"), "Release Kill")     # stays latched and says how to release
        self.assertEqual(kill.property("visualRole"), "killActive")

        QTest.mouseClick(self.window, Qt.LeftButton, Qt.NoModifier, point)
        QTest.qWait(30)
        self.assertEqual(self.item.property("killRequests"), 2)     # second click releases
        self.assertFalse(craft.property("killSwitchEngaged"))
        self.assertEqual(kill.property("text"), "Emergency Kill")
        self.assertFalse(self.errors, self.errors)

    def test_every_right_panel_button_is_visible_without_scrolling(self):
        names = ["missionDefineAOP", "missionFetchTarget", "missionTakeoff", "missionLand", "missionHold",
                 "missionManual", "missionRTL", "missionStandoff", "missionAbort", "missionEngage",
                 "missionChangeHeight", "missionEmergencyKill"]
        panel_source = (self.root / "src/FlyView/RightMissionPanel.qml").read_text(encoding="utf-8")
        self.assertNotIn("CAMERA FEED", panel_source)
        self.assertNotIn("Flickable {", panel_source.split("Popup {", 1)[0])
        self.panel_scene(1366, 768)
        self.item.property("action").setProperty("visible", False)   # the profile-specific extra button
        panel = self.item.property("panel")
        for width, height in [(1366, 768), (1920, 1080), (1600, 900)]:
            self.window.resize(width, height)
            self.item.setWidth(width)
            self.item.setHeight(height)
            QTest.qWait(80)
            compass = self.item.findChild(QObject, "missionCompass")
            self.assertTrue(compass.isVisible())
            compass_top = compass.mapToItem(panel, 0, 0).y()
            rects = []
            for name in names:
                button = self.item.findChild(QObject, name)
                self.assertIsNotNone(button, name)
                top_left = button.mapToItem(panel, 0, 0)
                rect = (top_left.x(), top_left.y(), top_left.x() + button.width(), top_left.y() + button.height())
                self.assertGreaterEqual(rect[0], 0, name)
                self.assertLessEqual(rect[2], panel.width() + 1, name)
                self.assertLessEqual(rect[3], compass_top, f"{name} is hidden behind the compass at {height}")
                self.assertGreaterEqual(button.height(), 32, name)
                for other_name, other in rects:
                    apart = rect[2] <= other[0] + 1 or other[2] <= rect[0] + 1 or rect[3] <= other[1] + 1 or other[3] <= rect[1] + 1
                    self.assertTrue(apart, f"{name} overlaps {other_name} at {height}")
                rects.append((name, rect))
        self.assertFalse(self.errors, self.errors)

    def test_background_opacity_fades_only_the_panel_chrome(self):
        self.panel_scene(1366, 768)
        self.display_mode.highContrast = False                     # normal theme: panel base alpha 0.8
        panel = self.item.property("panel")
        engage = self.item.findChild(QObject, "missionEngage")
        preview = self.engine.newQObject(panel).property("previewSlot").toQObject()
        compass = self.item.findChild(QObject, "missionCompass")
        QTest.qWait(40)
        button_color = engage.property("background").property("color")
        border = lambda: self.engine.newQObject(panel).property("border").toQObject().property("color")

        self.assertAlmostEqual(panel.property("color").alphaF(), 0.8, places=2)      # default 100%: as before
        self.assertGreater(border().alphaF(), 0.9)

        panel.setProperty("backgroundOpacity", 0.5)
        QTest.qWait(40)
        self.assertAlmostEqual(panel.property("color").alphaF(), 0.4, places=2)
        self.assertAlmostEqual(border().alphaF(), 0.5 * 1.0, places=1)

        panel.setProperty("backgroundOpacity", 0.0)
        QTest.qWait(40)
        self.assertEqual(panel.property("color").alpha(), 0)                          # no background ...
        self.assertEqual(border().alpha(), 0)                                         # ... and no border
        # buttons, compass and preview are untouched
        self.assertEqual(engage.property("background").property("color"), button_color)
        self.assertEqual(engage.property("opacity"), 1.0)
        self.assertEqual(preview.property("opacity"), 1.0)
        self.assertTrue(compass.isVisible())
        self.assertEqual(compass.property("opacity"), 1.0)
        self.assertTrue(engage.isEnabled())
        self.assertFalse(self.errors, self.errors)

    def test_opacity_is_an_admin_setting_and_the_map_runs_under_the_panel(self):
        settings = {f["name"]: f for f in __import__("json").loads(
            (self.root / "src/Settings/FlyView.SettingsGroup.json").read_text(encoding="utf-8"))["QGC.MetaData.Facts"]}
        fact = settings["rightPanelOpacity"]
        self.assertEqual((fact["default"], fact["min"], fact["max"]), (100, 0, 100))
        self.assertIn("DEFINE_SETTINGFACT(rightPanelOpacity)", (self.root / "src/Settings/FlyViewSettings.h").read_text(encoding="utf-8"))
        self.assertIn("DECLARE_SETTINGSFACT(FlyViewSettings, rightPanelOpacity)", (self.root / "src/Settings/FlyViewSettings.cc").read_text(encoding="utf-8"))
        self.assertIn("_flyView.rightPanelOpacity", (self.root / "src/Toolbar/AdminSettingsDialog.qml").read_text(encoding="utf-8"))
        layer = (self.root / "src/FlyView/FlyViewWidgetLayer.qml").read_text(encoding="utf-8")
        self.assertIn("rightPanelOpacity.rawValue", layer.split("RightMissionPanel {", 1)[1])
        fly_view = (self.root / "src/FlyView/FlyView.qml").read_text(encoding="utf-8")
        surface = fly_view.split("id: flightSurface", 1)[1].split("}", 1)[0]
        self.assertNotIn("rightMargin", surface)                   # the map is no longer cut off at the panel
        self.assertIn("rightDockInset:         _root._dockWidth", fly_view)

    def test_compass_is_visible_below_secondary_actions(self):
        self.panel_scene(1024, 768)
        panel = self.item.property("panel")

        def visual_child(item, name):
            if item.objectName() == name:
                return item
            for child in item.childItems():
                found = visual_child(child, name)
                if found:
                    return found
            return None

        compass = visual_child(panel, "missionCompass")
        define_aop = visual_child(panel, "missionDefineAOP")
        last_action = visual_child(panel, "missionEngage")
        self.assertIsNotNone(compass)
        self.assertIsNotNone(define_aop)
        self.assertIsNotNone(last_action)
        self.assertTrue(compass.isVisible())
        compass_top = compass.mapToItem(panel, 0, 0).y()
        compass_point = compass.mapToItem(panel, 0, compass.height())
        action_point = last_action.mapToItem(panel, 0, last_action.height())
        self.assertGreater(compass_point.y(), action_point.y())
        preview = self.engine.newQObject(panel).property("previewSlot").toQObject()
        preview_bottom = preview.mapToItem(panel, 0, preview.height()).y()
        self.assertLessEqual(preview_bottom, panel.height() - 9)
        self.assertLessEqual(panel.width(), 138)
        self.assertFalse(self.errors, self.errors)

    def test_engage_enabled_by_default_and_hold_commits(self):
        self.panel_scene(1024, 1000)
        panel = self.item.property("panel")
        engage = self.item.findChild(QObject, "missionEngage")

        def visual_child(item, name):
            if item.objectName() == name:
                return item
            for child in item.childItems():
                found = visual_child(child, name)
                if found:
                    return found
            return None

        # KAN-21: the enable-engage confirmation toggle was removed. Engage is enabled by
        # default whenever it is eligible; the 3 s hold-to-confirm is the only interlock.
        self.assertIsNone(visual_child(panel, "missionEngageConfirmation"))
        self.assertTrue(engage.isEnabled())

        craft = self.item.property("craft")
        craft.setProperty("flying", False)
        QTest.qWait(60)
        self.assertFalse(engage.isEnabled())
        craft.setProperty("flying", True)
        QTest.qWait(60)
        self.assertTrue(engage.isEnabled())

        engage.setProperty("applicationActive", True)
        engage_point = engage.mapToItem(self.item, engage.width() / 2, engage.height() / 2)
        QTest.mouseMove(self.window, engage_point.toPoint())
        QTest.mousePress(self.window, Qt.LeftButton, Qt.NoModifier, engage_point.toPoint())
        self.assertTrue(engage.property("holding"))
        engage.setProperty("_startedMs", int(time.time() * 1000) - 3000)
        QTest.qWait(50)
        self.assertEqual(self.item.property("engageRequests"), 1)
        QTest.mouseRelease(self.window, Qt.LeftButton, Qt.NoModifier, engage_point.toPoint())
        self.assertFalse(self.errors, self.errors)

    def test_light_panel_and_command_contrast(self):
        self.panel_scene(1366, 768)
        self.display_mode.lightTheme = True
        QTest.qWait(80)
        panel = self.item.property("panel")
        self.assertEqual(panel.property("color"), QColor("white"))

        def luminance(color):
            channels = (color.redF(), color.greenF(), color.blueF())
            linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
            return sum(value * weight for value, weight in zip(linear, (0.2126, 0.7152, 0.0722)))

        for name in ["missionTakeoff", "missionAbort", "missionStandoff", "missionEngage"]:
            button = self.item.findChild(QObject, name)
            self.assertIsNotNone(button)
            foreground = button.property("foreground")
            background = button.property("background").property("color")
            low, high = sorted((luminance(foreground), luminance(background)))
            self.assertGreaterEqual((high + 0.05) / (low + 0.05), 4.5, name)
        output = os.environ.get("STRATUM_RIGHT_PANEL_SCREENSHOTS")
        if output:
            self.window.grabWindow().save(str(Path(output) / "stratum-light-mission-panel.png"))
        self.assertEqual(self.item.property("engageRequests"), 0)
        self.assertFalse(self.errors, self.errors)

    def test_normal_colors_and_live_high_contrast_restore(self):
        self.panel_scene(1366, 768)
        panel = self.item.property("panel")
        engage = self.item.findChild(QObject, "missionEngage")
        takeoff = self.item.findChild(QObject, "missionTakeoff")
        self.assertEqual(panel.property("color"), QColor("#050A06"))
        self.display_mode.highContrast = False
        panel_color = panel.property("color")
        self.assertEqual(panel_color.name(), "#06131b")
        self.assertLess(panel_color.alpha(), 255)
        engage_color = engage.property("background").property("color")
        takeoff_color = takeoff.property("background").property("color")
        self.assertEqual(engage_color.name(), "#b3141f")
        self.assertLess(engage_color.alpha(), 255)
        # KAN-21: non-engage/abort buttons use the neutral theme button colour.
        self.assertEqual(takeoff_color.name(), "#102d43")
        self.assertLess(takeoff_color.alpha(), 255)
        self.assertEqual(engage.property("holdDuration"), 3000)
        self.assertEqual(engage.property("foreground"), QColor("#F1F7FA"))
        self.display_mode.highContrast = True
        self.assertEqual(panel.property("color"), QColor("#050A06"))
        # KAN-21: Engage stays red in the high-contrast theme too.
        self.assertEqual(engage.property("background").property("color"), QColor("#b3141f"))
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
                engage = self.item.findChild(QObject, "missionEngage")
                QTest.qWait(60)
                image = self.window.grabWindow()
                self.assertFalse(image.isNull())
                # KAN-21: Engage reads red in BOTH themes. Check the button fill directly
                # (robust to the taller command list clipping the button at small heights).
                engage_color = engage.property("background").property("color")
                self.assertGreater(engage_color.red(), engage_color.green())
                self.assertGreater(engage_color.red(), engage_color.blue())
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

    def test_header_reads_flight_time_without_invokable_ownership_transfer(self):
        source = (self.root / "src/Toolbar/FlightTelemetryHeader.qml").read_text(encoding="utf-8")
        self.assertNotIn(".getFact(", source)
        self.panel_scene()
        header = self.item.property("header")

        def texts(item):
            values = [item.property("text")] if item.inherits("QQuickText") else []
            for child in item.childItems():
                values.extend(texts(child))
            return values

        self.assertIn("01:01:01", texts(header))
        for _ in range(5):
            self.engine.collectGarbage()
            self.app.processEvents()
        self.assertIn("01:01:01", texts(header))
        self.assertFalse(self.errors, self.errors)

    def test_compact_primary_positions_and_command_dispatch(self):
        self.panel_scene(1366, 1000)
        buttons = {name: self.item.findChild(QObject, "mission" + name) for name in ["Takeoff", "Abort", "Standoff", "Engage"]}
        self.assertTrue(all(buttons.values()))
        points = {name: button.mapToItem(self.item, button.width() / 2, button.height() / 2) for name, button in buttons.items()}
        # KAN-51: single column of circular buttons -- Takeoff, ..., Standoff, Abort, Engage.
        self.assertAlmostEqual(points["Takeoff"].x(), points["Engage"].x(), delta=1)
        self.assertAlmostEqual(points["Standoff"].x(), points["Abort"].x(), delta=1)
        self.assertLess(points["Takeoff"].y(), points["Standoff"].y())
        self.assertLess(points["Standoff"].y(), points["Abort"].y())
        self.assertLess(points["Abort"].y(), points["Engage"].y())
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
        button = visual_child(self.item, "missionSecondary_Payload")
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