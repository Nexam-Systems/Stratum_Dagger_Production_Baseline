import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QtLocation
import QtPositioning
import QtQuick.Window
import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.Toolbar
import QGroundControl.Viewer3D

Item {
    id: _root

    readonly property bool _is3DMode:       QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D
    readonly property bool _keepSceneAlive: QGroundControl.settingsManager.viewer3DSettings.keepSceneAlive.rawValue

    // STRATUM: active vehicle profile (1 = Dropper, 2 = Dagger). Gates profile-specific UI
    // such as the on-video camera-control overlays.
    readonly property bool _stratumIsDropper: QGroundControl.settingsManager.appSettings.stratumProfile.rawValue === 1
    readonly property bool _stratumIsDagger:  QGroundControl.settingsManager.appSettings.stratumProfile.rawValue === 2

    // These should only be used by MainRootWindow
    property var planController:    _planController
    property var guidedController:  _guidedController

    PlanMasterController {
        id:                     _planController
        flyView:                true
        Component.onCompleted:  start()
    }

    // STRATUM: shared engagement/abort safety-loop controller. Reached by the Engage
    // trigger (down the tool-strip chain) and the Abort control + countdown overlay
    // below, so both act on one piece of arming/destination state.
    EngagementController {
        id: engagementController
    }

    // STRATUM: joystick safety-critical combos. When two buttons are assigned to the
    // "Engage" action (or the "Abort" action) the joystick's multi-button-combo path
    // only fires the signal when BOTH buttons are pressed together. Both signals route
    // to EngagementController so joystick engage/abort behave exactly like the on-screen
    // controls (arm-on-engage safety, ABRT_* param push, etc).
    Connections {
        target: joystickManager.activeJoystick
        ignoreUnknownSignals: true
        function onStratumEngageRequested() { engagementController.engage() }
        function onStratumAbortRequested()  { engagementController.abort() }
    }

    // STRATUM: low-battery RTL safety monitor. While armed, if the battery pack voltage
    // stays at or below the configured threshold (flyViewSettings.lowBatteryRTLVoltage,
    // 0 = disabled) continuously for _holdSeconds, prompt the operator to send an RTL.
    // The sustained window rejects momentary voltage sag/spikes, so a single dip does not
    // trigger the prompt. Re-prompting is suppressed until the voltage recovers above the
    // threshold, to avoid spamming the operator who chose not to return.
    Item {
        id: lowBatteryRTLMonitor

        readonly property int  _holdSeconds: 20
        readonly property var  _vehicle:     QGroundControl.multiVehicleManager.activeVehicle
        readonly property real _threshold:   QGroundControl.settingsManager.flyViewSettings.lowBatteryRTLVoltage.rawValue
        readonly property var  _battery:     (_vehicle && _vehicle.batteries.count > 0) ? _vehicle.batteries.get(0) : null
        readonly property real _voltage:     _battery ? _battery.voltage.rawValue : Number.NaN
        readonly property bool _monitorOn:   !!_vehicle && _vehicle.armed && _threshold > 0

        property int  _secondsBelow: 0
        property bool _prompted:     false

        function _isBelowThreshold() {
            return !isNaN(_voltage) && _voltage > 0 && _voltage <= _threshold
        }

        function _promptRTL() {
            if (!_vehicle) {
                return
            }
            QGroundControl.showMessageDialog(
                mainWindow,
                qsTr("Low Battery"),
                qsTr("Battery voltage (%1 V) has stayed at or below the %2 V threshold for %3 s. Send RTL (Return To Launch)?")
                    .arg(_voltage.toFixed(2)).arg(_threshold.toFixed(2)).arg(_holdSeconds),
                Dialog.Yes | Dialog.No,
                function() {
                    if (lowBatteryRTLMonitor._vehicle) {
                        lowBatteryRTLMonitor._vehicle.guidedModeRTL(false)
                    }
                })
        }

        Timer {
            interval:   1000
            repeat:     true
            running:    lowBatteryRTLMonitor._monitorOn
            // Reset the window/prompt whenever monitoring starts or stops (arm, disarm,
            // vehicle change, or the feature being enabled/disabled).
            onRunningChanged: {
                lowBatteryRTLMonitor._secondsBelow = 0
                lowBatteryRTLMonitor._prompted = false
            }
            onTriggered: {
                if (lowBatteryRTLMonitor._isBelowThreshold()) {
                    lowBatteryRTLMonitor._secondsBelow++
                    if (lowBatteryRTLMonitor._secondsBelow >= lowBatteryRTLMonitor._holdSeconds && !lowBatteryRTLMonitor._prompted) {
                        lowBatteryRTLMonitor._prompted = true
                        lowBatteryRTLMonitor._promptRTL()
                    }
                } else {
                    // Voltage recovered above threshold: reset the window and re-arm the prompt.
                    lowBatteryRTLMonitor._secondsBelow = 0
                    lowBatteryRTLMonitor._prompted = false
                }
            }
        }
    }

    property bool   _mainWindowIsMap:       mapControl.pipState.state === mapControl.pipState.fullState
    property bool   _isFullWindowItemDark:  _mainWindowIsMap ? mapControl.isSatelliteMap : true
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _missionController:     _planController.missionController
    property var    _geoFenceController:    _planController.geoFenceController
    property var    _rallyPointController:  _planController.rallyPointController
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2
    property var    _guidedController:      guidedActionsController
    property var    _guidedValueSlider:     guidedValueSlider
    property var    _widgetLayer:           widgetLayer
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property rect   _centerViewport:        Qt.rect(0, 0, width, height)
    property real   _rightPanelWidth:       ScreenTools.defaultFontPixelWidth * 30
    property var    _mapControl:            mapControl
    property real   _widgetMargin:          ScreenTools.defaultFontPixelWidth * 0.75

    property real   _fullItemZorder:    0
    property real   _pipItemZorder:     QGroundControl.zOrderWidgets

    // STRATUM: true when the video (camera) is the maximized window rather than the
    // map. Drives the on-video camera-control overlay and tells the dropper panel to
    // fold its camera controls away (they live on the video instead). See req. 4.
    readonly property bool _cameraMaximized: QGroundControl.videoManager.hasVideo &&
                                             videoControl.pipState.state === videoControl.pipState.fullState

    function _calcCenterViewPort() {
        var newToolInset = Qt.rect(0, 0, width, height)
        toolstrip.adjustToolInset(newToolInset)
    }

    function dropMainStatusIndicatorTool() {
        toolbar.dropMainStatusIndicatorTool();
    }

    QGCToolInsets {
        id:                     _toolInsets
        topEdgeLeftInset:       toolbar.height
        topEdgeCenterInset:     topEdgeLeftInset
        topEdgeRightInset:      topEdgeLeftInset
        leftEdgeBottomInset:    _pipView.leftEdgeBottomInset
        bottomEdgeLeftInset:    _pipView.bottomEdgeLeftInset
    }

    Item {
        id:                 mapHolder
        anchors.fill:       parent

        FlyViewMap {
            id:                     mapControl
            planMasterController:   _planController
            rightPanelWidth:        ScreenTools.defaultFontPixelHeight * 9
            pipView:                _pipView
            pipMode:                !_mainWindowIsMap
            toolInsets:             customOverlay.totalToolInsets
            mapName:                "FlightDisplayView"
            enabled:                !_is3DMode
            visible:                !_is3DMode
        }

        FlyViewVideo {
            id:         videoControl
            pipView:    _pipView
        }

        PipView {
            id:                     _pipView
            anchors.left:           parent.left
            anchors.bottom:         parent.bottom
            anchors.margins:        _toolsMargin
            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1:                  mapControl
            item2:                  QGroundControl.videoManager.hasVideo ? videoControl : null
            show:                   QGroundControl.videoManager.hasVideo && !QGroundControl.videoManager.fullScreen &&
                                        (videoControl.pipState.state === videoControl.pipState.pipState || mapControl.pipState.state === mapControl.pipState.pipState)
            z:                      QGroundControl.zOrderWidgets

            property real leftEdgeBottomInset: visible ? width + anchors.margins : 0
            property real bottomEdgeLeftInset: visible ? height + anchors.margins : 0
        }

        FlyViewWidgetLayer {
            id:                     widgetLayer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            anchors.margins:        _widgetMargin
            anchors.topMargin:      toolbar.height + _widgetMargin
            z:                      _fullItemZorder + 2
            parentToolInsets:       _toolInsets
            mapControl:             _mapControl
            engagementController:   engagementController
            cameraMaximized:        _cameraMaximized
            standoffController:     mapControl.standoffCmdController
            visible:                !QGroundControl.videoManager.fullScreen
        }

        FlyViewCustomLayer {
            id:                 customOverlay
            anchors.fill:       widgetLayer
            z:                  _fullItemZorder + 2
            parentToolInsets:   widgetLayer.totalToolInsets
            mapControl:         _mapControl
            visible:            !QGroundControl.videoManager.fullScreen
        }

        // STRATUM: camera / gimbal controls overlaid on the live video when the camera
        // is the maximized window. Lives in mapHolder (not the widget layer) so it stays
        // visible in full-screen video, where the widget layer is hidden. When the map is
        // maximized this hides and the same controls fold back into the dropper panel's
        // camera section (req. 4).
        FlyViewCameraControls {
            id:                     videoCameraOverlay
            overlayMode:            true
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin:    _toolsMargin
            width:                  ScreenTools.defaultFontPixelWidth * 24
            z:                      QGroundControl.zOrderWidgets + 1
            visible:                _cameraMaximized && _stratumIsDropper
        }

        // STRATUM: Dagger camera-control overlay. Wraps a segmented A2 mini / C12
        // selector; the selected camera drives both the RTSP feed and the control cluster.
        FlyViewCameraControlsDaggerRoot {
            id:                     videoCameraOverlayDagger
            overlayMode:            true
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin:    _toolsMargin
            width:                  ScreenTools.defaultFontPixelWidth * 24
            z:                      QGroundControl.zOrderWidgets + 1
            visible:                _cameraMaximized && _stratumIsDagger
        }

        // Development tool for visualizing the insets for a paticular layer, show if needed
        FlyViewInsetViewer {
            id:                     widgetLayerInsetViewer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            z:                      widgetLayer.z + 1
            insetsToView:           widgetLayer.totalToolInsets
            visible:                false
        }

        GuidedActionsController {
            id:                 guidedActionsController
            missionController:  _missionController
            guidedValueSlider:     _guidedValueSlider
            // STRATUM: required by actionPnEngage so the abort destination is armed
            // before PN Engagement is commanded. Without this binding the controller
            // falls back to a direct mode set with no abort destination guaranteed.
            engagementController:  engagementController
        }

        //-- Guided value slider (e.g. altitude)
        GuidedValueSlider {
            id:                 guidedValueSlider
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            anchors.topMargin:  toolbar.height
            z:                  QGroundControl.zOrderTopMost
            visible:            false
        }

        QGCPalette { id: qgcPal }

        // STRATUM: guided-action confirm bar, relocated from the top toolbar to the
        // bottom edge for ergonomic reach. Hosts the slide-to-confirm control used to
        // accept guided / flight-mode command changes. The message display and its
        // fade timer/animation are kept co-located in this same document so the
        // GuidedActionConfirm internals resolve their ids exactly as before.
        Item {
            id:                         guidedActionConfirmBottomBar
            anchors.bottom:             parent.bottom
            anchors.bottomMargin:       _toolsMargin
            anchors.horizontalCenter:   parent.horizontalCenter
            width:                      guidedActionConfirmBottom.width + (_toolsMargin * 2)
            height:                     ScreenTools.toolbarHeight
            visible:                    guidedActionConfirmBottom.visible
            z:                          QGroundControl.zOrderTopMost

            Rectangle {
                anchors.fill:   parent
                color:          qgcPal.window
                opacity:        0.85
                radius:         ScreenTools.defaultBorderRadius
            }

            GuidedActionConfirm {
                id:                 guidedActionConfirmBottom
                anchors.centerIn:   parent
                height:             parent.height
                guidedController:   _guidedController
                guidedValueSlider:  _guidedValueSlider
                messageDisplay:     guidedActionMessageDisplay
            }
        }

        // Message display floats just above the bottom confirm bar. Defined here (not
        // inside GuidedActionConfirm) so it is not clipped by the bar. Its opacity is
        // driven by GuidedActionConfirm's own fade timer/animation (which target this
        // rectangle through the messageDisplay property).
        Rectangle {
            id:                         guidedActionMessageDisplay
            anchors.bottom:             guidedActionConfirmBottomBar.top
            anchors.bottomMargin:       _margins
            anchors.horizontalCenter:   guidedActionConfirmBottomBar.horizontalCenter
            width:                      messageLabel.contentWidth + (_margins * 2)
            height:                     messageLabel.contentHeight + (_margins * 2)
            color:                      qgcPal.windowTransparent
            radius:                     ScreenTools.defaultBorderRadius
            visible:                    guidedActionConfirmBottom.visible
            z:                          QGroundControl.zOrderTopMost

            QGCLabel {
                id:         messageLabel
                x:          _margins
                y:          _margins
                width:      ScreenTools.defaultFontPixelWidth * 30
                wrapMode:   Text.WordWrap
                text:       guidedActionConfirmBottom.message
            }
        }

        // STRATUM: engagement status + abort overlay. Top-centre of the flight view
        // (below the toolbar), above all map widgets so it cannot be missed. Carries
        // the blinking ENGAGING! banner, the time-to-impact countdown, and the
        // HOLD-TO-ABORT control. Driven by the shared engagement/abort controller.
        EngagementAbortOverlay {
            id:                     engagementAbortOverlay
            engagementController:    engagementController
            topMargin:               toolbar.height + (_toolsMargin * 3)
        }

        // STRATUM: vision-engagement status + abort overlay. Same top-centre slot as the
        // coordinate-engagement overlay above; the two are mutually exclusive by mode, so
        // only one is ever visible. Carries the VISION ENGAGING! banner, the 42002-driven
        // guidance panel, and the SHARED HOLD-TO-ABORT control (contract Task 5 -- one
        // abort path, not a fork).
        VisionEngagementOverlay {
            id:                     visionEngagementOverlay
            engagementController:    engagementController
            topMargin:               toolbar.height + (_toolsMargin * 3)
        }

        Loader {
            id:           viewer3DLoader
            z:            1
            anchors.fill: parent
            visible:      _is3DMode
        }

        Connections {
            target: QGCViewer3DManager
            function onDisplayModeChanged() {
                if (QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D) {
                    if (!viewer3DLoader.item) {
                        viewer3DLoader.setSource(
                            "qrc:/qml/QGroundControl/Viewer3D/Models3D/Viewer3DModel.qml",
                            { missionController: Qt.binding(() => _missionController) }
                        )
                    }
                } else if (!_keepSceneAlive) {
                    viewer3DLoader.source = ""
                }
            }
        }

        // STRATUM: map click "Set standoff here" -> open the Set Standoff panel
        // pre-filled with the clicked coordinate (same panel as the ribbon button).
        Connections {
            target: mapControl
            function onSetStandoffHereRequested(coordinate) {
                widgetLayer.openStandoffWithTarget(coordinate)
            }
        }
    }

    FlyViewToolBar {
        id:                 toolbar
        guidedValueSlider:  _guidedValueSlider
        visible:            !QGroundControl.videoManager.fullScreen

        // STRATUM: AOP / standoff entry commands relocated to the ribbon centre; route
        // them to the widget layer that owns the standoff panel and the AOP map editor.
        onDefineAOP:   widgetLayer.startAOP()
        onSetStandoff: widgetLayer.toggleStandoff()
    }
}
