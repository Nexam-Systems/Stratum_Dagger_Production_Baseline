import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM: vision-engagement status + abort overlay.
//
// Top-centre overlay that owns the operator-facing half of the safety loop during a
// CAMERA-GUIDED terminal run (custom sub_mode 23). It is the vision counterpart of
// EngagementAbortOverlay and is mutually exclusive with it (the vehicle is in either
// Engagement or Vision Engagement, never both):
//   * a blinking VISION ENGAGING! banner;
//   * the guidance panel (VisionEngagementStatus), driven by VISION_ENGAGEMENT_STATUS
//     (42002) -- lock state, range/closing, and the gated time-to-impact countdown;
//   * the SAME HOLD-TO-ABORT control as coordinate Engagement, wired to the SHARED
//     engagement controller's abort() (DO_SET_MODE sub=22). This is NOT a second abort
//     path -- it calls the one abort() the whole app uses (contract Task 5).
//
// The abort control is enabled whenever the vehicle is in Vision Engagement (ANY guidance
// state, including SEARCH and the vehicle's own self-ABORT) and is NEVER gated on a valid
// time-to-impact estimate -- abort must work while the countdown reads "computing".
Item {
    id: root

    property var  engagementController
    property real topMargin: 0

    property var  _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle

    // In the vision-engagement mode (sub 23), from the shared controller.
    readonly property bool _visionEngaged:
        !!engagementController && engagementController.visionEngaged

    readonly property string _abortModeName:
        engagementController ? engagementController.abortModeName : qsTr("Abort")
    readonly property bool _aborting:
        !!_activeVehicle && _activeVehicle.flightMode === _abortModeName

    // Live guidance state from VISION_ENGAGEMENT_STATUS (42002).
    readonly property var  _vs:       _activeVehicle ? _activeVehicle.visionEngagementStatus : null
    readonly property int  _vsState:  _vs ? _vs.state.rawValue : 0
    readonly property int  _stateAbort: 4

    // Abort is offered for the entire mode -- any guidance state -- and never depends on
    // a valid estimate. It stays live through the vehicle's own self-abort so the
    // operator can still command the recovery point.
    readonly property bool _abortEnabled: _visionEngaged

    // Recovery-complete confirmation, mirroring EngagementAbortOverlay: PX4 auto-switches
    // Abort -> Hold on reaching the recovery point; we surface a brief banner off that
    // transition. Shared abort path -> identical recovery behaviour.
    readonly property string _flightMode:    _activeVehicle ? _activeVehicle.flightMode : ""
    readonly property string _holdModeName:  _activeVehicle ? _activeVehicle.pauseFlightMode : qsTr("Hold")
    property string _prevFlightMode: ""
    property bool   _showRecovered:  false

    Component.onCompleted: _prevFlightMode = _flightMode

    on_FlightModeChanged: {
        if (_prevFlightMode === _abortModeName && _flightMode === _holdModeName) {
            _showRecovered = true
            recoveredTimer.restart()
        }
        _prevFlightMode = _flightMode
    }

    Timer {
        id:             recoveredTimer
        interval:       5000
        repeat:         false
        onTriggered:    root._showRecovered = false
    }

    visible:                    _visionEngaged || _showRecovered
    implicitWidth:              panel.implicitWidth
    implicitHeight:             panel.implicitHeight
    anchors.horizontalCenter:   parent.horizontalCenter
    anchors.top:                parent.top
    anchors.topMargin:          topMargin
    z:                          QGroundControl.zOrderTopMost

    QGCPalette { id: qgcPal }

    ColumnLayout {
        id:         panel
        spacing:    ScreenTools.defaultFontPixelHeight * 0.5

        // Blinking VISION ENGAGING! banner -- shown while in the mode and not
        // self-aborting (the panel covers the self-abort case).
        Rectangle {
            id:                 engagingBanner
            Layout.alignment:   Qt.AlignHCenter
            visible:            root._visionEngaged && root._vsState !== root._stateAbort
            implicitWidth:      engagingLabel.contentWidth + (ScreenTools.defaultFontPixelWidth * 4)
            implicitHeight:     engagingLabel.contentHeight + (ScreenTools.defaultFontPixelWidth * 2)
            radius:             ScreenTools.defaultBorderRadius
            color:              "#cc0000"
            border.color:       "white"
            border.width:       2

            QGCLabel {
                id:                 engagingLabel
                anchors.centerIn:   parent
                text:               qsTr("VISION ENGAGING!")
                color:              "white"
                font.bold:          true
                font.pointSize:     ScreenTools.largeFontPointSize
            }

            SequentialAnimation on opacity {
                running:    engagingBanner.visible
                loops:      Animation.Infinite
                NumberAnimation { from: 1.0;  to: 0.25; duration: 450 }
                NumberAnimation { from: 0.25; to: 1.0;  duration: 450 }
            }
        }

        // Guidance readout. Self-manages its content by guidance state; shown while in
        // the mode.
        VisionEngagementStatus {
            Layout.alignment:   Qt.AlignHCenter
            visible:            root._visionEngaged
            visionStatus:       root._activeVehicle ? root._activeVehicle.visionEngagementStatus : null
        }

        // HOLD-TO-ABORT control -- the SAME deliberate hold-to-fire control as coordinate
        // Engagement, calling the shared controller's abort() (DO_SET_MODE sub=22).
        QGCDelayButton {
            id:                 abortButton
            Layout.alignment:   Qt.AlignHCenter
            visible:            root._abortEnabled
            text:               qsTr("HOLD TO ABORT")
            delay:              1000
            onActivated: {
                if (root.engagementController) {
                    root.engagementController.abort()
                }
            }
        }

        // Recovery strip while in Abort mode.
        Rectangle {
            Layout.alignment:   Qt.AlignHCenter
            visible:            root._aborting && !root._visionEngaged
            implicitWidth:      abortingLabel.contentWidth + (ScreenTools.defaultFontPixelWidth * 4)
            implicitHeight:     abortingLabel.contentHeight + (ScreenTools.defaultFontPixelWidth * 2)
            radius:             ScreenTools.defaultBorderRadius
            color:              "#1E88E5"
            border.color:       "white"
            border.width:       2

            QGCLabel {
                id:                 abortingLabel
                anchors.centerIn:   parent
                text:               qsTr("ABORTING — RECOVERING")
                color:              "white"
                font.bold:          true
                font.pointSize:     ScreenTools.mediumFontPointSize
            }
        }

        // Transient "recovery complete" confirmation once PX4 auto-switches to Hold.
        Rectangle {
            Layout.alignment:   Qt.AlignHCenter
            visible:            root._showRecovered
            implicitWidth:      recoveredLabel.contentWidth + (ScreenTools.defaultFontPixelWidth * 4)
            implicitHeight:     recoveredLabel.contentHeight + (ScreenTools.defaultFontPixelWidth * 2)
            radius:             ScreenTools.defaultBorderRadius
            color:              "#43A047"
            border.color:       "white"
            border.width:       2

            QGCLabel {
                id:                 recoveredLabel
                anchors.centerIn:   parent
                text:               qsTr("ABORTED — BACK TO STANDOFF")
                color:              "white"
                font.bold:          true
                font.pointSize:     ScreenTools.mediumFontPointSize
            }
        }
    }
}
