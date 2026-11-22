import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView

// STRATUM KAN-45: Change Height dialog. Replaces the scrollable height slider that used to open
// beside the control panel. A small pop-up (same style as the Takeoff dialog) captures the new
// height above the take-off point; pressing "Change Height" commands the vehicle to it.
QGCPopupDialog {
    id:                 root
    title:              qsTr("Change Height")
    buttons:            Dialog.Ok | Dialog.Cancel
    acceptButtonText:   qsTr("Change Height")
    acceptHoldDuration: 1000                    // KAN-53: hold for 1 second to confirm

    property var    guidedController
    property var    _activeVehicle:     guidedController ? guidedController._activeVehicle : null
    property var    _unitsConversion:   QGroundControl.unitsConversion
    property var    _flyViewSettings:   QGroundControl.settingsManager.flyViewSettings
    property string _altUnits:          _unitsConversion.appSettingsVerticalDistanceUnitsString
    // All values below are in app-settings vertical distance units, like the Takeoff dialog.
    property real   _minHeight:         _flyViewSettings.guidedMinimumAltitude.value
    property real   _maxHeight:         _flyViewSettings.guidedMaximumAltitude.value
    property real   _currentHeight:     _activeVehicle ? _activeVehicle.altitudeRelative.value : 0
    property real   _enteredHeight:     parseFloat(heightField.text)
    property bool   _canChange:         guidedController && guidedController.showChangeAlt
    property bool   _heightValid:       !isNaN(_enteredHeight) && _enteredHeight >= _minHeight && _enteredHeight <= _maxHeight

    acceptButtonEnabled: _heightValid && _canChange

    QGCPalette { id: qgcPal }

    onAccepted: {
        // sliderOutputValue is interpreted in app-settings vertical distance units and converted
        // to meters inside executeAction, which computes the change from the current height.
        guidedController.executeAction(guidedController.actionChangeAlt, undefined, _enteredHeight, false)
    }

    ColumnLayout {
        spacing: ScreenTools.defaultFontPixelHeight / 2

        QGCLabel {
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 40
            wrapMode:               Text.WordWrap
            text:                   qsTr("Set the new height. The vehicle will climb or descend to this height above its take-off point.")
        }

        QGCLabel {
            text: qsTr("Current height: %1 %2").arg(root._currentHeight.toFixed(1)).arg(root._altUnits)
        }

        RowLayout {
            spacing: ScreenTools.defaultFontPixelWidth

            QGCLabel { text: qsTr("New height") }

            QGCTextField {
                id:                     heightField
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 14
                // Filled once when the dialog opens (not bound), so live altitude updates
                // never overwrite what the operator is typing.
                unitsLabel:             root._altUnits
                showUnits:              true
                inputMethodHints:       Qt.ImhFormattedNumbersOnly
                Component.onCompleted: {
                    text = Math.min(root._maxHeight, Math.max(root._minHeight, root._currentHeight)).toFixed(1)
                    selectAll()
                    forceActiveFocus()
                }
            }
        }

        QGCLabel {
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 40
            wrapMode:               Text.WordWrap
            visible:                !root._heightValid
            color:                  qgcPal.warningText
            text:                   qsTr("Height must be between %1 and %2 %3.")
                                        .arg(root._minHeight.toFixed(1)).arg(root._maxHeight.toFixed(1)).arg(root._altUnits)
        }

        QGCLabel {
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 40
            wrapMode:               Text.WordWrap
            visible:                !root._canChange
            color:                  qgcPal.warningText
            text:                   qsTr("The height can only be changed while the vehicle is armed and flying.")
        }
    }
}
