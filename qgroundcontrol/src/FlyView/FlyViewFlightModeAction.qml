import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM: Flight-mode picker on the fly-view command strip. Replaces the top-ribbon
// dropdown; the ribbon now shows the current mode as a read-only status. Clicking a
// mode confirms via a modal dialog (matching Land/Hold behaviour) then writes
// Vehicle.flightMode by its advertised name.
ToolStripAction {
    // NOTE: id must NOT be "action" -- QGCButton inherits AbstractButton.action,
    // which would shadow this id inside the drop-panel button bindings and blank
    // out every entry.
    id:         _root
    text:       qsTr("Flight Mode")
    iconSource: "/qmlimages/FlightModesComponentIcon.png"
    visible:    true
    enabled:    !!QGroundControl.multiVehicleManager.activeVehicle

    // Empty list = show every mode reported by the firmware plugin.
    readonly property var _allowedModes: [
        qsTr("Takeoff"), qsTr("Land"),
        qsTr("Safe Recovery"), qsTr("Return"),
        qsTr("Position"),
        qsTr("Standoff"), qsTr("Engagement"),
        qsTr("Hold"), qsTr("Abort")
    ]

    // PX4 "Position" (POSCTL) is presented as "Manual" to the operator.
    function _displayLabel(mode) {
        return mode === qsTr("Position") ? qsTr("Manual") : mode
    }

    function _commandMode(modeName) {
        var vehicle = QGroundControl.multiVehicleManager.activeVehicle
        if (!vehicle) return
        QGroundControl.showMessageDialog(
            mainWindow,
            modeName,
            qsTr("Switch the vehicle to %1 flight mode?").arg(modeName),
            Dialog.Ok | Dialog.Cancel,
            function() {
                var v = QGroundControl.multiVehicleManager.activeVehicle
                if (v) v.flightMode = modeName
            })
    }

    dropPanelComponent: Component {
        ColumnLayout {
            id:      panelColumn
            spacing: ScreenTools.defaultFontPixelHeight * 0.25

            property var _vehicle: QGroundControl.multiVehicleManager.activeVehicle
            property var _modes: {
                if (!_vehicle) return []
                if (_root._allowedModes.length === 0) return _vehicle.flightModes
                return _vehicle.flightModes.filter(function(m) {
                    return _root._allowedModes.indexOf(m) !== -1
                })
            }

            QGCPalette { id: qgcPal }

            QGCLabel {
                Layout.fillWidth:       true
                horizontalAlignment:    Text.AlignHCenter
                text:                   panelColumn._vehicle
                                            ? qsTr("Current: %1").arg(_root._displayLabel(panelColumn._vehicle.flightMode))
                                            : qsTr("No vehicle")
                font.bold:              true
                color:                  qgcPal.text
            }

            Repeater {
                model: panelColumn._modes

                QGCButton {
                    Layout.fillWidth:       true
                    Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 18
                    text:                   _root._displayLabel(modelData)
                    highlighted:            panelColumn._vehicle && panelColumn._vehicle.flightMode === modelData

                    onClicked: {
                        var mode = modelData
                        dropPanel.hide()
                        _root._commandMode(mode)
                    }
                }
            }
        }
    }
}
