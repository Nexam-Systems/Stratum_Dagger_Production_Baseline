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
    property bool compact: false
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

    GridLayout {
        id: fields

        columns: 4
        columnSpacing: root.compact ? 4 : 12
        rowSpacing: root.compact ? 6 : 8
        width: parent.width - (root.compact ? 4 : 16)
        x: root.compact ? 2 : 8
        y: 6

        Group {
            iconSource: "/InstrumentValueIcons/airplane.svg"
            title: root.compact ? qsTr("UAV") : qsTr("UAV GPS / LAT · LON")
            value: root.positionFresh && root.vehicle.coordinate.isValid ? root.vehicle.coordinate.latitude.toFixed(root.compact ? 5 : 7) + (root.compact ? "," : "  ") + root.vehicle.coordinate.longitude.toFixed(root.compact ? 5 : 7) : qsTr("Unavailable")
        }

        Group {
            iconSource: "/InstrumentValueIcons/target.svg"
            title: root.compact ? qsTr("TARGET") : root.targetPending ? qsTr("TARGET / PENDING") : qsTr("TARGET / DESIGNATED")
            value: root.target && root.target.isValid ? root.target.latitude.toFixed(root.compact ? 5 : 7) + (root.compact ? "," : "  ") + root.target.longitude.toFixed(root.compact ? 5 : 7) : qsTr("Unavailable")
        }

        Group {
            iconSource: "/InstrumentValueIcons/dashboard.svg"
            title: root.compact ? qsTr("GROUND SPEED") : qsTr("GROUND SPEED")
            value: root.number(root.facts ? root.facts.groundSpeed : null, root.motionFresh)
        }

        Group {
            iconSource: "/InstrumentValueIcons/arrow-thick-up.svg"
            title: root.compact ? qsTr("V SPEED") : qsTr("VERTICAL SPEED (+UP / −DOWN)")
            value: root.number(root.facts ? root.facts.climbRate : null, root.motionFresh)
        }

        Group {
            iconSource: "/InstrumentValueIcons/arrow-base-down.svg"
            title: root.compact ? qsTr("ALT") : qsTr("HEIGHT ABOVE HOME")
            value: root.number(root.facts ? root.facts.altitudeRelative : null, root.altitudeFresh)
        }

        Group {
            iconSource: "/InstrumentValueIcons/home.svg"
            title: root.compact ? qsTr("HOME") : qsTr("HOME DISTANCE")
            value: root.vehicle && root.vehicle.homePosition.isValid ? root.number(root.facts ? root.facts.distanceToHome : null, root.positionFresh) : "--"
        }

        Group {
            iconSource: "/InstrumentValueIcons/time.svg"
            title: root.compact ? qsTr("TIME") : root.vehicle && root.vehicle.armedTimerSinceConnection ? qsTr("SINCE CONNECTION") : qsTr("ARMED TIME")
            value: root.live && root.facts ? root.duration(root.facts.getFact("flightTime")) : "--:--:--"
        }

        Group {
            iconSource: "/InstrumentValueIcons/video-camera.svg"
            title: root.compact ? qsTr("VIDEO") : qsTr("VIDEO")
            value: root.videoLive ? qsTr("Live") : qsTr("Waiting / unavailable")
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: root.visible

        onTriggered: root.nowMs = Date.now()
    }

    component Group: Item {
        property string iconSource: ""
        property string title
        property string value

        implicitHeight: groupColumn.implicitHeight
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: (fields.width - fields.columnSpacing * 3) / 4
        Layout.preferredHeight: implicitHeight

        Column {
            id: groupColumn
            spacing: root.compact ? 0 : 3
            width: parent.width

            Row {
                visible: !root.compact
                spacing: root.compact ? 3 : 0
                width: parent.width

                QGCColoredImage {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.compact ? 11 : 0
                    height: width
                    sourceSize.height: height
                    source: parent.parent.parent.iconSource
                    color: headerPalette.highContrast ? headerPalette.buttonBorder : "#79CBE8"
                    visible: root.compact
                }

                QGCLabel {
                    id: titleLabel

                    color: headerPalette.highContrast ? headerPalette.buttonBorder : "#79CBE8"
                    font.pointSize: root.compact ? ScreenTools.smallFontPointSize * 0.95 : ScreenTools.smallFontPointSize
                    text: parent.parent.parent.title
                    width: root.compact ? parent.width - 14 : parent.width
                    wrapMode: root.compact ? Text.NoWrap : Text.WordWrap
                    elide: root.compact ? Text.ElideRight : Text.ElideNone
                }
            }

            Row {
                visible: root.compact
                spacing: 4
                width: parent.width

                QGCColoredImage {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13
                    height: width
                    sourceSize.height: height
                    source: parent.parent.parent.iconSource
                    color: headerPalette.highContrast ? headerPalette.buttonBorder : "#79CBE8"
                }

                QGCLabel {
                    id: compactValueLabel

                    Accessible.name: parent.parent.parent.title + ": " + parent.parent.parent.value
                    font.family: ScreenTools.fixedFontFamily
                    font.pointSize: ScreenTools.smallFontPointSize * 0.95
                    font.bold: true
                    text: parent.parent.parent.value
                    width: parent.width - 17
                    wrapMode: Text.NoWrap
                    elide: Text.ElideMiddle
                }
            }

            QGCLabel {
                id: valueLabel

                visible: !root.compact
                font.family: ScreenTools.fixedFontFamily
                font.pointSize: ScreenTools.smallFontPointSize
                text: parent.parent.value
                width: parent.width
                wrapMode: root.compact ? Text.NoWrap : Text.WordWrap
                elide: root.compact ? Text.ElideMiddle : Text.ElideNone
            }
        }
    }
}
