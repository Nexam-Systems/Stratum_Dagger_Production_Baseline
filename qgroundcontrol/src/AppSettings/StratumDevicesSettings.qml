import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

// STRATUM Assets registry. Operators register each asset by its serial number (the
// 8-byte DIP V2 frame, hex) and a name. STRATUM decodes the serial (with the admin-set
// Device Info Key) to derive the camera IP + data-link; "Apply" provisions the camera
// and "Connect" links to the asset.
Rectangle {
    id:             root
    objectName:     "settingsPage_StratumDevices"
    color:          qgcPal.window
    anchors.fill:   parent

    readonly property real _margins: ScreenTools.defaultFontPixelHeight
    readonly property var  _vs:      QGroundControl.settingsManager.videoSettings
    readonly property var  _vm:      QGroundControl.videoManager
    readonly property bool _dev:     QGroundControl.corePlugin.stratumDevBuild

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
        // Force the write to disk now; settings Facts are otherwise flushed lazily,
        // so a removal could be lost if the app is closed/uninstalled immediately.
        _vm.syncSettings()
    }

    // Remove an asset row reliably. Runs in the page (root) context so the save still
    // executes after deviceModel.remove destroys the row's delegate.
    function removeDeviceAt(i) {
        if (i < 0 || i >= deviceModel.count) {
            return
        }
        const row = deviceModel.get(i)
        unregisterSigningKey(row.serial, row.name)
        deviceModel.remove(i)
        saveRegistry()
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
        // Remove any stale entry first so an edited serial/handshake replaces the old key.
        QGroundControl.mavlinkSigningKeys.removeKey(keyName)
        QGroundControl.mavlinkSigningKeys.addKey(keyName, "NX" + r.handshake)
        return true
    }

    // Drop a device's handshake signing key so a removed/renamed device can no longer connect.
    function unregisterSigningKey(serial, name) {
        const keyName = (name && name.length > 0) ? name : serial
        QGroundControl.mavlinkSigningKeys.removeKey(keyName)
    }

    // Create (or reuse) a UDP link to the device's decoded data-link endpoint and connect it,
    // after making sure the handshake signing key is registered.
    function connectDevice(serial, name) {
        const r = _vm.decodeDeviceSerial(serial)
        if (!r.valid) {
            return false
        }
        registerSigningKey(serial, name)

        const lm = QGroundControl.linkManager
        const linkName = qsTr("STRATUM %1").arg((name && name.length > 0) ? name : serial)
        for (let i = 0; i < lm.linkConfigurations.count; ++i) {
            const existing = lm.linkConfigurations.get(i)
            if (existing && existing.name === linkName) {
                lm.createConnectedLink(existing)
                return true
            }
        }
        const cfg = lm.createConfiguration(LinkConfiguration.TypeUdp, linkName)
        cfg.addHost(r.dataIp, r.port)
        lm.endCreateConfiguration(cfg)
        lm.createConnectedLink(cfg)
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
                text:            qsTr("STRATUM Assets")
                font.pointSize:  ScreenTools.largeFontPointSize * 1.3
                font.bold:       true
            }

            // Client build: short prompt only. Dev build: full registry explanation.
            QGCLabel {
                Layout.fillWidth: true
                wrapMode:         Text.WordWrap
                visible:          !root._dev
                text: qsTr("Enter the vehicle's serial key and a name to register it, then connect.")
            }

            QGCLabel {
                Layout.fillWidth: true
                wrapMode:         Text.WordWrap
                visible:          root._dev
                text: qsTr("Register each asset by its serial number and a name. STRATUM decodes the serial to " +
                           "recover the 6-digit handshake (stored as NX + digits) and registers it as the asset's " +
                           "signing key so its connection is accepted. Press \"Apply\" to provision the camera " +
                           "(IP + TV/IR video streams); press \"Connect\" to link to the asset. The decode key is " +
                           "set by an administrator.")
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: qgcPal.groupBorder }

            // ---- Column headers -----------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth
                QGCLabel { text: qsTr("Serial Number");  Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 24; font.bold: true }
                QGCLabel { text: qsTr("Vehicle Name");   Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 18; font.bold: true }
                QGCLabel { text: qsTr("Status");         Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16; font.bold: true }
                Item     { Layout.fillWidth: true }
                QGCLabel { text: qsTr("Actions");        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 28; font.bold: true }
            }

            // ---- Device rows --------------------------------------------
            Repeater {
                model: deviceModel
                delegate: RowLayout {
                    id:               assetRow
                    required property int    index
                    required property string serial
                    required property string name

                    Layout.fillWidth: true
                    spacing:          ScreenTools.defaultFontPixelWidth

                    // Live connection state: true when the asset's signing key is actively
                    // in use by a connected vehicle (keyUsageRevision makes it reactive).
                    readonly property string _keyName:   (name && name.length > 0) ? name : serial
                    readonly property bool   _connected: {
                        void(QGroundControl.mavlinkSigningKeys.keyUsageRevision)
                        return _keyName.length > 0 && QGroundControl.mavlinkSigningKeys.isKeyInUse(_keyName)
                    }

                    QGCTextField {
                        id:                    serialField
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 24
                        // Stored serials are clean hex; display them grouped in fours.
                        text:                  _format(_clean(serial))
                        placeholderText:       qsTr("e.g. 2033-65AB-DE49-00FC")
                        inputMethodHints:      Qt.ImhNoPredictiveText

                        property int _prevCleanLen: _clean(serial).length

                        // Keep only hex, upper-case, capped at the 16-char (8-byte) frame.
                        function _clean(raw) {
                            var c = raw.replace(/[^0-9a-fA-F]/g, "").toUpperCase()
                            return c.length > 16 ? c.substring(0, 16) : c
                        }
                        // Group into fours with dashes; add a trailing dash right after a
                        // completed group so "4B2C" becomes "4B2C-" (but never at full length).
                        function _format(clean) {
                            var groups = []
                            for (var i = 0; i < clean.length; i += 4) groups.push(clean.substring(i, i + 4))
                            var out = groups.join("-")
                            if (clean.length > 0 && clean.length < 16 && (clean.length % 4) === 0) out += "-"
                            return out
                        }

                        onTextEdited: {
                            var clean = _clean(text)
                            // Backspace over an auto-inserted trailing dash: hex content is
                            // unchanged but the field shrank -> drop the last hex digit so
                            // delete feels natural.
                            if (clean.length === _prevCleanLen && text.length < _format(clean).length) {
                                clean = clean.substring(0, Math.max(0, clean.length - 1))
                            }
                            var formatted = _format(clean)
                            _prevCleanLen = clean.length
                            if (text !== formatted) {
                                text = formatted
                                cursorPosition = formatted.length
                            }
                        }

                        onEditingFinished: {
                            var clean = _clean(text)
                            deviceModel.setProperty(index, "serial", clean)
                            root.saveRegistry()
                            root.registerSigningKey(clean, name)
                        }
                    }
                    QGCTextField {
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 18
                        text:                  name
                        placeholderText:       qsTr("e.g. Dagger 01")
                        onEditingFinished: {
                            root.unregisterSigningKey(serialField.text, name)
                            deviceModel.setProperty(index, "name", text)
                            root.saveRegistry()
                            root.registerSigningKey(serialField.text, text)
                        }
                    }
                    RowLayout {
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                        spacing:               ScreenTools.defaultFontPixelWidth / 2
                        Rectangle {
                            implicitWidth:    ScreenTools.defaultFontPixelHeight * 0.5
                            implicitHeight:   implicitWidth
                            radius:           implicitWidth / 2
                            color:            assetRow._connected ? qgcPal.colorGreen : (qgcPal.lightTheme ? qgcPal.colorGrey : "#808080")
                            Layout.alignment: Qt.AlignVCenter
                        }
                        QGCLabel {
                            text:  assetRow._connected ? qsTr("Connected") : qsTr("Offline")
                            color: assetRow._connected ? qgcPal.colorGreen : qgcPal.text
                        }
                    }
                    Item { Layout.fillWidth: true }
                    QGCButton {
                        text:    qsTr("Apply")
                        enabled: serialField.text.length > 0
                        onClicked: {
                            const r = root._vm.decodeDeviceSerial(serialField.text)
                            if (!r.valid) {
                                QGroundControl.showMessageDialog(root, qsTr("Apply Asset"),
                                    root._dev ? qsTr("Could not decode serial: %1").arg(r.error)
                                              : qsTr("Serial key invalid."))
                                return
                            }
                            root.registerSigningKey(serialField.text, name)
                            if (root._vm.applyDeviceSerial(serialField.text)) {
                                QGroundControl.showMessageDialog(root, qsTr("Apply Asset"),
                                    root._dev
                                        ? qsTr("Provisioned %1.\nCamera: %2\nData-link: %3:%4\nHandshake key NX%5 registered.")
                                            .arg(name.length ? name : serialField.text)
                                            .arg(r.cameraIp).arg(r.dataIp).arg(r.port).arg(r.handshake)
                                        : qsTr("Vehicle registered."))
                            } else {
                                QGroundControl.showMessageDialog(root, qsTr("Apply Asset"),
                                    root._dev ? qsTr("Could not provision %1.").arg(serialField.text)
                                              : qsTr("Could not register vehicle."))
                            }
                        }
                    }
                    QGCButton {
                        text:    qsTr("Connect")
                        enabled: serialField.text.length > 0
                        onClicked: {
                            const r = root._vm.decodeDeviceSerial(serialField.text)
                            if (!r.valid) {
                                QGroundControl.showMessageDialog(root, qsTr("Connect Asset"),
                                    root._dev ? qsTr("Could not decode serial: %1").arg(r.error)
                                              : qsTr("Serial key invalid."))
                                return
                            }
                            root.connectDevice(serialField.text, name)
                            QGroundControl.showMessageDialog(root, qsTr("Connect Asset"),
                                root._dev
                                    ? qsTr("Connecting to %1 at %2:%3 …")
                                        .arg(name.length ? name : serialField.text).arg(r.dataIp).arg(r.port)
                                    : qsTr("Connecting to %1 …").arg(name.length ? name : serialField.text))
                        }
                    }
                    QGCButton {
                        text: qsTr("Remove")
                        onClicked: root.removeDeviceAt(index)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing:          ScreenTools.defaultFontPixelWidth
                QGCButton {
                    text: qsTr("Add Asset")
                    onClicked: {
                        deviceModel.append({ serial: "", name: "" })
                        root.saveRegistry()
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
