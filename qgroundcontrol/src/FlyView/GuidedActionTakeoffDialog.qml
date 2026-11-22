import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView

// STRATUM: Modal takeoff dialog. Replaces the inline slide-to-confirm bar for the
// Takeoff command. Captures the desired takeoff altitude and surfaces an explicit
// launch caution, since accepting arms and launches the vehicle.
QGCPopupDialog {
    id:         root
    title:      qsTr("Takeoff")
    buttons:    Dialog.Ok | Dialog.Cancel
    // KAN-53: the Takeoff button must be held for 1 second; the hold is the confirmation.
    acceptButtonText:   qsTr("Takeoff")
    acceptHoldDuration: 1000

    property var    guidedController
    property var    _activeVehicle:     guidedController ? guidedController._activeVehicle : null
    property var    _unitsConversion:   QGroundControl.unitsConversion
    property string _altUnits:          _unitsConversion.appSettingsVerticalDistanceUnitsString
    property real   _minAltitude:       _activeVehicle ? _unitsConversion.metersToAppSettingsVerticalDistanceUnits(_activeVehicle.minimumTakeoffAltitudeMeters()) : 0

    QGCPalette { id: qgcPal }

    onAccepted: {
        var altitude = parseFloat(altitudeField.text)
        if (isNaN(altitude) || altitude < root._minAltitude) {
            altitude = root._minAltitude
        }
        // sliderOutputValue is interpreted in app-settings vertical distance units and
        // converted to meters inside executeAction, matching the original slider path.
        guidedController.executeAction(guidedController.actionTakeoff, undefined, altitude, false)
    }

    ColumnLayout {
        spacing: ScreenTools.defaultFontPixelHeight / 2

        QGCLabel {
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 40
            wrapMode:               Text.WordWrap
            text:                   qsTr("Set the takeoff altitude. The vehicle will climb to this height above its current position.")
        }

        RowLayout {
            spacing: ScreenTools.defaultFontPixelWidth

            QGCLabel { text: qsTr("Takeoff altitude") }

            QGCTextField {
                id:                 altitudeField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 14
                text:               root._minAltitude.toFixed(1)
                unitsLabel:         root._altUnits
                showUnits:          true
                inputMethodHints:   Qt.ImhFormattedNumbersOnly
            }
        }

        QGCLabel {
            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 40
            wrapMode:               Text.WordWrap
            color:                  qgcPal.warningText
            font.bold:              true
            text:                   qsTr("CAUTION: Holding Takeoff for 1 second will launch the vehicle. It will arm (if required) and climb to the altitude above.")
        }
    }
}
