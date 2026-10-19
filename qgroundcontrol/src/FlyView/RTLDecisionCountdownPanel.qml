import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM Issue #4 / Phase 0: compact Fly View overlay for the RTL Point-of-No-Return
// decision countdown. Bound to an RTLPointOfNoReturnEstimator. The countdown is advisory
// and clearly labelled UNCALIBRATED until flight-validated; RTL always stays available.
Rectangle {
    id: root

    property var estimator
    property int warnSeconds:     120
    property int criticalSeconds: 60

    readonly property int    _seconds:  estimator ? estimator.pnrCountdownSeconds : -1
    readonly property string _status:   estimator ? estimator.pnrStatus : "UNKNOWN"
    readonly property string _reason:   estimator ? estimator.pnrReason : "NONE"
    readonly property bool   _hasTimer: _seconds >= 0

    readonly property color _normalColor:  "#79CBE8"
    readonly property color _warnColor:     "#F2C200"
    readonly property color _criticalColor: "#EF5350"
    readonly property color _accentColor: {
        if (_status === "PNR_REACHED" || estimator && estimator.batteryCritical) return _criticalColor
        if (!_hasTimer) return _normalColor
        if (_seconds <= criticalSeconds) return _criticalColor
        if (_seconds <= warnSeconds) return _warnColor
        return _normalColor
    }

    implicitWidth:  barRow.implicitWidth + 20
    implicitHeight: barRow.implicitHeight + 10
    radius:         4
    border.width:   1
    border.color:   _accentColor
    color:          panelPalette.highContrast ? panelPalette.window
                                              : Qt.rgba(panelPalette.window.r, panelPalette.window.g, panelPalette.window.b, 0.85)
    visible:        !!estimator

    QGCPalette { id: panelPalette }

    function _clock(seconds) {
        if (seconds === undefined || seconds < 0)
            return "--:--"
        var mm = Math.floor(seconds / 60)
        var ss = Math.floor(seconds % 60)
        return (mm < 10 ? "0" : "") + mm + ":" + (ss < 10 ? "0" : "") + ss
    }
    function _km(meters) {
        return (meters === undefined || isNaN(meters)) ? "--" : (meters / 1000).toFixed(1) + " km"
    }
    function _kw(watts) {
        if (watts === undefined || isNaN(watts))
            return "--"
        return watts < 1000 ? Math.round(watts) + " W" : (watts / 1000).toFixed(1) + " kW"
    }
    function _kmh(ms) {
        return (ms === undefined || isNaN(ms)) ? "--" : Math.round(ms * 3.6) + " km/h"
    }
    function _wh(value) {
        return (value === undefined || isNaN(value)) ? "--" : (value >= 0 ? "+" : "") + Math.round(value) + " Wh"
    }
    function _statusText() {
        switch (_status) {
        case "UNKNOWN":        return qsTr("PNR UNKNOWN")
        case "PNR_REACHED":    return qsTr("PNR REACHED — ESTIMATED")
        case "BEYOND_HORIZON": return qsTr("BEYOND HORIZON")
        case "VALIDATED":      return qsTr("VALIDATED")
        default:               return qsTr("ESTIMATED — UNCALIBRATED")
        }
    }

    // Inline "KEY value" cell used for each metric in the bar.
    component Field: Row {
        id: field
        property string key
        property string value
        spacing: 4
        QGCLabel { text: field.key; opacity: 0.6 }
        QGCLabel { text: field.value }
    }

    RowLayout {
        id: barRow
        anchors.centerIn: parent
        spacing: 12

        QGCLabel { text: qsTr("RTL PNR"); font.bold: true }
        QGCLabel {
            objectName:     "pnrCountdown"
            color:          root._accentColor
            font.bold:      true
            font.pointSize: ScreenTools.mediumFontPointSize
            text:           root._hasTimer ? root._clock(root._seconds) : "--:--"
        }
        QGCLabel {
            objectName: "pnrStatus"
            color:      root._accentColor
            text:       root._statusText()
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight:     true
            Layout.topMargin:      3
            Layout.bottomMargin:   3
            color:                 panelPalette.groupBorder
        }

        Field { key: qsTr("LIMIT");  value: root._reason }
        Field { key: qsTr("HOME");   value: estimator ? root._km(estimator.distanceFromHomeM) : "--" }
        Field { key: qsTr("POWER");  value: estimator ? root._kw(estimator.filteredPowerW) : "--" }
        Field { key: qsTr("SPEED");  value: estimator ? root._kmh(estimator.groundSpeedMS) : "--" }
        Field { key: qsTr("RTL");    value: estimator ? root._clock(estimator.rtlEstimatedTimeSeconds) : "--" }
        Field { key: qsTr("MARGIN"); value: estimator ? root._wh(estimator.energyMarginWh) : "--" }
        Field { key: qsTr("MAX");    value: estimator ? root._km(estimator.totalDistanceLimitM) : "--" }

        QGCLabel {
            objectName: "pnrBatteryWarning"
            visible:    estimator && estimator.batteryCritical
            color:      root._criticalColor
            font.bold:  true
            text:       qsTr("PX4 BATTERY CRITICAL")
        }
    }
}
