import QtQuick
import QtQuick.Controls

Button {
    id: control

    property bool _completed: false
    property var _pressedVehicle: null
    property double _startedMs: 0
    property bool applicationActive: Qt.application.state === Qt.ApplicationActive
    property string command: ""
    property bool contextActive: true
    property int holdDuration: 1000
    readonly property real holdProgress: _startedMs > 0 ? Math.min(1, Math.max(0, (clock.nowMs - _startedMs) / holdDuration)) : 0
    readonly property bool holding: _startedMs > 0
    property var vehicleIdentity: null

    signal committed

    function cancelHold() {
        _startedMs = 0;
        _pressedVehicle = null;
    }

    Accessible.name: command
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    onApplicationActiveChanged: if (!applicationActive)
        cancelHold()
    onCanceled: cancelHold()
    onContextActiveChanged: if (!contextActive)
        cancelHold()
    onEnabledChanged: if (!enabled)
        cancelHold()
    onHoveredChanged: if (pressed && !hovered)
        cancelHold()
    onPressed: {
        cancelHold();
        _completed = false;
        if (enabled && visible && contextActive && applicationActive && vehicleIdentity) {
            _pressedVehicle = vehicleIdentity;
            _startedMs = Date.now();
            clock.nowMs = _startedMs;
        }
    }
    onReleased: cancelHold()
    onVehicleIdentityChanged: cancelHold()
    onVisibleChanged: if (!visible)
        cancelHold()

    Timer {
        id: clock

        property double nowMs: Date.now()

        interval: 20
        repeat: true
        running: control.holding

        onTriggered: {
            nowMs = Date.now();
            if (!control.down || !control.enabled || !control.visible || !control.contextActive || !control.applicationActive || control._pressedVehicle !== control.vehicleIdentity) {
                control.cancelHold();
                return;
            }
            if (!control._completed && nowMs - control._startedMs >= control.holdDuration) {
                control._completed = true;
                control.cancelHold();
                control.committed();
            }
        }
    }
}
