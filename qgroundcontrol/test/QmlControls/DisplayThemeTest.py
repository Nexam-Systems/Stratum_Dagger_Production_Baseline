import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QObject, Property, QSettings, Signal, QUrl
from PySide6.QtGui import QGuiApplication, QColor, QImage, QPainter
from PySide6.QtQml import QQmlComponent, QQmlEngine, QJSValue
from PySide6.QtQuick import QQuickImageProvider, QQuickItem


def palette_definitions(source):
    roles = {}
    for name, *values in re.findall(
            r'DECLARE_QGC_COLOR\(\s*(\w+),\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)"', source):
        roles[name] = values
    for name, disabled, enabled in re.findall(
            r'DECLARE_QGC_NONTHEMED_COLOR\(\s*(\w+),\s*"([^"]+)",\s*"([^"]+)"', source):
        roles[name] = [disabled, enabled, disabled, enabled]
    for name, color in re.findall(r'DECLARE_QGC_SINGLE_COLOR\(\s*(\w+),\s*"([^"]+)"', source):
        roles[name] = [color] * 4
    high_contrast = dict(re.findall(r'\{"(\w+)", "(#[0-9A-Fa-f]+)"\}', source))
    return roles, high_contrast


def create_theme_modules(folder, repo):
    """Keep palette ownership in QGC, re-exported by QGroundControl, as in production."""
    backend = folder / 'QGC'
    controls = folder / 'QGroundControl' / 'Controls'
    backend.mkdir(parents=True)
    controls.mkdir(parents=True)
    roles, high_contrast = palette_definitions((repo / 'src/QmlControls/QGCPalette.cc').read_text(encoding='utf-8'))
    (backend / 'qmldir').write_text(
        'module QGC\nsingleton ThemeState 1.0 ThemeState.qml\nQGCPalette 1.0 QGCPalette.qml\n', encoding='utf-8')
    (backend / 'ThemeState.qml').write_text(
        'pragma Singleton\nimport QtQuick\nQtObject { property int value: 1 }\n', encoding='utf-8')
    (backend / 'QGCPalette.qml').write_text("""import QtQuick
QtObject {
 id: palette
 enum Theme { Light, Dark }
 property bool colorGroupEnabled: true
 readonly property bool highContrast: ThemeState.value === 0
 readonly property bool lightTheme: ThemeState.value === 2
 readonly property int globalTheme: lightTheme ? 0 : 1
 signal paletteChanged()
 onColorGroupEnabledChanged: paletteChanged()
 property Connections observer: Connections {
  target: ThemeState
  function onValueChanged() { palette.paletteChanged() }
 }
 property var roles: """ + json.dumps(roles) + """
 property var highColors: """ + json.dumps(high_contrast) + """
 function colorFor(name) {
  if (highContrast) {
   if (!colorGroupEnabled) {
    if (["button", "primaryButton", "buttonHighlight"].indexOf(name) >= 0) return "#202420"
    if (["text", "buttonText", "primaryButtonText", "buttonHighlightText"].indexOf(name) >= 0) return "#B5BDB0"
    if (name === "buttonBorder") return "#7D8876"
   }
   return highColors[name] || roles[name][3]
  }
  return roles[name][(lightTheme ? 0 : 2) + (colorGroupEnabled ? 1 : 0)]
 }
""" + ''.join(f' property color {name}: colorFor("{name}")\n' for name in roles) + '}\n', encoding='utf-8')
    module = controls.parent
    (module / 'qmldir').write_text(
        'module QGroundControl\nimport QGC 1.0\nsingleton QGroundControl 1.0 QGroundControl.qml\n', encoding='utf-8')
    (module / 'QGroundControl.qml').write_text("""pragma Singleton
import QtQuick
import QGC
QtObject {
 property QtObject globalPalette: QGCPalette {}
 property QtObject corePlugin: QtObject { property bool showTouchAreas: false }
}
""", encoding='utf-8')
    names = []
    for path in (repo / 'src/QmlControls').glob('*.qml'):
        shutil.copy2(path, controls / path.name)
        names.append(path.stem)
    (controls / 'qmldir').write_text(
        'module QGroundControl.Controls\n' + ''.join(
            f'{"singleton " if name == "ScreenTools" else ""}{name} 1.0 {name}.qml\n' for name in names),
        encoding='utf-8')
    (controls / 'ScreenTools.qml').write_text("""pragma Singleton
import QtQuick
QtObject {
 property real defaultFontPixelWidth: 8
 property real defaultFontPixelHeight: 18
 property real defaultFontPointSize: 10
 property real smallFontPointSize: 9
 property real mediumFontPointSize: 12
 property real largeFontPointSize: 16
 property real largeFontPixelHeight: 27
 property string normalFontFamily: "Arial"
 property real realPixelDensity: 4
 property real defaultBorderRadius: 4
 property real implicitButtonWidth: 40
 property real implicitButtonHeight: 32
 property real implicitTextFieldWidth: 80
 property real implicitTextFieldHeight: 32
 property real implicitCheckBoxHeight: 18
 property real implicitSliderHeight: 18
 property real comboBoxPadding: 8
 property real toolbarHeight: 64
 property bool isMobile: false
 property bool isiOS: false
 property bool isDebug: false
}
""", encoding='utf-8')
    return roles


