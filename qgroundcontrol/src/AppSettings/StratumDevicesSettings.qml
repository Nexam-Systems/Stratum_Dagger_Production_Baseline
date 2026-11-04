import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

// STRATUM Devices registry. Operators register each aircraft by its device serial
// number (the 8-byte DIP V2 frame, hex) and a friendly vehicle name. STRATUM decrypts
// the serial with the Device Info Key to derive the camera IP + data-link, and
// "Apply" provisions the camera (IP + TV/IR streams) from that serial.
Rectangle {
    id:             root
    objectName:     "settingsPage_StratumDevices"
    color:          qgcPal.window
    anchors.fill:   parent

    readonly property real _margins: ScreenTools.defaultFontPixelHeight
    readonly property var  _vs:      QGroundControl.settingsManager.videoSettings
    readonly property var  _vm:      QGroundControl.videoManager

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    function loadRegistry() {
        deviceModel.clear()
        try {
            const arr = JSON.parse(_vs.deviceRegistry.rawValue || "[]")
            for (let i = 0; i < arr.length; ++i) {
                deviceModel.append({ serial: arr[i].serial || "", name: arr[i].name || "" })
            }
        } catch (e) {
            // Corrupt/empty registry -- start fresh.
        }
    }

    function saveRegistry() {
        var arr = []
        for (let i = 0; i < deviceModel.count; ++i) {
            const row = deviceModel.get(i)
            arr.push({ serial: row.serial, name: row.name })
        }
        _vs.deviceRegistry.rawValue = JSON.stringify(arr)
    }

    // Returns a human-readable decode preview for a serial.
    function previewText(serial) {
        if (!serial || serial.length === 0) {
            return qsTr("Enter a 16-character (8-byte) serial")
        }
        const r = _vm.decodeDeviceSerial(serial)
        if (r.valid) {
            return qsTr("Camera %1  ·  Data-link %2:%3").arg(r.cameraIp).arg(r.dataIp).arg(r.port)
        }
        return qsTr("Invalid: %1").arg(r.error)
    }

    function previewColor(serial) {
        if (!serial || serial.length === 0) {
            return qgcPal.text
        }
        return _vm.decodeDeviceSerial(serial).valid ? qgcPal.colorGreen : qgcPal.colorOrange
    }

    // Reconstruct the full 8-character handshake (NX + the 6 decoded digits) and register
    // it as a MAVLink signing key, so the aircraft's signed connection is accepted when it
    // connects. The serial carries only the 6 digits; the "NX" marker is prepended here.
    function registerSigningKey(serial, name) {
        const r = _vm.decodeDeviceSerial(serial)
        if (!r.valid) {
            return false
        }
        const keyName = (name && name.length > 0) ? name : serial
        // addKey() returns false if a key with this name already exists -- harmless/idempotent.
        QGroundControl.mavlinkSigningKeys.addKey(keyName, "NX" + r.handshake)
        return true
    }

    ListModel { id: deviceModel }

    Component.onCompleted: {
        loadRegistry()
        // Make every registered device's handshake key available up front so any of them
        // can be accepted the moment it connects.
        for (let i = 0; i < deviceModel.count; ++i) {
            const row = deviceModel.get(i)
            registerSigningKey(row.serial, row.name)
        }
    }

    QGCFlickable {
        anchors.margins:  _margins
        anchors.fill:     parent
        contentWidth:     content.width
        contentHeight:    content.height
        clip:             true

        ColumnLayout {
            id:      content
            width:   root.width - (_margins * 2)
            spacing: _margins

            QGCLabel {
                text:            qsTr("STRATUM Devices")
                font.pointSize:  ScreenTools.largeFontPointSize * 1.3
                font.bold:       true
            }

            QGCLabel {
                Layout.fillWidth: true
                wrapMode:         Text.WordWrap
                text: qsTr("Register each aircraft by its device serial number and a name. STRATUM decrypts the " +
                           "serial with the Device Info Key below to recover the 6-digit handshake (stored as " +
                           "NX + digits), the camera IP, and the data-link. The handshake is registered as the " +
                           "aircraft's signing key so its connection is accepted. Press \"Apply\" to also provision " +
                           "the camera (IP + TV/IR video streams).")
            }

            // ---- Device Info Key ----------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth

                QGCLabel {
                    text:                  qsTr("Device Info Key (hex)")
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 22
                }
                FactTextField {
                    Layout.fillWidth: true
                    fact:             _vs.daggerDeviceKey
                    placeholderText:  qsTr("32 hex characters (AES-128 key)")
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: qgcPal.groupBorder }

            // ---- Column headers -----------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth
                QGCLabel { text: qsTr("Serial Number");  Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 24; font.bold: true }
                QGCLabel { text: qsTr("Vehicle Name");   Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 18; font.bold: true }
                QGCLabel { text: qsTr("Decoded");        Layout.fillWidth: true; font.bold: true }
                Item     { Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 18 }
            }

            // ---- Device rows --------------------------------------------
            Repeater {
                model: deviceModel
                delegate: RowLayout {
                    required property int    index
                    required property string serial
                    required property string name

                    Layout.fillWidth: true
                    spacing:          ScreenTools.defaultFontPixelWidth

                    QGCTextField {
                        id:                    serialField
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 24
                        text:                  serial
                        placeholderText:       qsTr("e.g. 203365ABDE4900FC")
                        onEditingFinished: {
                            deviceModel.setProperty(index, "serial", text)
                            root.saveRegistry()
                            root.registerSigningKey(text, name)
                        }
                    }
                    QGCTextField {
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 18
                        text:                  name
                        placeholderText:       qsTr("e.g. Dagger 01")
                        onEditingFinished: {
                            deviceModel.setProperty(index, "name", text)
                            root.saveRegistry()
                            root.registerSigningKey(serialField.text, text)
                        }
                    }
                    QGCLabel {
                        Layout.fillWidth: true
                        elide:            Text.ElideRight
                        text:             root.previewText(serialField.text)
                        color:            root.previewColor(serialField.text)
                    }
                    QGCButton {
                        text:    qsTr("Apply")
                        enabled: root._vm.decodeDeviceSerial(serialField.text).valid
                        onClicked: {
                            root.registerSigningKey(serialField.text, name)
                            if (root._vm.applyDeviceSerial(serialField.text)) {
                                applyStatus.text  = qsTr("Provisioned %1 and registered its handshake key").arg(name.length ? name : serialField.text)
                                applyStatus.color = qgcPal.colorGreen
                            } else {
                                applyStatus.text  = qsTr("Could not provision %1").arg(serialField.text)
                                applyStatus.color = qgcPal.colorOrange
                            }
                        }
                    }
                    QGCButton {
                        text: qsTr("Remove")
                        onClicked: {
                            deviceModel.remove(index)
                            root.saveRegistry()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth
                QGCButton {
                    text: qsTr("Add Device")
                    onClicked: {
                        deviceModel.append({ serial: "", name: "" })
                        root.saveRegistry()
                    }
                }
                QGCLabel {
                    id:               applyStatus
                    Layout.fillWidth: true
                    wrapMode:         Text.WordWrap
                }
            }
        }
    }
}
