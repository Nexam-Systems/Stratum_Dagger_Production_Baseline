import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// Used as the base class control for both VehicleGPSIndicator and RTKGPSIndicator

Item {
    id:             control
    width:          gpsIndicatorRow.width
    anchors.top:    parent.top
    anchors.bottom: parent.bottom

    property var    _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property bool   _rtkConnected:  QGroundControl.gpsRtk.connected.value

    // STRATUM: toolbar shows horizontal/vertical accuracy in centimeters plus satellite count,
    // instead of the older HDOP dilution-of-precision figure.
    property var    _gps:           _activeVehicle ? _activeVehicle.gps : null
    property real   _hAccM:         _gps ? _gps.horizontalAccuracy.value : NaN
    property real   _vAccM:         _gps ? _gps.verticalAccuracy.value   : NaN
    property string _hAccText:      (_gps && !isNaN(_hAccM)) ? (_hAccM.toFixed(2) + " " + qsTr("m")) : qsTr("--")
    property string _vAccText:      (_gps && !isNaN(_vAccM)) ? (_vAccM.toFixed(2) + " " + qsTr("m")) : qsTr("--")
    property string _nSatText:      _gps ? _gps.count.valueString : qsTr("--")

    QGCPalette { id: qgcPal }

    Row {
        id:             gpsIndicatorRow
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        spacing:        ScreenTools.defaultFontPixelWidth / 2

        Row {
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            spacing:        -ScreenTools.defaultFontPixelWidth / 2

            QGCLabel {
                id:                     gpsLabel
                rotation:               90
                text:                   qsTr("RTK")
                color:                  qgcPal.text
                anchors.verticalCenter: parent.verticalCenter
                visible:                _rtkConnected
            }

            QGCColoredImage {
                id:                 gpsIcon
                width:              height
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                source:             "/qmlimages/Gps.svg"
                fillMode:           Image.PreserveAspectFit
                sourceSize.height:  height
                opacity:            (_activeVehicle && _activeVehicle.gps.count.value >= 0) ? 1 : 0.5
                color:              qgcPal.text
            }
        }

        GridLayout {
            id:                     gpsValuesGrid
            anchors.verticalCenter: parent.verticalCenter
            visible:                _gps && _gps.telemetryAvailable
            columns:                2
            rowSpacing:             0
            columnSpacing:          ScreenTools.defaultFontPixelWidth / 2

            QGCLabel {
                text:               qsTr("HAcc")
                color:              qgcPal.text
                font.pointSize:     ScreenTools.smallFontPointSize
            }
            QGCLabel {
                text:               _hAccText
                color:              qgcPal.text
                font.pointSize:     ScreenTools.smallFontPointSize
                Layout.alignment:   Qt.AlignRight
            }

            QGCLabel {
                text:               qsTr("VAcc")
                color:              qgcPal.text
                font.pointSize:     ScreenTools.smallFontPointSize
            }
            QGCLabel {
                text:               _vAccText
                color:              qgcPal.text
                font.pointSize:     ScreenTools.smallFontPointSize
                Layout.alignment:   Qt.AlignRight
            }

            QGCLabel {
                text:               qsTr("Nsat")
                color:              qgcPal.text
                font.pointSize:     ScreenTools.smallFontPointSize
            }
            QGCLabel {
                text:               _nSatText
                color:              qgcPal.text
                font.pointSize:     ScreenTools.smallFontPointSize
                Layout.alignment:   Qt.AlignRight
            }
        }
    }

    MouseArea {
        anchors.fill:   parent
        onClicked:      mainWindow.showIndicatorDrawer(gpsIndicatorPage, control)
    }

    Component {
        id: gpsIndicatorPage

        GPSIndicatorPage { }
    }
}