class ThemeIconProvider(QQuickImageProvider):
    def __init__(self, repo):
        super().__init__(QQuickImageProvider.Image)
        self.repo = repo
        self.files = {}

    def requestImage(self, identifier, size, requested):
        path, _, color = identifier.partition('?color=')
        path = path.lstrip('/')
        if path.startswith('InstrumentValueIcons/'):
            file = self.repo / 'resources' / path
        elif path.startswith('res/'):
            file = self.repo / 'resources' / path.removeprefix('res/')
        else:
            file = self.repo / 'src/QmlControls' / path.removeprefix('qmlimages/')
        if not file.exists():
            if path not in self.files:
                name = Path(path).name
                if name == 'City3DMapIcon.svg':
                    name = 'city_3d_map_icon.svg'
                matches = list(self.repo.rglob(name))
                if len(matches) != 1:
                    raise RuntimeError(f'Ambiguous or missing theme icon: {path}')
                self.files[path] = matches[0]
            file = self.files[path]
        image = QImage(str(file))
        if image.isNull():
            raise RuntimeError(f'Cannot load theme test icon: {file}')
        if requested.width() > 0 and requested.height() > 0:
            image = image.scaled(requested)
        painter = QPainter(image)
        painter.setCompositionMode(QPainter.CompositionMode_SourceIn)
        painter.fillRect(image.rect(), QColor('#' + color))
        painter.end()
        size.setWidth(image.width())
        size.setHeight(image.height())
        return image


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
    enumIndex = Property(int, lambda self: self.enumValues.index(self.get_value()), notify=changed)
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
        self.assertEqual(self.metadata['enumStrings'], 'Normal,High Contrast,Light')
        self.assertEqual(self.metadata['enumValues'], '1,0,2')
        self.assertEqual(self.metadata['default'], 0)
        source = (self.root / 'src/Settings/AppSettings.cc').read_text(encoding='utf-8')
        self.assertIn('_indoorPaletteChanged();', source)
        self.assertIn('QGCPalette::setHighContrast(theme != 1 && theme != 2);', source)
        self.assertIn('QGCPalette::setGlobalTheme(theme == 2 ? QGCPalette::Light : QGCPalette::Dark);', source)
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
            result = method.call([QJSValue(0)])
            self.assertFalse(result.isError(), result.toString())
            self.app.processEvents()
            self.assertEqual(dropdown.property('currentText'), 'Normal')
            self.assertEqual(SavedThemeFact(path, self.metadata).value, 1)
            method.call([QJSValue(1)])
            self.app.processEvents()
            self.assertEqual(dropdown.property('currentText'), 'High Contrast')
            self.assertEqual(SavedThemeFact(path, self.metadata).value, 0)
            method.call([QJSValue(2)])
            self.app.processEvents()
            self.assertEqual(dropdown.property('currentText'), 'Light')
            self.assertEqual(SavedThemeFact(path, self.metadata).value, 2)
            dropdown.deleteLater()
            engine.deleteLater()
            self.app.processEvents()

    def test_existing_saved_values_keep_their_names(self):
        names = self.metadata['enumStrings'].split(',')
        with tempfile.TemporaryDirectory() as folder:
            path = str(Path(folder) / 'settings.ini')
            for value, name in [(0, 'High Contrast'), (1, 'Normal'), (2, 'Light')]:
                settings = QSettings(path, QSettings.IniFormat)
                settings.setValue('indoorPalette', value)
                settings.sync()
                loaded = SavedThemeFact(path, self.metadata)
                self.assertEqual(loaded.value, value)
                self.assertEqual(names[loaded.enumIndex], name)

    def test_shared_controls_switch_live_and_keep_disabled_text_readable(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            roles = create_theme_modules(root, self.root)
            engine = QQmlEngine()
            engine.addImportPath(str(root))
            engine.addImageProvider('coloredsvg', ThemeIconProvider(self.root))
            component = QQmlComponent(engine)
            component.setData(b"""import QtQuick
import QtQuick.Layouts
import QGC
import QGroundControl
import QGroundControl.Controls
Item {
 width: 600
 height: 600
 property QtObject qgcPal: QGroundControl.globalPalette
 function selectTheme(value) { ThemeState.value = value }
 ColumnLayout {
  width: parent.width
  SettingsActionButton { objectName: "primary"; text: "Save"; primary: true }
  SettingsActionButton { objectName: "secondary"; text: "Reset" }
  ToolTabButton { objectName: "tab"; text: "General"; checked: true }
  SettingsSection {
   objectName: "section"
   heading: "Settings"
   Layout.fillWidth: true
   QGCTextField { Layout.fillWidth: true; text: "Example" }
  }
 }
}
""", QUrl.fromLocalFile(str(root / 'Harness.qml')))
            self.assertFalse(component.isError(), [error.toString() for error in component.errors()])
            item = component.create()
            self.assertIsInstance(item, QQuickItem)
            primary = item.findChild(QQuickItem, 'primary')
            secondary = item.findChild(QQuickItem, 'secondary')
            section = item.findChild(QQuickItem, 'section')
            self.assertIsNotNone(primary)
            for value, panel, accent in [(1, '#09161b', '#2cd4fd'), (0, '#050A06', '#C5F779'), (2, '#ffffff', '#005B70')]:
                item.selectTheme(value)
                self.app.processEvents()
                self.assertEqual(section.property('color'), QColor(panel))
                self.assertEqual(primary.property('background').property('color'), QColor(accent))
            primary.setProperty('enabled', False)
            self.app.processEvents()
            self.assertEqual(primary.property('textColor'), QColor(roles['buttonText'][0]))
            self.assertEqual(primary.property('background').property('color'), QColor(roles['button'][0]))
            self.assertEqual(primary.property('background').property('opacity'), 1.0)
            idle = secondary.property('background').property('color')
            secondary.setProperty('down', True)
            self.app.processEvents()
            self.assertNotEqual(secondary.property('background').property('color'), idle)
            item.selectTheme(1)
            self.app.processEvents()
            self.assertEqual(section.property('color'), QColor('#09161b'))
            item.deleteLater()
            engine.deleteLater()
            self.app.processEvents()

    def test_light_palette_contrast(self):
        source = (self.root / 'src/QmlControls/QGCPalette.cc').read_text(encoding='utf-8')
        roles = {
            match[0]: (match[1], match[2])
            for match in re.findall(
                r'DECLARE_QGC_COLOR\(\s*(\w+),\s*"([^"]+)",\s*"([^"]+)",\s*"[^"]+",\s*"[^"]+"', source)
        }

        def luminance(value):
            color = QColor(value)
            linear = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
                      for channel in (color.redF(), color.greenF(), color.blueF())]
            return sum(value * weight for value, weight in zip(linear, (0.2126, 0.7152, 0.0722)))

        def contrast(first, second):
            low, high = sorted((luminance(first), luminance(second)))
            return (high + 0.05) / (low + 0.05)

        self.assertEqual(QColor(roles['window'][1]), QColor('white'))
        text_pairs = [
            ('text', 'window'), ('text', 'windowShade'), ('text', 'windowShadeDark'),
            ('buttonText', 'button'), ('primaryButtonText', 'primaryButton'),
            ('buttonHighlightText', 'buttonHighlight'), ('textFieldText', 'textField'),
            ('alertText', 'alertBackground'),
        ]
        for enabled in (0, 1):
            for foreground, background in text_pairs:
                with self.subTest(foreground=foreground, background=background, enabled=enabled):
                    self.assertGreaterEqual(contrast(roles[foreground][enabled], roles[background][enabled]), 4.5)
        for foreground in ('brandingPurple', 'warningText', 'colorGreen', 'colorOrange',
                           'colorRed', 'colorGrey', 'colorBlue', 'colorYellow', 'colorYellowGreen'):
            for background in ('window', 'windowShade', 'windowShadeDark'):
                with self.subTest(foreground=foreground, background=background):
                    self.assertGreaterEqual(contrast(roles[foreground][1], roles[background][1]), 4.5)
        for border, background in [('groupBorder', 'window'), ('buttonBorder', 'button'), ('buttonBorder', 'textField')]:
            self.assertGreaterEqual(contrast(roles[border][1], roles[background][1]), 3)

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