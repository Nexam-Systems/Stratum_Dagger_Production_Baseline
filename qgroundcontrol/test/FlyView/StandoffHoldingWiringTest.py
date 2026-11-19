import json
import unittest
from pathlib import Path


# STRATUM #98 / KAN-47: wiring of the holding slot state, the configurable tolerances and the vehicle
# mode badge. The controller's behaviour is covered by StandoffHoldingTest.py; the map, the vehicle
# icon and the settings use C++ / map types, so this pins their wiring at source level.
class StandoffHoldingWiringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.map = (root / "src/FlyView/FlyViewMap.qml").read_text(encoding="utf-8")
        cls.vehicle = (root / "src/FlightMap/MapItems/VehicleMapItem.qml").read_text(encoding="utf-8")
        cls.admin = (root / "src/Toolbar/AdminSettingsDialog.qml").read_text(encoding="utf-8")
        cls.cmake = (root / "src/FlightMap/CMakeLists.txt").read_text(encoding="utf-8")
        cls.header = (root / "src/Settings/FlyViewSettings.h").read_text(encoding="utf-8")
        cls.source = (root / "src/Settings/FlyViewSettings.cc").read_text(encoding="utf-8")
        cls.images = root / "src/FlightMap/Images"
        cls.settings = {f["name"]: f for f in json.loads((root / "src/Settings/FlyView.SettingsGroup.json").read_text(encoding="utf-8"))["QGC.MetaData.Facts"]}
        cls.active = cls.map.split("// ---- ACTIVE", 1)[1].split("XC25 fetched-target", 1)[0]

    def test_tolerances_are_settings_with_the_agreed_defaults_and_admin_fields(self):
        defaults = {"standoffHoldHorizontalTolerance": 10, "standoffHoldVerticalTolerance": 5, "standoffHoldDwellTime": 3}
        for name, default in defaults.items():
            self.assertEqual(self.settings[name]["default"], default, name)
            self.assertIn(f"DEFINE_SETTINGFACT({name})", self.header)
            self.assertIn(f"DECLARE_SETTINGSFACT(FlyViewSettings, {name})", self.source)
            self.assertIn(f"_flyView.{name}", self.admin)

    def test_holding_icon_is_a_filled_blue_slot_registered_as_a_resource(self):
        svg = (self.images / "StandoffSlotHolding.svg").read_text(encoding="utf-8")
        self.assertIn('fill="#378ADD"', svg)
        self.assertIn("Images/StandoffSlotHolding.svg", self.cmake)

    def test_active_slot_icon_follows_the_holding_state(self):
        self.assertIn('standoffController.holding ? "/qmlimages/StandoffSlotHolding.svg" : "/qmlimages/StandoffSlotEnroute.svg"', self.active)
        self.assertIn("slotCoordinate:     standoffActiveGeometry.slotCoordinate", self.map)

    def test_path_line_is_only_drawn_while_en_route_in_standoff_or_hold(self):
        line = self.map.split("_standoffPathVisible:", 1)[1].split("\n", 1)[0]
        self.assertIn("!standoffController.holding", line)
        self.assertIn("standoffController.inStandoffOrHold", line)

    def test_vehicle_icon_carries_the_mode_badge_during_an_active_standoff(self):
        self.assertIn("modeBadgeText:  (standoffController._standoffActive && object === _activeVehicle) ? object.flightMode : \"\"", self.map)
        self.assertIn('property string modeBadgeText:  ""', self.vehicle)
        self.assertIn("id:                         modeBadge", self.vehicle)


if __name__ == "__main__":
    unittest.main()
