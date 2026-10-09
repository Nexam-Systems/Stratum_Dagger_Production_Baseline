import QtQuick

import QGroundControl
import QGroundControl.Controls

Item {
    id: _root

    property Item pipView
    property Item pipState: videoPipState

    PipState {
        id:         videoPipState
        pipView:    _root.pipView
        isDark:     true

        onWindowAboutToOpen: {
            QGroundControl.videoManager.stopVideo()
            videoStartDelay.start()
        }

        onWindowAboutToClose: {
            QGroundControl.videoManager.stopVideo()
            videoStartDelay.start()
        }

        onStateChanged: {
            if (pipState.state !== pipState.fullState) {
                QGroundControl.videoManager.fullScreen = false
            }
        }
    }

    Timer {
        id:           videoStartDelay
        interval:     2000;
        running:      false
        repeat:       false
        onTriggered:  QGroundControl.videoManager.startVideo()
    }

    //-- Video Streaming
    FlightDisplayViewVideo {
        id:             videoStreaming
        anchors.fill:   parent
        useSmallFont:   _root.pipState.state !== _root.pipState.fullState
        visible:        QGroundControl.videoManager.isStreamSource || QGroundControl.videoManager.isUvc
    }

    QGCLabel {
        text: qsTr("Double-click to exit full screen")
        font.pointSize: ScreenTools.largeFontPointSize
        visible: QGroundControl.videoManager.fullScreen
        anchors.centerIn: parent

        onVisibleChanged: {
            if (visible) {
                labelAnimation.start()
            }
        }

        PropertyAnimation on opacity {
            id: labelAnimation
            duration: 10000
            from: 1.0
            to: 0.0
            easing.type: Easing.InExpo
        }
    }

    OnScreenGimbalController {
        id:                      onScreenGimbalController
        anchors.fill:            parent
        cameraTrackingEnabled:   !!(videoStreaming._camera && videoStreaming._camera.trackingEnabled)
    }

    OnScreenCameraTrackingController {
        id:                      cameraTrackingController
        anchors.fill:            parent
        camera:                  videoStreaming._camera
        videoWidth:              videoStreaming.getWidth()
        videoHeight:             videoStreaming.getHeight()
    }

    //-- STRATUM: operator visual target designation. Sends NEXAM_TARGET_SELECT on
    //   click/drag and renders the tracked box streamed back by the companion. Works
    //   without a MAVLink camera (the tracker lives on the companion computer).
    //   Left unconditional (matches Dagger_main): NEXAM_TARGET_SELECT is a custom
    //   message id, so non-Dagger autopilots silently ignore it.
    TargetTrackingOverlay {
        id:                      targetTrackingOverlay
        anchors.fill:            parent
        vehicle:                 QGroundControl.multiVehicleManager.activeVehicle
        videoWidth:              videoStreaming.getWidth()
        videoHeight:             videoStreaming.getHeight()
    }

    //-- STRATUM: tracker ROI-scoping overlay. Draws the outer ROI box the companion
    //   tracker searches within and exposes a single diagonal-fraction control that
    //   calls Vehicle::setTrackerRoi (NEXAM_TRACKER_CONFIG / 42005).
    TrackerRoiOverlay {
        id:                      trackerRoiOverlay
        anchors.fill:            parent
        // STRATUM: sit above flyViewVideoMouseArea (below) so the +/- ROI buttons receive
        // clicks; the overlay's transparent areas still pass mouse events through to the
        // designation MouseArea (a plain Item does not grab events).
        z:                       20
        vehicle:                 QGroundControl.multiVehicleManager.activeVehicle
        videoWidth:              videoStreaming.getWidth()
        videoHeight:             videoStreaming.getHeight()
    }

    MouseArea {
        id:                         flyViewVideoMouseArea
        anchors.fill:               parent
        enabled:                    pipState.state === pipState.fullState
        acceptedButtons:            Qt.LeftButton | Qt.RightButton

        property real _pressX:      0
        property real _pressY:      0
        property bool _dragging:    false
        property bool _ctrlTrackDrag: false
        readonly property real _dragThreshold: 10

        // STRATUM: current C12 pan/tilt speed derived from the live drag delta.
        // The Timer flushes these to the gimbal at 10 Hz so a UDP command is not
        // emitted on every mouse motion frame. Range -100..+100, protocol accepts
        // -127..+127 (0.5°/s per unit), so 100 caps at ~50°/s.
        property int _c12YawSpeed:   0
        property int _c12PitchSpeed: 0
        readonly property var  _vs:        QGroundControl.settingsManager.videoSettings
        readonly property var  _admin:     QGroundControl.settingsManager.adminSettings
        readonly property bool _c12Active: _vs && _vs.daggerCamera.rawValue === 1
        readonly property int _c12MaxSpeed: {
            if (!_admin) return 100
            var raw = Number(_admin.c12GimbalMaxSpeed.rawValue)
            if (!isFinite(raw)) return 100
            return Math.max(1, Math.min(127, Math.round(raw)))
        }

        Timer {
            id:       c12GimbalDragTimer
            interval: 100
            repeat:   true
            onTriggered: {
                if (flyViewVideoMouseArea._c12Active) {
                    QGroundControl.videoManager.sendC12GimbalCombinedRate(
                        flyViewVideoMouseArea._c12YawSpeed,
                        flyViewVideoMouseArea._c12PitchSpeed)
                }
            }
        }

        function _updateC12DragSpeed(mouseX, mouseY) {
            var w = videoStreaming.getWidth()
            var h = videoStreaming.getHeight()
            if (w <= 0 || h <= 0) return
            var dx = mouseX - _pressX
            var dy = mouseY - _pressY
            var fullScale = _c12MaxSpeed * 2
            _c12YawSpeed   = Math.max(-_c12MaxSpeed, Math.min(_c12MaxSpeed, Math.round(dx / w * fullScale)))
            _c12PitchSpeed = Math.max(-_c12MaxSpeed, Math.min(_c12MaxSpeed, Math.round(-dy / h * fullScale)))
        }

        onDoubleClicked: QGroundControl.videoManager.fullScreen = !QGroundControl.videoManager.fullScreen

        onPressed: (mouse) => {
            _pressX = mouse.x
            _pressY = mouse.y
            _dragging = false
            _ctrlTrackDrag = (mouse.modifiers & Qt.ControlModifier) !== 0
        }

        onPositionChanged: (mouse) => {
            if (!_dragging && (Math.abs(mouse.x - _pressX) >= _dragThreshold || Math.abs(mouse.y - _pressY) >= _dragThreshold)) {
                _dragging = true
                if (_ctrlTrackDrag) {
                    targetTrackingOverlay.mouseDragStart(_pressX, _pressY)
                } else {
                    onScreenGimbalController.mouseDragStart(_pressX, _pressY)
                    cameraTrackingController.mouseDragStart(_pressX, _pressY)
                    if (_c12Active) {
                        _c12YawSpeed = 0
                        _c12PitchSpeed = 0
                        c12GimbalDragTimer.start()
                    }
                }
            }
            if (_dragging) {
                if (_ctrlTrackDrag) {
                    targetTrackingOverlay.mouseDragPositionChanged(mouse.x, mouse.y)
                } else {
                    onScreenGimbalController.mouseDragPositionChanged(mouse.x, mouse.y)
                    cameraTrackingController.mouseDragPositionChanged(mouse.x, mouse.y)
                    if (_c12Active) {
                        _updateC12DragSpeed(mouse.x, mouse.y)
                    }
                }
            }
        }

        onReleased: (mouse) => {
            if (_dragging) {
                if (_ctrlTrackDrag) {
                    targetTrackingOverlay.mouseDragEnd(mouse.x, mouse.y)
                } else {
                    onScreenGimbalController.mouseDragEnd()
                    cameraTrackingController.mouseDragEnd(mouse.x, mouse.y)
                    if (_c12Active) {
                        c12GimbalDragTimer.stop()
                        QGroundControl.videoManager.sendC12GimbalCombinedRate(0, 0)
                        _c12YawSpeed = 0
                        _c12PitchSpeed = 0
                    }
                }
            } else {
                onScreenGimbalController.mouseClicked(mouse.x, mouse.y)
                cameraTrackingController.mouseClicked(mouse.x, mouse.y)
                targetTrackingOverlay.mouseClicked(mouse.x, mouse.y)
            }
            _dragging = false
            _ctrlTrackDrag = false
        }

        // STRATUM: scroll-wheel zoom for the C12. Each wheel notch fires a single
        // DZM zoom+ / zoom- command. Non-C12 cameras ignore the packet because
        // sendCameraAction only speaks the Skydroid TOP protocol.
        WheelHandler {
            acceptedDevices:    PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y > 0) {
                    QGroundControl.videoManager.sendCameraAction("zoom-in")
                } else if (event.angleDelta.y < 0) {
                    QGroundControl.videoManager.sendCameraAction("zoom-out")
                }
            }
        }
    }

    ProximityRadarVideoView{
        anchors.fill:   parent
        vehicle:        QGroundControl.multiVehicleManager.activeVehicle
    }

    ObstacleDistanceOverlayVideo {
        id: obstacleDistance
        showText: pipState.state === pipState.fullState
    }

    //-- STRATUM flight-parameter OSD. Drawn on top of the video only.
    //   enabled:false inside the control lets gimbal/tracking input pass through.
    FlyViewVideoOSD {
        id:         flightParamOSD
        anchors.fill: parent
        compact:    _root.pipState.state !== _root.pipState.fullState
        visible:    videoStreaming.visible
    }
}
