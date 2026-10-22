import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM KAN-17 (test UI): unified top status bar. A single rounded-border strip of
// label/value cells (STRATUM wordmark, UAV, STATE, MODE, positions, ALT/GS/VS, TIME,
// VIDEO, GNSS, LINK, BATT). Experimental layout to preview styling; the NX logo button
// stays in FlyViewToolBar. All data comes from the active vehicle.
Item {
    id: root

    property var  vehicle
    property var  pendingTarget: null
    property var  designatedTarget: null
    property bool videoLive: false
    property color ribbonTextColor: qgcPal.text

    readonly property var  _facts:  vehicle ? vehicle.vehicle : null
    readonly property var  _gps:    vehicle ? vehicle.gps : null
    readonly property var  _radio:  vehicle ? vehicle.radioStatus : null
    readonly property var  _batt:   (vehicle && vehicle.batteries && vehicle.batteries.count > 0) ? vehicle.batteries.get(0) : null
    readonly property bool _live:   !!vehicle && (!vehicle.vehicleLinkManager || !vehicle.vehicleLinkManager.communicationLost)
    readonly property var  _target: (pendingTarget && pendingTarget.isValid) ? pendingTarget : designatedTarget

    readonly property color _accent: qgcPal.highContrast ? qgcPal.text : "#79CBE8"
    readonly property color _labelColor: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.6)

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    function _num(fact) {
        return (fact && isFinite(Number(fact.rawValue))) ? (Number(fact.value).toFixed(1) + " " + fact.units) : "--"
    }
    function _meters(fact) {
        return (fact && isFinite(Number(fact.rawValue))) ? (Number(fact.value).toFixed(2) + " m") : "--"
    }
    function _coord(c) {
        return (c && c.isValid) ? (c.latitude.toFixed(6) + "\u00b0\n" + c.longitude.toFixed(6) + "\u00b0") : "--"
    }
    function _duration(fact) {
        if (!fact || !isFinite(Number(fact.rawValue)))
            return "--:--:--"
        var s = Math.max(0, Math.floor(Number(fact.rawValue)))
        return String(Math.floor(s / 3600)).padStart(2, "0") + ":" + String(Math.floor(s / 60) % 60).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }
    function _uavName() {
        if (!vehicle)
            return "--"
        return "UAV-" + (vehicle.id < 10 ? "0" + vehicle.id : vehicle.id)
    }
    function _stateText() {
        if (!vehicle)   return qsTr("DISCONNECTED")
        if (!_live)     return qsTr("COMMS LOST")
        if (!vehicle.armed) {
            if (vehicle.readyToFlyAvailable && !vehicle.readyToFly) return qsTr("NOT READY")
            if (!vehicle.allSensorsHealthy)                         return qsTr("NOT READY")
            return qsTr("READY")
        }
        var mode = vehicle.flightMode
        if (mode === qsTr("Abort")) return qsTr("ABORT")
        if (mode === qsTr("Engagement") || mode === qsTr("Vision Engagement")) return qsTr("ENGAGING")
        if (vehicle.landing) return qsTr("LANDING")
        if (vehicle.flying)  return qsTr("FLYING")
        return qsTr("ARMED")
    }
    function _stateColor() {
        var s = _stateText()
        if (s === qsTr("ABORT") || s === qsTr("COMMS LOST") || s === qsTr("DISCONNECTED")) return qgcPal.colorRed
        if (s === qsTr("ENGAGING")) return qgcPal.colorOrange
        if (s === qsTr("NOT READY")) return qgcPal.colorYellow
        return qgcPal.colorGreen
    }
    function _link() {
        return (_radio && _radio.lrssi && isFinite(Number(_radio.lrssi.rawValue))) ? (_radio.lrssi.rawValue + " dBm") : "--"
    }
    function _batteryText() {
        return (_batt && _batt.percentRemaining && isFinite(Number(_batt.percentRemaining.rawValue))) ? (Math.round(_batt.percentRemaining.rawValue) + "%") : "--"
    }

    // One label-over-value cell.
    component Cell: ColumnLayout {
        id: cell
        property string label: ""
        property string value: ""
        property color valueColor: root._accent
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 2

        Item { Layout.fillHeight: true }
        QGCLabel {
            Layout.alignment: Qt.AlignHCenter
            text: cell.label
            color: root._labelColor
            font.pointSize: ScreenTools.smallFontPointSize * 0.85
        }
        QGCLabel {
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            text: cell.value
            color: cell.valueColor
            font.bold: true
            font.pointSize: ScreenTools.smallFontPointSize
        }
        Item { Layout.fillHeight: true }
    }

    component Divider: Rectangle {
        Layout.preferredWidth: 1
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        Layout.fillHeight: true
        color: root._accent
        opacity: 0.35
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 6
        radius: height * 0.28
        color: "transparent"
        border.color: root._accent
        border.width: 2

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 0

            // STRATUM wordmark
            ColumnLayout {
                Layout.fillHeight: true
                Layout.rightMargin: 6
                spacing: 0
                Item { Layout.fillHeight: true }
                QGCLabel { text: "STRATUM"; color: root.ribbonTextColor; font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize; font.letterSpacing: 2 }
                QGCLabel { text: QGroundControl.qgcVersion; color: root._labelColor; font.pointSize: ScreenTools.smallFontPointSize * 0.85 }
                Item { Layout.fillHeight: true }
            }

            Divider {}
            Cell { label: qsTr("UAV");     value: root._uavName() }
            Divider {}
            Cell { label: qsTr("STATE");   value: root._stateText();  valueColor: root._stateColor() }
            Divider {}
            Cell { label: qsTr("MODE");    value: vehicle ? vehicle.flightMode : "--" }
            Divider {}
            Cell { label: qsTr("UAV POS"); value: root._coord(vehicle ? vehicle.coordinate : null) }
            Divider {}
            Cell { label: qsTr("TGT POS"); value: root._coord(root._target) }
            Divider {}
            Cell { label: qsTr("ALT");     value: root._num(_facts ? _facts.altitudeRelative : null) }
            Divider {}
            Cell { label: qsTr("GS");      value: root._num(_facts ? _facts.groundSpeed : null) }
            Divider {}
            Cell { label: qsTr("VS");      value: root._num(_facts ? _facts.climbRate : null) }
            Divider {}
            Cell { label: qsTr("TIME");    value: root._duration(_facts ? _facts.flightTime : null) }
            Divider {}
            Cell { label: qsTr("VIDEO");   value: root.videoLive ? qsTr("LIVE") : qsTr("WAITING"); valueColor: root.videoLive ? qgcPal.colorGreen : qgcPal.colorOrange }
            Divider {}

            // GNSS cell: label + three compact rows.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 1
                Item { Layout.fillHeight: true }
                QGCLabel { Layout.alignment: Qt.AlignHCenter; text: qsTr("GNSS"); color: root._labelColor; font.pointSize: ScreenTools.smallFontPointSize * 0.85 }
                GridLayout {
                    Layout.alignment: Qt.AlignHCenter
                    columns: 2
                    rowSpacing: 0
                    columnSpacing: 4
                    QGCLabel { text: qsTr("HD");   color: root._labelColor; font.pointSize: ScreenTools.smallFontPointSize * 0.8 }
                    QGCLabel { text: root._meters(_gps ? _gps.horizontalAccuracy : null); color: root._accent; font.pointSize: ScreenTools.smallFontPointSize * 0.8 }
                    QGCLabel { text: qsTr("VACC"); color: root._labelColor; font.pointSize: ScreenTools.smallFontPointSize * 0.8 }
                    QGCLabel { text: root._meters(_gps ? _gps.verticalAccuracy : null); color: root._accent; font.pointSize: ScreenTools.smallFontPointSize * 0.8 }
                    QGCLabel { text: qsTr("NSAT"); color: root._labelColor; font.pointSize: ScreenTools.smallFontPointSize * 0.8 }
                    QGCLabel { text: (_gps && _gps.count) ? _gps.count.valueString : "--"; color: root._accent; font.pointSize: ScreenTools.smallFontPointSize * 0.8 }
                }
                Item { Layout.fillHeight: true }
            }

            Divider {}
            Cell { label: qsTr("LINK"); value: root._link() }
            Divider {}
            Cell { label: qsTr("BATT"); value: root._batteryText() }
        }
    }
}
