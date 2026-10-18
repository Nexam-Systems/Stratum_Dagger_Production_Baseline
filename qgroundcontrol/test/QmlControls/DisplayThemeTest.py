import json
import os
from pathlib import Path
import re
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QObject, Property, QSettings, Signal, QUrl
from PySide6.QtGui import QGuiApplication, QColor
from PySide6.QtQml import QQmlComponent, QQmlEngine, QJSValue


class SavedThemeFact(QObject):
    changed = Signal()

    def __init__(self, path, metadata):
        super().__init__()
        self.settings = QSettings(path, QSettings.IniFormat)
        self.metadata = metadata

    def get_value(self):
        return self.settings.value('indoorPalette', self.metadata['default'], int)

    def set_value(self, value):
        self.settings.setValue('indoorPalette', value)
        self.settings.sync()
        self.changed.emit()

    value = Property(int, get_value, set_value, notify=changed)
    enumIndex = Property(int, get_value, notify=changed)
    enumStrings = Property('QStringList', lambda self: self.metadata['enumStrings'].split(','), constant=True)
    enumValues = Property('QVariantList', lambda self: [int(value) for value in self.metadata['enumValues'].split(',')], constant=True)


class DisplayThemeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.root = Path(__file__).resolve().parents[2]
        facts = json.loads((cls.root / 'src/Settings/App.SettingsGroup.json').read_text())['QGC.MetaData.Facts']
        cls.metadata = next(fact for fact in facts if fact['name'] == 'indoorPalette')

    def test_general_dropdown_metadata_and_startup(self):
        self.assertEqual(self.metadata['enumStrings'], 'High Contrast,Normal')
        self.assertEqual(self.metadata['enumValues'], '0,1')
        self.assertEqual(self.metadata['default'], 0)
        source = (self.root / 'src/Settings/AppSettings.cc').read_text(encoding='utf-8')
        self.assertIn('_indoorPaletteChanged();', source)
        self.assertIn('QGCPalette::setHighContrast(indoorPalette()->rawValue().toUInt() != 1);', source)
        self.assertIn('QGCPalette::setGlobalTheme(QGCPalette::Dark);', source)
        settings = json.loads((self.root / 'src/AppSettings/pages/General.SettingsUI.json').read_text())
        self.assertTrue(any(control.get('setting') == 'appSettings.indoorPalette'
                            for group in settings['groups'] for control in group['controls']))

    def test_actual_fact_dropdown_saves_and_reloads(self):
        with tempfile.TemporaryDirectory() as folder:
            path = str(Path(folder) / 'settings.ini')
            fact = SavedThemeFact(path, self.metadata)
            engine = QQmlEngine()
            engine.rootContext().setContextProperty('savedTheme', fact)
            source = (self.root / 'src/FactSystem/FactControls/FactComboBox.qml').read_text()
            body = source.split('QGCComboBox {', 1)[1].replace('property Fact fact: Fact { }', 'property var fact: savedTheme')
            component = QQmlComponent(engine)
            component.setData(('import QtQuick\nimport QtQuick.Controls\nComboBox {' + body).encode(), QUrl('file:///ThemeDropdownHarness.qml'))
            self.assertFalse(component.isError(), [error.toString() for error in component.errors()])
            dropdown = component.create()
            self.assertIsNotNone(dropdown)
            self.app.processEvents()
            self.assertEqual(dropdown.property('currentText'), 'High Contrast')
            method = engine.newQObject(dropdown).property('activated')
            result = method.call([QJSValue(1)])
            self.assertFalse(result.isError(), result.toString())
            self.app.processEvents()
            self.assertEqual(dropdown.property('currentText'), 'Normal')
            self.assertEqual(SavedThemeFact(path, self.metadata).value, 1)
            method.call([QJSValue(0)])
            self.app.processEvents()
            self.assertEqual(dropdown.property('currentText'), 'High Contrast')
            self.assertEqual(SavedThemeFact(path, self.metadata).value, 0)
            dropdown.deleteLater()
            engine.deleteLater()
            self.app.processEvents()

    def test_normal_palette_readability(self):
        source = (self.root / 'src/QmlControls/QGCPalette.cc').read_text(encoding='utf-8')
        colors = dict(re.findall(r'DECLARE_QGC_COLOR\(\s*(\w+),\s*"[^"]+",\s*"[^"]+",\s*"[^"]+",\s*"([^"]+)"', source))

        def luminance(color):
            color = QColor(color)
            channels = [color.redF(), color.greenF(), color.blueF()]
            linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
            return sum(value * weight for value, weight in zip(linear, [0.2126, 0.7152, 0.0722]))

        for foreground, background in [('text', 'window'), ('buttonText', 'button'),
                                       ('primaryButtonText', 'primaryButton'), ('textFieldText', 'textField'),
                                       ('warningText', 'window')]:
            first, second = sorted([luminance(colors[foreground]), luminance(colors[background])])
            self.assertGreaterEqual((second + 0.05) / (first + 0.05), 4.5, foreground)
        for background in ['#7C202C', '#441B26', '#073E37', '#102D43']:
            first, second = sorted([luminance('#F1F7FA'), luminance(background)])
            self.assertGreaterEqual((second + 0.05) / (first + 0.05), 4.5)


if __name__ == '__main__':
    unittest.main()