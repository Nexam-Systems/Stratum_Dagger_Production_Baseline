import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Item {
    id: root

    required property var vehicle
    required property real gimbalYawDegrees
    required property real gimbalPitchDegrees
    required property real gimbalRollDegrees
    required property double gimbalTimestampMs

    // Target ground is assumed level with the take-off point, so height above it is the relative altitude.
    readonly property real heightAboveTakeoff: (vehicle && vehicle.vehicle) ? Number(vehicle.vehicle.altitudeRelative.rawValue) : NaN
    property var estimate: ({})

    readonly property int _attitudeFreshnessMs: 1500
    readonly property var _facts: vehicle ? vehicle.vehicle : null

    CameraGeolocation { id: geometry }

    implicitWidth: resultLayout.implicitWidth
    implicitHeight: resultLayout.implicitHeight

    function _invalid(reason) {
        return {
            status: "INVALID",
            reason: reason,
            source: "CAMERA_CENTRE_RAY",
            latitude: null,
            longitude: null,
            horizontalRange: null,
            bearing: null,
            dNorth: null,
            dEast: null,
            slantRange: null
        }
    }

    function _number(fact) {
        return fact ? Number(fact.rawValue) : NaN
    }

    function _buildEstimate() {
        const now = Date.now()
        if (!vehicle || !vehicle.coordinate || !vehicle.coordinate.isValid) {
            return _invalid(qsTr("Vehicle position is invalid"))
        }
        if (!vehicle.vehicleLinkManager || vehicle.vehicleLinkManager.communicationLost) {
            return _invalid(qsTr("Vehicle telemetry lost"))
        }
        if (!vehicle.gps || !isFinite(_number(vehicle.gps.lock)) || _number(vehicle.gps.lock) < 3) {
            return _invalid(qsTr("GPS fix is not 3D or better"))
        }
        if (!vehicle.homePosition.isValid) {
            return _invalid(qsTr("Home position is unavailable"))
        }
        const positionTimestamp = Number(vehicle.positionTimestampMs)
        if (!isFinite(positionTimestamp) || positionTimestamp <= 0
                || now - positionTimestamp < 0 || now - positionTimestamp > 2000) {
            return _invalid(qsTr("Fused vehicle position is unavailable or stale"))
        }
        if (!_facts || !isFinite(Number(_facts.attitudeTimestampMs)) || _facts.attitudeTimestampMs <= 0
                || now - Number(_facts.attitudeTimestampMs) < 0 || now - Number(_facts.attitudeTimestampMs) > _attitudeFreshnessMs) {
            return _invalid(qsTr("Vehicle attitude is unavailable or stale"))
        }
        if (!isFinite(gimbalYawDegrees) || !isFinite(gimbalPitchDegrees) || !isFinite(gimbalRollDegrees)
                || !isFinite(gimbalTimestampMs) || gimbalTimestampMs <= 0
                || now - gimbalTimestampMs < 0 || now - gimbalTimestampMs > _attitudeFreshnessMs) {
            return _invalid(qsTr("C12 measured attitude is unavailable or stale"))
        }
        const latestSample = Math.max(positionTimestamp, Number(_facts.attitudeTimestampMs), gimbalTimestampMs)
        const earliestSample = Math.min(positionTimestamp, Number(_facts.attitudeTimestampMs), gimbalTimestampMs)
        if (latestSample - earliestSample > 500)
            return _invalid(qsTr("Position, vehicle and camera attitude samples are not aligned"))
        const result = geometry.estimate(vehicle.coordinate, vehicle.homePosition, heightAboveTakeoff,
                                        _number(_facts.roll), _number(_facts.pitch), _number(_facts.heading),
                                        gimbalRollDegrees, gimbalPitchDegrees, gimbalYawDegrees)
        result.sampleTimestampMs = Math.min(Number(_facts.attitudeTimestampMs), gimbalTimestampMs)
        return result
    }

    function computeEstimate() {
        return _buildEstimate()
    }

    function _refresh() {
        estimate = _buildEstimate()
    }

    function _formatResult() {
        if (!estimate || (estimate.status !== "VALID" && estimate.status !== "DEGRADED")) {
            return qsTr("INVALID: %1").arg(estimate ? estimate.reason : qsTr("Waiting for telemetry"))
        }
        return qsTr("Centre ground point %1, %2 | Horizontal %3 m | Bearing %4° | Slant %5 m")
                .arg(Number(estimate.latitude).toFixed(7))
                .arg(Number(estimate.longitude).toFixed(7))
                .arg(Number(estimate.horizontalRange).toFixed(1))
                .arg(Number(estimate.bearing).toFixed(1))
                .arg(Number(estimate.slantRange).toFixed(1))
    }

    function _jsonOutput() {
        return JSON.stringify(estimate || _invalid(qsTr("Waiting for telemetry")), null, 2)
    }

    onGimbalYawDegreesChanged: _refresh()
    onGimbalPitchDegreesChanged: _refresh()
    onGimbalRollDegreesChanged: _refresh()
    onGimbalTimestampMsChanged: _refresh()
    onHeightAboveTakeoffChanged: _refresh()
    onVehicleChanged: _refresh()

    Connections {
        target: root.vehicle
        function onCoordinateChanged() {
            root._refresh()
        }
        function onHomePositionChanged() { root._refresh() }
        function onPositionUpdated() { root._refresh() }
    }

    Connections {
        target: root._facts
        function onAttitudeUpdated() { root._refresh() }
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
            text: isFinite(root.heightAboveTakeoff)
                  ? qsTr("Height above take-off (target ground): %1 m").arg(Number(root.heightAboveTakeoff).toFixed(1))
                  : qsTr("Height above take-off (target ground): unavailable")
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
            text: root.estimate && root.estimate.status === "DEGRADED"
                ? qsTr("DEGRADED: %1").arg(root.estimate.reason)
                : qsTr("Source: measured camera centre ray. Tracking is not required. Ground is assumed level with take-off.")
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
