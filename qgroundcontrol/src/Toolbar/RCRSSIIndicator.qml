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
    property bool showIndicator: _activeVehicle && _activeVehicle.supports && _activeVehicle.supports.radio

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    readonly property color indicatorColor: qgcPal.highContrast ? qgcPal.text : "#79CBE8"
    property bool   _rcRSSIAvailable:   _activeVehicle && _activeVehicle.rcRSSI && Number(_activeVehicle.rcRSSI.rawValue) > 0 && Number(_activeVehicle.rcRSSI.rawValue) <= 100
    readonly property string _rcRSSIText: {
        if (!_activeVehicle || !_activeVehicle.rcRSSI) return qsTr("--")
        var value = Number(_activeVehicle.rcRSSI.rawValue)
        return isFinite(value) && value > 0 && value <= 100 ? value.toFixed(0) + "%" : qsTr("--")
    }

    Component {
        id: rcRSSIInfoPage

        ToolIndicatorPage {
            showExpand: false

            contentComponent: SettingsGroupLayout {
                heading: qsTr("RC RSSI Status")

                LabelledLabel {
                    label:      qsTr("RSSI")
                    labelText:  _rcRSSIText
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
            color:              control.indicatorColor
        }

        QGCLabel {
            anchors.verticalCenter: parent.verticalCenter
            text:                   _rcRSSIText
            color:                  control.indicatorColor
            font.pointSize:         ScreenTools.smallFontPointSize
        }

        SignalStrength {
            indicatorColor: control.indicatorColor
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
