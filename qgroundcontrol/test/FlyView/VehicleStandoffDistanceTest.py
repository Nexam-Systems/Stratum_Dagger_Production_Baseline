import re
import unittest
from pathlib import Path


# STRATUM KAN-14: Vehicle -> Standoff distance shown as a field in the battery-aware PNR
# bar, alongside the Home -> Standoff field (KAN-13). The panel uses QGroundControl units
# conversion + coordinate math the isolated harness can't run, so this pins the acceptance
# criteria at source level.
class VehicleStandoffDistanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.panel = (root / "src/FlyView/RTLDecisionCountdownPanel.qml").read_text(encoding="utf-8")
        cls.widget = (root / "src/FlyView/FlyViewWidgetLayer.qml").read_text(encoding="utf-8")
        cls.map = (root / "src/FlyView/FlyViewMap.qml").read_text(encoding="utf-8")

    def test_distance_is_vehicle_to_standoff_great_circle(self):
        self.assertIn("vehicle.coordinate", self.panel)
        self.assertIn("_vehCoord.distanceTo(standoffController._targetCoordinate)", self.panel)

    def test_hidden_value_until_vehicle_and_standoff_valid(self):
        veh = re.search(r"_vehCoord:\s*(.+)", self.panel).group(1)
        self.assertIn("vehicle.coordinate.isValid", veh)
        valid = re.search(r"_vehSoValid:\s*(.+?)\n\s*readonly", self.panel, re.S).group(1)
        self.assertIn("_vehCoord", valid)
        self.assertIn("standoffController._standoffActive", valid)
        self.assertIn("standoffController._targetCoordinate", valid)

    def test_vehicle_field_uses_app_distance_units(self):
        self.assertIn('qsTr("VEH->STDF")', self.panel)
        self.assertIn("root._dist(root._vehStandoffM)", self.panel)
        self.assertIn("metersToAppSettingsHorizontalDistanceUnits(meters)", self.panel)
        self.assertIn("appSettingsHorizontalDistanceUnitsString", self.panel)

    def test_sits_next_to_home_standoff_field(self):
        # Vehicle field immediately follows the home field in the standoff-distance section.
        self.assertRegex(
            self.panel,
            r'qsTr\("HOME->STDF"\);\s*value:\s*root\._dist\(root\._homeStandoffM\)\s*\}\s*\n\s*Field \{\s*key:\s*qsTr\("VEH->STDF"\)')

    def test_panel_is_wired_with_vehicle_and_standoff(self):
        block = re.search(r"RTLDecisionCountdownPanel\s*\{.*?\n    \}", self.widget, re.S).group(0)
        self.assertIn("vehicle:                  _root._activeVehicle", block)
        self.assertIn("standoffController:       _root.standoffController", block)

    def test_no_map_line_drawn(self):
        self.assertNotIn("vehStandoffLine", self.map)
        self.assertNotIn("homeStandoffLine", self.map)


if __name__ == "__main__":
    unittest.main(verbosity=2)
