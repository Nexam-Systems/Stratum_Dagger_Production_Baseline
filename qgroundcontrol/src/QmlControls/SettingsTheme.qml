import QtQuick
import QGroundControl

QtObject {
    readonly property bool highContrast: QGroundControl.globalPalette.highContrast
    readonly property bool lightTheme: QGroundControl.globalPalette.lightTheme
    readonly property bool useSharedPalette: highContrast || lightTheme
    readonly property color background: useSharedPalette ? QGroundControl.globalPalette.window : "#061218"
    readonly property color panel: useSharedPalette ? QGroundControl.globalPalette.window : "#09161b"
    readonly property color header: useSharedPalette ? QGroundControl.globalPalette.windowShade : "#0c1b21"
    readonly property color input: useSharedPalette ? QGroundControl.globalPalette.textField : "#0b202a"
    readonly property color border: highContrast ? QGroundControl.globalPalette.text
                                   : lightTheme ? QGroundControl.globalPalette.groupBorder : "#285663"
    readonly property color accent: useSharedPalette ? QGroundControl.globalPalette.brandingPurple : "#2cd4fd"
    readonly property color text: useSharedPalette ? QGroundControl.globalPalette.text : "#edf5f8"
    readonly property color secondaryText: highContrast ? QGroundControl.globalPalette.text
                                          : lightTheme ? QGroundControl.globalPalette.colorGrey : "#aec5cf"
    readonly property color accentText: useSharedPalette ? QGroundControl.globalPalette.primaryButtonText : "#031218"
}
