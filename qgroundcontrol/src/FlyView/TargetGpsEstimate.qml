import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Item {
    id: root

    required property var vehicle
    required property var tracker
    required property real gimbalYawDegrees
    required property real gimbalPitchDegrees
    required property double gimbalTimestampMs
    required property int selectedCameraSource
    required property int activeCameraSource
    required property double selectionTimestampMs
    property bool c12TrackingActive: false

    // Target ground elevation is assumed equal to the take-off (home) point AMSL.
    readonly property real targetGroundAltitudeAmsl: (vehicle && vehicle.homePosition && vehicle.homePosition.isValid)
                                                     ? Number(vehicle.homePosition.altitude) : NaN
    property double _lastPositionMs: 0
    property double _lastHeadingMs: 0
    property double _lastAltitudeMs: 0
    property int _refreshTick: 0
    property var estimate: ({})

    readonly property int _gpsFreshnessMs: 2000
    readonly property int _attitudeFreshnessMs: 1500
    readonly property int _trackerFreshnessMs: 500
    readonly property int _maxInputSkewMs: 1500
    readonly property real _minPitchDegrees: 1.0
    readonly property real _centerTolerance: 0.02
    readonly property real _cameraOffsetMeters: 0.1524

    implicitWidth: resultLayout.implicitWidth
    implicitHeight: resultLayout.implicitHeight

    function _invalid(reason, roi) {
        return {
            status: "INVALID",
            reason: reason,
            trackSource: null,
            latitude: null,
            longitude: null,
            horizontalRange: null,
            bearing: null,
            dNorth: null,
            dEast: null,
            companionTrackerROI: roi,
            c12SdkROI: null,
            c12SdkROIStatus: "UNAVAILABLE_NO_CW2_RESULT_SCHEMA"
        }
    }

    function _number(fact) {
        return fact ? Number(fact.rawValue) : NaN
    }

    function _roi() {
        if (!tracker) return null
        return {
            source: "NEXAM_TARGET_TRACK",
            coordinateSystem: "normalized_0_to_1",
            x0: _number(tracker.topLeftX),
            y0: _number(tracker.topLeftY),
            x1: _number(tracker.botRightX),
            y1: _number(tracker.botRightY)
        }
    }

    function _buildEstimate() {
        var roi = _roi()
        var now = Date.now()
        if (!vehicle || !vehicle.coordinate || !vehicle.coordinate.isValid) {
            return _invalid(qsTr("Vehicle position is invalid"), roi)
        }
        // Facts only signal on value change, so a steady heading/altitude is not stale while the link is alive.
        if (!vehicle.vehicleLinkManager || vehicle.vehicleLinkManager.communicationLost) {
            return _invalid(qsTr("Vehicle telemetry lost"), roi)
        }
        if (!vehicle.gps || _number(vehicle.gps.lock) < 3) {
            return _invalid(qsTr("GPS fix is not 3D or better"), roi)
        }

        var latitude = Number(vehicle.coordinate.latitude)
        var longitude = Number(vehicle.coordinate.longitude)
        var altitudeAmsl = _number(vehicle.vehicle ? vehicle.vehicle.altitudeAMSL : null)
        var headingDegrees = _number(vehicle.vehicle ? vehicle.vehicle.heading : null)
        if (!isFinite(latitude) || !isFinite(longitude)) {
            return _invalid(qsTr("Vehicle latitude or longitude is invalid"), roi)
        }
        if (!isFinite(altitudeAmsl)) {
            return _invalid(qsTr("Vehicle AMSL altitude is unavailable"), roi)
        }
        if (!isFinite(headingDegrees)) {
            return _invalid(qsTr("Vehicle heading is unavailable"), roi)
        }
        if (!isFinite(gimbalYawDegrees) || !isFinite(gimbalPitchDegrees) ||
                gimbalTimestampMs <= 0 || now - gimbalTimestampMs > _attitudeFreshnessMs) {
            return _invalid(qsTr("C12 gimbal attitude is unavailable or stale"), roi)
        }
        var trackSource = ""
        if (c12TrackingActive) {
            // C12 on-camera tracker steers the gimbal onto the target, so the gimbal
            // line of sight is the target bearing; it reports no ROI back to the GCS.
            trackSource = "C12_ONBOARD_TRACKER"
        } else {
            var trackTimestamp = Number(tracker ? tracker.lastUpdateMs : 0)
            if (!tracker || !tracker.telemetryAvailable || Number(tracker.status.rawValue) !== 1) {
                return _invalid(qsTr("No active tracker (start C12 tracking or select a target)"), roi)
            }
            if (selectedCameraSource < 0 || selectedCameraSource !== activeCameraSource) {
                return _invalid(qsTr("Tracker source does not match the active camera feed"), roi)
            }
            if (!isFinite(trackTimestamp) || now - trackTimestamp > _trackerFreshnessMs ||
                    trackTimestamp < selectionTimestampMs) {
                return _invalid(qsTr("Tracker result is stale or predates the current selection"), roi)
            }
            if (!roi || !isFinite(roi.x0) || !isFinite(roi.y0) || !isFinite(roi.x1) || !isFinite(roi.y1)) {
                return _invalid(qsTr("Tracker ROI is invalid"), roi)
            }
            var centerX = (roi.x0 + roi.x1) / 2
            var centerY = (roi.y0 + roi.y1) / 2
            if (Math.abs(centerX - 0.5) > _centerTolerance || Math.abs(centerY - 0.5) > _centerTolerance) {
                return _invalid(qsTr("Target must be centered in the camera frame"), roi)
            }
            trackSource = "NEXAM_TARGET_TRACK"
        }

        var targetAltitudeAmsl = targetGroundAltitudeAmsl
        if (!isFinite(targetAltitudeAmsl)) {
            return _invalid(qsTr("Home position AMSL altitude is unavailable"), roi)
        }
        var height = altitudeAmsl - targetAltitudeAmsl
        if (height <= 0) {
            return _invalid(qsTr("Vehicle AMSL altitude must be above target ground elevation"), roi)
        }
        if (gimbalPitchDegrees >= 0) {
            return _invalid(qsTr("C12 camera must be pitched downward to estimate ground target coordinates"), roi)
        }
        var pitchMagnitude = Math.abs(gimbalPitchDegrees)
        if (pitchMagnitude < _minPitchDegrees) {
            return _invalid(qsTr("Pitch too close to horizontal"), roi)
        }

        var radians = Math.PI / 180.0
        var headingRadians = headingDegrees * radians
        var bearing = ((headingDegrees - gimbalYawDegrees) % 360.0 + 360.0) % 360.0
        var bearingRadians = bearing * radians
        var horizontalRange = height / Math.tan(pitchMagnitude * radians)
        var dNorth = horizontalRange * Math.cos(bearingRadians) + _cameraOffsetMeters * Math.cos(headingRadians)
        var dEast = horizontalRange * Math.sin(bearingRadians) + _cameraOffsetMeters * Math.sin(headingRadians)
        var longitudeScale = 111320.0 * Math.cos(latitude * radians)
        if (Math.abs(longitudeScale) < 1.0) {
            return _invalid(qsTr("Longitude calculation is singular at this latitude"), roi)
        }
        var targetLatitude = latitude + dNorth / 111320.0
        var targetLongitude = longitude + dEast / longitudeScale
        if (!isFinite(targetLatitude) || !isFinite(targetLongitude) ||
                Math.abs(targetLatitude) > 90 || Math.abs(targetLongitude) > 180) {
            return _invalid(qsTr("Calculated target coordinates are outside valid bounds"), roi)
        }

        return {
            status: "VALID",
            reason: "",
            trackSource: trackSource,
            latitude: targetLatitude,
            longitude: targetLongitude,
            horizontalRange: horizontalRange,
            bearing: bearing,
            dNorth: dNorth,
            dEast: dEast,
            companionTrackerROI: roi,
            c12SdkROI: null,
            c12SdkROIStatus: "UNAVAILABLE_NO_CW2_RESULT_SCHEMA"
        }
    }

    function _refresh() {
        _refreshTick++
        estimate = _buildEstimate()
    }

    function _formatResult() {
        if (!estimate || estimate.status !== "VALID") {
            return qsTr("INVALID: %1").arg(estimate ? estimate.reason : qsTr("Waiting for telemetry"))
        }
        return qsTr("Target %1, %2 | Range %3 m | Bearing %4°")
                .arg(Number(estimate.latitude).toFixed(7))
                .arg(Number(estimate.longitude).toFixed(7))
                .arg(Number(estimate.horizontalRange).toFixed(1))
                .arg(Number(estimate.bearing).toFixed(1))
    }

    function _jsonOutput() {
        return JSON.stringify(estimate || _invalid(qsTr("Waiting for telemetry"), null), null, 2)
    }

    onGimbalYawDegreesChanged: _refresh()
    onGimbalPitchDegreesChanged: _refresh()
    onGimbalTimestampMsChanged: _refresh()
    onSelectedCameraSourceChanged: _refresh()
    onActiveCameraSourceChanged: _refresh()
    onSelectionTimestampMsChanged: _refresh()
    onC12TrackingActiveChanged: _refresh()
    onTargetGroundAltitudeAmslChanged: _refresh()
    onVehicleChanged: {
        _lastPositionMs = 0
        _lastHeadingMs = 0
        _lastAltitudeMs = 0
        _refresh()
    }
    onTrackerChanged: _refresh()

    Connections {
        target: root.vehicle
        function onCoordinateChanged() {
            root._lastPositionMs = Date.now()
            root._refresh()
        }
    }

    Connections {
        target: root.vehicle && root.vehicle.vehicle ? root.vehicle.vehicle.heading : null
        function onRawValueChanged() {
            root._lastHeadingMs = Date.now()
            root._refresh()
        }
    }

    Connections {
        target: root.vehicle && root.vehicle.vehicle ? root.vehicle.vehicle.altitudeAMSL : null
        function onRawValueChanged() {
            root._lastAltitudeMs = Date.now()
            root._refresh()
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: root._refresh()
    }

    ColumnLayout {
        id: resultLayout
        width: parent ? parent.width : implicitWidth
        spacing: ScreenTools.defaultFontPixelHeight / 3

        QGCLabel {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: isFinite(root.targetGroundAltitudeAmsl)
                  ? qsTr("Target ground AMSL (home): %1 m").arg(Number(root.targetGroundAltitudeAmsl).toFixed(1))
                  : qsTr("Target ground AMSL (home): unavailable")
        }

        QGCLabel {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root._formatResult()
            color: root.estimate && root.estimate.status === "VALID" ? qgcPal.text : qgcPal.warningText
        }

        QGCLabel {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: qgcPal.warningText
            font.pointSize: ScreenTools.smallFontPointSize
            text: root.c12TrackingActive
                  ? qsTr("Source: C12 on-camera tracker. Target bearing is taken from the gimbal line of sight (tracker keeps the target centred).")
                  : qsTr("Source: NEXAM_TARGET_TRACK. The C12 does not report its tracker ROI to the GCS.")
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(jsonArea.implicitHeight, ScreenTools.defaultFontPixelHeight * 24)
            clip: true

            TextArea {
                id: jsonArea
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                text: root._jsonOutput()
                font.family: "Consolas"
                font.pixelSize: ScreenTools.smallFontPixelSize
            }
        }
    }

    QGCPalette { id: qgcPal }

    Component.onCompleted: _refresh()
}
