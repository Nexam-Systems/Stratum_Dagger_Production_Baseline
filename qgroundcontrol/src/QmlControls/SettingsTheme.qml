import QtQuick
import QGroundControl

QtObject {
    readonly property bool highContrast: QGroundControl.globalPalette.highContrast
    readonly property color background: highContrast ? QGroundControl.globalPalette.window : "#061218"
    readonly property color panel: highContrast ? QGroundControl.globalPalette.window : "#09161b"
    readonly property color header: highContrast ? QGroundControl.globalPalette.windowShade : "#0c1b21"
    readonly property color input: highContrast ? QGroundControl.globalPalette.textField : "#0b202a"
    readonly property color border: highContrast ? QGroundControl.globalPalette.text : "#285663"
    readonly property color accent: highContrast ? QGroundControl.globalPalette.brandingPurple : "#2cd4fd"
    readonly property color text: highContrast ? QGroundControl.globalPalette.text : "#edf5f8"
    readonly property color secondaryText: highContrast ? QGroundControl.globalPalette.text : "#aec5cf"
    readonly property color accentText: highContrast ? QGroundControl.globalPalette.primaryButtonText : "#031218"
}
