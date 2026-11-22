import os
import re
import tempfile
import unittest
from pathlib import Path

import PySide6

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlComponent
from PySide6.QtTest import QTest


# KAN-52: the first map click in Set Standoff filled Lat/Lon but drew no target, ring or slot until the
# second click. _updatePending() ran from the Lat/Lon onTextChanged handlers and read a validity binding
# that had not been refreshed yet, so each pick drew one step late. This mounts the panel's real
# _coordValid / _updatePending source against two text fields wired the same way as the panel.
class StandoffFirstClickTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        root = Path(__file__).resolve().parents[2]
        source = (root / "src/FlyView/FlyViewWidgetLayer.qml").read_text(encoding="utf-8")
        panel = source.split("id:                 standoffPanel", 1)[1]
        cls.coord_valid = re.search(r"[ \t]*function _targetFromFields\(\) \{.*?\n        \}\n[ \t]*property bool _coordValid:[^\n]*\n", panel, re.S).group(0)
        cls.update_pending = re.search(r"[ \t]*function _updatePending\(\) \{.*?\n        \}\n", panel, re.S).group(0)

    def mount(self, inside_aop=True):
        self.temp = tempfile.TemporaryDirectory()
        host = f'''import QtQuick
import QtQuick.Controls
import QtPositioning

Item {{
    id: standoffPanel
    property var mapControl: map
    property bool _aopReject: false
    property bool insideAop: {str(inside_aop).lower()}
    property bool pendingValid: map.pending.isValid
    property real pendingLat: map.pending.isValid ? map.pending.latitude : NaN
    property real pendingLon: map.pending.isValid ? map.pending.longitude : NaN

    QtObject {{
        id: map
        property var pending: QtPositioning.coordinate()
        property int writes: 0
        function isCoordinateInsideAOP(coordinate) {{ return standoffPanel.insideAop }}
        function setStandoffPendingCoordinate(coordinate) {{ pending = coordinate; writes++ }}
    }}

    TextField {{ id: standoffLatField; onTextChanged: standoffPanel._updatePending() }}
    TextField {{ id: standoffLonField; onTextChanged: standoffPanel._updatePending() }}

{self.coord_valid}
{self.update_pending}
    // Same as the panel's map-pick handler: Lat first, then Lon.
    function pick(lat, lon) {{
        standoffLatField.text = lat.toFixed(7)
        standoffLonField.text = lon.toFixed(7)
    }}
}}
'''
        path = Path(self.temp.name) / "Host.qml"
        path.write_text(host, encoding="utf-8")
        self.engine = QQmlEngine()
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(path)))
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

    def pick(self, lat, lon):
        from PySide6.QtCore import QMetaObject, Q_ARG, Qt
        QMetaObject.invokeMethod(self.item, "pick", Qt.DirectConnection, Q_ARG("QVariant", lat), Q_ARG("QVariant", lon))
        QTest.qWait(5)

    def test_first_click_sets_the_pending_target(self):
        self.mount()
        self.pick(47.1234567, 8.7654321)
        self.assertTrue(self.item.property("pendingValid"))
        self.assertAlmostEqual(self.item.property("pendingLat"), 47.1234567, places=6)
        self.assertAlmostEqual(self.item.property("pendingLon"), 8.7654321, places=6)

    def test_later_clicks_move_the_target_to_the_new_point(self):
        self.mount()
        self.pick(47.0, 8.0)
        self.pick(47.5, 8.5)
        self.pick(46.0, 7.0)
        self.assertAlmostEqual(self.item.property("pendingLat"), 46.0, places=6)
        self.assertAlmostEqual(self.item.property("pendingLon"), 7.0, places=6)

    def test_a_pick_outside_the_aop_is_still_rejected(self):
        self.mount(inside_aop=False)
        self.pick(47.0, 8.0)
        self.assertFalse(self.item.property("pendingValid"))
        self.assertTrue(self.item.property("_aopReject"))


if __name__ == "__main__":
    unittest.main()
