import json
import os
from pathlib import Path
import re
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QUrl, Qt
from PySide6.QtGui import QGuiApplication, QColor, QFont, QFontDatabase
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest


class HighContrastTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        font = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts/segoeui.ttf"
        if font.exists():
            QFontDatabase.addApplicationFont(str(font))
            cls.app.setFont(QFont("Segoe UI", 10))
        cls.root = Path(__file__).resolve().parents[2]
        source = (cls.root / "src/QmlControls/QGCPalette.cc").read_text(encoding="utf-8")
        cls.colors = dict(re.findall(r'\{"(\w+)", "(#[0-9A-F]+)"\}', source))

    def setUp(self):
        self.engine = QQmlEngine()

    def tearDown(self):
        if hasattr(self, "window"):
            self.window.close()
        if hasattr(self, "item"):
            self.item.setParentItem(None)
            self.item.deleteLater()
        self.app.processEvents()
        self.engine.deleteLater()
        self.app.processEvents()

    @staticmethod
    def contrast(foreground, background):
        def luminance(color):
            value = QColor(color)
            channels = [value.redF(), value.greenF(), value.blueF()]
            linear = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4 for channel in channels]
            return sum(channel * weight for channel, weight in zip(linear, [0.2126, 0.7152, 0.0722]))
        first, second = sorted([luminance(foreground), luminance(background)])
        return (second + 0.05) / (first + 0.05)

    def build_scene(self):
        def body(path, base):
            text = (self.root / path).read_text(encoding="utf-8")
            return text.split(base + " {", 1)[1]

        button = body("src/QmlControls/QGCButton.qml", "Button")
        button = button.replace("qgcPal.globalTheme === QGCPalette.Light || qgcPal.globalTheme === QGCPalette.Dark", "true")
        camera_text = (self.root / "src/FlyView/FlyViewCameraControls.qml").read_text(encoding="utf-8")
        camera_button = camera_text.split("component IconButton : Button {", 1)[1].split("component SectionLabel", 1)[0]
        camera_button = camera_button.rsplit("}", 1)[0]
        palette = "component QGCPalette: QtObject { readonly property bool highContrast: true; property bool colorGroupEnabled: true;\n"
        for name, color in self.colors.items():
            disabled = {
                "button": "#202420", "primaryButton": "#202420", "buttonHighlight": "#202420",
                "text": "#B5BDB0", "buttonText": "#B5BDB0", "primaryButtonText": "#B5BDB0",
                "buttonHighlightText": "#B5BDB0", "buttonBorder": "#7D8876",
            }.get(name, color)
            palette += f'property color {name}: colorGroupEnabled ? "{color}" : "{disabled}";\n'
        palette += "}\n"
        fixture = """
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
    id: root
    width: 1024
    height: 700
    property real _btnHeight: 44
    property real _iconSize: 20
    property bool compact: false
    property color backdrop: "#E8E8E8"
    property int clicks: 0
    readonly property var takeoffButton: takeoff
    readonly property var surface: panel
    readonly property var cameraButton: camera
    readonly property var disabledButton: unavailable
    QGCPalette { id: btnPal }
    QtObject {
        id: ScreenTools
        property bool isMobile: false
        property real defaultBorderRadius: 4
        property real defaultFontPixelWidth: 8
        property real defaultFontPixelHeight: 16
        property real implicitButtonWidth: 90
        property real implicitButtonHeight: 40
        property real smallFontPointSize: 10
        property real defaultFontPointSize: 11
        property string normalFontFamily: "Segoe UI"
    }
    Rectangle { anchors.fill: parent; color: root.backdrop }
    Rectangle {
        id: panel
        x: 16; y: 16
        width: parent.width - 32
        height: content.implicitHeight + 24
        color: btnPal.window
        border.color: btnPal.buttonBorder
        border.width: 2
        ColumnLayout {
            id: content
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 12
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                QGCButton { id: takeoff; Layout.fillWidth: true; text: "Takeoff"; onClicked: root.clicks++ }
                QGCButton { Layout.fillWidth: true; text: "Hold" }
                QGCButton { Layout.fillWidth: true; text: "Abort" }
            }
            QGCLabel { text: "Standoff / DISARMED / GPS 3D"; font.bold: true }
            QGCLabel { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Comms Lost - check vehicle link"; color: btnPal.warningText }
            RowLayout {
                Layout.fillWidth: true
                CameraButton { id: camera; tip: "Centre gimbal"; text: "Centre" }
                CameraButton { tip: "Camera down"; text: "Down" }
                CameraButton { tip: "Thermal feed"; text: "IR"; primary: true }
            }
            QGCButton { id: unavailable; Layout.fillWidth: true; enabled: false; text: "Unavailable command"; onClicked: root.clicks++ }
        }
    }
"""
        fixture = fixture.replace("id: ScreenTools", "id: screenTools")
        label = 'component QGCLabel: Text { color: btnPal.text; font.family: "Segoe UI"; font.pointSize: 11 }\n'
        image = 'component QGCColoredImage: Image { property color color }\n'
        fixture += palette + label + image
        fixture += "component QGCButton: Button {" + button
        fixture += "component CameraButton: Button {" + camera_button + "}\n}"
        fixture = fixture.replace("ScreenTools.", "screenTools.")
        self.component = QQmlComponent(self.engine)
        self.component.setData(fixture.encode(), QUrl("file:///HighContrastHarness.qml"))
        self.assertFalse(self.component.isError(), [error.toString() for error in self.component.errors()])
        self.item = self.component.create()
        self.assertIsNotNone(self.item)
        self.window = QQuickWindow()
        self.item.setParentItem(self.window.contentItem())

    def test_readable_color_pairs(self):
        for foreground, background in [
            ("text", "window"), ("buttonText", "button"), ("primaryButtonText", "primaryButton"),
            ("buttonHighlightText", "buttonHighlight"), ("textFieldText", "textField"),
            ("warningText", "window"), ("statusFailedText", "window"), ("statusPendingText", "window"),
            ("alertText", "alertBackground"),
        ]:
            with self.subTest(foreground=foreground):
                self.assertGreaterEqual(self.contrast(self.colors[foreground], self.colors[background]), 4.5)
        self.assertGreaterEqual(self.contrast(self.colors["buttonBorder"], self.colors["button"]), 3)
        self.assertGreaterEqual(self.contrast("#B5BDB0", "#202420"), 4.5)

    def test_default_styling_preserves_button_behavior(self):
        self.build_scene()
        self.window.resize(1024, 700)
        self.window.show()
        QTest.qWait(60)
        self.assertEqual(self.item.property("surface").property("color"), QColor(self.colors["window"]))
        button = self.item.property("takeoffButton")
        point = button.mapToItem(self.item, button.width() / 2, button.height() / 2)
        QTest.mouseClick(self.window, Qt.LeftButton, Qt.NoModifier, point.toPoint())
        self.assertEqual(self.item.property("clicks"), 1)
        button.forceActiveFocus()
        QTest.keyClick(self.window, Qt.Key_Space)
        self.assertEqual(self.item.property("clicks"), 2)
        disabled = self.item.property("disabledButton")
        point = disabled.mapToItem(self.item, disabled.width() / 2, disabled.height() / 2)
        QTest.mouseClick(self.window, Qt.LeftButton, Qt.NoModifier, point.toPoint())
        self.assertEqual(self.item.property("clicks"), 2)

    def test_default_without_switch_or_saved_preference(self):
        facts = json.loads((self.root / "src/Settings/App.SettingsGroup.json").read_text())['QGC.MetaData.Facts']
        self.assertFalse(any(fact['name'] == 'highContrastMode' for fact in facts))
        settings = (self.root / "src/Settings/AppSettings.cc").read_text(encoding="utf-8")
        self.assertIn('QGCPalette::setHighContrast(true);', settings)
        self.assertNotIn('highContrastMode', settings)
        palette = (self.root / 'src/QmlControls/QGCPalette.cc').read_text()
        self.assertIn('bool QGCPalette::_highContrast = true;', palette)
        self.assertIn('if (_highContrastColors.isEmpty()) setHighContrast(_highContrast);', palette)
        self.assertFalse((self.root / 'src/Toolbar/HighContrastToggle.qml').exists())
        self.assertNotIn('HighContrastToggle', (self.root / 'src/Toolbar/FlyViewToolBar.qml').read_text())

    def test_render_desktop_field_and_narrow(self):
        self.build_scene()
        output = os.environ.get("STRATUM_CONTRAST_SCREENSHOTS")
        for width, height in [(1366, 768), (1024, 600), (480, 640)]:
            self.item.setWidth(width)
            self.item.setHeight(height)
            self.window.resize(width, height)
            self.window.show()
            for lighting, backdrop in [("bright", "#E8E8E8"), ("night", "#080808")]:
                self.item.setProperty("backdrop", QColor(backdrop))
                QTest.qWait(40)
                image = self.window.grabWindow()
                self.assertFalse(image.isNull())
                surface = self.item.property("surface")
                self.assertLess(surface.y() + surface.height(), height)
                button = self.item.property("takeoffButton")
                self.assertGreater(button.width(), 60)
                self.assertGreater(button.height(), 30)
                self.assertEqual(image.pixelColor(22, 22), QColor(self.colors["window"]))
                if output:
                    image.save(str(Path(output) / f"contrast-default-{width}-{lighting}.png"))


if __name__ == "__main__":
    unittest.main()