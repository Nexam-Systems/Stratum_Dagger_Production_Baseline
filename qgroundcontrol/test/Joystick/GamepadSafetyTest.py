import os
from pathlib import Path
import time
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QJSValue, QQmlComponent, QQmlEngine


class GamepadSafetyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.engine = QQmlEngine()
        cls.source = Path(__file__).resolve().parents[2] / "src/FlyView/GamepadSafetyState.qml"
        cls.component = QQmlComponent(cls.engine, QUrl.fromLocalFile(str(cls.source)))
        assert not cls.component.isError(), [error.toString() for error in cls.component.errors()]

    def setUp(self):
        self.item = self.component.create()
        self.commands = []
        self.navigation = []
        self.item.committed.connect(self.commands.append)
        self.item.navigationRequested.connect(lambda horizontal, vertical: self.navigation.append((horizontal, vertical)))
        self.item.setProperty("modeEnabled", True)
        self.feed()

    def tearDown(self):
        self.item.deleteLater()
        self.app.processEvents()

    def call(self, name, *arguments):
        values = [QJSValue(value if isinstance(value, (bool, str)) else float(value)) for value in arguments]
        result = self.engine.newQObject(self.item).property(name).call(values)
        self.assertFalse(result.isError(), result.toString())

    def feed(self, buttons=0, safety=False, manual=False, ready=True, timestamp=None):
        self.call("process", buttons, safety, manual, ready, timestamp or int(time.time() * 1000))

    def select_and_arm(self, face=8):
        self.feed(face)
        self.feed()
        self.feed(safety=True)
        self.item.setProperty("armStartedMs", int(time.time() * 1000) - 700)

    def test_disabled_never_executes(self):
        self.item.setProperty("modeEnabled", False)
        self.select_and_arm()
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])

    def test_select_arm_right_hand_commit_once(self):
        for face, command in [(8, "Takeoff"), (4, "Standoff"), (1, "RTL")]:
            self.select_and_arm(face)
            self.feed(1 << 10, safety=True)
            self.feed(1 << 10, safety=True)
            self.assertEqual(self.commands[-1], command)
            self.feed()
        self.assertEqual(self.commands, ["Takeoff", "Standoff", "RTL"])

    def test_early_commit_requires_new_press(self):
        self.feed(8)
        self.feed(safety=True)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])
        self.item.setProperty("armStartedMs", int(time.time() * 1000) - 700)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])
        self.feed(safety=True)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, ["Takeoff"])

    def test_preheld_l2_does_not_arm_selection(self):
        self.feed(safety=True)
        self.feed(8, safety=True)
        self.feed(safety=True)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])
        self.feed()
        self.feed(safety=True)
        self.item.setProperty("armStartedMs", int(time.time() * 1000) - 700)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, ["Takeoff"])

    def test_circle_cancels_without_abort(self):
        self.select_and_arm()
        self.feed(2)
        self.assertEqual(self.item.property("pendingCommand"), "")
        self.assertEqual(self.commands, [])

    def test_abort_requires_one_second_continuous_hold(self):
        self.feed(1 << 9)
        self.feed((1 << 9) | 2)
        self.assertEqual(self.item.property("pendingCommand"), "Abort")
        self.item.setProperty("holdStartedMs", int(time.time() * 1000) - 900)
        self.feed((1 << 9) | 2)
        self.assertEqual(self.commands, [])
        self.item.setProperty("holdStartedMs", int(time.time() * 1000) - 1000)
        self.feed((1 << 9) | 2)
        self.feed((1 << 9) | 2)
        self.assertEqual(self.commands, ["Abort"])

    def test_abort_release_cancels_hold(self):
        self.feed((1 << 9) | 2)
        self.feed(1 << 9)
        self.assertEqual(self.item.property("pendingCommand"), "")
        self.assertEqual(self.item.property("holdStartedMs"), 0)
        self.assertEqual(self.commands, [])

    def test_engage_requires_selection_and_three_second_hold(self):
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])
        self.feed((1 << 9) | 8, safety=True)
        self.assertEqual(self.item.property("pendingCommand"), "Engage")
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.item.property("holdStartedMs"), 0)
        self.feed()
        self.feed(1 << 10, safety=True)
        self.item.setProperty("holdStartedMs", int(time.time() * 1000) - 2900)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])
        self.item.setProperty("holdStartedMs", int(time.time() * 1000) - 3000)
        self.feed(1 << 10, safety=True)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, ["Engage"])

    def test_engage_release_resets_progress(self):
        self.feed((1 << 9) | 8)
        self.feed()
        self.feed(1 << 10, safety=True)
        self.item.setProperty("holdStartedMs", int(time.time() * 1000) - 2000)
        self.feed(safety=True)
        self.assertEqual(self.item.property("holdStartedMs"), 0)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])

    def test_input_gap_interrupts_timed_holds(self):
        self.feed((1 << 9) | 2)
        self.item.setProperty("holdStartedMs", int(time.time() * 1000) - 1100)
        self.item.setProperty("lastSampleMs", int(time.time() * 1000) - 300)
        self.feed((1 << 9) | 2)
        self.assertEqual(self.commands, [])
        self.assertEqual(self.item.property("pendingCommand"), "")
        self.feed()
        self.feed((1 << 9) | 8)
        self.feed()
        self.feed(1 << 10, safety=True)
        self.item.setProperty("holdStartedMs", int(time.time() * 1000) - 3100)
        self.item.setProperty("lastSampleMs", int(time.time() * 1000) - 300)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])
        self.assertEqual(self.item.property("holdStartedMs"), 0)

    def test_expired_and_stale_samples_do_not_commit(self):
        self.select_and_arm()
        self.item.setProperty("selectionDeadlineMs", int(time.time() * 1000) - 1)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])
        self.feed()
        self.select_and_arm()
        self.feed(1 << 10, safety=True, timestamp=int(time.time() * 1000) - 1000)
        self.assertEqual(self.commands, [])

    def test_r2_and_conflicting_faces_cancel(self):
        self.select_and_arm()
        self.feed(1 << 10, safety=True, manual=True)
        self.assertEqual(self.commands, [])
        self.assertEqual(self.item.property("pendingCommand"), "")
        self.feed()
        self.feed(8 | 4)
        self.assertEqual(self.item.property("pendingCommand"), "")

    def test_release_gate_and_reenable_clear_selection(self):
        self.feed(8, safety=True, ready=False)
        self.assertEqual(self.item.property("pendingCommand"), "")
        self.feed()
        self.select_and_arm()
        self.item.setProperty("modeEnabled", False)
        self.item.setProperty("modeEnabled", True)
        self.feed(1 << 10, safety=True)
        self.assertEqual(self.commands, [])

    def test_dpad_navigation_not_flight_command(self):
        self.feed(1 << 11)
        self.assertEqual(self.navigation, [(0, -1)])
        self.assertEqual(self.commands, [])


if __name__ == "__main__":
    unittest.main()