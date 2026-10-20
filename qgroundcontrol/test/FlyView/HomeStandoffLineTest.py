import re
import unittest
from pathlib import Path


# STRATUM KAN-13: Home -> Standoff distance line on the Fly View map. The overlay is pure
# QtLocation/QtPositioning map QML, which the isolated PySide6 harness cannot instantiate
# (no QtLocation module), so this pins the acceptance criteria at the source level.
class HomeStandoffLineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.source = (root / "src/FlyView/FlyViewMap.qml").read_text(encoding="utf-8")
        block = re.search(r"MapPolyline\s*\{\s*id:\s*homeStandoffLine.*?\n    \}", cls.source, re.S)
        cls.line_block = block.group(0) if block else ""

    def test_polyline_connects_home_and_standoff(self):
        self.assertTrue(self.line_block, "homeStandoffLine MapPolyline not found")
        self.assertIn("_homeStandoffHome", self.line_block)
        self.assertIn("standoffController._targetCoordinate", self.line_block)
        # Home source is Vehicle.homePosition; standoff from the standoff controller.
        self.assertIn("_activeVehicle.homePosition", self.source)

    def test_line_style_is_distinct_mint(self):
        # Distinct from the crimson standoff visuals / future vehicle->standoff line.
        self.assertIn('line.color: "#1DE9B6"', self.line_block)
        self.assertNotIn("#D11A35", self.line_block)

    def test_label_uses_great_circle_distance_in_app_units(self):
        self.assertIn("_homeStandoffHome.distanceTo(standoffController._targetCoordinate)", self.source)
        self.assertIn("metersToAppSettingsHorizontalDistanceUnits(_root._homeStandoffDistance)", self.source)
        self.assertIn("appSettingsHorizontalDistanceUnitsString", self.source)

    def test_hidden_until_home_and_standoff_valid(self):
        self.assertIn("visible:    _root._homeStandoffValid", self.line_block)
        valid = re.search(r"_homeStandoffValid:\s*(.+)", self.source).group(1)
        self.assertIn("standoffController._standoffActive", valid)
        self.assertIn("_homeStandoffHome.isValid", valid)
        self.assertIn("standoffController._targetCoordinate.isValid", valid)

    def test_label_anchored_at_line_midpoint(self):
        self.assertIn("_homeStandoffMidpoint", self.source)
        self.assertIn("atDistanceAndAzimuth(_homeStandoffDistance / 2", self.source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
