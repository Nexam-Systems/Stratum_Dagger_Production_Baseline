import re
import unittest
from pathlib import Path


# STRATUM KAN-13 (revised): Home -> Standoff distance shown as a field in the battery-aware
# PNR bar instead of a map line. The panel uses QGroundControl.unitsConversion + coordinate
# math that the isolated harness can't run, so this pins the acceptance criteria at source
# level and guards that the earlier map polyline was removed.
class HomeStandoffDistanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.panel = (root / "src/FlyView/RTLDecisionCountdownPanel.qml").read_text(encoding="utf-8")
        cls.widget = (root / "src/FlyView/FlyViewWidgetLayer.qml").read_text(encoding="utf-8")
        cls.map = (root / "src/FlyView/FlyViewMap.qml").read_text(encoding="utf-8")

    def test_distance_is_home_to_standoff_great_circle(self):
        self.assertIn("vehicle.homePosition", self.panel)
        self.assertIn("_soHome.distanceTo(standoffController._targetCoordinate)", self.panel)

    def test_hidden_value_until_home_and_standoff_valid(self):
        valid = re.search(r"_soValid:\s*(.+?)\n\s*readonly", self.panel, re.S).group(1)
        self.assertIn("_soHome", valid)
        self.assertIn("standoffController._standoffActive", valid)
        self.assertIn("standoffController._targetCoordinate", valid)

    def test_label_field_in_bar_uses_app_distance_units(self):
        self.assertIn('Field { key: qsTr("HOME->STDF"); value: root._dist(root._homeStandoffM) }', self.panel)
        self.assertIn("metersToAppSettingsHorizontalDistanceUnits(meters)", self.panel)
        self.assertIn("appSettingsHorizontalDistanceUnitsString", self.panel)

    def test_panel_is_wired_with_vehicle_and_standoff(self):
        block = re.search(r"RTLDecisionCountdownPanel\s*\{.*?\n    \}", self.widget, re.S).group(0)
        self.assertIn("vehicle:                  _root._activeVehicle", block)
        self.assertIn("standoffController:       _root.standoffController", block)

    def test_no_map_line_drawn(self):
        self.assertNotIn("homeStandoffLine", self.map)
        self.assertNotIn("homeStandoffLabel", self.map)


if __name__ == "__main__":
    unittest.main(verbosity=2)
