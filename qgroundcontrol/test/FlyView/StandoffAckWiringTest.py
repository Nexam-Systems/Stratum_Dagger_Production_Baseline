import re
import unittest
from pathlib import Path


# STRATUM #98 / KAN-46: wiring of the ACK-driven slot state in the Set Standoff panel and the map.
# The controller's behaviour is covered by StandoffAckTest.py; the panel and map use C++ types, so
# this pins their wiring at source level.
class StandoffAckWiringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.widget = (root / "src/FlyView/FlyViewWidgetLayer.qml").read_text(encoding="utf-8")
        cls.map = (root / "src/FlyView/FlyViewMap.qml").read_text(encoding="utf-8")
        cls.controller = (root / "src/FlyView/StandoffController.qml").read_text(encoding="utf-8")
        cls.cmake = (root / "src/FlightMap/CMakeLists.txt").read_text(encoding="utf-8")
        cls.images = root / "src/FlightMap/Images"
        cls.panel = cls.widget.split("id:                 standoffPanel", 1)[1].split("MapScale {", 1)[0]

    def test_panel_no_longer_closes_on_send_but_when_the_vehicle_accepts(self):
        button = self.panel.split('text:       qsTr("Set Standoff")', 1)[1]
        self.assertNotIn("standoffPanel.close()", button)
        self.assertIn("beginStandoff(distance, height, speed, direction, target)", button)
        self.assertIn("function onStandoffAccepted() { standoffPanel.close() }", self.panel)

    def test_set_standoff_is_disabled_while_waiting_for_the_ack(self):
        button = self.panel.split('text:       qsTr("Set Standoff")', 1)[1].split("onClicked", 1)[0]
        self.assertIn("standoffCmdController.awaitingAck", button)

    def test_panel_shows_waiting_and_rejected_messages_and_keeps_the_values(self):
        self.assertIn("standoffCmdController.awaitingAck", self.panel)
        self.assertIn("standoffCmdController.rejected", self.panel)
        self.assertIn("standoffCmdController.rejectReason", self.panel)
        self.assertIn("Your values are kept", self.panel)
        # nothing resets the fields on a rejection
        self.assertNotIn('standoffDistanceField.text = "100"', self.panel)

    def test_every_input_edit_clears_the_rejection(self):
        for field in ("Lat", "Lon", "Altitude", "Distance", "Height", "Speed", "Direction"):
            block = self.panel.split(f"id:                    standoff{field}Field", 1)[1].split("QGCLabel {", 1)[0]
            self.assertIn("_inputEdited()", block, field)
        self.assertIn("clearRejected()", self.panel.split("function close()", 1)[1].split("function toggle", 1)[0])

    def test_map_shows_the_rejected_icon_on_the_draft_slot_only(self):
        self.assertTrue((self.images / "StandoffSlotRejected.svg").is_file())
        self.assertIn("Images/StandoffSlotRejected.svg", self.cmake)
        draft = self.map.split("// ---- DRAFT", 1)[1].split("// ---- ACTIVE", 1)[0]
        active = self.map.split("// ---- ACTIVE", 1)[1].split("XC25 fetched-target", 1)[0]
        self.assertIn('standoffController.rejected ? "/qmlimages/StandoffSlotRejected.svg" : "/qmlimages/StandoffSlotDraft.svg"', draft)
        self.assertNotIn("StandoffSlotRejected", active)

    def test_map_draws_a_thin_dashed_blue_path_to_the_slot_while_en_route(self):
        self.assertIn("component StandoffPathDash : MapPolyline", self.map)
        self.assertIn('line.color: "#378ADD"', self.map.split("component StandoffPathDash", 1)[1].split("MapItemView", 1)[0])
        self.assertIn("_standoffPathFrom:   _activeVehicleCoordinate", self.map)
        self.assertIn("_standoffPathTo:     standoffActiveGeometry.slotCoordinate", self.map)
        self.assertIn("_standoffPathVisible: _standoffActiveSlot", self.map)

    def test_map_shows_the_abort_statustext_banner(self):
        self.assertIn("standoffController.statusMessage", self.map)

    def test_controller_listens_to_the_command_result_and_statustext(self):
        self.assertIn("function onMavCommandResult(vehicleId, targetComponent, command, ackResult, failureCode)", self.controller)
        self.assertIn("command !== root._cmdStandoffParams", self.controller)
        self.assertIn("function onTextMessageReceived(", self.controller)
        # the mode switch happens only after the ACK
        begin = self.controller.split("function beginStandoff(", 1)[1].split("function cancelStandoff", 1)[0]
        dagger = begin.split("if (_isDagger) {", 1)[1].split("// Dropper path", 1)[0]
        self.assertNotIn('flightMode = "Standoff"', dagger)
        self.assertIn('flightMode = "Standoff"', self.controller.split("function onMavCommandResult", 1)[1].split("function onTextMessageReceived", 1)[0])


if __name__ == "__main__":
    unittest.main()
