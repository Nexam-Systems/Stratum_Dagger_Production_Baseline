import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM KAN-17 (test UI): unified top status bar. A borderless strip of divider-
// separated label/value cells (STRATUM wordmark, UAV, STATE, MODE, positions,
// ALT/GS/VS, TIME, VIDEO, GNSS, LINK, BATT) that reads as part of the toolbar ribbon.
// STATE / GNSS / LINK / BATT are clickable and open the standard QGC info drawers; the
// far-right edge hides the 7-tap admin entry. The NX logo button stays in
// FlyViewToolBar. All data comes from the active vehicle.
Item {
    id: root

    property var  vehicle
    property var  pendingTarget: null
    property var  designatedTarget: null
    property var  standoffController: null
    property bool videoLive: false
    property color ribbonTextColor: qgcPal.text

    // Standoff distance cells (moved into the ribbon's right region, KAN-17). Matches the
    // gating used by RTLDecisionCountdownPanel: only valid while standoff is active and the
    // target coordinate is valid. Values are shown in the app's horizontal distance units.
    readonly property var  _soHome:  (vehicle && vehicle.homePosition && vehicle.homePosition.isValid) ? vehicle.homePosition : null
    readonly property bool _soValid: !!_soHome && !!standoffController && standoffController._standoffActive === true
                                     && standoffController._targetCoordinate && standoffController._targetCoordinate.isValid
    readonly property real _homeStandoffM: _soValid ? _soHome.distanceTo(standoffController._targetCoordinate) : Number.NaN
    readonly property var  _vehCoord: (vehicle && vehicle.coordinate && vehicle.coordinate.isValid) ? vehicle.coordinate : null
    readonly property bool _vehSoValid: !!_vehCoord && !!standoffController && standoffController._standoffActive === true
                                        && standoffController._targetCoordinate && standoffController._targetCoordinate.isValid
    readonly property real _vehStandoffM: _vehSoValid ? _vehCoord.distanceTo(standoffController._targetCoordinate) : Number.NaN
    readonly property real _homeVehM: (_soHome && _vehCoord) ? _soHome.distanceTo(vehicle.coordinate) : Number.NaN

    readonly property var  _facts:  vehicle ? vehicle.vehicle : null
    readonly property var  _gps:    vehicle ? vehicle.gps : null
    readonly property var  _radio:  vehicle ? vehicle.radioStatus : null
    readonly property var  _batt:   (vehicle && vehicle.batteries && vehicle.batteries.count > 0) ? vehicle.batteries.get(0) : null
    readonly property bool _live:   !!vehicle && (!vehicle.vehicleLinkManager || !vehicle.vehicleLinkManager.communicationLost)
    readonly property var  _target: (pendingTarget && pendingTarget.isValid) ? pendingTarget : designatedTarget

    // Exposed as _activeVehicle so reused toolbar drawer pages (GPSIndicatorPage,
    // VehicleMessageList) resolve the active vehicle from this component's scope.
    readonly property var  _activeVehicle: vehicle

    // Theme-aware palette matching the two approved mockups:
    //   - Normal theme:        cyan accent. Labels/dividers cyan, data values white.
    //   - High-contrast theme: neon-green accent. Labels white, data values green.
    // Status values (STATE / LINK / BATT) and VIDEO carry their own health colours
    // in both themes.
    readonly property bool  _hc:         qgcPal.highContrast
    readonly property color _accent:     _hc ? "#2EE62E" : "#79CBE8"
    readonly property color _labelColor: _hc ? qgcPal.text : _accent
    readonly property color _valueColor: _hc ? _accent : qgcPal.text
    readonly property color _dimColor:   Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.55)

    // Larger, tightly-packed cell typography (KAN-17 feedback).
    readonly property real  _labelFontSize: ScreenTools.smallFontPointSize
    readonly property real  _valueFontSize: ScreenTools.defaultFontPointSize
    readonly property real  _cellPadding:   ScreenTools.defaultFontPixelWidth * 0.75

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    function _num(fact) {
        return (fact && isFinite(Number(fact.rawValue))) ? (Number(fact.value).toFixed(1) + " " + fact.units) : "--"
    }
    function _meters(fact) {
        return (fact && isFinite(Number(fact.rawValue))) ? (Number(fact.value).toFixed(2) + " m") : "--"
    }
    function _dist(meters) {
        if (meters === undefined || isNaN(meters))
            return "--"
        return QGroundControl.unitsConversion.metersToAppSettingsHorizontalDistanceUnits(meters).toFixed(0) + " " + QGroundControl.unitsConversion.appSettingsHorizontalDistanceUnitsString
    }
    function _gnssText() {
        var sat  = (_gps && _gps.count && isFinite(Number(_gps.count.rawValue))) ? _gps.count.valueString : "--"
        var hacc = (_gps && _gps.horizontalAccuracy && isFinite(Number(_gps.horizontalAccuracy.rawValue))) ? (Number(_gps.horizontalAccuracy.value).toFixed(1) + " m") : "--"
        return sat + " \u00b7 " + hacc
    }
    function _coord(c) {
        return (c && c.isValid) ? (c.latitude.toFixed(6) + "\u00b0\n" + c.longitude.toFixed(6) + "\u00b0") : "--"
    }
    function _duration(fact) {
        if (!fact || !isFinite(Number(fact.rawValue)))
            return "--:--"
        var s = Math.max(0, Math.floor(Number(fact.rawValue)))
        return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
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
    function _factText(fact, suffix, decimals) {
        if (!fact || !isFinite(Number(fact.rawValue)))
            return "--"
        var d = (decimals === undefined) ? 1 : decimals
        return Number(fact.rawValue).toFixed(d) + (suffix ? suffix : "")
    }
    function _battColor() {
        if (!_batt || !_batt.percentRemaining || !isFinite(Number(_batt.percentRemaining.rawValue)))
            return _valueColor
        var p = Number(_batt.percentRemaining.rawValue)
        if (p <= 15) return qgcPal.colorRed
        if (p <= 30) return qgcPal.colorOrange
        return qgcPal.colorGreen
    }
    function _linkColor() {
        if (!_radio || !_radio.lrssi || !isFinite(Number(_radio.lrssi.rawValue)))
            return _valueColor
        var r = Number(_radio.lrssi.rawValue)
        if (r >= -90)  return qgcPal.colorGreen
        if (r >= -100) return qgcPal.colorOrange
        return qgcPal.colorRed
    }

    // One label-over-value cell. Optionally clickable (opens an info drawer) with a
    // small down-chevron affordance, matching the chevron next to the NX menu mark.
    component Cell: Item {
        id: cell
        property string label: ""
        property string value: ""
        property color valueColor: root._valueColor
        property bool clickable: false
        property bool showChevron: false
        // Optional stable content width (in px). Numeric cells (ALT/GS/VS) use this so a
        // sign flip (negative GS/VS) or digit-count change cannot reflow the whole ribbon.
        property real minContentWidth: 0
        signal cellClicked()
        Layout.fillHeight: true
        implicitWidth: Math.max(cellCol.implicitWidth, minContentWidth) + root._cellPadding * 2
        implicitHeight: cellCol.implicitHeight

        ColumnLayout {
            id: cellCol
            anchors.centerIn: parent
            spacing: 1
            QGCLabel {
                Layout.alignment: Qt.AlignHCenter
                text: cell.label
                color: root._labelColor
                font.pointSize: root._labelFontSize
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 3
                QGCLabel {
                    horizontalAlignment: Text.AlignHCenter
                    text: cell.value
                    color: cell.valueColor
                    font.bold: true
                    font.pointSize: root._valueFontSize
                }
                QGCLabel {
                    visible: cell.showChevron
                    text: "\u25BE"
                    color: cell.valueColor
                    opacity: 0.85
                    font.pointSize: root._valueFontSize * 0.85
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: cell.clickable
            cursorShape: cell.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: cell.cellClicked()
        }
    }

    component Divider: Rectangle {
        Layout.preferredWidth: 1
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        Layout.fillHeight: true
        color: root._accent
        opacity: 0.5
    }

    // STRATUM: no enclosing capsule/border -- the cells read as part of the same
    // toolbar ribbon rather than a separate floating pill. Just a transparent
    // container that supplies the inner margins for the cell row.
    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 6
        radius: 0
        color: "transparent"
        border.width: 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 0

            // STRATUM wordmark -- also the hidden admin entry: seven quick taps open
            // the password-protected admin settings dialog.
            Item {
                id: wordmarkCell
                Layout.fillHeight: true
                Layout.rightMargin: 6
                Layout.leftMargin: root._cellPadding
                implicitWidth: wordmarkCol.implicitWidth
                implicitHeight: wordmarkCol.implicitHeight

                property int  _tapCount: 0
                property real _firstTapMs: 0

                ColumnLayout {
                    id: wordmarkCol
                    anchors.centerIn: parent
                    spacing: 0
                    QGCLabel { text: "STRATUM"; color: root.ribbonTextColor; font.bold: true; font.pointSize: ScreenTools.mediumFontPointSize; font.letterSpacing: 2 }
                    QGCLabel { text: QGroundControl.qgcVersion; color: root._dimColor; font.pointSize: ScreenTools.smallFontPointSize * 0.85 }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.ArrowCursor
                    onClicked: {
                        var nowMs = Date.now()
                        if (wordmarkCell._tapCount === 0 || (nowMs - wordmarkCell._firstTapMs) > 3000) {
                            wordmarkCell._tapCount = 1
                            wordmarkCell._firstTapMs = nowMs
                            return
                        }
                        wordmarkCell._tapCount += 1
                        if (wordmarkCell._tapCount >= 7) {
                            wordmarkCell._tapCount = 0
                            wordmarkCell._firstTapMs = 0
                            adminDialogFactory.open()
                        }
                    }
                }

                QGCPopupDialogFactory {
                    id:              adminDialogFactory
                    dialogComponent: adminDialogComponent
                }
                Component {
                    id: adminDialogComponent
                    AdminSettingsDialog { }
                }
            }

            Divider {}
            Cell {
                id: stateCell
                label: qsTr("STATE")
                value: root._stateText()
                valueColor: root._stateColor()
                clickable: true
                showChevron: true
                onCellClicked: mainWindow.showIndicatorDrawer(stateDrawerComponent, stateCell)
            }
            Divider {}
            Cell { label: qsTr("MODE");    value: vehicle ? vehicle.flightMode : "--" }
            Divider {}
            Cell { label: qsTr("UAV POS"); value: root._coord(vehicle ? vehicle.coordinate : null) }
            Divider {}
            Cell { label: qsTr("TGT POS"); value: root._coord(root._target) }
            Divider {}
            Cell { label: qsTr("ALT");     value: root._num(_facts ? _facts.altitudeRelative : null); minContentWidth: ScreenTools.defaultFontPixelWidth * 8 }
            Divider {}
            Cell { label: qsTr("GS");      value: root._num(_facts ? _facts.groundSpeed : null); minContentWidth: ScreenTools.defaultFontPixelWidth * 10 }
            Divider {}
            Cell { label: qsTr("VS");      value: root._num(_facts ? _facts.climbRate : null); minContentWidth: ScreenTools.defaultFontPixelWidth * 10 }
            Divider {}
            Cell { label: qsTr("TIME");    value: root._duration(_facts ? _facts.flightTime : null) }
            Divider {}

            // GNSS summary cell (sat count + horizontal accuracy) at the same size/style as
            // the other cells. Click opens the full GPS details drawer (HDOP/VDOP/sats/etc).
            Cell {
                id: gnssCell
                label: qsTr("GNSS")
                value: root._gnssText()
                clickable: true
                showChevron: true
                onCellClicked: mainWindow.showIndicatorDrawer(gnssDrawerComponent, gnssCell)
            }

            Divider {}
            Cell {
                id: linkCell
                label: qsTr("LINK")
                value: root._link()
                valueColor: root._linkColor()
                clickable: true
                onCellClicked: mainWindow.showIndicatorDrawer(linkDrawerComponent, linkCell)
            }
            Divider {}
            Cell {
                id: battCell
                label: qsTr("BATT")
                value: root._batteryText()
                valueColor: root._battColor()
                clickable: true
                onCellClicked: mainWindow.showIndicatorDrawer(battDrawerComponent, battCell)
            }

            // Flexible spacer pushes the standoff distance cells into the previously-empty
            // right region of the ribbon so that space is used.
            Item { Layout.fillWidth: true; Layout.fillHeight: true }

            Divider {}
            Cell { label: qsTr("HOME\u2192STDF"); value: root._dist(root._homeStandoffM); minContentWidth: ScreenTools.defaultFontPixelWidth * 7 }
            Divider {}
            Cell { label: qsTr("VEH\u2192STDF");  value: root._dist(root._vehStandoffM); minContentWidth: ScreenTools.defaultFontPixelWidth * 7 }
            Divider {}
            Cell { label: qsTr("HOME\u2192VEH");  value: root._dist(root._homeVehM); minContentWidth: ScreenTools.defaultFontPixelWidth * 7 }
        }
    }

    // ---- Click-through info drawers (reuse the standard QGC indicator drawer) ----

    Component {
        id: stateDrawerComponent
        ToolIndicatorPage {
            showExpand: false
            contentComponent: ColumnLayout {
                spacing: ScreenTools.defaultFontPixelHeight / 2

                SettingsGroupLayout {
                    heading: qsTr("Vehicle State")

                    RowLayout {
                        spacing: ScreenTools.defaultFontPixelWidth
                        visible: root.vehicle
                        QGCDelayButton {
                            text: (root.vehicle && root.vehicle.armed) ? qsTr("Disarm") : qsTr("Arm")
                            onActivated: {
                                if (root.vehicle)
                                    root.vehicle.armed = !root.vehicle.armed
                                mainWindow.closeIndicatorDrawer()
                            }
                        }
                    }
                    QGCLabel {
                        visible: !root.vehicle
                        text:    qsTr("No vehicle connected")
                    }
                }

                SettingsGroupLayout {
                    heading: qsTr("Vehicle Messages")

                    Loader {
                        id:              stateMsgLoader
                        active:          !!root.vehicle
                        sourceComponent: VehicleMessageList { visible: !noMessages }
                    }
                    QGCLabel {
                        text:    qsTr("No new vehicle messages")
                        visible: !stateMsgLoader.item || stateMsgLoader.item.noMessages
                    }
                }
            }
        }
    }

    Component {
        id: gnssDrawerComponent
        GPSIndicatorPage { }
    }

    Component {
        id: battDrawerComponent
        ToolIndicatorPage {
            showExpand: false
            contentComponent: SettingsGroupLayout {
                heading: qsTr("Battery Status")
                LabelledLabel { label: qsTr("Charge:");   labelText: root._batteryText() }
                LabelledLabel { label: qsTr("Voltage:");  labelText: root._factText(root._batt ? root._batt.voltage : null, " V") }
                LabelledLabel { label: qsTr("Current:");  labelText: root._factText(root._batt ? root._batt.current : null, " A") }
                LabelledLabel { label: qsTr("Consumed:"); labelText: root._factText(root._batt ? root._batt.mahConsumed : null, " mAh", 0) }
            }
        }
    }

    Component {
        id: linkDrawerComponent
        ToolIndicatorPage {
            showExpand: false
            contentComponent: SettingsGroupLayout {
                heading: qsTr("Link / Telemetry RSSI")
                LabelledLabel { label: qsTr("Local RSSI:");   labelText: root._factText(root._radio ? root._radio.lrssi : null, " dBm", 0) }
                LabelledLabel { label: qsTr("Remote RSSI:");  labelText: root._factText(root._radio ? root._radio.rrssi : null, " dBm", 0) }
                LabelledLabel { label: qsTr("RX Errors:");    labelText: root._factText(root._radio ? root._radio.rxErrors : null, "", 0) }
                LabelledLabel { label: qsTr("Errors Fixed:"); labelText: root._factText(root._radio ? root._radio.fixed : null, "", 0) }
            }
        }
    }
}
