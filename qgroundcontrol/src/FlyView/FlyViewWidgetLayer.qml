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
import QGroundControl.Viewer3D

// This is the ui overlay layer for the widgets/tools for Fly View
Item {
    id: _root

    property var    parentToolInsets
    property var    totalToolInsets:        _totalToolInsets
    property var    mapControl
    property var    engagementController    // STRATUM: forwarded to the Engage trigger
    property bool   cameraMaximized:        false   // STRATUM: video is the maximized window
    property var    standoffController              // STRATUM: forwarded to the dropper drop check

    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _planMasterController:  globals.planMasterControllerFlyView
    property var    _missionController:     _planMasterController.missionController
    property var    _geoFenceController:    _planMasterController.geoFenceController
    property var    _rallyPointController:  _planMasterController.rallyPointController
    property var    _guidedController:      globals.guidedControllerFlyView
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property rect   _centerViewport:        Qt.rect(0, 0, width, height)
    property real   _rightPanelWidth:       ScreenTools.defaultFontPixelWidth * 30
    property real   _layoutMargin:          ScreenTools.defaultFontPixelWidth * 0.75
    property bool   _layoutSpacing:         ScreenTools.defaultFontPixelWidth
    property bool   _showSingleVehicleUI:   true

    // STRATUM: AOP edit + standoff-entry actions were relocated to the top ribbon
    // (FlyViewToolBar). These functions keep the logic here (where the standoff panel
    // and the AOP map editor live) and are invoked from FlyView.qml's ribbon wiring.
    function startAOP() {
        standoffPanel.close()
        mapControl.startAOPEdit()
    }
    function toggleStandoff() {
        standoffPanel.toggle()
    }

    // STRATUM: opens the Set Standoff panel (if not already visible) and pre-fills
    // the target lat/lon fields with the coordinate the operator picked from the map
    // click menu. The panel's own textChanged handlers push the pending marker.
    function openStandoffWithTarget(coordinate) {
        if (!coordinate || !coordinate.isValid) {
            return
        }
        if (!standoffPanel.visible) {
            standoffPanel.open()
        }
        standoffLatField.text = coordinate.latitude.toFixed(7)
        standoffLonField.text = coordinate.longitude.toFixed(7)
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    // STRATUM: AOP edit-mode action bar. Shown only while defining the Area of
    // Operations. "Apply changes" is present only when a vehicle is connected,
    // because committing the boundary uploads it to the vehicle as an inclusion
    // geofence; with no vehicle the operator can still lay out and lock the AOP.
    Rectangle {
        id:                         aopEditBar
        visible:                    mapControl && mapControl._aopEditMode
        z:                          QGroundControl.zOrderTopMost
        anchors.horizontalCenter:   parent.horizontalCenter
        anchors.top:                parent.top
        anchors.topMargin:          parentToolInsets.topEdgeCenterInset + _toolsMargin * 2
        radius:                     _margins
        color:                      qgcPal.window
        border.color:               qgcPal.groupBorder
        border.width:               1
        width:                      aopBarColumn.width + _toolsMargin * 4
        height:                     aopBarColumn.height + _toolsMargin * 2

        ColumnLayout {
            id:                 aopBarColumn
            anchors.centerIn:   parent
            spacing:            _toolsMargin

            RowLayout {
                id:                 aopBarRow
                Layout.alignment:   Qt.AlignHCenter
                spacing:            _toolsMargin * 2

                QGCLabel {
                    text:       qsTr("Defining Area of Operations")
                    font.bold:  true
                }

                QGCButton {
                    text:       qsTr("Cancel")
                    onClicked:  mapControl.cancelAOPEdit()
                }

                QGCButton {
                    text:       qsTr("Apply changes")
                    primary:    true
                    visible:    _activeVehicle !== null
                    onClicked:  mapControl.applyAOPEdit()
                }
            }

            // STRATUM: amber warning shown while no vehicle is connected. The AOP can
            // be laid out offline, but it only commits as an inclusion geofence once a
            // vehicle link exists - hence there is deliberately no Apply button above
            // until a vehicle connects. This bar tells the operator exactly that.
            Rectangle {
                id:                 aopNoVehicleWarning
                Layout.alignment:   Qt.AlignHCenter
                visible:            _activeVehicle === null
                width:              aopWarningLabel.width + _toolsMargin * 3
                height:             aopWarningLabel.height + _toolsMargin * 1.5
                radius:             _margins / 2
                color:              "#F2C200"

                QGCLabel {
                    id:                     aopWarningLabel
                    anchors.centerIn:       parent
                    width:                  ScreenTools.defaultFontPixelWidth * 42
                    wrapMode:               Text.WordWrap
                    horizontalAlignment:    Text.AlignHCenter
                    color:                  "black"
                    text:                   qsTr("No vehicle connected. This AOP is being laid out locally and will be uploaded as an inclusion geofence once a vehicle is connected.")
                }
            }

            // STRATUM: red warning shown when the last Apply was rejected because at
            // least one AOP vertex sat farther than the "Max AOP Distance" setting
            // (Application Settings -> General -> STRATUM Operational Limits) from the
            // enforcement anchor (vehicle home / vehicle / map centre).
            Rectangle {
                id:                 aopRangeRejectWarning
                Layout.alignment:   Qt.AlignHCenter
                visible:            mapControl && mapControl._aopRangeReject
                width:              aopRangeRejectLabel.width + _toolsMargin * 3
                height:             aopRangeRejectLabel.height + _toolsMargin * 1.5
                radius:             _margins / 2
                color:              "#EF5350"

                QGCLabel {
                    id:                     aopRangeRejectLabel
                    anchors.centerIn:       parent
                    width:                  ScreenTools.defaultFontPixelWidth * 46
                    wrapMode:               Text.WordWrap
                    horizontalAlignment:    Text.AlignHCenter
                    color:                  "white"
                    text:                   qsTr("Apply rejected: one or more AOP vertices are farther than the configured Max AOP Distance (%1 m). Pull the outer vertices inward and try again.")
                                                .arg(Math.round(QGroundControl.settingsManager.flyViewSettings.maxAOPDistance.rawValue))
                }
            }
        }
    }

    QGCToolInsets {
        id:                     _totalToolInsets
        leftEdgeTopInset:       toolStrip.leftEdgeTopInset
        leftEdgeCenterInset:    toolStrip.leftEdgeCenterInset
        leftEdgeBottomInset:    virtualJoystickMultiTouch.visible ? virtualJoystickMultiTouch.leftEdgeBottomInset : parentToolInsets.leftEdgeBottomInset
        rightEdgeTopInset:      topRightPanel.rightEdgeTopInset
        rightEdgeCenterInset:   topRightPanel.rightEdgeCenterInset
        rightEdgeBottomInset:   bottomRightRowLayout.rightEdgeBottomInset
        topEdgeLeftInset:       toolStrip.topEdgeLeftInset
        topEdgeCenterInset:     mapScale.topEdgeCenterInset
        topEdgeRightInset:      topRightPanel.topEdgeRightInset
        bottomEdgeLeftInset:    virtualJoystickMultiTouch.visible ? virtualJoystickMultiTouch.bottomEdgeLeftInset : parentToolInsets.bottomEdgeLeftInset
        bottomEdgeCenterInset:  bottomRightRowLayout.bottomEdgeCenterInset
        bottomEdgeRightInset:   virtualJoystickMultiTouch.visible ? virtualJoystickMultiTouch.bottomEdgeRightInset : bottomRightRowLayout.bottomEdgeRightInset
    }

    FlyViewTopRightPanel {
        id:                     topRightPanel
        anchors.top:            parent.top
        anchors.right:          parent.right
        maximumHeight:          parent.height - (bottomRightRowLayout.height + _margins * 4)

        property real topEdgeRightInset:    height + _layoutMargin
        property real rightEdgeTopInset:    width + _layoutMargin
        property real rightEdgeCenterInset: rightEdgeTopInset
    }

    FlyViewTopRightColumnLayout {
        id:                 topRightColumnLayout
        anchors.top:        parent.top
        anchors.right:      parent.right
        spacing:            _layoutSpacing
        visible:           !topRightPanel.visible

        property real topEdgeRightInset:    childrenRect.height + _layoutMargin
        property real rightEdgeTopInset:    width + _layoutMargin
        property real rightEdgeCenterInset: rightEdgeTopInset
    }

    FlyViewBottomRightRowLayout {
        id:                 bottomRightRowLayout
        anchors.bottom:     parent.bottom
        anchors.right:      parent.right
        spacing:            _layoutSpacing

        property real bottomEdgeRightInset:     height + _layoutMargin
        property real bottomEdgeCenterInset:    bottomEdgeRightInset
        property real rightEdgeBottomInset:     width + _layoutMargin
    }

    FlyViewMissionCompleteDialog {
        missionController:      _missionController
        geoFenceController:     _geoFenceController
        rallyPointController:   _rallyPointController
    }

    //-- Virtual Joystick
    Loader {
        id:                         virtualJoystickMultiTouch
        z:                          QGroundControl.zOrderTopMost + 1
        anchors.right:              parent.right
        anchors.rightMargin:        anchors.leftMargin
        height:                     Math.min(parent.height * 0.25, ScreenTools.defaultFontPixelWidth * 16)
        visible:                    _virtualJoystickEnabled && !QGroundControl.videoManager.fullScreen && !(_activeVehicle ? _activeVehicle.usingHighLatencyLink : false)
        anchors.bottom:             parent.bottom
        anchors.bottomMargin:       bottomLoaderMargin
        anchors.left:               parent.left
        anchors.leftMargin:         ( y > toolStrip.y + toolStrip.height ? toolStrip.width / 2 : toolStrip.width * 1.05 + toolStrip.x)
        source:                     "qrc:/qml/QGroundControl/FlyView/VirtualJoystick.qml"
        active:                     _virtualJoystickEnabled && !(_activeVehicle ? _activeVehicle.usingHighLatencyLink : false)

        property real bottomEdgeLeftInset:     parent.height-y
        property bool autoCenterThrottle:      QGroundControl.settingsManager.appSettings.virtualJoystickAutoCenterThrottle.rawValue
        property bool leftHandedMode:          QGroundControl.settingsManager.appSettings.virtualJoystickLeftHandedMode.rawValue
        property bool _virtualJoystickEnabled: QGroundControl.settingsManager.appSettings.virtualJoystick.rawValue
        property real bottomEdgeRightInset:    parent.height-y
        property var  _pipViewMargin:          _pipView.visible ? parentToolInsets.bottomEdgeLeftInset + ScreenTools.defaultFontPixelHeight * 2 :
                                               bottomRightRowLayout.height + ScreenTools.defaultFontPixelHeight * 1.5

        property var  bottomLoaderMargin:      _pipViewMargin >= parent.height / 2 ? parent.height / 2 : _pipViewMargin

        // Width is difficult to access directly hence this hack which may not work in all circumstances
        property real leftEdgeBottomInset:  visible ? bottomEdgeLeftInset + width/18 - ScreenTools.defaultFontPixelHeight*2 : 0
        property real rightEdgeBottomInset: visible ? bottomEdgeRightInset + width/18 - ScreenTools.defaultFontPixelHeight*2 : 0
        property real rootWidth:            _root.width
        property var  itemX:                virtualJoystickMultiTouch.x   // real X on screen

        onRootWidthChanged: virtualJoystickMultiTouch.status == Loader.Ready && visible ? virtualJoystickMultiTouch.item.uiTotalWidth = rootWidth : undefined
        onItemXChanged:     virtualJoystickMultiTouch.status == Loader.Ready && visible ? virtualJoystickMultiTouch.item.uiRealX = itemX : undefined

        //Loader status logic
        onLoaded: {
            if (virtualJoystickMultiTouch.visible) {
                virtualJoystickMultiTouch.item.calibration = true
                virtualJoystickMultiTouch.item.uiTotalWidth = rootWidth
                virtualJoystickMultiTouch.item.uiRealX = itemX
            } else {
                virtualJoystickMultiTouch.item.calibration = false
            }
        }
    }

    FlyViewToolStrip {
        id:                     toolStrip
        anchors.left:           parent.left
        anchors.top:            parent.top
        engagementController:    _root.engagementController
        cameraMaximized:         _root.cameraMaximized
        standoffController:      _root.standoffController
        z:                      QGroundControl.zOrderWidgets
        maxHeight:              parent.height - y - parentToolInsets.bottomEdgeLeftInset - _toolsMargin
        visible:                !QGroundControl.videoManager.fullScreen

        onDisplayPreFlightChecklist: {
            if (!preFlightChecklistLoader.active) {
                preFlightChecklistLoader.active = true
            }
            preFlightChecklistLoader.item.open()
        }

        // STRATUM: enter Area-Of-Operations edit mode on the single Fly map. The
        // standoff panel is closed first so its crosshair pick mode and the AOP
        // polygon editor never contend for the same map clicks.
        onDefineAOP:  startAOP()

        // STRATUM: toggle the standoff entry panel beside the strip.
        onSetStandoff: toggleStandoff()

        property real topEdgeLeftInset:     visible ? y + height : 0
        property real leftEdgeTopInset:     visible ? x + width : 0
        property real leftEdgeCenterInset:  leftEdgeTopInset
    }

    VehicleWarnings {
        anchors.centerIn:   parent
        z:                  QGroundControl.zOrderTopMost
    }

    // STRATUM: Standoff entry panel. Opened by the crimson "Set Standoff" strip
    // command; sits beside the strip (top-aligned with the button) rather than over
    // the map centre. The operator either types the target lat/lon or clicks the map
    // while the crosshair pick cursor is active (FlyViewMap._standoffPickMode) - both
    // paths fill the same fields, and the last writer wins. Commit goes through
    // StandoffController.beginStandoff, which sends the web-UI standoff contract
    // (cmd 31010 params + 31011 activate) to the bridge companion computer.
    Rectangle {
        id:                 standoffPanel
        visible:            false
        z:                  QGroundControl.zOrderTopMost
        anchors.left:       toolStrip.right
        anchors.leftMargin: _toolsMargin
        anchors.top:        toolStrip.top
        radius:             _margins
        color:              qgcPal.window
        border.color:       "#D11A35"
        border.width:       1
        width:              standoffPanelGrid.width + _toolsMargin * 4
        height:             standoffPanelGrid.height + _toolsMargin * 4

        property bool _coordValid: {
            var lat = parseFloat(standoffLatField.text)
            var lon = parseFloat(standoffLonField.text)
            return !isNaN(lat) && !isNaN(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180
        }

        // STRATUM: set when the last commit was rejected for being outside the AOP.
        property bool _aopReject: false

        function open() {
            visible = true
            if (mapControl) {
                mapControl.startStandoffPick()
                _updatePending()   // fields may still hold a valid target from last use
            }
        }
        function close() {
            visible = false
            if (mapControl) {
                mapControl.stopStandoffPick()
            }
        }
        function toggle() {
            if (visible) {
                close()
            } else {
                open()
            }
        }

        // STRATUM: single writer of the map's interim (blue) target marker. Runs on
        // every lat/lon edit - map picks land here too, since a pick writes the same
        // fields. An invalid pair clears the marker rather than leaving it stale.
        function _updatePending() {
            // A fresh target edit clears any prior AOP rejection.
            _aopReject = false
            if (!mapControl) {
                return
            }
            if (_coordValid) {
                mapControl.setStandoffPendingCoordinate(QtPositioning.coordinate(parseFloat(standoffLatField.text),
                                                                                 parseFloat(standoffLonField.text)))
            } else {
                mapControl.setStandoffPendingCoordinate(QtPositioning.coordinate())
            }
        }

        // Crosshair map pick -> fields.
        Connections {
            target: mapControl
            function onStandoffTargetPicked(coordinate) {
                standoffLatField.text = coordinate.latitude.toFixed(7)
                standoffLonField.text = coordinate.longitude.toFixed(7)
            }
        }

        DeadMouseArea { anchors.fill: parent }

        GridLayout {
            id:                 standoffPanelGrid
            anchors.centerIn:   parent
            columns:            2
            columnSpacing:      ScreenTools.defaultFontPixelWidth
            rowSpacing:         ScreenTools.defaultFontPixelHeight / 2

            QGCLabel {
                Layout.columnSpan:  2
                text:               qsTr("Set Standoff")
                font.bold:          true
            }

            QGCLabel {
                Layout.columnSpan:   2
                Layout.maximumWidth: ScreenTools.defaultFontPixelWidth * 34
                wrapMode:            Text.WordWrap
                text:                qsTr("Enter the target position, or click the map with the crosshair cursor.")
            }

            QGCLabel { text: qsTr("Latitude") }
            QGCTextField {
                id:                    standoffLatField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                unitsLabel:            qsTr("deg")
                showUnits:             true
                inputMethodHints:      Qt.ImhFormattedNumbersOnly
                onTextChanged:         standoffPanel._updatePending()
            }

            QGCLabel { text: qsTr("Longitude") }
            QGCTextField {
                id:                    standoffLonField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                unitsLabel:            qsTr("deg")
                showUnits:             true
                inputMethodHints:      Qt.ImhFormattedNumbersOnly
                onTextChanged:         standoffPanel._updatePending()
            }

            // STRATUM: raw metres / km-h to match the web UI standoff contract exactly
            // (the values are sent verbatim to the bridge in cmd 31010).
            QGCLabel { text: qsTr("Distance") }
            QGCTextField {
                id:                    standoffDistanceField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                text:                  "300"
                unitsLabel:            qsTr("m")
                showUnits:             true
                inputMethodHints:      Qt.ImhFormattedNumbersOnly
            }

            QGCLabel { text: qsTr("Height AGL") }
            QGCTextField {
                id:                    standoffHeightField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                text:                  "150"
                unitsLabel:            qsTr("m")
                showUnits:             true
                inputMethodHints:      Qt.ImhFormattedNumbersOnly
            }

            QGCLabel { text: qsTr("Speed") }
            QGCTextField {
                id:                    standoffSpeedField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                text:                  "30"
                unitsLabel:            qsTr("km/h")
                showUnits:             true
                inputMethodHints:      Qt.ImhFormattedNumbersOnly
            }

            QGCLabel { text: qsTr("Direction") }
            QGCComboBox {
                id:                    standoffDirectionCombo
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                currentIndex:          0
                // Index maps directly to the web UI direction value (0=N,1=E,2=S,3=W).
                model:                 [qsTr("North ↑"), qsTr("East →"), qsTr("South ↓"), qsTr("West ←")]
            }

            // STRATUM: the command needs a vehicle; surface that instead of failing
            // silently inside beginStandoff.
            QGCLabel {
                Layout.columnSpan:  2
                visible:            !_activeVehicle
                color:              "#F2C200"
                text:               qsTr("No vehicle connected.")
            }

            // STRATUM: AOP rejection — the standoff target must lie inside the defined
            // Area of Operations (mirrors the web UI's isInsideAOP check).
            QGCLabel {
                Layout.columnSpan:   2
                Layout.maximumWidth: ScreenTools.defaultFontPixelWidth * 34
                visible:             standoffPanel._aopReject
                color:               "#EF5350"
                wrapMode:            Text.WordWrap
                text:                qsTr("Target is outside the defined AOP boundary — standoff rejected.")
            }

            RowLayout {
                Layout.columnSpan:  2
                Layout.alignment:   Qt.AlignRight
                spacing:            _toolsMargin

                QGCButton {
                    text:       qsTr("Cancel")
                    onClicked:  standoffPanel.close()
                }

                QGCButton {
                    text:       qsTr("Set Standoff")
                    primary:    true
                    enabled:    standoffPanel._coordValid && _activeVehicle !== null
                    onClicked: {
                        var distance  = parseFloat(standoffDistanceField.text)
                        var height    = parseFloat(standoffHeightField.text)
                        var speed     = parseFloat(standoffSpeedField.text)
                        var direction = standoffDirectionCombo.currentIndex   // 0=N,1=E,2=S,3=W
                        if (isNaN(distance) || distance <= 0) { distance = 0 }
                        if (isNaN(height))                    { height   = 0 }
                        if (isNaN(speed)   || speed <= 0)     { speed    = 0 }
                        var target = QtPositioning.coordinate(parseFloat(standoffLatField.text),
                                                              parseFloat(standoffLonField.text))
                        // AOP enforcement: reject a target outside the defined AOP boundary.
                        if (mapControl && !mapControl.isCoordinateInsideAOP(target)) {
                            standoffPanel._aopReject = true
                            return
                        }
                        standoffPanel._aopReject = false
                        // STRATUM: beginStandoff returns false when Vehicle::guidedModeStandoff
                        // rejects the request (e.g. hold point beyond maxGoToLocationDistance).
                        // Leave the panel open so the operator can adjust; the rejection toast
                        // is emitted from Vehicle.cc.
                        if (mapControl.standoffCmdController.beginStandoff(distance, height, speed, direction, target)) {
                            standoffPanel.close()
                        }
                    }
                }
            }
        }
    }

    MapScale {
        id:                 mapScale
        anchors.left:       toolStrip.right
        anchors.leftMargin: _toolsMargin
        anchors.top:        parent.top
        mapControl:         _mapControl
        autoHide:           true
        visible:            !ScreenTools.isTinyScreen && QGroundControl.corePlugin.options.flyView.showMapScale && QGCViewer3DManager.displayMode !== QGCViewer3DManager.View3D && mapControl.pipState.state === mapControl.pipState.fullState

        property real topEdgeCenterInset: visible ? y + height : 0
    }

    Loader {
        id: preFlightChecklistLoader
        sourceComponent: preFlightChecklistPopup
        active: false
    }

    Component {
        id: preFlightChecklistPopup
        FlyViewPreFlightChecklistPopup {
        }
    }
}
