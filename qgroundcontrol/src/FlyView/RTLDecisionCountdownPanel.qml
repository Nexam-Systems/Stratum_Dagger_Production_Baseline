import QtQuick
import QtQuick.Layouts

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

    implicitWidth:  210
    implicitHeight: contentCol.implicitHeight + 16
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
        return (watts === undefined || isNaN(watts)) ? "--" : (watts / 1000).toFixed(1) + " kW"
    }
    function _kmh(ms) {
        return (ms === undefined || isNaN(ms)) ? "--" : Math.round(ms * 3.6) + " km/h"
    }
    function _wh(value) {
        return (value === undefined || isNaN(value)) ? "--" : (value >= 0 ? "+" : "") + Math.round(value) + " Wh"
    }
    function _statusText() {
        switch (_status) {
        case "UNKNOWN":        return qsTr("PNR UNKNOWN — TELEMETRY / HOME / MODEL")
        case "PNR_REACHED":    return qsTr("PNR REACHED — ESTIMATED")
        case "BEYOND_HORIZON": return qsTr("PNR BEYOND PREDICTION HORIZON")
        case "VALIDATED":      return qsTr("VALIDATED")
        default:               return qsTr("ESTIMATED — UNCALIBRATED")
        }
    }

    ColumnLayout {
        id: contentCol
        anchors.fill:    parent
        anchors.margins: 8
        spacing:         2

        QGCLabel {
            Layout.fillWidth: true
            font.bold:        true
            text:             qsTr("RTL DECISION COUNTDOWN")
        }

        QGCLabel {
            objectName:            "pnrCountdown"
            Layout.fillWidth:      true
            Layout.topMargin:      2
            horizontalAlignment:   Text.AlignHCenter
            color:                 root._accentColor
            font.pointSize:        ScreenTools.largeFontPointSize
            font.bold:             true
            text:                  root._hasTimer ? root._clock(root._seconds) : "--:--"
        }
        QGCLabel {
            objectName:          "pnrStatus"
            Layout.fillWidth:    true
            horizontalAlignment: Text.AlignHCenter
            wrapMode:            Text.WordWrap
            color:               root._accentColor
            text:                root._statusText()
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: panelPalette.groupBorder }

        GridLayout {
            Layout.fillWidth: true
            columns:          2
            columnSpacing:    8
            rowSpacing:       1

            QGCLabel { text: qsTr("LIMIT") }
            QGCLabel { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: root._reason }
            QGCLabel { text: qsTr("HOME") }
            QGCLabel { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: estimator ? root._km(estimator.distanceFromHomeM) : "--" }
            QGCLabel { text: qsTr("POWER") }
            QGCLabel { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: estimator ? root._kw(estimator.filteredPowerW) : "--" }
            QGCLabel { text: qsTr("SPEED") }
            QGCLabel { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: estimator ? root._kmh(estimator.groundSpeedMS) : "--" }
            QGCLabel { text: qsTr("RTL TIME") }
            QGCLabel { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: estimator ? root._clock(estimator.rtlEstimatedTimeSeconds) : "--" }
            QGCLabel { text: qsTr("MARGIN") }
            QGCLabel { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: estimator ? root._wh(estimator.energyMarginWh) : "--" }
        }

        QGCLabel {
            Layout.fillWidth: true
            text:             estimator ? qsTr("MISSION LIMIT: %1 total").arg(root._km(estimator.totalDistanceLimitM)) : ""
        }

        QGCLabel {
            objectName:       "pnrBatteryWarning"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode:         Text.WordWrap
            visible:          estimator && estimator.batteryCritical
            color:            root._criticalColor
            font.bold:        true
            text:             qsTr("PX4 BATTERY CRITICAL")
        }
    }
}
