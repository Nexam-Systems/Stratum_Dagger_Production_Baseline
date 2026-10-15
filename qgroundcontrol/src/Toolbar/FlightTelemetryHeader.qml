import QGroundControl
import QGroundControl.Controls
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool altitudeFresh: live && facts && facts.altitudeTimestampMs > 0 && nowMs - facts.altitudeTimestampMs < 2000
    property var designatedTarget: null
    readonly property var facts: vehicle ? vehicle.vehicle : null
    readonly property bool live: vehicle && !vehicle.vehicleLinkManager.communicationLost
    readonly property bool motionFresh: live && facts && facts.motionTimestampMs > 0 && nowMs - facts.motionTimestampMs < 2000
    property double nowMs: Date.now()
    property var pendingTarget: null
    readonly property bool positionFresh: live && vehicle.positionTimestampMs > 0 && nowMs - vehicle.positionTimestampMs < 2000
    readonly property var target: pendingTarget && pendingTarget.isValid ? pendingTarget : designatedTarget
    readonly property bool targetPending: pendingTarget && pendingTarget.isValid
    readonly property var units: QGroundControl.unitsConversion
    property var vehicle: null
    property bool videoLive: false

    function duration(fact) {
        if (!fact || !isFinite(Number(fact.rawValue)))
            return "--:--:--";
        const seconds = Math.max(0, Math.floor(Number(fact.rawValue)));
        return String(Math.floor(seconds / 3600)).padStart(2, "0") + ":" + String(Math.floor(seconds / 60) % 60).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
    }

    function number(fact, fresh) {
        if (!fresh || !fact || !isFinite(Number(fact.rawValue)))
            return "--";
        return Number(fact.value).toFixed(1) + " " + fact.units;
    }

    implicitHeight: fields.implicitHeight + 12

    QGCPalette {
        id: headerPalette

        colorGroupEnabled: true
    }

    Flow {
        id: fields

        spacing: 12
        width: parent.width - 16
        x: 8
        y: 6

        Group {
            title: qsTr("UAV GPS / LAT · LON")
            value: root.positionFresh && root.vehicle.coordinate.isValid ? root.vehicle.coordinate.latitude.toFixed(7) + "  " + root.vehicle.coordinate.longitude.toFixed(7) : qsTr("Unavailable")
        }

        Group {
            title: root.targetPending ? qsTr("TARGET / PENDING") : qsTr("TARGET / DESIGNATED")
            value: root.target && root.target.isValid ? root.target.latitude.toFixed(7) + "  " + root.target.longitude.toFixed(7) : qsTr("Unavailable")
        }

        Group {
            title: qsTr("GROUND SPEED")
            value: root.number(root.facts ? root.facts.groundSpeed : null, root.motionFresh)
        }

        Group {
            title: qsTr("VERTICAL SPEED (+UP / −DOWN)")
            value: root.number(root.facts ? root.facts.climbRate : null, root.motionFresh)
        }

        Group {
            title: qsTr("HEIGHT ABOVE HOME")
            value: root.number(root.facts ? root.facts.altitudeRelative : null, root.altitudeFresh)
        }

        Group {
            title: qsTr("HOME DISTANCE")
            value: root.vehicle && root.vehicle.homePosition.isValid ? root.number(root.facts ? root.facts.distanceToHome : null, root.positionFresh) : "--"
        }

        Group {
            title: root.vehicle && root.vehicle.armedTimerSinceConnection ? qsTr("SINCE CONNECTION") : qsTr("ARMED TIME")
            value: root.live && root.facts ? root.duration(root.facts.getFact("flightTime")) : "--:--:--"
        }

        Group {
            title: qsTr("VIDEO")
            value: root.videoLive ? qsTr("Live") : qsTr("Waiting / unavailable")
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: root.visible

        onTriggered: root.nowMs = Date.now()
    }

    component Group: Column {
        property string title
        property string value

        spacing: 3
        width: Math.min(root.width - 16, Math.max(136, valueLabel.implicitWidth + 16, titleLabel.implicitWidth + 16))

        QGCLabel {
            id: titleLabel

                color: headerPalette.highContrast ? headerPalette.buttonBorder : "#79CBE8"
            font.pointSize: ScreenTools.smallFontPointSize
            text: parent.title
            width: parent.width
            wrapMode: Text.WordWrap
        }

        QGCLabel {
            id: valueLabel

            font.family: ScreenTools.fixedFontFamily
            font.pointSize: ScreenTools.smallFontPointSize
            text: parent.value
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }
}
