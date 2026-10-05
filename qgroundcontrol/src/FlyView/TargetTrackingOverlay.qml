import QtQuick

import QGroundControl

// STRATUM: operator-in-the-loop visual target designation overlay.
//
// Draws on top of the live video. A click drops a fixed selection box
// (on the 1280x720 protocol frame) centred on the click point. That normalized
// box is sent to two downstream trackers so operators can use whichever is
// available on the airframe:
//   * Companion (OpenCV) tracker via Vehicle::sendTargetSelect
//     (NEXAM_TARGET_SELECT / 42003). Streams NEXAM_TARGET_TRACK (42004) back,
//     which lands as vehicle.targetTrack.* and is drawn as the red tracked box.
//   * C12 on-camera AI tracker via VideoManager.sendC12TrackRegion (Skydroid AI
//     V1.2.0 binary on UDP :1030). Only fired when the operator has actually
//     selected the C12 (daggerCamera == 1) so we never spam UDP at a fixed IP
//     the operator hasn't opted into.
//
// Ctrl+drag on the video emits a custom region while plain drag remains reserved
// for gimbal pan/tilt (see FlyViewVideo.qml).
Item {
    id: rootItem

    required property var  vehicle       // active Vehicle (may be null)
    required property real videoWidth
    required property real videoHeight

    readonly property var _adminSettings: QGroundControl.settingsManager.adminSettings
    readonly property int _fixedBoxPx: {
        if (!_adminSettings) return 200
        var raw = Number(_adminSettings.trackerBoxSizePx.rawValue)
        if (!isFinite(raw)) return 200
        return Math.max(32, Math.min(640, Math.round(raw)))
    }

    readonly property bool _enabled: !!vehicle && videoWidth > 0 && videoHeight > 0

    // STRATUM: gate the C12-AI dispatch on the operator having explicitly picked
    // the C12 as the active camera so we don't send stray UDP at :1030 when the
    // airframe is flying an A2 mini or a standard MAVLink camera.
    readonly property var _videoSettings: QGroundControl.settingsManager.videoSettings
    readonly property bool _c12Active: _videoSettings && _videoSettings.daggerCamera.rawValue === 1
    // C12 AI SET_REGION carries a "video source" byte (0=visible/TV, 1=IR/thermal).
    // Derive it from whichever stored URL the live rtspUrl currently matches so the
    // tracker latches onto the feed the operator is actually looking at.
    readonly property int _c12VideoSource: {
        if (!_videoSettings) return 0
        var live = _videoSettings.rtspUrl.rawValue
        var ir = _videoSettings.daggerC12IrRtspUrl.rawValue
        return (ir !== "" && live === ir) ? 1 : 0
    }

    readonly property real _marginH: (rootItem.width - videoWidth) / 2
    readonly property real _marginV: (rootItem.height - videoHeight) / 2

    property bool _dragSelecting: false
    property real _dragStartX: 0
    property real _dragStartY: 0
    property real _dragNowX: 0
    property real _dragNowY: 0

    // --- Tracked target feed (from the companion via NEXAM_TARGET_TRACK) ---
    // status: 0=IDLE, 1=TRACKING, 2=LOST
    readonly property var  _track: vehicle ? vehicle.targetTrack : null
    readonly property bool _trackingActive: _enabled && _track && _track.status.value === 1

    // --- helpers -------------------------------------------------------------
    // View coordinate -> normalized video coordinate (0..1), clamped, letterbox-aware.
    function _normX(px) { return Math.max(0.0, Math.min(1.0, (px - _marginH) / videoWidth)) }
    function _normY(py) { return Math.max(0.0, Math.min(1.0, (py - _marginV) / videoHeight)) }

    function _sendSelection(x0, y0, x1, y1) {
        if (!_enabled) {
            return
        }
        vehicle.sendTargetSelect(x0, y0, x1, y1, 1)
        if (_c12Active) {
            QGroundControl.videoManager.sendC12TrackRegion(x0, y0, x1, y1, _c12VideoSource)
        }
    }

    function mouseClicked(mouseX, mouseY) {
        if (!_enabled) {
            return
        }
        // Fixed 200x200 protocol-frame box centred on the click.
        var cx = _normX(mouseX)
        var cy = _normY(mouseY)
        var hw = (_fixedBoxPx / 2) / 1280.0
        var hh = (_fixedBoxPx / 2) /  720.0
        var x0 = Math.max(0.0, cx - hw)
        var y0 = Math.max(0.0, cy - hh)
        var x1 = Math.min(1.0, cx + hw)
        var y1 = Math.min(1.0, cy + hh)
        _sendSelection(x0, y0, x1, y1)
    }

    function mouseDragStart(mouseX, mouseY) {
        if (!_enabled) {
            return
        }
        _dragSelecting = true
        _dragStartX = mouseX
        _dragStartY = mouseY
        _dragNowX = mouseX
        _dragNowY = mouseY
    }

    function mouseDragPositionChanged(mouseX, mouseY) {
        if (!_dragSelecting) {
            return
        }
        _dragNowX = mouseX
        _dragNowY = mouseY
    }

    function mouseDragEnd(mouseX, mouseY) {
        if (!_dragSelecting) {
            return
        }
        _dragNowX = mouseX
        _dragNowY = mouseY
        _dragSelecting = false

        var x0 = _normX(Math.min(_dragStartX, _dragNowX))
        var y0 = _normY(Math.min(_dragStartY, _dragNowY))
        var x1 = _normX(Math.max(_dragStartX, _dragNowX))
        var y1 = _normY(Math.max(_dragStartY, _dragNowY))

        if ((x1 - x0) < 0.003 || (y1 - y0) < 0.003) {
            mouseClicked(mouseX, mouseY)
            return
        }
        _sendSelection(x0, y0, x1, y1)
    }

    Rectangle {
        visible: rootItem._dragSelecting
        color: Qt.rgba(1, 1, 1, 0.08)
        border.color: "white"
        border.width: 2
        radius: 2
        x: Math.min(rootItem._dragStartX, rootItem._dragNowX)
        y: Math.min(rootItem._dragStartY, rootItem._dragNowY)
        width: Math.abs(rootItem._dragNowX - rootItem._dragStartX)
        height: Math.abs(rootItem._dragNowY - rootItem._dragStartY)
    }

    // --- tracked target overlay (red box streamed back from the companion) ---
    Rectangle {
        id: trackedBox
        color: "transparent"
        border.color: "red"
        border.width: 3
        radius: 3
        visible: rootItem._trackingActive

        x: rootItem._trackingActive ? rootItem._marginH + videoWidth  * rootItem._track.topLeftX.value : 0
        y: rootItem._trackingActive ? rootItem._marginV + videoHeight * rootItem._track.topLeftY.value : 0
        width:  rootItem._trackingActive ? videoWidth  * (rootItem._track.botRightX.value - rootItem._track.topLeftX.value) : 0
        height: rootItem._trackingActive ? videoHeight * (rootItem._track.botRightY.value - rootItem._track.topLeftY.value) : 0

        // Small corner label with the track id + confidence.
        Rectangle {
            visible: parent.visible
            color: Qt.rgba(0, 0, 0, 0.5)
            anchors.left: parent.left
            anchors.bottom: parent.top
            width: label.implicitWidth + 8
            height: label.implicitHeight + 4
            Text {
                id: label
                anchors.centerIn: parent
                color: "red"
                font.pixelSize: 12
                text: rootItem._trackingActive
                      ? ("T" + rootItem._track.targetId.value + "  " + Math.round(rootItem._track.confidence.value * 100) + "%")
                      : ""
            }
        }
    }
}
