import unittest
from pathlib import Path


# STRATUM KAN-45: Change Height opens a small pop-up (like Takeoff) instead of the scrollable
# height slider. The controller and dialog use QGC types, so this pins the wiring at source level.
class ChangeHeightDialogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        cls.controller = (root / "src/FlyView/GuidedActionsController.qml").read_text(encoding="utf-8")
        cls.dialog = (root / "src/FlyView/GuidedActionChangeHeightDialog.qml").read_text(encoding="utf-8")
        cls.cmake = (root / "src/FlyView/CMakeLists.txt").read_text(encoding="utf-8")
        cls.panel = (root / "src/FlyView/RightMissionPanel.qml").read_text(encoding="utf-8")

    def test_every_change_height_entry_point_opens_the_dialog_not_the_slider(self):
        confirm = self.controller.split("function confirmAction(", 1)[1]
        head = confirm.split("var showImmediate", 1)[0]
        self.assertIn("if (actionCode === actionChangeAlt)", head)
        self.assertIn("showChangeHeightDialog()", head)
        self.assertIn("return", head)
        # the slider is no longer set up or shown for Change Height
        setup = self.controller.split("function setupSlider(", 1)[1].split("on_ActiveVehicleChanged", 1)[0]
        self.assertNotIn("actionChangeAlt", setup)
        self.assertNotIn("case actionChangeAlt:\n            confirmDialog.title", self.controller)

    def test_panel_button_still_goes_through_confirm_action(self):
        self.assertIn("root.guidedController.confirmAction(root.guidedController.actionChangeAlt)", self.panel)

    def test_dialog_is_registered_and_instantiated_by_the_controller(self):
        self.assertIn("GuidedActionChangeHeightDialog.qml", self.cmake)
        self.assertIn("GuidedActionChangeHeightDialog {", self.controller)
        self.assertIn("changeHeightDialogFactory.open({ anchorRect: anchor })", self.controller)

    def test_dialog_has_a_change_height_button_and_limits_the_value(self):
        self.assertIn('acceptButtonText:   qsTr("Change Height")', self.dialog)
        self.assertIn("guidedMinimumAltitude", self.dialog)
        self.assertIn("guidedMaximumAltitude", self.dialog)
        self.assertIn("acceptButtonEnabled: _heightValid && _canChange", self.dialog)
        self.assertIn("guidedController.executeAction(guidedController.actionChangeAlt, undefined, _enteredHeight, false)", self.dialog)

    def test_field_is_not_bound_to_the_live_altitude(self):
        field = self.dialog.split("id:                     heightField", 1)[1].split("QGCLabel", 1)[0]
        self.assertNotIn("text:                   Math", field)


if __name__ == "__main__":
    unittest.main()
