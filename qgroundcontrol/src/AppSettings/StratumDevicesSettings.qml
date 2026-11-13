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

    // Reactive connect-status dialog: shows "Connecting to X …" until a vehicle actually
    // appears on the asset's link, then switches to "Connected to X." and auto-closes.
    QGCPopupDialogFactory {
        id: connectStatusDialogFactory
        dialogComponent: connectStatusDialogComponent
    }

    Component {
        id: connectStatusDialogComponent

        QGCPopupDialog {
            id:      connectStatusDialog
            title:   qsTr("Connect Asset")
            buttons: Dialog.Close

            // Set by connectStatusDialogFactory.open({...}).
            property string linkName:    ""
            property string displayName: ""
            property string detail:      ""   // dev-only extra, e.g. " at 192.168.20.5:14545"

            readonly property bool _connected: {
                void(QGroundControl.multiVehicleManager.vehicles.count)
                return linkName.length > 0 && root.vehicleOnLink(linkName) !== null
            }

            QGCLabel {
                text: connectStatusDialog._connected
                          ? qsTr("Connected to %1.").arg(connectStatusDialog.displayName)
                          : qsTr("Connecting to %1%2 …").arg(connectStatusDialog.displayName).arg(connectStatusDialog.detail)
            }

            // Once the vehicle is confirmed connected, close the dialog shortly after so the
            // operator sees the "Connected" confirmation without having to dismiss it.
            Timer {
                interval: 1200
                running:  connectStatusDialog._connected
                onTriggered: connectStatusDialog.close()
            }
        }
    }

    // STRATUM #84: Test Pairing dialog. Shows "Testing vehicle connectivity" while the backend
    // probes the vehicle then the camera, switches to "Vehicle ready to be connected" on
    // success (auto-closes after 1.5 s), or shows the failure reason. Dev build additionally
    // shows the IP currently being probed. Closing cancels the in-progress probe.
    QGCPopupDialogFactory {
        id: pairingDialogFactory
        dialogComponent: pairingDialogComponent
    }

    Component {
        id: pairingDialogComponent

        QGCPopupDialog {
            id:      pairingDialog
            title:   qsTr("Test Pairing")
            buttons: Dialog.Close

            property string statusText: qsTr("Testing vehicle connectivity …")
            property bool   done:       false

            onClosed: QGroundControl.videoManager.cancelPairingTest()

            ColumnLayout {
                spacing: ScreenTools.defaultFontPixelHeight / 2

                QGCLabel {
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 44
                    wrapMode:              Text.WordWrap
                    text:                  pairingDialog.statusText
                }

                Connections {
                    target: QGroundControl.videoManager

                    function onPairingTestStage(stage, endpoint) {
                        if (pairingDialog.done) {
                            return
                        }
                        pairingDialog.statusText = root._dev
                            ? qsTr("Testing vehicle connectivity … pinging %1 (%2)").arg(stage).arg(endpoint)
                            : qsTr("Testing vehicle connectivity …")
                    }
                    function onPairingTestSucceeded() {
                        pairingDialog.done = true
                        pairingDialog.statusText = qsTr("Vehicle ready to be connected")
                        pairingAutoClose.start()
                    }
                    function onPairingTestFailed(reason) {
                        pairingDialog.done = true
                        pairingDialog.statusText = root._dev ? reason : qsTr("Vehicle not reachable.")
                    }
                }

                Timer {
                    id:       pairingAutoClose
                    interval: 1500
                    onTriggered: pairingDialog.close()
                }
            }
        }
    }

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

    // Display name of the auto-created link for an asset (matches what connectDevice creates).
    function assetLinkName(serial, name) {
        return qsTr("STRATUM %1").arg((name && name.length > 0) ? name : serial)
    }

    // Find the LinkConfiguration created for this asset, or null if none exists yet.
    function assetLinkConfig(serial, name) {
        const lm = QGroundControl.linkManager
        const linkName = assetLinkName(serial, name)
        for (let i = 0; i < lm.linkConfigurations.count; ++i) {
            const c = lm.linkConfigurations.get(i)
            if (c && c.name === linkName) {
                return c
            }
        }
        return null
    }

    // Return the connected Vehicle currently using the named link, or null. A Vehicle only
    // exists once a heartbeat has been received, so this confirms the vehicle actually
    // connected (not merely that the UDP link/socket was created).
    function vehicleOnLink(linkName) {
        const mvm = QGroundControl.multiVehicleManager
        for (let i = 0; i < mvm.vehicles.count; ++i) {
            const v = mvm.vehicles.get(i)
            if (!v || !v.vehicleLinkManager) {
                continue
            }
            if (v.vehicleLinkManager.linkNames.indexOf(linkName) !== -1
                    && !v.vehicleLinkManager.communicationLost) {
                return v
            }
        }
        return null
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
        const linkName = assetLinkName(serial, name)
        // Single-vehicle policy: drop any other connected vehicle before connecting this one.
        disconnectOtherConnections(linkName)
        for (let i = 0; i < lm.linkConfigurations.count; ++i) {
            const existing = lm.linkConfigurations.get(i)
            if (existing && existing.name === linkName) {
                // Self-heal older entries saved without a local port (UDP configs only).
                if (r.port && existing.localPort !== undefined && existing.localPort === 0) {
                    existing.localPort = r.port
                }
                lm.createConnectedLink(existing)
                return true
            }
        }
        const cfg = lm.createConfiguration(LinkConfiguration.TypeUdp, linkName)
        // Bind QGC to the decoded data-link port as well as targeting the vehicle there;
        // without a local port the UDP socket can't establish the connection.
        cfg.localPort = r.port
        cfg.addHost(r.dataIp, r.port)
        lm.endCreateConfiguration(cfg)
        lm.createConnectedLink(cfg)
        return true
    }

    // Disconnect the asset's link if it is currently connected.
    function disconnectDevice(serial, name) {
        const cfg = assetLinkConfig(serial, name)
        if (cfg) {
            QGroundControl.linkManager.disconnectLinkConfiguration(cfg)
            return true
        }
        return false
    }

    // Enforce a single connected vehicle: disconnect every currently-active link except the
    // one we are about to connect (keepLinkName). Called from connectDevice so that connecting
    // a new asset automatically drops any other connected vehicle.
    function disconnectOtherConnections(keepLinkName) {
        const lm = QGroundControl.linkManager
        for (let i = 0; i < lm.linkConfigurations.count; ++i) {
            const c = lm.linkConfigurations.get(i)
            if (c && c.name !== keepLinkName && c.linkActive) {
                lm.disconnectLinkConfiguration(c)
            }
        }
    }

    ListModel { id: deviceModel }

    Component.onCompleted: {
        loadRegistry()
        // Make every registered device's handshake key available up front so any of them
        // can be accepted the moment it connects. Skip keys that are already present: signing
        // keys persist in MAVLinkSigningKeys across tab opens (loaded at startup), and
        // re-registering runs an expensive PBKDF2 derivation (~250 ms each) per asset, which
        // made the Assets tab take several seconds to open every time. Only newly-added assets
        // pay the one-time derivation cost.
        for (let i = 0; i < deviceModel.count; ++i) {
            const row = deviceModel.get(i)
            const keyName = (row.name && row.name.length > 0) ? row.name : row.serial
            if (keyName.length > 0 && QGroundControl.mavlinkSigningKeys.keyHexByName(keyName) !== "") {
                continue
            }
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

                    // Live connection state: true only when a Vehicle is actually connected on
                    // this asset's link (a Vehicle exists only after a heartbeat), not merely
                    // when the UDP socket was created. _linkCfg is still used for Disconnect.
                    readonly property string _linkName: root.assetLinkName(serialField.text, name)
                    readonly property var    _linkCfg: {
                        void(QGroundControl.linkManager.linkConfigurations.count)
                        return root.assetLinkConfig(serialField.text, name)
                    }
                    readonly property bool   _connected: {
                        void(QGroundControl.multiVehicleManager.vehicles.count)
                        return root.vehicleOnLink(_linkName) !== null
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
                        text:    qsTr("Test Pairing")
                        enabled: serialField.text.length > 0
                        onClicked: {
                            const r = root._vm.decodeDeviceSerial(serialField.text)
                            if (!r.valid) {
                                QGroundControl.showMessageDialog(root, qsTr("Test Pairing"),
                                    root._dev ? qsTr("Could not decode serial: %1").arg(r.error)
                                              : qsTr("Serial key invalid."))
                                return
                            }
                            pairingDialogFactory.open()
                            // Ping the vehicle IP, then the camera IP (host reachability, no port).
                            root._vm.startPairingTest(r.dataIp, r.cameraIp)
                        }
                    }
                    QGCButton {
                        text:    qsTr("Connect")
                        visible: !assetRow._connected
                        enabled: serialField.text.length > 0
                        onClicked: {
                            const r = root._vm.decodeDeviceSerial(serialField.text)
                            if (!r.valid) {
                                QGroundControl.showMessageDialog(root, qsTr("Connect Asset"),
                                    root._dev ? qsTr("Could not decode serial: %1").arg(r.error)
                                              : qsTr("Serial key invalid."))
                                return
                            }
                            const displayName = name.length ? name : serialField.text
                            root.connectDevice(serialField.text, name)
                            // Reactive dialog: shows "Connecting …" until the vehicle actually
                            // appears on the link, then "Connected to X." and auto-closes.
                            connectStatusDialogFactory.open({
                                linkName:    assetRow._linkName,
                                displayName: displayName,
                                detail:      root._dev ? qsTr(" at %1:%2").arg(r.dataIp).arg(r.port) : ""
                            })
                        }
                    }
                    QGCButton {
                        text:    qsTr("Disconnect")
                        visible: assetRow._connected
                        onClicked: root.disconnectDevice(serialField.text, name)
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
