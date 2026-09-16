import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

//-------------------------------------------------------------------------
//-- RC RSSI Indicator
Item {
    id:             control
    width:          rssiRow.width * 1.1
    anchors.top:    parent.top
    anchors.bottom: parent.bottom

    // STRATUM: keep the RC RSSI / signal-strength widget on the bar whenever the vehicle
    // supports a radio link. Bars grey out (percent 0) when no live RSSI is available.
    property bool showIndicator: _activeVehicle.supports.radio

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property bool   _rcRSSIAvailable:   _activeVehicle.rcRSSI.rawValue > 0 && _activeVehicle.rcRSSI.rawValue <= 100

    Component {
        id: rcRSSIInfoPage

        ToolIndicatorPage {
            showExpand: false

            contentComponent: SettingsGroupLayout {
                heading: qsTr("RC RSSI Status")

                LabelledLabel {
                    label:      qsTr("RSSI")
                    labelText:  _activeVehicle.rcRSSI.rawValue + "%"
                }
            }
        }
    }

    Row {
        id:             rssiRow
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        spacing:        ScreenTools.defaultFontPixelWidth * 0.5

        QGCColoredImage {
            width:              height
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            sourceSize.height:  height
            source:             "/qmlimages/RC.svg"
            fillMode:           Image.PreserveAspectFit
            opacity:            _rcRSSIAvailable ? 1 : 0.5
            color:              qgcPal.buttonText
        }

        QGCLabel {
            anchors.verticalCenter: parent.verticalCenter
            text:                   _rcRSSIAvailable ? (_activeVehicle.rcRSSI.rawValue + qsTr("%")) : qsTr("--")
            color:                  qgcPal.buttonText
            font.pointSize:         ScreenTools.smallFontPointSize
            font.bold:              true
            font.family:            ScreenTools.demiboldFontFamily
        }

        SignalStrength {
            anchors.verticalCenter: parent.verticalCenter
            size:                   parent.height * 0.5
            percent:                _rcRSSIAvailable ? _activeVehicle.rcRSSI.rawValue : 0
        }
    }

    MouseArea {
        anchors.fill:   parent
        onClicked:      mainWindow.showIndicatorDrawer(rcRSSIInfoPage, control)
    }
}
