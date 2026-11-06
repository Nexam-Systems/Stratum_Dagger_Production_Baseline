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
 function scenario(average, severity, missing) {
  var rows = []
  for (var i = 0; i < 4; ++i) rows.push({
   name: "Motor " + (i + 1),
   temperatureC: missing && i === 3 ? Number.NaN : (severity === 3 && i === 0 ? 81 : 40 + i),
   severity: missing && i === 3 ? 0 : (severity === 3 && i === 0 ? 3 : 1)
  })
  _thermal = {averageC:average, freshCount:missing ? 3 : 4, severity:severity, sensors:rows}
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
        self.item.scenario(51.75, 3, False)
        self.app.processEvents()
        self.assertEqual(self.item.property("averageText"), "51.8 \u00b0C")
        self.assertEqual(self.item.property("averageColor").name(), "#ff0000")
        self.assertIn("81.00 \u00b0C", self.texts())

    def test_drawer_contains_only_four_motors_and_average(self):
        self.item.scenario(41, 1, True)
        self.app.processEvents()
        texts = self.texts()
        self.assertCountEqual(texts, [
            "Motor Temperatures", "Motor 1", "40.00 \u00b0C",
            "Motor 2", "41.00 \u00b0C", "Motor 3", "42.00 \u00b0C",
            "Motor 4", "N/A", "Average:", "41.0 \u00b0C",
        ])

    def test_no_vehicle_and_warning_colors(self):
        self.assertEqual(self.item.property("averageText"), "--")
        self.assertCountEqual(self.texts(), [
            "Motor Temperatures", "Motor 1", "N/A", "Motor 2", "N/A",
            "Motor 3", "N/A", "Motor 4", "N/A", "Average:", "--",
        ])
        self.item.scenario(75, 2, False)
        self.assertEqual(self.item.property("averageColor").name(), "#ff9900")
        self.item.scenario(40, 0, False)
        self.assertEqual(self.item.property("averageColor").name(), "#808080")


if __name__ == "__main__":
    unittest.main()
