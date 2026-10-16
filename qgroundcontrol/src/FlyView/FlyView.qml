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

    // STRATUM: camera controls dock to the left only while the video is maximized.
    readonly property bool _cameraMaximized: QGroundControl.videoManager.hasVideo &&
                                             videoControl.pipState.state === videoControl.pipState.fullState
    property bool _cameraControlsExpanded: true
    readonly property bool _showRightPanel: !QGroundControl.videoManager.fullScreen
    readonly property real _dockWidth: _showRightPanel ? widgetLayer.commandPanelWidth + _widgetMargin * 2 : 0
    on_CameraMaximizedChanged: _cameraControlsExpanded = true

    function _calcCenterViewPort() {
        _centerViewport = Qt.rect(0, toolbar.height, Math.max(0, width - _dockWidth), Math.max(0, height - toolbar.height))
    }

    function dropMainStatusIndicatorTool() {
        toolbar.dropMainStatusIndicatorTool();
    }

    QGCToolInsets {
        id:                     _toolInsets
        topEdgeLeftInset:       toolbar.height
        topEdgeCenterInset:     topEdgeLeftInset
        topEdgeRightInset:      topEdgeLeftInset
        leftEdgeBottomInset:    0
        bottomEdgeLeftInset:    0
    }

    Item {
        id:                 mapHolder
        anchors.fill:       parent

        Item {
            id: flightSurface
            anchors.fill: parent
            anchors.topMargin: QGroundControl.videoManager.fullScreen ? 0 : toolbar.height
            anchors.rightMargin: _root._dockWidth
        }

        FlyViewMap {
            id:                     mapControl
            parent:                 flightSurface
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
            parent:     flightSurface
            pipView:    _pipView
        }

        PipView {
            id:                     _pipView
            parent:                 widgetLayer.previewSlot
            anchors.centerIn:       parent
            docked:                 true
            fullItemParent:         flightSurface
            width:                  parent.width
            height:                 width * 9 / 16
            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1:                  mapControl
            item2:                  QGroundControl.videoManager.hasVideo ? videoControl : null
            show:                   _root._showRightPanel && QGroundControl.videoManager.hasVideo && !QGroundControl.videoManager.fullScreen &&
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
            panelExpanded:          _root._showRightPanel
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

        Component {
            id: dropperCameraComponent
            FlyViewCameraControls { compact: true }
        }

        Component {
            id: daggerCameraComponent
            FlyViewCameraControlsDaggerRoot { compact: true }
        }

        Rectangle {
            id: cameraControlsCard
            anchors.left: flightSurface.left
            anchors.leftMargin: 8
            anchors.verticalCenter: flightSurface.verticalCenter
            width: Math.min(176, flightSurface.width * 0.22)
            height: Math.min(flightSurface.height - 16, Math.max(180, cameraControlsScroll.contentHeight + 16))
            visible: _root._cameraMaximized && _root._cameraControlsExpanded && !QGroundControl.videoManager.fullScreen
            color: qgcPal.highContrast ? qgcPal.window : Qt.rgba(qgcPal.window.r, qgcPal.window.g, qgcPal.window.b, 0.84)
            border.color: qgcPal.groupBorder
            border.width: 1
            radius: 4
            clip: true
            z: QGroundControl.zOrderTopMost

            ScrollView {
                id: cameraControlsScroll
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: cameraControlsScroll.availableWidth
                    spacing: 6

                    QGCLabel {
                        Layout.fillWidth: true
                        text: qsTr("CAMERA CONTROLS")
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }

                    Loader {
                        id: cameraControlsLoader
                        Layout.fillWidth: true
                        active: _root._cameraMaximized && _root._cameraControlsExpanded
                        sourceComponent: _stratumIsDagger ? daggerCameraComponent : dropperCameraComponent
                    }
                }
            }
        }

        QGCButton {
            anchors.left: _root._cameraControlsExpanded ? cameraControlsCard.right : flightSurface.left
            anchors.leftMargin: _root._cameraControlsExpanded ? 2 : 8
            anchors.verticalCenter: flightSurface.verticalCenter
            width: 36
            height: 64
            visible: _root._cameraMaximized && !QGroundControl.videoManager.fullScreen
            z: QGroundControl.zOrderTopMost + 1
            Accessible.name: _root._cameraControlsExpanded ? qsTr("Hide camera controls") : qsTr("Show camera controls")
            ToolTip.visible: hovered
            ToolTip.text: Accessible.name
            contentItem: Item {
                QGCColoredImage {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    sourceSize.height: height
                    fillMode: Image.PreserveAspectFit
                    source: _root._cameraControlsExpanded ? "/InstrumentValueIcons/cheveron-left.svg" : "/InstrumentValueIcons/cheveron-right.svg"
                    color: qgcPal.buttonText
                }
            }
            onClicked: _root._cameraControlsExpanded = !_root._cameraControlsExpanded
        }

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: toolbar.height + 8
            anchors.horizontalCenter: flightSurface.horizontalCenter
            width: Math.min(420, flightSurface.width - 24)
            height: 60
            z: QGroundControl.zOrderTopMost + 2
            visible: widgetLayer.holdCommand !== ""
            color: qgcPal.window
            border.color: qgcPal.warningText
            border.width: 2
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                QGCLabel { text: widgetLayer.holdComplete ? qsTr("%1 request sent").arg(widgetLayer.holdCommand) : qsTr("Hold to %1").arg(widgetLayer.holdCommand) }
                ProgressBar { Layout.fillWidth: true; value: widgetLayer.holdProgress }
            }
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
            topMargin:               toolbar.height + (widgetLayer.holdCommand !== "" ? 80 : _toolsMargin * 3)
        }

        // STRATUM: vision-engagement status + abort overlay. Same top-centre slot as the
        // coordinate-engagement overlay above; the two are mutually exclusive by mode, so
        // only one is ever visible. Carries the VISION ENGAGING! banner, the 42002-driven
        // guidance panel, and the SHARED HOLD-TO-ABORT control (contract Task 5 -- one
        // abort path, not a fork).
        VisionEngagementOverlay {
            id:                     visionEngagementOverlay
            engagementController:    engagementController
            topMargin:               toolbar.height + (widgetLayer.holdCommand !== "" ? 80 : _toolsMargin * 3)
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
        pendingTarget:      mapControl._standoffPendingCoordinate
        designatedTarget:   mapControl.standoffCmdController._targetCoordinate

        // STRATUM: AOP / standoff entry commands relocated to the ribbon centre; route
        // them to the widget layer that owns the standoff panel and the AOP map editor.
        onDefineAOP:   widgetLayer.startAOP()
        onSetStandoff: widgetLayer.toggleStandoff()
    }
}
