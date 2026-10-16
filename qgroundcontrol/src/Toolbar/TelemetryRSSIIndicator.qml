import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

//-------------------------------------------------------------------------
//-- Telemetry / Network Link RSSI
Item {
    id:             control
    objectName:     "toolbar_telemetryRSSIIndicator"
    anchors.top:    parent.top
    anchors.bottom: parent.bottom
    width:          telemRow.width * 1.1

    // STRATUM: show the network/telemetry link strength whenever the vehicle uses a radio
    // link, so operators always have a link indicator (bars grey out when no live data).
    property bool showIndicator: (_activeVehicle && _activeVehicle.supports && _activeVehicle.supports.radio) || _hasTelemetry

    property var  _activeVehicle:   QGroundControl.multiVehicleManager.activeVehicle
    property var  _radioStatus:     _activeVehicle ? _activeVehicle.radioStatus : null
    property bool _hasTelemetry:    _radioStatus && _radioStatus.lrssi && Number(_radioStatus.lrssi.rawValue) !== 0

    // RADIO_STATUS rssi is reported as a 0-255 raw value (higher is stronger). Map to a
    // 0-100 percentage for the shared SignalStrength bar visual.
    property real _linkPercent:     _hasTelemetry ? Math.max(0, Math.min(100, Number(_radioStatus.lrssi.rawValue) * (100.0 / 255.0))) : 0

    Row {
        id:             telemRow
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        spacing:        ScreenTools.defaultFontPixelWidth

        QGCColoredImage {
            id:                 telemIcon
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            width:              height
            sourceSize.height:  height
            source:             "/qmlimages/TelemRSSI.svg"
            fillMode:           Image.PreserveAspectFit
            opacity:            _hasTelemetry ? 1 : 0.5
            color:              qgcPal.buttonText
        }

        SignalStrength {
            anchors.verticalCenter: parent.verticalCenter
            size:                   parent.height * 0.5
            percent:                _linkPercent
        }
    }

    MouseArea {
        anchors.fill:   parent
        onClicked:      mainWindow.showIndicatorDrawer(telemRSSIInfoPage, control)
    }

    Component {
        id: telemRSSIInfoPage

        ToolIndicatorPage {
            showExpand: false

            contentComponent: SettingsGroupLayout {
                heading: qsTr("Telemetry RSSI Status")

                LabelledLabel {
                    label:      qsTr("Local RSSI:")
                    labelText:  _radioStatus.lrssi.rawValue + " " + qsTr("dBm")
                }

                LabelledLabel {
                    label:      qsTr("Remote RSSI:")
                    labelText:  _radioStatus.rrssi.rawValue + " " + qsTr("dBm")
                }

                LabelledLabel {
                    label:      qsTr("RX Errors:")
                    labelText:  _radioStatus.rxErrors.rawValue
                }

                LabelledLabel {
                    label:      qsTr("Errors Fixed:")
                    labelText:  _radioStatus.fixed.rawValue
                }

                LabelledLabel {
                    label:      qsTr("TX Buffer:")
                    labelText:  _radioStatus.txBuffer.rawValue
                }

                LabelledLabel {
                    label:      qsTr("Local Noise:")
                    labelText:  _radioStatus.lNoise.rawValue
                }

                LabelledLabel {
                    label:      qsTr("Remote Noise:")
                    labelText:  _radioStatus.rNoise.rawValue
                }
            }
        }
    }
}
