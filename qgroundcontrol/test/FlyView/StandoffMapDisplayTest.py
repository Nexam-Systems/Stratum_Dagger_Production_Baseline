import re
import unittest
from pathlib import Path


# STRATUM #98 / KAN-44: the standoff target, ring and slot are drawn on the FlyView map from
# StandoffGeometry (draft while the Set Standoff panel is open, active once it is pressed). The map
# uses C++ types, so these pin the behaviour at source level.
class StandoffMapDisplayTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.map = (root / "src/FlyView/FlyViewMap.qml").read_text(encoding="utf-8")
        cls.widget = (root / "src/FlyView/FlyViewWidgetLayer.qml").read_text(encoding="utf-8")
        cls.cmake = (root / "src/FlightMap/CMakeLists.txt").read_text(encoding="utf-8")
        cls.images = root / "src/FlightMap/Images"

    def test_old_surveillance_circle_and_t_markers_are_replaced(self):
        self.assertNotIn("standoffSurveillanceCircle", self.map)
        self.assertNotIn("StandoffTargetMarker", self.map)
        self.assertNotIn("MapCircle {", self.map.split("StandoffController {", 1)[1].split("XC25 fetched-target", 1)[0])

    def test_icon_assets_exist_and_are_registered(self):
        for name in ("StandoffTargetDraft", "StandoffTargetActive", "StandoffSlotDraft", "StandoffSlotEnroute"):
            self.assertTrue((self.images / f"{name}.svg").is_file(), name)
            self.assertIn(f"Images/{name}.svg", self.cmake)
            self.assertIn(f"/qmlimages/{name}.svg", self.map)

    def test_draft_and_active_use_the_matching_icons(self):
        draft = self.map.split("// ---- DRAFT", 1)[1].split("// ---- ACTIVE", 1)[0]
        active = self.map.split("// ---- ACTIVE", 1)[1].split("XC25 fetched-target", 1)[0]
        self.assertIn("StandoffTargetDraft.svg", draft)
        self.assertIn("StandoffSlotDraft.svg", draft)
        self.assertIn("StandoffTargetActive.svg", active)
        self.assertIn("StandoffSlotEnroute.svg", active)

    def test_ring_is_a_dashed_geodesic_with_the_r_agl_label(self):
        self.assertIn("component StandoffRingDash : MapPolyline", self.map)
        self.assertIn("model:      _root._standoffDraftRing ? 72 : 0", self.map)
        self.assertIn("StandoffGeometry.ringPath", self.map)
        self.assertIn('qsTr("R %1 m · +%2 m AGL")', self.map)
        self.assertIn("ring[180]", self.map)  # label hangs below the ring's southern point

    def test_slot_points_at_the_target_and_is_labelled_with_the_bearing(self):
        slot = self.map.split("component StandoffSlotIcon", 1)[1].split("component StandoffRingLabel", 1)[0]
        self.assertIn("rotation:           slotIconRoot.slotBearing - _root.bearing", slot)
        self.assertIn('.slice(-3) + "°"', slot)

    def test_only_the_draft_slot_is_draggable_and_only_theta_changes(self):
        draft = self.map.split("// ---- DRAFT", 1)[1].split("// ---- ACTIVE", 1)[0]
        active = self.map.split("// ---- ACTIVE", 1)[1].split("XC25 fetched-target", 1)[0]
        self.assertIn("dragTarget:     _root._standoffPendingCoordinate", draft)
        self.assertIn("onDragged:      (bearing) => _root.standoffSlotDragged(bearing)", draft)
        self.assertNotIn("dragTarget", active)
        # a drag reports only a bearing (never a distance or height)
        self.assertIn("signal standoffSlotDragged(real bearing)", self.map)
        self.assertIn("function onStandoffSlotDragged(bearing)", self.widget)
        handler = self.widget.split("function onStandoffSlotDragged(bearing)", 1)[1].split("}", 1)[0]
        self.assertIn("standoffDirectionField.text", handler)
        self.assertNotIn("standoffDistanceField", handler)
        self.assertNotIn("standoffHeightField", handler)
        self.assertIn("% 360", handler)  # 359.96 must not become the invalid 360.0

    def test_ring_handle_is_draft_only_and_changes_only_the_distance(self):
        draft = self.map.split("// ---- DRAFT", 1)[1].split("// ---- ACTIVE", 1)[0]
        active = self.map.split("// ---- ACTIVE", 1)[1].split("XC25 fetched-target", 1)[0]
        self.assertIn("StandoffRingHandle {", draft)
        self.assertNotIn("StandoffRingHandle", active)
        self.assertIn("onDragged:      (distance) => _root.standoffRingDragged(distance)", draft)
        self.assertIn("signal standoffRingDragged(real distance)", self.map)
        handler = self.widget.split("function onStandoffRingDragged(distance)", 1)[1].split("\n            }", 1)[0]
        self.assertIn("standoffDistanceField.text", handler)
        self.assertNotIn("standoffDirectionField", handler)
        self.assertNotIn("standoffHeightField", handler)
        # a drag is clamped to the configured limits so it can never make the input invalid
        self.assertIn("standoffGeometry.maxDistance", handler)
        self.assertIn("standoffGeometry.minDistance", handler)

    def test_ring_has_a_translucent_red_fill_and_the_dark_outline_sits_under_the_dashes(self):
        self.assertIn("component StandoffRingFill : MapPolygon", self.map)
        self.assertIn("Qt.rgba(0.89, 0.29, 0.29, 0.22)", self.map)   # red, low opacity: map stays visible
        draft = self.map.split("// ---- DRAFT", 1)[1].split("// ---- ACTIVE", 1)[0]
        active = self.map.split("// ---- ACTIVE", 1)[1].split("XC25 fetched-target", 1)[0]
        for part in (draft, active):
            self.assertIn("StandoffRingFill {", part)
            # the dark outline must be a MapItemView declared BEFORE the dash view; a separate
            # MapPolyline is always drawn on top of a MapItemView and hid the dashes
            self.assertLess(part.index("delegate:   StandoffRingShadow"), part.index("delegate:   StandoffRingDash"))
            self.assertNotIn("line.color: Qt.rgba(0, 0, 0, 0.55)", part)

    def test_panel_hands_its_model_to_the_map_and_closing_clears_it(self):
        self.assertIn("mapControl.setStandoffDraft(standoffGeometry)", self.widget)
        stop = self.map.split("function stopStandoffPick() {", 1)[1].split("}", 1)[0]
        self.assertIn("_standoffDraft = null", stop)


if __name__ == "__main__":
    unittest.main()
