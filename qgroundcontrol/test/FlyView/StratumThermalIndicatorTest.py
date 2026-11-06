"""Render the actual thermal drawer with service doubles; policy is tested in C++."""

import os
from pathlib import Path
import re
import shutil
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickItem


class StratumThermalIndicatorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.repo = Path(__file__).resolve().parents[2]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        module = self.root / "QGroundControl"
        controls = module / "Controls"
        controls.mkdir(parents=True)
        (module / "qmldir").write_text(
            "module QGroundControl\nQGCPalette 1.0 QGCPalette.qml\nsingleton QGroundControl 1.0 QGroundControl.qml\n",
            encoding="utf-8",
        )
        (module / "QGCPalette.qml").write_text("""import QtQuick
QtObject {
 property bool colorGroupEnabled: true
 property color text: "white"
 property color colorRed: "#ff0000"
 property color colorOrange: "#ff9900"
 property color colorGreen: "#00ff00"
 property color groupBorder: "#285468"
 property color windowShade: "#0b1d27"
 property color brandingPurple: "#48d6ff"
}
""", encoding="utf-8")
        (module / "QGroundControl.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
 property QtObject globalPalette: QGCPalette {}
 property QtObject multiVehicleManager: QtObject {
  property var activeVehicle: null
  property bool parameterReadyVehicleAvailable: false
 }
}
""", encoding="utf-8")
        names = ("ToolIndicatorPage", "SettingsGroupLayout", "QGCLabel")
        for name in names:
            shutil.copy2(self.repo / "src" / "QmlControls" / f"{name}.qml", controls / f"{name}.qml")
        (controls / "qmldir").write_text(
            "module QGroundControl.Controls\nsingleton ScreenTools 1.0 ScreenTools.qml\n"
            + "".join(f"{name} 1.0 {name}.qml\n" for name in names), encoding="utf-8"
        )
        (controls / "ScreenTools.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
 property real defaultFontPixelWidth: 8
 property real defaultFontPixelHeight: 18
 property real defaultFontPointSize: 10
 property real smallFontPointSize: 9
 property string normalFontFamily: "Arial"
}
""", encoding="utf-8")
        source = (self.repo / "src" / "Toolbar" / "StratumStatusBar.qml").read_text(encoding="utf-8")
        helpers = "\n".join(re.findall(r"    function _(?:avgTempText|thermalColor)\(.*?\n    }", source, re.S))
        drawer = source[source.index("    Component {\n        id: escTempDrawerComponent"):].rsplit("\n}", 1)[0]
        harness = """import QtQuick
import QtQuick.Layouts
import QGroundControl
import QGroundControl.Controls
Item {
 id: root
 width: 600
 height: 700
 property color _dimColor: "#808080"
 property var _thermal: null
 property string averageText: _avgTempText()
 property color averageColor: _thermalColor(_thermal ? _thermal.severity : 0)
 QGCPalette { id: qgcPal }
 function scenario(average, severity, blocked) {
  var rows = []
  for (var i = 0; i < 5; ++i) rows.push({
   name: i === 0 ? "FC IMU TEMP" : "Motor " + i + " ESC",
   temperatureC: i === 0 ? Number.NaN : 40 + i,
   state: i === 0 ? "NO DATA" : "NORMAL", severity: i === 0 ? 0 : 1,
   source: i === 0 ? "Unverified" : "ESC_INFO", required: i === 4, ageSeconds: i === 0 ? -1 : 0.2
  })
  _thermal = {averageC:average, freshCount:4, severity:severity, sensors:rows,
   sourceNotice:"IMU source is unverified", reason:blocked ? "Temperature too high" : "",
   groundBlocked:blocked, confirmedGround:blocked}
 }
""" + helpers + "\n" + drawer + "\n Loader { sourceComponent: escTempDrawerComponent }\n}"
        path = self.root / "Harness.qml"
        path.write_text(harness, encoding="utf-8")
        self.engine = QQmlEngine()
        self.engine.addImportPath(str(self.root))
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(path)))
        self.assertFalse(self.component.isError(), [error.toString() for error in self.component.errors()])
        self.item = self.component.create()
        self.assertIsInstance(self.item, QQuickItem)

    def tearDown(self):
        self.item.deleteLater()
        self.engine.deleteLater()
        self.app.processEvents()
        self.temp.cleanup()

    def texts(self, item=None):
        item = item or self.item
        result = []
        if item.isVisible() and item.metaObject().indexOfProperty("text") >= 0:
            result.append(item.property("text"))
        for child in item.childItems():
            result.extend(self.texts(child))
        return result

    def test_average_and_worst_sensor_color(self):
        self.item.scenario(48.2, 3, True)
        self.app.processEvents()
        self.assertEqual(self.item.property("averageText"), "48.2 \u00b0C")
        self.assertEqual(self.item.property("averageColor").name(), "#ff0000")
        self.assertTrue(any("blocked" in text for text in self.texts()))

    def test_drawer_has_four_escs_and_imu_with_no_data(self):
        self.item.scenario(42.5, 1, False)
        self.app.processEvents()
        texts = self.texts()
        self.assertIn("FC IMU TEMP", texts)
        for index in range(1, 5):
            self.assertIn(f"Motor {index} ESC", texts)
        self.assertIn("NO DATA", texts)
        self.assertTrue(any("warning-only" in text for text in texts))

    def test_no_vehicle_and_warning_colors(self):
        self.assertEqual(self.item.property("averageText"), "--")
        self.assertIn("No vehicle connected", self.texts())
        self.item.scenario(75, 2, False)
        self.assertEqual(self.item.property("averageColor").name(), "#ff9900")
        self.item.scenario(40, 0, False)
        self.assertEqual(self.item.property("averageColor").name(), "#808080")


if __name__ == "__main__":
    unittest.main()
