import re
import unittest
from pathlib import Path


# STRATUM KAN-16: Home -> Vehicle distance shown as a field in the battery-aware PNR bar
# (no map line), alongside Home -> Standoff and Vehicle -> Standoff. The panel uses the
# QGroundControl units conversion + coordinate math the isolated harness can't run, so
# this pins the acceptance criteria at source level.
class HomeVehicleDistanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.panel = (root / "src/FlyView/RTLDecisionCountdownPanel.qml").read_text(encoding="utf-8")
        cls.widget = (root / "src/FlyView/FlyViewWidgetLayer.qml").read_text(encoding="utf-8")
        cls.map = (root / "src/FlyView/FlyViewMap.qml").read_text(encoding="utf-8")

    def test_distance_is_home_to_vehicle_great_circle(self):
        self.assertIn("vehicle.coordinate", self.panel)
        self.assertIn("_soHome.distanceTo(vehicle.coordinate)", self.panel)

    def test_hidden_value_until_home_and_vehicle_valid(self):
        veh = re.search(r"_vehCoord:\s*(.+)", self.panel).group(1)
        self.assertIn("vehicle.coordinate.isValid", veh)
        home_veh = re.search(r"_homeVehM:\s*(.+)", self.panel).group(1)
        self.assertIn("_soHome", home_veh)
        self.assertIn("_vehCoord", home_veh)

    def test_field_uses_app_distance_units(self):
        self.assertIn('qsTr("HOME->VEH")', self.panel)
        self.assertIn("root._dist(root._homeVehM)", self.panel)
        self.assertIn("metersToAppSettingsHorizontalDistanceUnits(meters)", self.panel)
        self.assertIn("appSettingsHorizontalDistanceUnitsString", self.panel)

    def test_all_three_distance_fields_present_in_order(self):
        # Home -> Standoff, Vehicle -> Standoff, then Home -> Vehicle in the same section.
        self.assertRegex(
            self.panel,
            r'qsTr\("HOME->STDF"\).*?\n\s*Field \{\s*key:\s*qsTr\("VEH->STDF"\).*?\n\s*Field \{\s*key:\s*qsTr\("HOME->VEH"\)')

    def test_panel_is_wired_with_vehicle(self):
        block = re.search(r"RTLDecisionCountdownPanel\s*\{.*?\n    \}", self.widget, re.S).group(0)
        self.assertIn("vehicle:                  _root._activeVehicle", block)

    def test_no_map_line_drawn(self):
        self.assertNotIn("homeVehLine", self.map)
        self.assertNotIn("homeStandoffLine", self.map)


if __name__ == "__main__":
    unittest.main(verbosity=2)
