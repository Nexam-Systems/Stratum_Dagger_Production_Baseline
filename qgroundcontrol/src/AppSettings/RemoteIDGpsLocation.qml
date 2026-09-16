import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

SettingsGroupLayout {
    heading:            qsTr("NMEA External GPS")
    Layout.fillWidth:   true
    // STRATUM: always expose the NMEA GPS device + baudrate on desktop so the operator
    // can activate the external GCS GPS regardless of RID location-type or the
    // autoConnect user-visible flags (which some plugins default to false on setup).
    visible:            !ScreenTools.isMobile

    property int    _locationType:    QGroundControl.settingsManager.remoteIDSettings.locationType.value

    readonly property int _idxDisabled: 0
    readonly property int _idxUdpPort:  1

    LabelledComboBox {
        id:                 nmeaPortCombo
        label:              qsTr("Device")
        Layout.fillWidth:   true

        model: ListModel { }

        onActivated: (index) => {
            if (index !== -1) {
                QGroundControl.settingsManager.autoConnectSettings.autoConnectNmeaPort.value = comboBox.textAt(index);
            }
        }
        Component.onCompleted: {
            model.append({text: qsTr("Disabled")})
            model.append({text: qsTr("UDP Port")})

            for (var i in QGroundControl.linkManager.serialPorts) {
                nmeaPortCombo.model.append({text: QGroundControl.linkManager.serialPorts[i]})
            }
            var index = nmeaPortCombo.comboBox.find(QGroundControl.settingsManager.autoConnectSettings.autoConnectNmeaPort.valueString);
            nmeaPortCombo.currentIndex = index;
            if (QGroundControl.linkManager.serialPorts.length === 0) {
                nmeaPortCombo.model.append({text: qsTr("Serial <none available>")})
            }
        }
    }

    LabelledComboBox {
        id:                 nmeaBaudCombo
        label:              qsTr("Baudrate")
        Layout.fillWidth:   true
        visible:            nmeaPortCombo.currentIndex > _idxUdpPort
        model:              QGroundControl.linkManager.serialBaudRates

        onActivated: (index) => {
            if (index !== -1) {
                QGroundControl.settingsManager.autoConnectSettings.autoConnectNmeaBaud.value = parseInt(comboBox.textAt(index));
            }
        }
        Component.onCompleted: {
            var index = nmeaBaudCombo.comboBox.find(QGroundControl.settingsManager.autoConnectSettings.autoConnectNmeaBaud.valueString);
            nmeaBaudCombo.currentIndex = index;
        }
    }

    LabelledFactTextField {
        label:              qsTr("UDP Port")
        fact:               QGroundControl.settingsManager.autoConnectSettings.nmeaUdpPort
        Layout.fillWidth:   true
        visible:            nmeaPortCombo.currentIndex === _idxUdpPort
    }
}
