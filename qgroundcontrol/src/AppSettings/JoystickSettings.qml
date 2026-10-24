import QtQuick

import QGroundControl
import QGroundControl.Controls

// STRATUM KAN-21: joystick calibration relocated here from the NX-logo popup's
// "Configure Joystick" entry so it sits alongside the other Settings pages (General,
// Comm Links, Maps, ...). Hosts the standard Vehicle Setup joystick component via a
// Loader URL so this settings module needs no compile-time dependency on VehicleSetup.
// Available in both the client and developer builds.
Rectangle {
    id:           root
    objectName:   "settingsPage_Joystick"
    color:        qgcPal.window
    anchors.fill: parent

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle

    Loader {
        anchors.fill:    parent
        anchors.margins: ScreenTools.defaultFontPixelHeight / 2
        active:          !!root._activeVehicle
        source:          "qrc:/qml/QGroundControl/VehicleSetup/JoystickComponent.qml"
    }

    QGCLabel {
        anchors.centerIn:    parent
        visible:             !root._activeVehicle
        width:               parent.width * 0.8
        horizontalAlignment: Text.AlignHCenter
        wrapMode:            Text.WordWrap
        text:                qsTr("Connect a vehicle to calibrate and configure the joystick.")
    }
}
