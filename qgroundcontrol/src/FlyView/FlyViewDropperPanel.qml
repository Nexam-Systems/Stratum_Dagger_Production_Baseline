import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls

// STRATUM dropper panel. Three sections — Drop / Load / Camera — mirroring the
// UAV-VAS web UI dropper + camera panels one-to-one, in QGC's Stratum styling.
Rectangle {
    id: panel

    property var dropperAction

    QGCPalette { id: contrastPalette; colorGroupEnabled: true }
    readonly property color _accent:    contrastPalette.highContrast ? contrastPalette.buttonBorder : "#3DFFA6"
    readonly property color _accentDim:  contrastPalette.highContrast ? contrastPalette.text : "#1FB97D"
    readonly property color _danger:     "#EF5350"
    readonly property color _dangerFill: "#B71C1C"

    property var _state: dropperAction ? dropperAction._dropperState : ({ selectedMode: null, selectedPayloadIdx: null, dropped: [false, false, false, false], loaded: [false, false, false, false] })

    width: ScreenTools.defaultFontPixelWidth * 30
    implicitHeight: contentColumn.implicitHeight + (ScreenTools.defaultFontPixelWidth * 1.5)
    color: contrastPalette.highContrast ? contrastPalette.window : Qt.rgba(0, 0, 0, 0.86)
    radius: ScreenTools.defaultBorderRadius
    border.color: _accent
    border.width: 1

    MessageDialog {
        id: unloadConfirmDialog
        title: qsTr("Open all payload gates?")
        text: qsTr("This opens ALL servo gates. Ensure the area below the UAV is completely clear before proceeding. Continue?")
        buttons: MessageDialog.Yes | MessageDialog.No
        onAccepted: dropperAction ? dropperAction._dropperUnloadAll() : undefined
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: ScreenTools.defaultFontPixelWidth * 0.75
        spacing: ScreenTools.defaultFontPixelWidth * 0.5

        QGCLabel {
            text: qsTr("PAYLOAD & CAMERA")
            font.bold: true
            color: panel._accent
        }

        QGCLabel {
            text: dropperAction ? dropperAction._dropperStatusText : qsTr("Dropper ready")
            color: "#BFDBFE"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ---- Section selector ------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth * 0.35

            QGCButton {
                text: qsTr("Drop")
                Layout.fillWidth: true
                primary: dropperAction && dropperAction._dropperSection === "drop"
                onClicked: dropperAction ? dropperAction._showDropperSection("drop") : undefined
            }
            QGCButton {
                text: qsTr("Load")
                Layout.fillWidth: true
                primary: dropperAction && dropperAction._dropperSection === "load"
                onClicked: dropperAction ? dropperAction._showDropperSection("load") : undefined
            }
            QGCButton {
                text: qsTr("Camera")
                Layout.fillWidth: true
                primary: dropperAction && dropperAction._dropperSection === "camera"
                onClicked: dropperAction ? dropperAction._showDropperSection("camera") : undefined
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: panel._accentDim; opacity: 0.4 }

        // ==== DROP: select PLD or BURST, then commit with DROP ================
        ColumnLayout {
            visible: dropperAction && dropperAction._dropperSection === "drop"
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth * 0.4

            QGCLabel {
                text: qsTr("SELECT PAYLOAD OR BURST, THEN DROP")
                color: "#FF9800"
                font.pointSize: ScreenTools.smallFontPointSize
            }

            GridLayout {
                columns: 2
                Layout.fillWidth: true
                columnSpacing: ScreenTools.defaultFontPixelWidth * 0.4
                rowSpacing: ScreenTools.defaultFontPixelWidth * 0.4

                Repeater {
                    model: 4
                    delegate: QGCButton {
                        required property int index
                        readonly property bool _dropped: panel._state.dropped[index]
                        readonly property bool _selected: panel._state.selectedMode === "single" && panel._state.selectedPayloadIdx === index
                        Layout.fillWidth: true
                        text: _dropped ? qsTr("✓ PLD %1").arg(index + 1) : qsTr("PLD %1").arg(index + 1)
                        enabled: dropperAction && !_dropped
                        primary: _selected
                        onClicked: dropperAction ? dropperAction._selectDrop("single", index) : undefined
                    }
                }
            }

            QGCButton {
                text: qsTr("⚡ BURST (ALL)")
                Layout.fillWidth: true
                primary: panel._state.selectedMode === "burst"
                onClicked: dropperAction ? dropperAction._selectDrop("burst", -1) : undefined
            }

            QGCButton {
                text: qsTr("▼ DROP")
                Layout.fillWidth: true
                enabled: dropperAction && panel._state.selectedMode !== null
                backgroundColor: enabled ? panel._dangerFill : Qt.rgba(0.3, 0.1, 0.1, 0.4)
                textColor: enabled ? "white" : "#88FFFFFF"
                onClicked: dropperAction ? dropperAction._requestDrop() : undefined
            }

            // Safety-override — shown only after a drop was blocked by the distance check,
            // matching the web UI override flow.
            QGCButton {
                visible: dropperAction && dropperAction._dropBlockReason !== ""
                Layout.fillWidth: true
                text: qsTr("⚠ OVERRIDE & DROP")
                backgroundColor: "#7A1FA2"
                textColor: "white"
                onClicked: dropperAction ? dropperAction._executeDrop() : undefined
            }

            QGCLabel {
                visible: dropperAction && dropperAction._dropBlockReason !== ""
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#FBBF24"
                font.pointSize: ScreenTools.smallFontPointSize
                text: qsTr("Overriding safety checks may release the payload in an unintended location.")
            }

            QGCLabel {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: panel._accentDim
                font.pointSize: ScreenTools.smallFontPointSize
                text: {
                    var n = panel._state.dropped.filter(function (d) { return d }).length
                    if (n === 4) return qsTr("✓ ALL PAYLOADS DEPLOYED")
                    if (n > 0)   return qsTr("%1 dropped · %2 remaining").arg(n).arg(4 - n)
                    return ""
                }
            }
        }

        // ==== LOAD: each bay loads / unloads independently ===================
        ColumnLayout {
            visible: dropperAction && dropperAction._dropperSection === "load"
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth * 0.4

            QGCLabel {
                text: qsTr("Tap a bay to load it (close gate); tap again to unload (open gate). Bays are independent.")
                color: panel._accentDim
                font.pointSize: ScreenTools.smallFontPointSize
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            QGCButton {
                text: qsTr("⊞ OPEN ALL GATES")
                Layout.fillWidth: true
                enabled: !!dropperAction && !!dropperAction._activeVehicle
                onClicked: unloadConfirmDialog.open()
            }

            GridLayout {
                columns: 2
                Layout.fillWidth: true
                columnSpacing: ScreenTools.defaultFontPixelWidth * 0.4
                rowSpacing: ScreenTools.defaultFontPixelWidth * 0.4

                Repeater {
                    model: 4
                    delegate: QGCButton {
                        required property int index
                        readonly property bool _loaded: panel._state.loaded[index]
                        Layout.fillWidth: true
                        text: _loaded ? qsTr("✓ PLD %1 (unload)").arg(index + 1) : qsTr("▼ Load PLD %1").arg(index + 1)
                        primary: _loaded
                        enabled: dropperAction && !!dropperAction._activeVehicle
                        onClicked: dropperAction ? dropperAction._dropperToggleLoad(index) : undefined
                    }
                }
            }

            QGCLabel {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: panel._accentDim
                font.pointSize: ScreenTools.smallFontPointSize
                text: {
                    var n = panel._state.loaded.filter(function (l) { return l }).length
                    if (n === 4) return qsTr("✓ ALL 4 BAYS LOADED")
                    if (n > 0)   return qsTr("%1 of 4 bays loaded").arg(n)
                    return qsTr("All gates open")
                }
            }
        }

        // ==== CAMERA =========================================================
        ColumnLayout {
            visible: dropperAction && dropperAction._dropperSection === "camera"
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth * 0.4

            // When the camera is the maximized window the controls live on the video
            // overlay, so the panel just points the operator there (req. 4).
            QGCLabel {
                visible: dropperAction && dropperAction.cameraMaximized
                text: qsTr("Camera controls are shown over the maximized video.")
                color: panel._accentDim
                font.pointSize: ScreenTools.smallFontPointSize
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            FlyViewCameraControls {
                id: cameraControls
                visible: dropperAction && !dropperAction.cameraMaximized
                Layout.fillWidth: true
                compact: true
                onStatusMessage: function (text) {
                    if (dropperAction) dropperAction._setStatus(text)
                }
            }
        }
    }
}
