import re
import unittest
from pathlib import Path


# STRATUM #98 / KAN-43: the Set Standoff panel is fed through StandoffGeometry, shows the derived
# standoff point live, validates the inputs, and only WARNS (never blocks) on link range. The panel
# sits inside FlyViewWidgetLayer and uses C++ types, so these pin the behaviour at source level.
class StandoffPanelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.widget = (root / "src/FlyView/FlyViewWidgetLayer.qml").read_text(encoding="utf-8")
        cls.panel = cls.widget.split("id:                 standoffPanel", 1)[1].split("MapScale {", 1)[0]

    def test_geometry_model_is_fed_from_the_panel_fields_and_gcs_position(self):
        model = re.search(r"StandoffGeometry\s*\{(.*?)\n        \}", self.panel, re.S).group(1)
        for prop, field in [("targetLatitude", "standoffLatField"), ("targetLongitude", "standoffLonField"),
                            ("targetAltitude", "standoffAltitudeField"), ("distance", "standoffDistanceField"),
                            ("height", "standoffHeightField"), ("direction", "standoffDirectionField")]:
            self.assertRegex(model, rf"{prop}:\s+parseFloat\({field}\.text\)")
        self.assertIn("gcsCoordinate:   QGroundControl.qgcPositionManger.gcsPosition", model)

    def test_altitude_field_and_labels(self):
        self.assertIn("id:                    standoffAltitudeField", self.panel)
        self.assertIn('qsTr("Height above target")', self.panel)
        self.assertNotIn("Height AGL", self.panel)

    def test_defaults_are_100m_distance_and_height(self):
        distance = self.panel.split("id:                    standoffDistanceField", 1)[1].split("}", 1)[0]
        height = self.panel.split("id:                    standoffHeightField", 1)[1].split("}", 1)[0]
        self.assertIn('text:                  "100"', distance)
        self.assertIn('text:                  "100"', height)

    def test_all_input_errors_are_shown(self):
        for name in ("altitudeError", "distanceError", "heightError", "directionError"):
            self.assertIn(f"visible:             standoffGeometry.{name} !== \"\"", self.panel)
            self.assertIn(f"text:                standoffGeometry.{name}", self.panel)

    def test_derived_values_are_shown_live(self):
        for needle in ("standoffGeometry.slotCoordinate.latitude", "standoffGeometry.slotCoordinate.longitude",
                       "standoffGeometry.slotAltitude", "standoffGeometry.slantRange",
                       "standoffGeometry.gcsDistanceToSlot"):
            self.assertIn(needle, self.panel)

    def test_link_range_is_a_warning_that_does_not_block(self):
        valid = re.search(r"_inputsValid:(.+?)\n\n", self.panel, re.S).group(1)
        for name in ("altitudeError", "distanceError", "heightError", "directionError"):
            self.assertIn(name, valid)
        self.assertNotIn("linkRangeExceeded", valid)
        self.assertIn("visible:             standoffGeometry.linkRangeExceeded", self.panel)
        self.assertIn("The command is not blocked.", self.panel)

    def test_set_standoff_is_blocked_by_invalid_inputs(self):
        button = self.panel.split('text:       qsTr("Set Standoff")', 1)[1]
        self.assertIn("standoffPanel._inputsValid", button.split("onClicked", 1)[0])
        self.assertIn("if (!standoffPanel._inputsValid)", button)
        self.assertNotIn("linkRangeExceeded", button)

    def test_no_target_info_block_yet(self):
        # entered-by / entered-at / source need operator tracking, which is out of scope (todo).
        for needle in ("entered-by", "Entered by", "entered-at", "Entered at", "operator-entered"):
            self.assertNotIn(needle, self.panel)


if __name__ == "__main__":
    unittest.main()
