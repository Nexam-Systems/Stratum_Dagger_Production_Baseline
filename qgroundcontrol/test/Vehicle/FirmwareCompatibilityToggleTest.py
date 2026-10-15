import json
import os
from pathlib import Path
import re
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QObject, Property, QSettings, Signal, QUrl, QPoint, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest


class SavedFact(QObject):
    changed = Signal()

    def __init__(self, path, default):
        super().__init__()
        self.settings = QSettings(path, QSettings.IniFormat)
        self.default = default

    def get_value(self):
        return self.settings.value("Admin/firmwareCompatibilityChecksEnabled", self.default, bool)

    def set_value(self, value):
        self.settings.setValue("Admin/firmwareCompatibilityChecksEnabled", bool(value))
        self.settings.sync()
        self.changed.emit()

    value = Property(bool, get_value, set_value, notify=changed)
    typeIsBool = Property(bool, lambda self: True, constant=True)


class FirmwareCompatibilityToggleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.root = Path(__file__).resolve().parents[2]

    def test_checkbox_saves_and_reloads(self):
        facts = json.loads((self.root / "src/Settings/Admin.SettingsGroup.json").read_text())["QGC.MetaData.Facts"]
        metadata = next(fact for fact in facts if fact["name"] == "firmwareCompatibilityChecksEnabled")
        self.assertEqual(metadata["type"], "bool")
        self.assertTrue(metadata["default"])
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "settings.ini")
            fact = SavedFact(path, metadata["default"])
            engine = QQmlEngine()
            engine.rootContext().setContextProperty("savedFact", fact)
            source = (self.root / "src/FactSystem/FactControls/FactCheckBox.qml").read_text()
            body = source.split("QGCCheckBox {", 1)[1].replace("property Fact fact: Fact { }", "property var fact: savedFact")
            component = QQmlComponent(engine)
            component.setData(("import QtQuick\nimport QtQuick.Controls\nCheckBox { width: 320; height: 44; text: 'Enable firmware compatibility checks';" + body).encode(), QUrl("file:///CompatibilityCheckboxTest.qml"))
            self.assertFalse(component.isError(), [error.toString() for error in component.errors()])
            checkbox = component.create()
            self.assertIsNotNone(checkbox)
            window = QQuickWindow()
            window.resize(340, 70)
            checkbox.setParentItem(window.contentItem())
            window.show()
            QTest.qWait(40)
            self.assertTrue(checkbox.property("checked"))
            QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier, QPoint(12, 22))
            self.assertFalse(fact.value)
            self.assertFalse(SavedFact(path, metadata["default"]).value)
            QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier, QPoint(12, 22))
            self.assertTrue(fact.value)
            self.assertTrue(SavedFact(path, metadata["default"]).value)
            window.close()
            checkbox.setParentItem(None)
            checkbox.deleteLater()
            engine.deleteLater()
            self.app.processEvents()

    def test_native_guards_and_missing_version_path(self):
        source = (self.root / "src/Vehicle/Vehicle.cc").read_text()
        for name in ["checkPx4VersionAgainstAdminFloor", "checkStratumCustomVersionAgainstAdminFloor"]:
            body = source.split("bool Vehicle::" + name, 1)[1].split("\n}", 1)[0]
            self.assertRegex(body, r"if \(!admin \|\| !admin->firmwareCompatibilityChecksEnabled\(\)->rawValue\(\).toBool\(\)\)\s*\{\s*return true;")
            self.assertLess(body.index("firmwareCompatibilityChecksEnabled"), body.index("strictCompatibilityGate"))
        source = (self.root / "src/Vehicle/InitialConnectStateMachine.cc").read_text()
        failure = source.split("void InitialConnectStateMachine::_handleAutopilotVersionFailure()", 1)[1].split("void InitialConnectStateMachine::_requestStandardModes", 1)[0]
        self.assertRegex(failure, r"if \(!vehicle\(\)->checkStratumCustomVersionAgainstAdminFloor")
        self.assertIn("vehicle()->acceptFirmwareConnection();", failure)
        self.assertIn("vehicle()->_setCapabilities(assumedCapabilities);", failure)

    def test_admin_binding_and_warning_are_separate(self):
        qml = (self.root / "src/Toolbar/AdminSettingsDialog.qml").read_text()
        self.assertIn("_admin.firmwareCompatibilityChecksEnabled", qml)
        self.assertIn("_admin.strictCompatibilityGate", qml)
        header = (self.root / "src/Settings/AdminSettings.h").read_text()
        source = (self.root / "src/Settings/AdminSettings.cc").read_text()
        self.assertIn("DEFINE_SETTINGFACT(firmwareCompatibilityChecksEnabled)", header)
        self.assertIn("DECLARE_SETTINGSFACT(AdminSettings, firmwareCompatibilityChecksEnabled)", source)


if __name__ == "__main__":
    unittest.main()