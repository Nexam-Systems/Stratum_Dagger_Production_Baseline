import re
import unittest
from pathlib import Path


# STRATUM KAN-15: top-bar indicators share a unified look. These source-level checks pin
# the standardization (toolbar indicators are rendered-only QML not runnable in the
# isolated harness): unified indicatorColor high-contrast source, consistent RSSI row
# spacing, non-bold RSSI label, small battery voltage font, and a shared indicatorColor
# in the telemetry header.
class ToolbarIndicatorConsistencyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        toolbar = Path(__file__).resolve().parents[2] / "src/Toolbar"
        cls.files = {
            n: (toolbar / f"{n}.qml").read_text(encoding="utf-8")
            for n in ["GPSIndicator", "RCRSSIIndicator", "TelemetryRSSIIndicator",
                      "BatteryIndicator", "SignalStrength", "FlightTelemetryHeader"]
        }

    def test_unified_indicator_color_high_contrast_source(self):
        for name in ["GPSIndicator", "RCRSSIIndicator", "TelemetryRSSIIndicator",
                     "BatteryIndicator", "SignalStrength"]:
            line = re.search(r"indicatorColor:\s*(.+)", self.files[name]).group(1)
            self.assertIn('qgcPal.highContrast ? qgcPal.text : "#79CBE8"', line, name)

    def test_flight_header_uses_shared_indicator_color(self):
        header = self.files["FlightTelemetryHeader"]
        self.assertIn('readonly property color indicatorColor: headerPalette.highContrast ? headerPalette.text : "#79CBE8"', header)
        self.assertNotIn("headerPalette.buttonBorder", header)

    def test_rc_rssi_label_not_bold_or_demibold(self):
        rc = self.files["RCRSSIIndicator"]
        self.assertNotIn("demiboldFontFamily", rc)
        self.assertNotIn("font.bold:", rc)

    def test_rssi_row_spacing_consistent(self):
        self.assertIn("spacing:        ScreenTools.defaultFontPixelWidth * 0.5", self.files["RCRSSIIndicator"])
        self.assertIn("spacing:        ScreenTools.defaultFontPixelWidth * 0.5", self.files["TelemetryRSSIIndicator"])

    def test_battery_voltage_label_uses_small_font(self):
        # The QGCLabel that renders the voltage uses the standard small point size.
        voltage_label = re.search(r"QGCLabel \{[^{}]*getBatteryVoltageText\(\)[^{}]*\}",
                                  self.files["BatteryIndicator"], re.S).group(0)
        self.assertIn("ScreenTools.smallFontPointSize", voltage_label)
        self.assertNotIn("mediumFontPointSize", voltage_label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
