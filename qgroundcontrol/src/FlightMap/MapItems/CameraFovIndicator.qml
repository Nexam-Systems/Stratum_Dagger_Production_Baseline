import QtQuick

import QGroundControl
import QGroundControl.Controls

Canvas {
    id: root

    required property var vehicle
    required property var map
    required property real iconSize

    readonly property var _videoSettings: QGroundControl.settingsManager.videoSettings
    readonly property var _fovSettings: QGroundControl.settingsManager.gimbalControllerSettings
    readonly property var _videoManager: QGroundControl.videoManager
    readonly property var _vehicleFacts: vehicle ? vehicle.vehicle : null
    readonly property var _gimbal: vehicle ? vehicle.gimbalController.activeGimbal : null
    readonly property var _camera: vehicle ? vehicle.cameraManager.currentCameraInstance : null
    readonly property var _cameraStream: _camera ? _camera.currentStreamInstance : null
    readonly property var _stream: _cameraStream && (!_usesC12
                                   || (String(_camera.modelName).toLowerCase().indexOf("c12") !== -1
                                       && _cameraStream.uri === String(_videoSettings.rtspUrl.rawValue)))
                                   ? _cameraStream : null
    readonly property bool _usesC12: vehicle === QGroundControl.multiVehicleManager.activeVehicle
                                     && Number(_videoSettings.daggerCamera.rawValue) === 1
    readonly property bool _isActiveVehicle: vehicle && vehicle === QGroundControl.multiVehicleManager.activeVehicle
    readonly property real _vehicleHeading: _vehicleFacts ? Number(_vehicleFacts.heading.rawValue) : NaN
    readonly property real _pitch: _usesC12 ? Number(_videoManager.c12PitchDegrees)
                                           : (_gimbal ? Number(_gimbal.absolutePitch.rawValue) : NaN)
    readonly property real _yaw: _usesC12 ? Number(_videoManager.c12YawDegrees)
                                         : (_gimbal ? Number(_gimbal.yawInVehicleFrame
                                                             ? _gimbal.bodyYaw.rawValue : _gimbal.absoluteYaw.rawValue) : NaN)
    readonly property real _bearing: _usesC12 ? normalizeHeading(_vehicleHeading - _yaw)
                                     : (_gimbal && _gimbal.yawInVehicleFrame
                                        ? normalizeHeading(_vehicleHeading + _yaw) : normalizeHeading(_yaw))
    readonly property real _hfov: _stream && Number(_stream.hfov) !== 0
                                  ? Number(_stream.hfov) : Number(_fovSettings.cameraHFov.rawValue)
    readonly property real _attitudeTimestamp: _usesC12 ? Number(_videoManager.c12AttitudeTimestampMs)
                                                       : (_gimbal ? Number(_gimbal.attitudeTimestampMs) : 0)
    readonly property bool _orientationFresh: isFresh(_attitudeTimestamp, 2000)
                                              && (!_usesC12 || _attitudeTimestamp >= _c12SelectionMs)
                                              && isFresh(_vehicleFacts ? Number(_vehicleFacts.attitudeTimestampMs) : 0, 2000)
    readonly property bool _fovFresh: !_stream || Number(_stream.hfov) === 0
                                     || isFresh(Number(_stream.statusTimestampMs), 15000)
    readonly property bool _cameraAvailable: _usesC12 || (_camera && !_camera.isBasic && _gimbal && !_gimbal.retracted)
    readonly property bool _available: _isActiveVehicle && _cameraAvailable && _orientationFresh && _fovFresh
                                      && vehicle.vehicleLinkManager && !vehicle.vehicleLinkManager.communicationLost
                                      && isFinite(_bearing) && isFinite(_pitch) && Math.abs(_pitch) <= 90
                                      && isFinite(_hfov) && _hfov > 0 && _hfov < 180
    readonly property real _radius: Math.max(72, Math.min(180, iconSize * 3.75))
    readonly property real _innerRadius: iconSize * 0.58
    readonly property real _horizontalProjection: Math.cos(_pitch * Math.PI / 180)
    readonly property real _coneRadius: _innerRadius + (_radius - _innerRadius) * _horizontalProjection
    readonly property bool _nadir: Math.abs(_pitch) >= 85

    property double _nowMs: Date.now()
    property double _c12SelectionMs: Date.now()

    width: _radius * 2 + 4
    height: width
    visible: _available
    rotation: _bearing - (map ? map.bearing : 0)
    antialiasing: true

    function normalizeHeading(angle) {
        return ((angle % 360) + 360) % 360
    }

    function isFresh(timestamp, timeout) {
        const now = Math.max(_nowMs, Date.now())
        return isFinite(timestamp) && timestamp > 0 && now >= timestamp && now - timestamp <= timeout
    }

    on_UsesC12Changed: _c12SelectionMs = Date.now()
    onVehicleChanged: _c12SelectionMs = Date.now()
    on_HfovChanged: requestPaint()
    on_ConeRadiusChanged: requestPaint()
    on_InnerRadiusChanged: requestPaint()
    on_NadirChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Timer {
        interval: 200
        repeat: true
        running: root._isActiveVehicle && root.vehicle && root.vehicle.coordinate.isValid
        onTriggered: root._nowMs = Date.now()
    }

    onPaint: {
        const context = getContext("2d")
        context.clearRect(0, 0, width, height)
        if (!_available) return

        const centerX = width / 2
        const centerY = height / 2
        context.lineWidth = 2
        context.strokeStyle = "#FF79C6"
        context.fillStyle = "rgba(255, 121, 198, 0.20)"
        context.beginPath()
        if (_nadir) {
            context.arc(centerX, centerY, _innerRadius + 6, 0, Math.PI * 2)
            context.stroke()
            return
        }

        const halfFov = _hfov * Math.PI / 360
        const startAngle = -Math.PI / 2 - halfFov
        const endAngle = -Math.PI / 2 + halfFov
        context.arc(centerX, centerY, _coneRadius, startAngle, endAngle, false)
        context.arc(centerX, centerY, _innerRadius, endAngle, startAngle, true)
        context.closePath()
        context.fill()
        context.stroke()
    }
}