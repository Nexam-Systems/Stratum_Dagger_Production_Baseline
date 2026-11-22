import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

/// STRATUM KAN-53: a QGCButton that must be HELD to confirm. The hold is the confirmation, so no
/// "are you sure" dialog is needed.
///     holdDuration > 0: held() fires once the button has been held for that many milliseconds.
///                       Releasing earlier sends nothing. A progress fill shows how far the hold is.
///     holdDuration = 0: held() fires on an ordinary click (the button behaves like a QGCButton).
QGCButton {
    id: control

    property int  holdDuration: 1000                    // ms, 0 = plain click
    readonly property real holdProgress: _startedMs > 0 && holdDuration > 0 ? Math.min(1, Math.max(0, (_clock.nowMs - _startedMs) / holdDuration)) : 0
    readonly property bool holding: _startedMs > 0

    signal held

    property double _startedMs: 0

    function cancelHold() {
        _startedMs = 0
    }

    onPressed: {
        if (enabled && visible && holdDuration > 0) {
            _clock.nowMs = Date.now()
            _startedMs = _clock.nowMs
        }
    }
    onReleased: cancelHold()
    onCanceled: cancelHold()
    onEnabledChanged: if (!enabled) cancelHold()
    onVisibleChanged: if (!visible) cancelHold()
    onClicked: if (holdDuration <= 0) held()

    Timer {
        id:         _clock
        property double nowMs: Date.now()
        interval:   20
        repeat:     true
        running:    control.holding
        onTriggered: {
            nowMs = Date.now()
            if (!control.down || !control.enabled || !control.visible) {
                control.cancelHold()
            } else if (nowMs - control._startedMs >= control.holdDuration) {
                control.cancelHold()
                control.held()
            }
        }
    }

    QGCPalette { id: _holdPalette; colorGroupEnabled: control.enabled }

    // Progress fill, drawn over the button face while it is being held.
    Rectangle {
        anchors.left:   parent.left
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        width:          parent.width * control.holdProgress
        visible:        control.holdProgress > 0
        radius:         control.backRadius
        color:          _holdPalette.buttonHighlight
        opacity:        0.65
    }
}
