import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM Dagger camera / gimbal control cluster (SIYI A2 mini).
// The A2 mini is a single-axis (tilt only) FPV gimbal so this exposes only what the
// hardware supports: pitch up/down (hold-to-repeat), center, capture, record toggle,
// and a motion-mode cycle. All commands are sent as SIYI SDK v3 UDP packets by
// VideoManager::sendSiyiCameraAction(), whose destination host/port are configured
// in Application Settings > Video (daggerCameraSdkHost / daggerCameraSdkPort).
Item {
    id: root

    property bool overlayMode: false
    property bool compact: false
    function stopMotion() { root._sendStop() }
    onVisibleChanged: if (!visible) stopMotion()
    Component.onDestruction: stopMotion()

    signal statusMessage(string text)

    property bool _recActive: false

    readonly property color _accent:    "#3DFFA6"
    readonly property color _accentDim: "#1FB97D"
    readonly property real  _btnHeight: ScreenTools.defaultFontPixelHeight * (compact ? 1.9 : 2.3)
    readonly property real  _spacing:   ScreenTools.defaultFontPixelWidth * 0.4
    readonly property real  _pad:       overlayMode ? ScreenTools.defaultFontPixelWidth * 0.75 : 0

    implicitWidth:  contentColumn.implicitWidth + (_pad * 2)
    implicitHeight: contentColumn.implicitHeight + (_pad * 2)

    function _send(cameraAction) {
        const sent = QGroundControl.videoManager.sendSiyiCameraAction(cameraAction)
        if (!sent) {
            root.statusMessage(qsTr("Camera command failed"))
        }
        return sent
    }

    function _toggleRec() {
        _recActive = !_recActive
        if (_send("rec-toggle")) {
            root.statusMessage(_recActive ? qsTr("● Recording started") : qsTr("■ Recording stopped"))
        } else {
            _recActive = !_recActive // roll back on failure
        }
    }

    // Sends stop repeatedly to defend against dropped UDP packets — the SIYI rate
    // command latches; if all stops are lost the gimbal keeps slewing. The C++ side
    // fires 5 back-to-back UDP writes per "stop" call.
    function _sendStop() {
        _send("stop")
    }

    // Fires a burst of stops on release. Runs for ~250 ms after the button is released
    // so a single lost packet at release time cannot leave the gimbal latched.
    Timer {
        id: safetyStopTimer
        interval: 50
        repeat: true
        property int _ticks: 0
        onTriggered: {
            root._send("stop")
            if (++_ticks >= 5) { stop(); _ticks = 0 }
        }
        function kick() { _ticks = 0; restart() }
    }

    // Reliable hold-to-move pitch button. Uses MouseArea + a Timer that is bound to
    // mouseArea.pressed so it stops the instant the user releases (or the mouse leaves,
    // or the app loses focus). On release the safety-stop timer sprays extra stops to
    // survive UDP loss. Sending a stop BEFORE the direction defeats any latched rate
    // in the opposite direction that may not have been cleared yet.
    component PtzButton : Rectangle {
        id: ptzButton
        property string ptzAction
        property string label
        implicitHeight: root._btnHeight
        Layout.fillWidth: true
        color: mouseArea.pressed ? root._accentDim
                                 : (mouseArea.containsMouse ? Qt.rgba(0.24, 1.0, 0.65, 0.18)
                                                            : Qt.rgba(1, 1, 1, 0.08))
        radius: ScreenTools.defaultBorderRadius
        border.color: root._accent
        border.width: 1
        QGCLabel {
            anchors.centerIn: parent
            text: ptzButton.label
            color: "white"
            font.bold: true
        }
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onPressed: {
                safetyStopTimer.stop()
                root._send("stop")                              // clear any latched rate
                if (root._send(ptzButton.ptzAction)) {
                    root.statusMessage(qsTr("→ %1").arg(ptzButton.ptzAction))
                }
            }
            onReleased:  safetyStopTimer.kick()
            onCanceled:  safetyStopTimer.kick()
        }
        Timer {
            interval: 120
            repeat: true
            running: mouseArea.pressed && root.visible && root.enabled
            onTriggered: root._send(ptzButton.ptzAction)
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.overlayMode
        color: Qt.rgba(0, 0, 0, 0.72)
        radius: ScreenTools.defaultBorderRadius
        border.color: root._accent
        border.width: 1
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: root._pad
        spacing: root._spacing

        // Label
        QGCLabel {
            text: qsTr("A2 MINI")
            color: root._accentDim
            font.pointSize: ScreenTools.smallFontPointSize
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
        }

        // ---- Pitch (single-axis) --------------------------------------
        PtzButton { label: qsTr("▲  Pitch Up");   ptzAction: "pitch-up" }
        QGCButton {
            text: qsTr("⊙  Center")
            implicitHeight: root._btnHeight
            Layout.fillWidth: true
            onClicked: {
                // Cancel any latched rate before centering, then command return-to-home,
                // then run the safety-stop burst so a stray rate cannot resume after.
                root._send("stop")
                if (root._send("center")) root.statusMessage(qsTr("Gimbal centred"))
                safetyStopTimer.kick()
            }
        }
        PtzButton { label: qsTr("▼  Pitch Down"); ptzAction: "pitch-down" }

        Item { Layout.preferredHeight: root._spacing }

        // ---- Media: Capture / Record --------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            QGCButton {
                text: qsTr("📷 Capture")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                onClicked: { if (root._send("capture")) root.statusMessage(qsTr("📷 Photo captured")) }
            }
            QGCButton {
                text: root._recActive ? qsTr("■ Stop") : qsTr("● Rec")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                primary: root._recActive
                onClicked: root._toggleRec()
            }
        }

        // ---- Motion mode (Lock / Follow / FPV) ----------------------
        // Lock: hold earth-frame attitude (default here — prevents drift with no
        // vehicle attitude source). Follow: track drone yaw. FPV: mirror drone roll/pitch.
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            QGCButton {
                text: qsTr("Lock")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                onClicked: { if (root._send("mode-lock"))   root.statusMessage(qsTr("Gimbal → Lock")) }
            }
            QGCButton {
                text: qsTr("Follow")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                onClicked: { if (root._send("mode-follow")) root.statusMessage(qsTr("Gimbal → Follow")) }
            }
            QGCButton {
                text: qsTr("FPV")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                onClicked: { if (root._send("mode-fpv"))    root.statusMessage(qsTr("Gimbal → FPV")) }
            }
        }
    }

    // STRATUM: at panel load, force the A2 mini into Lock mode + centre. Without an
    // explicit mode the gimbal defaults to Follow, which drifts when no vehicle
    // attitude is streaming.
    Component.onCompleted: {
        _send("stop")
        _send("mode-lock")
        _send("center")
    }
}
